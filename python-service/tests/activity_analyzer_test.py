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
        {"action": "logout", "timestamp": (base + timedelta(minutes=15)).isoformat()},
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
    assert parsed is ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer):
    """Test _parse_timestamp parses ISO 8601 string correctly."""
    ts_str = "2024-01-01T12:00:00"
    parsed = activity_analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.month == 1
    assert parsed.day == 1
    assert parsed.hour == 12
    assert parsed.minute == 0
    assert parsed.second == 0


def test_activityanalyzer_parse_timestamp_with_z_suffix(activity_analyzer):
    """Test _parse_timestamp parses ISO string with Z suffix as UTC."""
    ts_str = "2024-01-01T12:00:00Z"
    parsed = activity_analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is not None
    assert parsed.hour == 12


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer):
    """Test _parse_timestamp returns None for invalid string."""
    ts_str = "not-a-timestamp"
    parsed = activity_analyzer._parse_timestamp(ts_str)
    assert parsed is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer):
    """Test _parse_timestamp returns None for unsupported type."""
    parsed = activity_analyzer._parse_timestamp(12345)
    assert parsed is None


# -------------------- _detect_peak_hours tests --------------------


def test_activityanalyzer_detect_peak_hours_basic(activity_analyzer):
    """Test _detect_peak_hours detects peak hours above threshold."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(8):
        activities.append({"timestamp": (base + timedelta(hours=0, minutes=i)).isoformat()})
    for i in range(2):
        activities.append({"timestamp": (base + timedelta(hours=1, minutes=i)).isoformat()})
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "peak_hours"
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_no_peak(activity_analyzer):
    """Test _detect_peak_hours returns empty list when no hour exceeds threshold."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    for h in range(5):
        activities.append({"timestamp": (base + timedelta(hours=h)).isoformat()})
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_invalid_timestamps(activity_analyzer):
    """Test _detect_peak_hours ignores activities with invalid timestamps."""
    activities = [
        {"timestamp": "invalid"},
        {"timestamp": None},
    ]
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


# -------------------- _detect_action_sequences tests --------------------


def test_activityanalyzer_detect_action_sequences_min_length(activity_analyzer):
    """Test _detect_action_sequences returns empty list when fewer than 3 activities."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T00:00:00"},
        {"action": "b", "timestamp": "2024-01-01T00:01:00"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_common_sequences(activity_analyzer):
    """Test _detect_action_sequences detects sequences occurring at least twice."""
    activities = [
        {"action": "a"},
        {"action": "b"},
        {"action": "c"},
        {"action": "a"},
        {"action": "b"},
        {"action": "c"},
        {"action": "d"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "action_sequence"
    assert "a → b → c" in pattern.description
    assert "(occurred 2 times)" in pattern.description
    assert pattern.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_uses_default_action(activity_analyzer):
    """Test _detect_action_sequences uses empty string when action key missing."""
    activities = [
        {},
        {"action": "x"},
        {"action": "y"},
        {},
        {"action": "x"},
        {"action": "y"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    assert " → x → y" in patterns[0].description


# -------------------- _detect_regularity tests --------------------


def test_activityanalyzer_detect_regularity_not_enough_activities(activity_analyzer):
    """Test _detect_regularity returns empty list when fewer than 5 activities."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat()} for i in range(4)
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_not_enough_valid_timestamps(activity_analyzer):
    """Test _detect_regularity returns empty list when fewer than 5 valid timestamps."""
    activities = [
        {"timestamp": "invalid"},
        {"timestamp": None},
        {"timestamp": "2024-01-01T00:00:00"},
        {"timestamp": "2024-01-01T00:01:00"},
        {"timestamp": "2024-01-01T00:02:00"},
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer):
    """Test _detect_regularity detects highly regular intervals (low CV)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=5 * i)).isoformat()} for i in range(6)
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer):
    """Test _detect_regularity returns empty list for irregular intervals."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    intervals = [1, 10, 30, 2, 45, 3]
    activities = []
    current = base
    for inc in intervals:
        current += timedelta(minutes=inc)
        activities.append({"timestamp": current.isoformat()})
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


# -------------------- detect_anomalies tests --------------------


def test_activityanalyzer_detect_anomalies_not_enough_activities(activity_analyzer):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T00:00:00"},
        {"action": "a", "timestamp": "2024-01-01T00:01:00"},
        {"action": "a", "timestamp": "2024-01-01T00:02:00"},
        {"action": "a", "timestamp": "2024-01-01T00:03:00"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_requires_min_timestamps_per_action(activity_analyzer):
    """Test detect_anomalies skips actions with fewer than 3 timestamps."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        {"action": "a", "timestamp": (base + timedelta(minutes=0)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(minutes=1)).isoformat()},
        {"action": "b", "timestamp": (base + timedelta(minutes=2)).isoformat()},
        {"action": "b", "timestamp": (base + timedelta(minutes=3)).isoformat()},
        {"action": "b", "timestamp": (base + timedelta(minutes=4)).isoformat()},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_detects_large_interval(activity_analyzer):
    """Test detect_anomalies flags intervals with z-score above threshold."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        {"action": "a", "timestamp": (base + timedelta(minutes=0)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(minutes=1)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(minutes=2)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(hours=10)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(hours=10, minutes=1)).isoformat()},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert len(anomalies) >= 1
    for anomaly in anomalies:
        assert anomaly["action"] == "a"
        assert "Unusual interval" in anomaly["reason"]
        assert isinstance(anomaly["z_score"], float)


def test_activityanalyzer_detect_anomalies_ignores_invalid_timestamps(activity_analyzer):
    """Test detect_anomalies ignores activities with invalid timestamps."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "a", "timestamp": None},
        {"action": "a", "timestamp": "2024-01-01T00:00:00"},
        {"action": "a", "timestamp": "2024-01-01T00:01:00"},
        {"action": "a", "timestamp": "2024-01-01T00:02:00"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


# -------------------- get_user_score tests --------------------


def test_activityanalyzer_get_user_score_empty(activity_analyzer):
    """Test get_user_score returns 0.0 for empty activities list."""
    score = activity_analyzer.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer):
    """Test get_user_score computes score based on diversity, frequency, and volume."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    for i in range(10):
        activities.append(
            {
                "action": "a" if i < 5 else "b",
                "timestamp": (base + timedelta(days=i)).isoformat(),
            }
        )
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_no_timestamps(activity_analyzer):
    """Test get_user_score when timestamps are missing or invalid uses total_actions as actions_per_day."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "b", "timestamp": None},
        {"action": "c"},
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_unique_action_logic(activity_analyzer):
    """Test get_user_score unique action counting logic based on implementation."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        {"action": "a", "timestamp": (base + timedelta(days=0)).isoformat()},
        {"action": "b", "timestamp": (base + timedelta(days=1)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(days=2)).isoformat()},
        {"action": "c", "timestamp": (base + timedelta(days=3)).isoformat()},
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_same_day(activity_analyzer):
    """Test get_user_score when all activities occur on the same day (days_active=1)."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        {"action": "a", "timestamp": (base + timedelta(hours=i)).isoformat()}
        for i in range(5)
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


# -------------------- analyze_patterns tests --------------------


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer):
    """Test analyze_patterns returns empty list for empty activities."""
    patterns = activity_analyzer.analyze_patterns([])
    assert patterns == []


def test_activityanalyzer_analyze_patterns_combines_detectors(activity_analyzer, sample_activities):
    """Test analyze_patterns combines results from all internal detectors."""
    with patch.object(
        activity_analyzer, "_detect_peak_hours", return_value=[ActivityPattern("peak_hours", "desc", 0.85)]
    ) as mock_peak, patch.object(
        activity_analyzer, "_detect_action_sequences", return_value=[ActivityPattern("action_sequence", "desc", 0.75)]
    ) as mock_seq, patch.object(
        activity_analyzer, "_detect_regularity", return_value=[ActivityPattern("regularity", "desc", 0.9)]
    ) as mock_reg:
        patterns = activity_analyzer.analyze_patterns(sample_activities)
        assert len(patterns) == 3
        mock_peak.assert_called_once_with(sample_activities)
        mock_seq.assert_called_once_with(sample_activities)
        mock_reg.assert_called_once_with(sample_activities)
        types = {p.pattern_type for p in patterns}
        assert types == {"peak_hours", "action_sequence", "regularity"}


def test_activityanalyzer_analyze_patterns_handles_internal_exceptions(activity_analyzer, sample_activities):
    """Test analyze_patterns propagates exceptions from internal detectors."""
    with patch.object(
        activity_analyzer, "_detect_peak_hours", side_effect=RuntimeError("failure")
    ):
        with pytest.raises(RuntimeError):
            activity_analyzer.analyze_patterns(sample_activities)


# -------------------- mocking and edge-case tests --------------------


def test_activityanalyzer_detect_anomalies_no_intervals(activity_analyzer):
    """Test detect_anomalies when all timestamps for an action are identical (no intervals)."""
    ts = "2024-01-01T00:00:00"
    activities = [
        {"action": "a", "timestamp": ts},
        {"action": "a", "timestamp": ts},
        {"action": "a", "timestamp": ts},
        {"action": "a", "timestamp": ts},
        {"action": "a", "timestamp": ts},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_zero_std_dev(activity_analyzer):
    """Test detect_anomalies when std_dev is zero (all intervals equal) results in no anomalies."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        {"action": "a", "timestamp": (base + timedelta(minutes=5 * i)).isoformat()}
        for i in range(5)
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_mock_zscore_threshold(activity_analyzer):
    """Test detect_anomalies behavior when anomaly_threshold is modified."""
    activity_analyzer.anomaly_threshold = 0.1
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        {"action": "a", "timestamp": (base + timedelta(minutes=0)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(minutes=1)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(minutes=2)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(hours=10)).isoformat()},
        {"action": "a", "timestamp": (base + timedelta(hours=10, minutes=1)).isoformat()},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert len(anomalies) >= 1


def test_activityanalyzer_detect_peak_hours_mock_parse_timestamp(activity_analyzer):
    """Test _detect_peak_hours with mocked _parse_timestamp to control hours."""
    activities = [{"timestamp": "dummy"} for _ in range(10)]

    def fake_parse(ts):
        return datetime(2024, 1, 1, 5, 0, 0)

    with patch.object(activity_analyzer, "_parse_timestamp", side_effect=fake_parse):
        patterns = activity_analyzer._detect_peak_hours(activities)
        assert len(patterns) == 1
        assert "05:00" in patterns[0].description


def test_activityanalyzer_detect_regularity_mock_parse_timestamp(activity_analyzer):
    """Test _detect_regularity with mocked _parse_timestamp to simulate regular intervals."""
    activities = [{"timestamp": "dummy"} for _ in range(6)]

    base = datetime(2024, 1, 1, 0, 0, 0)

    def fake_parse(ts):
        index = fake_parse.call_count
        fake_parse.call_count += 1
        return base + timedelta(minutes=10 * index)

    fake_parse.call_count = 0

    with patch.object(activity_analyzer, "_parse_timestamp", side_effect=fake_parse):
        patterns = activity_analyzer._detect_regularity(activities)
        assert len(patterns) == 1
        assert patterns[0].pattern_type == "regularity"


def test_activityanalyzer_get_user_score_mock_parse_timestamp_exception(activity_analyzer):
    """Test get_user_score handles exceptions from _parse_timestamp by treating timestamps as invalid."""
    activities = [
        {"action": "a", "timestamp": "bad1"},
        {"action": "b", "timestamp": "bad2"},
    ]

    with patch.object(activity_analyzer, "_parse_timestamp", side_effect=Exception("parse error")):
        score = activity_analyzer.get_user_score(activities)
        assert isinstance(score, float)
        assert 0.0 <= score <= 100.0


def test_activityanalyzer_detect_anomalies_mock_parse_timestamp_exception(activity_analyzer):
    """Test detect_anomalies handles exceptions from _parse_timestamp by skipping those entries."""
    activities = [
        {"action": "a", "timestamp": "bad1"},
        {"action": "a", "timestamp": "bad2"},
        {"action": "a", "timestamp": "bad3"},
        {"action": "a", "timestamp": "bad4"},
        {"action": "a", "timestamp": "bad5"},
    ]

    with patch.object(activity_analyzer, "_parse_timestamp", side_effect=Exception("parse error")):
        anomalies = activity_analyzer.detect_anomalies(activities)
        assert anomalies == []


def test_activityanalyzer_analyze_patterns_with_real_detectors(activity_analyzer):
    """Test analyze_patterns end-to-end with real detector implementations."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(10):
        activities.append(
            {
                "action": "a" if i % 2 == 0 else "b",
                "timestamp": (base + timedelta(hours=i)).isoformat(),
            }
        )
    patterns = activity_analyzer.analyze_patterns(activities)
    assert isinstance(patterns, list)
    for p in patterns:
        assert isinstance(p, ActivityPattern)
        assert isinstance(p.pattern_type, str)
        assert isinstance(p.description, str)
        assert isinstance(p.confidence, float) or isinstance(p.confidence, int)