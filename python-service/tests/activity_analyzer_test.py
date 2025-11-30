import pytest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a fixed base datetime for consistent tests."""
    return datetime(2021, 1, 1, 9, 0, 0)


def make_activity(action: str, ts):
    return {"action": action, "timestamp": ts}


def test_activitypattern_to_dict_returns_correct_dict():
    """ActivityPattern.to_dict should return a dict with expected keys and values."""
    p = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.5)
    assert p.to_dict() == {
        "pattern_type": "peak_hours",
        "description": "desc",
        "confidence": 0.5,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """ActivityAnalyzer should initialize thresholds with correct default values."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_various_inputs(analyzer, base_time):
    """_parse_timestamp should handle datetimes, ISO strings with/without Z, and invalid inputs."""
    # Direct datetime
    assert analyzer._parse_timestamp(base_time) == base_time

    # ISO string without Z
    iso_str = "2021-01-01T12:34:56"
    dt = analyzer._parse_timestamp(iso_str)
    assert isinstance(dt, datetime)
    assert dt.year == 2021 and dt.hour == 12 and dt.minute == 34 and dt.second == 56
    assert dt.tzinfo is None  # no timezone in input

    # ISO string with Z -> should produce timezone-aware UTC datetime
    iso_z = "2021-01-01T12:34:56Z"
    dtz = analyzer._parse_timestamp(iso_z)
    assert isinstance(dtz, datetime)
    assert dtz.tzinfo is not None
    assert dtz.utcoffset() == timedelta(0)

    # ISO string with timezone offset
    iso_offset = "2021-01-01T12:00:00+02:00"
    dto = analyzer._parse_timestamp(iso_offset)
    assert isinstance(dto, datetime)
    assert dto.tzinfo is not None
    assert dto.utcoffset() == timedelta(hours=2)

    # Invalid string
    assert analyzer._parse_timestamp("not-a-time") is None

    # None
    assert analyzer._parse_timestamp(None) is None


def test_activityanalyzer_detect_peak_hours_detects_multiple_hours(analyzer, base_time):
    """_detect_peak_hours should detect hours whose share exceeds threshold and list them sorted."""
    activities = []
    # 4 at 09:00
    for i in range(4):
        activities.append(make_activity("a", base_time.replace(hour=9, minute=i)))
    # 3 at 10:00
    for i in range(3):
        activities.append(make_activity("b", base_time.replace(hour=10, minute=i)))
    # 1 each at 11, 12, 13
    activities.append(make_activity("c", base_time.replace(hour=11)))
    activities.append(make_activity("d", base_time.replace(hour=12)))
    activities.append(make_activity("e", base_time.replace(hour=13)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert p.confidence == 0.85
    assert p.description == "High activity during hours: 09:00, 10:00"


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps_returns_empty(analyzer):
    """_detect_peak_hours should return empty when no valid timestamps are present."""
    activities = [make_activity("x", "invalid"), make_activity("y", "also-bad")]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_peak_hours_threshold_edge_case(analyzer, base_time):
    """_detect_peak_hours should use strict greater-than threshold."""
    activities = []
    # total 10, one hour has exactly 2 occurrences -> fraction 0.2 equals threshold, should not include
    for i in range(2):
        activities.append(make_activity("a", base_time.replace(hour=9, minute=i)))
    # distribute remaining 8 across 8 distinct hours
    hours = [10, 11, 12, 13, 14, 15, 16, 17]
    for i, h in enumerate(hours):
        activities.append(make_activity("b", base_time.replace(hour=h, minute=i)))
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_detects_common_sequence(analyzer, base_time):
    """_detect_action_sequences should identify repeated 3-action sequences."""
    actions = [
        "login", "view", "click", "logout",
        "login", "view", "click", "share",
    ]
    activities = [make_activity(a, base_time + timedelta(minutes=i)) for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "login → view → click" in p.description
    assert "(occurred 2 times)" in p.description
    assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_returns_top_three(analyzer, base_time):
    """_detect_action_sequences should return at most top three repeated sequences."""
    # Create two identical blocks to repeat three windows twice: [a,b,c,d,e] repeated
    block = ["a", "b", "c", "d", "e"]
    actions = block + block
    activities = [make_activity(a, base_time + timedelta(minutes=i)) for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 3
    # Ensure each is marked as occurred 2 times
    assert all("(occurred 2 times)" in p.description for p in patterns)


def test_activityanalyzer_detect_regularity_identifies_regular_pattern(analyzer, base_time):
    """_detect_regularity should flag highly regular intervals with low coefficient of variation."""
    activities = [make_activity("tick", base_time + timedelta(hours=i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert p.confidence == 0.9
    assert "Highly regular activity pattern" in p.description
    assert "(CV: 0.00)" in p.description


def test_activityanalyzer_detect_regularity_irregular_no_pattern(analyzer, base_time):
    """_detect_regularity should not return a pattern for very irregular intervals."""
    deltas = [1, 10, 50, 120, 420, 60]  # minutes between events
    timestamps = [base_time]
    for d in deltas:
        timestamps.append(timestamps[-1] + timedelta(minutes=d))
    activities = [make_activity("tick", t) for t in timestamps]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_analyze_patterns_composes_results_with_mocks(analyzer):
    """analyze_patterns should combine results from internal detection methods."""
    fake_peak = [ActivityPattern("peak_hours", "peak", 0.85)]
    fake_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    fake_reg = [ActivityPattern("regularity", "reg", 0.9)]
    activities = [{"action": "x", "timestamp": "2021-01-01T00:00:00Z"}]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=fake_peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=fake_seq) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=fake_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)
        assert patterns == fake_peak + fake_seq + fake_reg
        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)


def test_activityanalyzer_analyze_patterns_with_empty_input_returns_empty(analyzer):
    """analyze_patterns should return empty list for empty input."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_with_valid_timestamps(analyzer, base_time):
    """get_user_score should compute expected score using days between first and last timestamps."""
    activities = [
        make_activity("a", base_time),
        make_activity("b", base_time + timedelta(days=1)),
        make_activity("a", base_time + timedelta(days=2)),
        make_activity("c", base_time + timedelta(days=2, hours=12)),
        make_activity("a", base_time + timedelta(days=3)),
    ]
    # Expected:
    # total=5, unique=3 => diversity=0.6
    # days_active=(last-first)=3 days => actions_per_day=5/3 => frequency=1.6667/10 = 0.166666...
    # volume=5/100=0.05
    # final=(0.6*0.3 + 0.1666667*0.4 + 0.05*0.3)*100 = 26.17 after rounding
    score = analyzer.get_user_score(activities)
    assert score == 26.17


def test_activityanalyzer_get_user_score_no_timestamps_uses_total_actions(analyzer):
    """get_user_score should fall back to actions_per_day=total_actions when timestamps are invalid."""
    activities = [
        make_activity("a", "bad"),
        make_activity("b", "also-bad"),
        make_activity("a", None),
        make_activity("c", "invalid"),
        make_activity("a", "nope"),
    ]
    # total=5, unique=3 => diversity=0.6
    # actions_per_day=5 => frequency=0.5
    # volume=0.05
    # final=(0.6*0.3 + 0.5*0.4 + 0.05*0.3)*100 = 39.5
    score = analyzer.get_user_score(activities)
    assert score == 39.5


def test_activityanalyzer_get_user_score_empty_returns_zero(analyzer):
    """get_user_score should return 0.0 for empty list."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_detect_anomalies_identifies_large_interval(analyzer, base_time):
    """detect_anomalies should flag unusually large inter-event intervals for an action."""
    # 7 timestamps for 'ping' with one large gap
    times = [
        base_time,
        base_time + timedelta(seconds=10),
        base_time + timedelta(seconds=20),
        base_time + timedelta(seconds=30),
        base_time + timedelta(seconds=1030),  # large gap here from previous
        base_time + timedelta(seconds=1040),
        base_time + timedelta(seconds=1050),
    ]
    activities = [make_activity("ping", t) for t in times]
    # add another action with insufficient data to be ignored
    activities += [make_activity("other", base_time + timedelta(minutes=i)) for i in range(2)]

    analyzer.anomaly_threshold = 2.0  # lower threshold to ensure detection in test
    anomalies = analyzer.detect_anomalies(activities)
    # Expect one anomaly for the interval leading to the 5th timestamp
    assert len(anomalies) == 1
    an = anomalies[0]
    assert an["action"] == "ping"
    assert an["timestamp"] == times[4].isoformat()
    assert an["z_score"] >= 2.0
    assert "Unusual interval" in an["reason"]


def test_activityanalyzer_detect_anomalies_too_few_activities_returns_empty(analyzer, base_time):
    """detect_anomalies should return empty when fewer than 5 activities are provided."""
    activities = [make_activity("x", base_time + timedelta(minutes=i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_zero_stddev_returns_empty(analyzer, base_time):
    """detect_anomalies should not flag anomalies when intervals are constant (std dev is zero)."""
    times = [base_time + timedelta(seconds=10 * i) for i in range(7)]
    activities = [make_activity("steady", t) for t in times]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []