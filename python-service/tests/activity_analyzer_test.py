import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide a fresh ActivityAnalyzer instance for each test."""
    return ActivityAnalyzer()


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict output."""
    ap = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.9)
    assert ap.pattern_type == "peak_hours"
    assert ap.description == "desc"
    assert ap.confidence == 0.9

    d = ap.to_dict()
    assert d == {"pattern_type": "peak_hours", "description": "desc", "confidence": 0.9}


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp with datetime, ISO strings with Z, invalid input."""
    dt = datetime(2025, 1, 1, 12, 30, 0)
    assert analyzer._parse_timestamp(dt) == dt

    iso_z = "2025-01-01T12:30:00Z"
    parsed = analyzer._parse_timestamp(iso_z)
    assert isinstance(parsed, datetime)
    assert parsed.hour == 12
    assert parsed.minute == 30

    invalid = "not-a-timestamp"
    assert analyzer._parse_timestamp(invalid) is None

    assert analyzer._parse_timestamp(12345) is None
    assert analyzer._parse_timestamp(None) is None


def test_activityanalyzer_detect_peak_hours_single_hour(analyzer):
    """Detect a single peak hour where one hour dominates activity."""
    base = datetime(2025, 1, 1, 0, 0, 0)
    activities = []

    # 10 activities at hour 9
    for i in range(10):
        activities.append({"action": "a", "timestamp": base.replace(hour=9) + timedelta(minutes=i)})

    # 2 activities at hour 10
    for i in range(2):
        activities.append({"action": "b", "timestamp": base.replace(hour=10) + timedelta(minutes=i)})

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "High activity during hours: 09:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_none(analyzer):
    """Return empty list when no valid timestamps or no peak exceeds threshold."""
    activities = [{"action": "a", "timestamp": "invalid"}, {"action": "b", "timestamp": None}]
    assert analyzer._detect_peak_hours(activities) == []

    # Set very high threshold to force no peaks
    analyzer.peak_hour_threshold = 0.99
    base = datetime(2025, 1, 1, 8, 0, 0)
    act = [{"action": "a", "timestamp": base + timedelta(hours=i)} for i in range(5)]
    assert analyzer._detect_peak_hours(act) == []


def test_activityanalyzer_detect_action_sequences_identifies_common(analyzer):
    """Detect common action sequences of length 3 occurring at least twice."""
    activities = [
        {"action": "A", "timestamp": datetime(2025, 1, 1, 9, 0, 0)},
        {"action": "B", "timestamp": datetime(2025, 1, 1, 9, 0, 1)},
        {"action": "C", "timestamp": datetime(2025, 1, 1, 9, 0, 2)},
        {"action": "A", "timestamp": datetime(2025, 1, 1, 9, 0, 3)},
        {"action": "B", "timestamp": datetime(2025, 1, 1, 9, 0, 4)},
        {"action": "C", "timestamp": datetime(2025, 1, 1, 9, 0, 5)},
        {"action": "D", "timestamp": datetime(2025, 1, 1, 9, 0, 6)},
    ]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) >= 1
    assert patterns[0].pattern_type == "action_sequence"
    assert "Common sequence: A → B → C (occurred 2 times)" in patterns[0].description
    assert patterns[0].confidence == 0.75


def test_activityanalyzer_detect_action_sequences_insufficient(analyzer):
    """Return empty list if fewer than 3 activities."""
    activities = [{"action": "A", "timestamp": datetime(2025, 1, 1, 9, 0, 0)}]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer):
    """Detect highly regular activity when intervals are consistent (low CV)."""
    base = datetime(2025, 1, 1, 9, 0, 0)
    activities = []
    for i in range(6):
        activities.append({"action": "A", "timestamp": base + timedelta(minutes=10 * i)})

    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern (CV: 0.00)" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer):
    """Do not detect regularity when intervals vary greatly."""
    timestamps = [
        datetime(2025, 1, 1, 9, 0, 0),
        datetime(2025, 1, 1, 9, 1, 0),
        datetime(2025, 1, 1, 9, 10, 0),
        datetime(2025, 1, 1, 9, 40, 0),
        datetime(2025, 1, 1, 10, 40, 0),
        datetime(2025, 1, 1, 12, 40, 0),
    ]
    activities = [{"action": "A", "timestamp": t} for t in timestamps]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_analyze_patterns_combines_and_calls_detectors(analyzer):
    """Ensure analyze_patterns calls internal detectors and combines their results."""
    activities = [{"action": "A", "timestamp": datetime(2025, 1, 1, 9, 0, 0)} for _ in range(6)]

    fake_peak = [ActivityPattern("peak_hours", "peak", 0.85)]
    fake_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    fake_reg = [ActivityPattern("regularity", "reg", 0.9)]

    with patch.object(analyzer, "_detect_peak_hours", return_value=fake_peak) as m_peak, \
         patch.object(analyzer, "_detect_action_sequences", return_value=fake_seq) as m_seq, \
         patch.object(analyzer, "_detect_regularity", return_value=fake_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)

    m_peak.assert_called_once_with(activities)
    m_seq.assert_called_once_with(activities)
    m_reg.assert_called_once_with(activities)

    assert patterns == fake_peak + fake_seq + fake_reg


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """analyze_patterns returns empty list on empty activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_with_valid_timestamps(analyzer):
    """Compute user score using valid timestamps and verify expected result."""
    # 4 activities over 2 days, actions A, B, A, C -> unique_actions = 3
    activities = [
        {"action": "A", "timestamp": datetime(2025, 1, 1, 0, 0, 0)},
        {"action": "B", "timestamp": datetime(2025, 1, 1, 12, 0, 0)},
        {"action": "A", "timestamp": datetime(2025, 1, 2, 0, 0, 0)},
        {"action": "C", "timestamp": datetime(2025, 1, 3, 0, 0, 0)},
    ]
    # total_actions=4, days_active=(last-first).days=2 -> actions_per_day=2
    # diversity=3/4=0.75, frequency=min(2/10,1)=0.2, volume=min(4/100,1)=0.04
    # final=(0.75*0.3 + 0.2*0.4 + 0.04*0.3)*100 = 31.7
    score = analyzer.get_user_score(activities)
    assert score == 31.7


def test_activityanalyzer_get_user_score_with_invalid_timestamps(analyzer):
    """Compute user score falling back when timestamps cannot be parsed."""
    activities = [
        {"action": "A", "timestamp": "invalid"},
        {"action": "B", "timestamp": "also-invalid"},
        {"action": "A", "timestamp": None},
        {"action": "C", "timestamp": 12345},
    ]
    # total_actions=4, actions_per_day falls back to total_actions=4
    # diversity=3/4=0.75, frequency=min(4/10,1)=0.4, volume=min(4/100,1)=0.04
    # final=(0.75*0.3 + 0.4*0.4 + 0.04*0.3)*100 = 39.7
    score = analyzer.get_user_score(activities)
    assert score == 39.7


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Return 0.0 score for empty activities."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_detect_anomalies_minimum_length(analyzer):
    """No anomalies detected if fewer than 5 activities."""
    activities = [{"action": "A", "timestamp": datetime(2025, 1, 1, 0, 0, 0)} for _ in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_std_zero_no_anomaly(analyzer):
    """When intervals have zero std deviation, no anomalies should be reported."""
    base = datetime(2025, 1, 1, 0, 0, 0)
    # 6 timestamps at equal 10s intervals for action 'click'
    activities = []
    for i in range(6):
        activities.append({"action": "click", "timestamp": base + timedelta(seconds=10 * i)})

    anomalies = analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)
    assert len(anomalies) == 0


def test_activityanalyzer_detect_anomalies_flags_outlier_interval(analyzer):
    """Detect anomalies when an interval deviates more than anomaly_threshold z-scores."""
    base = datetime(2025, 1, 1, 0, 0, 0)
    activities = []

    # 22 timestamps for 'click': 21 intervals with one large jump at the end
    for i in range(21):
        activities.append({"action": "click", "timestamp": base + timedelta(seconds=10 * i)})

    # Large jump
    big_ts = base + timedelta(seconds=10 * 20 + 400)
    activities.append({"action": "click", "timestamp": big_ts})

    # Add some noise for other actions to ensure len(activities) >= 5 and mixed content
    activities.extend([
        {"action": "view", "timestamp": base + timedelta(seconds=5)},
        {"action": "view", "timestamp": base + timedelta(seconds=15)},
    ])

    anomalies = analyzer.detect_anomalies(activities)
    # Expect a single anomaly for the large interval, at timestamp big_ts
    assert len(anomalies) >= 1
    found = [a for a in anomalies if a["action"] == "click"]
    assert len(found) >= 1
    # Ensure at least one anomaly corresponds to the timestamp after the large interval
    assert any(a["timestamp"] == big_ts.isoformat() and a["z_score"] > analyzer.anomaly_threshold and "Unusual interval" in a["reason"] for a in found)


def test_activityanalyzer_parse_timestamp_error_handling_does_not_raise(analyzer):
    """_parse_timestamp should not raise for malformed strings; it should return None."""
    bad = "2025-13-99T25:61:61Z"  # clearly invalid date/time
    result = analyzer._parse_timestamp(bad)
    assert result is None


def test_activityanalyzer_analyze_patterns_propagates_internal_results_with_mock(analyzer):
    """analyze_patterns should concatenate results from detector methods using mocks."""
    activities = [{"action": "X", "timestamp": datetime(2025, 1, 1, 0, 0, 0)} for _ in range(10)]
    p1 = ActivityPattern("peak_hours", "p1", 0.85)
    p2 = ActivityPattern("action_sequence", "p2", 0.75)
    p3 = ActivityPattern("regularity", "p3", 0.9)

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[p1]) as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[p2]) as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[p3]) as m3:
        patterns = analyzer.analyze_patterns(activities)

    assert patterns == [p1, p2, p3]
    m1.assert_called_once_with(activities)
    m2.assert_called_once_with(activities)
    m3.assert_called_once_with(activities)