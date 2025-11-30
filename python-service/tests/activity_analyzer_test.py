import pytest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide an ActivityAnalyzer instance."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for tests."""
    return datetime(2023, 1, 1, 10, 0, 0)


def make_activity(action: str, ts: datetime):
    """Helper to create an activity dict."""
    return {"action": action, "timestamp": ts.isoformat()}


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict output."""
    pattern = ActivityPattern("peak_hours", "High activity", 0.85)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "High activity"
    assert pattern.confidence == 0.85

    d = pattern.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "High activity",
        "confidence": 0.85,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initializes with correct default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_datetime(analyzer, base_time):
    """Test _parse_timestamp returns datetime unchanged when given a datetime."""
    parsed = analyzer._parse_timestamp(base_time)
    assert isinstance(parsed, datetime)
    assert parsed == base_time


def test_activityanalyzer_parse_timestamp_iso_z(analyzer):
    """Test _parse_timestamp handles ISO 8601 strings with Z suffix."""
    ts_str = "2023-01-01T10:00:00Z"
    parsed = analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    # Should be timezone-aware UTC
    assert parsed.tzinfo is not None
    assert parsed.utcoffset() == timedelta(0)


def test_activityanalyzer_parse_timestamp_iso_offset(analyzer):
    """Test _parse_timestamp handles ISO 8601 strings with timezone offset."""
    ts_str = "2023-01-01T10:00:00+05:00"
    parsed = analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is not None
    assert parsed.utcoffset() == timedelta(hours=5)


def test_activityanalyzer_parse_timestamp_invalid(analyzer):
    """Test _parse_timestamp returns None for invalid inputs."""
    assert analyzer._parse_timestamp("not-a-timestamp") is None
    assert analyzer._parse_timestamp(12345) is None
    assert analyzer._parse_timestamp(None) is None


def test_activityanalyzer_parse_timestamp_fromisoformat_exception_handled(analyzer):
    """Test _parse_timestamp handles exceptions from datetime.fromisoformat gracefully."""
    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=ValueError):
        assert analyzer._parse_timestamp("2023-01-01T00:00:00") is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    activities = []
    # 10:00 - 3
    for i in range(3):
        activities.append(make_activity("a", base_time + timedelta(minutes=i)))
    # 11:00 - 3
    for i in range(3):
        activities.append(make_activity("b", base_time.replace(hour=11) + timedelta(minutes=i)))
    # 12:00 - 2
    for i in range(2):
        activities.append(make_activity("c", base_time.replace(hour=12) + timedelta(minutes=i)))
    # 13:00 - 2
    for i in range(2):
        activities.append(make_activity("d", base_time.replace(hour=13) + timedelta(minutes=i)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert isinstance(p, ActivityPattern)
    assert p.pattern_type == "peak_hours"
    assert p.confidence == 0.85
    assert "High activity during hours: 10:00, 11:00" == p.description


def test_activityanalyzer_detect_peak_hours_no_peak(analyzer, base_time):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    activities = []
    # 10 events across 5 hours: each hour has 2 events => ratio 0.2 (not strictly greater)
    for h in range(5):
        for i in range(2):
            activities.append(make_activity("x", base_time.replace(hour=8 + h) + timedelta(minutes=i)))
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_basic(analyzer, base_time):
    """Test _detect_action_sequences identifies a common sequence occurring at least twice."""
    # Actions: A,B,C,X,A,B,C => sequence ABC occurs twice, others once
    actions = ["A", "B", "C", "X", "A", "B", "C"]
    activities = [make_activity(a, base_time + timedelta(seconds=i)) for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "Common sequence: A → B → C (occurred 2 times)" == p.description
    assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_top3(analyzer, base_time):
    """Test _detect_action_sequences returns at most top 3 sequences by frequency."""
    # Build three distinct sequences each occurring twice, separated by unique separators.
    actions = [
        "A", "B", "C", "X", "A", "B", "C",
        "D", "E", "F", "Y", "D", "E", "F",
        "G", "H", "I", "Z", "G", "H", "I",
    ]
    activities = [make_activity(a, base_time + timedelta(seconds=i)) for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert 1 <= len(patterns) <= 3  # should be up to 3
    # All patterns should describe "occurred 2 times"
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert "(occurred 2 times)" in p.description
        assert p.confidence == 0.75


def test_activityanalyzer_detect_regularity_regular(analyzer, base_time):
    """Test _detect_regularity finds highly regular activity with low CV."""
    # 6 timestamps exactly 60s apart
    activities = [make_activity("tick", base_time + timedelta(seconds=60 * i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern (CV: 0.00)" == p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty when activity is not regular."""
    # Irregular intervals
    offsets = [0, 10, 55, 200, 260, 500]
    activities = [make_activity("tick", base_time + timedelta(seconds=o)) for o in offsets]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_analyze_patterns_delegates_and_combines_with_mocks(analyzer):
    """Test analyze_patterns combines results from internal detectors using mocks."""
    activities = [{"action": "A", "timestamp": "2023-01-01T00:00:00"}]

    peak_mock = [ActivityPattern("peak_hours", "mock peaks", 0.85)]
    seq_mock = [ActivityPattern("action_sequence", "mock seq", 0.75)]
    reg_mock = [ActivityPattern("regularity", "mock reg", 0.9)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=peak_mock) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=seq_mock) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=reg_mock) as m_reg:
        result = analyzer.analyze_patterns(activities)
        assert result == peak_mock + seq_mock + reg_mock
        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list when given no activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_same_day(analyzer, base_time):
    """Test get_user_score when all activities occur within the same day."""
    # 10 actions within same day -> actions_per_day == total_actions
    actions = ["A", "B", "C", "A", "B", "C", "X", "Y", "Z", "A"]
    activities = [make_activity(a, base_time + timedelta(minutes=i)) for i, a in enumerate(actions)]
    score = analyzer.get_user_score(activities)
    # diversity: unique_actions=7, total=10 => 0.7
    # frequency: actions_per_day=10 => 1.0
    # volume: min(10/100,1) = 0.1
    # final = (0.7*0.3 + 1.0*0.4 + 0.1*0.3)*100 = (0.21 + 0.4 + 0.03)*100 = 64.0
    assert score == 64.0


def test_activityanalyzer_get_user_score_multi_day(analyzer, base_time):
    """Test get_user_score when activities span multiple days."""
    # 10 actions over 5 days
    activities = [make_activity("A" if i % 2 == 0 else "B", base_time + timedelta(days=i)) for i in range(10)]
    score = analyzer.get_user_score(activities)
    # total=10, unique=2 -> diversity=0.2
    # days_active = (last-first).days = 9 -> actions_per_day ~ 10/9
    # frequency = min((10/9)/10, 1) = ~0.111...
    # volume = 0.1
    expected = (0.2 * 0.3 + (10/9)/10 * 0.4 + 0.1 * 0.3) * 100
    assert score == round(expected, 2)


def test_activityanalyzer_get_user_score_missing_timestamps(analyzer):
    """Test get_user_score when timestamps are missing or invalid."""
    activities = [
        {"action": "A", "timestamp": "invalid"},
        {"action": "B", "timestamp": None},
        {"action": "A", "timestamp": 123},
        {"action": "C"},  # missing timestamp key
    ]
    # total=4, unique=3 -> diversity=0.75
    # no valid timestamps => actions_per_day = total = 4 => frequency = 0.4
    # volume = 0.04
    expected = (0.75 * 0.3 + 0.4 * 0.4 + 0.04 * 0.3) * 100
    assert analyzer.get_user_score(activities) == round(expected, 2)


def test_activityanalyzer_detect_anomalies_thresholded(analyzer, base_time):
    """Test detect_anomalies identifies intervals with z-score above threshold."""
    # Create intervals predominantly 60s, with one large interval to be anomalous.
    times = [
        base_time,
        base_time + timedelta(seconds=60),
        base_time + timedelta(seconds=120),
        base_time + timedelta(seconds=180),
        base_time + timedelta(seconds=900),  # large gap after previous (720s interval)
        base_time + timedelta(seconds=960),
    ]
    activities = [make_activity("click", t) for t in times]
    # Lower threshold to ensure detection
    analyzer.anomaly_threshold = 1.5
    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "click"
    # The anomaly corresponds to the big interval ending at times[4]
    assert anomaly["timestamp"] == times[4].isoformat()
    assert anomaly["z_score"] >= 1.5
    assert "Unusual interval" in anomaly["reason"]


def test_activityanalyzer_detect_anomalies_insufficient_data(analyzer, base_time):
    """Test detect_anomalies returns empty list when there are fewer than 5 activities."""
    activities = [make_activity("click", base_time + timedelta(seconds=60 * i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_skips_actions_with_few_timestamps(analyzer, base_time):
    """Test detect_anomalies ignores actions with fewer than 3 timestamps."""
    # 5 total activities but 'view' has only 2 timestamps; 'click' has 3 with constant intervals.
    activities = [
        make_activity("view", base_time),
        make_activity("click", base_time + timedelta(seconds=0)),
        make_activity("click", base_time + timedelta(seconds=60)),
        make_activity("view", base_time + timedelta(seconds=1)),
        make_activity("click", base_time + timedelta(seconds=120)),
    ]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_no_stddev_no_anomalies(analyzer, base_time):
    """Test detect_anomalies returns no anomalies when intervals have zero std dev."""
    times = [base_time + timedelta(seconds=60 * i) for i in range(6)]
    activities = [make_activity("click", t) for t in times]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_invalid_timestamps_ignored(analyzer):
    """Test detect_anomalies handles invalid timestamps gracefully without raising."""
    activities = [
        {"action": "click", "timestamp": "invalid"},
        {"action": "click", "timestamp": None},
        {"action": "click", "timestamp": 123},
        {"action": "click", "timestamp": "2023-01-01T00:00:00Z"},
        {"action": "click", "timestamp": "2023-01-01T00:01:00Z"},
    ]
    # Less than 3 valid timestamps for 'click', so no anomalies
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_analyze_patterns_with_invalid_timestamps_does_not_raise(analyzer):
    """Test analyze_patterns handles activities with invalid timestamps without raising errors."""
    activities = [
        {"action": "A", "timestamp": "not-a-time"},
        {"action": "B", "timestamp": "also-not-a-time"},
        {"action": "C", "timestamp": "2023-01-01T00:00:00Z"},
    ]
    # Should run, likely only action sequences might produce patterns
    patterns = analyzer.analyze_patterns(activities)
    assert isinstance(patterns, list) and all(isinstance(p, ActivityPattern) for p in patterns) or patterns == []