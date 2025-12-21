import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Base datetime for constructing events"""
    return datetime(2023, 1, 1, 0, 0, 0)


def make_activity(ts, action="click"):
    """Helper to create an activity dict"""
    return {"timestamp": ts, "action": action}


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict method"""
    pattern = ActivityPattern(pattern_type="peak_hours", description="Desc", confidence=0.85)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "Desc"
    assert pattern.confidence == 0.85

    d = pattern.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "Desc",
        "confidence": 0.85,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization with default thresholds"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_datetime(analyzer, base_time):
    """Test _parse_timestamp returns datetime unchanged for datetime input"""
    dt = analyzer._parse_timestamp(base_time)
    assert isinstance(dt, datetime)
    assert dt == base_time


def test_activityanalyzer_parse_timestamp_iso_z(analyzer):
    """Test _parse_timestamp handles ISO strings with Z suffix"""
    ts = "2023-01-01T12:34:56Z"
    dt = analyzer._parse_timestamp(ts)
    assert isinstance(dt, datetime)
    # Ensure timezone-aware UTC
    assert dt.tzinfo is not None
    assert dt.utcoffset() == timedelta(0)


def test_activityanalyzer_parse_timestamp_invalid_string(analyzer):
    """Test _parse_timestamp returns None for invalid string"""
    assert analyzer._parse_timestamp("not-a-date") is None


def test_activityanalyzer_parse_timestamp_fromisoformat_error(analyzer):
    """Test _parse_timestamp handles exceptions from datetime.fromisoformat gracefully"""
    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=AttributeError):
        assert analyzer._parse_timestamp("2023-01-01T00:00:00") is None


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for no activities"""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_analyze_patterns_composes_results(analyzer):
    """Test analyze_patterns composes and concatenates results from detection methods"""
    fake_peak = [ActivityPattern("peak_hours", "peak desc", 0.85)]
    fake_seq = [ActivityPattern("action_sequence", "seq desc", 0.75)]
    fake_reg = [ActivityPattern("regularity", "reg desc", 0.9)]
    activities = [make_activity(datetime(2023, 1, 1, 13, 0, 0)) for _ in range(5)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=fake_peak) as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=fake_seq) as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=fake_reg) as m3:
        patterns = analyzer.analyze_patterns(activities)

    assert patterns == fake_peak + fake_seq + fake_reg
    m1.assert_called_once()
    m2.assert_called_once()
    m3.assert_called_once()


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies peak hours based on threshold"""
    activities = []
    # 3 events at 13:00 and 2 events at 14:00 => 3/5 = 0.6 > 0.2
    activities += [make_activity(base_time.replace(hour=13) + timedelta(minutes=i)) for i in range(3)]
    activities += [make_activity(base_time.replace(hour=14) + timedelta(minutes=i)) for i in range(2)]

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "13:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when timestamps are invalid"""
    activities = [{"timestamp": "invalid", "action": "x"}, {"timestamp": None, "action": "y"}]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_too_few(analyzer):
    """Test _detect_action_sequences returns empty when fewer than 3 activities"""
    activities = [make_activity(datetime(2023, 1, 1, 10, 0, 0), "a"),
                  make_activity(datetime(2023, 1, 1, 10, 1, 0), "b")]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_action_sequences_common(analyzer):
    """Test _detect_action_sequences detects repeated 3-action sequence"""
    activities = [
        {"timestamp": datetime(2023, 1, 1, 10, 0, 0), "action": "a"},
        {"timestamp": datetime(2023, 1, 1, 10, 1, 0), "action": "b"},
        {"timestamp": datetime(2023, 1, 1, 10, 2, 0), "action": "c"},
        {"timestamp": datetime(2023, 1, 1, 10, 3, 0), "action": "a"},
        {"timestamp": datetime(2023, 1, 1, 10, 4, 0), "action": "b"},
        {"timestamp": datetime(2023, 1, 1, 10, 5, 0), "action": "c"},
        {"timestamp": datetime(2023, 1, 1, 10, 6, 0), "action": "a"},
    ]
    patterns = analyzer._detect_action_sequences(activities)
    assert any(p.pattern_type == "action_sequence" for p in patterns)
    seq_patterns = [p for p in patterns if p.pattern_type == "action_sequence"]
    found = False
    for p in seq_patterns:
        if "Common sequence: a → b → c (occurred 2 times)" in p.description:
            found = True
            assert p.confidence == 0.75
    assert found


def test_activityanalyzer_detect_regularity_high(analyzer, base_time):
    """Test _detect_regularity identifies highly regular intervals"""
    activities = [
        make_activity(base_time + timedelta(minutes=10 * i)) for i in range(6)
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV: 0.00" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty for irregular activity intervals"""
    activities = [
        make_activity(base_time + timedelta(minutes=1)),
        make_activity(base_time + timedelta(minutes=2)),
        make_activity(base_time + timedelta(minutes=4)),
        make_activity(base_time + timedelta(minutes=8)),
        make_activity(base_time + timedelta(minutes=16)),
        make_activity(base_time + timedelta(minutes=32)),
    ]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 when no activities"""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_basic(analyzer, base_time):
    """Test get_user_score with known values to validate scoring calculation"""
    actions = ["a", "b", "a", "c", "a", "d", "a", "b", "c", "a"]  # 10 total, 4 unique
    activities = [
        make_activity(base_time + timedelta(minutes=i), actions[i]) for i in range(10)
    ]
    score = analyzer.get_user_score(activities)
    # Computation:
    # diversity = 4/10 = 0.4
    # frequency = min(10 actions per 1 day / 10, 1) = 1.0
    # volume = min(10/100, 1) = 0.1
    # final = (0.4*0.3 + 1.0*0.4 + 0.1*0.3) * 100 = (0.12 + 0.4 + 0.03)*100 = 55.0
    assert score == 55.0


def test_activityanalyzer_get_user_score_invalid_timestamps(analyzer):
    """Test get_user_score falls back to total_actions for frequency when timestamps invalid"""
    # 5 actions, invalid timestamps so actions_per_day = total_actions = 5
    activities = [{"timestamp": "invalid", "action": a} for a in ["a", "b", "a", "a", "c"]]
    score = analyzer.get_user_score(activities)
    # unique_actions = 3, total = 5
    # diversity = 3/5 = 0.6
    # frequency = min(5/10,1) = 0.5
    # volume = min(5/100,1) = 0.05
    # final = (0.6*0.3 + 0.5*0.4 + 0.05*0.3) * 100 = (0.18 + 0.2 + 0.015)*100 = 39.5
    assert score == 39.5


def test_activityanalyzer_get_user_score_unsorted_timestamps(analyzer):
    """Test get_user_score handles unsorted timestamps and non-positive day differences"""
    activities = [
        make_activity(datetime(2023, 1, 2, 0, 0, 0), "a"),  # later date first
        make_activity(datetime(2023, 1, 1, 23, 59, 0), "b"),
        make_activity(datetime(2023, 1, 2, 1, 0, 0), "c"),
    ]
    score = analyzer.get_user_score(activities)
    # total=3, unique=3
    # days_active = max((last - first).days, 1) => first=2023-01-02, last=2023-01-02 01:00 => .days = 0 -> 1
    # actions_per_day = 3/1=3 => freq = 0.3
    # diversity = 3/3=1.0
    # volume = 3/100=0.03
    # final = (1.0*0.3 + 0.3*0.4 + 0.03*0.3)*100 = (0.3 + 0.12 + 0.009)*100 = 42.9
    assert score == 42.9


def test_activityanalyzer_detect_anomalies_insufficient_data(analyzer):
    """Test detect_anomalies returns empty list when fewer than 5 activities"""
    activities = [
        make_activity(datetime(2023, 1, 1, 0, i, 0), "x") for i in range(4)
    ]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_outlier_interval(analyzer, base_time):
    """Test detect_anomalies flags a large outlier interval using z-score threshold"""
    # Build 102 timestamps: 100 intervals of 10s and 1 interval of 1000s
    timestamps = [base_time + timedelta(seconds=10 * i) for i in range(101)]
    timestamps.append(timestamps[-1] + timedelta(seconds=1000))
    activities = [make_activity(ts, "click") for ts in timestamps]
    # Add another action with too few timestamps to be considered
    activities += [make_activity(base_time + timedelta(seconds=5 * i), "view") for i in range(2)]

    anomalies = analyzer.detect_anomalies(activities)
    # Expect one anomaly at the last timestamp for 'click'
    assert len(anomalies) >= 1
    # Find the anomaly for 'click'
    click_anoms = [a for a in anomalies if a["action"] == "click"]
    assert len(click_anoms) >= 1
    # The anomalous timestamp should be the last 'click' timestamp
    expected_ts = timestamps[-1].isoformat()
    assert any(a["timestamp"] == expected_ts for a in click_anoms)
    # Check z_score exceeds threshold significantly
    assert any(a["z_score"] >= 9.5 for a in click_anoms)
    # Reason should include useful message
    assert all("Unusual interval" in a["reason"] for a in click_anoms)


def test_activityanalyzer_detect_anomalies_no_std_dev(analyzer, base_time):
    """Test detect_anomalies returns no anomalies when std_dev is zero (perfect regularity)"""
    timestamps = [base_time + timedelta(minutes=i) for i in range(6)]  # equal 1-min intervals
    activities = [make_activity(ts, "regular") for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_ignores_unparsed(analyzer, base_time):
    """Test detect_anomalies ignores activities with unparseable timestamps via mocked parser"""
    activities = [{"timestamp": "invalid", "action": "x"} for _ in range(10)]

    with patch.object(ActivityAnalyzer, "_parse_timestamp", return_value=None) as mock_parse:
        anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []
    assert mock_parse.call_count == 10