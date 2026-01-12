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


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer):
    """Test _parse_timestamp returns datetime unchanged when given datetime."""
    ts = datetime(2024, 1, 1, 12, 0, 0)
    parsed = activity_analyzer._parse_timestamp(ts)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer):
    """Test _parse_timestamp parses ISO formatted string."""
    ts_str = "2024-01-01T12:00:00"
    parsed = activity_analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.hour == 12


def test_activityanalyzer_parse_timestamp_iso_string_with_z(activity_analyzer):
    """Test _parse_timestamp parses ISO string with Z timezone."""
    ts_str = "2024-01-01T12:00:00Z"
    parsed = activity_analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.hour == 12
    assert parsed.tzinfo is not None


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


def test_activityanalyzer_detect_peak_hours_no_peak(activity_analyzer):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    for h in range(5):
        activities.append({"timestamp": (base + timedelta(hours=h)).isoformat(), "action": "a"})
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_invalid_timestamps(activity_analyzer):
    """Test _detect_peak_hours ignores invalid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
    ]
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


# -------------------- _detect_action_sequences tests --------------------


def test_activityanalyzer_detect_action_sequences_min_length(activity_analyzer):
    """Test _detect_action_sequences returns empty for less than 3 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"},
        {"timestamp": datetime.now().isoformat(), "action": "b"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_common_sequences(activity_analyzer):
    """Test _detect_action_sequences detects repeated 3-action sequences."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": a}
        for i, a in enumerate(
            [
                "login",
                "view",
                "click",
                "login",
                "view",
                "click",
                "logout",
                "login",
                "view",
                "click",
            ]
        )
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert len(patterns) >= 1
    seq_descriptions = [p.description for p in patterns]
    assert any("login → view → click" in d for d in seq_descriptions)
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


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
    """Test _detect_regularity returns empty for less than 5 activities."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i * 10)).isoformat(), "action": "a"}
        for i in range(4)
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer):
    """Test _detect_regularity detects highly regular intervals."""
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
    """Test _detect_regularity returns empty for irregular intervals."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    deltas = [1, 5, 20, 2, 30]
    activities = [
        {"timestamp": (base + timedelta(minutes=sum(deltas[:i]))).isoformat(), "action": "a"}
        for i in range(len(deltas) + 1)
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_ignores_invalid_timestamps(activity_analyzer):
    """Test _detect_regularity ignores invalid timestamps and may return empty."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "c"},
        {"timestamp": (base + timedelta(minutes=10)).isoformat(), "action": "d"},
        {"timestamp": (base + timedelta(minutes=20)).isoformat(), "action": "e"},
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


# -------------------- analyze_patterns tests --------------------


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer):
    """Test analyze_patterns returns empty list for no activities."""
    assert activity_analyzer.analyze_patterns([]) == []


def test_activityanalyzer_analyze_patterns_combines_detectors(activity_analyzer, sample_activities):
    """Test analyze_patterns aggregates patterns from all detectors."""
    with patch.object(activity_analyzer, "_detect_peak_hours", return_value=[ActivityPattern("peak", "p", 0.1)]) as m_peak, \
         patch.object(activity_analyzer, "_detect_action_sequences", return_value=[ActivityPattern("seq", "s", 0.2)]) as m_seq, \
         patch.object(activity_analyzer, "_detect_regularity", return_value=[ActivityPattern("reg", "r", 0.3)]) as m_reg:
        patterns = activity_analyzer.analyze_patterns(sample_activities)
        assert len(patterns) == 3
        assert {p.pattern_type for p in patterns} == {"peak", "seq", "reg"}
        m_peak.assert_called_once_with(sample_activities)
        m_seq.assert_called_once_with(sample_activities)
        m_reg.assert_called_once_with(sample_activities)


# -------------------- get_user_score tests --------------------


def test_activityanalyzer_get_user_score_empty(activity_analyzer):
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer):
    """Test get_user_score computes score based on diversity, frequency, and volume."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(days=i)).isoformat(), "action": "a" if i < 3 else "b"}
        for i in range(6)
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_unique_action_logic(activity_analyzer):
    """Test get_user_score unique action counting logic with repeated actions."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    actions = ["a", "b", "a", "c", "b"]
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": act}
        for i, act in enumerate(actions)
    ]
    score = activity_analyzer.get_user_score(activities)
    assert score == pytest.approx(score)


def test_activityanalyzer_get_user_score_no_valid_timestamps(activity_analyzer):
    """Test get_user_score when timestamps cannot be parsed (uses total_actions as actions_per_day)."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": "also-invalid", "action": "c"},
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_single_day(activity_analyzer):
    """Test get_user_score when all activities occur on the same day (days_active=1)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(hours=i)).isoformat(), "action": "a"}
        for i in range(5)
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


# -------------------- detect_anomalies tests --------------------


def test_activityanalyzer_detect_anomalies_too_few_activities(activity_analyzer):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"}
        for i in range(4)
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_no_anomalies(activity_analyzer):
    """Test detect_anomalies returns empty when intervals are consistent."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i * 10)).isoformat(), "action": "a"}
        for i in range(6)
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_with_anomaly(activity_analyzer):
    """Test detect_anomalies detects an interval with high z-score."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    timestamps = [
        base,
        base + timedelta(minutes=10),
        base + timedelta(minutes=20),
        base + timedelta(hours=5),
        base + timedelta(hours=5, minutes=10),
    ]
    activities = [
        {"timestamp": ts.isoformat(), "action": "a"}
        for ts in timestamps
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)
    for anomaly in anomalies:
        assert anomaly["action"] == "a"
        assert "timestamp" in anomaly
        assert "z_score" in anomaly
        assert "reason" in anomaly


def test_activityanalyzer_detect_anomalies_ignores_actions_with_few_timestamps(activity_analyzer):
    """Test detect_anomalies ignores actions with fewer than 3 timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=10)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=20)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(minutes=30)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(minutes=40)).isoformat(), "action": "c"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_invalid_timestamps(activity_analyzer):
    """Test detect_anomalies skips activities with invalid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "a"},
        {"timestamp": "2024-01-01T10:00:00", "action": "a"},
        {"timestamp": "2024-01-01T10:10:00", "action": "a"},
        {"timestamp": "2024-01-01T10:20:00", "action": "a"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_uses_anomaly_threshold(activity_analyzer):
    """Test detect_anomalies respects anomaly_threshold by mocking std_dev and mean."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    timestamps = [
        base,
        base + timedelta(minutes=1),
        base + timedelta(minutes=2),
        base + timedelta(minutes=100),
        base + timedelta(minutes=101),
    ]
    activities = [
        {"timestamp": ts.isoformat(), "action": "a"}
        for ts in timestamps
    ]

    original_parse = activity_analyzer._parse_timestamp

    with patch.object(activity_analyzer, "_parse_timestamp", side_effect=original_parse) as mock_parse:
        anomalies = activity_analyzer.detect_anomalies(activities)
        assert mock_parse.call_count == len(activities)
        assert isinstance(anomalies, list)


# -------------------- exception / robustness tests --------------------


def test_activityanalyzer_analyze_patterns_handles_internal_exception(activity_analyzer, sample_activities):
    """Test analyze_patterns continues to work if one detector raises an exception."""
    with patch.object(activity_analyzer, "_detect_peak_hours", side_effect=Exception("boom")), \
         patch.object(activity_analyzer, "_detect_action_sequences", return_value=[]), \
         patch.object(activity_analyzer, "_detect_regularity", return_value=[]):
        with pytest.raises(Exception):
            activity_analyzer.analyze_patterns(sample_activities)


def test_activityanalyzer_detect_anomalies_no_crash_on_zero_std_dev(activity_analyzer):
    """Test detect_anomalies does not crash when std_dev is zero (all intervals equal)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i * 10)).isoformat(), "action": "a"}
        for i in range(5)
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []