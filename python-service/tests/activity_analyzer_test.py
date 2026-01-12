import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def activity_analyzer():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def sample_activities():
    """Provide a list of sample activities with ISO timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc)
    return [
        {"action": "login", "timestamp": (base + timedelta(minutes=0)).isoformat()},
        {"action": "view", "timestamp": (base + timedelta(minutes=5)).isoformat()},
        {"action": "click", "timestamp": (base + timedelta(minutes=10)).isoformat()},
        {"action": "view", "timestamp": (base + timedelta(minutes=15)).isoformat()},
        {"action": "logout", "timestamp": (base + timedelta(minutes=20)).isoformat()},
    ]


# -------------------- ActivityPattern tests --------------------


def test_activitypattern_init_and_attributes():
    """Test ActivityPattern initialization and attribute assignment."""
    pattern = ActivityPattern("type1", "desc", 0.95)
    assert pattern.pattern_type == "type1"
    assert pattern.description == "desc"
    assert pattern.confidence == pytest.approx(0.95)


def test_activitypattern_to_dict():
    """Test ActivityPattern.to_dict returns correct dictionary."""
    pattern = ActivityPattern("peak_hours", "High activity", 0.85)
    result = pattern.to_dict()
    assert result["pattern_type"] == "peak_hours"
    assert result["description"] == "High activity"
    assert result["confidence"] == pytest.approx(0.85)


# -------------------- ActivityAnalyzer.__init__ tests --------------------


def test_activityanalyzer_init_defaults(activity_analyzer):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert activity_analyzer.peak_hour_threshold == pytest.approx(0.2)
    assert activity_analyzer.anomaly_threshold == pytest.approx(3.0)


# -------------------- _parse_timestamp tests --------------------


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer):
    """Test _parse_timestamp returns datetime unchanged when given datetime."""
    ts = datetime(2024, 1, 1, 12, 0, 0)
    parsed = activity_analyzer._parse_timestamp(ts)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer):
    """Test _parse_timestamp parses ISO 8601 string with Z suffix."""
    ts_str = "2024-01-01T12:00:00Z"
    parsed = activity_analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.month == 1
    assert parsed.day == 1
    assert parsed.hour == 12


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer):
    """Test _parse_timestamp returns None for invalid string."""
    parsed = activity_analyzer._parse_timestamp("not-a-timestamp")
    assert parsed is None


def test_activityanalyzer_parse_timestamp_none(activity_analyzer):
    """Test _parse_timestamp returns None for None input."""
    parsed = activity_analyzer._parse_timestamp(None)
    assert parsed is None


# -------------------- _detect_peak_hours tests --------------------


def test_activityanalyzer_detect_peak_hours_basic(activity_analyzer):
    """Test _detect_peak_hours detects peak hours above threshold."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 8 activities at 10:00, 2 at 11:00 -> 10:00 is 80% > 0.2
    for i in range(8):
        activities.append({"action": "a", "timestamp": (base + timedelta(minutes=i)).isoformat()})
    for i in range(2):
        activities.append({"action": "b", "timestamp": (base + timedelta(hours=1, minutes=i)).isoformat()})

    patterns = activity_analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "peak_hours"
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_no_peak(activity_analyzer):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    # 1 activity per hour for 5 hours -> each 20%, equal to threshold, not greater
    for h in range(5):
        activities.append({"action": "a", "timestamp": (base + timedelta(hours=h)).isoformat()})

    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_empty(activity_analyzer):
    """Test _detect_peak_hours returns empty list for no valid timestamps."""
    patterns = activity_analyzer._detect_peak_hours([])
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_invalid_timestamps(activity_analyzer):
    """Test _detect_peak_hours ignores invalid timestamps and may return empty."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "b", "timestamp": None},
    ]
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


# -------------------- _detect_action_sequences tests --------------------


def test_activityanalyzer_detect_action_sequences_min_length(activity_analyzer):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T00:00:00Z"},
        {"action": "b", "timestamp": "2024-01-01T00:01:00Z"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_common_sequences(activity_analyzer):
    """Test _detect_action_sequences detects sequences occurring at least twice."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T00:00:00Z"},
        {"action": "b", "timestamp": "2024-01-01T00:01:00Z"},
        {"action": "c", "timestamp": "2024-01-01T00:02:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:03:00Z"},
        {"action": "b", "timestamp": "2024-01-01T00:04:00Z"},
        {"action": "c", "timestamp": "2024-01-01T00:05:00Z"},
        {"action": "d", "timestamp": "2024-01-01T00:06:00Z"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    # sequence (a,b,c) appears twice
    assert any("Common sequence: a → b → c (occurred 2 times)" in p.description for p in patterns)
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_uses_default_action(activity_analyzer):
    """Test _detect_action_sequences uses empty string when action key missing."""
    activities = [
        {"timestamp": "2024-01-01T00:00:00Z"},
        {"action": "b", "timestamp": "2024-01-01T00:01:00Z"},
        {"action": "c", "timestamp": "2024-01-01T00:02:00Z"},
        {"timestamp": "2024-01-01T00:03:00Z"},
        {"action": "b", "timestamp": "2024-01-01T00:04:00Z"},
        {"action": "c", "timestamp": "2024-01-01T00:05:00Z"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    # sequence ("", "b", "c") appears twice
    assert any("Common sequence:  → b → c (occurred 2 times)" in p.description for p in patterns)


# -------------------- _detect_regularity tests --------------------


def test_activityanalyzer_detect_regularity_not_enough_activities(activity_analyzer):
    """Test _detect_regularity returns empty when fewer than 5 activities."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T00:00:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:01:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:02:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:03:00Z"},
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer):
    """Test _detect_regularity detects highly regular intervals (low CV)."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    # 6 activities exactly 60 seconds apart
    for i in range(6):
        activities.append({"action": "a", "timestamp": (base + timedelta(seconds=60 * i)).isoformat()})
    patterns = activity_analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer):
    """Test _detect_regularity returns empty when coefficient of variation is high."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    # Intervals: 10s, 100s, 5s, 200s, 50s -> high variation
    offsets = [0, 10, 110, 115, 315, 365]
    for off in offsets:
        activities.append({"action": "a", "timestamp": (base + timedelta(seconds=off)).isoformat()})
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_ignores_invalid_timestamps(activity_analyzer):
    """Test _detect_regularity ignores invalid timestamps and may return empty."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "a", "timestamp": None},
        {"action": "a", "timestamp": "2024-01-01T00:00:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:01:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:02:00Z"},
    ]
    # Only 3 valid timestamps -> should return empty
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


# -------------------- analyze_patterns tests --------------------


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer):
    """Test analyze_patterns returns empty list when no activities."""
    patterns = activity_analyzer.analyze_patterns([])
    assert patterns == []


def test_activityanalyzer_analyze_patterns_integration(activity_analyzer):
    """Test analyze_patterns aggregates patterns from all detectors."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # Create enough data to trigger peak_hours, action_sequence, and regularity
    for i in range(10):
        activities.append(
            {"action": "a" if i % 3 == 0 else "b" if i % 3 == 1 else "c",
             "timestamp": (base + timedelta(minutes=5 * i)).isoformat()}
        )
    patterns = activity_analyzer.analyze_patterns(activities)
    # We expect at least one pattern from each detector, but exact count may vary
    types = {p.pattern_type for p in patterns}
    assert "peak_hours" in types
    assert "action_sequence" in types
    assert "regularity" in types


def test_activityanalyzer_analyze_patterns_uses_internal_methods(activity_analyzer):
    """Test analyze_patterns calls internal detection methods."""
    activities = [{"action": "a", "timestamp": "2024-01-01T00:00:00Z"}] * 6
    with patch.object(activity_analyzer, "_detect_peak_hours", return_value=[]) as mock_peak, \
         patch.object(activity_analyzer, "_detect_action_sequences", return_value=[]) as mock_seq, \
         patch.object(activity_analyzer, "_detect_regularity", return_value=[]) as mock_reg:
        patterns = activity_analyzer.analyze_patterns(activities)
        assert patterns == []
        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)


# -------------------- get_user_score tests --------------------


def test_activityanalyzer_get_user_score_empty(activity_analyzer):
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer):
    """Test get_user_score computes score based on diversity, frequency, and volume."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 10 actions over 2 days, 3 unique actions
    for i in range(10):
        ts = base + timedelta(hours=12 * i)  # spans multiple days
        activities.append({"action": ["a", "b", "c"][i % 3], "timestamp": ts.isoformat()})

    score = activity_analyzer.get_user_score(activities)

    # Manually compute expected score according to implementation
    total_actions = 10
    unique_actions = 3
    first_ts = activities[0]["timestamp"]
    last_ts = activities[-1]["timestamp"]
    first_dt = datetime.fromisoformat(first_ts)
    last_dt = datetime.fromisoformat(last_ts)
    days_active = max((last_dt - first_dt).days, 1)
    actions_per_day = total_actions / days_active
    diversity_score = unique_actions / max(total_actions, 1)
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100
    expected = round(expected, 2)

    assert score == pytest.approx(expected)


def test_activityanalyzer_get_user_score_no_timestamps(activity_analyzer):
    """Test get_user_score when timestamps are missing or invalid uses total_actions as actions_per_day."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "b", "timestamp": None},
        {"action": "c"},  # no timestamp key
    ]
    score = activity_analyzer.get_user_score(activities)

    total_actions = 3
    unique_actions = 3  # all different
    actions_per_day = total_actions
    diversity_score = unique_actions / max(total_actions, 1)
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100
    expected = round(expected, 2)

    assert score == pytest.approx(expected)


def test_activityanalyzer_get_user_score_duplicate_actions_logic(activity_analyzer):
    """Test get_user_score unique action counting logic with repeated actions."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        {"action": "a", "timestamp": (base + timedelta(minutes=0)).isoformat()},
        {"action": "b", "timestamp": (base + timedelta(minutes=1)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(minutes=2)).isoformat()},
        {"action": "c", "timestamp": (base + timedelta(minutes=3)).isoformat()},
    ]
    # According to implementation, unique_actions will be 3 (a, b, c)
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)


# -------------------- detect_anomalies tests --------------------


def test_activityanalyzer_detect_anomalies_not_enough_activities(activity_analyzer):
    """Test detect_anomalies returns empty when fewer than 5 activities."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T00:00:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:01:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:02:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:03:00Z"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_basic_detection(activity_analyzer):
    """Test detect_anomalies flags intervals with z-score above threshold."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    # Create mostly regular intervals of 60s, with one very large gap
    timestamps = [
        base,
        base + timedelta(seconds=60),
        base + timedelta(seconds=120),
        base + timedelta(seconds=180),
        base + timedelta(seconds=1800),  # big jump -> anomaly
        base + timedelta(seconds=1860),
    ]
    activities = [{"action": "a", "timestamp": ts.isoformat()} for ts in timestamps]

    anomalies = activity_analyzer.detect_anomalies(activities)
    # There should be at least one anomaly for action 'a'
    assert len(anomalies) >= 1
    assert all(a["action"] == "a" for a in anomalies)
    for a in anomalies:
        assert isinstance(a["z_score"], float)
        assert a["z_score"] > activity_analyzer.anomaly_threshold
        assert "Unusual interval" in a["reason"]


def test_activityanalyzer_detect_anomalies_multiple_actions(activity_analyzer):
    """Test detect_anomalies processes each action separately."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    # Action a: regular
    for i in range(5):
        activities.append({"action": "a", "timestamp": (base + timedelta(seconds=60 * i)).isoformat()})
    # Action b: irregular with one big gap
    for i, off in enumerate([0, 60, 1200, 1260, 1320]):
        activities.append({"action": "b", "timestamp": (base + timedelta(seconds=off)).isoformat()})

    anomalies = activity_analyzer.detect_anomalies(activities)
    # Expect anomalies only for action 'b'
    assert all(a["action"] == "b" for a in anomalies)


def test_activityanalyzer_detect_anomalies_ignores_invalid_timestamps(activity_analyzer):
    """Test detect_anomalies ignores activities with invalid timestamps."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "a", "timestamp": None},
        {"action": "a", "timestamp": (base + timedelta(seconds=0)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(seconds=60)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(seconds=120)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(seconds=1800)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(seconds=1860)).isoformat()},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert len(anomalies) >= 1


def test_activityanalyzer_detect_anomalies_no_intervals(activity_analyzer):
    """Test detect_anomalies handles case where all timestamps for an action are identical."""
    ts = "2024-01-01T00:00:00Z"
    activities = [{"action": "a", "timestamp": ts} for _ in range(6)]
    anomalies = activity_analyzer.detect_anomalies(activities)
    # intervals will all be 0, std_dev 0 -> no anomalies
    assert anomalies == []


# -------------------- detect_anomalies exception handling via mocking --------------------


def test_activityanalyzer_detect_anomalies_parse_exception_handling(activity_analyzer, monkeypatch):
    """Test detect_anomalies handles exceptions from _parse_timestamp gracefully."""
    def bad_parse(_):
        raise ValueError("parse error")

    monkeypatch.setattr(activity_analyzer, "_parse_timestamp", bad_parse)
    activities = [
        {"action": "a", "timestamp": "2024-01-01T00:00:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:01:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:02:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:03:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:04:00Z"},
    ]
    # Since our replacement raises, this will propagate; test that exception is raised
    with pytest.raises(ValueError):
        activity_analyzer.detect_anomalies(activities)


# -------------------- get_user_score exception handling via mocking --------------------


def test_activityanalyzer_get_user_score_parse_exception(activity_analyzer, monkeypatch):
    """Test get_user_score propagates exceptions from _parse_timestamp."""
    def bad_parse(_):
        raise RuntimeError("parse error")

    monkeypatch.setattr(activity_analyzer, "_parse_timestamp", bad_parse)
    activities = [
        {"action": "a", "timestamp": "2024-01-01T00:00:00Z"},
        {"action": "b", "timestamp": "2024-01-02T00:00:00Z"},
    ]
    with pytest.raises(RuntimeError):
        activity_analyzer.get_user_score(activities)


# -------------------- analyze_patterns exception handling via mocking --------------------


def test_activityanalyzer_analyze_patterns_internal_exception(activity_analyzer):
    """Test analyze_patterns propagates exceptions from internal detectors."""
    activities = [{"action": "a", "timestamp": "2024-01-01T00:00:00Z"}] * 6
    with patch.object(activity_analyzer, "_detect_peak_hours", side_effect=Exception("boom")):
        with pytest.raises(Exception):
            activity_analyzer.analyze_patterns(activities)


# -------------------- _detect_peak_hours exception handling via mocking --------------------


def test_activityanalyzer_detect_peak_hours_parse_exception(activity_analyzer, monkeypatch):
    """Test _detect_peak_hours propagates exceptions from _parse_timestamp."""
    def bad_parse(_):
        raise RuntimeError("parse error")

    monkeypatch.setattr(activity_analyzer, "_parse_timestamp", bad_parse)
    activities = [{"action": "a", "timestamp": "2024-01-01T00:00:00Z"}]
    with pytest.raises(RuntimeError):
        activity_analyzer._detect_peak_hours(activities)