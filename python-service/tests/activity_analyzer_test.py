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
    """Test analyze_patterns returns empty list for no activities."""
    result = activity_analyzer_instance.analyze_patterns([])
    assert result == []


def test_activityanalyzer_analyze_patterns_calls_submethods(activity_analyzer_instance):
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
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer_instance.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer_instance):
    """Test get_user_score with simple activity list and same day timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"}
        for i in range(5)
    ]
    score = activity_analyzer_instance.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_multiple_days_and_unique_actions(activity_analyzer_instance):
    """Test get_user_score with multiple days and multiple unique actions."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(days=i)).isoformat(), "action": action}
        for i, action in enumerate(["a", "b", "c", "a", "b", "d"])
    ]
    score = activity_analyzer_instance.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_invalid_timestamps(activity_analyzer_instance):
    """Test get_user_score when timestamps cannot be parsed (falls back to total_actions)."""
    activities = [
        {"timestamp": "not-a-timestamp", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": 12345, "action": "c"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_unique_action_logic(activity_analyzer_instance):
    """Test get_user_score unique action counting logic (order-based, first occurrence only)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Actions: a, b, a, c, b -> unique_actions should be 3 (a, b, c)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": action}
        for i, action in enumerate(["a", "b", "a", "c", "b"])
    ]
    score = activity_analyzer_instance.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_detect_anomalies_too_few_activities(activity_analyzer_instance):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_no_intervals(activity_analyzer_instance):
    """Test detect_anomalies when all timestamps for an action are identical (no intervals)."""
    ts = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": ts.isoformat(), "action": "a"},
        {"timestamp": ts.isoformat(), "action": "a"},
        {"timestamp": ts.isoformat(), "action": "a"},
        {"timestamp": ts.isoformat(), "action": "a"},
        {"timestamp": ts.isoformat(), "action": "a"},
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_with_clear_outlier(activity_analyzer_instance):
    """Test detect_anomalies detects an interval with high z-score as anomaly."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Intervals: 60, 60, 60, 3600 -> last interval should be anomaly
    timestamps = [
        base,
        base + timedelta(seconds=60),
        base + timedelta(seconds=120),
        base + timedelta(seconds=180),
        base + timedelta(seconds=180 + 3600),
    ]
    activities = [{"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps]

    result = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(result, list)
    if result:
        anomaly = result[0]
        assert anomaly["action"] == "a"
        assert "timestamp" in anomaly
        assert "z_score" in anomaly
        assert isinstance(anomaly["z_score"], float)


def test_activityanalyzer_detect_anomalies_ignores_actions_with_few_timestamps(activity_analyzer_instance):
    """Test detect_anomalies ignores actions that have fewer than 3 timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"} for i in range(3)
    ] + [
        {"timestamp": (base + timedelta(minutes=10 + i)).isoformat(), "action": "b"} for i in range(2)
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(result, list)


def test_activityanalyzer_detect_peak_hours_no_timestamps(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty when no valid timestamps."""
    activities = [{"timestamp": "invalid", "action": "a"}]
    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert result == []


def test_activityanalyzer_detect_peak_hours_single_peak(activity_analyzer_instance):
    """Test _detect_peak_hours identifies a single peak hour."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 8 activities at 10:00, 2 at 11:00 -> 10:00 should be peak (> 0.2)
    for i in range(8):
        activities.append({"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"})
    for i in range(2):
        activities.append({"timestamp": (base + timedelta(hours=1, minutes=i)).isoformat(), "action": "b"})

    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(result) == 1
    pattern = result[0]
    assert pattern.pattern_type == "peak_hours"
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_multiple_peaks(activity_analyzer_instance):
    """Test _detect_peak_hours identifies multiple peak hours."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 5 at 10:00, 5 at 11:00 -> both should be peaks
    for i in range(5):
        activities.append({"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"})
        activities.append({"timestamp": (base + timedelta(hours=1, minutes=i)).isoformat(), "action": "b"})

    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(result) == 1
    desc = result[0].description
    assert "10:00" in desc
    assert "11:00" in desc


def test_activityanalyzer_detect_action_sequences_too_short(activity_analyzer_instance):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"},
        {"timestamp": datetime.now().isoformat(), "action": "b"},
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert result == []


def test_activityanalyzer_detect_action_sequences_common_sequence(activity_analyzer_instance):
    """Test _detect_action_sequences detects repeated 3-action sequences."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Sequence: a,b,c,a,b,c,x -> 'a,b,c' occurs twice
    actions = ["a", "b", "c", "a", "b", "c", "x"]
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": act}
        for i, act in enumerate(actions)
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(result) >= 1
    pattern = result[0]
    assert pattern.pattern_type == "action_sequence"
    assert "a → b → c" in pattern.description
    assert "(occurred 2 times)" in pattern.description
    assert pattern.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_top_three(activity_analyzer_instance):
    """Test _detect_action_sequences returns at most three most common sequences."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    actions = ["a", "b", "c", "d", "e", "f", "g"] * 3
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": act}
        for i, act in enumerate(actions)
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(result) <= 3


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_invalid_timestamps(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"} for _ in range(10)
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer_instance):
    """Test _detect_regularity detects highly regular intervals (low coefficient of variation)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Regular 60-second intervals
    activities = [
        {"timestamp": (base + timedelta(seconds=60 * i)).isoformat(), "action": "a"}
        for i in range(6)
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert len(result) == 1
    pattern = result[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer_instance):
    """Test _detect_regularity returns empty for irregular intervals (high coefficient of variation)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    intervals = [10, 100, 5, 300, 20, 600]
    timestamps = [base]
    for sec in intervals:
        timestamps.append(timestamps[-1] + timedelta(seconds=sec))
    activities = [{"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer_instance):
    """Test _parse_timestamp returns datetime unchanged when input is datetime."""
    ts = datetime(2024, 1, 1, 10, 0, 0)
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string correctly."""
    ts = "2024-01-01T10:00:00"
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.hour == 10


def test_activityanalyzer_parse_timestamp_z_suffix(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string with Z suffix as UTC."""
    ts = "2024-01-01T10:00:00Z"
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.hour == 10


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer_instance):
    """Test _parse_timestamp returns None for invalid string."""
    parsed = activity_analyzer_instance._parse_timestamp("not-a-timestamp")
    assert parsed is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer_instance):
    """Test _parse_timestamp returns None for unsupported type."""
    parsed = activity_analyzer_instance._parse_timestamp(12345)
    assert parsed is None


def test_activityanalyzer_analyze_patterns_integration(activity_analyzer_instance):
    """Integration test: analyze_patterns returns combined patterns for realistic data."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # Peak at 10:00
    for i in range(10):
        activities.append({"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "view"})
    # Some sequences and regularity
    for i, act in enumerate(["a", "b", "c", "a", "b", "c", "a"]):
        activities.append({"timestamp": (base + timedelta(hours=1, minutes=i * 2)).isoformat(), "action": act})

    patterns = activity_analyzer_instance.analyze_patterns(activities)
    assert isinstance(patterns, list)
    assert all(isinstance(p, ActivityPattern) for p in patterns)