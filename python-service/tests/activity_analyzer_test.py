import pytest
from unittest.mock import patch
from datetime import datetime, timedelta
from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


def make_activity(action, ts):
    """Helper to create an activity dict"""
    return {"action": action, "timestamp": ts}


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict output"""
    p = ActivityPattern(pattern_type="test_type", description="Test description", confidence=0.95)
    d = p.to_dict()
    assert d["pattern_type"] == "test_type"
    assert d["description"] == "Test description"
    assert d["confidence"] == 0.95


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization defaults"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_various_inputs(analyzer):
    """Test _parse_timestamp handles datetime, ISO strings, and invalid inputs"""
    now = datetime(2021, 1, 1, 12, 0, 0)
    assert analyzer._parse_timestamp(now) == now

    iso_z = "2021-01-01T12:00:00Z"
    parsed = analyzer._parse_timestamp(iso_z)
    assert parsed is not None
    assert parsed.tzinfo is not None

    iso = "2021-01-01T12:00:00"
    parsed2 = analyzer._parse_timestamp(iso)
    assert isinstance(parsed2, datetime)

    assert analyzer._parse_timestamp("not-a-date") is None
    assert analyzer._parse_timestamp(None) is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer):
    """Test _detect_peak_hours identifies hours exceeding threshold"""
    base = datetime(2021, 1, 1, 9, 0, 0)
    activities = []
    # 3 events at 09:xx
    for i in range(3):
        activities.append(make_activity("a", base + timedelta(minutes=i)))
    # 3 events at 10:xx
    for i in range(3):
        activities.append(make_activity("a", base.replace(hour=10) + timedelta(minutes=i)))
    # 4 events spread over other hours to total 10
    activities.append(make_activity("a", base.replace(hour=8)))
    activities.append(make_activity("a", base.replace(hour=11)))
    activities.append(make_activity("a", base.replace(hour=12)))
    activities.append(make_activity("a", base.replace(hour=13)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "peak_hours"
    assert "09:00" in pattern.description
    assert "10:00" in pattern.description
    assert pattern.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_below_threshold(analyzer):
    """Test _detect_peak_hours returns empty when not exceeding threshold (> 0.2)"""
    base = datetime(2021, 1, 1, 9, 0, 0)
    # 5 events across 5 different hours -> each 0.2 (not > 0.2)
    activities = [
        make_activity("a", base.replace(hour=9)),
        make_activity("a", base.replace(hour=10)),
        make_activity("a", base.replace(hour=11)),
        make_activity("a", base.replace(hour=12)),
        make_activity("a", base.replace(hour=13)),
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_invalid_timestamps(analyzer):
    """Test _detect_peak_hours handles invalid timestamps gracefully"""
    activities = [
        make_activity("a", "invalid"),
        make_activity("a", 12345),
        make_activity("a", None),
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_repeated(analyzer):
    """Test _detect_action_sequences detects frequent triplets"""
    activities = [
        make_activity("A", datetime(2021, 1, 1, 0, 0)),
        make_activity("B", datetime(2021, 1, 1, 0, 1)),
        make_activity("C", datetime(2021, 1, 1, 0, 2)),
        make_activity("X", datetime(2021, 1, 1, 0, 3)),
        make_activity("A", datetime(2021, 1, 1, 0, 4)),
        make_activity("B", datetime(2021, 1, 1, 0, 5)),
        make_activity("C", datetime(2021, 1, 1, 0, 6)),
        make_activity("Y", datetime(2021, 1, 1, 0, 7)),
    ]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) >= 1
    found = any(
        p.pattern_type == "action_sequence" and "Common sequence: A → B → C (occurred 2 times)" in p.description
        for p in patterns
    )
    assert found


def test_activityanalyzer_detect_action_sequences_no_repeats(analyzer):
    """Test _detect_action_sequences returns empty when no repeats"""
    activities = [
        make_activity("A", datetime(2021, 1, 1, 0, 0)),
        make_activity("B", datetime(2021, 1, 1, 0, 1)),
        make_activity("C", datetime(2021, 1, 1, 0, 2)),
        make_activity("D", datetime(2021, 1, 1, 0, 3)),
        make_activity("E", datetime(2021, 1, 1, 0, 4)),
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_action_sequences_short_list(analyzer):
    """Test _detect_action_sequences returns empty for < 3 activities"""
    activities = [make_activity("A", datetime(2021, 1, 1))]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_regular(analyzer):
    """Test _detect_regularity identifies highly regular timestamp intervals"""
    base = datetime(2021, 1, 1, 0, 0, 0)
    activities = [make_activity("a", base + timedelta(hours=i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer):
    """Test _detect_regularity returns empty for irregular intervals"""
    base = datetime(2021, 1, 1, 0, 0, 0)
    intervals = [0, 10, 30, 60, 120, 300]  # minutes
    activities = [make_activity("a", base + timedelta(minutes=m)) for m in intervals]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_invalid_timestamps(analyzer):
    """Test _detect_regularity ignores invalid timestamps and may return empty if insufficient valid ones"""
    base = datetime(2021, 1, 1, 0, 0, 0)
    activities = [
        make_activity("a", base),
        make_activity("a", "invalid"),
        make_activity("a", None),
        make_activity("a", base + timedelta(hours=1)),
        make_activity("a", base + timedelta(hours=2)),
        make_activity("a", 12345),
    ]
    # Only 3 valid timestamps -> should return []
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_get_user_score_no_activities(analyzer):
    """Test get_user_score returns 0.0 for empty input"""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_basic_calculation(analyzer):
    """Test get_user_score with valid timestamps across multiple days"""
    base = datetime(2021, 1, 1, 0, 0, 0)
    activities = [make_activity("view", base + timedelta(hours=i)) for i in range(10)]
    # Set last timestamp two days after first to ensure days_active=2
    activities[-1]["timestamp"] = base + timedelta(days=2)

    score = analyzer.get_user_score(activities)
    # diversity_score (buggy) -> 1.0
    # actions_per_day = 10 / 2 = 5 -> frequency_score=0.5
    # volume_score = 10/100=0.1
    # final = (0.3 + 0.2 + 0.03) * 100 = 53.0
    assert score == 53.0


def test_activityanalyzer_get_user_score_invalid_timestamps_use_total_actions(analyzer):
    """Test get_user_score uses total_actions when timestamps are invalid"""
    activities = [make_activity("click", "invalid-timestamp") for _ in range(15)]
    score = analyzer.get_user_score(activities)
    # diversity_score (buggy) -> 1.0
    # actions_per_day=total_actions=15 -> frequency_score=min(1.5,1.0)=1.0
    # volume_score=0.15
    # final=(0.3 + 0.4 + 0.045) * 100 = 74.5
    assert score == 74.5


def test_activityanalyzer_analyze_patterns_calls_detectors_and_aggregates(analyzer):
    """Test analyze_patterns calls all detector methods and aggregates results"""
    activities = [make_activity("a", datetime(2021, 1, 1))]
    p1 = ActivityPattern("peak_hours", "ph", 0.1)
    p2 = ActivityPattern("action_sequence", "seq", 0.2)

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[p1]) as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[p2]) as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[]) as m3:
        result = analyzer.analyze_patterns(activities)
        m1.assert_called_once_with(activities)
        m2.assert_called_once_with(activities)
        m3.assert_called_once_with(activities)
        assert len(result) == 2
        types = {r.pattern_type for r in result}
        assert "peak_hours" in types
        assert "action_sequence" in types


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list on empty input and does not call detectors"""
    with patch.object(ActivityAnalyzer, "_detect_peak_hours") as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences") as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity") as m3:
        result = analyzer.analyze_patterns([])
        assert result == []
        m1.assert_not_called()
        m2.assert_not_called()
        m3.assert_not_called()


def test_activityanalyzer_detect_anomalies_minimum_length(analyzer):
    """Test detect_anomalies returns empty for fewer than 5 activities"""
    activities = [make_activity("a", datetime(2021, 1, 1, 0, i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_ignores_invalid_and_insufficient(analyzer):
    """Test detect_anomalies ignores invalid timestamps and actions with <3 timestamps"""
    activities = [
        make_activity("a", "invalid"),
        make_activity("a", None),
        make_activity("b", datetime(2021, 1, 1, 0, 0)),
        make_activity("b", datetime(2021, 1, 1, 0, 1)),
        make_activity("c", datetime(2021, 1, 1, 0, 2)),
    ]
    # For action 'b' there are only 2 valid timestamps -> insufficient; expect no anomalies
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_detects_outlier(analyzer):
    """Test detect_anomalies flags a large interval outlier using z-score"""
    base = datetime(2021, 1, 1, 0, 0, 0)
    timestamps = [base]
    # First 10 small intervals of 10s
    for _ in range(10):
        timestamps.append(timestamps[-1] + timedelta(seconds=10))
    # One large interval of 1200s (outlier)
    timestamps.append(timestamps[-1] + timedelta(seconds=1200))
    # Next 9 small intervals of 10s to make total 20 intervals (21 timestamps)
    for _ in range(9):
        timestamps.append(timestamps[-1] + timedelta(seconds=10))

    activities = [make_activity("login", ts) for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)

    # Expect exactly one anomaly at the timestamp after the large interval
    assert len(anomalies) >= 1
    # Filter by action
    anomalies_login = [a for a in anomalies if a["action"] == "login"]
    assert len(anomalies_login) >= 1

    # The anomalous timestamp is the one right after the big interval (index 11)
    expected_ts = timestamps[11].isoformat()
    found = any(a["timestamp"] == expected_ts and a["z_score"] >= 3.5 and "Unusual interval" in a["reason"]
                for a in anomalies_login)
    assert found


def test_activityanalyzer_detect_anomalies_no_stddev_zero(analyzer):
    """Test detect_anomalies returns empty when intervals have zero std deviation"""
    base = datetime(2021, 1, 1, 0, 0, 0)
    timestamps = [base + timedelta(seconds=10 * i) for i in range(6)]  # 5 equal intervals
    activities = [make_activity("click", ts) for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_parse_timestamp_exception_handling(analyzer):
    """Test _parse_timestamp handles invalid strings without raising exceptions"""
    bad_values = ["", "2021-13-01T00:00:00", "2021-01-32", "2021-01-01 25:00:00", "not-a-date"]
    for val in bad_values:
        assert analyzer._parse_timestamp(val) is None