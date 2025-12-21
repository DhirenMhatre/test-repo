import pytest
from unittest.mock import patch

from datetime import datetime, timedelta

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing test timestamps."""
    return datetime(2023, 1, 1, 9, 0, 0)


def make_activity(action, ts):
    return {'action': action, 'timestamp': ts}


def test_activitypattern_to_dict_basic():
    """Test ActivityPattern.to_dict returns expected dictionary."""
    pattern = ActivityPattern('peak_hours', 'High during 09:00', 0.85)
    d = pattern.to_dict()
    assert d == {
        'pattern_type': 'peak_hours',
        'description': 'High during 09:00',
        'confidence': 0.85
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initializes with correct default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for no activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_analyze_patterns_combines_results_and_calls(analyzer):
    """Test analyze_patterns combines results from internal detection methods and calls them."""
    activities = [make_activity('a', datetime(2023, 1, 1, 10, 0, 0))]
    peak_pat = ActivityPattern('peak_hours', 'X', 0.85)
    seq_pat = ActivityPattern('action_sequence', 'Y', 0.75)

    with patch.object(analyzer, '_detect_peak_hours', return_value=[peak_pat]) as mp, \
         patch.object(analyzer, '_detect_action_sequences', return_value=[seq_pat]) as ms, \
         patch.object(analyzer, '_detect_regularity', return_value=[]) as mr:
        patterns = analyzer.analyze_patterns(activities)
        mp.assert_called_once_with(activities)
        ms.assert_called_once_with(activities)
        mr.assert_called_once_with(activities)

    assert patterns == [peak_pat, seq_pat]


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_valid_data(analyzer, base_time):
    """Test get_user_score computes expected score with valid timestamps and actions."""
    # 10 actions across 2 days difference -> actions_per_day = 5
    actions = ['a', 'b', 'a', 'c', 'b', 'a', 'd', 'c', 'a', 'b']
    activities = []
    for i, action in enumerate(actions):
        # distribute timestamps between first and last
        ts = base_time + timedelta(hours=i)
        activities.append(make_activity(action, ts))

    # Ensure last timestamp is exactly 2 days later to set days_active = 2
    activities[0]['timestamp'] = base_time
    activities[-1]['timestamp'] = base_time + timedelta(days=2)

    score = analyzer.get_user_score(activities)
    # diversity_score = 4/10=0.4; frequency_score=5/10=0.5; volume_score=10/100=0.1
    # final = (0.4*0.3 + 0.5*0.4 + 0.1*0.3) * 100 = 35.0
    assert score == 35.0


def test_activityanalyzer_get_user_score_unparseable_timestamps(analyzer):
    """Test get_user_score uses total actions per day fallback when timestamps are unparseable."""
    actions = ['a', 'b', 'a', 'c', 'b', 'a']  # total=6, unique=3
    activities = []
    for action in actions:
        activities.append(make_activity(action, 'not-a-timestamp'))
    score = analyzer.get_user_score(activities)
    # frequency_score = min(6/10, 1) = 0.6
    # diversity_score = 3/6 = 0.5
    # volume_score = 6/100 = 0.06
    # final = (0.5*0.3 + 0.6*0.4 + 0.06*0.3) * 100 = 40.8
    assert score == 40.8


def test_activityanalyzer_detect_anomalies_not_enough_data(analyzer):
    """Test detect_anomalies returns empty list when insufficient activities."""
    activities = [
        make_activity('click', datetime(2023, 1, 1, 0, 0, 0)),
        make_activity('click', datetime(2023, 1, 1, 0, 1, 0)),
        make_activity('click', datetime(2023, 1, 1, 0, 2, 0)),
        make_activity('click', datetime(2023, 1, 1, 0, 3, 0)),
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_with_anomaly(analyzer, base_time):
    """Test detect_anomalies flags unusual interval with z-score above threshold."""
    # Create intervals: 60s, 60s, 600s, 60s for 'click'
    t0 = base_time
    t1 = t0 + timedelta(seconds=60)
    t2 = t1 + timedelta(seconds=60)
    t3 = t2 + timedelta(seconds=600)
    t4 = t3 + timedelta(seconds=60)
    activities = [
        make_activity('click', t0),
        make_activity('click', t1),
        make_activity('click', t2),
        make_activity('click', t3),
        make_activity('click', t4),
        # Add some other action
        make_activity('view', base_time),
    ]
    analyzer.anomaly_threshold = 1.5  # relax for testing
    anomalies = analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)
    assert len(anomalies) >= 1
    # Anomaly should correspond to timestamp at the end of the 600s interval (t3)
    matching = [a for a in anomalies if a.get('action') == 'click' and a.get('timestamp') == t3.isoformat()]
    assert len(matching) == 1
    assert 'Unusual interval' in matching[0].get('reason', '')
    assert matching[0]['z_score'] >= 1.5


def test_activityanalyzer_detect_anomalies_zero_stddev_no_anomalies(analyzer, base_time):
    """Test detect_anomalies returns no anomalies when intervals have zero std deviation."""
    t0 = base_time
    t1 = t0 + timedelta(seconds=60)
    t2 = t1 + timedelta(seconds=60)
    t3 = t2 + timedelta(seconds=60)
    t4 = t3 + timedelta(seconds=60)
    activities = [
        make_activity('ping', t0),
        make_activity('ping', t1),
        make_activity('ping', t2),
        make_activity('ping', t3),
        make_activity('ping', t4),
    ]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_ignores_nonparseable_timestamps(analyzer):
    """Test detect_anomalies handles invalid timestamps gracefully without raising exceptions."""
    activities = [
        make_activity('click', 'bad-ts-1'),
        make_activity('click', 'bad-ts-2'),
        make_activity('click', 'bad-ts-3'),
        make_activity('click', 'bad-ts-4'),
        make_activity('click', 'bad-ts-5'),
    ]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding the threshold."""
    activities = []
    # 09:00 -> 3 events
    for i in range(3):
        activities.append(make_activity('a', base_time.replace(hour=9, minute=i)))
    # 10:00 -> 3 events
    for i in range(3):
        activities.append(make_activity('b', base_time.replace(hour=10, minute=i)))
    # 23:00 -> 4 events
    for i in range(4):
        activities.append(make_activity('c', base_time.replace(hour=23, minute=i)))
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert isinstance(pat, ActivityPattern)
    assert pat.pattern_type == 'peak_hours'
    assert pat.confidence == 0.85
    assert 'High activity during hours: 09:00, 10:00, 23:00' == pat.description


def test_activityanalyzer_detect_peak_hours_below_threshold_returns_empty(analyzer, base_time):
    """Test _detect_peak_hours returns empty when no hour strictly exceeds threshold."""
    activities = []
    # 5 hours with one event each -> each share is exactly 0.2, not strictly greater
    for h in [8, 9, 10, 11, 12]:
        activities.append(make_activity('a', base_time.replace(hour=h)))
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_peak_hours_ignores_invalid_timestamps(analyzer):
    """Test _detect_peak_hours ignores activities with invalid timestamps."""
    activities = [
        make_activity('a', 'not-a-ts'),
        make_activity('b', None),
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_basic(analyzer, base_time):
    """Test _detect_action_sequences identifies frequent 3-action sequences."""
    actions = ['A', 'B', 'C', 'A', 'B', 'C', 'A']
    activities = [make_activity(a, base_time + timedelta(minutes=i)) for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    # Expect at least the 'A → B → C' pattern with count 2
    seq_descriptions = [p.description for p in patterns if p.pattern_type == 'action_sequence']
    assert any('Common sequence: A → B → C (occurred 2 times)' == desc for desc in seq_descriptions)
    # Only sequences with count >= 2 are included; here there should be 2 such sequences (ABC and BCA)
    assert len(patterns) == 2
    for p in patterns:
        assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_insufficient_length(analyzer):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [make_activity('A', datetime(2023, 1, 1, 0, 0, 0)),
                  make_activity('B', datetime(2023, 1, 1, 0, 1, 0))]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity detects highly regular activity pattern."""
    activities = []
    for i in range(6):
        activities.append(make_activity('x', base_time + timedelta(hours=i)))
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == 'regularity'
    assert pat.confidence == 0.9
    assert 'Highly regular activity pattern (CV: 0.00)' == pat.description


def test_activityanalyzer_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty for irregular intervals."""
    activities = [
        make_activity('x', base_time),
        make_activity('x', base_time + timedelta(minutes=5)),
        make_activity('x', base_time + timedelta(minutes=20)),
        make_activity('x', base_time + timedelta(minutes=50)),
        make_activity('x', base_time + timedelta(minutes=53)),
        make_activity('x', base_time + timedelta(minutes=120)),
    ]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_parse_timestamp_datetime_passthrough(analyzer, base_time):
    """Test _parse_timestamp returns the same datetime instance when given a datetime object."""
    result = analyzer._parse_timestamp(base_time)
    assert result is base_time


def test_activityanalyzer_parse_timestamp_valid_iso_with_z(analyzer):
    """Test _parse_timestamp parses ISO string with Z suffix."""
    ts_str = '2023-01-01T12:34:56Z'
    result = analyzer._parse_timestamp(ts_str)
    assert isinstance(result, datetime)
    assert result.isoformat().endswith('+00:00')
    assert result.hour == 12
    assert result.minute == 34
    assert result.second == 56


def test_activityanalyzer_parse_timestamp_invalid_returns_none(analyzer):
    """Test _parse_timestamp returns None for invalid timestamp strings."""
    assert analyzer._parse_timestamp('not-a-date') is None


def test_activityanalyzer_parse_timestamp_fromisoformat_raises_returns_none(analyzer):
    """Test _parse_timestamp handles exceptions from datetime.fromisoformat gracefully."""
    with patch('src.activity_analyzer.datetime.fromisoformat', side_effect=ValueError):
        result = analyzer._parse_timestamp('2023-01-01T00:00:00')
        assert result is None