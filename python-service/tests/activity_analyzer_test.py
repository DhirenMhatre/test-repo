import pytest
from unittest.mock import patch
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Base datetime for constructing test timestamps."""
    return datetime(2021, 1, 1, 0, 0, 0)


def make_activity(action: str, ts):
    """Helper to create activity dicts."""
    return {"action": action, "timestamp": ts}


def test_activitypattern_to_dict_basic():
    """Test ActivityPattern.to_dict returns correct mapping."""
    ap = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.9)
    d = ap.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "desc",
        "confidence": 0.9,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initializes with default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp handles datetime objects and ISO strings, returns None for invalid."""
    dt = datetime(2021, 1, 1, 12, 34, 56)
    assert analyzer._parse_timestamp(dt) == dt

    dt_z = analyzer._parse_timestamp("2021-01-01T12:34:56Z")
    assert dt_z is not None
    assert dt_z.hour == 12

    dt_off = analyzer._parse_timestamp("2021-01-01T12:34:56+02:00")
    assert dt_off is not None
    assert dt_off.hour == 12

    assert analyzer._parse_timestamp("not-a-date") is None
    assert analyzer._parse_timestamp(12345) is None
    assert analyzer._parse_timestamp(None) is None


def test_activityanalyzer_parse_timestamp_error_handling(monkeypatch, analyzer):
    """Test _parse_timestamp safely handles ValueError from datetime.fromisoformat."""
    class DummyDateTime:
        @classmethod
        def fromisoformat(cls, s):
            raise ValueError("bad format")

    # Patch the datetime class used in the module
    monkeypatch.setattr("src.activity_analyzer.datetime", DummyDateTime)
    # Should return None rather than raising
    assert analyzer._parse_timestamp("2021-01-01T00:00:00") is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours above threshold and formats description."""
    activities = []
    # 3 activities at 09:xx, 2 at 10:xx, total 5 => hour 9 count = 3/5 = 0.6 > 0.2
    for i in range(3):
        activities.append(make_activity("a", base_time.replace(hour=9, minute=i)))
    for i in range(2):
        activities.append(make_activity("a", base_time.replace(hour=10, minute=i)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert isinstance(p, ActivityPattern)
    assert p.pattern_type == "peak_hours"
    assert "09:00" in p.description


def test_activityanalyzer_detect_peak_hours_threshold_edge(analyzer, base_time):
    """Test _detect_peak_hours uses strict greater than threshold, not greater or equal."""
    activities = [
        make_activity("a", base_time.replace(hour=8, minute=0)),
        make_activity("a", base_time.replace(hour=9, minute=0)),
        make_activity("a", base_time.replace(hour=10, minute=0)),
        make_activity("a", base_time.replace(hour=11, minute=0)),
        make_activity("a", base_time.replace(hour=12, minute=0)),
    ]
    # Each hour has 1/5 = 0.2, equal to threshold, should not include any
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_no_parsable_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when timestamps cannot be parsed."""
    activities = [
        make_activity("a", "invalid"),
        make_activity("a", None),
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_common(analyzer):
    """Test _detect_action_sequences identifies repeated 3-action sequences."""
    actions = ["login", "view", "logout", "login", "view", "logout", "other"]
    activities = [make_activity(a, datetime(2021, 1, 1, 0, i, 0)) for i, a in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "Common sequence" in p.description
    assert "login → view → logout" in p.description
    assert "occurred 2 times" in p.description
    assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_limit_top3(analyzer):
    """Test _detect_action_sequences returns at most the top 3 sequences."""
    # Construct four different sequences each repeated twice, separated to avoid overlaps
    seqs = [
        ["A", "B", "C"],
        ["D", "E", "F"],
        ["G", "H", "I"],
        ["J", "K", "L"],
    ]
    actions = []
    minute = 0
    for s in seqs:
        actions.extend(s + ["X"] + s + ["Y"])
    activities = [make_activity(a, datetime(2021, 1, 1, 0, minute + i, 0)) for i, a in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 3
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert "Common sequence" in p.description
        assert "occurred 2 times" in p.description


def test_activityanalyzer_detect_action_sequences_too_short(analyzer):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [make_activity("a", datetime(2021, 1, 1, 0, 0, 0))]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_high(analyzer, base_time):
    """Test _detect_regularity identifies highly regular intervals (low CV)."""
    activities = [make_activity("a", base_time + timedelta(hours=i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_not_enough(analyzer, base_time):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    activities = [make_activity("a", base_time + timedelta(hours=i)) for i in range(4)]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_detect_regularity_not_regular(analyzer, base_time):
    """Test _detect_regularity returns empty when variability is too high."""
    # Intervals: 60, 120, 60, 180, 60 seconds
    t0 = base_time
    timestamps = [
        t0,
        t0 + timedelta(seconds=60),
        t0 + timedelta(seconds=180),
        t0 + timedelta(seconds=240),
        t0 + timedelta(seconds=420),
        t0 + timedelta(seconds=480),
    ]
    activities = [make_activity("a", ts) for ts in timestamps]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list and does not call detectors when no activities."""
    with patch.object(ActivityAnalyzer, "_detect_peak_hours") as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences") as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity") as m3:
        result = analyzer.analyze_patterns([])
        assert result == []
        m1.assert_not_called()
        m2.assert_not_called()
        m3.assert_not_called()


def test_activityanalyzer_analyze_patterns_invokes_detectors(analyzer):
    """Test analyze_patterns aggregates patterns from internal detectors."""
    fake_p1 = ActivityPattern("peak_hours", "d1", 0.1)
    fake_p2 = ActivityPattern("action_sequence", "d2", 0.2)
    fake_p3 = ActivityPattern("regularity", "d3", 0.3)
    activities = [make_activity("a", datetime(2021, 1, 1, 0, 0, 0))]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[fake_p1]) as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[fake_p2]) as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[fake_p3]) as m3:
        result = analyzer.analyze_patterns(activities)
        assert result == [fake_p1, fake_p2, fake_p3]
        m1.assert_called_once_with(activities)
        m2.assert_called_once_with(activities)
        m3.assert_called_once_with(activities)


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_same_day(analyzer, base_time):
    """Test get_user_score calculation when activities occur within the same day."""
    activities = [
        make_activity("login", base_time + timedelta(hours=0)),
        make_activity("view", base_time + timedelta(hours=1)),
        make_activity("view", base_time + timedelta(hours=2)),
        make_activity("logout", base_time + timedelta(hours=3)),
        make_activity("login", base_time + timedelta(hours=4)),
    ]
    score = analyzer.get_user_score(activities)
    # Expected: diversity=3/5=0.6, frequency=5/10=0.5, volume=5/100=0.05
    # final = (0.6*0.3 + 0.5*0.4 + 0.05*0.3) * 100 = 39.5
    assert score == 39.5


def test_activityanalyzer_get_user_score_multi_day(analyzer, base_time):
    """Test get_user_score calculation across multiple days."""
    # 50 actions across 5-day span (difference in .days)
    activities = []
    for i in range(50):
        ts = base_time + timedelta(days=i // 10)  # 10 actions per day over 5 days -> last day index 4
        activities.append(make_activity(f"action_{i % 10}", ts))
    # Ensure first and last reflect the 5-day span (days=4? Use 0..49 -> 0..4 days => .days=4)
    # Adjust to create 5-day span in .days: set last ts to base_time + 5 days
    activities[-1]["timestamp"] = base_time + timedelta(days=5)

    score = analyzer.get_user_score(activities)
    # days_active = 5, actions_per_day=10 -> frequency=1.0, diversity=10/50=0.2, volume=0.5
    # final = (0.2*0.3 + 1.0*0.4 + 0.5*0.3)*100 = 61.0
    assert score == 61.0


def test_activityanalyzer_detect_anomalies_not_enough(analyzer, base_time):
    """Test detect_anomalies returns empty when not enough activities."""
    activities = [make_activity("a", base_time + timedelta(minutes=i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_basic(analyzer, base_time):
    """Test detect_anomalies flags intervals with z-score strictly greater than threshold."""
    # Create 12 timestamps for 'click' action: 10 intervals of 60s, 1 interval of 600s
    timestamps = [base_time + timedelta(seconds=60 * i) for i in range(11)]
    timestamps.append(timestamps[-1] + timedelta(seconds=600))
    activities = [make_activity("click", ts) for ts in timestamps]
    # Add some other action with <3 timestamps to ensure it's ignored
    activities += [
        make_activity("view", base_time + timedelta(hours=1)),
        make_activity("view", base_time + timedelta(hours=2)),
    ]

    anomalies = analyzer.detect_anomalies(activities)
    # Expect one anomaly corresponding to the last timestamp (after the large interval)
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "click"
    assert "Unusual interval" in anomaly["reason"]
    assert anomaly["timestamp"] == timestamps[-1].isoformat()
    assert anomaly["z_score"] >= 3.16  # rounded; expect approximately 3.16


def test_activityanalyzer_detect_anomalies_zscore_equal_threshold_not_reported(analyzer, base_time):
    """Test detect_anomalies does not flag intervals with z-score equal to threshold (strictly greater needed)."""
    # Create 11 timestamps for 'click' action: 9 intervals of 60s, 1 interval large to yield z=3.0
    # Using the math above, with m=9 small and 1 large, z = sqrt(9) = 3.0
    timestamps = [base_time + timedelta(seconds=60 * i) for i in range(10)]
    timestamps.append(timestamps[-1] + timedelta(seconds=600))  # one large gap
    activities = [make_activity("click", ts) for ts in timestamps]

    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []