import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing test timestamps."""
    return datetime(2023, 1, 1, 0, 0, 0)


def test_ActivityPattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict serialization."""
    pattern = ActivityPattern("peak_hours", "High activity at 10:00", 0.85)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "High activity at 10:00"
    assert pattern.confidence == 0.85

    as_dict = pattern.to_dict()
    assert as_dict == {
        "pattern_type": "peak_hours",
        "description": "High activity at 10:00",
        "confidence": 0.85,
    }


def test_ActivityAnalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default thresholds on initialization."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_ActivityAnalyzer_parse_timestamp_datetime_input(analyzer, base_time):
    """Test _parse_timestamp with a datetime object."""
    ts = analyzer._parse_timestamp(base_time)
    assert isinstance(ts, datetime)
    assert ts == base_time


def test_ActivityAnalyzer_parse_timestamp_iso_string_with_Z(analyzer):
    """Test _parse_timestamp with ISO 8601 string containing 'Z' suffix."""
    ts = analyzer._parse_timestamp("2023-01-01T12:34:56Z")
    # Expect timezone-aware datetime with +00:00 offset
    assert isinstance(ts, datetime)
    assert ts.tzinfo is not None
    assert ts.isoformat().endswith("+00:00")


def test_ActivityAnalyzer_parse_timestamp_iso_string_with_offset(analyzer):
    """Test _parse_timestamp with ISO 8601 string containing explicit offset."""
    ts = analyzer._parse_timestamp("2023-01-01T12:34:56+00:00")
    assert isinstance(ts, datetime)
    assert ts.tzinfo is not None
    assert ts.isoformat().endswith("+00:00")


def test_ActivityAnalyzer_parse_timestamp_invalid_string(analyzer):
    """Test _parse_timestamp with an invalid string returns None."""
    ts = analyzer._parse_timestamp("not-a-timestamp")
    assert ts is None


def test_ActivityAnalyzer_parse_timestamp_non_string(analyzer):
    """Test _parse_timestamp with unsupported type returns None."""
    ts = analyzer._parse_timestamp(12345)
    assert ts is None


def test_ActivityAnalyzer_detect_peak_hours_no_parsable_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when timestamps cannot be parsed."""
    activities = [{"action": "a", "timestamp": "invalid"} for _ in range(5)]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_ActivityAnalyzer_detect_peak_hours_threshold_exact_not_included(analyzer, base_time):
    """Test peak hour detection excludes hours at exactly the threshold ratio."""
    # 5 activities, each in different hour -> each ratio is 0.2, should not include any
    activities = [
        {"action": "a", "timestamp": base_time.replace(hour=h)} for h in range(5)
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_ActivityAnalyzer_detect_peak_hours_detects_multiple_hours(analyzer, base_time):
    """Test peak hour detection identifies hours exceeding the threshold."""
    # 10 activities, 3 at hour 10 (30%), 3 at hour 15 (30%), others spread
    activities = []
    activities += [{"action": "a", "timestamp": base_time.replace(hour=10)} for _ in range(3)]
    activities += [{"action": "b", "timestamp": base_time.replace(hour=15)} for _ in range(3)]
    activities += [{"action": "c", "timestamp": base_time.replace(hour=h)} for h in [0, 1, 2, 3]]
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    assert patterns[0].pattern_type == "peak_hours"
    assert "10:00" in patterns[0].description
    assert "15:00" in patterns[0].description


def test_ActivityAnalyzer_detect_action_sequences_insufficient_length(analyzer):
    """Test action sequence detection on fewer than 3 activities returns empty list."""
    activities = [{"action": "A", "timestamp": datetime(2023, 1, 1)}]
    assert analyzer._detect_action_sequences(activities) == []


def test_ActivityAnalyzer_detect_action_sequences_detects_common(analyzer, base_time):
    """Test action sequence detection identifies common sequences."""
    # Actions: A,B,C,D,A,B,C -> 'A,B,C' occurs twice
    actions = ["A", "B", "C", "D", "A", "B", "C"]
    activities = [
        {"action": act, "timestamp": base_time + timedelta(minutes=i)} for i, act in enumerate(actions)
    ]
    patterns = analyzer._detect_action_sequences(activities)
    assert any(p.pattern_type == "action_sequence" for p in patterns)
    assert any("Common sequence: A → B → C (occurred 2 times)" in p.description for p in patterns)


def test_ActivityAnalyzer_detect_regularity_insufficient_data(analyzer):
    """Test regularity detection requires at least 5 valid timestamps."""
    activities = [{"action": "a", "timestamp": datetime(2023, 1, 1, 0, i)} for i in range(4)]
    assert analyzer._detect_regularity(activities) == []


def test_ActivityAnalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """Test regularity detection identifies highly regular activity."""
    # 6 timestamps at 10-minute intervals -> very low CV
    activities = [
        {"action": "a", "timestamp": base_time + timedelta(minutes=10 * i)} for i in range(6)
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    assert patterns[0].pattern_type == "regularity"
    assert "Highly regular activity pattern" in patterns[0].description


def test_ActivityAnalyzer_detect_regularity_irregular(analyzer, base_time):
    """Test regularity detection does not flag irregular activity."""
    # Irregular intervals
    minutes = [0, 1, 5, 20, 22, 100]
    activities = [{"action": "a", "timestamp": base_time + timedelta(minutes=m)} for m in minutes]
    assert analyzer._detect_regularity(activities) == []


def test_ActivityAnalyzer_detect_anomalies_insufficient_activities(analyzer, base_time):
    """Test detect_anomalies returns empty when there are fewer than 5 total activities."""
    activities = [{"action": "click", "timestamp": base_time + timedelta(seconds=i)} for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_ActivityAnalyzer_detect_anomalies_no_std_dev(analyzer, base_time):
    """Test detect_anomalies returns empty when intervals have zero standard deviation."""
    # 5 identical intervals for action 'click'
    clicks = [
        {"action": "click", "timestamp": base_time + timedelta(seconds=10 * i)} for i in range(5)
    ]
    # Add some other actions with fewer than 3 occurrences to ensure they are ignored
    others = [{"action": "view", "timestamp": base_time + timedelta(seconds=3)}]
    activities = clicks + others
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_ActivityAnalyzer_detect_anomalies_detects_interval_anomaly(analyzer, base_time):
    """Test detect_anomalies identifies an outlier interval with z-score above threshold."""
    # Intervals: 10s, 10s, 1000s, 10s -> anomaly at third interval
    t0 = base_time
    t1 = t0 + timedelta(seconds=10)
    t2 = t1 + timedelta(seconds=10)
    t3 = t2 + timedelta(seconds=1000)  # anomalous longer interval
    t4 = t3 + timedelta(seconds=10)
    activities = [
        {"action": "click", "timestamp": t0},
        {"action": "click", "timestamp": t1},
        {"action": "click", "timestamp": t2},
        {"action": "click", "timestamp": t3},
        {"action": "click", "timestamp": t4},
    ]
    anomalies = analyzer.detect_anomalies(activities)
    # Expect at least one anomaly pointing to t3 (since anomaly is interval leading to t3)
    assert len(anomalies) >= 1
    found = next((a for a in anomalies if a["timestamp"] == t3.isoformat()), None)
    assert found is not None
    assert found["action"] == "click"
    assert found["z_score"] > analyzer.anomaly_threshold
    assert "Unusual interval" in found["reason"]


def test_ActivityAnalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list."""
    assert analyzer.get_user_score([]) == 0.0


def test_ActivityAnalyzer_get_user_score_computation(analyzer, base_time):
    """Test get_user_score computes diversity, frequency, and volume correctly."""
    # 20 actions in the same day, 4 unique actions repeated 5 times
    actions = ["A", "B", "C", "D"] * 5
    activities = [
        {"action": act, "timestamp": base_time + timedelta(minutes=i)} for i, act in enumerate(actions)
    ]
    # diversity = 4/20 = 0.2
    # frequency = min(20/1 / 10, 1) = 1.0
    # volume = min(20/100, 1) = 0.2
    # final = (0.2*0.3 + 1.0*0.4 + 0.2*0.3)*100 = 52.0
    score = analyzer.get_user_score(activities)
    assert score == 52.0


def test_ActivityAnalyzer_get_user_score_out_of_order_timestamps(analyzer, base_time):
    """Test get_user_score handles last timestamp earlier than first by clamping days to at least 1."""
    activities = [
        {"action": "A", "timestamp": base_time + timedelta(days=1)},  # first
        {"action": "B", "timestamp": base_time + timedelta(days=2)},
        {"action": "C", "timestamp": base_time + timedelta(days=3)},
        {"action": "D", "timestamp": base_time + timedelta(days=4)},
        {"action": "E", "timestamp": base_time},  # last is earlier
    ]
    # total=5, unique=5 => diversity=1.0
    # days_active clamped to 1 => actions_per_day=5 => frequency = 0.5
    # volume = 0.05
    # final = (1.0*0.3 + 0.5*0.4 + 0.05*0.3)*100 = 51.5
    score = analyzer.get_user_score(activities)
    assert score == 51.5


def test_ActivityAnalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for no activities."""
    assert analyzer.analyze_patterns([]) == []


def test_ActivityAnalyzer_analyze_patterns_calls_detectors_and_concatenates(analyzer):
    """Test analyze_patterns calls the detection methods and concatenates results in order."""
    mock_peak = [ActivityPattern("peak_hours", "peak", 0.1)]
    mock_seq = [ActivityPattern("action_sequence", "seq", 0.2)]
    mock_reg = [ActivityPattern("regularity", "reg", 0.3)]
    activities = [{"action": "a", "timestamp": datetime(2023, 1, 1)}]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)

        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)

        # Validate concatenation order
        types = [p.pattern_type for p in patterns]
        assert types == ["peak_hours", "action_sequence", "regularity"]


def test_ActivityAnalyzer_analyze_patterns_propagates_parse_exception(analyzer):
    """Test analyze_patterns propagates exceptions from _parse_timestamp."""
    activities = [{"action": "a", "timestamp": "2023-01-01T00:00:00"}]
    with patch.object(ActivityAnalyzer, "_parse_timestamp", side_effect=ValueError("parse error")):
        with pytest.raises(ValueError):
            analyzer.analyze_patterns(activities)