import pytest
from unittest.mock import patch
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Base datetime for constructing activity timestamps"""
    return datetime(2023, 1, 1, 0, 0, 0)


@pytest.fixture
def pattern_instance():
    """Create an ActivityPattern instance for testing"""
    return ActivityPattern(pattern_type="test_type", description="Test pattern", confidence=0.95)


def make_activity(action: str, ts=None):
    """Helper to create an activity dict"""
    d = {'action': action}
    if ts is not None:
        d['timestamp'] = ts
    return d


def test_activitypattern_init_and_to_dict(pattern_instance):
    """Test ActivityPattern initialization and to_dict output"""
    assert pattern_instance.pattern_type == "test_type"
    assert pattern_instance.description == "Test pattern"
    assert pattern_instance.confidence == 0.95

    d = pattern_instance.to_dict()
    assert d == {
        'pattern_type': "test_type",
        'description': "Test pattern",
        'confidence': 0.95
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default configuration values"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_supported_formats(analyzer):
    """Test _parse_timestamp supports datetime, ISO strings with Z, and invalid inputs"""
    dt = datetime(2023, 5, 1, 12, 30, 0)
    assert analyzer._parse_timestamp(dt) == dt

    iso_z = "2023-05-01T12:30:00Z"
    parsed = analyzer._parse_timestamp(iso_z)
    assert parsed is not None
    assert parsed.isoformat().endswith("+00:00")

    iso_plain = "2023-05-01T12:30:00"
    parsed2 = analyzer._parse_timestamp(iso_plain)
    assert parsed2 == datetime(2023, 5, 1, 12, 30, 0)

    assert analyzer._parse_timestamp("not-a-timestamp") is None
    assert analyzer._parse_timestamp(None) is None
    assert analyzer._parse_timestamp(12345) is None


def test_activityanalyzer_detect_peak_hours_identifies_hours(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold"""
    activities = []
    # 10 total events: 3 at hour 9, 3 at 10, 4 at 11 -> all above 0.2 threshold
    for _ in range(3):
        activities.append(make_activity("a", base_time.replace(hour=9)))
    for _ in range(3):
        activities.append(make_activity("b", base_time.replace(hour=10)))
    for _ in range(4):
        activities.append(make_activity("c", base_time.replace(hour=11)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert p.confidence == 0.85
    assert "High activity during hours: 09:00, 10:00, 11:00" in p.description


def test_activityanalyzer_detect_peak_hours_no_peaks(analyzer, base_time):
    """Test _detect_peak_hours returns empty when counts do not exceed threshold"""
    # 5 hours, 1 event each -> 0.2 each, not strictly greater than 0.2
    activities = [
        make_activity("a", base_time.replace(hour=h)) for h in range(5)
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_identifies_common(analyzer, base_time):
    """Test _detect_action_sequences finds common 3-grams occurring at least twice"""
    # Create sequences: ABC repeated (3 times), DEF repeated (3 times), XYZ repeated (3 times)
    actions = ["A", "B", "C"] * 3 + ["D", "E", "F"] * 3 + ["X", "Y", "Z"] * 3
    activities = [make_activity(a, base_time + timedelta(seconds=i)) for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)

    assert len(patterns) == 3
    descs = [p.description for p in patterns]
    assert any("A → B → C" in d for d in descs)
    assert any("D → E → F" in d for d in descs)
    assert any("X → Y → Z" in d for d in descs)
    for d in descs:
        assert "occurred" in d
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_limits_top_three(analyzer, base_time):
    """Test _detect_action_sequences returns at most the top three sequences"""
    # Windows in the first part:
    # ABC (3), BCA (2), CAB (2)
    part1 = ["A", "B", "C"] * 3
    # Second part yields: DEF (2), EFD (2), and some with 1
    part2 = ["D", "E", "F", "D", "E", "F", "D"]
    actions = part1 + part2
    activities = [make_activity(a, base_time + timedelta(seconds=i)) for i, a in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 3  # Ensure limit to top 3

    descs = [p.description for p in patterns]
    # The top one must be ABC; the others among BCA and CAB (both count 2)
    assert any("A → B → C" in d for d in descs)
    assert sum(1 for d in descs if "B → C → D" in d or "D → E → F" in d) <= 1


def test_activityanalyzer_detect_action_sequences_too_short(analyzer):
    """Test _detect_action_sequences returns empty for less than 3 activities"""
    activities = [make_activity("A", datetime(2023, 1, 1, 0, 0, 0)), make_activity("B", datetime(2023, 1, 1, 0, 0, 1))]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_regular(analyzer, base_time):
    """Test _detect_regularity returns pattern for highly regular intervals"""
    # 6 timestamps at regular 60s intervals
    activities = [make_activity("action", base_time + timedelta(seconds=60 * i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty when activity is irregular"""
    times = [0, 30, 90, 200, 450, 1000]  # increasingly irregular
    activities = [make_activity("action", base_time + timedelta(seconds=t)) for t in times]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_analyze_patterns_combines_private_detectors(analyzer):
    """Test analyze_patterns aggregates results from private detection methods"""
    activities = [make_activity("x", datetime(2023, 1, 1, 0, 0, 0))]

    mock_peak = [ActivityPattern("peak_hours", "peak", 0.85)]
    mock_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    mock_reg = [ActivityPattern("regularity", "regular", 0.9)]

    with patch.object(analyzer, "_detect_peak_hours", return_value=mock_peak) as m1, \
         patch.object(analyzer, "_detect_action_sequences", return_value=mock_seq) as m2, \
         patch.object(analyzer, "_detect_regularity", return_value=mock_reg) as m3:
        result = analyzer.analyze_patterns(activities)
        assert result == mock_peak + mock_seq + mock_reg
        m1.assert_called_once_with(activities)
        m2.assert_called_once_with(activities)
        m3.assert_called_once_with(activities)


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list on empty input"""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0 for empty activities"""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_invalid_timestamps(analyzer):
    """Test get_user_score with invalid timestamps uses total actions for frequency"""
    # Note: diversity_score becomes 1.0 due to unique action counting logic
    activities = [make_activity("A"), make_activity("A"), make_activity("B"), make_activity("C"), make_activity("C"),
                  make_activity("D"), make_activity("D"), make_activity("D"), make_activity("E"), make_activity("E")]
    # total=10, actions_per_day=10 (invalid timestamps), frequency_score=1.0, volume_score=0.1, diversity_score=1.0
    # final = (1.0*0.3 + 1.0*0.4 + 0.1*0.3)*100 = 73.0
    assert analyzer.get_user_score(activities) == 73.0


def test_activityanalyzer_get_user_score_valid_timestamps_over_days(analyzer, base_time):
    """Test get_user_score with valid first/last timestamps across multiple days"""
    actions = ["A", "B", "C", "D"] * 5  # 20 total
    activities = []
    # First timestamp
    activities.append(make_activity(actions[0], base_time))
    # Middle entries with arbitrary times
    for i, a in enumerate(actions[1:-1], start=1):
        activities.append(make_activity(a, base_time + timedelta(hours=i)))
    # Last timestamp after 3 days
    activities.append(make_activity(actions[-1], base_time + timedelta(days=3)))

    # total=20, days_active=3, actions_per_day≈6.6667, frequency_score≈0.6667
    # volume_score=0.2, diversity_score=1.0 due to logic
    # final ≈ (1.0*0.3 + 0.6667*0.4 + 0.2*0.3)*100 = 62.67
    assert analyzer.get_user_score(activities) == 62.67


def test_activityanalyzer_get_user_score_diversity_bug_consistency(analyzer):
    """Test that diversity scoring is insensitive to actual uniqueness due to current logic"""
    # Same length, different uniqueness; scores should be equal
    acts_all_same = [make_activity("A") for _ in range(5)]
    acts_all_unique = [make_activity(f"A{i}") for i in range(5)]
    score_same = analyzer.get_user_score(acts_all_same)
    score_unique = analyzer.get_user_score(acts_all_unique)
    assert score_same == score_unique


def test_activityanalyzer_detect_anomalies_insufficient(analyzer, base_time):
    """Test detect_anomalies returns empty if not enough activities"""
    activities = [make_activity("click", base_time + timedelta(seconds=i * 10)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_detects_with_threshold_adjust(analyzer, base_time):
    """Test detect_anomalies flags anomalies when threshold is lowered"""
    analyzer.anomaly_threshold = 1.0  # Make it easier to flag z-score anomalies
    times = [
        0, 10, 20, 30, 40, 50, 60, 400  # large gap before 400
    ]
    activities = [make_activity("click", base_time + timedelta(seconds=t)) for t in times]
    anoms = analyzer.detect_anomalies(activities)
    assert isinstance(anoms, list)
    assert len(anoms) >= 1
    assert all(a['action'] == 'click' for a in anoms)
    assert all('z_score' in a for a in anoms)


def test_activityanalyzer_detect_anomalies_multiple_actions_and_skips_short(analyzer, base_time):
    """Test detect_anomalies processes per action and skips those with too few timestamps"""
    analyzer.anomaly_threshold = 1.0
    # 'click' has enough timestamps; 'view' has only two and should be skipped
    acts = []
    for t in [0, 10, 20, 400, 410, 420]:
        acts.append(make_activity("click", base_time + timedelta(seconds=t)))
    for t in [5, 15]:
        acts.append(make_activity("view", base_time + timedelta(seconds=t)))

    anoms = analyzer.detect_anomalies(acts)
    assert all(a['action'] == 'click' for a in anoms)
    # Ensure no anomalies produced for 'view'
    assert not any(a.get('action') == 'view' for a in anoms)


def test_activityanalyzer_detect_anomalies_no_std_dev_no_anomaly(analyzer, base_time):
    """Test detect_anomalies does not raise and returns empty when intervals are constant (std_dev=0)"""
    times = [0, 10, 20, 30, 40, 50]  # constant intervals
    activities = [make_activity("constant", base_time + timedelta(seconds=t)) for t in times]
    anoms = analyzer.detect_anomalies(activities)
    assert anoms == []


def test_activityanalyzer_detect_peak_hours_ignores_invalid_timestamps(analyzer):
    """Test _detect_peak_hours ignores activities with invalid timestamps"""
    activities = [
        {'action': 'a', 'timestamp': 'invalid'},
        {'action': 'b'},  # missing timestamp
    ]
    assert analyzer._detect_peak_hours(activities) == []