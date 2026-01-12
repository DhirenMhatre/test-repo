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
    # fromisoformat with +00:00 creates aware datetime
    expected = datetime.fromisoformat("2024-01-01T12:00:00+00:00")
    assert parsed == expected


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
    """Test analyze_patterns returns empty list for no activities."""
    assert activity_analyzer.analyze_patterns([]) == []


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
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer):
    """Test get_user_score computes score based on diversity, frequency, and volume."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(days=i)).isoformat(), "action": "a" if i % 2 == 0 else "b"}
        for i in range(10)
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_no_timestamps(activity_analyzer):
    """Test get_user_score when timestamps are missing or invalid uses total_actions for frequency."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"action": "c"},
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_unique_action_logic(activity_analyzer):
    """Test get_user_score unique action counting logic with repeated actions."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(hours=i)).isoformat(), "action": a}
        for i, a in enumerate(["x", "y", "x", "z", "y"])
    ]
    # According to implementation, unique_actions is number of first occurrences
    # of each action in order: x, y, z => 3
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


def test_activityanalyzer_get_user_score_single_day(activity_analyzer):
    """Test get_user_score when all activities occur on the same day (days_active=1)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=5 * i)).isoformat(), "action": "a"}
        for i in range(20)
    ]
    score = activity_analyzer.get_user_score(activities)
    assert isinstance(score, float)
    assert 0.0 <= score <= 100.0


# -------------------- detect_anomalies tests --------------------


def test_activityanalyzer_detect_anomalies_too_few_activities(activity_analyzer):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_no_anomalies(activity_analyzer):
    """Test detect_anomalies returns empty list when intervals are regular."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    for i in range(6):
        activities.append({"timestamp": (base + timedelta(minutes=10 * i)).isoformat(), "action": "a"})
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_with_anomaly(activity_analyzer):
    """Test detect_anomalies detects an interval with high z-score as anomaly."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Regular 10-minute intervals, then a large gap to create anomaly
    timestamps = [
        base,
        base + timedelta(minutes=10),
        base + timedelta(minutes=20),
        base + timedelta(minutes=30),
        base + timedelta(hours=3),  # big gap
        base + timedelta(hours=3, minutes=10),
    ]
    activities = [{"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)
    # Depending on z-score, at least one anomaly is expected
    assert len(anomalies) >= 1
    for anomaly in anomalies:
        assert anomaly["action"] == "a"
        assert "timestamp" in anomaly
        assert "z_score" in anomaly
        assert "reason" in anomaly
        assert isinstance(anomaly["z_score"], float)


def test_activityanalyzer_detect_anomalies_ignores_actions_with_few_timestamps(activity_analyzer):
    """Test detect_anomalies ignores actions with fewer than 3 timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"} for i in range(3)
    ]
    # Add other actions with only 2 occurrences
    activities += [
        {"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(hours=2)).isoformat(), "action": "b"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_invalid_timestamps(activity_analyzer):
    """Test detect_anomalies skips activities with invalid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "a"},
        {"timestamp": 12345, "action": "a"},
        {"timestamp": datetime(2024, 1, 1, 10, 0, 0).isoformat(), "action": "a"},
        {"timestamp": datetime(2024, 1, 1, 10, 10, 0).isoformat(), "action": "a"},
        {"timestamp": datetime(2024, 1, 1, 10, 20, 0).isoformat(), "action": "a"},
    ]
    anomalies = activity_analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)


# -------------------- _detect_peak_hours tests --------------------


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(activity_analyzer):
    """Test _detect_peak_hours returns empty list when no valid timestamps."""
    activities = [{"timestamp": "invalid", "action": "a"} for _ in range(5)]
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_below_threshold(activity_analyzer):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    # Spread evenly across 5 hours so none exceeds 20%
    for i in range(10):
        ts = base + timedelta(hours=i % 5)
        activities.append({"timestamp": ts.isoformat(), "action": "a"})
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_above_threshold(activity_analyzer):
    """Test _detect_peak_hours identifies peak hours correctly."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 8 activities at 10:00, 2 at 11:00 -> hour 10 has 80% > 0.2
    for _ in range(8):
        activities.append({"timestamp": base.isoformat(), "action": "a"})
    for _ in range(2):
        activities.append({"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "b"})
    patterns = activity_analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "peak_hours"
    assert "High activity during hours" in pattern.description
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


# -------------------- _detect_action_sequences tests --------------------


def test_activityanalyzer_detect_action_sequences_too_short(activity_analyzer):
    """Test _detect_action_sequences returns empty list when fewer than 3 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"},
        {"timestamp": datetime.now().isoformat(), "action": "b"},
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_no_repeats(activity_analyzer):
    """Test _detect_action_sequences returns empty when no sequence repeats at least twice."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    actions = ["a", "b", "c", "d", "e"]
    activities = [
        {"timestamp": (base + timedelta(minutes=5 * i)).isoformat(), "action": act}
        for i, act in enumerate(actions)
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_with_repeats(activity_analyzer):
    """Test _detect_action_sequences identifies common sequences occurring at least twice."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    actions = ["a", "b", "c", "a", "b", "c", "d"]
    activities = [
        {"timestamp": (base + timedelta(minutes=5 * i)).isoformat(), "action": act}
        for i, act in enumerate(actions)
    ]
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert len(patterns) >= 1
    seq_pattern = patterns[0]
    assert seq_pattern.pattern_type == "action_sequence"
    assert "Common sequence" in seq_pattern.description
    assert "a → b → c" in seq_pattern.description
    assert "(occurred 2 times)" in seq_pattern.description
    assert seq_pattern.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_uses_default_action(activity_analyzer):
    """Test _detect_action_sequences uses empty string when action key is missing."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=5 * i)).isoformat()} for i in range(6)
    ]
    # All actions default to '', so sequence ('', '', '') repeats multiple times
    patterns = activity_analyzer._detect_action_sequences(activities)
    assert len(patterns) >= 1
    assert patterns[0].pattern_type == "action_sequence"


# -------------------- _detect_regularity tests --------------------


def test_activityanalyzer_detect_regularity_too_few_activities(activity_analyzer):
    """Test _detect_regularity returns empty list when fewer than 5 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_insufficient_valid_timestamps(activity_analyzer):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "a"},
        {"timestamp": 123, "action": "a"},
        {"timestamp": datetime.now().isoformat(), "action": "a"},
        {"timestamp": datetime.now().isoformat(), "action": "a"},
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer):
    """Test _detect_regularity detects highly regular intervals (low coefficient of variation)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
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
    """Test _detect_regularity returns empty when activity is irregular (high coefficient of variation)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    intervals = [5, 15, 30, 60, 120]  # highly variable
    timestamps = [base]
    for minutes in intervals:
        timestamps.append(timestamps[-1] + timedelta(minutes=minutes))
    activities = [
        {"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps
    ]
    patterns = activity_analyzer._detect_regularity(activities)
    assert patterns == []


# -------------------- analyze_patterns integration behavior --------------------


def test_activityanalyzer_analyze_patterns_integration(activity_analyzer):
    """Test analyze_patterns returns combined patterns from all detectors."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # Create data that should trigger peak hours, sequences, and regularity
    for i in range(10):
        activities.append(
            {"timestamp": (base + timedelta(minutes=10 * i)).isoformat(), "action": "a" if i % 3 else "b"}
        )
    patterns = activity_analyzer.analyze_patterns(activities)
    assert isinstance(patterns, list)
    assert all(isinstance(p, ActivityPattern) for p in patterns)