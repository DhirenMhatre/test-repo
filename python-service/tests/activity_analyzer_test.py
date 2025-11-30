import pytest
from unittest.mock import patch
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def now():
    """Provide a fixed base datetime for reproducible timestamp tests."""
    return datetime(2021, 1, 1, 0, 0, 0)


def make_activity(action: str, ts):
    """Helper to create an activity dictionary."""
    return {"action": action, "timestamp": ts}


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict output."""
    pattern = ActivityPattern("type1", "desc", 0.42)
    dct = pattern.to_dict()
    assert dct["pattern_type"] == "type1"
    assert dct["description"] == "desc"
    assert dct["confidence"] == 0.42


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default thresholds on initialization."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer, now):
    """Test _parse_timestamp handles datetime, ISO strings, Z-suffix, and invalid values."""
    # datetime passthrough
    assert analyzer._parse_timestamp(now) == now

    # naive ISO string
    iso_str = "2021-01-01T12:34:56"
    parsed = analyzer._parse_timestamp(iso_str)
    assert isinstance(parsed, datetime)
    assert parsed == datetime(2021, 1, 1, 12, 34, 56)

    # Z-suffix ISO string becomes +00:00
    z_str = "2021-01-01T00:00:00Z"
    parsed_z = analyzer._parse_timestamp(z_str)
    assert parsed_z == datetime.fromisoformat("2021-01-01T00:00:00+00:00")

    # invalid string -> None
    assert analyzer._parse_timestamp("invalid-timestamp") is None

    # non-str, non-datetime -> None
    assert analyzer._parse_timestamp(12345) is None


def test_activityanalyzer_analyze_patterns_calls_internal(analyzer, now):
    """Test analyze_patterns delegates to internal detectors and concatenates results."""
    activities = [
        make_activity("A", now),
        make_activity("B", now + timedelta(hours=1)),
        make_activity("C", now + timedelta(hours=2)),
    ]
    p1 = ActivityPattern("peak_hours", "p", 0.8)
    p2 = ActivityPattern("action_sequence", "s", 0.7)
    p3 = ActivityPattern("regularity", "r", 0.9)

    with patch.object(analyzer, "_detect_peak_hours", return_value=[p1]) as m1, \
         patch.object(analyzer, "_detect_action_sequences", return_value=[p2]) as m2, \
         patch.object(analyzer, "_detect_regularity", return_value=[p3]) as m3:
        result = analyzer.analyze_patterns(activities)
        assert result == [p1, p2, p3]
        m1.assert_called_once_with(activities)
        m2.assert_called_once_with(activities)
        m3.assert_called_once_with(activities)


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for no activities and does not call detectors."""
    with patch.object(analyzer, "_detect_peak_hours") as m1, \
         patch.object(analyzer, "_detect_action_sequences") as m2, \
         patch.object(analyzer, "_detect_regularity") as m3:
        result = analyzer.analyze_patterns([])
        assert result == []
        m1.assert_not_called()
        m2.assert_not_called()
        m3.assert_not_called()


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_valid_timestamps(analyzer, now):
    """Test get_user_score computes expected score using parsed timestamps and day span."""
    # 20 actions over 4 days (first to last inclusive difference is 4 days)
    activities = []
    for i in range(20):
        ts = now + timedelta(days=(i // 5))  # 5 actions per day over 4 days (0..3) => last day will be day 3
        # ensure last timestamp is day 4 to get 4 days difference
        if i == 19:
            ts = now + timedelta(days=4)
        action = f"act_{i % 5}"  # 5 unique actions
        activities.append(make_activity(action, ts))

    score = analyzer.get_user_score(activities)
    # Expected calculation:
    # total_actions = 20
    # unique_actions = 5 => diversity = 5/20 = 0.25
    # days_active = 4 => actions_per_day = 5 => frequency = 0.5
    # volume = 20/100 = 0.2
    # final = (0.3*0.25 + 0.4*0.5 + 0.3*0.2) * 100 = 33.5
    assert score == 33.5


def test_activityanalyzer_get_user_score_no_parsable_timestamps(analyzer):
    """Test get_user_score falls back to total actions for frequency when timestamps invalid."""
    activities = [make_activity("act", "not-a-date") for _ in range(5)]
    score = analyzer.get_user_score(activities)
    # total_actions = 5
    # unique_actions = 1 => diversity = 0.2
    # actions_per_day = total_actions => 5 => frequency = 0.5
    # volume = 0.05
    # final = (0.3*0.2 + 0.4*0.5 + 0.3*0.05) * 100 = 27.5
    assert score == 27.5


def test_activityanalyzer_detect_anomalies_identifies_outlier(analyzer, now):
    """Test detect_anomalies flags an unusually long interval for an action."""
    # Build 6 click events; one large interval (600s) among 60s intervals
    times = [
        now,
        now + timedelta(seconds=60),
        now + timedelta(seconds=120),
        now + timedelta(seconds=720),  # +600s from previous (outlier)
        now + timedelta(seconds=780),
        now + timedelta(seconds=840),
    ]
    activities = [make_activity("click", t) for t in times]

    # Lower threshold to ensure detection without exact z-score math
    analyzer.anomaly_threshold = 1.5
    anomalies = analyzer.detect_anomalies(activities)

    assert isinstance(anomalies, list)
    assert len(anomalies) >= 1
    # The anomaly should correspond to the end of the outlier interval (at index 3)
    anomaly_ts = times[3].isoformat()
    assert any(a["action"] == "click" and a["timestamp"] == anomaly_ts and "Unusual interval" in a["reason"] for a in anomalies)


def test_activityanalyzer_detect_anomalies_not_enough_data(analyzer, now):
    """Test detect_anomalies returns empty list when insufficient data."""
    # Less than 5 activities overall
    activities = [
        make_activity("click", now),
        make_activity("click", now + timedelta(seconds=60)),
        make_activity("click", now + timedelta(seconds=120)),
        make_activity("view", now + timedelta(seconds=180)),
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_peak_hours_basic(analyzer, now):
    """Test _detect_peak_hours identifies peak hours exceeding threshold."""
    activities = [
        make_activity("a", now.replace(hour=9)),
        make_activity("b", now.replace(hour=9, minute=10)),
        make_activity("c", now.replace(hour=9, minute=20)),
        make_activity("d", now.replace(hour=21)),
        make_activity("e", now.replace(hour=11)),
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "peak_hours"
    assert pat.confidence == 0.85
    assert "High activity during hours" in pat.description
    assert "09:00" in pat.description
    # Exactly which hours appear depends on threshold; hour 9 definitely included
    # hour 21 likely not (1/5 = 0.2 is not > 0.2), hour 11 not


def test_activityanalyzer_detect_peak_hours_none(analyzer, now):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    activities = [
        make_activity("a", now.replace(hour=8)),
        make_activity("b", now.replace(hour=9)),
        make_activity("c", now.replace(hour=10)),
        make_activity("d", now.replace(hour=11)),
        make_activity("e", now.replace(hour=12)),
    ]
    # Fractions are all 0.2, not strictly greater than 0.2
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_common(analyzer, now):
    """Test _detect_action_sequences finds repeated 3-action sequences."""
    activities = [
        make_activity("A", now + timedelta(seconds=0)),
        make_activity("B", now + timedelta(seconds=1)),
        make_activity("C", now + timedelta(seconds=2)),
        make_activity("D", now + timedelta(seconds=3)),
        make_activity("A", now + timedelta(seconds=4)),
        make_activity("B", now + timedelta(seconds=5)),
        make_activity("C", now + timedelta(seconds=6)),
        make_activity("E", now + timedelta(seconds=7)),
    ]
    patterns = analyzer._detect_action_sequences(activities)
    # The sequence A,B,C occurs twice
    assert any(p.pattern_type == "action_sequence" and "Common sequence: A → B → C (occurred 2 times)" in p.description and p.confidence == 0.75 for p in patterns)


def test_activityanalyzer_detect_action_sequences_insufficient(analyzer):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [
        make_activity("A", "2021-01-01T00:00:00"),
        make_activity("B", "2021-01-01T00:00:01"),
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, now):
    """Test _detect_regularity detects highly regular intervals (low CV)."""
    activities = [
        make_activity("x", now + timedelta(seconds=0)),
        make_activity("x", now + timedelta(seconds=60)),
        make_activity("x", now + timedelta(seconds=120)),
        make_activity("x", now + timedelta(seconds=180)),
        make_activity("x", now + timedelta(seconds=240)),
        make_activity("x", now + timedelta(seconds=300)),
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "regularity"
    assert pat.confidence == 0.9
    assert "Highly regular activity pattern" in pat.description
    assert "(CV: 0.00)" in pat.description


def test_activityanalyzer_detect_regularity_not_regular(analyzer, now):
    """Test _detect_regularity returns empty for irregular intervals (high CV)."""
    activities = [
        make_activity("x", now + timedelta(seconds=0)),
        make_activity("x", now + timedelta(seconds=30)),
        make_activity("x", now + timedelta(seconds=150)),
        make_activity("x", now + timedelta(seconds=160)),
        make_activity("x", now + timedelta(seconds=400)),
        make_activity("x", now + timedelta(seconds=1000)),
    ]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_detect_regularity_unparsable(analyzer):
    """Test _detect_regularity handles unparsable timestamps and returns empty when effective count < 5."""
    activities = [
        make_activity("x", "2021-01-01T00:00:00"),
        make_activity("x", "invalid"),
        make_activity("x", "2021-01-01T00:02:00"),
        make_activity("x", "bad-date"),
        make_activity("x", "2021-01-01T00:06:00"),
        make_activity("x", "2021-01-01T00:08:00"),
    ]
    # Only 4 valid timestamps; should return empty
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_parse_timestamp_z_suffix(analyzer):
    """Test _parse_timestamp correctly handles 'Z' UTC suffix."""
    ts = analyzer._parse_timestamp("2022-06-15T12:00:00Z")
    expected = datetime.fromisoformat("2022-06-15T12:00:00+00:00")
    assert ts == expected