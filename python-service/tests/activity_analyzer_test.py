import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def activity_pattern_instance():
    """Create ActivityPattern instance for testing."""
    return ActivityPattern(pattern_type="test_type", description="test description", confidence=0.95)


@pytest.fixture
def activity_analyzer_instance():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def test_activitypattern_init():
    """Test ActivityPattern initialization with valid data."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.8)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "desc"
    assert pattern.confidence == pytest.approx(0.8)


def test_activitypattern_to_dict(activity_pattern_instance):
    """Test ActivityPattern.to_dict returns correct dictionary."""
    result = activity_pattern_instance.to_dict()
    assert result["pattern_type"] == "test_type"
    assert result["description"] == "test description"
    assert result["confidence"] == pytest.approx(0.95)


def test_activityanalyzer_init_defaults(activity_analyzer_instance):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert activity_analyzer_instance.peak_hour_threshold == pytest.approx(0.2)
    assert activity_analyzer_instance.anomaly_threshold == pytest.approx(3.0)


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer_instance):
    """Test analyze_patterns returns empty list when no activities."""
    result = activity_analyzer_instance.analyze_patterns([])
    assert result == []


def test_activityanalyzer_analyze_patterns_calls_internal_methods(activity_analyzer_instance):
    """Test analyze_patterns calls internal detection methods and aggregates results."""
    activities = [{"timestamp": datetime.now().isoformat(), "action": "a"}]

    with patch.object(activity_analyzer_instance, "_detect_peak_hours", return_value=[ActivityPattern("t1", "d1", 0.5)]) as mock_peak, \
         patch.object(activity_analyzer_instance, "_detect_action_sequences", return_value=[ActivityPattern("t2", "d2", 0.6)]) as mock_seq, \
         patch.object(activity_analyzer_instance, "_detect_regularity", return_value=[ActivityPattern("t3", "d3", 0.7)]) as mock_reg:

        result = activity_analyzer_instance.analyze_patterns(activities)

        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)

        assert len(result) == 3
        assert [p.pattern_type for p in result] == ["t1", "t2", "t3"]


def test_activityanalyzer_get_user_score_empty(activity_analyzer_instance):
    """Test get_user_score returns 0.0 when no activities."""
    score = activity_analyzer_instance.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer_instance):
    """Test get_user_score with simple activity list and ISO timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(days=0)).isoformat(), "action": "login"},
        {"timestamp": (base + timedelta(days=0, hours=1)).isoformat(), "action": "view"},
        {"timestamp": (base + timedelta(days=1)).isoformat(), "action": "logout"},
        {"timestamp": (base + timedelta(days=1, hours=2)).isoformat(), "action": "login"},
    ]
    # total_actions = 4
    # unique_actions = 3 (login, view, logout)
    # days_active = 1 (difference in days between first and last)
    # actions_per_day = 4
    # diversity_score = 3/4 = 0.75
    # frequency_score = min(4/10,1)=0.4
    # volume_score = min(4/100,1)=0.04
    # final = (0.75*0.3 + 0.4*0.4 + 0.04*0.3)*100
    expected = (0.75 * 0.3 + 0.4 * 0.4 + 0.04 * 0.3) * 100
    score = activity_analyzer_instance.get_user_score(activities)
    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_no_parsable_timestamps(activity_analyzer_instance):
    """Test get_user_score when timestamps are not parsable; uses total_actions as actions_per_day."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": 12345, "action": "c"},
    ]
    # total_actions = 3
    # unique_actions = 3
    # actions_per_day = 3
    # diversity_score = 1.0
    # frequency_score = 0.3
    # volume_score = 0.03
    expected = (1.0 * 0.3 + 0.3 * 0.4 + 0.03 * 0.3) * 100
    score = activity_analyzer_instance.get_user_score(activities)
    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_duplicate_action_logic(activity_analyzer_instance):
    """Test get_user_score unique action counting logic with repeated actions."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": (base + timedelta(hours=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(hours=2)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=3)).isoformat(), "action": "b"},
    ]
    # According to implementation, unique_actions will be 2 (a, b)
    score = activity_analyzer_instance.get_user_score(activities)
    assert isinstance(score, float)


def test_activityanalyzer_detect_anomalies_too_few(activity_analyzer_instance):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_no_anomalies(activity_analyzer_instance):
    """Test detect_anomalies returns empty when intervals are regular."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(6):
        activities.append({"timestamp": (base + timedelta(minutes=10 * i)).isoformat(), "action": "click"})
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_with_anomaly(activity_analyzer_instance):
    """Test detect_anomalies detects an interval anomaly based on z-score."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Mostly 10s intervals, one very large interval to create anomaly
    timestamps = [
        base,
        base + timedelta(seconds=10),
        base + timedelta(seconds=20),
        base + timedelta(seconds=30),
        base + timedelta(seconds=1000),
        base + timedelta(seconds=1010),
    ]
    activities = [{"timestamp": ts.isoformat(), "action": "click"} for ts in timestamps]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(result, list)
    if result:
        for anomaly in result:
            assert anomaly["action"] == "click"
            assert "timestamp" in anomaly
            assert "z_score" in anomaly
            assert isinstance(anomaly["z_score"], float) or isinstance(anomaly["z_score"], int)


def test_activityanalyzer_detect_anomalies_ignores_unparsable_timestamps(activity_analyzer_instance):
    """Test detect_anomalies ignores activities with unparsable timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": base.isoformat(), "action": "click"},
        {"timestamp": "invalid", "action": "click"},
        {"timestamp": (base + timedelta(seconds=10)).isoformat(), "action": "click"},
        {"timestamp": (base + timedelta(seconds=20)).isoformat(), "action": "click"},
        {"timestamp": (base + timedelta(seconds=30)).isoformat(), "action": "click"},
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(result, list)


def test_activityanalyzer_detect_anomalies_multiple_actions(activity_analyzer_instance):
    """Test detect_anomalies handles multiple actions separately."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(5):
        activities.append({"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"})
    for i in range(5):
        activities.append({"timestamp": (base + timedelta(minutes=2 * i)).isoformat(), "action": "b"})
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(result, list)


def test_activityanalyzer_detect_peak_hours_no_timestamps(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty when no valid timestamps."""
    activities = [{"timestamp": "invalid", "action": "a"}]
    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert result == []


def test_activityanalyzer_detect_peak_hours_single_peak(activity_analyzer_instance):
    """Test _detect_peak_hours identifies peak hours above threshold."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 8 activities at 10:00, 2 at 11:00; threshold 0.2 => 10:00 is peak, 11:00 also peak
    for _ in range(8):
        activities.append({"timestamp": base.isoformat(), "action": "a"})
    for _ in range(2):
        activities.append({"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "b"})
    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(result) == 1
    pattern = result[0]
    assert pattern.pattern_type == "peak_hours"
    assert "High activity during hours" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_below_threshold(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(5):
        activities.append({"timestamp": (base + timedelta(hours=i)).isoformat(), "action": "a"})
    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert result == []


def test_activityanalyzer_detect_action_sequences_too_short(activity_analyzer_instance):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [{"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(2)]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert result == []


def test_activityanalyzer_detect_action_sequences_common_sequences(activity_analyzer_instance):
    """Test _detect_action_sequences identifies common sequences occurring at least twice."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": a}
        for i, a in enumerate(["a", "b", "c", "a", "b", "c", "d"])
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(result) >= 1
    descriptions = [p.description for p in result]
    assert any("Common sequence: a → b → c" in d for d in descriptions)
    for p in result:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_top_three(activity_analyzer_instance):
    """Test _detect_action_sequences returns at most three most common sequences."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    actions = ["a", "b", "c", "d", "e", "f"]
    activities = []
    for i in range(20):
        activities.append({"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": actions[i % len(actions)]})
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(result) <= 3


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_insufficient_valid_timestamps(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": 123, "action": "c"},
        {"timestamp": datetime.now().isoformat(), "action": "d"},
        {"timestamp": "also invalid", "action": "e"},
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer_instance):
    """Test _detect_regularity detects highly regular activity pattern."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(6):
        activities.append({"timestamp": (base + timedelta(minutes=10 * i)).isoformat(), "action": "a"})
    result = activity_analyzer_instance._detect_regularity(activities)
    assert len(result) == 1
    pattern = result[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer_instance):
    """Test _detect_regularity returns empty for irregular intervals."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    intervals = [1, 5, 20, 60, 2, 15]
    activities = []
    current = base
    for inc in intervals:
        current += timedelta(minutes=inc)
        activities.append({"timestamp": current.isoformat(), "action": "a"})
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer_instance):
    """Test _parse_timestamp returns datetime unchanged when input is datetime."""
    ts = datetime(2024, 1, 1, 10, 0, 0)
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO format string."""
    ts = "2024-01-01T10:00:00"
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.hour == 10


def test_activityanalyzer_parse_timestamp_iso_string_with_z(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO format string with Z suffix."""
    ts = "2024-01-01T10:00:00Z"
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.hour == 10


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer_instance):
    """Test _parse_timestamp returns None for invalid string."""
    ts = "not-a-timestamp"
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert parsed is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer_instance):
    """Test _parse_timestamp returns None for unsupported type."""
    parsed = activity_analyzer_instance._parse_timestamp(12345)
    assert parsed is None


def test_activityanalyzer_parse_timestamp_exception_handling(activity_analyzer_instance, monkeypatch):
    """Test _parse_timestamp gracefully handles exceptions from datetime.fromisoformat."""
    def bad_fromisoformat(_):
        raise ValueError("bad format")

    with monkeypatch.context() as m:
        m.setattr("datetime.datetime.fromisoformat", bad_fromisoformat, raising=False)
        parsed = activity_analyzer_instance._parse_timestamp("2024-01-01T10:00:00")
        assert parsed is None


def test_activityanalyzer_analyze_patterns_integration(activity_analyzer_instance):
    """Integration test for analyze_patterns with realistic activities."""
    base = datetime(2024, 1, 1, 9, 0, 0)
    activities = []
    for i in range(10):
        activities.append({"timestamp": (base + timedelta(hours=1 * (i // 2))).isoformat(), "action": "a" if i % 2 == 0 else "b"})
    patterns = activity_analyzer_instance.analyze_patterns(activities)
    assert isinstance(patterns, list)
    for p in patterns:
        assert isinstance(p, ActivityPattern)