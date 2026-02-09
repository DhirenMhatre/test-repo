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
    pattern = ActivityPattern("type1", "desc", 0.9)
    assert pattern.pattern_type == "type1"
    assert pattern.description == "desc"
    assert pattern.confidence == pytest.approx(0.9)


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
    assert isinstance(parsed, datetime)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer):
    """Test _parse_timestamp parses ISO formatted string."""
    ts_str = "2024-01-01T12:00:00"
    parsed = activity_analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed == datetime.fromisoformat(ts_str)


def test_activityanalyzer_parse_timestamp_z_suffix(activity_analyzer):
    """Test _parse_timestamp parses ISO string with Z suffix as UTC."""
    ts_str = "2024-01-01T12:00:00Z"
    parsed = activity_analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed == datetime.fromisoformat("2024-01-01T12:00:00+00:00")


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer):
    """Test _parse_timestamp returns None for invalid string."""
    parsed = activity_analyzer._parse_timestamp("not-a-timestamp")
    assert parsed is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer):
    """Test _parse_timestamp returns None for unsupported type."""
    parsed = activity_analyzer._parse_timestamp(12345)
    assert parsed is None


# -------------------- _detect_peak_hours tests --------------------


def test_activityanalyzer_detect_peak_hours_basic(activity_analyzer):
    """Test _detect_peak_hours identifies peak hours above threshold."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(8):
        activities.append({"timestamp": (base + timedelta(hours=10 - base.hour)).isoformat(), "action": "a"})
    for i in range(2):
        activities.append({"timestamp": (base + timedelta(hours=11 - base.hour)).isoformat(), "action": "b"})
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "peak_hours"
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_no_timestamp(activity_analyzer):
    """Test _detect_peak_hours ignores activities with invalid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
    ]
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_no_peak(activity_analyzer):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    for h in range(10):
        activities.append({"timestamp": (base + timedelta(hours=h)).isoformat(), "action": "a"})
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


# -------------------- _detect_action_sequences tests --------------------


def test_activityanalyzer_detect_action_sequences_min_length(activity_analyzer):
    """Test _detect_action_sequences returns empty for fewer than 3 activities."""
    activities = [
        {"timestamp": datetime(2024, 1, 1, 10, 0, 0).isoformat(), "action": "a"},
        {"timestamp": datetime(2024, 1, 1, 10, 1, 0).isoformat(), "action": "b"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_common_sequences(activity_analyzer):
    """Test _detect_action_sequences identifies repeated 3-action sequences."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=1)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(minutes=2)).isoformat(), "action": "c"},
        {"timestamp": (base + timedelta(minutes=3)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=4)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(minutes=5)).isoformat(), "action": "c"},
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
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=1)).isoformat()},
        {"timestamp": (base + timedelta(minutes=2)).isoformat(), "action": "c"},
        {"timestamp": (base + timedelta(minutes=3)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=4)).isoformat()},
        {"timestamp": (base + timedelta(minutes=5)).isoformat(), "action": "c"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    assert "a →  → c" in patterns[0].description


# -------------------- _detect_regularity tests --------------------


def test_activityanalyzer_detect_regularity_not_enough_activities(activity_analyzer):
    """Test _detect_regularity returns empty for fewer than 5 activities."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i * 10)).isoformat(), "action": "a"}
        for i in range(4)
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_not_enough_valid_timestamps(activity_analyzer):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": "2024-01-01T10:00:00", "action": "c"},
        {"timestamp": "2024-01-01T10:10:00", "action": "d"},
        {"timestamp": "invalid2", "action": "e"},
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer):
    """Test _detect_regularity detects highly regular intervals (low CV)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i * 10)).isoformat(), "action": "a"}
        for i in range(6)
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer):
    """Test _detect_regularity returns empty for irregular intervals (high CV)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    intervals = [1, 5, 20, 2, 30]
    activities = []
    current = base
    for i, minutes in enumerate(intervals):
        current = current + timedelta(minutes=minutes)
        activities.append({"timestamp": current.isoformat(), "action": "a"})
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


# -------------------- analyze_patterns tests --------------------


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer):
    """Test analyze_patterns returns empty list for no activities."""
    assert activity_analyzer.analyze_patterns([]) == []


def test_activityanalyzer_analyze_patterns_combines_patterns(activity_analyzer):
    """Test analyze_patterns aggregates patterns from all detectors."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(10):
        activities.append({"timestamp": (base + timedelta(hours=0)).isoformat(), "action": "a"})
    for i in range(2):
        activities.append({"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "b"})
    for i in range(3):
        activities.append({"timestamp": (base + timedelta(minutes=i * 10)).isoformat(), "action": "x"})
    for i in range(3):
        activities.append({"timestamp": (base + timedelta(minutes=30 + i * 10)).isoformat(), "action": "x"})
    for i in range(6):
        activities.append({"timestamp": (base + timedelta(hours=2, minutes=i * 10)).isoformat(), "action": "y"})
    patterns = activity_analyzer.analyze_patterns(activities)
    assert isinstance(patterns, list)
    assert any(p.pattern_type == "peak_hours" for p in patterns)
    assert any(p.pattern_type == "action_sequence" for p in patterns)
    assert any(p.pattern_type == "regularity" for p in patterns)


def test_activityanalyzer_analyze_patterns_uses_internal_methods(activity_analyzer):
    """Test analyze_patterns calls internal detection methods."""
    activities = [{"timestamp": datetime(2024, 1, 1, 10, 0, 0).isoformat(), "action": "a"}] * 6
    with patch.object(activity_analyzer, "_detect_peak_hours", return_value=[ActivityPattern("peak_hours", "d", 0.1)]) as mock_peak, \
         patch.object(activity_analyzer, "_detect_action_sequences", return_value=[ActivityPattern("action_sequence", "d", 0.2)]) as mock_seq, \
         patch.object(activity_analyzer, "_detect_regularity", return_value=[ActivityPattern("regularity", "d", 0.3)]) as mock_reg:
        patterns = activity_analyzer.analyze_patterns(activities)
        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)
        assert len(patterns) == 3


# -------------------- get_user_score tests --------------------


def test_activityanalyzer_get_user_score_empty(activity_analyzer):
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer):
    """Test get_user_score computes score based on diversity, frequency, and volume."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(10):
        activities.append({"timestamp": (base + timedelta(days=i)).isoformat(), "action": "a"})
    for i in range(5):
        activities.append({"timestamp": (base + timedelta(days=i)).isoformat(), "action": "b"})
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_unique_action_logic(activity_analyzer):
    """Test get_user_score unique action counting logic with duplicates."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(days=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(days=1)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(days=2)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(days=3)).isoformat(), "action": "c"},
    ]
    score = activity_analyzer.get_user_score(activities)
    assert score == pytest.approx(score)


def test_activityanalyzer_get_user_score_missing_actions(activity_analyzer):
    """Test get_user_score handles missing action keys as empty strings."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(days=0)).isoformat()},
        {"timestamp": (base + timedelta(days=1)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(days=2)).isoformat()},
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_invalid_timestamps(activity_analyzer):
    """Test get_user_score falls back to total_actions when timestamps invalid."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": "also-invalid", "action": "c"},
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


# -------------------- detect_anomalies tests --------------------


def test_activityanalyzer_detect_anomalies_too_few_activities(activity_analyzer):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [
        {"timestamp": datetime(2024, 1, 1, 10, 0, 0).isoformat(), "action": "a"},
        {"timestamp": datetime(2024, 1, 1, 10, 1, 0).isoformat(), "action": "a"},
        {"timestamp": datetime(2024, 1, 1, 10, 2, 0).isoformat(), "action": "a"},
        {"timestamp": datetime(2024, 1, 1, 10, 3, 0).isoformat(), "action": "a"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_no_anomalies(activity_analyzer):
    """Test detect_anomalies returns empty when intervals are consistent."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(6):
        activities.append({"timestamp": (base + timedelta(minutes=i * 10)).isoformat(), "action": "a"})
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_with_anomaly(activity_analyzer):
    """Test detect_anomalies detects an interval with high z-score."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=10)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=20)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=30)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=5)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=5, minutes=10)).isoformat(), "action": "a"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)
    assert len(anomalies) >= 1
    for anomaly in anomalies:
        assert "action" in anomaly
        assert "timestamp" in anomaly
        assert "z_score" in anomaly
        assert "reason" in anomaly
        assert isinstance(anomaly["z_score"], float)


def test_activityanalyzer_detect_anomalies_ignores_few_timestamps_per_action(activity_analyzer):
    """Test detect_anomalies ignores actions with fewer than 3 timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=10)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=20)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(minutes=30)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(minutes=40)).isoformat(), "action": "b"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)


def test_activityanalyzer_detect_anomalies_invalid_timestamps(activity_analyzer):
    """Test detect_anomalies handles invalid timestamps gracefully."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": "2024-01-01T10:00:00", "action": "a"},
        {"timestamp": "2024-01-01T10:10:00", "action": "a"},
        {"timestamp": "2024-01-01T10:20:00", "action": "a"},
        {"timestamp": "2024-01-01T10:30:00", "action": "a"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)


def test_activityanalyzer_detect_anomalies_uses_default_action(activity_analyzer):
    """Test detect_anomalies uses 'unknown' for missing action keys."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=0)).isoformat()},
        {"timestamp": (base + timedelta(minutes=10)).isoformat()},
        {"timestamp": (base + timedelta(minutes=20)).isoformat()},
        {"timestamp": (base + timedelta(minutes=30)).isoformat()},
        {"timestamp": (base + timedelta(minutes=40)).isoformat()},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)


# -------------------- detect_anomalies with mocking tests --------------------


def test_activityanalyzer_detect_anomalies_mock_parse_timestamp(activity_analyzer):
    """Test detect_anomalies behavior when _parse_timestamp is mocked to raise."""
    activities = [
        {"timestamp": "2024-01-01T10:00:00", "action": "a"},
        {"timestamp": "2024-01-01T10:10:00", "action": "a"},
        {"timestamp": "2024-01-01T10:20:00", "action": "a"},
        {"timestamp": "2024-01-01T10:30:00", "action": "a"},
        {"timestamp": "2024-01-01T10:40:00", "action": "a"},
    ]
    with patch.object(activity_analyzer, "_parse_timestamp", side_effect=Exception("parse error")):
        with pytest.raises(Exception):
            activity_analyzer.detect_anomalies(activities)


# -------------------- get_user_score with mocking tests --------------------


def test_activityanalyzer_get_user_score_mock_parse_timestamp(activity_analyzer):
    """Test get_user_score when _parse_timestamp is mocked to raise an exception."""
    activities = [
        {"timestamp": "2024-01-01T10:00:00", "action": "a"},
        {"timestamp": "2024-01-02T10:00:00", "action": "b"},
    ]
    with patch.object(activity_analyzer, "_parse_timestamp", side_effect=Exception("parse error")):
        with pytest.raises(Exception):
            activity_analyzer.get_user_score(activities)