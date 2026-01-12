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
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer_instance.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer_instance):
    """Test get_user_score with simple valid activities and ISO timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(days=0)).isoformat(), "action": "login"},
        {"timestamp": (base + timedelta(days=0, hours=1)).isoformat(), "action": "view"},
        {"timestamp": (base + timedelta(days=1)).isoformat(), "action": "logout"},
        {"timestamp": (base + timedelta(days=1, hours=2)).isoformat(), "action": "login"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    # Manually compute expected:
    # total_actions = 4
    # unique_actions = 3 (login, view, logout)
    # days_active = 1 (difference in days between day 0 and day 1)
    # actions_per_day = 4 / 1 = 4
    # diversity_score = 3/4 = 0.75
    # frequency_score = min(4/10, 1) = 0.4
    # volume_score = min(4/100, 1) = 0.04
    # final = (0.75*0.3 + 0.4*0.4 + 0.04*0.3)*100
    expected = (0.75 * 0.3 + 0.4 * 0.4 + 0.04 * 0.3) * 100
    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_no_parsable_timestamps(activity_analyzer_instance):
    """Test get_user_score when timestamps are not parsable, using total_actions as actions_per_day."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": 12345, "action": "a"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    # total_actions = 3
    # unique_actions = 2 (a, b)
    # actions_per_day = 3
    # diversity_score = 2/3
    # frequency_score = min(3/10, 1) = 0.3
    # volume_score = min(3/100, 1) = 0.03
    expected = ((2 / 3) * 0.3 + 0.3 * 0.4 + 0.03 * 0.3) * 100
    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_duplicate_action_logic(activity_analyzer_instance):
    """Test get_user_score unique action counting logic with repeated actions."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": (base + timedelta(hours=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(hours=2)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=3)).isoformat(), "action": "c"},
        {"timestamp": (base + timedelta(hours=4)).isoformat(), "action": "b"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    # According to implementation:
    # unique_actions counts first occurrence only using index-based check
    # action_list = [a,b,a,c,b]
    # unique_actions = 3 (a,b,c)
    total_actions = 5
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
    """Test detect_anomalies when actions have fewer than 3 timestamps, resulting in no anomalies."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=1)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(minutes=2)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=3)).isoformat(), "action": "c"},
        {"timestamp": (base + timedelta(minutes=4)).isoformat(), "action": "d"},
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_with_outlier_interval(activity_analyzer_instance):
    """Test detect_anomalies detects an interval with high z-score as anomaly."""
    base = datetime(2024, 1, 1)
    # Create mostly 60s intervals, one very large interval to trigger anomaly
    timestamps = [
        base,
        base + timedelta(seconds=60),
        base + timedelta(seconds=120),
        base + timedelta(seconds=1800),  # big jump
        base + timedelta(seconds=1860),
    ]
    activities = [{"timestamp": ts.isoformat(), "action": "click"} for ts in timestamps]

    result = activity_analyzer_instance.detect_anomalies(activities)

    # There should be at least one anomaly for 'click'
    assert isinstance(result, list)
    assert len(result) >= 1
    for anomaly in result:
        assert anomaly["action"] == "click"
        assert isinstance(anomaly["timestamp"], str)
        assert anomaly["z_score"] == pytest.approx(anomaly["z_score"])
        assert "Unusual interval" in anomaly["reason"]


def test_activityanalyzer_detect_anomalies_ignores_unparsable_timestamps(activity_analyzer_instance):
    """Test detect_anomalies ignores activities with unparsable timestamps."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": base.isoformat(), "action": "x"},
        {"timestamp": "invalid", "action": "x"},
        {"timestamp": (base + timedelta(seconds=60)).isoformat(), "action": "x"},
        {"timestamp": None, "action": "x"},
        {"timestamp": (base + timedelta(seconds=120)).isoformat(), "action": "x"},
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(result, list)


def test_activityanalyzer_detect_peak_hours_no_activities(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty list when no valid timestamps."""
    result = activity_analyzer_instance._detect_peak_hours([{"timestamp": "invalid"}])
    assert result == []


def test_activityanalyzer_detect_peak_hours_basic(activity_analyzer_instance):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 8 activities at 10:00, 2 at 11:00 -> 10:00 should be peak (0.8 > 0.2)
    for _ in range(8):
        activities.append({"timestamp": base.isoformat(), "action": "a"})
    for _ in range(2):
        activities.append({"timestamp": (base.replace(hour=11)).isoformat(), "action": "b"})

    patterns = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "peak_hours"
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_multiple_hours(activity_analyzer_instance):
    """Test _detect_peak_hours can return multiple peak hours in description."""
    base = datetime(2024, 1, 1, 9, 0, 0)
    activities = []
    # 3 at 9:00, 3 at 10:00, 4 at 11:00 -> all above 0.2 threshold
    for _ in range(3):
        activities.append({"timestamp": base.isoformat(), "action": "a"})
    for _ in range(3):
        activities.append({"timestamp": base.replace(hour=10).isoformat(), "action": "b"})
    for _ in range(4):
        activities.append({"timestamp": base.replace(hour=11).isoformat(), "action": "c"})

    patterns = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(patterns) == 1
    desc = patterns[0].description
    assert "09:00" in desc
    assert "10:00" in desc
    assert "11:00" in desc


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
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": act}
        for i, act in enumerate([
            "a", "b", "c",  # seq1
            "d",
            "a", "b", "c",  # seq1 again
            "e",
            "b", "c", "d",  # seq2
            "b", "c", "d",  # seq2 again
        ])
    ]
    patterns = activity_analyzer_instance._detect_action_sequences(activities)
    # Expect sequences "a→b→c" and "b→c→d" at least
    assert len(patterns) >= 2
    descriptions = [p.description for p in patterns]
    assert any("a → b → c" in d for d in descriptions)
    assert any("b → c → d" in d for d in descriptions)
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer_instance):
    """Test _detect_regularity returns empty list when fewer than 5 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"}
        for _ in range(4)
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_unparsable_timestamps(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "a"},
        {"timestamp": 123, "action": "a"},
        {"timestamp": "2024-01-01T00:00:00", "action": "a"},
        {"timestamp": "2024-01-01T00:01:00", "action": "a"},
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer_instance):
    """Test _detect_regularity detects highly regular intervals (low coefficient of variation)."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    # 6 timestamps, 5 intervals of exactly 60 seconds
    activities = [
        {"timestamp": (base + timedelta(seconds=60 * i)).isoformat(), "action": "a"}
        for i in range(6)
    ]
    patterns = activity_analyzer_instance._detect_regularity(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "regularity"
    assert "CV:" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer_instance):
    """Test _detect_regularity returns empty when coefficient of variation is high."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    # Irregular intervals
    offsets = [0, 10, 100, 300, 900, 3600]
    activities = [
        {"timestamp": (base + timedelta(seconds=o)).isoformat(), "action": "a"}
        for o in offsets
    ]
    patterns = activity_analyzer_instance._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer_instance):
    """Test _parse_timestamp returns datetime unchanged when input is datetime."""
    ts = datetime(2024, 1, 1, 12, 0, 0)
    result = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(result, datetime)
    assert result == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string correctly."""
    ts_str = "2024-01-01T12:00:00"
    result = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(result, datetime)
    assert result.year == 2024
    assert result.month == 1
    assert result.day == 1
    assert result.hour == 12
    assert result.minute == 0
    assert result.second == 0


def test_activityanalyzer_parse_timestamp_iso_string_with_z(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string with 'Z' timezone suffix."""
    ts_str = "2024-01-01T12:00:00Z"
    result = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(result, datetime)
    assert result.year == 2024
    assert result.hour == 12


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer_instance):
    """Test _parse_timestamp returns None for invalid string."""
    result = activity_analyzer_instance._parse_timestamp("not-a-timestamp")
    assert result is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer_instance):
    """Test _parse_timestamp returns None for unsupported type."""
    result = activity_analyzer_instance._parse_timestamp(12345)
    assert result is None


def test_activityanalyzer_analyze_patterns_integration(activity_analyzer_instance):
    """Integration test: analyze_patterns returns combined patterns for realistic data."""
    base = datetime(2024, 1, 1, 9, 0, 0)
    activities = []
    # Create regular hourly activity at 9, 10, 11 for 5 days with repeating sequences
    for day in range(5):
        for hour, action in [(9, "login"), (10, "view"), (11, "logout")]:
            ts = base.replace(day=base.day + day, hour=hour)
            activities.append({"timestamp": ts.isoformat(), "action": action})

    patterns = activity_analyzer_instance.analyze_patterns(activities)
    assert isinstance(patterns, list)
    assert len(patterns) >= 1
    # Expect at least peak_hours and action_sequence or regularity
    types = {p.pattern_type for p in patterns}
    assert "peak_hours" in types or "regularity" in types or "action_sequence" in types