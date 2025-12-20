import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Provide an ActivityAnalyzer instance."""
    return ActivityAnalyzer()


def test_activitypattern_to_dict_basic():
    """Test ActivityPattern to_dict outputs the correct dictionary."""
    p = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.9)
    d = p.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "desc"
    assert d["confidence"] == 0.9


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp with datetime, ISO string, and invalid string."""
    # datetime instance
    dt = datetime(2024, 1, 1, 12, 0, 0)
    parsed_dt = analyzer._parse_timestamp(dt)
    assert parsed_dt == dt

    # ISO string with Z
    iso_str = "2024-01-01T12:00:00Z"
    parsed_iso = analyzer._parse_timestamp(iso_str)
    assert parsed_iso is not None
    assert parsed_iso.tzinfo is not None
    assert parsed_iso.utcoffset() == timedelta(0)
    assert parsed_iso.replace(tzinfo=None) == datetime(2024, 1, 1, 12, 0, 0)

    # Invalid string returns None, no exception
    bad = "not-a-timestamp"
    assert analyzer._parse_timestamp(bad) is None

    # Unsupported type returns None, no exception
    assert analyzer._parse_timestamp(12345) is None


def test_activityanalyzer_detect_peak_hours_threshold(analyzer):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    base = datetime(2024, 1, 1, 14, 0, 0)

    activities = []
    # 14:00 hour - 5 times
    for i in range(5):
        activities.append({"action": "x", "timestamp": base + timedelta(minutes=i)})

    # 16:00 hour - 3 times
    for i in range(3):
        activities.append({"action": "x", "timestamp": datetime(2024, 1, 1, 16, i, 0)})

    # 20:00 hour - 2 times (exactly 0.2, should not be included because threshold is strict >)
    for i in range(2):
        activities.append({"action": "x", "timestamp": datetime(2024, 1, 1, 20, i, 0)})

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "14:00" in p.description
    assert "16:00" in p.description
    assert "20:00" not in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_action_sequences_common(analyzer):
    """Test _detect_action_sequences finds repeated 3-action sequences."""
    activities = [
        {"action": "A", "timestamp": datetime(2024, 1, 1, 10, 0, 0)},
        {"action": "B", "timestamp": datetime(2024, 1, 1, 10, 1, 0)},
        {"action": "C", "timestamp": datetime(2024, 1, 1, 10, 2, 0)},
        {"action": "A", "timestamp": datetime(2024, 1, 1, 10, 3, 0)},
        {"action": "B", "timestamp": datetime(2024, 1, 1, 10, 4, 0)},
        {"action": "C", "timestamp": datetime(2024, 1, 1, 10, 5, 0)},
        {"action": "X", "timestamp": datetime(2024, 1, 1, 10, 6, 0)},
    ]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) >= 1
    found = any("Common sequence: A → B → C (occurred 2 times)" in p.description for p in patterns)
    assert found
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_min_length(analyzer):
    """Test _detect_action_sequences returns empty for fewer than 3 activities."""
    activities = [
        {"action": "A", "timestamp": datetime(2024, 1, 1, 10, 0, 0)},
        {"action": "B", "timestamp": datetime(2024, 1, 1, 10, 1, 0)},
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer):
    """Test _detect_regularity identifies highly regular intervals."""
    start = datetime(2024, 1, 1, 12, 0, 0)
    activities = [
        {"action": "evt", "timestamp": start + timedelta(minutes=i)} for i in range(6)
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_insufficient(analyzer):
    """Test _detect_regularity returns empty when there are fewer than 5 timestamps."""
    start = datetime(2024, 1, 1, 12, 0, 0)
    activities = [
        {"action": "evt", "timestamp": start + timedelta(minutes=i)} for i in range(4)
    ]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_get_user_score_with_dates(analyzer):
    """Test get_user_score with valid timestamps and mixed actions."""
    # 10 actions spanning 5 days => days_active = 5, actions_per_day = 2
    # diversity: 4 unique / 10 total = 0.4
    # frequency_score = 0.2, volume_score = 0.1
    # final = (0.4*0.3 + 0.2*0.4 + 0.1*0.3)*100 = 23.0
    start = datetime(2024, 1, 1, 0, 0, 0)
    # Construct activities; first and last timestamps matter for days_active
    activities = [
        {"action": "a", "timestamp": start},
        {"action": "b", "timestamp": start + timedelta(hours=1)},
        {"action": "c", "timestamp": start + timedelta(days=1)},
        {"action": "d", "timestamp": start + timedelta(days=1, hours=1)},
        {"action": "a", "timestamp": start + timedelta(days=2)},
        {"action": "b", "timestamp": start + timedelta(days=2, hours=1)},
        {"action": "c", "timestamp": start + timedelta(days=3)},
        {"action": "d", "timestamp": start + timedelta(days=3, hours=1)},
        {"action": "a", "timestamp": start + timedelta(days=4)},
        {"action": "b", "timestamp": start + timedelta(days=5)},  # last
    ]
    score = analyzer.get_user_score(activities)
    assert score == 23.0


def test_activityanalyzer_get_user_score_no_timestamps(analyzer):
    """Test get_user_score with unparseable timestamps falls back to total_actions."""
    # total=5, frequency_score = 0.5, volume=0.05, diversity=2/5=0.4
    # final = (0.4*0.3 + 0.5*0.4 + 0.05*0.3)*100 = 33.5
    activities = [
        {"action": "a", "timestamp": "bad"},
        {"action": "a", "timestamp": None},
        {"action": "b", "timestamp": "invalid"},
        {"action": "a", "timestamp": object()},
        {"action": "b", "timestamp": 12345},
    ]
    score = analyzer.get_user_score(activities)
    assert score == 33.5


def test_activityanalyzer_detect_anomalies_basic(analyzer):
    """Test detect_anomalies flags unusually long interval for an action."""
    # Use a lower threshold to ensure we detect the anomaly
    analyzer.anomaly_threshold = 1.5
    base = datetime(2024, 1, 1, 12, 0, 0)
    activities = [
        {"action": "click", "timestamp": base + timedelta(seconds=0)},
        {"action": "click", "timestamp": base + timedelta(seconds=60)},
        {"action": "click", "timestamp": base + timedelta(seconds=120)},
        {"action": "click", "timestamp": base + timedelta(seconds=180)},
        {"action": "click", "timestamp": base + timedelta(seconds=2100)},  # large gap
        {"action": "view", "timestamp": base + timedelta(seconds=0)},
        {"action": "view", "timestamp": base + timedelta(seconds=10)},  # less than 3 timestamps -> ignored
    ]
    anomalies = analyzer.detect_anomalies(activities)
    # Should flag the last click timestamp as anomaly
    assert len(anomalies) >= 1
    # Find anomaly for action 'click'
    click_anoms = [a for a in anomalies if a["action"] == "click"]
    assert len(click_anoms) >= 1
    last_ts = (base + timedelta(seconds=2100)).isoformat()
    found = any(a["timestamp"] == last_ts for a in click_anoms)
    assert found
    assert any(a["z_score"] >= 1.5 for a in click_anoms)
    assert all("Unusual interval" in a["reason"] for a in click_anoms)


def test_activityanalyzer_detect_anomalies_small_input(analyzer):
    """Test detect_anomalies returns empty when fewer than 5 activities."""
    base = datetime(2024, 1, 1, 12, 0, 0)
    activities = [
        {"action": "click", "timestamp": base + timedelta(seconds=0)},
        {"action": "click", "timestamp": base + timedelta(seconds=60)},
        {"action": "click", "timestamp": base + timedelta(seconds=120)},
        {"action": "click", "timestamp": base + timedelta(seconds=180)},
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_zero_stddev(analyzer):
    """Test detect_anomalies with identical intervals yields no anomalies due to zero std dev."""
    base = datetime(2024, 1, 1, 12, 0, 0)
    activities = [
        {"action": "click", "timestamp": base + timedelta(seconds=s)}
        for s in [0, 60, 120, 180, 240]
    ]
    # Need at least 5 activities overall; only one action present, intervals identical
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_analyze_patterns_integration_calls_mocks(analyzer):
    """Test analyze_patterns aggregates patterns from internal detectors."""
    acts = [
        {"action": "A", "timestamp": datetime(2024, 1, 1, 12, 0, 0)},
        {"action": "B", "timestamp": datetime(2024, 1, 1, 12, 1, 0)},
        {"action": "C", "timestamp": datetime(2024, 1, 1, 12, 2, 0)},
    ]
    mock_peak = [ActivityPattern("p1", "peak", 0.1)]
    mock_seq = [ActivityPattern("p2", "seq", 0.2)]
    mock_reg = [ActivityPattern("p3", "reg", 0.3)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as m_reg:
        patterns = analyzer.analyze_patterns(acts)
        assert patterns == mock_peak + mock_seq + mock_reg
        m_peak.assert_called_once_with(acts)
        m_seq.assert_called_once_with(acts)
        m_reg.assert_called_once_with(acts)


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for empty input."""
    assert analyzer.analyze_patterns([]) == []