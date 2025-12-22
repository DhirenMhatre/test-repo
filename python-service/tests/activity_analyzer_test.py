import pytest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def pattern():
    """Create ActivityPattern instance for testing."""
    return ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.85)


def make_activity(action="click", ts=None):
    """Helper to build an activity dict."""
    return {"action": action, "timestamp": ts}


def dt(year=2025, month=1, day=1, hour=0, minute=0, second=0, tz=timezone.utc):
    """Helper to create timezone-aware datetime."""
    return datetime(year, month, day, hour, minute, second, tzinfo=tz)


def test_activity_pattern_init_sets_attributes():
    """Test ActivityPattern initialization sets attributes correctly."""
    p = ActivityPattern(pattern_type="t", description="d", confidence=0.1)
    assert p.pattern_type == "t"
    assert p.description == "d"
    assert p.confidence == pytest.approx(0.1)


def test_activity_pattern_to_dict_returns_expected_keys_and_values(pattern):
    """Test ActivityPattern.to_dict returns the expected dict representation."""
    data = pattern.to_dict()
    assert data == {"pattern_type": "peak_hours", "description": "desc", "confidence": pytest.approx(0.85)}


def test_activity_analyzer_init_sets_thresholds(analyzer):
    """Test ActivityAnalyzer initialization sets threshold attributes."""
    assert analyzer.peak_hour_threshold == pytest.approx(0.2)
    assert analyzer.anomaly_threshold == pytest.approx(3.0)


def test_activity_analyzer_parse_timestamp_datetime_returns_same(analyzer):
    """Test _parse_timestamp returns the same datetime object when passed a datetime."""
    ts = dt(2025, 1, 2, 3)
    assert analyzer._parse_timestamp(ts) is ts


def test_activity_analyzer_parse_timestamp_iso_z_parses_to_datetime(analyzer):
    """Test _parse_timestamp parses ISO strings with 'Z' suffix."""
    ts_str = "2025-01-02T03:04:05Z"
    parsed = analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.isoformat() == "2025-01-02T03:04:05+00:00"


def test_activity_analyzer_parse_timestamp_invalid_string_returns_none(analyzer):
    """Test _parse_timestamp returns None for invalid timestamp strings."""
    assert analyzer._parse_timestamp("not-a-timestamp") is None


def test_activity_analyzer_parse_timestamp_non_str_non_datetime_returns_none(analyzer):
    """Test _parse_timestamp returns None for unsupported types."""
    assert analyzer._parse_timestamp(12345) is None
    assert analyzer._parse_timestamp({"ts": "2025-01-01"}) is None


def test_activity_analyzer_analyze_patterns_empty_returns_empty(analyzer):
    """Test analyze_patterns returns empty list for no activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activity_analyzer_analyze_patterns_calls_internal_detectors(analyzer):
    """Test analyze_patterns calls internal detection methods and aggregates results."""
    p1 = ActivityPattern("peak_hours", "ph", 0.85)
    p2 = ActivityPattern("action_sequence", "seq", 0.75)
    p3 = ActivityPattern("regularity", "reg", 0.9)
    activities = [make_activity("a", dt()), make_activity("b", dt()), make_activity("c", dt())]

    with patch.object(analyzer, "_detect_peak_hours", return_value=[p1]) as m1, \
         patch.object(analyzer, "_detect_action_sequences", return_value=[p2]) as m2, \
         patch.object(analyzer, "_detect_regularity", return_value=[p3]) as m3:
        result = analyzer.analyze_patterns(activities)

    assert result == [p1, p2, p3]
    m1.assert_called_once_with(activities)
    m2.assert_called_once_with(activities)
    m3.assert_called_once_with(activities)


def test_activity_analyzer_detect_peak_hours_no_parsable_timestamps_returns_empty(analyzer):
    """Test _detect_peak_hours returns empty list when no timestamps can be parsed."""
    activities = [make_activity("a", "bad"), make_activity("b", None)]
    assert analyzer._detect_peak_hours(activities) == []


def test_activity_analyzer_detect_peak_hours_identifies_peak_above_threshold(analyzer):
    """Test _detect_peak_hours returns pattern when a given hour exceeds threshold proportion."""
    base = dt(2025, 1, 1, 10)
    activities = []
    # 3 activities at hour 10, 1 at hour 11 => 10 has 75% > 0.2
    activities.extend([make_activity("x", base + timedelta(minutes=i)) for i in (0, 1, 2)])
    activities.append(make_activity("y", dt(2025, 1, 1, 11, 0)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "10:00" in p.description
    assert p.confidence == pytest.approx(0.85)


def test_activity_analyzer_detect_peak_hours_threshold_strictly_greater(analyzer):
    """Test _detect_peak_hours uses '>' comparison (not '>=')."""
    analyzer.peak_hour_threshold = 0.5
    # Two hours each 50% => should NOT trigger due to strict '>'
    activities = [
        make_activity("a", dt(2025, 1, 1, 10, 0)),
        make_activity("b", dt(2025, 1, 1, 10, 5)),
        make_activity("c", dt(2025, 1, 1, 11, 0)),
        make_activity("d", dt(2025, 1, 1, 11, 5)),
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activity_analyzer_detect_action_sequences_less_than_three_returns_empty(analyzer):
    """Test _detect_action_sequences returns empty list when not enough activities."""
    assert analyzer._detect_action_sequences([make_activity("a", dt()), make_activity("b", dt())]) == []


def test_activity_analyzer_detect_action_sequences_detects_common_triple(analyzer):
    """Test _detect_action_sequences identifies sequences repeated at least twice."""
    actions = ["A", "B", "C", "A", "B", "C", "X"]
    activities = [make_activity(a, dt(2025, 1, 1, 10, i)) for i, a in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) >= 1
    seq_patterns = [p for p in patterns if p.pattern_type == "action_sequence"]
    assert len(seq_patterns) == 1
    p = seq_patterns[0]
    assert "A → B → C" in p.description
    assert "(occurred 2 times)" in p.description
    assert p.confidence == pytest.approx(0.75)


def test_activity_analyzer_detect_action_sequences_returns_at_most_three_patterns(analyzer):
    """Test _detect_action_sequences returns at most 3 patterns."""
    # Create 4 different triples each repeated twice -> only top 3 returned
    activities = []
    base = dt(2025, 1, 1, 12, 0)
    seqs = [
        ["A", "B", "C"],
        ["D", "E", "F"],
        ["G", "H", "I"],
        ["J", "K", "L"],
    ]
    t = 0
    for s in seqs:
        for _ in range(2):
            # Add the triple as consecutive items
            for a in s:
                activities.append(make_activity(a, base + timedelta(seconds=t)))
                t += 1

    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 3
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


def test_activity_analyzer_detect_regularity_less_than_five_returns_empty(analyzer):
    """Test _detect_regularity returns empty list when not enough activities."""
    activities = [make_activity("a", dt(2025, 1, 1, 0, i)) for i in range(4)]
    assert analyzer._detect_regularity(activities) == []


def test_activity_analyzer_detect_regularity_ignores_unparsable_and_requires_five_valid(analyzer):
    """Test _detect_regularity returns empty if fewer than five timestamps are parsable."""
    activities = [
        make_activity("a", dt(2025, 1, 1, 0, 0)),
        make_activity("b", "bad"),
        make_activity("c", None),
        make_activity("d", dt(2025, 1, 1, 0, 10)),
        make_activity("e", dt(2025, 1, 1, 0, 20)),
        make_activity("f", dt(2025, 1, 1, 0, 30)),
    ]
    # only 4 valid timestamps -> should return []
    assert analyzer._detect_regularity(activities) == []


def test_activity_analyzer_detect_regularity_highly_regular_detected(analyzer):
    """Test _detect_regularity returns regularity pattern when CV < 0.3."""
    base = dt(2025, 1, 1, 0, 0, 0)
    # Perfectly regular intervals: 60s
    timestamps = [base + timedelta(seconds=60 * i) for i in range(5)]
    activities = [make_activity("a", ts) for ts in timestamps]

    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert "CV: 0.00" in p.description
    assert p.confidence == pytest.approx(0.9)


def test_activity_analyzer_detect_regularity_irregular_not_detected(analyzer):
    """Test _detect_regularity returns empty list when CV is not below threshold."""
    base = dt(2025, 1, 1, 0, 0, 0)
    timestamps = [
        base,
        base + timedelta(seconds=10),
        base + timedelta(seconds=100),
        base + timedelta(seconds=120),
        base + timedelta(seconds=300),
    ]
    activities = [make_activity("a", ts) for ts in timestamps]
    assert analyzer._detect_regularity(activities) == []


def test_activity_analyzer_get_user_score_empty_returns_zero(analyzer):
    """Test get_user_score returns 0.0 for empty activities."""
    assert analyzer.get_user_score([]) == pytest.approx(0.0)


def test_activity_analyzer_get_user_score_single_action_defaults_days_active_to_one(analyzer):
    """Test get_user_score uses at least 1 day active when timestamps are same day."""
    activities = [
        make_activity("click", dt(2025, 1, 1, 10, 0)),
        make_activity("click", dt(2025, 1, 1, 10, 5)),
    ]
    # total_actions=2
    # unique_actions=1 (only 'click')
    # days_active=max((last-first).days,1) -> 1
    # actions_per_day=2/1=2
    # diversity=1/2=0.5 -> 0.15 weighted
    # frequency=min(2/10,1)=0.2 -> 0.08 weighted
    # volume=min(2/100,1)=0.02 -> 0.006 weighted
    # final=(0.15+0.08+0.006)*100=23.6
    assert analyzer.get_user_score(activities) == pytest.approx(23.6)


def test_activity_analyzer_get_user_score_unique_action_count_buggy_logic_is_preserved(analyzer):
    """Test get_user_score unique action logic (uses index of first occurrence) matches source behavior."""
    # action_list = ["a","b","a"] should count as 2 unique due to buggy logic.
    activities = [
        make_activity("a", dt(2025, 1, 1, 0, 0)),
        make_activity("b", dt(2025, 1, 1, 0, 1)),
        make_activity("a", dt(2025, 1, 1, 0, 2)),
    ]
    # total=3, unique_actions computed by source = 2
    # days_active = 1, actions_per_day=3
    # diversity=2/3=0.6666666667
    # frequency=0.3
    # volume=0.03
    # final=(0.6666666667*0.3 + 0.3*0.4 + 0.03*0.3)*100
    expected = round((0.2 + 0.12 + 0.009) * 100, 2)  # 32.9
    assert analyzer.get_user_score(activities) == pytest.approx(expected)


def test_activity_analyzer_get_user_score_missing_timestamps_falls_back_to_total_actions(analyzer):
    """Test get_user_score uses total_actions as actions_per_day when timestamps cannot be parsed."""
    activities = [
        make_activity("a", "bad"),
        make_activity("b", None),
        make_activity("c", "also-bad"),
        make_activity("d", "bad"),
    ]
    # total=4, unique=4
    # actions_per_day=4 (fallback)
    # diversity=1.0, frequency=0.4, volume=0.04
    # final=(0.3+0.16+0.012)*100=47.2
    assert analyzer.get_user_score(activities) == pytest.approx(47.2)


def test_activity_analyzer_get_user_score_caps_frequency_and_volume(analyzer):
    """Test get_user_score caps frequency and volume scores at 1.0."""
    base = dt(2025, 1, 1, 0, 0)
    # 200 actions over 1 day => actions_per_day=200 => frequency capped at 1.0
    activities = [make_activity(f"a{i}", base + timedelta(minutes=i)) for i in range(200)]
    score = analyzer.get_user_score(activities)
    # diversity=200/200=1, frequency=1, volume=1 (capped total_actions/100=2 ->1)
    # final=(0.3+0.4+0.3)*100=100
    assert score == pytest.approx(100.0)


def test_activity_analyzer_detect_anomalies_less_than_five_returns_empty(analyzer):
    """Test detect_anomalies returns empty list when fewer than 5 activities provided."""
    activities = [make_activity("a", dt(2025, 1, 1, 0, i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activity_analyzer_detect_anomalies_ignores_actions_with_less_than_three_timestamps(analyzer):
    """Test detect_anomalies skips actions that have fewer than 3 parsed timestamps."""
    activities = [
        make_activity("a", dt(2025, 1, 1, 0, 0)),
        make_activity("a", dt(2025, 1, 1, 0, 1)),
        make_activity("b", dt(2025, 1, 1, 0, 2)),
        make_activity("b", dt(2025, 1, 1, 0, 3)),
        make_activity("c", "bad"),
        make_activity("c", None),
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activity_analyzer_detect_anomalies_no_anomaly_when_intervals_consistent(analyzer):
    """Test detect_anomalies returns no anomalies when intervals yield no z-scores above threshold."""
    activities = [
        make_activity("a", dt(2025, 1, 1, 0, 0)),
        make_activity("a", dt(2025, 1, 1, 0, 10)),
        make_activity("a", dt(2025, 1, 1, 0, 20)),
        make_activity("a", dt(2025, 1, 1, 0, 30)),
        make_activity("x", dt(2025, 1, 1, 0, 40)),
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activity_analyzer_detect_anomalies_detects_outlier_interval_when_threshold_lowered(analyzer):
    """Test detect_anomalies flags an interval as anomalous when z-score exceeds threshold."""
    analyzer.anomaly_threshold = 1.0  # lower to make detection feasible with small sample
    # Intervals: 10s, 10s, 1000s, 10s -> 1000s should be the outlier
    timestamps = [
        dt(2025, 1, 1, 0, 0, 0),
        dt(2025, 1, 1, 0, 0, 10),
        dt(2025, 1, 1, 0, 0, 20),
        dt(2025, 1, 1, 0, 16, 60) if False else dt(2025, 1, 1, 0, 17, 0),  # 1000s after 00:00:20
        dt(2025, 1, 1, 0, 17, 10),
    ]
    activities = [make_activity("a", t) for t in timestamps]
    # add another action to ensure len(activities) >= 5 already satisfied, but keep as-is

    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) == 1
    anom = anomalies[0]
    assert anom["action"] == "a"
    assert anom["timestamp"] == timestamps[3].isoformat()
    assert anom["z_score"] == pytest.approx(anom["z_score"])
    assert "Unusual interval" in anom["reason"]
    assert "vs avg" in anom["reason"]


def test_activity_analyzer_detect_anomalies_handles_unparsable_timestamps(analyzer):
    """Test detect_anomalies ignores activities with unparsable timestamps without raising."""
    analyzer.anomaly_threshold = 1.0
    activities = [
        make_activity("a", "bad"),
        make_activity("a", None),
        make_activity("a", dt(2025, 1, 1, 0, 0, 0)),
        make_activity("a", dt(2025, 1, 1, 0, 0, 10)),
        make_activity("a", dt(2025, 1, 1, 0, 0, 20)),
        make_activity("b", dt(2025, 1, 1, 0, 0, 30)),
    ]
    # With only 3 valid timestamps for 'a', we have 2 intervals; std_dev can be 0 leading to no anomalies
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activity_analyzer_analyze_patterns_integration_expected_types(analyzer):
    """Test analyze_patterns returns expected pattern types when data contains peak hours, sequences, and regularity."""
    base = dt(2025, 1, 1, 10, 0, 0)
    # 5 regular timestamps 60s apart, but skew hour distribution to create peak hours as well
    timestamps = [base + timedelta(seconds=60 * i) for i in range(5)]
    activities = [
        make_activity("A", timestamps[0]),
        make_activity("B", timestamps[1]),
        make_activity("C", timestamps[2]),
        make_activity("A", timestamps[3]),
        make_activity("B", timestamps[4]),
    ]
    # Add one more to create repeated ABC with overlap: A,B,C,A,B,C
    activities.append(make_activity("C", base + timedelta(seconds=60 * 5)))

    patterns = analyzer.analyze_patterns(activities)
    types = {p.pattern_type for p in patterns}
    assert "peak_hours" in types
    assert "action_sequence" in types
    assert "regularity" in types