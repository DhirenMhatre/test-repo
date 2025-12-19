import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide an ActivityAnalyzer instance."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing activities."""
    return datetime(2023, 1, 1, 12, 0, 0)


def make_activity(action: str, ts: datetime):
    """Helper to create an activity dict."""
    return {"action": action, "timestamp": ts}


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict output."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.9)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "desc"
    assert pattern.confidence == 0.9

    d = pattern.to_dict()
    assert d == {"pattern_type": "peak_hours", "description": "desc", "confidence": 0.9}


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp with datetime objects and strings."""
    # datetime object
    dt = datetime(2024, 5, 17, 8, 30, 0)
    assert analyzer._parse_timestamp(dt) == dt

    # ISO string with Z (UTC)
    iso_z = "2024-05-17T08:30:00Z"
    parsed = analyzer._parse_timestamp(iso_z)
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is not None
    assert parsed.isoformat().endswith("+00:00")

    # ISO string without Z
    iso = "2024-05-17T08:30:00"
    parsed2 = analyzer._parse_timestamp(iso)
    assert isinstance(parsed2, datetime)
    assert parsed2.tzinfo is None

    # Invalid string
    assert analyzer._parse_timestamp("not-a-date") is None

    # Unsupported type
    assert analyzer._parse_timestamp(12345) is None


def test_parse_timestamp_exception_handled(analyzer):
    """Test _parse_timestamp handles exceptions from fromisoformat and returns None."""
    with patch("src.activity_analyzer.datetime") as mock_datetime:
        mock_datetime.fromisoformat.side_effect = ValueError("bad format")
        assert analyzer._parse_timestamp("2024-01-01T00:00:00") is None


def test_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    activities = []
    # 3 activities at 14:00
    for i in range(3):
        activities.append(make_activity("a", base_time.replace(hour=14, minute=i)))
    # 2 activities at 09:00
    for i in range(2):
        activities.append(make_activity("a", base_time.replace(hour=9, minute=i)))
    # 5 activities spread across other hours
    others = [8, 10, 11, 15, 16]
    for i, h in enumerate(others):
        activities.append(make_activity("a", base_time.replace(hour=h, minute=i)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert isinstance(pat, ActivityPattern)
    assert pat.pattern_type == "peak_hours"
    assert "14:00" in pat.description
    assert pat.confidence == 0.85


def test_detect_peak_hours_no_parseable(analyzer):
    """Test _detect_peak_hours returns empty when no parseable timestamps."""
    activities = [{"action": "a", "timestamp": "invalid"} for _ in range(5)]
    assert analyzer._detect_peak_hours(activities) == []


def test_detect_action_sequences_common(analyzer, base_time):
    """Test _detect_action_sequences detects repeated 3-action sequence."""
    actions = ["A", "B", "C", "A", "B", "C", "A"]
    activities = [make_activity(a, base_time + timedelta(seconds=i)) for i, a in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "action_sequence"
    assert "Common sequence: A → B → C (occurred 2 times)" in pat.description
    assert pat.confidence == 0.75


def test_detect_action_sequences_insufficient(analyzer, base_time):
    """Test _detect_action_sequences returns empty for less than 3 activities."""
    activities = [make_activity("A", base_time), make_activity("B", base_time + timedelta(seconds=1))]
    assert analyzer._detect_action_sequences(activities) == []


def test_detect_regularity_regular(analyzer, base_time):
    """Test _detect_regularity identifies highly regular activity patterns."""
    activities = [make_activity("ping", base_time + timedelta(hours=i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "regularity"
    assert "CV: 0.00" in pat.description
    assert pat.confidence == 0.9


def test_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty for irregular intervals."""
    # Irregular intervals: 0h, 1h, 1.5h, 3h, 4.2h
    deltas = [0, 1, 2.5, 5.5, 9.7, 15.0]
    activities = [make_activity("ping", base_time + timedelta(hours=h)) for h in deltas]
    assert analyzer._detect_regularity(activities) == []


def test_detect_anomalies_basic(analyzer, base_time):
    """Test detect_anomalies flags an interval with z-score above threshold."""
    # Build 12 timestamps for action 'click': 10 small intervals (10s), then 1 large interval (10000s)
    times = [base_time]
    for _ in range(10):
        times.append(times[-1] + timedelta(seconds=10))
    times.append(times[-1] + timedelta(seconds=10000))  # anomalous large gap

    activities = [make_activity("click", t) for t in times]

    # Include other actions to ensure per-action grouping doesn't create false anomalies
    activities += [
        make_activity("view", base_time + timedelta(minutes=i)) for i in range(3)
    ]

    anomalies = analyzer.detect_anomalies(activities)
    # Expect exactly one anomaly corresponding to the large gap for 'click'
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "click"
    assert "Unusual interval" in anomaly["reason"]
    # The timestamp should be the end of the anomalous interval
    assert anomaly["timestamp"] == times[-1].isoformat()
    assert anomaly["z_score"] > analyzer.anomaly_threshold


def test_detect_anomalies_not_enough_data(analyzer, base_time):
    """Test detect_anomalies returns empty list when total activities < 5."""
    activities = [make_activity("a", base_time + timedelta(seconds=i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_detect_anomalies_zero_std_dev(analyzer, base_time):
    """Test detect_anomalies handles zero standard deviation without errors."""
    # All intervals equal for action 'steady' -> std_dev == 0, no anomalies expected
    times = [base_time + timedelta(seconds=10 * i) for i in range(6)]  # 5 equal intervals
    activities = [make_activity("steady", t) for t in times]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list."""
    assert analyzer.get_user_score([]) == 0.0


def test_get_user_score_computation_unsorted_timestamps(analyzer, base_time):
    """Test get_user_score with known actions and unsorted timestamps affecting days_active."""
    # 10 activities, actions: A,B,C repeated
    actions = ["A", "B", "C", "A", "B", "C", "A", "B", "C", "A"]
    # Intentionally unsorted: first timestamp is later than last
    activities = [
        make_activity(actions[i], base_time + timedelta(days=1, minutes=i)) for i in range(5)
    ] + [
        make_activity(actions[i+5], base_time - timedelta(days=1, minutes=i)) for i in range(5)
    ]
    # Expected:
    # total_actions = 10
    # unique_actions = 3
    # days_active uses first and last as given (unsorted) -> negative -> max(neg,1)=1
    # actions_per_day = 10 / 1 = 10 => frequency_score = 1.0
    # diversity_score = 3/10 = 0.3
    # volume_score = 10/100 = 0.1
    # final = (0.3*0.3 + 1.0*0.4 + 0.1*0.3)*100 = (0.09 + 0.4 + 0.03)*100 = 52.0
    score = analyzer.get_user_score(activities)
    assert score == 52.0


def test_get_user_score_missing_timestamps(analyzer):
    """Test get_user_score defaults actions_per_day to total_actions when timestamps missing."""
    activities = [{"action": "A"}, {"action": "B"}, {"action": "C"}]
    # total_actions = 3
    # unique_actions = 3
    # actions_per_day = 3 (no timestamps)
    # diversity = 1.0, frequency = min(3/10,1)=0.3, volume = 0.03
    # final = (1*0.3 + 0.3*0.4 + 0.03*0.3)*100 = (0.3 + 0.12 + 0.009)*100 = 42.9
    score = analyzer.get_user_score(activities)
    assert score == 42.9


def test_analyze_patterns_combines_detectors_with_mocks(analyzer):
    """Test analyze_patterns aggregates results from internal detectors."""
    activities = [{"action": "x", "timestamp": "2024-01-01T00:00:00Z"}]

    mock_patterns_peak = [ActivityPattern("peak_hours", "peak", 0.85)]
    mock_patterns_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    mock_patterns_reg = [ActivityPattern("regularity", "reg", 0.9)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_patterns_peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_patterns_seq) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_patterns_reg) as m_reg:
        results = analyzer.analyze_patterns(activities)

        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)

        assert results == mock_patterns_peak + mock_patterns_seq + mock_patterns_reg


def test_analyze_patterns_empty_short_circuits(analyzer):
    """Test analyze_patterns returns empty and does not call detectors when no activities."""
    with patch.object(ActivityAnalyzer, "_detect_peak_hours") as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences") as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity") as m_reg:
        results = analyzer.analyze_patterns([])
        assert results == []
        m_peak.assert_not_called()
        m_seq.assert_not_called()
        m_reg.assert_not_called()


def test_peak_hours_threshold_adjustment(analyzer, base_time):
    """Test _detect_peak_hours respects custom threshold."""
    analyzer.peak_hour_threshold = 0.5  # make it harder to hit
    activities = []
    # 4 at hour 10, 3 at hour 11, 3 at hour 12 -> no hour exceeds 0.5 with total 10
    for i in range(4):
        activities.append(make_activity("a", base_time.replace(hour=10, minute=i)))
    for i in range(3):
        activities.append(make_activity("a", base_time.replace(hour=11, minute=i)))
    for i in range(3):
        activities.append(make_activity("a", base_time.replace(hour=12, minute=i)))

    assert analyzer._detect_peak_hours(activities) == []


def test_parse_timestamp_with_timezone_z(analyzer):
    """Test _parse_timestamp correctly handles 'Z' UTC suffix."""
    ts_str = "2023-07-01T10:15:30Z"
    dt = analyzer._parse_timestamp(ts_str)
    assert dt is not None
    assert dt.tzinfo is not None
    assert dt.utcoffset() == timedelta(0)


def test_detect_anomalies_multiple_actions(analyzer, base_time):
    """Test detect_anomalies analyzes actions independently."""
    # 'click' with anomaly as before
    times = [base_time]
    for _ in range(10):
        times.append(times[-1] + timedelta(seconds=10))
    times.append(times[-1] + timedelta(seconds=10000))
    activities_click = [make_activity("click", t) for t in times]

    # 'view' consistent intervals, should not produce anomaly
    view_times = [base_time + timedelta(seconds=20 * i) for i in range(8)]
    activities_view = [make_activity("view", t) for t in view_times]

    anomalies = analyzer.detect_anomalies(activities_click + activities_view)
    assert len(anomalies) == 1
    assert anomalies[0]["action"] == "click"