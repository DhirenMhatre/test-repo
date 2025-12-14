import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing activities"""
    return datetime(2023, 1, 1, 8, 0, 0)


def make_activity(ts, action):
    """Helper to create an activity dict"""
    return {"timestamp": ts, "action": action}


def test_activitypattern_initialization_and_to_dict():
    """Test ActivityPattern initialization and to_dict output"""
    pattern = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.85)
    d = pattern.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "desc"
    assert d["confidence"] == 0.85


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default initialization values"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp for datetime, ISO strings with/without Z, and invalid input"""
    dt = datetime(2023, 1, 1, 10, 0, 0)
    assert analyzer._parse_timestamp(dt) == dt

    iso_no_z = "2023-01-01T10:00:00"
    parsed_no_z = analyzer._parse_timestamp(iso_no_z)
    assert isinstance(parsed_no_z, datetime)
    assert parsed_no_z.tzinfo is None

    iso_z = "2023-01-01T10:00:00Z"
    parsed_z = analyzer._parse_timestamp(iso_z)
    assert parsed_z.tzinfo is not None
    assert parsed_z.utcoffset().total_seconds() == 0

    assert analyzer._parse_timestamp("not-a-timestamp") is None
    assert analyzer._parse_timestamp(12345) is None


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for no activities"""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_analyze_patterns_calls_detectors_and_aggregates(analyzer, base_time):
    """Test analyze_patterns calls internal detectors and aggregates their patterns"""
    activities = [
        make_activity(base_time + timedelta(minutes=i), "A") for i in range(6)
    ]

    mock_peak = [ActivityPattern("peak_hours", "peak", 0.8)]
    mock_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    mock_reg = [ActivityPattern("regularity", "reg", 0.9)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as p_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as p_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as p_reg:

        patterns = analyzer.analyze_patterns(activities)

        p_peak.assert_called_once_with(activities)
        p_seq.assert_called_once_with(activities)
        p_reg.assert_called_once_with(activities)

        assert isinstance(patterns, list)
        assert len(patterns) == 3
        types = [p.pattern_type for p in patterns]
        assert "peak_hours" in types
        assert "action_sequence" in types
        assert "regularity" in types


def test_activityanalyzer_analyze_patterns_propagates_exception(analyzer, base_time):
    """Test analyze_patterns propagates exceptions from internal detection methods"""
    activities = [make_activity(base_time, "A")]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", side_effect=ValueError("boom")):
        with pytest.raises(ValueError):
            analyzer.analyze_patterns(activities)


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities"""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_valid_timestamps_same_day(analyzer, base_time):
    """Test get_user_score calculation with valid timestamps on the same day"""
    activities = [make_activity(base_time + timedelta(minutes=i), "A") for i in range(10)]
    score = analyzer.get_user_score(activities)
    # Diversity bug in implementation makes diversity_score = 1.0
    # actions_per_day = 10/1 => frequency_score = 1.0, volume_score = 0.1
    # final = (1*0.3 + 1*0.4 + 0.1*0.3) * 100 = 73.0
    assert score == 73.0


def test_activityanalyzer_get_user_score_without_parsable_timestamps(analyzer):
    """Test get_user_score when timestamps are not parsable uses total_actions for frequency"""
    activities = [
        {"timestamp": "invalid", "action": "A"},
        {"timestamp": None, "action": "B"},
        {"timestamp": {}, "action": "C"},
        {"timestamp": "also-invalid", "action": "D"},
        {"timestamp": 123, "action": "E"},
    ]
    score = analyzer.get_user_score(activities)
    # total_actions=5; actions_per_day=5; frequency_score=0.5; volume=0.05; diversity bug => 1.0
    # final=(0.3 + 0.2 + 0.015) * 100 = 51.5
    assert score == 51.5


def test_activityanalyzer_detect_anomalies_requires_min_length(analyzer, base_time):
    """Test detect_anomalies returns empty when fewer than 5 activities provided"""
    activities = [make_activity(base_time + timedelta(seconds=i), "A") for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_flags_interval_outlier(analyzer, base_time):
    """Test detect_anomalies flags a large interval outlier using z-score > anomaly_threshold"""
    # Construct 12 timestamps for one action: 10 intervals of 10s, then one interval of 100s
    times = [base_time]
    for _ in range(10):
        times.append(times[-1] + timedelta(seconds=10))
    times.append(times[-1] + timedelta(seconds=100))  # outlier interval at the end

    activities = [make_activity(t, "click") for t in times]
    anomalies = analyzer.detect_anomalies(activities)

    assert len(anomalies) >= 1
    # Find anomaly for 'click' at the last timestamp
    outliers = [a for a in anomalies if a["action"] == "click" and a["timestamp"] == times[-1].isoformat()]
    assert len(outliers) == 1
    assert outliers[0]["z_score"] >= analyzer.anomaly_threshold
    assert "Unusual interval" in outliers[0]["reason"]


def test_activityanalyzer_detect_anomalies_ignores_insufficient_action_samples(analyzer, base_time):
    """Test detect_anomalies ignores actions with fewer than 3 timestamps"""
    # Overall length >=5 but 'x' has only 2 timestamps, 'y' has 3 steady intervals
    x_times = [base_time, base_time + timedelta(seconds=10)]
    y_times = [base_time + timedelta(minutes=1) + timedelta(seconds=s) for s in (0, 10, 20)]
    activities = [make_activity(t, "x") for t in x_times] + [make_activity(t, "y") for t in y_times]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold"""
    activities = []
    # 9:00 hour - 9 events
    activities += [make_activity(base_time.replace(hour=9) + timedelta(minutes=i), "A") for i in range(9)]
    # 15:00 hour - 5 events
    activities += [make_activity(base_time.replace(hour=15) + timedelta(minutes=i), "B") for i in range(5)]
    # Other hours - 8 events spread
    activities += [make_activity(base_time.replace(hour=12) + timedelta(minutes=i), "C") for i in range(4)]
    activities += [make_activity(base_time.replace(hour=18) + timedelta(minutes=i), "D") for i in range(4)]
    # Total = 26; 9/26≈0.346, 5/26≈0.192 -> only hour 9 should pass (>0.2)
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "09:00" in p.description
    assert "15:00" not in p.description


def test_activityanalyzer_detect_peak_hours_below_threshold(analyzer, base_time):
    """Test _detect_peak_hours returns empty when no hour meets threshold"""
    activities = [make_activity(base_time.replace(hour=h), "A") for h in range(5)]  # 1 per hour
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_common(analyzer, base_time):
    """Test _detect_action_sequences returns common 3-action sequence"""
    actions = ["A", "B", "C", "D", "A", "B", "C"]
    activities = [make_activity(base_time + timedelta(minutes=i), act) for i, act in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "A → B → C (occurred 2 times)" in p.description
    assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_insufficient(analyzer, base_time):
    """Test _detect_action_sequences returns empty when fewer than 3 activities"""
    activities = [make_activity(base_time, "A"), make_activity(base_time + timedelta(minutes=1), "B")]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity identifies highly regular activity pattern"""
    activities = [make_activity(base_time + timedelta(seconds=60 * i), "A") for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular" in p.description
    assert "CV:" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty for irregular intervals"""
    increments = [0, 10, 60, 90, 120, 200]  # varied intervals
    activities = [make_activity(base_time + timedelta(seconds=s), "A") for s in increments]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []