import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def activity_analyzer():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def sample_activities():
    """Provide a list of sample activities with timestamps and actions."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    return [
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "login"},
        {"timestamp": (base + timedelta(minutes=5)).isoformat(), "action": "view"},
        {"timestamp": (base + timedelta(minutes=10)).isoformat(), "action": "click"},
        {"timestamp": (base + timedelta(minutes=15)).isoformat(), "action": "view"},
        {"timestamp": (base + timedelta(minutes=20)).isoformat(), "action": "logout"},
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
    assert result == {
        "pattern_type": "peak_hours",
        "description": "High activity",
        "confidence": pytest.approx(0.85),
    }


# -------------------- ActivityAnalyzer.__init__ tests --------------------


def test_activityanalyzer_init_defaults(activity_analyzer):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert activity_analyzer.peak_hour_threshold == pytest.approx(0.2)
    assert activity_analyzer.anomaly_threshold == pytest.approx(3.0)


# -------------------- _parse_timestamp tests --------------------


def test_activityanalyzer_parse_timestamp_with_datetime(activity_analyzer):
    """Test _parse_timestamp returns datetime unchanged when given datetime."""
    ts = datetime(2024, 1, 1, 12, 0, 0)
    parsed = activity_analyzer._parse_timestamp(ts)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_with_iso_string(activity_analyzer):
    """Test _parse_timestamp parses ISO formatted string."""
    ts_str = "2024-01-01T12:00:00"
    parsed = activity_analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed == datetime.fromisoformat(ts_str)


def test_activityanalyzer_parse_timestamp_with_z_suffix(activity_analyzer):
    """Test _parse_timestamp parses ISO string with Z suffix as UTC."""
    ts_str = "2024-01-01T12:00:00Z"
    parsed = activity_analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    # fromisoformat with +00:00 will create aware datetime; just check components
    assert parsed.year == 2024
    assert parsed.month == 1
    assert parsed.day == 1
    assert parsed.hour == 12
    assert parsed.minute == 0
    assert parsed.second == 0


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer):
    """Test _parse_timestamp returns None for invalid string."""
    parsed = activity_analyzer._parse_timestamp("not-a-timestamp")
    assert parsed is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer):
    """Test _parse_timestamp returns None for unsupported type."""
    parsed = activity_analyzer._parse_timestamp(12345)
    assert parsed is None


# -------------------- analyze_patterns tests --------------------


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer):
    """Test analyze_patterns returns empty list when no activities."""
    result = activity_analyzer.analyze_patterns([])
    assert result == []


def test_activityanalyzer_analyze_patterns_calls_internal_methods(activity_analyzer, sample_activities):
    """Test analyze_patterns calls internal detection methods and aggregates results."""
    with patch.object(activity_analyzer, "_detect_peak_hours", return_value=[ActivityPattern("peak", "p", 0.1)]) as mock_peak, \
         patch.object(activity_analyzer, "_detect_action_sequences", return_value=[ActivityPattern("seq", "s", 0.2)]) as mock_seq, \
         patch.object(activity_analyzer, "_detect_regularity", return_value=[ActivityPattern("reg", "r", 0.3)]) as mock_reg:

        patterns = activity_analyzer.analyze_patterns(sample_activities)

        mock_peak.assert_called_once_with(sample_activities)
        mock_seq.assert_called_once_with(sample_activities)
        mock_reg.assert_called_once_with(sample_activities)

        assert len(patterns) == 3
        assert [p.pattern_type for p in patterns] == ["peak", "seq", "reg"]


# -------------------- get_user_score tests --------------------


def test_activityanalyzer_get_user_score_empty(activity_analyzer):
    """Test get_user_score returns 0.0 when no activities."""
    score = activity_analyzer.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer):
    """Test get_user_score computes score based on diversity, frequency, and volume."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(days=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(days=1)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(days=2)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(days=3)).isoformat(), "action": "c"},
    ]
    score = activity_analyzer.get_user_score(activities)

    # Manually compute expected according to implementation
    total_actions = 4
    # unique_actions logic: first occurrence only, using index-based check
    # actions: ['a','b','a','c'] -> unique: 'a','b','c' => 3
    diversity_score = 3 / 4
    days_active = max((activity_analyzer._parse_timestamp(activities[-1]["timestamp"]) -
                       activity_analyzer._parse_timestamp(activities[0]["timestamp"])).days, 1)
    actions_per_day = total_actions / days_active
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100
    expected = round(expected, 2)

    assert score == pytest.approx(expected)


def test_activityanalyzer_get_user_score_no_valid_timestamps(activity_analyzer):
    """Test get_user_score when timestamps cannot be parsed (uses total_actions as actions_per_day)."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": "also-invalid", "action": "b"},
        {"timestamp": None, "action": "c"},
    ]
    score = activity_analyzer.get_user_score(activities)

    total_actions = 3
    # unique actions: 'a','b','c'
    diversity_score = 3 / 3
    actions_per_day = total_actions  # because first_ts and last_ts are None
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100
    expected = round(expected, 2)

    assert score == pytest.approx(expected)


def test_activityanalyzer_get_user_score_single_activity(activity_analyzer):
    """Test get_user_score with a single activity (days_active should be 1)."""
    ts = datetime(2024, 1, 1, 10, 0, 0).isoformat()
    activities = [{"timestamp": ts, "action": "only"}]
    score = activity_analyzer.get_user_score(activities)

    total_actions = 1
    diversity_score = 1 / 1
    actions_per_day = 1 / 1
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100
    expected = round(expected, 2)

    assert score == pytest.approx(expected)


# -------------------- detect_anomalies tests --------------------


def test_activityanalyzer_detect_anomalies_too_few_activities(activity_analyzer):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_no_anomalies(activity_analyzer):
    """Test detect_anomalies returns empty list when intervals are regular."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Same action every 10 minutes, 6 times
    activities = [
        {"timestamp": (base + timedelta(minutes=10 * i)).isoformat(), "action": "ping"}
        for i in range(6)
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_with_anomaly(activity_analyzer):
    """Test detect_anomalies detects an interval with high z-score."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Intervals: 10, 10, 10, 1000 seconds to create an anomaly
    timestamps = [
        base,
        base + timedelta(seconds=10),
        base + timedelta(seconds=20),
        base + timedelta(seconds=30),
        base + timedelta(seconds=1030),
    ]
    activities = [{"timestamp": ts.isoformat(), "action": "ping"} for ts in timestamps]

    anomalies = activity_analyzer.detect_anomalies(activities)

    assert len(anomalies) >= 1
    anomaly = anomalies[-1]
    assert anomaly["action"] == "ping"
    assert "timestamp" in anomaly
    assert "z_score" in anomaly
    assert isinstance(anomaly["z_score"], float)
    assert "Unusual interval" in anomaly["reason"]


def test_activityanalyzer_detect_anomalies_ignores_actions_with_few_timestamps(activity_analyzer):
    """Test detect_anomalies ignores actions that occur fewer than 3 times."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"} for i in range(3)
    ] + [
        {"timestamp": (base + timedelta(minutes=100 + i)).isoformat(), "action": "b"} for i in range(2)
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    # 'b' has only 2 timestamps, so should be ignored; 'a' is regular
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_invalid_timestamps(activity_analyzer):
    """Test detect_anomalies handles invalid timestamps gracefully."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "a"},
        {"timestamp": "2024-01-01T10:00:00", "action": "a"},
        {"timestamp": "2024-01-01T10:10:00", "action": "a"},
        {"timestamp": "2024-01-01T10:20:00", "action": "a"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    # Should not raise and likely no anomalies for regular intervals
    assert isinstance(anomalies, list)


# -------------------- _detect_peak_hours tests --------------------


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(activity_analyzer):
    """Test _detect_peak_hours returns empty when no valid timestamps."""
    activities = [{"timestamp": "invalid", "action": "a"} for _ in range(5)]
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_identifies_peak(activity_analyzer):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 8 activities at 10:00
    for i in range(8):
        activities.append({"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"})
    # 2 activities at 11:00
    for i in range(2):
        activities.append({"timestamp": (base + timedelta(hours=1, minutes=i)).isoformat(), "action": "b"})

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
    # 5 activities spread across 5 different hours -> each 0.2, equals threshold but not greater
    for i in range(5):
        activities.append({"timestamp": (base + timedelta(hours=i)).isoformat(), "action": "a"})

    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


# -------------------- _detect_action_sequences tests --------------------


def test_activityanalyzer_detect_action_sequences_too_few(activity_analyzer):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"},
        {"timestamp": datetime.now().isoformat(), "action": "b"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_common_sequences(activity_analyzer):
    """Test _detect_action_sequences identifies common 3-action sequences."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": act}
        for i, act in enumerate([
            "login", "view", "click",   # seq1
            "logout",
            "login", "view", "click",   # seq1 again
            "login", "view", "scroll",  # seq2
            "login", "view", "click",   # seq1 third time
        ])
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)

    # sequence ('login','view','click') should appear at least 3 times
    assert any("login → view → click" in p.description for p in patterns)
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_requires_min_count(activity_analyzer):
    """Test _detect_action_sequences only returns sequences occurring at least twice."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Only one occurrence of each sequence
    actions = ["a", "b", "c", "d", "e"]
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": act}
        for i, act in enumerate(actions)
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert patterns == []


# -------------------- _detect_regularity tests --------------------


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer):
    """Test _detect_regularity returns empty when fewer than 5 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"}
        for _ in range(4)
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_not_enough_valid_timestamps(activity_analyzer):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "a"},
        {"timestamp": "2024-01-01T10:00:00", "action": "a"},
        {"timestamp": "2024-01-01T10:10:00", "action": "a"},
        {"timestamp": "2024-01-01T10:20:00", "action": "a"},
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer):
    """Test _detect_regularity detects highly regular intervals (low CV)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Regular 10-minute intervals
    activities = [
        {"timestamp": (base + timedelta(minutes=10 * i)).isoformat(), "action": "a"}
        for i in range(6)
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer):
    """Test _detect_regularity returns empty when coefficient of variation is high."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Irregular intervals
    offsets = [0, 1, 3, 10, 30, 60]  # minutes
    activities = [
        {"timestamp": (base + timedelta(minutes=o)).isoformat(), "action": "a"}
        for o in offsets
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


# -------------------- analyze_patterns integration behavior --------------------


def test_activityanalyzer_analyze_patterns_integration(activity_analyzer):
    """Test analyze_patterns returns combined patterns from all detectors."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # Create enough data to trigger all detectors
    for i in range(10):
        activities.append({"timestamp": (base + timedelta(minutes=10 * i)).isoformat(), "action": "a"})
    for i in range(10, 20):
        activities.append({"timestamp": (base + timedelta(hours=1, minutes=5 * i)).isoformat(), "action": "b"})

    patterns = activity_analyzer.analyze_patterns(activities)
    assert isinstance(patterns, list)
    assert all(isinstance(p, ActivityPattern) for p in patterns)


# -------------------- exception handling / robustness tests --------------------


def test_activityanalyzer_detect_anomalies_handles_parse_exception(activity_analyzer, monkeypatch):
    """Test detect_anomalies handles exceptions from _parse_timestamp gracefully."""
    def bad_parse(_):
        raise ValueError("parse error")

    monkeypatch.setattr(activity_analyzer, "_parse_timestamp", bad_parse)

    activities = [
        {"timestamp": "2024-01-01T10:00:00", "action": "a"},
        {"timestamp": "2024-01-01T10:10:00", "action": "a"},
        {"timestamp": "2024-01-01T10:20:00", "action": "a"},
        {"timestamp": "2024-01-01T10:30:00", "action": "a"},
        {"timestamp": "2024-01-01T10:40:00", "action": "a"},
    ]

    # Since method does not catch exceptions internally, this should raise
    with pytest.raises(ValueError):
        activity_analyzer.detect_anomalies(activities)


def test_activityanalyzer_get_user_score_handles_parse_exception(activity_analyzer, monkeypatch):
    """Test get_user_score propagates exceptions from _parse_timestamp."""
    def bad_parse(_):
        raise ValueError("parse error")

    monkeypatch.setattr(activity_analyzer, "_parse_timestamp", bad_parse)

    activities = [
        {"timestamp": "2024-01-01T10:00:00", "action": "a"},
        {"timestamp": "2024-01-02T10:00:00", "action": "b"},
    ]

    with pytest.raises(ValueError):
        activity_analyzer.get_user_score(activities)