import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def activity_pattern_instance():
    """Create an ActivityPattern instance for testing."""
    return ActivityPattern(pattern_type="test_type", description="test description", confidence=0.75)


@pytest.fixture
def activity_analyzer_instance():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def test_activitypattern_init():
    """Test ActivityPattern initialization sets attributes correctly."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.9)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "desc"
    assert pattern.confidence == pytest.approx(0.9)


def test_activitypattern_to_dict(activity_pattern_instance):
    """Test ActivityPattern.to_dict returns correct dictionary."""
    result = activity_pattern_instance.to_dict()
    assert result["pattern_type"] == "test_type"
    assert result["description"] == "test description"
    assert result["confidence"] == pytest.approx(0.75)


def test_activityanalyzer_init_defaults(activity_analyzer_instance):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert activity_analyzer_instance.peak_hour_threshold == pytest.approx(0.2)
    assert activity_analyzer_instance.anomaly_threshold == pytest.approx(3.0)


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer_instance):
    """Test analyze_patterns returns empty list when no activities provided."""
    assert activity_analyzer_instance.analyze_patterns([]) == []


def test_activityanalyzer_analyze_patterns_combines_patterns(activity_analyzer_instance):
    """Test analyze_patterns combines results from internal detection methods."""
    activities = [{"timestamp": datetime.now(), "action": "a"}]

    with patch.object(activity_analyzer_instance, "_detect_peak_hours", return_value=[ActivityPattern("p", "ph", 0.1)]) as mock_peak, \
         patch.object(activity_analyzer_instance, "_detect_action_sequences", return_value=[ActivityPattern("s", "seq", 0.2)]) as mock_seq, \
         patch.object(activity_analyzer_instance, "_detect_regularity", return_value=[ActivityPattern("r", "reg", 0.3)]) as mock_reg:

        patterns = activity_analyzer_instance.analyze_patterns(activities)

        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)

        assert len(patterns) == 3
        assert [p.pattern_type for p in patterns] == ["p", "s", "r"]


def test_activityanalyzer_get_user_score_empty(activity_analyzer_instance):
    """Test get_user_score returns 0.0 for empty activities list."""
    score = activity_analyzer_instance.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer_instance):
    """Test get_user_score with simple non-empty activities."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": base.isoformat(), "action": "login"},
        {"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "view"},
        {"timestamp": (base + timedelta(hours=2)).isoformat(), "action": "logout"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    # Manual calculation:
    # total_actions = 3, unique_actions = 3, days_active = 1
    # actions_per_day = 3
    # diversity_score = 3/3 = 1
    # frequency_score = min(3/10, 1) = 0.3
    # volume_score = min(3/100, 1) = 0.03
    # final = (1*0.3 + 0.3*0.4 + 0.03*0.3)*100 = (0.3 + 0.12 + 0.009)*100 = 42.9
    expected = 42.9
    assert score == pytest.approx(expected)


def test_activityanalyzer_get_user_score_duplicate_actions(activity_analyzer_instance):
    """Test get_user_score counts unique actions using the implemented logic."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": base.isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=2)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(hours=3)).isoformat(), "action": "b"},
    ]
    # According to implementation, unique_actions will be 2 ("a" then "b")
    score = activity_analyzer_instance.get_user_score(activities)

    # total_actions = 4, unique_actions = 2, days_active = 1
    # actions_per_day = 4
    # diversity_score = 2/4 = 0.5
    # frequency_score = min(4/10, 1) = 0.4
    # volume_score = min(4/100, 1) = 0.04
    # final = (0.5*0.3 + 0.4*0.4 + 0.04*0.3)*100
    #       = (0.15 + 0.16 + 0.012)*100 = 32.2
    expected = 32.2
    assert score == pytest.approx(expected)


def test_activityanalyzer_get_user_score_invalid_timestamps(activity_analyzer_instance):
    """Test get_user_score when timestamps cannot be parsed (falls back to total_actions)."""
    activities = [
        {"timestamp": "not-a-date", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": 12345, "action": "c"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    # total_actions = 3, unique_actions = 3
    # actions_per_day = total_actions (since first_ts/last_ts are None) = 3
    # diversity_score = 1
    # frequency_score = min(3/10, 1) = 0.3
    # volume_score = min(3/100, 1) = 0.03
    # final = 42.9
    expected = 42.9
    assert score == pytest.approx(expected)


def test_activityanalyzer_detect_anomalies_too_few(activity_analyzer_instance):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now(), "action": "a"} for _ in range(4)]
    assert activity_analyzer_instance.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_no_intervals(activity_analyzer_instance):
    """Test detect_anomalies when actions have fewer than 3 timestamps (skipped)."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": base.isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(seconds=10)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(seconds=20)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(seconds=30)).isoformat(), "action": "c"},
        {"timestamp": (base + timedelta(seconds=40)).isoformat(), "action": "c"},
    ]
    # No action has >=3 timestamps, so no anomalies
    anomalies = activity_analyzer_instance.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_with_outlier_interval(activity_analyzer_instance):
    """Test detect_anomalies detects an interval with high z-score as anomaly."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    # Create regular intervals of 10s, then one large interval to trigger anomaly
    timestamps = [
        base,
        base + timedelta(seconds=10),
        base + timedelta(seconds=20),
        base + timedelta(seconds=30),
        base + timedelta(seconds=200),  # large gap
    ]
    activities = [{"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps]

    anomalies = activity_analyzer_instance.detect_anomalies(activities)

    assert len(anomalies) >= 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "a"
    assert "timestamp" in anomaly
    assert "z_score" in anomaly
    assert isinstance(anomaly["z_score"], float)
    assert anomaly["z_score"] > activity_analyzer_instance.anomaly_threshold
    assert "Unusual interval" in anomaly["reason"]


def test_activityanalyzer_detect_anomalies_ignores_unparsable_timestamps(activity_analyzer_instance):
    """Test detect_anomalies ignores activities with unparsable timestamps."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": base.isoformat(), "action": "a"},
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": (base + timedelta(seconds=10)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(seconds=20)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(seconds=30)).isoformat(), "action": "a"},
    ]
    anomalies = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(anomalies, list)


def test_activityanalyzer_detect_peak_hours_no_activities(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty list when no valid timestamps."""
    activities = [{"timestamp": "invalid", "action": "a"}]
    patterns = activity_analyzer_instance._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_identifies_peak(activity_analyzer_instance):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    base = datetime(2024, 1, 1, 10, 0, tzinfo=timezone.utc)
    activities = []
    # 8 activities at 10:00, 2 at 11:00
    for _ in range(8):
        activities.append({"timestamp": base.isoformat(), "action": "a"})
    for _ in range(2):
        activities.append({"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "b"})

    patterns = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "peak_hours"
    assert "High activity during hours" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_multiple_peaks(activity_analyzer_instance):
    """Test _detect_peak_hours can return multiple peak hours in description."""
    base = datetime(2024, 1, 1, 10, 0, tzinfo=timezone.utc)
    activities = []
    # 3 at 10:00, 3 at 11:00, 4 at 12:00 -> all above 0.2 threshold
    for _ in range(3):
        activities.append({"timestamp": base.isoformat(), "action": "a"})
    for _ in range(3):
        activities.append({"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "b"})
    for _ in range(4):
        activities.append({"timestamp": (base + timedelta(hours=2)).isoformat(), "action": "c"})

    patterns = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(patterns) == 1
    desc = patterns[0].description
    assert "10:00" in desc
    assert "11:00" in desc
    assert "12:00" in desc


def test_activityanalyzer_detect_action_sequences_too_short(activity_analyzer_instance):
    """Test _detect_action_sequences returns empty list when fewer than 3 activities."""
    activities = [{"timestamp": datetime.now(), "action": "a"} for _ in range(2)]
    assert activity_analyzer_instance._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_action_sequences_common_sequences(activity_analyzer_instance):
    """Test _detect_action_sequences identifies common sequences occurring at least twice."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": a}
        for i, a in enumerate(
            [
                "login",
                "view",
                "logout",   # seq1
                "login",
                "view",
                "logout",   # seq1 again
                "login",
                "edit",
                "save",     # seq2
                "login",
                "edit",
                "save",     # seq2 again
            ]
        )
    ]

    patterns = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(patterns) >= 2
    descriptions = [p.description for p in patterns]
    assert any("login → view → logout" in d for d in descriptions)
    assert any("login → edit → save" in d for d in descriptions)
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_respects_top3(activity_analyzer_instance):
    """Test _detect_action_sequences only returns up to 3 most common sequences."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    actions = ["a", "b", "c", "d"]
    activities = []
    # Create many overlapping sequences; ensure more than 3 unique sequences exist
    for i in range(20):
        activities.append({"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": actions[i % 4]})

    patterns = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(patterns) <= 3


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer_instance):
    """Test _detect_regularity returns empty list when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now(), "action": "a"} for _ in range(4)]
    assert activity_analyzer_instance._detect_regularity(activities) == []


def test_activityanalyzer_detect_regularity_insufficient_valid_timestamps(activity_analyzer_instance):
    """Test _detect_regularity returns empty list when fewer than 5 valid timestamps."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "a"},
        {"timestamp": (base + timedelta(minutes=1)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=2)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=3)).isoformat(), "action": "a"},
    ]
    patterns = activity_analyzer_instance._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer_instance):
    """Test _detect_regularity detects highly regular intervals (low coefficient of variation)."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": (base + timedelta(minutes=i * 10)).isoformat(), "action": "a"}
        for i in range(6)
    ]
    patterns = activity_analyzer_instance._detect_regularity(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer_instance):
    """Test _detect_regularity returns empty list for irregular intervals."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    intervals = [1, 5, 20, 2, 30]  # highly variable
    timestamps = [base]
    for i in intervals:
        timestamps.append(timestamps[-1] + timedelta(minutes=i))
    activities = [{"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps]

    patterns = activity_analyzer_instance._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer_instance):
    """Test _parse_timestamp returns datetime unchanged when input is datetime."""
    ts = datetime(2024, 1, 1, tzinfo=timezone.utc)
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string correctly."""
    ts = datetime(2024, 1, 1, 12, 0, tzinfo=timezone.utc)
    parsed = activity_analyzer_instance._parse_timestamp(ts.isoformat())
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_z_suffix(activity_analyzer_instance):
    """Test _parse_timestamp handles 'Z' suffix by converting to UTC offset."""
    ts_str = "2024-01-01T12:00:00Z"
    parsed = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.month == 1
    assert parsed.day == 1
    assert parsed.hour == 12


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer_instance):
    """Test _parse_timestamp returns None for invalid string."""
    parsed = activity_analyzer_instance._parse_timestamp("not-a-timestamp")
    assert parsed is None


def test_activityanalyzer_parse_timestamp_other_types(activity_analyzer_instance):
    """Test _parse_timestamp returns None for unsupported types."""
    assert activity_analyzer_instance._parse_timestamp(12345) is None
    assert activity_analyzer_instance._parse_timestamp(None) is None


def test_activityanalyzer_internal_parse_timestamp_exception_handling(activity_analyzer_instance, monkeypatch):
    """Test _parse_timestamp gracefully handles exceptions from datetime.fromisoformat."""
    def bad_fromisoformat(_):
        raise ValueError("bad format")

    with monkeypatch.patch("datetime.datetime.fromisoformat", side_effect=bad_fromisoformat):
        parsed = activity_analyzer_instance._parse_timestamp("2024-01-01T00:00:00")
        assert parsed is None


def test_activityanalyzer_detect_anomalies_uses_internal_parse_timestamp(activity_analyzer_instance, monkeypatch):
    """Test detect_anomalies uses _parse_timestamp and handles its behavior."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": base.isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(seconds=10)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(seconds=20)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(seconds=30)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(seconds=40)).isoformat(), "action": "a"},
    ]

    mock_parse = MagicMock(side_effect=activity_analyzer_instance._parse_timestamp)
    monkeypatch.setattr(activity_analyzer_instance, "_parse_timestamp", mock_parse)

    _ = activity_analyzer_instance.detect_anomalies(activities)
    assert mock_parse.call_count == len(activities)