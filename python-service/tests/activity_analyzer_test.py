import pytest
from unittest.mock import patch
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide a fresh ActivityAnalyzer instance for each test."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing test timestamps."""
    return datetime(2025, 1, 1, 9, 0, 0)


def make_activity(ts, action="act"):
    """Helper to create an activity dict with ISO timestamp string."""
    if isinstance(ts, datetime):
        iso = ts.isoformat()
    else:
        iso = ts
    return {"timestamp": iso, "action": action}


def test_activitypattern_to_dict_basic():
    """Test ActivityPattern.to_dict returns expected dictionary."""
    pat = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.9)
    d = pat.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "desc"
    assert d["confidence"] == 0.9


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_valid_variants(analyzer, base_time):
    """Test _parse_timestamp handles datetime object and ISO strings with/without Z."""
    # Direct datetime
    dt = analyzer._parse_timestamp(base_time)
    assert isinstance(dt, datetime)
    assert dt == base_time

    # ISO with Z
    iso_z = "2025-01-01T10:00:00Z"
    dt2 = analyzer._parse_timestamp(iso_z)
    assert isinstance(dt2, datetime)
    assert dt2.hour == 10

    # ISO without Z
    iso = "2025-01-01T11:30:00"
    dt3 = analyzer._parse_timestamp(iso)
    assert isinstance(dt3, datetime)
    assert dt3.hour == 11

    # Invalid
    assert analyzer._parse_timestamp("not-a-timestamp") is None


def test_activityanalyzer_parse_timestamp_handles_valueerror(analyzer):
    """Test _parse_timestamp gracefully handles ValueError from fromisoformat."""
    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=ValueError):
        assert analyzer._parse_timestamp("2025-01-01T00:00:00") is None


def test_activityanalyzer_detect_peak_hours_identifies_peaks(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    activities = []
    # 5 activities at 10:00
    for i in range(5):
        activities.append(make_activity(base_time.replace(hour=10) + timedelta(minutes=i), action="x"))
    # 3 at 09:00
    for i in range(3):
        activities.append(make_activity(base_time.replace(hour=9) + timedelta(minutes=i), action="y"))
    # 2 at 15:00
    for i in range(2):
        activities.append(make_activity(base_time.replace(hour=15) + timedelta(minutes=i), action="z"))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "peak_hours"
    assert "High activity during hours:" in pat.description
    # 10 total, 5 and 3 should be included (> 0.2), 2 should not (== 0.2)
    assert "09:00" in pat.description
    assert "10:00" in pat.description
    assert "15:00" not in pat.description


def test_activityanalyzer_detect_peak_hours_no_peaks(analyzer, base_time):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    activities = []
    # 10 activities evenly across 5 hours -> each 0.2 proportion (not strictly >)
    hours = [8, 9, 10, 11, 12]
    for h in hours:
        for i in range(2):
            activities.append(make_activity(base_time.replace(hour=h) + timedelta(minutes=i), action=str(h)))
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_common(analyzer, base_time):
    """Test _detect_action_sequences finds common 3-action sequences."""
    actions = ["A", "B", "C", "A", "B", "C", "A"]
    activities = [
        make_activity(base_time + timedelta(minutes=i), action=act) for i, act in enumerate(actions)
    ]

    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 2
    for pat in patterns:
        assert pat.pattern_type == "action_sequence"
        assert "Common sequence:" in pat.description
        assert "occurred 2 times" in pat.description


def test_activityanalyzer_detect_action_sequences_short_input(analyzer, base_time):
    """Test _detect_action_sequences returns empty for fewer than 3 activities."""
    activities = [
        make_activity(base_time, action="A"),
        make_activity(base_time + timedelta(minutes=1), action="B"),
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_high(analyzer, base_time):
    """Test _detect_regularity returns pattern for low coefficient of variation."""
    # 6 events exactly 1 day apart
    activities = [
        make_activity(base_time + timedelta(days=i), action="tick") for i in range(6)
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pat.description
    assert pat.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty for irregular intervals (high CV)."""
    # Intervals: 1h, 3h, 12h, 36h, etc.
    times = [
        base_time,
        base_time + timedelta(hours=1),
        base_time + timedelta(hours=4),
        base_time + timedelta(hours=16),
        base_time + timedelta(hours=52),
        base_time + timedelta(hours=80),
    ]
    activities = [make_activity(t, action="vary") for t in times]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_analyze_patterns_combines_results(analyzer, base_time):
    """Test analyze_patterns combines results from all internal detectors."""
    activities = [
        make_activity(base_time + timedelta(minutes=i), action="A") for i in range(10)
    ]
    fake_peak = [ActivityPattern("peak_hours", "peaks", 0.85)]
    fake_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    fake_reg = [ActivityPattern("regularity", "reg", 0.9)]
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=fake_peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=fake_seq) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=fake_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)
        assert len(patterns) == 3
        assert patterns[0].pattern_type == "peak_hours"
        assert patterns[1].pattern_type == "action_sequence"
        assert patterns[2].pattern_type == "regularity"
        m_peak.assert_called_once()
        m_seq.assert_called_once()
        m_reg.assert_called_once()


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for no activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_computation(analyzer, base_time):
    """Test get_user_score computes expected score with valid timestamps."""
    # 10 actions over 6 days (Jan1 to Jan6 -> days_active=5)
    actions = ["a", "b", "c", "d", "e", "a", "b", "c", "d", "e"]
    activities = []
    for i, act in enumerate(actions):
        day = i // 2  # two per day
        t = base_time + timedelta(days=day, minutes=i)
        activities.append({"timestamp": t.isoformat(), "action": act})

    score = analyzer.get_user_score(activities)
    # Expected: diversity 5/10=0.5, freq (10/5)/10=0.2, volume 10/100=0.1
    # final = (0.5*0.3 + 0.2*0.4 + 0.1*0.3)*100 = 26.0
    assert score == 26.0


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_no_valid_timestamps(analyzer):
    """Test get_user_score when timestamps cannot be parsed uses total_actions as frequency."""
    activities = []
    actions = ["a", "b", "c", "d", "e", "a", "b", "c", "d", "e"]
    for act in actions:
        activities.append({"timestamp": "invalid-ts", "action": act})
    score = analyzer.get_user_score(activities)
    # actions_per_day=total_actions=10 -> frequency=1.0
    # diversity=0.5, volume=0.1
    # final=(0.5*0.3 + 1.0*0.4 + 0.1*0.3)*100 = 58.0
    assert score == 58.0


def test_activityanalyzer_detect_anomalies_flags_with_low_threshold(analyzer, base_time):
    """Test detect_anomalies flags interval anomaly when threshold is lowered."""
    # 6 login events: mostly 60s apart, one big gap
    times = [
        base_time,
        base_time + timedelta(seconds=60),
        base_time + timedelta(seconds=120),
        base_time + timedelta(seconds=180),
        base_time + timedelta(seconds=180 + 600),  # big gap here
        base_time + timedelta(seconds=180 + 600 + 60),
    ]
    activities = [make_activity(t, action="login") for t in times]

    analyzer.anomaly_threshold = 0.5  # Make it easy to flag
    anomalies = analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)
    assert len(anomalies) >= 1
    assert anomalies[0]["action"] == "login"
    assert "Unusual interval" in anomalies[0]["reason"]
    assert anomalies[0]["z_score"] >= analyzer.anomaly_threshold


def test_activityanalyzer_detect_anomalies_requires_min_activities(analyzer, base_time):
    """Test detect_anomalies returns empty when fewer than 5 total activities."""
    times = [
        base_time,
        base_time + timedelta(seconds=60),
        base_time + timedelta(seconds=120),
        base_time + timedelta(seconds=180),
    ]
    activities = [make_activity(t, action="login") for t in times]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_constant_intervals_no_stddev(analyzer, base_time):
    """Test detect_anomalies returns empty when intervals have zero std deviation."""
    times = [
        base_time + timedelta(seconds=60 * i) for i in range(6)
    ]
    activities = [make_activity(t, action="login") for t in times]
    # Default threshold; with zero std_dev no anomalies should be flagged
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []