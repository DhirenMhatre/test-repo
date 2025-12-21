import pytest
from unittest.mock import patch
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


def test_activitypattern_to_dict_basic():
    """Test ActivityPattern.to_dict returns correct dictionary"""
    p = ActivityPattern(pattern_type="peak_hours", description="High activity during hours: 09:00", confidence=0.85)
    d = p.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "High activity during hours: 09:00",
        "confidence": 0.85,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization sets default thresholds"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_datetime_input(analyzer):
    """Test _parse_timestamp returns datetime as-is when input is datetime"""
    ts = datetime(2023, 1, 1, 12, 0, 0)
    parsed = analyzer._parse_timestamp(ts)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_z(analyzer):
    """Test _parse_timestamp parses ISO string ending with Z to timezone-aware datetime"""
    ts_str = "2023-01-01T00:00:00Z"
    parsed = analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is not None
    assert parsed.utcoffset() == timedelta(0)


def test_activityanalyzer_parse_timestamp_invalid(analyzer):
    """Test _parse_timestamp returns None for invalid string"""
    parsed = analyzer._parse_timestamp("not-a-date")
    assert parsed is None


def test_activityanalyzer_parse_timestamp_nonstring(analyzer):
    """Test _parse_timestamp returns None for non-supported types"""
    parsed = analyzer._parse_timestamp(12345)
    assert parsed is None


def test_activityanalyzer_parse_timestamp_fromiso_exception(analyzer, monkeypatch):
    """Test _parse_timestamp handles exceptions from datetime.fromisoformat and returns None"""
    def raise_value_error(_):
        raise ValueError("bad")
    # Patch the datetime.fromisoformat used inside the module
    import src.activity_analyzer as module_under_test
    monkeypatch.setattr(module_under_test.datetime, "fromisoformat", raise_value_error)
    parsed = analyzer._parse_timestamp("2023-01-01T00:00:00")
    assert parsed is None


def test_activityanalyzer_analyze_patterns_calls_detectors(analyzer):
    """Test analyze_patterns calls internal detectors and aggregates results"""
    activities = [{"action": "a", "timestamp": "2023-01-01T01:00:00"}]

    peak_patterns = [ActivityPattern("peak_hours", "desc1", 0.85)]
    seq_patterns = [ActivityPattern("action_sequence", "desc2", 0.75)]
    reg_patterns = [ActivityPattern("regularity", "desc3", 0.9)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=peak_patterns) as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=seq_patterns) as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=reg_patterns) as mock_reg:
        result = analyzer.analyze_patterns(activities)
        assert result == peak_patterns + seq_patterns + reg_patterns
        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for empty activities"""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities"""
    score = analyzer.get_user_score([])
    assert score == 0.0


def test_activityanalyzer_get_user_score_valid_timestamps_multi_day(analyzer):
    """Test get_user_score computes expected score with valid timestamps over multiple days"""
    # 10 activities from Jan 1 to Jan 6 (5 days difference)
    base = datetime(2023, 1, 1, 0, 0, 0)
    activities = []
    actions = ["A"] * 5 + ["B"] * 3 + ["C"] * 2  # diversity 3/10
    for i, act in enumerate(actions):
        # spread activities evenly; last one at Jan 6 00:00:00
        ts = (base + timedelta(days=(5 * i // (len(actions) - 1)))).isoformat()
        activities.append({"action": act, "timestamp": ts})

    # Expected calculation: diversity=0.3, actions_per_day=2.0 -> freq=0.2, volume=0.1
    # Weighted sum = 0.3*0.3 + 0.4*0.2 + 0.3*0.1 = 0.2; *100 = 20.0
    score = analyzer.get_user_score(activities)
    assert score == 20.0


def test_activityanalyzer_get_user_score_unparseable_timestamps(analyzer):
    """Test get_user_score uses fallback when timestamps cannot be parsed"""
    activities = [
        {"action": "A", "timestamp": "bad"},
        {"action": "B", "timestamp": "not-a-ts"},
        {"action": "C", "timestamp": None},
        {"action": "D", "timestamp": 123},
    ]
    # diversity=1.0 (all unique), actions_per_day=4 (fallback) -> freq=0.4, volume=0.04
    # Weighted sum = 0.3*1.0 + 0.4*0.4 + 0.3*0.04 = 0.472; *100 = 47.2
    score = analyzer.get_user_score(activities)
    assert score == 47.2


def test_activityanalyzer_detect_anomalies_not_enough_activities(analyzer):
    """Test detect_anomalies returns empty when not enough activities"""
    activities = [{"action": "click", "timestamp": datetime(2023, 1, 1, 0, 0, 0)}] * 4
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_flags_outlier_interval(analyzer):
    """Test detect_anomalies flags an interval outlier using z-score threshold"""
    base = datetime(2023, 1, 1, 0, 0, 0)
    # Build 12 timestamps for one action 'click' to produce 11 intervals
    # 10 intervals of 60s and 1 large interval of 3600s to create outlier
    intervals = [60] * 5 + [3600] + [60] * 5
    timestamps = [base]
    for delta in intervals:
        timestamps.append(timestamps[-1] + timedelta(seconds=delta))
    activities = [{"action": "click", "timestamp": ts} for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    # Expect exactly one anomaly corresponding to the large interval
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "click"
    # Timestamp should be the end of the large interval
    expected_ts = timestamps[6].isoformat()  # after the big interval at index 5
    assert anomaly["timestamp"] == expected_ts
    assert "Unusual interval" in anomaly["reason"]
    assert anomaly["z_score"] >= 3.0


def test_activityanalyzer_detect_anomalies_multiple_actions_mixed_counts(analyzer):
    """Test detect_anomalies ignores actions with less than 3 timestamps"""
    base = datetime(2023, 1, 2, 0, 0, 0)
    # Action 'few' with only 2 timestamps should be ignored
    few = [{"action": "few", "timestamp": base}, {"action": "few", "timestamp": base + timedelta(minutes=1)}]
    # Action 'normal' with uniform intervals (no anomalies)
    normal_times = [base + timedelta(minutes=i) for i in range(6)]
    normal = [{"action": "normal", "timestamp": ts} for ts in normal_times]
    # Action 'spike' with outlier, ensure enough total activities
    spike_times = [base + timedelta(minutes=i) for i in range(6)]
    spike_times[3] = spike_times[2] + timedelta(hours=3)
    spike = [{"action": "spike", "timestamp": ts} for ts in spike_times]

    activities = few + normal + spike
    anomalies = analyzer.detect_anomalies(activities)

    # 'few' should not produce any anomalies
    assert all(a["action"] != "few" for a in anomalies)
    # 'normal' should not produce anomalies
    assert all(a["action"] != "normal" for a in anomalies)


def test_activityanalyzer_detect_peak_hours_basic(analyzer):
    """Test _detect_peak_hours identifies peak hours above threshold"""
    base = datetime(2023, 1, 1, 0, 0, 0)
    activities = []
    # 5 events at 09:00 and 5 at other times (total 10; 09:00 has 50%)
    for i in range(5):
        activities.append({"action": "x", "timestamp": (base.replace(hour=9) + timedelta(minutes=i)).isoformat()})
    for i in range(5):
        activities.append({"action": "y", "timestamp": (base.replace(hour=12) + timedelta(minutes=i)).isoformat()})
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert isinstance(p, ActivityPattern)
    assert p.pattern_type == "peak_hours"
    assert "09:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when timestamps are invalid"""
    activities = [{"action": "x", "timestamp": "bad"}, {"action": "y", "timestamp": None}]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_common(analyzer):
    """Test _detect_action_sequences detects common sequences occurring at least twice"""
    acts = [
        {"action": "A", "timestamp": "2023-01-01T00:00:00"},
        {"action": "B", "timestamp": "2023-01-01T00:01:00"},
        {"action": "C", "timestamp": "2023-01-01T00:02:00"},
        {"action": "A", "timestamp": "2023-01-01T00:03:00"},
        {"action": "B", "timestamp": "2023-01-01T00:04:00"},
        {"action": "C", "timestamp": "2023-01-01T00:05:00"},
    ]
    patterns = analyzer._detect_action_sequences(acts)
    assert len(patterns) >= 1
    descs = [p.description for p in patterns]
    assert any("A → B → C" in d and "occurred 2 times" in d for d in descs)
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_insufficient(analyzer):
    """Test _detect_action_sequences returns empty when insufficient activities"""
    acts = [{"action": "A"}, {"action": "B"}]
    patterns = analyzer._detect_action_sequences(acts)
    assert patterns == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer):
    """Test _detect_regularity identifies highly regular patterns"""
    base = datetime(2023, 1, 1, 0, 0, 0)
    acts = [{"action": "x", "timestamp": (base + timedelta(minutes=60 * i)).isoformat()} for i in range(6)]
    patterns = analyzer._detect_regularity(acts)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV: 0.00" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular_or_insufficient(analyzer):
    """Test _detect_regularity returns empty when patterns are irregular or insufficient timestamps"""
    # Insufficient
    acts_insufficient = [{"action": "x", "timestamp": "2023-01-01T00:00:00"} for _ in range(4)]
    assert analyzer._detect_regularity(acts_insufficient) == []

    # Irregular: varying intervals to yield high CV
    base = datetime(2023, 1, 1, 0, 0, 0)
    times = [base, base + timedelta(minutes=1), base + timedelta(minutes=3),
             base + timedelta(minutes=6), base + timedelta(minutes=10)]
    acts_irregular = [{"action": "x", "timestamp": t.isoformat()} for t in times]
    assert analyzer._detect_regularity(acts_irregular) == []