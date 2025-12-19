import pytest
from datetime import datetime, timedelta
from unittest.mock import patch

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Base datetime for constructing events"""
    return datetime(2025, 1, 1, 0, 0, 0)


def make_activity(ts, action="a"):
    """Helper to build an activity dict."""
    return {"timestamp": ts, "action": action}


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict serialization"""
    ap = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.9)
    assert ap.pattern_type == "peak_hours"
    assert ap.description == "desc"
    assert ap.confidence == 0.9
    d = ap.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "desc",
        "confidence": 0.9,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default thresholds on initialization"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_various_inputs(analyzer):
    """Test _parse_timestamp with datetime, ISO strings, and invalid inputs"""
    now = datetime(2025, 1, 1, 12, 0, 0)
    # datetime input
    assert analyzer._parse_timestamp(now) == now

    # ISO with Z
    ts_str_z = "2025-01-01T12:00:00Z"
    parsed_z = analyzer._parse_timestamp(ts_str_z)
    assert isinstance(parsed_z, datetime)
    assert parsed_z.isoformat().endswith("+00:00")

    # ISO without timezone
    ts_str = "2025-01-01T12:00:00"
    parsed = analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)

    # Invalid string
    assert analyzer._parse_timestamp("not-a-timestamp") is None

    # None input
    assert analyzer._parse_timestamp(None) is None


def test_activityanalyzer_detect_peak_hours_single_peak(analyzer, base_time):
    """Test _detect_peak_hours identifies only hours above the threshold"""
    activities = []
    # 3 activities at 09:00
    for i in range(3):
        activities.append(make_activity((base_time.replace(hour=9) + timedelta(minutes=i)).isoformat() + "Z"))
    # 2 activities at 10:00
    for i in range(2):
        activities.append(make_activity((base_time.replace(hour=10) + timedelta(minutes=i)).isoformat() + "Z"))
    # 5 activities at various other hours
    other_hours = [0, 1, 2, 3, 4]
    for h in other_hours:
        activities.append(make_activity((base_time.replace(hour=h)).isoformat() + "Z"))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "09:00" in p.description
    assert "10:00" not in p.description
    assert p.confidence == 0.85

    # No parseable timestamps -> no patterns
    invalid = [make_activity("invalid", "x") for _ in range(3)]
    assert analyzer._detect_peak_hours(invalid) == []


def test_activityanalyzer_detect_action_sequences_common(analyzer):
    """Test _detect_action_sequences finds common sequences occurring at least twice"""
    actions = [
        "a", "b", "c",
        "x", "y", "z",
        "a", "b", "c",
        "a", "b", "c",
        "m", "n", "o"
    ]
    activities = [make_activity(f"2025-01-01T00:{i:02d}:00Z", action=a) for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "Common sequence: a → b → c (occurred 3 times)" == p.description
    assert p.confidence == 0.75


def test_activityanalyzer_detect_regularity_highly_regular(analyzer):
    """Test _detect_regularity detects highly regular intervals"""
    # 6 timestamps exactly 1 hour apart
    activities = []
    base = datetime(2025, 1, 1, 0, 0, 0)
    for i in range(6):
        activities.append(make_activity((base + timedelta(hours=i)).isoformat() + "Z"))
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV: 0.00" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer):
    """Test _detect_regularity returns empty when intervals are irregular"""
    # Alternating intervals: 1h, 4h, 1h, 4h, 4h
    times = [
        datetime(2025, 1, 1, 0, 0, 0),
        datetime(2025, 1, 1, 1, 0, 0),
        datetime(2025, 1, 1, 5, 0, 0),
        datetime(2025, 1, 1, 6, 0, 0),
        datetime(2025, 1, 1, 10, 0, 0),
        datetime(2025, 1, 1, 14, 0, 0),
    ]
    activities = [make_activity(t.isoformat() + "Z") for t in times]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_analyze_patterns_combines_results(analyzer):
    """Test analyze_patterns combines outputs from detectors in order"""
    activities = [make_activity("2025-01-01T00:00:00Z", "login")]
    mock_peak = [ActivityPattern("peak_hours", "peak desc", 0.8)]
    mock_seq = [ActivityPattern("action_sequence", "seq desc", 0.7)]
    mock_reg = [ActivityPattern("regularity", "reg desc", 0.9)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as m3:
        results = analyzer.analyze_patterns(activities)
        m1.assert_called_once_with(activities)
        m2.assert_called_once_with(activities)
        m3.assert_called_once_with(activities)
        assert results == mock_peak + mock_seq + mock_reg


def test_activityanalyzer_analyze_patterns_empty_no_calls(analyzer):
    """Test analyze_patterns returns empty and does not call detectors for empty input"""
    with patch.object(ActivityAnalyzer, "_detect_peak_hours") as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences") as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity") as m3:
        results = analyzer.analyze_patterns([])
        assert results == []
        m1.assert_not_called()
        m2.assert_not_called()
        m3.assert_not_called()


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities"""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_calculation_basic(analyzer):
    """Test get_user_score with same-day timestamps and mixed actions"""
    # 4 actions at same timestamp; algorithm will count unique_actions erroneously as 4
    ts = "2025-01-01T00:00:00Z"
    activities = [
        {"timestamp": ts, "action": "a"},
        {"timestamp": ts, "action": "a"},
        {"timestamp": ts, "action": "b"},
        {"timestamp": ts, "action": "c"},
    ]
    score = analyzer.get_user_score(activities)
    # diversity=1.0, frequency=0.4, volume=0.04 -> final=47.2
    assert score == 47.2


def test_activityanalyzer_get_user_score_invalid_timestamps_defaults(analyzer):
    """Test get_user_score uses total actions when timestamps cannot be parsed"""
    activities = [{"timestamp": "invalid", "action": "x"} for _ in range(10)]
    score = analyzer.get_user_score(activities)
    # diversity=1.0 (due to flawed uniqueness logic), frequency=1.0, volume=0.1 -> 73.0
    assert score == 73.0


def test_activityanalyzer_detect_anomalies_insufficient(analyzer):
    """Test detect_anomalies returns empty when not enough activities"""
    activities = [
        make_activity(datetime(2025, 1, 1, 0, 0, 0), "login"),
        make_activity(datetime(2025, 1, 1, 0, 1, 0), "login"),
        make_activity(datetime(2025, 1, 1, 0, 2, 0), "login"),
        make_activity(datetime(2025, 1, 1, 0, 3, 0), "login"),
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_flags_large_interval(analyzer, base_time):
    """Test detect_anomalies flags an interval with large z-score"""
    # Build timestamps: 9 small 1-minute intervals, then 60-minute big interval, then 3 small 1-minute intervals
    timestamps = [base_time]
    # 9 small
    for i in range(1, 10):
        timestamps.append(base_time + timedelta(minutes=i))
    # big gap (60 minutes from last)
    big_gap_time = timestamps[-1] + timedelta(minutes=60)
    timestamps.append(big_gap_time)
    # 3 small after
    for i in range(1, 4):
        timestamps.append(big_gap_time + timedelta(minutes=i))

    activities = [make_activity(ts, "login") for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    # Expect exactly one anomaly at the end of the big interval
    assert len(anomalies) == 1
    anom = anomalies[0]
    assert anom["action"] == "login"
    assert anom["timestamp"] == big_gap_time.isoformat()
    assert anom["z_score"] > 3.0
    assert "Unusual interval" in anom["reason"]


def test_activityanalyzer_detect_anomalies_zero_std_no_flags(analyzer, base_time):
    """Test detect_anomalies does not flag anomalies when intervals are identical (std=0)"""
    timestamps = [base_time + timedelta(minutes=i) for i in range(6)]
    activities = [make_activity(ts, "login") for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_parse_timestamp_handles_invalid_string(analyzer):
    """Test _parse_timestamp gracefully handles invalid strings (exception handling)"""
    assert analyzer._parse_timestamp("totally-invalid") is None