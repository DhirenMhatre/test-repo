import pytest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide an ActivityAnalyzer instance."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing activity timestamps."""
    return datetime(2023, 1, 1, 0, 0, 0)


def make_activity(ts, action="act"):
    """Helper to create an activity dict."""
    return {"timestamp": ts, "action": action}


def test_activitypattern_initialization_and_to_dict():
    """Test ActivityPattern initialization and to_dict output."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="High activity", confidence=0.85)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "High activity"
    assert pattern.confidence == pytest.approx(0.85)

    d = pattern.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "High activity"
    assert d["confidence"] == pytest.approx(0.85)


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default thresholds."""
    assert analyzer.peak_hour_threshold == pytest.approx(0.2)
    assert analyzer.anomaly_threshold == pytest.approx(3.0)


def test_activityanalyzer_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp with datetime, ISO string, Z suffix, and invalid inputs."""
    dt = datetime(2021, 1, 1, 12, 0, 0)
    assert analyzer._parse_timestamp(dt) == dt

    iso_str = "2021-01-01T12:00:00"
    parsed = analyzer._parse_timestamp(iso_str)
    assert isinstance(parsed, datetime)
    # naive datetime expected for ISO without timezone
    assert parsed.tzinfo is None
    assert parsed == datetime(2021, 1, 1, 12, 0, 0)

    iso_z = "2021-01-01T12:00:00Z"
    parsed_z = analyzer._parse_timestamp(iso_z)
    assert isinstance(parsed_z, datetime)
    assert parsed_z.tzinfo is not None
    assert parsed_z.utcoffset() == timedelta(0)

    invalid = "not-a-date"
    assert analyzer._parse_timestamp(invalid) is None

    assert analyzer._parse_timestamp(12345) is None


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities."""
    assert analyzer.get_user_score([]) == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(analyzer, base_time):
    """Test get_user_score with valid sequential timestamps within one day."""
    activities = [make_activity(base_time + timedelta(minutes=i), action="a") for i in range(10)]
    # diversity_score = 1.0 due to code logic
    # actions_per_day = total_actions = 10 -> frequency_score = 1.0
    # volume_score = 10/100 = 0.1
    # final = (0.3 + 0.4*1.0 + 0.3*0.1)*100 = 73.0
    score = analyzer.get_user_score(activities)
    assert score == pytest.approx(73.0)


def test_activityanalyzer_get_user_score_invalid_timestamps(analyzer):
    """Test get_user_score when timestamps are invalid strings (frequency uses total actions)."""
    activities = [
        {"timestamp": "bad1", "action": "x"},
        {"timestamp": "bad2", "action": "x"},
        {"timestamp": "bad3", "action": "x"},
    ]
    # diversity_score = 1.0
    # actions_per_day = total_actions = 3 -> frequency_score = 0.3
    # volume_score = 0.03
    # final = (0.3 + 0.4*0.3 + 0.3*0.03)*100 = 42.9
    score = analyzer.get_user_score(activities)
    assert score == pytest.approx(42.9)


def test_activityanalyzer_analyze_patterns_empty_does_not_call_helpers(analyzer):
    """Test analyze_patterns returns empty list and does not call helper detectors for empty input."""
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", autospec=True) as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", autospec=True) as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", autospec=True) as mock_reg:
        result = analyzer.analyze_patterns([])
        assert result == []
        mock_peak.assert_not_called()
        mock_seq.assert_not_called()
        mock_reg.assert_not_called()


def test_activityanalyzer_analyze_patterns_combines_results(analyzer, base_time):
    """Test analyze_patterns combines results from helper detection methods in order."""
    peak = ActivityPattern("peak_hours", "peak", 0.8)
    seq = ActivityPattern("action_sequence", "seq", 0.7)
    reg = ActivityPattern("regularity", "reg", 0.9)

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[peak]) as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[seq]) as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[reg]) as mock_reg:
        acts = [make_activity(base_time, "a")]
        result = analyzer.analyze_patterns(acts)
        assert result == [peak, seq, reg]
        mock_peak.assert_called_once_with(acts)
        mock_seq.assert_called_once_with(acts)
        mock_reg.assert_called_once_with(acts)


def test_detect_peak_hours_threshold_boundary(analyzer, base_time):
    """Test _detect_peak_hours does not include hours at exactly the threshold (not strictly greater)."""
    # 5 activities in 5 different hours -> each is 0.2 fraction, should not trigger
    activities = [
        make_activity(base_time.replace(hour=h)) for h in [0, 1, 2, 3, 4]
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_detect_peak_hours_detects_multiple_hours(analyzer, base_time):
    """Test _detect_peak_hours identifies multiple hours exceeding the threshold."""
    activities = []
    # 4 at 05:00
    activities.extend([make_activity(base_time.replace(hour=5, minute=i)) for i in range(4)])
    # 3 at 10:00
    activities.extend([make_activity(base_time.replace(hour=10, minute=i)) for i in range(3)])
    # 3 at 11:00
    activities.extend([make_activity(base_time.replace(hour=11, minute=i)) for i in range(3)])

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "peak_hours"
    assert "High activity during hours: 05:00, 10:00, 11:00" == pat.description
    assert pat.confidence == pytest.approx(0.85)


def test_detect_action_sequences_common(analyzer, base_time):
    """Test _detect_action_sequences identifies a common sequence occurring at least twice."""
    actions = ["A", "B", "C", "A", "B", "C", "D"]
    activities = [make_activity(base_time + timedelta(minutes=i), action=a) for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    # (A,B,C) occurs twice
    assert any(p.pattern_type == "action_sequence" for p in patterns)
    matched = [p for p in patterns if "Common sequence: A → B → C (occurred 2 times)" in p.description]
    assert len(matched) == 1
    assert matched[0].confidence == pytest.approx(0.75)


def test_detect_action_sequences_insufficient_length(analyzer, base_time):
    """Test _detect_action_sequences returns empty when there are fewer than 3 activities."""
    activities = [make_activity(base_time, "A"), make_activity(base_time + timedelta(minutes=1), "B")]
    assert analyzer._detect_action_sequences(activities) == []


def test_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity detects a highly regular pattern with low coefficient of variation."""
    # 6 activities at exact 1-hour intervals
    activities = [make_activity(base_time + timedelta(hours=i), "A") for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern (CV: 0.00)" in p.description
    assert p.confidence == pytest.approx(0.9)


def test_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty for irregular intervals (high coefficient of variation)."""
    # 5 activities with alternating short and long gaps to increase CV
    timestamps = [
        base_time,
        base_time + timedelta(seconds=10),
        base_time + timedelta(seconds=1010),
        base_time + timedelta(seconds=1020),
        base_time + timedelta(seconds=3020),
    ]
    activities = [make_activity(ts, "A") for ts in timestamps]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_detect_anomalies_insufficient_activities(analyzer, base_time):
    """Test detect_anomalies returns empty when there are fewer than 5 activities total."""
    activities = [make_activity(base_time + timedelta(seconds=i * 10), "click") for i in range(4)]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_detect_anomalies_no_stddev(analyzer, base_time):
    """Test detect_anomalies returns empty when intervals have zero standard deviation."""
    # 5 activities at uniform intervals for one action
    activities = [make_activity(base_time + timedelta(seconds=i * 10), "click") for i in range(5)]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_detect_anomalies_flags_large_gap(analyzer, base_time):
    """Test detect_anomalies flags a large interval outlier with z-score above threshold."""
    # Build 12 timestamps for a single action: 10 short intervals (10s), then one huge interval (10000s)
    timestamps = [base_time + timedelta(seconds=10 * i) for i in range(11)]
    timestamps.append(base_time + timedelta(seconds=(10 * 10) + 10000))
    activities = [make_activity(ts, "click") for ts in timestamps]

    anomalies = analyzer.detect_anomalies(activities)
    # Expect one anomaly for the big gap ending at the last timestamp
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "click"
    assert anomaly["timestamp"] == timestamps[-1].isoformat()
    assert "Unusual interval" in anomaly["reason"]

    # Compute expected rounded z-score as per implementation
    intervals = []
    for i in range(1, len(timestamps)):
        intervals.append((timestamps[i] - timestamps[i - 1]).total_seconds())
    mean_interval = sum(intervals) / len(intervals)
    variance = sum((x - mean_interval) ** 2 for x in intervals) / len(intervals)
    std_dev = variance ** 0.5
    expected_z = round(abs((intervals[-1] - mean_interval) / std_dev), 2)
    assert anomaly["z_score"] == pytest.approx(expected_z)


def test_analyze_patterns_with_mixed_validity(analyzer, base_time):
    """Test analyze_patterns handles activities with missing fields without raising exceptions."""
    activities = [
        {"timestamp": base_time, "action": "A"},
        {"timestamp": None, "action": "B"},
        {"action": "C"},  # missing timestamp
        {"timestamp": "invalid", "action": "D"},  # unparsable timestamp
        {"timestamp": base_time + timedelta(hours=1)},  # missing action defaults to ''
        {"timestamp": base_time + timedelta(hours=1, minutes=1), "action": "A"},
    ]
    result = analyzer.analyze_patterns(activities)
    # Result should be a list; pattern count depends on detections but should not error
    assert isinstance(result, list)