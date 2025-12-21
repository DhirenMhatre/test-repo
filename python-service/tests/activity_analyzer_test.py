import pytest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide a fresh ActivityAnalyzer instance for each test."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Base datetime for generating test timestamps."""
    return datetime(2025, 1, 1, 9, 0, 0)


def mk_act(action, ts):
    """Helper to construct an activity dict."""
    return {"action": action, "timestamp": ts}


def test_activitypattern_initialization_and_to_dict():
    """Test ActivityPattern initialization and to_dict output."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.95)
    d = pattern.to_dict()
    assert isinstance(d, dict)
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "desc"
    assert d["confidence"] == 0.95


def test_activityanalyzer_init_defaults(analyzer):
    """Test default thresholds on initialization."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_valid_and_invalid(analyzer, base_time):
    """Test _parse_timestamp with valid datetime, ISO with Z, and invalid input."""
    # Valid datetime instance (naive)
    dt = analyzer._parse_timestamp(base_time)
    assert isinstance(dt, datetime)
    assert dt == base_time

    # Valid ISO with Z should produce aware datetime
    dt_z = analyzer._parse_timestamp("2025-01-01T10:00:00Z")
    assert isinstance(dt_z, datetime)
    assert dt_z.tzinfo is not None
    assert dt_z.utcoffset() == timedelta(0)

    # Valid ISO without timezone (naive)
    dt_naive = analyzer._parse_timestamp("2025-01-01T11:00:00")
    assert isinstance(dt_naive, datetime)
    assert dt_naive.tzinfo is None

    # Invalid string
    assert analyzer._parse_timestamp("not-a-date") is None

    # Unsupported type
    assert analyzer._parse_timestamp(1234567890) is None


def test_activityanalyzer_detect_peak_hours_basic_threshold_behavior(analyzer, base_time):
    """Test detecting peak hours based on threshold (> 0.2)."""
    activities = []
    # 5 events in 09:00 hour
    for i in range(5):
        activities.append(mk_act("a", base_time + timedelta(minutes=i)))
    # 3 events in 10:00 hour
    for i in range(3):
        activities.append(mk_act("b", base_time.replace(hour=10) + timedelta(minutes=i)))
    # 2 events in 11:00 hour
    for i in range(2):
        activities.append(mk_act("c", base_time.replace(hour=11) + timedelta(minutes=i)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "09:00" in p.description
    assert "10:00" in p.description
    # 11:00 has exactly 0.2 share which should not be included (strict >)
    assert "11:00" not in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps_returns_empty(analyzer):
    """Test _detect_peak_hours returns empty when timestamps are invalid or missing."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "b", "timestamp": None},
        {"action": "c"}  # missing timestamp
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_common_sequence(analyzer, base_time):
    """Test detecting common action sequences of length 3 occurring at least twice."""
    actions = ["A", "B", "C", "D", "A", "B", "C"]
    activities = [mk_act(a, base_time + timedelta(seconds=i)) for i, a in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    # Should detect "A → B → C" occurred 2 times
    assert any(
        p.pattern_type == "action_sequence" and
        "A → B → C" in p.description and
        "occurred 2 times" in p.description and
        p.confidence == 0.75
        for p in patterns
    )


def test_activityanalyzer_detect_action_sequences_too_short_returns_empty(analyzer, base_time):
    """Test _detect_action_sequences returns empty with fewer than 3 activities."""
    activities = [mk_act("A", base_time), mk_act("B", base_time + timedelta(seconds=1))]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity identifies highly regular intervals (low CV)."""
    # 6 activities at 60s intervals
    activities = [mk_act("act", base_time + timedelta(seconds=60 * i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert "(CV: 0.00)" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_insufficient_data(analyzer, base_time):
    """Test _detect_regularity returns empty with fewer than 5 valid timestamps."""
    # Only 4 valid timestamps
    activities = [
        mk_act("a", base_time),
        mk_act("b", base_time + timedelta(seconds=10)),
        mk_act("c", "invalid"),
        mk_act("d", base_time + timedelta(seconds=30)),
        mk_act("e", None),
        mk_act("f", base_time + timedelta(seconds=50))
    ]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_get_user_score_basic_calculation(analyzer, base_time):
    """Test get_user_score with known values to validate scoring."""
    # 10 actions over the same day; two unique actions repeated
    actions = ["A", "B"] * 5
    activities = [mk_act(a, base_time + timedelta(minutes=i)) for i, a in enumerate(actions)]
    score = analyzer.get_user_score(activities)
    # diversity = 2/10=0.2, frequency=10/10=1.0, volume=10/100=0.1
    # final = (0.2*0.3 + 1.0*0.4 + 0.1*0.3) * 100 = 49.0
    assert score == 49.0


def test_activityanalyzer_get_user_score_handles_invalid_timestamps(analyzer):
    """Test get_user_score handles missing/invalid timestamps gracefully."""
    activities = [
        {"action": "view", "timestamp": "invalid"},
        {"action": "click", "timestamp": None},
        {"action": "view", "timestamp": 12345},
    ]
    score = analyzer.get_user_score(activities)
    # total_actions=3, unique_actions=2 -> diversity=2/3 ~= 0.6667
    # actions_per_day=total_actions (invalid timestamps) -> 3
    # frequency_score=0.3, volume_score=0.03
    # final = (0.6667*0.3 + 0.3*0.4 + 0.03*0.3) * 100 ≈ (0.2 + 0.12 + 0.009) * 100 = 32.9
    assert isinstance(score, float)
    assert round(score, 1) == 32.9


def test_activityanalyzer_detect_anomalies_requires_min_events(analyzer, base_time):
    """Test detect_anomalies returns empty when fewer than 5 activities."""
    activities = [mk_act("click", base_time + timedelta(seconds=10 * i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_flags_large_interval(analyzer, base_time):
    """Test detect_anomalies flags an interval with z-score above threshold."""
    # Build 12 timestamps for 'click': 11 intervals (10 small 10s intervals, one large 200s)
    timestamps = []
    small_intervals = [10] * 9
    # Start at t=0, then 9 small intervals
    t = 0
    timestamps.append(base_time + timedelta(seconds=t))
    for s in small_intervals:
        t += s
        timestamps.append(base_time + timedelta(seconds=t))
    # add large interval 200s
    t += 200
    timestamps.append(base_time + timedelta(seconds=t))
    # add final small 10s interval
    t += 10
    timestamps.append(base_time + timedelta(seconds=t))

    activities = [mk_act("click", ts) for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)

    assert len(anomalies) >= 1
    # Expect anomaly at the timestamp immediately following the large interval, i.e., at t after +200
    expected_ts = (base_time + timedelta(seconds=(small_intervals[-1] + sum(small_intervals) + 200))).isoformat()
    assert any(a["action"] == "click" and a["timestamp"] == timestamps[-2].isoformat() for a in anomalies)
    # Check z_score rounded (sqrt(10) ≈ 3.1623 -> 3.16)
    assert any(a["z_score"] == 3.16 for a in anomalies)
    # Ensure reason contains expected text
    assert any("Unusual interval" in a["reason"] for a in anomalies)


def test_activityanalyzer_detect_anomalies_no_std_dev_no_anomaly(analyzer, base_time):
    """Test detect_anomalies does not flag anomalies when std dev is zero."""
    # Uniform intervals -> no anomalies
    timestamps = [base_time + timedelta(seconds=10 * i) for i in range(7)]
    activities = [mk_act("click", ts) for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_analyze_patterns_calls_detectors_and_aggregates(analyzer):
    """Test analyze_patterns calls individual detectors and aggregates their results."""
    activities = [
        {"action": "a", "timestamp": "2025-01-01T09:00:00Z"},
        {"action": "b", "timestamp": "2025-01-01T09:01:00Z"},
        {"action": "c", "timestamp": "2025-01-01T09:02:00Z"},
        {"action": "d", "timestamp": "2025-01-01T09:03:00Z"},
    ]
    mock_peak = [ActivityPattern("peak_hours", "mock peak", 0.1)]
    mock_seq = [ActivityPattern("action_sequence", "mock seq", 0.2)]
    mock_reg = [ActivityPattern("regularity", "mock reg", 0.3)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as p_mock, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as s_mock, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as r_mock:
        patterns = analyzer.analyze_patterns(activities)

        p_mock.assert_called_once()
        s_mock.assert_called_once()
        r_mock.assert_called_once()

        assert patterns == mock_peak + mock_seq + mock_reg


def test_activityanalyzer_analyze_patterns_empty_input_returns_empty(analyzer):
    """Test analyze_patterns returns empty list for empty input."""
    assert analyzer.analyze_patterns([]) == []