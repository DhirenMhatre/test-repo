import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Base datetime for constructing test timestamps"""
    return datetime(2023, 1, 1, 10, 0, 0)


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict serialization"""
    ap = ActivityPattern(pattern_type="peak_hours", description="High activity", confidence=0.9)
    assert ap.pattern_type == "peak_hours"
    assert ap.description == "High activity"
    assert ap.confidence == 0.9

    d = ap.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "High activity",
        "confidence": 0.9,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default thresholds on initialization"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_valid_variants(analyzer):
    """Test _parse_timestamp handles datetime and ISO-8601 with Z suffix"""
    dt = datetime(2023, 1, 1, 12, 30, 0)
    assert analyzer._parse_timestamp(dt) == dt

    iso_z = "2023-01-01T12:30:00Z"
    parsed = analyzer._parse_timestamp(iso_z)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2023 and parsed.month == 1 and parsed.day == 1
    assert parsed.hour == 12 and parsed.minute == 30 and parsed.second == 0
    assert parsed.tzinfo is not None  # Z -> +00:00


def test_activityanalyzer_parse_timestamp_invalid_and_exception(analyzer):
    """Test _parse_timestamp returns None for invalid inputs and handles exceptions"""
    assert analyzer._parse_timestamp("not-a-timestamp") is None

    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=ValueError):
        assert analyzer._parse_timestamp("2023-01-01T00:00:00Z") is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold"""
    # 5 activities at 10:xx and 1 at 09:xx
    activities = []
    for i in range(5):
        activities.append({"action": "x", "timestamp": base_time + timedelta(minutes=i)})
    activities.append({"action": "x", "timestamp": base_time - timedelta(hours=1)})

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "10:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_threshold_equal_not_included(analyzer, base_time):
    """Test _detect_peak_hours does not include hours equal to threshold (strictly greater only)"""
    # 5 events across 5 distinct hours -> each hour fraction = 0.2, should not be included
    activities = []
    for i in range(5):
        activities.append({"action": "x", "timestamp": base_time + timedelta(hours=i)})

    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_no_parseable_timestamps(analyzer):
    """Test _detect_peak_hours returns empty if timestamps are unparsable"""
    activities = [{"action": "x", "timestamp": "invalid"} for _ in range(5)]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_common_sequences(analyzer, base_time):
    """Test _detect_action_sequences identifies common 3-action sequence occurring at least twice"""
    actions = ["A", "B", "C", "X", "A", "B", "C"]
    activities = [
        {"action": a, "timestamp": base_time + timedelta(minutes=i)} for i, a in enumerate(actions)
    ]

    patterns = analyzer._detect_action_sequences(activities)
    # Should identify "A → B → C" occurring twice
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "A → B → C" in p.description
    assert "occurred 2 times" in p.description
    assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_too_short(analyzer, base_time):
    """Test _detect_action_sequences returns empty when not enough activities"""
    activities = [
        {"action": "A", "timestamp": base_time},
        {"action": "B", "timestamp": base_time + timedelta(minutes=1)},
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_regular_and_irregular(analyzer, base_time):
    """Test _detect_regularity returns regularity pattern for low CV and none for high CV"""
    # Regular: every 10 minutes (constant intervals)
    regular_acts = [
        {"action": "x", "timestamp": base_time + timedelta(minutes=10 * i)} for i in range(6)
    ]
    regular_patterns = analyzer._detect_regularity(regular_acts)
    assert len(regular_patterns) == 1
    assert regular_patterns[0].pattern_type == "regularity"
    assert "CV: 0.00" in regular_patterns[0].description

    # Irregular: varying intervals to increase CV
    ts = [
        base_time,
        base_time + timedelta(seconds=60),
        base_time + timedelta(seconds=180),
        base_time + timedelta(seconds=480),
        base_time + timedelta(seconds=540),
        base_time + timedelta(seconds=960),
    ]
    irregular_acts = [{"action": "x", "timestamp": t} for t in ts]
    irregular_patterns = analyzer._detect_regularity(irregular_acts)
    assert irregular_patterns == []


def test_activityanalyzer_analyze_patterns_combines_detectors(analyzer, base_time):
    """Test analyze_patterns aggregates patterns from all detectors"""
    # Construct activities that trigger all detectors:
    # - Peak hours: all in hour 10
    # - Regularity: every 10 minutes
    # - Action sequences: A→B→C repeated twice
    actions = ["A", "B", "C", "A", "B", "C"]
    activities = [
        {"action": a, "timestamp": base_time + timedelta(minutes=10 * i)} for i, a in enumerate(actions)
    ]

    patterns = analyzer.analyze_patterns(activities)

    types = [p.pattern_type for p in patterns]
    assert "peak_hours" in types
    assert "action_sequence" in types
    assert "regularity" in types
    assert len(patterns) >= 3


def test_activityanalyzer_analyze_patterns_uses_private_detectors_with_mock(analyzer):
    """Test analyze_patterns delegates to private detector methods and combines their results"""
    activities = [{"action": "A", "timestamp": datetime(2023, 1, 1, 0, 0, 0)}]

    peak = [ActivityPattern("peak_hours", "Peak", 0.85)]
    seq = [ActivityPattern("action_sequence", "Seq", 0.75)]
    reg = [ActivityPattern("regularity", "Reg", 0.9)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=seq) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=reg) as m_reg:
        res = analyzer.analyze_patterns(activities)
        assert res == peak + seq + reg
        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for empty activities"""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities"""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_invalid_timestamps(analyzer):
    """Test get_user_score when timestamps are invalid falls back to total_actions frequency"""
    # total_actions=4, unique_actions (due to algorithm) becomes 4, frequency=0.4, volume=0.04 => 47.2
    activities = [
        {"action": "A", "timestamp": "bad"},
        {"action": "B", "timestamp": "bad"},
        {"action": "B", "timestamp": "bad"},
        {"action": "C", "timestamp": "bad"},
    ]
    score = analyzer.get_user_score(activities)
    assert score == 47.2


def test_activityanalyzer_get_user_score_basic_valid(analyzer, base_time):
    """Test get_user_score with valid timestamps and unique actions within one day"""
    # 10 activities in same day, unique actions
    activities = [
        {"action": f"A{i}", "timestamp": base_time + timedelta(minutes=i)} for i in range(10)
    ]
    # diversity=1.0, frequency=1.0, volume=0.1 -> final 73.0
    score = analyzer.get_user_score(activities)
    assert score == 73.0


def test_activityanalyzer_detect_anomalies_activity_intervals_anomaly_detected(analyzer, base_time):
    """Test detect_anomalies flags unusually large interval for an action"""
    # Build 22 activities: 20 intervals of 10s, then one very large interval
    activities = []
    ts = base_time
    activities.append({"action": "click", "timestamp": ts})
    for _ in range(20):
        ts = ts + timedelta(seconds=10)
        activities.append({"action": "click", "timestamp": ts})
    # big interval
    ts = ts + timedelta(seconds=100000)
    activities.append({"action": "click", "timestamp": ts})

    anomalies = analyzer.detect_anomalies(activities)
    # Should detect at least one anomaly for 'click' at the last timestamp
    assert len(anomalies) >= 1
    last_anomaly = [a for a in anomalies if a["timestamp"] == ts.isoformat()]
    assert last_anomaly, "Expected anomaly at the last timestamp"
    assert last_anomaly[0]["action"] == "click"
    assert last_anomaly[0]["z_score"] > analyzer.anomaly_threshold
    assert "Unusual interval" in last_anomaly[0]["reason"]


def test_activityanalyzer_detect_anomalies_not_enough_activities(analyzer, base_time):
    """Test detect_anomalies returns empty when there are fewer than 5 activities overall"""
    activities = [
        {"action": "click", "timestamp": base_time + timedelta(seconds=i * 10)} for i in range(4)
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_action_with_few_timestamps_skipped(analyzer, base_time):
    """Test detect_anomalies skips actions with fewer than 3 timestamps"""
    activities = [
        {"action": "click", "timestamp": base_time},
        {"action": "click", "timestamp": base_time + timedelta(seconds=10)},
        {"action": "view", "timestamp": base_time + timedelta(seconds=20)},
        {"action": "view", "timestamp": base_time + timedelta(seconds=30)},
        {"action": "view", "timestamp": base_time + timedelta(seconds=1000)},
    ]
    # 'click' has 2 timestamps; 'view' has 3 but intervals [10, 970] unlikely to exceed threshold
    anomalies = analyzer.detect_anomalies(activities)
    # Ensure either empty or anomalies only for 'view' if any; but not for 'click'
    assert all(a["action"] != "click" for a in anomalies)


def test_activityanalyzer_parse_timestamp_with_mocked_return(analyzer):
    """Test _parse_timestamp is used by _detect_peak_hours by mocking it"""
    activities = [{"action": "x", "timestamp": "whatever"} for _ in range(3)]

    fake_dt = datetime(2023, 1, 1, 15, 0, 0, tzinfo=timezone.utc)

    def fake_parse(_):
        return fake_dt

    with patch.object(ActivityAnalyzer, "_parse_timestamp", side_effect=fake_parse) as mocked_parse:
        patterns = analyzer._detect_peak_hours(activities)
        mocked_parse.assert_called()
        assert len(patterns) == 1
        assert "15:00" in patterns[0].description