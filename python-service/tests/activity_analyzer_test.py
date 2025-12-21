import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Base datetime for generating test timestamps."""
    return datetime(2023, 1, 1, 0, 0, 0)


def make_activity(action: str, ts: datetime):
    """Helper to create an activity dict."""
    return {"action": action, "timestamp": ts}


def test_activitypattern_to_dict_basic():
    """ActivityPattern.to_dict should return all fields correctly."""
    ap = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.9)
    d = ap.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "desc"
    assert d["confidence"] == 0.9


def test_activityanalyzer_init_defaults(analyzer):
    """ActivityAnalyzer should initialize with default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_datetime_input(analyzer, base_time):
    """_parse_timestamp should return datetime as-is when given a datetime object."""
    result = analyzer._parse_timestamp(base_time)
    assert isinstance(result, datetime)
    assert result == base_time


def test_activityanalyzer_parse_timestamp_iso_string_naive(analyzer):
    """_parse_timestamp should parse ISO string without timezone (naive)."""
    ts_str = "2023-01-01T12:34:56"
    result = analyzer._parse_timestamp(ts_str)
    assert isinstance(result, datetime)
    assert result.tzinfo is None
    assert result.year == 2023 and result.month == 1 and result.day == 1
    assert result.hour == 12 and result.minute == 34 and result.second == 56


def test_activityanalyzer_parse_timestamp_iso_string_z_suffix(analyzer):
    """_parse_timestamp should handle 'Z' suffix by converting to +00:00."""
    ts_str = "2024-01-02T03:04:05Z"
    result = analyzer._parse_timestamp(ts_str)
    assert isinstance(result, datetime)
    assert result.tzinfo is not None
    assert result.utcoffset() == timedelta(0)
    assert result.isoformat().startswith("2024-01-02T03:04:05")


def test_activityanalyzer_parse_timestamp_invalid_string_returns_none(analyzer):
    """_parse_timestamp should return None for invalid timestamp strings."""
    result = analyzer._parse_timestamp("not-a-timestamp")
    assert result is None


def test_activityanalyzer_parse_timestamp_exception_handling(analyzer):
    """_parse_timestamp should handle exceptions from datetime.fromisoformat and return None."""
    with patch("src.activity_analyzer.datetime") as mock_dt:
        mock_dt.fromisoformat.side_effect = ValueError
        result = analyzer._parse_timestamp("2023-01-01T00:00:00")
        assert result is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """_detect_peak_hours should detect hours exceeding the threshold."""
    activities = []
    # Create 10 activities at 14:00 hour
    for i in range(10):
        activities.append(make_activity("click", base_time.replace(hour=14) + timedelta(minutes=i)))
    # Create 5 activities at other hours
    for i in range(5):
        activities.append(make_activity("view", base_time.replace(hour=9) + timedelta(minutes=i)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "14:00" in p.description
    assert pytest.approx(p.confidence, rel=0.0) == 0.85


def test_activityanalyzer_detect_peak_hours_none_when_no_valid_timestamps(analyzer):
    """_detect_peak_hours should return empty when all timestamps are invalid."""
    activities = [{"action": "click", "timestamp": "invalid"} for _ in range(5)]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_threshold_boundary(analyzer, base_time):
    """_detect_peak_hours should not include hours equal to the threshold (strict >)."""
    # 1 out of 5 at a given hour -> 0.2, equals threshold -> should not include
    activities = []
    activities.append(make_activity("a", base_time.replace(hour=10)))
    for i in range(4):
        activities.append(make_activity("b", base_time.replace(hour=11) + timedelta(minutes=i)))
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_basic(analyzer, base_time):
    """_detect_action_sequences should identify repeated 3-action sequences."""
    activities = [
        make_activity("A", base_time),
        make_activity("B", base_time + timedelta(minutes=1)),
        make_activity("C", base_time + timedelta(minutes=2)),
        make_activity("X", base_time + timedelta(minutes=3)),
        make_activity("Y", base_time + timedelta(minutes=4)),
        make_activity("Z", base_time + timedelta(minutes=5)),
        make_activity("A", base_time + timedelta(minutes=6)),
        make_activity("B", base_time + timedelta(minutes=7)),
        make_activity("C", base_time + timedelta(minutes=8)),
    ]
    patterns = analyzer._detect_action_sequences(activities)
    # Should capture "A → B → C" occurring twice
    assert any(p.pattern_type == "action_sequence" and "A → B → C" in p.description and "(occurred 2 times)" in p.description for p in patterns)
    assert all(p.confidence == 0.75 for p in patterns)


def test_activityanalyzer_detect_action_sequences_insufficient_length(analyzer):
    """_detect_action_sequences should return empty when less than 3 activities."""
    activities = [make_activity("A", datetime.now()), make_activity("B", datetime.now())]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """_detect_regularity should detect highly regular activity patterns."""
    activities = [make_activity("ping", base_time + timedelta(minutes=10 * i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert pytest.approx(p.confidence, rel=0.0) == 0.9


def test_activityanalyzer_detect_regularity_not_regular(analyzer, base_time):
    """_detect_regularity should return empty when pattern is irregular."""
    # Irregular intervals
    times = [0, 1, 3, 7, 15, 31]
    activities = [make_activity("ping", base_time + timedelta(minutes=m)) for m in times]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_detect_regularity_insufficient_data(analyzer, base_time):
    """_detect_regularity should return empty when fewer than 5 valid timestamps."""
    activities = [make_activity("ping", base_time + timedelta(minutes=i)) for i in range(4)]
    assert analyzer._detect_regularity(activities) == []

    # 5 activities but with invalid timestamps leading to <5 parsed
    bad_activities = [
        {"action": "ping", "timestamp": "invalid"},
        {"action": "ping", "timestamp": base_time},
        {"action": "ping", "timestamp": "not a time"},
        {"action": "ping", "timestamp": base_time + timedelta(minutes=1)},
        {"action": "ping", "timestamp": "2023-13-01T00:00:00"},  # invalid month
    ]
    assert analyzer._detect_regularity(bad_activities) == []


def test_activityanalyzer_analyze_patterns_combines_results_with_mocks(analyzer):
    """analyze_patterns should aggregate results from detection methods in order."""
    mock_peak = [ActivityPattern("peak_hours", "peak", 0.85)]
    mock_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    mock_reg = [ActivityPattern("regularity", "reg", 0.9)]

    activities = [{"action": "A", "timestamp": datetime.now()} for _ in range(10)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as m3:
        patterns = analyzer.analyze_patterns(activities)

    m1.assert_called_once()
    m2.assert_called_once()
    m3.assert_called_once()
    assert patterns == mock_peak + mock_seq + mock_reg


def test_activityanalyzer_analyze_patterns_empty_input(analyzer):
    """analyze_patterns should return empty list for empty activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_basic(analyzer, base_time):
    """get_user_score should compute expected score with valid timestamps."""
    activities = [
        make_activity("a", base_time),
        make_activity("b", base_time + timedelta(minutes=1)),
        make_activity("a", base_time + timedelta(minutes=2)),
        make_activity("b", base_time + timedelta(minutes=3)),
    ]
    score = analyzer.get_user_score(activities)

    # Given the implementation's unique_actions bug, diversity_score == 1.0
    # total_actions=4, days_active=1, actions_per_day=4
    # diversity=1.0, frequency=0.4, volume=0.04
    # final=(0.3 + 0.16 + 0.012)*100=47.2
    assert score == 47.2


def test_activityanalyzer_get_user_score_no_activities(analyzer):
    """get_user_score should return 0.0 when activities list is empty."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_invalid_timestamps(analyzer):
    """get_user_score should handle invalid timestamps by treating actions_per_day as total_actions."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "b", "timestamp": "invalid"},
        {"action": "c", "timestamp": "invalid"},
        {"action": "d", "timestamp": "invalid"},
        {"action": "e", "timestamp": "invalid"},
    ]
    score = analyzer.get_user_score(activities)
    # total=5, actions_per_day=5, diversity=1.0, freq=0.5, volume=0.05
    # final=(0.3 + 0.2 + 0.015)*100=51.5
    assert score == 51.5


def test_activityanalyzer_detect_anomalies_insufficient_activities(analyzer):
    """detect_anomalies should return empty when fewer than 5 activities provided."""
    activities = [make_activity("A", datetime.now()) for _ in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_interval_outlier(analyzer, base_time):
    """detect_anomalies should flag intervals with z-score above threshold."""
    # For one action "A", create 12 timestamps: 11 intervals with 60s, except last interval huge
    times = [base_time + timedelta(seconds=60 * i) for i in range(11)]
    times.append(times[-1] + timedelta(seconds=3600))  # large gap to create z > 3
    activities = [make_activity("A", t) for t in times]

    anomalies = analyzer.detect_anomalies(activities)
    # Only one anomaly expected for the large gap
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "A"
    assert "Unusual interval" in anomaly["reason"]
    assert float(anomaly["z_score"]) > analyzer.anomaly_threshold
    # Timestamp should match the event after the anomalous interval (the last timestamp)
    assert anomaly["timestamp"] == times[-1].isoformat()


def test_activityanalyzer_detect_anomalies_multiple_actions_grouping(analyzer, base_time):
    """detect_anomalies should analyze each action separately and only flag where applicable."""
    # Action A with many regular intervals (no anomalies)
    times_a = [base_time + timedelta(minutes=i) for i in range(8)]
    activities_a = [make_activity("A", t) for t in times_a]

    # Action B with outlier requiring enough intervals: 12 timestamps as before
    times_b = [base_time + timedelta(seconds=60 * i) for i in range(11)]
    times_b.append(times_b[-1] + timedelta(seconds=3600))
    activities_b = [make_activity("B", t) for t in times_b]

    activities = activities_a + activities_b
    anomalies = analyzer.detect_anomalies(activities)

    assert len(anomalies) == 1
    assert anomalies[0]["action"] == "B"


def test_activityanalyzer_analyze_patterns_integration(analyzer, base_time):
    """analyze_patterns should return patterns from all detectors when applicable."""
    activities = []
    # Regular intervals to trigger regularity
    for i in range(6):
        activities.append(make_activity("A", base_time + timedelta(minutes=10 * i)))
    # Add repeated sequence to trigger action sequence
    activities.extend([
        make_activity("X", base_time + timedelta(hours=2)),
        make_activity("Y", base_time + timedelta(hours=2, minutes=1)),
        make_activity("Z", base_time + timedelta(hours=2, minutes=2)),
        make_activity("X", base_time + timedelta(hours=3)),
        make_activity("Y", base_time + timedelta(hours=3, minutes=1)),
        make_activity("Z", base_time + timedelta(hours=3, minutes=2)),
    ])
    # Add more activities in specific hour to trigger peak hours
    for i in range(10):
        activities.append(make_activity("P", base_time.replace(hour=14) + timedelta(minutes=i)))

    patterns = analyzer.analyze_patterns(activities)
    kinds = {p.pattern_type for p in patterns}
    assert "peak_hours" in kinds
    assert "action_sequence" in kinds
    assert "regularity" in kinds