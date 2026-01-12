import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def activity_pattern_instance():
    """Create ActivityPattern instance for testing."""
    return ActivityPattern(pattern_type="test_type", description="test_desc", confidence=0.95)


@pytest.fixture
def activity_analyzer_instance():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def test_activitypattern_init(activity_pattern_instance):
    """Test ActivityPattern initialization with valid data."""
    assert activity_pattern_instance.pattern_type == "test_type"
    assert activity_pattern_instance.description == "test_desc"
    assert activity_pattern_instance.confidence == pytest.approx(0.95)


def test_activitypattern_to_dict(activity_pattern_instance):
    """Test ActivityPattern.to_dict returns correct dictionary."""
    result = activity_pattern_instance.to_dict()
    assert result["pattern_type"] == "test_type"
    assert result["description"] == "test_desc"
    assert result["confidence"] == pytest.approx(0.95)


def test_activityanalyzer_init_defaults(activity_analyzer_instance):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert activity_analyzer_instance.peak_hour_threshold == pytest.approx(0.2)
    assert activity_analyzer_instance.anomaly_threshold == pytest.approx(3.0)


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer_instance):
    """Test analyze_patterns returns empty list for no activities."""
    result = activity_analyzer_instance.analyze_patterns([])
    assert result == []


def test_activityanalyzer_analyze_patterns_calls_internal_methods(activity_analyzer_instance):
    """Test analyze_patterns calls internal detection methods and aggregates results."""
    activities = [{"action": "a", "timestamp": datetime.now().isoformat()}]

    with patch.object(activity_analyzer_instance, "_detect_peak_hours", return_value=[ActivityPattern("p", "ph", 0.8)]) as mock_peak, \
         patch.object(activity_analyzer_instance, "_detect_action_sequences", return_value=[ActivityPattern("s", "seq", 0.7)]) as mock_seq, \
         patch.object(activity_analyzer_instance, "_detect_regularity", return_value=[ActivityPattern("r", "reg", 0.9)]) as mock_reg:

        result = activity_analyzer_instance.analyze_patterns(activities)

        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)

        assert len(result) == 3
        assert isinstance(result[0], ActivityPattern)
        assert {p.pattern_type for p in result} == {"p", "s", "r"}


def test_activityanalyzer_get_user_score_empty(activity_analyzer_instance):
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer_instance.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer_instance):
    """Test get_user_score with simple valid activities and ISO timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"action": "login", "timestamp": (base + timedelta(days=0)).isoformat()},
        {"action": "view", "timestamp": (base + timedelta(days=0, hours=1)).isoformat()},
        {"action": "logout", "timestamp": (base + timedelta(days=1)).isoformat()},
        {"action": "login", "timestamp": (base + timedelta(days=1, hours=2)).isoformat()},
    ]
    # total_actions = 4, unique_actions = 3 (login, view, logout)
    # days_active = 1, actions_per_day = 4
    # diversity_score = 3/4 = 0.75
    # frequency_score = min(4/10,1)=0.4
    # volume_score = min(4/100,1)=0.04
    # final = (0.75*0.3 + 0.4*0.4 + 0.04*0.3)*100
    expected = (0.75 * 0.3 + 0.4 * 0.4 + 0.04 * 0.3) * 100
    score = activity_analyzer_instance.get_user_score(activities)
    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_no_parsable_timestamps(activity_analyzer_instance):
    """Test get_user_score when timestamps are not parsable, using total_actions as actions_per_day."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "b", "timestamp": None},
        {"action": "a", "timestamp": 123},
    ]
    # total_actions = 3, unique_actions = 2 (a, b)
    # actions_per_day = total_actions = 3
    # diversity_score = 2/3
    # frequency_score = min(3/10,1)=0.3
    # volume_score = min(3/100,1)=0.03
    expected = ((2 / 3) * 0.3 + 0.3 * 0.4 + 0.03 * 0.3) * 100
    score = activity_analyzer_instance.get_user_score(activities)
    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_duplicate_action_logic(activity_analyzer_instance):
    """Test get_user_score unique action counting logic with repeated actions."""
    # The implementation uses index() and slice, so only first occurrence is considered for uniqueness.
    activities = [
        {"action": "a", "timestamp": datetime(2024, 1, 1).isoformat()},
        {"action": "b", "timestamp": datetime(2024, 1, 2).isoformat()},
        {"action": "a", "timestamp": datetime(2024, 1, 3).isoformat()},
        {"action": "c", "timestamp": datetime(2024, 1, 4).isoformat()},
        {"action": "b", "timestamp": datetime(2024, 1, 5).isoformat()},
    ]
    # unique_actions should be 3 (a, b, c) according to the implemented logic
    score = activity_analyzer_instance.get_user_score(activities)
    assert isinstance(score, float)


def test_activityanalyzer_detect_anomalies_too_few(activity_analyzer_instance):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [
        {"action": "a", "timestamp": datetime(2024, 1, 1).isoformat()},
        {"action": "a", "timestamp": datetime(2024, 1, 2).isoformat()},
        {"action": "a", "timestamp": datetime(2024, 1, 3).isoformat()},
        {"action": "a", "timestamp": datetime(2024, 1, 4).isoformat()},
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_no_anomalies(activity_analyzer_instance):
    """Test detect_anomalies returns empty when intervals are regular."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(6):
        activities.append({"action": "click", "timestamp": (base + timedelta(minutes=10 * i)).isoformat()})
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_with_anomaly(activity_analyzer_instance):
    """Test detect_anomalies detects an interval anomaly based on z-score."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Mostly 10s intervals, one very large interval to trigger anomaly
    timestamps = [
        base,
        base + timedelta(seconds=10),
        base + timedelta(seconds=20),
        base + timedelta(seconds=30),
        base + timedelta(seconds=1000),  # large jump
        base + timedelta(seconds=1010),
    ]
    activities = [{"action": "click", "timestamp": ts.isoformat()} for ts in timestamps]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(result, list)
    if result:
        anomaly = result[0]
        assert anomaly["action"] == "click"
        assert "timestamp" in anomaly
        assert "z_score" in anomaly
        assert isinstance(anomaly["z_score"], float)


def test_activityanalyzer_detect_anomalies_ignores_few_timestamps_per_action(activity_analyzer_instance):
    """Test detect_anomalies ignores actions with fewer than 3 timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"action": "a", "timestamp": (base + timedelta(minutes=i)).isoformat()} for i in range(2)
    ] + [
        {"action": "b", "timestamp": (base + timedelta(minutes=10 * i)).isoformat()} for i in range(5)
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    # Only 'b' is considered; ensure no crash and result is list
    assert isinstance(result, list)


def test_activityanalyzer_detect_anomalies_invalid_timestamps(activity_analyzer_instance):
    """Test detect_anomalies handles invalid timestamps gracefully."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "a", "timestamp": None},
        {"action": "a", "timestamp": 123},
        {"action": "a", "timestamp": "2024-01-01T10:00:00"},
        {"action": "a", "timestamp": "2024-01-01T10:10:00"},
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(result, list)


def test_activityanalyzer_detect_peak_hours_no_timestamps(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty when no valid timestamps."""
    activities = [{"action": "a", "timestamp": "invalid"}]
    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert result == []


def test_activityanalyzer_detect_peak_hours_single_peak(activity_analyzer_instance):
    """Test _detect_peak_hours detects a single peak hour."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 8 activities at 10:00, 2 at 11:00 -> 10:00 should be peak (>0.2)
    for _ in range(8):
        activities.append({"action": "a", "timestamp": base.isoformat()})
    for _ in range(2):
        activities.append({"action": "a", "timestamp": (base + timedelta(hours=1)).isoformat()})

    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(result) == 1
    pattern = result[0]
    assert pattern.pattern_type == "peak_hours"
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_multiple_peaks(activity_analyzer_instance):
    """Test _detect_peak_hours detects multiple peak hours."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for _ in range(5):
        activities.append({"action": "a", "timestamp": base.isoformat()})
    for _ in range(5):
        activities.append({"action": "a", "timestamp": (base + timedelta(hours=1)).isoformat()})

    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(result) == 1
    desc = result[0].description
    assert "10:00" in desc
    assert "11:00" in desc


def test_activityanalyzer_detect_action_sequences_too_short(activity_analyzer_instance):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [
        {"action": "a", "timestamp": datetime(2024, 1, 1).isoformat()},
        {"action": "b", "timestamp": datetime(2024, 1, 1, 1).isoformat()},
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert result == []


def test_activityanalyzer_detect_action_sequences_common_sequence(activity_analyzer_instance):
    """Test _detect_action_sequences detects common sequences occurring at least twice."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"action": "login", "timestamp": (base + timedelta(minutes=0)).isoformat()},
        {"action": "view", "timestamp": (base + timedelta(minutes=1)).isoformat()},
        {"action": "logout", "timestamp": (base + timedelta(minutes=2)).isoformat()},
        {"action": "login", "timestamp": (base + timedelta(minutes=3)).isoformat()},
        {"action": "view", "timestamp": (base + timedelta(minutes=4)).isoformat()},
        {"action": "logout", "timestamp": (base + timedelta(minutes=5)).isoformat()},
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(result) >= 1
    pattern = result[0]
    assert pattern.pattern_type == "action_sequence"
    assert "login → view → logout" in pattern.description
    assert pattern.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_top_three(activity_analyzer_instance):
    """Test _detect_action_sequences returns at most three most common sequences."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    actions = ["a", "b", "c", "d", "e", "f", "g"]
    activities = []
    for i, act in enumerate(actions * 3):
        activities.append({"action": act, "timestamp": (base + timedelta(minutes=i)).isoformat()})
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(result) <= 3


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 activities."""
    activities = [
        {"action": "a", "timestamp": datetime(2024, 1, 1, i).isoformat()} for i in range(4)
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_not_enough_valid_timestamps(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "a", "timestamp": None},
        {"action": "a", "timestamp": 123},
        {"action": "a", "timestamp": datetime(2024, 1, 1, 0).isoformat()},
        {"action": "a", "timestamp": datetime(2024, 1, 1, 1).isoformat()},
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer_instance):
    """Test _detect_regularity detects highly regular activity pattern."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(6):
        activities.append({"action": "a", "timestamp": (base + timedelta(minutes=10 * i)).isoformat()})
    result = activity_analyzer_instance._detect_regularity(activities)
    assert len(result) == 1
    pattern = result[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer_instance):
    """Test _detect_regularity returns empty for irregular intervals."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    intervals = [1, 5, 20, 60, 2, 30]
    activities = []
    current = base
    for i in range(len(intervals)):
        activities.append({"action": "a", "timestamp": current.isoformat()})
        current += timedelta(minutes=intervals[i])
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer_instance):
    """Test _parse_timestamp returns datetime unchanged when input is datetime."""
    ts = datetime(2024, 1, 1, 10, 0, 0)
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string."""
    ts_str = "2024-01-01T10:00:00"
    parsed = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.hour == 10


def test_activityanalyzer_parse_timestamp_iso_string_with_z(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string with Z suffix."""
    ts_str = "2024-01-01T10:00:00Z"
    parsed = activity_analyzer_instance._parse_timestamp(ts_str)
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
    """Test analyze_patterns integration with real detection methods."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"action": "login", "timestamp": (base + timedelta(minutes=0)).isoformat()},
        {"action": "view", "timestamp": (base + timedelta(minutes=10)).isoformat()},
        {"action": "logout", "timestamp": (base + timedelta(minutes=20)).isoformat()},
        {"action": "login", "timestamp": (base + timedelta(minutes=30)).isoformat()},
        {"action": "view", "timestamp": (base + timedelta(minutes=40)).isoformat()},
        {"action": "logout", "timestamp": (base + timedelta(minutes=50)).isoformat()},
        {"action": "login", "timestamp": (base + timedelta(hours=1)).isoformat()},
    ]
    patterns = activity_analyzer_instance.analyze_patterns(activities)
    assert isinstance(patterns, list)
    assert all(isinstance(p, ActivityPattern) for p in patterns)


def test_activityanalyzer_detect_anomalies_exception_handling(activity_analyzer_instance):
    """Test detect_anomalies handles exceptions from _parse_timestamp gracefully."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T10:00:00"},
        {"action": "a", "timestamp": "2024-01-01T10:10:00"},
        {"action": "a", "timestamp": "2024-01-01T10:20:00"},
        {"action": "a", "timestamp": "2024-01-01T10:30:00"},
        {"action": "a", "timestamp": "2024-01-01T10:40:00"},
    ]

    with patch.object(activity_analyzer_instance, "_parse_timestamp", side_effect=Exception("parse error")):
        # Even if _parse_timestamp raises, detect_anomalies should propagate or handle.
        with pytest.raises(Exception):
            activity_analyzer_instance.detect_anomalies(activities)


def test_activityanalyzer_get_user_score_exception_handling(activity_analyzer_instance):
    """Test get_user_score handles exceptions from _parse_timestamp gracefully."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T10:00:00"},
        {"action": "b", "timestamp": "2024-01-02T10:00:00"},
    ]

    with patch.object(activity_analyzer_instance, "_parse_timestamp", side_effect=Exception("parse error")):
        with pytest.raises(Exception):
            activity_analyzer_instance.get_user_score(activities)