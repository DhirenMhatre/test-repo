import pytest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def activity_pattern_instance():
    """Create an ActivityPattern instance for testing."""
    return ActivityPattern(pattern_type="test_type", description="test_desc", confidence=0.75)


@pytest.fixture
def activity_analyzer_instance():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def test_activitypattern_init_basic(activity_pattern_instance):
    """Test ActivityPattern initialization sets attributes correctly."""
    assert activity_pattern_instance.pattern_type == "test_type"
    assert activity_pattern_instance.description == "test_desc"
    assert activity_pattern_instance.confidence == pytest.approx(0.75)


def test_activitypattern_to_dict(activity_pattern_instance):
    """Test ActivityPattern.to_dict returns correct dictionary."""
    result = activity_pattern_instance.to_dict()
    assert isinstance(result, dict)
    assert result["pattern_type"] == "test_type"
    assert result["description"] == "test_desc"
    assert result["confidence"] == pytest.approx(0.75)


def test_activityanalyzer_init_defaults(activity_analyzer_instance):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert activity_analyzer_instance.peak_hour_threshold == pytest.approx(0.2)
    assert activity_analyzer_instance.anomaly_threshold == pytest.approx(3.0)


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer_instance):
    """Test analyze_patterns returns empty list for no activities."""
    result = activity_analyzer_instance.analyze_patterns([])
    assert result == []


def test_activityanalyzer_analyze_patterns_calls_internal_methods(activity_analyzer_instance):
    """Test analyze_patterns orchestrates internal detection methods."""
    activities = [
        {"action": "a", "timestamp": datetime.now(timezone.utc).isoformat()}
        for _ in range(5)
    ]

    with patch.object(activity_analyzer_instance, "_detect_peak_hours", return_value=[ActivityPattern("p", "d", 0.1)]) as mock_peak, \
         patch.object(activity_analyzer_instance, "_detect_action_sequences", return_value=[ActivityPattern("s", "d", 0.2)]) as mock_seq, \
         patch.object(activity_analyzer_instance, "_detect_regularity", return_value=[ActivityPattern("r", "d", 0.3)]) as mock_reg:

        result = activity_analyzer_instance.analyze_patterns(activities)

        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)

        assert len(result) == 3
        assert isinstance(result[0], ActivityPattern)


def test_activityanalyzer_get_user_score_empty(activity_analyzer_instance):
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer_instance.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer_instance):
    """Test get_user_score computes expected score with timestamps and actions."""
    base_time = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"action": "login", "timestamp": (base_time + timedelta(days=0)).isoformat()},
        {"action": "view", "timestamp": (base_time + timedelta(days=0)).isoformat()},
        {"action": "logout", "timestamp": (base_time + timedelta(days=1)).isoformat()},
        {"action": "login", "timestamp": (base_time + timedelta(days=1)).isoformat()},
    ]
    # total_actions = 4
    # unique_actions = 3 (login, view, logout)
    # days_active = 1 (difference is 1 day, max(1,1))
    # actions_per_day = 4 / 1 = 4
    # diversity_score = 3/4 = 0.75
    # frequency_score = min(4/10,1)=0.4
    # volume_score = min(4/100,1)=0.04
    # final = (0.75*0.3 + 0.4*0.4 + 0.04*0.3)*100
    expected = (0.75 * 0.3 + 0.4 * 0.4 + 0.04 * 0.3) * 100
    score = activity_analyzer_instance.get_user_score(activities)
    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_no_timestamps(activity_analyzer_instance):
    """Test get_user_score when timestamps are missing or unparsable."""
    activities = [
        {"action": "a", "timestamp": "not-a-timestamp"},
        {"action": "b", "timestamp": None},
        {"action": "a"},  # no timestamp key
    ]
    # total_actions = 3
    # unique_actions = 2 (a, b)
    # actions_per_day = total_actions (3) because timestamps invalid
    # diversity_score = 2/3
    # frequency_score = min(3/10,1)=0.3
    # volume_score = min(3/100,1)=0.03
    expected = ((2 / 3) * 0.3 + 0.3 * 0.4 + 0.03 * 0.3) * 100
    score = activity_analyzer_instance.get_user_score(activities)
    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_detect_anomalies_too_few(activity_analyzer_instance):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [
        {"action": "a", "timestamp": datetime.now(timezone.utc).isoformat()}
        for _ in range(4)
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_no_intervals(activity_analyzer_instance):
    """Test detect_anomalies when intervals list is empty (all same timestamp)."""
    ts = datetime(2024, 1, 1, tzinfo=timezone.utc).isoformat()
    activities = [
        {"action": "a", "timestamp": ts},
        {"action": "a", "timestamp": ts},
        {"action": "a", "timestamp": ts},
        {"action": "a", "timestamp": ts},
        {"action": "a", "timestamp": ts},
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_with_outlier_interval(activity_analyzer_instance):
    """Test detect_anomalies detects an interval with high z-score."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    # Intervals: 10, 10, 10, 1000 seconds -> last interval is anomaly
    timestamps = [
        base,
        base + timedelta(seconds=10),
        base + timedelta(seconds=20),
        base + timedelta(seconds=30),
        base + timedelta(seconds=1030),
    ]
    activities = [{"action": "click", "timestamp": ts.isoformat()} for ts in timestamps]

    anomalies = activity_analyzer_instance.detect_anomalies(activities)
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "click"
    assert "timestamp" in anomaly
    assert "z_score" in anomaly
    assert anomaly["z_score"] > 0
    assert "Unusual interval" in anomaly["reason"]


def test_activityanalyzer_detect_anomalies_multiple_actions(activity_analyzer_instance):
    """Test detect_anomalies handles multiple actions and skips those with <3 timestamps."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"action": "a", "timestamp": (base + timedelta(seconds=0)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(seconds=10)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(seconds=20)).isoformat()},
        {"action": "b", "timestamp": (base + timedelta(seconds=30)).isoformat()},
        {"action": "b", "timestamp": (base + timedelta(seconds=40)).isoformat()},
    ]
    # action 'b' has only 2 timestamps -> skipped
    anomalies = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(anomalies, list)


def test_activityanalyzer_detect_peak_hours_no_timestamps(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty when no valid timestamps."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "b", "timestamp": None},
    ]
    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert result == []


def test_activityanalyzer_detect_peak_hours_threshold(activity_analyzer_instance):
    """Test _detect_peak_hours identifies peak hours above threshold."""
    base = datetime(2024, 1, 1, 10, 0, tzinfo=timezone.utc)
    activities = []
    # 8 activities at 10:00, 2 at 11:00 -> 10:00 is 80% > 0.2
    for _ in range(8):
        activities.append({"action": "a", "timestamp": base.isoformat()})
    for _ in range(2):
        activities.append({"action": "b", "timestamp": (base + timedelta(hours=1)).isoformat()})

    patterns = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "peak_hours"
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_no_peak(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    base = datetime(2024, 1, 1, 0, 0, tzinfo=timezone.utc)
    activities = []
    # 5 different hours, each 20% -> equal to threshold, not greater
    for i in range(5):
        activities.append({"action": "a", "timestamp": (base + timedelta(hours=i)).isoformat()})

    patterns = activity_analyzer_instance._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_too_short(activity_analyzer_instance):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [
        {"action": "a", "timestamp": datetime.now(timezone.utc).isoformat()},
        {"action": "b", "timestamp": datetime.now(timezone.utc).isoformat()},
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert result == []


def test_activityanalyzer_detect_action_sequences_common(activity_analyzer_instance):
    """Test _detect_action_sequences identifies common sequences occurring at least twice."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"action": "a", "timestamp": (base + timedelta(seconds=0)).isoformat()},
        {"action": "b", "timestamp": (base + timedelta(seconds=1)).isoformat()},
        {"action": "c", "timestamp": (base + timedelta(seconds=2)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(seconds=3)).isoformat()},
        {"action": "b", "timestamp": (base + timedelta(seconds=4)).isoformat()},
        {"action": "c", "timestamp": (base + timedelta(seconds=5)).isoformat()},
    ]
    patterns = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(patterns) >= 1
    pattern = patterns[0]
    assert pattern.pattern_type == "action_sequence"
    assert "a → b → c" in pattern.description
    assert "(occurred 2 times)" in pattern.description
    assert pattern.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_limit_top3(activity_analyzer_instance):
    """Test _detect_action_sequences returns at most top 3 sequences."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    actions = ["a", "b", "c", "d", "e", "f"]
    activities = []
    for i, act in enumerate(actions * 3):
        activities.append({"action": act, "timestamp": (base + timedelta(seconds=i)).isoformat()})

    patterns = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(patterns) <= 3


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 activities."""
    activities = [
        {"action": "a", "timestamp": datetime.now(timezone.utc).isoformat()}
        for _ in range(4)
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_insufficient_valid_timestamps(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "a", "timestamp": None},
        {"action": "a", "timestamp": "2024-01-01T00:00:00Z"},
        {"action": "a", "timestamp": "2024-01-01T00:00:10Z"},
        {"action": "a", "timestamp": "2024-01-01T00:00:20Z"},
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer_instance):
    """Test _detect_regularity detects highly regular intervals (low CV)."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    # Intervals all 10 seconds -> CV = 0
    activities = []
    for i in range(6):
        activities.append({"action": "a", "timestamp": (base + timedelta(seconds=10 * i)).isoformat()})

    patterns = activity_analyzer_instance._detect_regularity(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_not_regular(activity_analyzer_instance):
    """Test _detect_regularity returns empty when coefficient of variation is high."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    # Irregular intervals
    timestamps = [
        base,
        base + timedelta(seconds=10),
        base + timedelta(seconds=50),
        base + timedelta(seconds=70),
        base + timedelta(seconds=200),
        base + timedelta(seconds=260),
    ]
    activities = [{"action": "a", "timestamp": ts.isoformat()} for ts in timestamps]
    patterns = activity_analyzer_instance._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer_instance):
    """Test _parse_timestamp returns datetime unchanged when input is datetime."""
    ts = datetime(2024, 1, 1, tzinfo=timezone.utc)
    result = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(result, datetime)
    assert result == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string with Z suffix."""
    ts_str = "2024-01-01T12:34:56Z"
    result = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(result, datetime)
    assert result.year == 2024
    assert result.month == 1
    assert result.day == 1
    assert result.hour == 12
    assert result.minute == 34
    assert result.second == 56


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer_instance):
    """Test _parse_timestamp returns None for invalid string."""
    result = activity_analyzer_instance._parse_timestamp("not-a-timestamp")
    assert result is None


def test_activityanalyzer_parse_timestamp_none(activity_analyzer_instance):
    """Test _parse_timestamp returns None for None input."""
    result = activity_analyzer_instance._parse_timestamp(None)
    assert result is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer_instance):
    """Test _parse_timestamp returns None for unsupported type (e.g., int)."""
    result = activity_analyzer_instance._parse_timestamp(123456)
    assert result is None


def test_activityanalyzer_detect_anomalies_exception_handling(activity_analyzer_instance):
    """Test detect_anomalies handles exceptions from _parse_timestamp gracefully."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"action": "a", "timestamp": base.isoformat()},
        {"action": "a", "timestamp": base.isoformat()},
        {"action": "a", "timestamp": base.isoformat()},
        {"action": "a", "timestamp": base.isoformat()},
        {"action": "a", "timestamp": base.isoformat()},
    ]

    with patch.object(activity_analyzer_instance, "_parse_timestamp", side_effect=Exception("parse error")):
        # Since exception is not caught inside detect_anomalies, it should propagate
        with pytest.raises(Exception):
            activity_analyzer_instance.detect_anomalies(activities)


def test_activityanalyzer_get_user_score_exception_in_parse(activity_analyzer_instance):
    """Test get_user_score handles exceptions from _parse_timestamp by treating timestamps as invalid."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T00:00:00Z"},
        {"action": "b", "timestamp": "2024-01-02T00:00:00Z"},
    ]

    with patch.object(activity_analyzer_instance, "_parse_timestamp", side_effect=[None, None]):
        score = activity_analyzer_instance.get_user_score(activities)
        # With 2 actions, 2 unique, no valid timestamps:
        # diversity = 1.0, actions_per_day = 2, frequency=0.2, volume=0.02
        expected = (1.0 * 0.3 + 0.2 * 0.4 + 0.02 * 0.3) * 100
        assert score == pytest.approx(round(expected, 2))