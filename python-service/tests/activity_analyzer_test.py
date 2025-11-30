import pytest
from unittest.mock import patch, MagicMock

from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base UTC datetime for constructing timestamps"""
    return datetime(2023, 1, 1, 12, 0, 0, tzinfo=timezone.utc)


def iso(dt: datetime) -> str:
    """Helper to convert datetime to isoformat with Z"""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat().replace("+00:00", "Z")


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict output"""
    pat = ActivityPattern(pattern_type="peak_hours", description="High activity 12:00", confidence=0.85)
    assert pat.pattern_type == "peak_hours"
    assert pat.description == "High activity 12:00"
    assert pat.confidence == 0.85
    d = pat.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "High activity 12:00",
        "confidence": 0.85,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default thresholds on initialization"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer, base_time):
    """Test _parse_timestamp handles datetime and ISO strings with Z and offsets"""
    # datetime
    dt = analyzer._parse_timestamp(base_time)
    assert isinstance(dt, datetime)
    assert dt == base_time

    # ISO with Z
    s = iso(base_time)
    dt2 = analyzer._parse_timestamp(s)
    assert isinstance(dt2, datetime)
    assert dt2 == base_time

    # ISO with offset
    s_offset = (base_time.replace(tzinfo=None)).isoformat()  # naive, but allowed
    dt3 = analyzer._parse_timestamp(s_offset)
    # naive datetime without Z still parsed by fromisoformat
    assert isinstance(dt3, datetime)
    # dt3 will be naive; convert both to naive for comparison
    assert dt3.replace(tzinfo=None) == base_time.replace(tzinfo=None)


def test_activityanalyzer_parse_timestamp_invalid(analyzer):
    """Test _parse_timestamp returns None for invalid inputs and handles exceptions"""
    assert analyzer._parse_timestamp("not-a-timestamp") is None
    assert analyzer._parse_timestamp(12345) is None
    # Patch datetime.fromisoformat to raise ValueError to ensure handled gracefully
    with patch("src.activity_analyzer.datetime") as mock_datetime:
        mock_datetime.fromisoformat.side_effect = ValueError("bad format")
        assert analyzer._parse_timestamp("2023-01-01T00:00:00Z") is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold"""
    # 10 activities at hour 15, 2 at hour 9
    acts = []
    for i in range(10):
        acts.append({"action": "a", "timestamp": iso(base_time.replace(hour=15) + timedelta(minutes=i))})
    for i in range(2):
        acts.append({"action": "b", "timestamp": iso(base_time.replace(hour=9) + timedelta(minutes=i))})

    patterns = analyzer._detect_peak_hours(acts)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "15:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when no parsable timestamps"""
    acts = [{"action": "x", "timestamp": "invalid-ts"} for _ in range(5)]
    assert analyzer._detect_peak_hours(acts) == []


def test_activityanalyzer_detect_action_sequences_min_length(analyzer):
    """Test _detect_action_sequences returns empty when activities fewer than 3"""
    acts = [{"action": "A", "timestamp": "2023-01-01T00:00:00Z"}]
    assert analyzer._detect_action_sequences(acts) == []


def test_activityanalyzer_detect_action_sequences_common(analyzer, base_time):
    """Test _detect_action_sequences finds repeated sequences"""
    # Sequence: A B C A B C A -> ABC occurs twice, BCA occurs twice
    actions = ["A", "B", "C", "A", "B", "C", "A"]
    acts = [
        {"action": a, "timestamp": iso(base_time + timedelta(minutes=i))}
        for i, a in enumerate(actions)
    ]
    patterns = analyzer._detect_action_sequences(acts)
    # Expect two patterns for ABC and BCA
    types = [p.pattern_type for p in patterns]
    assert all(t == "action_sequence" for t in types)
    descs = [p.description for p in patterns]
    assert any("A → B → C" in d and "occurred 2 times" in d for d in descs)
    assert any("B → C → A" in d and "occurred 2 times" in d for d in descs)
    assert all(p.confidence == 0.75 for p in patterns)


def test_activityanalyzer_detect_regularity_regular(analyzer, base_time):
    """Test _detect_regularity identifies highly regular intervals"""
    acts = []
    for i in range(6):
        acts.append({"action": "ping", "timestamp": iso(base_time + timedelta(seconds=60 * i))})
    patterns = analyzer._detect_regularity(acts)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_insufficient(analyzer, base_time):
    """Test _detect_regularity returns empty for insufficient valid timestamps"""
    acts = [{"action": "x", "timestamp": "bad-ts"} for _ in range(10)]
    assert analyzer._detect_regularity(acts) == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities"""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_basic_calculation(analyzer, base_time):
    """Test get_user_score computes expected score with known inputs"""
    # 10 actions within same day: diversity 5/10=0.5, frequency=1.0, volume=0.1 -> score 58.0
    acts = []
    actions = ["A", "B", "C", "D", "E"] * 2
    for i, a in enumerate(actions):
        acts.append({"action": a, "timestamp": iso(base_time + timedelta(minutes=i))})
    score = analyzer.get_user_score(acts)
    assert score == 58.0


def test_activityanalyzer_get_user_score_unparsable_timestamps(analyzer):
    """Test get_user_score falls back to actions_per_day=total when timestamps cannot be parsed"""
    # total_actions=4, diversity=2/4=0.5, frequency=min(4/10,1)=0.4, volume=0.04 -> score 0.3*0.5 + 0.4*0.4 + 0.3*0.04 = 0.15 + 0.16 + 0.012 = 0.322 -> 32.2
    acts = [
        {"action": "A", "timestamp": "bad"},
        {"action": "B", "timestamp": None},
        {"action": "A", "timestamp": 123},
        {"action": "B", "timestamp": object()},
    ]
    score = analyzer.get_user_score(acts)
    assert score == 32.2


def test_activityanalyzer_detect_anomalies_insufficient(analyzer, base_time):
    """Test detect_anomalies returns empty when fewer than 5 activities overall"""
    acts = []
    for i in range(4):
        acts.append({"action": "login", "timestamp": iso(base_time + timedelta(minutes=i))})
    assert analyzer.detect_anomalies(acts) == []


def test_activityanalyzer_detect_anomalies_outlier_interval(analyzer, base_time):
    """Test detect_anomalies flags an interval anomaly when threshold is lowered slightly below 3.0"""
    # 11 login events: 5 every 60s, one long gap, then 5 every 60s
    acts = []
    # First 6 entries: 5 intervals of 60s
    for i in range(6):
        acts.append({"action": "login", "timestamp": iso(base_time + timedelta(seconds=60 * i))})
    # Large gap: 15 minutes
    acts.append({"action": "login", "timestamp": iso(base_time + timedelta(minutes=20))})
    # remainder evenly spaced after gap
    for i in range(1, 5):
        acts.append({"action": "login", "timestamp": iso(base_time + timedelta(minutes=20, seconds=60 * i))})
    # Add some other actions to ensure multiple actions don't interfere
    acts.append({"action": "view", "timestamp": iso(base_time + timedelta(minutes=25))})
    acts.append({"action": "view", "timestamp": iso(base_time + timedelta(minutes=26))})

    # Lower threshold slightly so that single-outlier z=3.0 registers
    analyzer.anomaly_threshold = 2.99
    anomalies = analyzer.detect_anomalies(acts)

    # We expect at least one anomaly for 'login'
    assert any(a["action"] == "login" for a in anomalies)
    # Find the anomaly associated with the large gap: it should be the timestamp immediately after the gap
    expected_anom_ts = iso(base_time + timedelta(minutes=20))
    assert any(a["timestamp"] == expected_anom_ts for a in anomalies)
    # z_score rounded to at least 3.0
    assert any(a["z_score"] >= 3.0 for a in anomalies if a["action"] == "login")
    # reason should mention Unusual interval
    assert any("Unusual interval" in a["reason"] for a in anomalies)


def test_activityanalyzer_analyze_patterns_calls_components(analyzer):
    """Test analyze_patterns aggregates results from internal detectors"""
    acts = [{"action": "x", "timestamp": "2023-01-01T00:00:00Z"}]

    peak = [ActivityPattern("peak_hours", "hours: 12:00", 0.85)]
    seqs = [ActivityPattern("action_sequence", "A → B → C (occurred 2 times)", 0.75)]
    reg = [ActivityPattern("regularity", "Highly regular", 0.9)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=seqs) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=reg) as m_reg:
        patterns = analyzer.analyze_patterns(acts)
        m_peak.assert_called_once_with(acts)
        m_seq.assert_called_once_with(acts)
        m_reg.assert_called_once_with(acts)

    assert patterns == peak + seqs + reg


def test_activityanalyzer_analyze_patterns_empty_and_none(analyzer):
    """Test analyze_patterns returns empty list for empty or None inputs"""
    assert analyzer.analyze_patterns([]) == []
    assert analyzer.analyze_patterns(None) == []  # type: ignore[arg-type]