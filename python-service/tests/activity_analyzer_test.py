import pytest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def test_ActivityPattern_initialization_and_to_dict():
    """Test ActivityPattern initialization and to_dict output."""
    pattern = ActivityPattern('peak_hours', 'High activity during specific hours', 0.85)
    assert pattern.pattern_type == 'peak_hours'
    assert pattern.description == 'High activity during specific hours'
    assert pattern.confidence == 0.85

    d = pattern.to_dict()
    assert d['pattern_type'] == 'peak_hours'
    assert d['description'] == 'High activity during specific hours'
    assert d['confidence'] == 0.85


def test_ActivityAnalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initializes with expected default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_ActivityAnalyzer_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp handles datetime, ISO strings, and invalid inputs."""
    dt = datetime(2021, 1, 1, 12, 30, 45)
    assert analyzer._parse_timestamp(dt) == dt

    iso_z = "2021-01-01T12:30:45Z"
    parsed_z = analyzer._parse_timestamp(iso_z)
    assert isinstance(parsed_z, datetime)
    assert parsed_z.tzinfo is not None
    assert parsed_z.utcoffset() == timedelta(0)

    iso = "2021-01-01T12:30:45"
    parsed_iso = analyzer._parse_timestamp(iso)
    assert isinstance(parsed_iso, datetime)
    assert parsed_iso.tzinfo is None

    iso_offset = "2021-01-01T12:30:45+02:00"
    parsed_offset = analyzer._parse_timestamp(iso_offset)
    assert isinstance(parsed_offset, datetime)
    assert parsed_offset.tzinfo is not None
    assert parsed_offset.utcoffset() == timedelta(hours=2)

    assert analyzer._parse_timestamp("invalid") is None
    assert analyzer._parse_timestamp(None) is None
    assert analyzer._parse_timestamp(12345) is None


def test_ActivityAnalyzer_detect_peak_hours_basic(analyzer):
    """Test peak hour detection with hours exceeding threshold."""
    base = datetime(2021, 1, 1, 10, 0, 0)
    activities = []
    # 3 at 10:00
    activities += [{'action': 'click', 'timestamp': base + timedelta(minutes=5*i)} for i in range(3)]
    # 3 at 14:00
    activities += [{'action': 'click', 'timestamp': datetime(2021, 1, 1, 14, 0, 0) + timedelta(minutes=5*i)} for i in range(3)]
    # 4 at other hours
    activities += [
        {'action': 'click', 'timestamp': datetime(2021, 1, 1, 9, 10, 0)},
        {'action': 'click', 'timestamp': datetime(2021, 1, 1, 11, 20, 0)},
        {'action': 'click', 'timestamp': datetime(2021, 1, 1, 15, 30, 0)},
        {'action': 'click', 'timestamp': datetime(2021, 1, 1, 18, 40, 0)},
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == 'peak_hours'
    assert p.confidence == 0.85
    assert '10:00' in p.description
    assert '14:00' in p.description


def test_ActivityAnalyzer_detect_peak_hours_no_peaks(analyzer):
    """Test peak hour detection returns empty when no hour exceeds threshold (> 0.2)."""
    # 10 activities evenly distributed across 5 hours => each hour is exactly 0.2, not strictly greater
    activities = []
    hours = [8, 9, 10, 11, 12]
    for h in hours:
        activities.append({'action': 'click', 'timestamp': datetime(2021, 1, 1, h, 0, 0)})
        activities.append({'action': 'click', 'timestamp': datetime(2021, 1, 1, h, 30, 0)})

    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_ActivityAnalyzer_detect_peak_hours_ignores_invalid_timestamps(analyzer):
    """Test peak hour detection returns empty when timestamps are invalid."""
    activities = [
        {'action': 'click', 'timestamp': 'not-a-date'},
        {'action': 'click', 'timestamp': None},
        {'action': 'click'}  # missing timestamp
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_ActivityAnalyzer_detect_action_sequences_basic(analyzer):
    """Test detection of common action sequences of length 3."""
    activities = [
        {'action': 'A', 'timestamp': datetime(2021, 1, 1, 10, 0)},
        {'action': 'B', 'timestamp': datetime(2021, 1, 1, 10, 1)},
        {'action': 'C', 'timestamp': datetime(2021, 1, 1, 10, 2)},
        {'action': 'A', 'timestamp': datetime(2021, 1, 1, 10, 3)},
        {'action': 'B', 'timestamp': datetime(2021, 1, 1, 10, 4)},
        {'action': 'C', 'timestamp': datetime(2021, 1, 1, 10, 5)},
        {'action': 'D', 'timestamp': datetime(2021, 1, 1, 10, 6)},
    ]
    patterns = analyzer._detect_action_sequences(activities)
    assert any(p.pattern_type == 'action_sequence' for p in patterns)
    # There should be at most 3 patterns
    assert len(patterns) <= 3
    # ABC should be detected with count 2
    text = 'Common sequence: A → B → C (occurred 2 times)'
    assert any(p.description == text and p.confidence == 0.75 for p in patterns)


def test_ActivityAnalyzer_detect_action_sequences_less_than_three_returns_empty(analyzer):
    """Test action sequence detection returns empty when fewer than 3 activities."""
    activities = [
        {'action': 'A', 'timestamp': datetime(2021, 1, 1, 10, 0)},
        {'action': 'B', 'timestamp': datetime(2021, 1, 1, 10, 1)},
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_ActivityAnalyzer_detect_regularity_regular_and_irregular(analyzer):
    """Test regularity detection for highly regular and irregular intervals."""
    # Regular: 6 activities exactly 10 minutes apart
    start = datetime(2021, 1, 1, 9, 0)
    regular = [{'action': 'A', 'timestamp': start + timedelta(minutes=10*i)} for i in range(6)]
    patterns_regular = analyzer._detect_regularity(regular)
    assert len(patterns_regular) == 1
    assert patterns_regular[0].pattern_type == 'regularity'
    assert 'Highly regular activity pattern' in patterns_regular[0].description
    assert '(CV: 0.00)' in patterns_regular[0].description
    assert patterns_regular[0].confidence == 0.9

    # Irregular: 5 activities with varying intervals
    times = [
        datetime(2021, 1, 1, 9, 0),
        datetime(2021, 1, 1, 9, 0, 1),
        datetime(2021, 1, 1, 9, 2),
        datetime(2021, 1, 1, 9, 2, 5),
        datetime(2021, 1, 1, 9, 12),
    ]
    irregular = [{'action': 'A', 'timestamp': t} for t in times]
    patterns_irregular = analyzer._detect_regularity(irregular)
    assert patterns_irregular == []


def test_ActivityAnalyzer_detect_regularity_ignores_invalid_timestamps(analyzer):
    """Test regularity detection returns empty when not enough valid timestamps."""
    activities = [
        {'action': 'A', 'timestamp': 'bad'},
        {'action': 'A', 'timestamp': None},
        {'action': 'A'},
        {'action': 'A', 'timestamp': '2021-01-01T00:00:00Z'},
        {'action': 'A', 'timestamp': '2021-01-01T00:10:00Z'},
    ]
    # Only 2 valid timestamps => should return []
    assert analyzer._detect_regularity(activities) == []


def test_ActivityAnalyzer_analyze_patterns_aggregates_results_with_mocks(analyzer):
    """Test analyze_patterns combines results from sub-detectors."""
    activities = [{'action': 'A', 'timestamp': datetime(2021, 1, 1, 10, 0)}]

    mock_peak = [ActivityPattern('peak_hours', 'peak', 0.1)]
    mock_seq = [ActivityPattern('action_sequence', 'seq', 0.2)]
    mock_reg = []

    with patch.object(ActivityAnalyzer, '_detect_peak_hours', return_value=mock_peak) as m_peak, \
         patch.object(ActivityAnalyzer, '_detect_action_sequences', return_value=mock_seq) as m_seq, \
         patch.object(ActivityAnalyzer, '_detect_regularity', return_value=mock_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)

        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)

        assert patterns == mock_peak + mock_seq + mock_reg


def test_ActivityAnalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for no activities."""
    assert analyzer.analyze_patterns([]) == []


def test_ActivityAnalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty input."""
    assert analyzer.get_user_score([]) == 0.0


def test_ActivityAnalyzer_get_user_score_no_timestamps_with_duplicates(analyzer):
    """Test get_user_score calculation without timestamps and with duplicate actions (diversity bug)."""
    activities = [
        {'action': 'a'},  # no timestamp
        {'action': 'b'},
        {'action': 'a'},
    ]
    # Expected:
    # total_actions = 3
    # unique_actions computed by buggy algorithm => 3
    # diversity_score = 1.0
    # actions_per_day = 3 (since no timestamps) => frequency_score = 0.3
    # volume_score = 0.03
    # final = (0.3*0.3 + 0.3*0.4 + 0.03*0.3) * 100 = 42.9
    assert analyzer.get_user_score(activities) == 42.9


def test_ActivityAnalyzer_get_user_score_with_timestamps_spanning_days(analyzer):
    """Test get_user_score uses days_active based on the difference between first and last timestamps."""
    activities = [
        {'action': 'a', 'timestamp': datetime(2021, 1, 1, 0, 0, 0)},
        {'action': 'b', 'timestamp': datetime(2021, 1, 1, 12, 0, 0)},
        {'action': 'c', 'timestamp': datetime(2021, 1, 2, 12, 0, 0)},
        {'action': 'd', 'timestamp': datetime(2021, 1, 3, 0, 0, 0)},
    ]
    # days_active = 2 (Jan 1 -> Jan 3)
    # total_actions = 4 => actions_per_day = 2 => frequency_score = 0.2
    # diversity_score = 1.0 (all distinct)
    # volume_score = 0.04
    # final = (0.3 + 0.08 + 0.012) * 100 = 39.2
    assert analyzer.get_user_score(activities) == 39.2


def test_ActivityAnalyzer_detect_anomalies_threshold_and_formatting(analyzer):
    """Test detect_anomalies identifies outliers and formats anomaly details."""
    base = datetime(2021, 1, 1, 0, 0, 0)
    # Action A with intervals: 60, 60, 60, 60, 300 seconds
    a_times = [
        base,
        base + timedelta(seconds=60),
        base + timedelta(seconds=120),
        base + timedelta(seconds=180),
        base + timedelta(seconds=240),
        base + timedelta(seconds=540),
    ]
    activities = [{'action': 'A', 'timestamp': t} for t in a_times]
    # Unrelated action with insufficient timestamps
    activities += [
        {'action': 'B', 'timestamp': base + timedelta(seconds=5)},
        {'action': 'B', 'timestamp': base + timedelta(seconds=10)},
    ]

    analyzer.anomaly_threshold = 1.5
    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly['action'] == 'A'
    assert anomaly['timestamp'] == a_times[-1].isoformat()
    assert anomaly['z_score'] == 2.0
    assert 'Unusual interval: 300.0s' in anomaly['reason']
    assert 'avg 108.0s' in anomaly['reason']


def test_ActivityAnalyzer_detect_anomalies_insufficient_data(analyzer):
    """Test detect_anomalies returns empty when there are fewer than 5 activities total."""
    activities = [
        {'action': 'A', 'timestamp': datetime(2021, 1, 1, 0, 0, 0)},
        {'action': 'A', 'timestamp': datetime(2021, 1, 1, 0, 1, 0)},
        {'action': 'A', 'timestamp': datetime(2021, 1, 1, 0, 2, 0)},
        {'action': 'A', 'timestamp': datetime(2021, 1, 1, 0, 3, 0)},
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_ActivityAnalyzer_detect_anomalies_exception_propagation(analyzer):
    """Test detect_anomalies propagates exceptions from _parse_timestamp."""
    activities = [
        {'action': 'A', 'timestamp': '2021-01-01T00:00:00Z'},
        {'action': 'A', 'timestamp': '2021-01-01T00:01:00Z'},
        {'action': 'A', 'timestamp': '2021-01-01T00:02:00Z'},
        {'action': 'A', 'timestamp': '2021-01-01T00:03:00Z'},
        {'action': 'A', 'timestamp': '2021-01-01T00:04:00Z'},
    ]
    with patch.object(ActivityAnalyzer, '_parse_timestamp', side_effect=ValueError("boom")):
        with pytest.raises(ValueError):
            analyzer.detect_anomalies(activities)