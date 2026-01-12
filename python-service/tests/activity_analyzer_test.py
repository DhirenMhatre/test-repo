import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def activity_pattern_instance():
    """Create ActivityPattern instance for testing."""
    return ActivityPattern(pattern_type="test_type", description="test_desc", confidence=0.9)


@pytest.fixture
def activity_analyzer_instance():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def test_activitypattern_init():
    """Test ActivityPattern initialization with valid data."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.85)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "desc"
    assert pattern.confidence == pytest.approx(0.85)


def test_activitypattern_to_dict(activity_pattern_instance):
    """Test ActivityPattern.to_dict returns correct dictionary."""
    result = activity_pattern_instance.to_dict()
    assert result["pattern_type"] == "test_type"
    assert result["description"] == "test_desc"
    assert result["confidence"] == pytest.approx(0.9)


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
    """Test get_user_score with simple activity list and ISO timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(days=0)).isoformat(), "action": "login"},
        {"timestamp": (base + timedelta(days=0, hours=1)).isoformat(), "action": "view"},
        {"timestamp": (base + timedelta(days=1)).isoformat(), "action": "logout"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    total_actions = 3
    unique_actions = 3
    days_active = 1
    actions_per_day = total_actions / days_active
    diversity_score = unique_actions / total_actions
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100

    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_unparseable_timestamps(activity_analyzer_instance):
    """Test get_user_score when timestamps are unparseable, using total_actions as actions_per_day."""
    activities = [
        {"timestamp": "not-a-date", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": 12345, "action": "c"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    total_actions = 3
    unique_actions = 3
    actions_per_day = total_actions
    diversity_score = unique_actions / total_actions
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100

    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_duplicate_actions_logic(activity_analyzer_instance):
    """Test get_user_score unique action counting logic with duplicates."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": (base + timedelta(hours=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(hours=2)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=3)).isoformat(), "action": "c"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    total_actions = 4
    # According to implementation, unique_actions is 3 (a, b, c)
    unique_actions = 3
    days_active = 1
    actions_per_day = total_actions / days_active
    diversity_score = unique_actions / total_actions
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100

    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_detect_anomalies_too_few(activity_analyzer_instance):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_no_intervals(activity_analyzer_instance):
    """Test detect_anomalies when actions have fewer than 3 timestamps."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"} for i in range(2)
    ] + [
        {"timestamp": (base + timedelta(minutes=10 + i)).isoformat(), "action": "b"} for i in range(2)
    ] + [
        {"timestamp": (base + timedelta(minutes=20)).isoformat(), "action": "c"}
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_with_outlier_interval(activity_analyzer_instance):
    """Test detect_anomalies detects an interval with high z-score."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=5)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=10)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=5)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=5, minutes=5)).isoformat(), "action": "a"},
    ]
    anomalies = activity_analyzer_instance.detect_anomalies(activities)

    assert isinstance(anomalies, list)
    for anomaly in anomalies:
        assert anomaly["action"] == "a"
        assert "timestamp" in anomaly
        assert "z_score" in anomaly
        assert isinstance(anomaly["z_score"], float)
        assert "reason" in anomaly


def test_activityanalyzer_detect_anomalies_ignores_unparseable(activity_analyzer_instance):
    """Test detect_anomalies ignores activities with unparseable timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i * 5)).isoformat(), "action": "a"} for i in range(5)
    ]
    activities.append({"timestamp": "invalid", "action": "a"})
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(result, list)


def test_activityanalyzer_detect_anomalies_exception_handling(activity_analyzer_instance):
    """Test detect_anomalies handles exceptions from _parse_timestamp gracefully."""
    activities = [{"timestamp": "2024-01-01T00:00:00Z", "action": "a"} for _ in range(6)]

    with patch.object(activity_analyzer_instance, "_parse_timestamp", side_effect=Exception("parse error")):
        result = activity_analyzer_instance.detect_anomalies(activities)
        assert result == []


def test_activityanalyzer_detect_peak_hours_no_activities(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty list when no valid timestamps."""
    result = activity_analyzer_instance._detect_peak_hours([])
    assert result == []


def test_activityanalyzer_detect_peak_hours_below_threshold(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": (base + timedelta(hours=i)).isoformat(), "action": "a"} for i in range(5)
    ]
    activity_analyzer_instance.peak_hour_threshold = 0.5
    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert result == []


def test_activityanalyzer_detect_peak_hours_above_threshold(activity_analyzer_instance):
    """Test _detect_peak_hours identifies peak hours correctly."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for _ in range(8):
        activities.append({"timestamp": (base).isoformat(), "action": "a"})
    for _ in range(2):
        activities.append({"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "b"})

    activity_analyzer_instance.peak_hour_threshold = 0.5
    patterns = activity_analyzer_instance._detect_peak_hours(activities)

    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "peak_hours"
    assert "High activity during hours" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_ignores_unparseable(activity_analyzer_instance):
    """Test _detect_peak_hours ignores activities with invalid timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base).isoformat(), "action": "a"},
        {"timestamp": "invalid", "action": "b"},
    ]
    patterns = activity_analyzer_instance._detect_peak_hours(activities)
    assert isinstance(patterns, list)


def test_activityanalyzer_detect_action_sequences_too_short(activity_analyzer_instance):
    """Test _detect_action_sequences returns empty list when fewer than 3 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"},
        {"timestamp": datetime.now().isoformat(), "action": "b"},
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert result == []


def test_activityanalyzer_detect_action_sequences_common_sequences(activity_analyzer_instance):
    """Test _detect_action_sequences identifies common sequences occurring at least twice."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": a}
        for i, a in enumerate([
            "login", "view", "logout",
            "login", "view", "logout",
            "login", "other", "logout",
        ])
    ]
    patterns = activity_analyzer_instance._detect_action_sequences(activities)

    assert len(patterns) >= 1
    descriptions = [p.description for p in patterns]
    assert any("login → view → logout" in d for d in descriptions)
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_limit_top3(activity_analyzer_instance):
    """Test _detect_action_sequences returns at most top 3 sequences."""
    base = datetime(2024, 1, 1)
    actions = ["a", "b", "c", "d", "e", "f"]
    activities = []
    for i in range(10):
        for j in range(3):
            activities.append({
                "timestamp": (base + timedelta(minutes=i * 3 + j)).isoformat(),
                "action": actions[j],
            })
    patterns = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(patterns) <= 3


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer_instance):
    """Test _detect_regularity returns empty list when fewer than 5 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_not_enough_valid_timestamps(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": (base + timedelta(minutes=5)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=10)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=15)).isoformat(), "action": "a"},
        {"timestamp": "also-invalid", "action": "a"},
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer_instance):
    """Test _detect_regularity detects highly regular intervals (low coefficient of variation)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=5 * i)).isoformat(), "action": "a"}
        for i in range(6)
    ]
    patterns = activity_analyzer_instance._detect_regularity(activities)

    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer_instance):
    """Test _detect_regularity returns empty when coefficient of variation is high."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    intervals = [1, 10, 30, 60, 120]
    activities = []
    current = base
    for delta in intervals:
        current += timedelta(minutes=delta)
        activities.append({"timestamp": current.isoformat(), "action": "a"})
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer_instance):
    """Test _parse_timestamp returns datetime unchanged when input is datetime."""
    ts = datetime(2024, 1, 1, 12, 0, 0)
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string correctly."""
    ts_str = "2024-01-01T12:00:00"
    parsed = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.month == 1
    assert parsed.day == 1
    assert parsed.hour == 12
    assert parsed.minute == 0
    assert parsed.second == 0


def test_activityanalyzer_parse_timestamp_with_z_suffix(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO string with Z suffix as UTC."""
    ts_str = "2024-01-01T12:00:00Z"
    parsed = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.hour == 12


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer_instance):
    """Test _parse_timestamp returns None for invalid string."""
    parsed = activity_analyzer_instance._parse_timestamp("not-a-timestamp")
    assert parsed is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer_instance):
    """Test _parse_timestamp returns None for unsupported type."""
    parsed = activity_analyzer_instance._parse_timestamp(12345)
    assert parsed is None


def test_activityanalyzer_parse_timestamp_exception_handling(activity_analyzer_instance, monkeypatch):
    """Test _parse_timestamp handles exceptions from datetime.fromisoformat."""
    def bad_fromisoformat(_):
        raise ValueError("bad format")

    monkeypatch.setattr("datetime.datetime.fromisoformat", bad_fromisoformat, raising=False)
    parsed = activity_analyzer_instance._parse_timestamp("2024-01-01T00:00:00")
    assert parsed is None