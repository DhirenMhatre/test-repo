import pytest
from unittest.mock import patch
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide an ActivityAnalyzer instance for tests."""
    return ActivityAnalyzer()


def make_activity(ts, action="action"):
    """Helper to create an activity dict."""
    return {"timestamp": ts if isinstance(ts, str) else ts.isoformat(), "action": action}


def test_activitypattern_to_dict_basic():
    """ActivityPattern.to_dict should return the correct mapping."""
    pat = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.9)
    d = pat.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "desc"
    assert d["confidence"] == 0.9
    assert set(d.keys()) == {"pattern_type", "description", "confidence"}


def test_activityanalyzer_init_defaults(analyzer):
    """ActivityAnalyzer should initialize with default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_valid_datetime(analyzer):
    """_parse_timestamp should return the same datetime instance for datetime input."""
    now = datetime(2023, 1, 1, 12, 0, 0)
    parsed = analyzer._parse_timestamp(now)
    assert parsed == now


def test_activityanalyzer_parse_timestamp_valid_iso(analyzer):
    """_parse_timestamp should parse ISO8601 strings, including those with 'Z'."""
    iso = "2023-01-01T12:00:00"
    iso_z = "2023-01-01T12:00:00Z"
    parsed1 = analyzer._parse_timestamp(iso)
    parsed2 = analyzer._parse_timestamp(iso_z)
    assert isinstance(parsed1, datetime)
    assert isinstance(parsed2, datetime)


def test_activityanalyzer_parse_timestamp_invalid(analyzer):
    """_parse_timestamp should return None on invalid inputs without raising exceptions."""
    assert analyzer._parse_timestamp("not-a-timestamp") is None
    assert analyzer._parse_timestamp(12345) is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer):
    """_detect_peak_hours should identify hours exceeding the threshold and format hours correctly."""
    base = datetime(2023, 1, 1, 9, 0, 0)
    activities = []
    # 3 events at 09:00
    activities += [make_activity(base + timedelta(minutes=i), "a") for i in range(3)]
    # 3 events at 10:00
    activities += [make_activity(base.replace(hour=10) + timedelta(minutes=i), "b") for i in range(3)]
    # 4 events at 11:00
    activities += [make_activity(base.replace(hour=11) + timedelta(minutes=i), "c") for i in range(4)]
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "peak_hours"
    assert pat.confidence == 0.85
    # Ensure proper zero-padded hour formatting and inclusion of all peak hours
    assert "09:00" in pat.description
    assert "10:00" in pat.description
    assert "11:00" in pat.description


def test_activityanalyzer_detect_peak_hours_none(analyzer):
    """_detect_peak_hours should return empty list if no hour exceeds threshold."""
    base = datetime(2023, 1, 1, 0, 0, 0)
    activities = [make_activity(base.replace(hour=h), "x") for h in range(5)]  # 1 per hour, none > 20%
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """_detect_peak_hours should return empty list when all timestamps are invalid."""
    activities = [{"timestamp": "invalid", "action": "x"} for _ in range(5)]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_common(analyzer):
    """_detect_action_sequences should find repeated 3-action sequences."""
    actions = ["A", "B", "C", "X", "A", "B", "C", "Y", "A", "B", "C"]
    base = datetime(2023, 1, 1, 0, 0, 0)
    activities = [make_activity(base + timedelta(minutes=i), act) for i, act in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    # 'A,B,C' occurs 3 times
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "action_sequence"
    assert "Common sequence" in pat.description
    assert "A → B → C" in pat.description
    assert "(occurred 3 times)" in pat.description
    assert pat.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_insufficient(analyzer):
    """_detect_action_sequences should return empty list when fewer than 3 activities."""
    base = datetime(2023, 1, 1, 0, 0, 0)
    activities = [make_activity(base, "A"), make_activity(base + timedelta(minutes=1), "B")]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_action_sequences_top3(analyzer):
    """_detect_action_sequences should return up to top 3 sequences with count >= 2."""
    base = datetime(2023, 1, 1, 0, 0, 0)
    # Build repeating sequences:
    # ABC twice, BCD twice, CDE twice, others once
    seq = ["A", "B", "C", "A", "B", "C",
           "B", "C", "D", "B", "C", "D",
           "C", "D", "E", "C", "D", "E",
           "D", "E", "F"]
    activities = [make_activity(base + timedelta(minutes=i), a) for i, a in enumerate(seq)]
    patterns = analyzer._detect_action_sequences(activities)
    descs = [p.description for p in patterns]
    # Ensure the three expected common sequences are present
    assert any("A → B → C" in d for d in descs)
    assert any("B → C → D" in d for d in descs)
    assert any("C → D → E" in d for d in descs)
    # At most 3 patterns
    assert len(patterns) <= 3


def test_activityanalyzer_detect_regularity_regular(analyzer):
    """_detect_regularity should detect highly regular intervals (low CV)."""
    base = datetime(2023, 1, 1, 0, 0, 0)
    activities = [make_activity(base + timedelta(hours=i), "tick") for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "regularity"
    assert "CV: 0.00" in pat.description
    assert pat.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer):
    """_detect_regularity should not return a pattern when activity is irregular."""
    base = datetime(2023, 1, 1, 0, 0, 0)
    offsets = [0, 1, 4, 9, 16, 27]  # irregular spacing in hours
    activities = [make_activity(base + timedelta(hours=o), "event") for o in offsets]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_analyze_patterns_aggregates_and_calls_private(analyzer):
    """analyze_patterns should combine results from private detectors and call them when activities exist."""
    activities = [make_activity(datetime(2023, 1, 1, 0, 0, 0), "a")]
    fake_peak = [ActivityPattern("peak_hours", "peak", 0.85)]
    fake_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    fake_reg = [ActivityPattern("regularity", "reg", 0.9)]
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=fake_peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=fake_seq) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=fake_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)
        m_peak.assert_called_once()
        m_seq.assert_called_once()
        m_reg.assert_called_once()
        # Ensure combined results
        assert patterns == fake_peak + fake_seq + fake_reg


def test_activityanalyzer_analyze_patterns_empty_shortcircuits(analyzer):
    """analyze_patterns should return empty and not call detectors on empty input."""
    with patch.object(ActivityAnalyzer, "_detect_peak_hours") as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences") as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity") as m_reg:
        patterns = analyzer.analyze_patterns([])
        assert patterns == []
        m_peak.assert_not_called()
        m_seq.assert_not_called()
        m_reg.assert_not_called()


def test_activityanalyzer_get_user_score_empty(analyzer):
    """get_user_score should return 0.0 when no activities exist."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_computation(analyzer):
    """get_user_score should compute score based on diversity, frequency, and volume."""
    # 20 actions, 5 unique, over 2 days -> frequency_score=1, volume=0.2, diversity=0.25
    start = datetime(2020, 1, 1, 0, 0, 0)
    end = datetime(2020, 1, 3, 0, 0, 0)
    actions = ["A", "B", "C", "D", "E"] * 4  # 20 total, 5 unique
    activities = []
    for i, a in enumerate(actions):
        # Spread them between start and end; order matters only for first and last
        ts = start + (end - start) * (i / max(len(actions) - 1, 1))
        activities.append(make_activity(ts, a))
    expected = (0.25 * 0.3 + 1.0 * 0.4 + 0.2 * 0.3) * 100
    score = analyzer.get_user_score(activities)
    assert score == round(expected, 2) == 53.5


def test_activityanalyzer_get_user_score_invalid_timestamps_fallback(analyzer):
    """get_user_score should fallback to total_actions for frequency when timestamps are invalid."""
    actions = ["A", "B", "C", "D", "E"]
    activities = [{"timestamp": "invalid", "action": a} for a in actions]
    # diversity 1.0, frequency 0.5 (5/10), volume 0.05
    expected = (1.0 * 0.3 + 0.5 * 0.4 + 0.05 * 0.3) * 100
    score = analyzer.get_user_score(activities)
    assert score == round(expected, 2) == 51.5


def test_activityanalyzer_get_user_score_negative_days_handled(analyzer):
    """get_user_score should handle when last timestamp is earlier than first by using days_active=1."""
    # Provide reversed chronological order: last earlier than first
    t1 = datetime(2023, 1, 2, 0, 0, 0)
    t2 = datetime(2023, 1, 1, 0, 0, 0)
    actions = (["A"] * 4) + (["B"] * 4) + (["C"] * 4)  # total 12, unique 3
    activities = [make_activity(t1, actions[0])]
    for a in actions[1:-1]:
        activities.append(make_activity(t1 + timedelta(minutes=1), a))
    activities.append(make_activity(t2, actions[-1]))  # last earlier than first
    # diversity 3/12=0.25, frequency min(12/1/10,1)=1, volume 12/100=0.12
    expected = (0.25 * 0.3 + 1.0 * 0.4 + 0.12 * 0.3) * 100
    score = analyzer.get_user_score(activities)
    assert score == round(expected, 2) == 51.1


def test_activityanalyzer_detect_anomalies_outlier_interval(analyzer):
    """detect_anomalies should flag unusually large intervals for a repeated action."""
    start = datetime(2023, 1, 1, 0, 0, 0)
    times = [start]
    # 10 intervals of 10s
    for _ in range(10):
        times.append(times[-1] + timedelta(seconds=10))
    # one large interval of 1000s
    times.append(times[-1] + timedelta(seconds=1000))
    activities = [make_activity(t, "click") for t in times]
    # add another action with insufficient occurrences to ensure it's ignored
    activities += [make_activity(start + timedelta(minutes=i), "view") for i in range(2)]
    anomalies = analyzer.detect_anomalies(activities)
    # Should flag exactly one anomaly (the large interval)
    assert len(anomalies) == 1
    anom = anomalies[0]
    assert anom["action"] == "click"
    assert "Unusual interval" in anom["reason"]
    assert anom["z_score"] > analyzer.anomaly_threshold
    # The anomaly timestamp should be the end of the large interval (last timestamp)
    assert anom["timestamp"] == times[-1].isoformat()


def test_activityanalyzer_detect_anomalies_few_activities(analyzer):
    """detect_anomalies should return empty list when there are fewer than 5 activities."""
    start = datetime(2023, 1, 1, 0, 0, 0)
    activities = [make_activity(start + timedelta(seconds=i * 5), "click") for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_constant_intervals(analyzer):
    """detect_anomalies should not flag anomalies when intervals are constant (std_dev == 0)."""
    start = datetime(2023, 1, 1, 0, 0, 0)
    times = [start + timedelta(seconds=10 * i) for i in range(6)]
    activities = [make_activity(t, "click") for t in times]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_multiple_actions(analyzer):
    """detect_anomalies should analyze each action separately and ignore those with insufficient data."""
    base = datetime(2023, 1, 1, 0, 0, 0)
    # Action A with outlier
    times_a = [base]
    for _ in range(10):
        times_a.append(times_a[-1] + timedelta(seconds=10))
    times_a.append(times_a[-1] + timedelta(seconds=1000))
    acts_a = [make_activity(t, "A") for t in times_a]
    # Action B with only two occurrences (ignored)
    acts_b = [make_activity(base + timedelta(minutes=i * 5), "B") for i in range(2)]
    anomalies = analyzer.detect_anomalies(acts_a + acts_b)
    assert len(anomalies) == 1
    assert anomalies[0]["action"] == "A"


def test_activityanalyzer_analyze_patterns_exception_handling_parse(analyzer):
    """analyze_patterns should not be affected by invalid timestamps; detectors handle them gracefully."""
    # Mock detectors to validate that analyze_patterns continues even with invalid timestamps
    invalid_activities = [{"timestamp": "nonsense", "action": "x"} for _ in range(3)]
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[]), \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[]), \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[]):
        result = analyzer.analyze_patterns(invalid_activities)
        assert result == []