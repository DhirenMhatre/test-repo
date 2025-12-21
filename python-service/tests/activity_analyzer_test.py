import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide a fresh ActivityAnalyzer instance for tests."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing activity timestamps."""
    return datetime(2021, 1, 1, 10, 0, 0)


def make_activity(action: str, ts):
    """Helper to make an activity dict with given action and timestamp."""
    return {"action": action, "timestamp": ts}


def test_activitypattern_to_dict():
    """ActivityPattern.to_dict returns the correct mapping."""
    ap = ActivityPattern("peak_hours", "desc", 0.9)
    data = ap.to_dict()
    assert data == {"pattern_type": "peak_hours", "description": "desc", "confidence": 0.9}


def test_activityanalyzer_init_defaults(analyzer):
    """ActivityAnalyzer default thresholds are set correctly."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer):
    """_parse_timestamp handles datetime, ISO strings with/without Z, and invalid values."""
    dt = datetime(2021, 1, 1, 12, 34, 56)
    assert analyzer._parse_timestamp(dt) == dt

    parsed = analyzer._parse_timestamp("2021-01-01T12:34:56")
    assert isinstance(parsed, datetime)
    assert parsed.year == 2021 and parsed.hour == 12

    parsed_z = analyzer._parse_timestamp("2021-01-01T12:34:56Z")
    assert isinstance(parsed_z, datetime)
    # ISO with Z should parse as offset-aware +00:00
    assert parsed_z.tzinfo is not None

    # Invalid string returns None (no exception raised)
    assert analyzer._parse_timestamp("not-a-timestamp") is None

    # Non-string, non-datetime returns None
    assert analyzer._parse_timestamp(12345) is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """_detect_peak_hours identifies hours exceeding the threshold proportion."""
    activities = []
    # 3 activities at 10:00 hour
    for i in range(3):
        activities.append(make_activity("a", base_time + timedelta(minutes=i)))
    # 7 activities at 11:00 hour
    for i in range(7):
        activities.append(make_activity("b", base_time.replace(hour=11) + timedelta(minutes=i)))
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    assert patterns[0].pattern_type == "peak_hours"
    assert "10:00" in patterns[0].description
    assert "11:00" in patterns[0].description


def test_activityanalyzer_detect_peak_hours_none_due_to_threshold(analyzer, base_time):
    """_detect_peak_hours returns empty list when no hour surpasses the threshold."""
    analyzer.peak_hour_threshold = 0.5  # Increase threshold above observed proportions
    activities = []
    for i in range(3):
        activities.append(make_activity("a", base_time + timedelta(minutes=i)))
    for i in range(7):
        activities.append(make_activity("b", base_time.replace(hour=11) + timedelta(minutes=i)))
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_ignores_invalid_timestamps(analyzer):
    """_detect_peak_hours ignores activities with invalid timestamps."""
    activities = [
        {"action": "a", "timestamp": "invalid-date"},
        {"action": "b", "timestamp": None},
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_basic(analyzer, base_time):
    """_detect_action_sequences identifies common 3-action sequences occurring at least twice."""
    # Sequence: A,B,C repeated twice
    actions = ["A", "B", "C", "A", "B", "C"]
    activities = [
        make_activity(a, base_time + timedelta(minutes=i)) for i, a in enumerate(actions)
    ]
    patterns = analyzer._detect_action_sequences(activities)
    assert any(p.pattern_type == "action_sequence" for p in patterns)
    assert any("A → B → C" in p.description and "occurred 2 times" in p.description for p in patterns)


def test_activityanalyzer_detect_action_sequences_insufficient_data(analyzer):
    """_detect_action_sequences returns empty list for fewer than 3 activities."""
    activities = [make_activity("A", datetime(2021, 1, 1, 0, 0, 0))]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_high(analyzer, base_time):
    """_detect_regularity returns pattern when coefficient of variation is low (< 0.3)."""
    activities = [
        make_activity("x", base_time + timedelta(seconds=60 * i)) for i in range(6)
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    assert patterns[0].pattern_type == "regularity"
    assert "CV:" in patterns[0].description


def test_activityanalyzer_detect_regularity_low(analyzer, base_time):
    """_detect_regularity returns empty when variation is higher than threshold."""
    intervals = [0, 60, 180, 240, 420, 900]
    activities = [make_activity("x", base_time + timedelta(seconds=i)) for i in intervals]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_anomalies_insufficient(analyzer, base_time):
    """detect_anomalies returns empty when there are fewer than 5 activities."""
    activities = [make_activity("login", base_time + timedelta(minutes=i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_outlier_interval(analyzer, base_time):
    """detect_anomalies flags intervals with z-score above anomaly_threshold."""
    # 12 timestamps for 'click': 10 intervals of 60 seconds + one of 7200 seconds
    ts = [base_time + timedelta(seconds=60 * i) for i in range(11)]
    ts.append(base_time + timedelta(seconds=60 * 10 + 7200))
    activities = [make_activity("click", t) for t in ts]
    # Add some more activities of other action to increase list size
    activities += [make_activity("other", base_time + timedelta(hours=5, minutes=i)) for i in range(5)]

    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) >= 1
    # Ensure the anomaly relates to 'click'
    assert any(a["action"] == "click" and a["z_score"] >= analyzer.anomaly_threshold for a in anomalies)
    for a in anomalies:
        assert "Unusual interval" in a["reason"]


def test_activityanalyzer_detect_anomalies_no_stddev(analyzer, base_time):
    """detect_anomalies does not flag when standard deviation is zero."""
    # Identical intervals => std_dev == 0
    ts = [base_time + timedelta(minutes=i) for i in range(6)]
    activities = [make_activity("same", t) for t in ts]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """get_user_score returns 0.0 for empty activities."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_basic(analyzer, base_time):
    """get_user_score computes expected score based on diversity, frequency, and volume."""
    # 10 activities within the same day; due to implementation, unique_actions == total_actions
    activities = [
        make_activity("a", base_time + timedelta(minutes=i)) for i in range(10)
    ]
    score = analyzer.get_user_score(activities)
    # diversity=1.0, frequency=1.0, volume=0.1 -> final = (0.3+0.4+0.03)*100 = 73.0
    assert score == 73.0


def test_activityanalyzer_get_user_score_missing_timestamps(analyzer):
    """get_user_score falls back to using total_actions when timestamps are missing."""
    activities = [{"action": "x", "timestamp": "invalid"} for _ in range(1)]
    score = analyzer.get_user_score(activities)
    # total_actions=1, diversity=1.0, frequency=0.1, volume=0.01 -> 34.3
    assert score == 34.3


def test_activityanalyzer_analyze_patterns_combines_detectors(analyzer, base_time):
    """analyze_patterns aggregates patterns from internal detectors."""
    activities = [
        make_activity("a", base_time + timedelta(minutes=i)) for i in range(10)
    ]
    p1 = ActivityPattern("t1", "d1", 0.1)
    p2 = ActivityPattern("t2", "d2", 0.2)
    p3 = ActivityPattern("t3", "d3", 0.3)
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[p1]) as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[p2]) as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[p3]) as m3:
        patterns = analyzer.analyze_patterns(activities)
        assert patterns == [p1, p2, p3]
        m1.assert_called_once()
        m2.assert_called_once()
        m3.assert_called_once()


def test_activityanalyzer_analyze_patterns_empty_input(analyzer):
    """analyze_patterns returns empty list and does not call detectors for empty input."""
    with patch.object(ActivityAnalyzer, "_detect_peak_hours") as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences") as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity") as m3:
        patterns = analyzer.analyze_patterns([])
        assert patterns == []
        m1.assert_not_called()
        m2.assert_not_called()
        m3.assert_not_called()


def test_activityanalyzer_detect_action_sequences_with_missing_action_keys(analyzer, base_time):
    """_detect_action_sequences handles activities missing 'action' key by using empty string."""
    acts = [
        {"timestamp": base_time + timedelta(minutes=0)},  # action missing -> ''
        {"timestamp": base_time + timedelta(minutes=1)},
        {"timestamp": base_time + timedelta(minutes=2)},
        {"timestamp": base_time + timedelta(minutes=3)},
        {"timestamp": base_time + timedelta(minutes=4)},
        {"timestamp": base_time + timedelta(minutes=5)},
    ]
    patterns = analyzer._detect_action_sequences(acts)
    # Likely sequences of empty strings; ensure no crash and return possibly pattern if repeats
    assert isinstance(patterns, list)  # content depends on repetition; we just ensure no exception


def test_activityanalyzer_parse_timestamp_exception_handling(analyzer):
    """_parse_timestamp gracefully returns None on strings that raise ValueError in parsing."""
    # fromisoformat would raise ValueError; ensure handled and None is returned
    result = analyzer._parse_timestamp("2021-13-40T25:61:61")
    assert result is None


def test_activityanalyzer_peak_hours_multiple(analyzer, base_time):
    """_detect_peak_hours can include multiple peak hours."""
    activities = []
    # 4 at 09:00, 4 at 10:00, 2 at 11:00 => threshold 0.2 -> 0.4, 0.4, 0.2 (11:00 equals threshold not included)
    for i in range(4):
        activities.append(make_activity("a", base_time.replace(hour=9) + timedelta(minutes=i)))
    for i in range(4):
        activities.append(make_activity("b", base_time.replace(hour=10) + timedelta(minutes=i)))
    for i in range(2):
        activities.append(make_activity("c", base_time.replace(hour=11) + timedelta(minutes=i)))
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    desc = patterns[0].description
    assert "09:00" in desc and "10:00" in desc
    assert "11:00" not in desc  # exactly 0.2 should not be included since condition is '>' not '>='