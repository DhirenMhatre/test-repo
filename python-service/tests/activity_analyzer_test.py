import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Create ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base UTC datetime for constructing timestamps"""
    return datetime(2023, 1, 1, 0, 0, 0, tzinfo=timezone.utc)


def make_activity(action: str, ts: datetime):
    """Helper to build an activity dict"""
    return {"action": action, "timestamp": ts}


def test_activitypattern_to_dict_basic():
    """ActivityPattern.to_dict should serialize to a correct dict"""
    p = ActivityPattern("peak_hours", "High activity during hours: 14:00", 0.85)
    d = p.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "High activity during hours: 14:00"
    assert d["confidence"] == 0.85


def test_activityanalyzer_init_defaults(analyzer):
    """ActivityAnalyzer should initialize with correct default thresholds"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_supports_datetime_and_iso_z(analyzer, base_time):
    """_parse_timestamp should accept datetime and ISO 8601 with Z"""
    # datetime instance
    dt = base_time.replace(tzinfo=None)
    parsed_dt = analyzer._parse_timestamp(dt)
    assert parsed_dt == dt

    # ISO string with Z
    iso_z = "2023-01-01T12:30:00Z"
    parsed_iso = analyzer._parse_timestamp(iso_z)
    assert isinstance(parsed_iso, datetime)
    assert parsed_iso.tzinfo is not None
    assert parsed_iso.isoformat().endswith("+00:00")

    # ISO string with offset
    iso_offset = "2023-01-01T12:30:00+00:00"
    parsed_iso_offset = analyzer._parse_timestamp(iso_offset)
    assert isinstance(parsed_iso_offset, datetime)
    assert parsed_iso_offset.tzinfo is not None


def test_activityanalyzer_parse_timestamp_invalid_returns_none_no_raise(analyzer):
    """_parse_timestamp should return None for invalid input without raising"""
    invalid = "not-a-date"
    result = analyzer._parse_timestamp(invalid)
    assert result is None


def test_detect_peak_hours_identifies_peak(analyzer, base_time):
    """_detect_peak_hours should detect hours exceeding the threshold"""
    activities = []
    # 3 activities at 14:00
    for i in range(3):
        activities.append(make_activity("click", base_time.replace(hour=14) + timedelta(minutes=i)))
    # 7 activities spread across other hours (each 1 count)
    for h in [0, 1, 2, 3, 4, 5, 6]:
        activities.append(make_activity("view", base_time.replace(hour=h)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "14:00" in p.description
    assert p.confidence == 0.85


def test_detect_peak_hours_multiple_peaks_sorted(analyzer, base_time):
    """_detect_peak_hours should list multiple peak hours sorted ascending"""
    activities = []
    # 5 at 08:00, 5 at 20:00, 10 total -> both 0.5 share > 0.2
    for i in range(5):
        activities.append(make_activity("a", base_time.replace(hour=8) + timedelta(minutes=i)))
    for i in range(5):
        activities.append(make_activity("b", base_time.replace(hour=20) + timedelta(minutes=i)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    desc = patterns[0].description
    assert "08:00" in desc and "20:00" in desc
    assert desc.index("08:00") < desc.index("20:00")


def test_detect_peak_hours_returns_empty_below_threshold_or_no_valid_timestamps(analyzer, base_time):
    """_detect_peak_hours should return empty when no hour exceeds threshold or timestamps invalid"""
    # Exactly 5 activities across 5 different hours -> each 0.2, not > threshold
    activities = [
        make_activity("a", base_time.replace(hour=h)) for h in [0, 1, 2, 3, 4]
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []

    # All timestamps invalid -> empty
    invalid_activities = [{"action": "x", "timestamp": "invalid"} for _ in range(5)]
    assert analyzer._detect_peak_hours(invalid_activities) == []


def test_detect_action_sequences_finds_common_sequences_top3(analyzer, base_time):
    """_detect_action_sequences should find frequent 3-action sequences"""
    actions = ["A", "B", "C", "D", "A", "B", "C", "E", "A", "B", "C"]
    activities = [
        make_activity(a, base_time + timedelta(minutes=i)) for i, a in enumerate(actions)
    ]

    patterns = analyzer._detect_action_sequences(activities)
    # Only the A->B->C sequence occurs >= 2 times (3 times)
    assert any(
        p.pattern_type == "action_sequence" and "A → B → C" in p.description and "(occurred 3 times)" in p.description
        for p in patterns
    )


def test_detect_action_sequences_returns_empty_when_less_than_3_activities(analyzer, base_time):
    """_detect_action_sequences should return empty if fewer than 3 activities"""
    activities = [
        make_activity("A", base_time),
        make_activity("B", base_time + timedelta(minutes=1)),
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_detect_regularity_detects_regular_pattern_low_cv(analyzer, base_time):
    """_detect_regularity should detect highly regular intervals (low coefficient of variation)"""
    activities = [
        make_activity("x", base_time + timedelta(minutes=30 * i)) for i in range(6)
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    assert patterns[0].pattern_type == "regularity"
    assert "CV:" in patterns[0].description


def test_detect_regularity_returns_empty_for_insufficient_or_irregular(analyzer, base_time):
    """_detect_regularity should return empty for insufficient data or irregular intervals"""
    # Insufficient (<5)
    activities_insufficient = [
        make_activity("x", base_time + timedelta(minutes=30 * i)) for i in range(4)
    ]
    assert analyzer._detect_regularity(activities_insufficient) == []

    # Irregular intervals -> high CV
    irregular_times = [0, 1, 11, 12, 22, 23]  # Alternating short/long gaps
    activities_irregular = [
        make_activity("x", base_time + timedelta(minutes=m)) for m in irregular_times
    ]
    assert analyzer._detect_regularity(activities_irregular) == []


def test_analyze_patterns_calls_detectors_and_combines_results(analyzer):
    """analyze_patterns should call private detectors and combine results"""
    activities = [{"action": "x", "timestamp": "2023-01-01T00:00:00Z"}]
    p1 = ActivityPattern("peak_hours", "desc1", 0.1)
    p2 = ActivityPattern("action_sequence", "desc2", 0.2)
    p3 = ActivityPattern("regularity", "desc3", 0.3)

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[p1]) as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[p2]) as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[p3]) as mock_reg:
        result = analyzer.analyze_patterns(activities)
        assert result == [p1, p2, p3]
        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)


def test_analyze_patterns_empty_input_returns_empty_list(analyzer):
    """analyze_patterns should return empty list for empty activities"""
    assert analyzer.analyze_patterns([]) == []


def test_get_user_score_computation_basic(analyzer, base_time):
    """get_user_score should compute expected score with timestamps spanning 2 days"""
    # Build 20 activities between Jan 1 00:00 and Jan 3 00:00 (2 days)
    actions = (["A"] * 5) + (["B"] * 5) + (["C"] * 5) + (["D"] * 5)
    activities = [
        make_activity(a, base_time + timedelta(hours=i)) for i, a in enumerate(actions)
    ]
    # Adjust last timestamp to be exactly 2 days after first
    activities[-1]["timestamp"] = activities[0]["timestamp"] + timedelta(days=2)

    score = analyzer.get_user_score(activities)
    # diversity = 4/20 = 0.2; frequency = (20/2)/10 = 1.0; volume = 20/100 = 0.2
    # final = (0.2*0.3 + 1.0*0.4 + 0.2*0.3) * 100 = 52.0
    assert score == 52.0


def test_get_user_score_no_timestamps_uses_total_actions_for_frequency(analyzer):
    """get_user_score should fall back to total_actions for frequency if timestamps are missing"""
    activities = [{"action": f"a{i}", "timestamp": "invalid"} for i in range(5)]
    score = analyzer.get_user_score(activities)
    # diversity=1.0, frequency=0.5, volume=0.05 -> (0.3 + 0.2 + 0.015)*100 = 51.5
    assert score == 51.5


def test_get_user_score_handles_empty(analyzer):
    """get_user_score should return 0.0 for empty activities"""
    assert analyzer.get_user_score([]) == 0.0


def test_detect_anomalies_identifies_unusual_interval_with_many_points(analyzer, base_time):
    """detect_anomalies should flag a large-interval outlier when enough intervals exist"""
    # Build 13 timestamps for the same action 'click' -> 12 intervals
    # 11 intervals of 60s, one interval of 6000s to create a strong outlier
    timestamps = [base_time]
    for i in range(1, 13):
        if i == 6:
            timestamps.append(timestamps[-1] + timedelta(seconds=6000))
        else:
            timestamps.append(timestamps[-1] + timedelta(seconds=60))

    activities = [make_activity("click", ts) for ts in timestamps]
    # Add a few other activities to exceed the global len(activities) >= 5 check
    activities += [make_activity("view", base_time + timedelta(hours=1 + i)) for i in range(3)]

    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) >= 1
    # The anomaly should be for 'click' action
    assert all(a["action"] == "click" for a in anomalies)
    # Ensure z_score meets threshold
    assert all(a["z_score"] > analyzer.anomaly_threshold for a in anomalies)


def test_detect_anomalies_requires_minimum_data(analyzer, base_time):
    """detect_anomalies should return empty for insufficient activities"""
    activities = [make_activity("click", base_time + timedelta(minutes=i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_detect_anomalies_no_anomaly_when_intervals_constant(analyzer, base_time):
    """detect_anomalies should return empty when intervals are constant (std_dev=0)"""
    timestamps = [base_time + timedelta(minutes=i) for i in range(6)]
    activities = [make_activity("click", ts) for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_analyze_patterns_handles_invalid_timestamps_gracefully(analyzer):
    """analyze_patterns should not raise when activities contain invalid timestamps"""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "b", "timestamp": None},
    ]
    # Should return combined patterns from detectors; since detectors will see no valid data, expect empty
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[]), \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[]), \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[]):
        patterns = analyzer.analyze_patterns(activities)
        assert patterns == []


def test_activitypattern_attributes(analyzer):
    """ActivityPattern attributes should be set correctly"""
    p = ActivityPattern("regularity", "desc", 0.9)
    assert p.pattern_type == "regularity"
    assert p.description == "desc"
    assert p.confidence == 0.9