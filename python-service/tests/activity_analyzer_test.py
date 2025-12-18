import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Provide an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing test timestamps."""
    return datetime(2023, 1, 1, 9, 0, 0)


def test_activitypattern_to_dict():
    """ActivityPattern.to_dict should serialize fields correctly."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="High activity", confidence=0.85)
    d = pattern.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "High activity"
    assert d["confidence"] == 0.85


def test_activityanalyzer_init_defaults(analyzer):
    """ActivityAnalyzer should initialize with expected default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_datetime(analyzer, base_time):
    """_parse_timestamp should return datetime as-is when given a datetime object."""
    ts = analyzer._parse_timestamp(base_time)
    assert isinstance(ts, datetime)
    assert ts == base_time


def test_activityanalyzer_parse_timestamp_isostring_z(analyzer, base_time):
    """_parse_timestamp should parse ISO string with 'Z' suffix into a datetime."""
    iso_str = (base_time.replace(hour=12)).isoformat() + "Z"
    ts = analyzer._parse_timestamp(iso_str)
    assert isinstance(ts, datetime)
    # Comparing isoformat after normalizing 'Z' to +00:00
    assert ts.isoformat().endswith("+00:00")


def test_activityanalyzer_parse_timestamp_invalid(analyzer):
    """_parse_timestamp should return None for invalid strings or types."""
    assert analyzer._parse_timestamp("not-a-timestamp") is None
    assert analyzer._parse_timestamp(None) is None
    class Dummy:
        pass
    assert analyzer._parse_timestamp(Dummy()) is None


def test_analyzer_analyze_patterns_empty_input_returns_empty(analyzer):
    """analyze_patterns should return empty list when given no activities."""
    assert analyzer.analyze_patterns([]) == []


def test_analyzer_analyze_patterns_aggregates_results_mocked(analyzer):
    """analyze_patterns should call internal detectors and aggregate their results."""
    activities = [{"action": "a", "timestamp": datetime(2023, 1, 1)}]
    mock_peak = [ActivityPattern("peak_hours", "peak", 0.85)]
    mock_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    mock_reg = [ActivityPattern("regularity", "reg", 0.9)]

    with patch.object(analyzer, "_detect_peak_hours", return_value=mock_peak) as m1, \
         patch.object(analyzer, "_detect_action_sequences", return_value=mock_seq) as m2, \
         patch.object(analyzer, "_detect_regularity", return_value=mock_reg) as m3:
        res = analyzer.analyze_patterns(activities)
        assert res == mock_peak + mock_seq + mock_reg
        m1.assert_called_once_with(activities)
        m2.assert_called_once_with(activities)
        m3.assert_called_once_with(activities)


def test_detect_peak_hours_basic_multiple_hours(analyzer, base_time):
    """_detect_peak_hours should identify hours exceeding threshold."""
    # Create 10 activities: hour 09 -> 3 events, hour 10 -> 3 events, others scattered
    activities = []
    for i in range(3):
        activities.append({"action": "x", "timestamp": base_time.replace(hour=9, minute=i)})
    for i in range(3):
        activities.append({"action": "x", "timestamp": base_time.replace(hour=10, minute=i)})
    activities += [
        {"action": "x", "timestamp": base_time.replace(hour=11)},
        {"action": "x", "timestamp": base_time.replace(hour=12)},
        {"action": "x", "timestamp": base_time.replace(hour=13)},
        {"action": "x", "timestamp": base_time.replace(hour=14)},
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "09:00" in p.description
    assert "10:00" in p.description
    assert p.confidence == 0.85


def test_detect_peak_hours_no_valid_timestamps(analyzer):
    """_detect_peak_hours should return empty list when timestamps are invalid."""
    activities = [{"action": "x", "timestamp": "invalid"} for _ in range(5)]
    assert analyzer._detect_peak_hours(activities) == []


def test_detect_action_sequences_common_sequence_detected(analyzer, base_time):
    """_detect_action_sequences should find a repeated 3-action sequence occurring at least twice."""
    # Build actions: A, B, C, A, B, C
    activities = []
    actions = ["A", "B", "C", "A", "B", "C"]
    for i, a in enumerate(actions):
        activities.append({"action": a, "timestamp": base_time + timedelta(minutes=i)})
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "A → B → C" in p.description
    assert "(occurred 2 times)" in p.description
    assert p.confidence == 0.75


def test_detect_action_sequences_insufficient_length(analyzer):
    """_detect_action_sequences should return empty for fewer than 3 activities."""
    activities = [{"action": "A", "timestamp": datetime(2023, 1, 1)}]
    assert analyzer._detect_action_sequences(activities) == []


def test_detect_regularity_highly_regular(analyzer, base_time):
    """_detect_regularity should detect highly regular intervals with low CV."""
    activities = []
    for i in range(6):
        activities.append({"action": "x", "timestamp": base_time + timedelta(seconds=i * 60)})
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV: 0.00" in p.description
    assert p.confidence == 0.9


def test_detect_regularity_irregular_or_insufficient(analyzer, base_time):
    """_detect_regularity should return empty for irregular intervals or insufficient valid timestamps."""
    # Irregular intervals
    irregular = [
        {"action": "x", "timestamp": base_time + timedelta(seconds=s)}
        for s in (0, 10, 50, 120, 300, 700)
    ]
    assert analyzer._detect_regularity(irregular) == []

    # Insufficient valid timestamps
    few = [{"action": "x", "timestamp": "invalid"} for _ in range(6)]
    assert analyzer._detect_regularity(few) == []


def test_get_user_score_no_activities_returns_0(analyzer):
    """get_user_score should return 0.0 when no activities are provided."""
    assert analyzer.get_user_score([]) == 0.0


def test_get_user_score_same_day_high_frequency(analyzer, base_time):
    """get_user_score should compute correct score when all actions occur same day."""
    # 10 actions in the same day -> actions_per_day = 10 => frequency_score = 1.0
    # unique actions: 5 unique out of 10 -> diversity = 0.5
    # volume = 10/100 = 0.1
    # final = (0.5*0.3 + 1.0*0.4 + 0.1*0.3)*100 = 58.0
    actions = ["a", "b", "c", "d", "e"] * 2
    activities = [
        {"action": a, "timestamp": base_time + timedelta(minutes=i)} for i, a in enumerate(actions)
    ]
    score = analyzer.get_user_score(activities)
    assert score == 58.0


def test_get_user_score_invalid_timestamps_frequency_uses_total_actions(analyzer):
    """get_user_score should fall back to total actions for frequency when timestamps are invalid."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "b", "timestamp": "not-a-date"},
        {"action": "a", "timestamp": None},
    ]
    # diversity = 2/3, frequency = 3/10 = 0.3, volume = 3/100 = 0.03
    # final = (0.6667*0.3 + 0.3*0.4 + 0.03*0.3)*100 ≈ 32.9
    score = analyzer.get_user_score(activities)
    assert score == 32.9


def test_detect_anomalies_insufficient_data_returns_empty(analyzer, base_time):
    """detect_anomalies should return empty list when fewer than 5 activities are provided."""
    activities = [{"action": "x", "timestamp": base_time + timedelta(seconds=i*10)} for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_detect_anomalies_detects_large_interval_outlier(analyzer, base_time):
    """detect_anomalies should flag intervals with a z-score above threshold."""
    # Construct 12 timestamps for one action: 10 intervals of 10s, then one large interval
    # z-score for the outlier approximates sqrt(10) ~ 3.16 > 3.0
    activities = []
    current = base_time
    activities.append({"action": "ping", "timestamp": current})
    for _ in range(10):
        current = current + timedelta(seconds=10)
        activities.append({"action": "ping", "timestamp": current})
    # Large interval
    current = current + timedelta(seconds=1000)
    activities.append({"action": "ping", "timestamp": current})

    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) == 1
    anom = anomalies[0]
    assert anom["action"] == "ping"
    assert "Unusual interval" in anom["reason"]
    assert float(anom["z_score"]) >= 3.0
    # The anomaly timestamp should be the last timestamp (end of the large interval)
    assert anom["timestamp"] == current.isoformat()