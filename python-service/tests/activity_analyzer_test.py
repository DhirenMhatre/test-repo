import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide an ActivityAnalyzer instance."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing test timestamps."""
    return datetime(2023, 1, 1, 0, 0, 0)


def mk_ts(dt: datetime) -> str:
    """Helper: return ISO timestamp string."""
    return dt.isoformat()


def test_activitypattern_to_dict_basic():
    """Test ActivityPattern.to_dict returns correct dictionary representation."""
    ap = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.85)
    d = ap.to_dict()
    assert d == {"pattern_type": "peak_hours", "description": "desc", "confidence": 0.85}


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_analyze_patterns_calls_helpers_combines(analyzer):
    """Test analyze_patterns calls helper detectors and combines their results."""
    activities = [
        {"action": "a", "timestamp": mk_ts(datetime(2023, 1, 1, 9, 0, 0))},
        {"action": "b", "timestamp": mk_ts(datetime(2023, 1, 1, 10, 0, 0))},
    ]

    peak_ret = [ActivityPattern("peak_hours", "peak", 0.9)]
    seq_ret = [ActivityPattern("action_sequence", "seq1", 0.7), ActivityPattern("action_sequence", "seq2", 0.7)]
    reg_ret = [ActivityPattern("regularity", "regular", 0.8)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=peak_ret) as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=seq_ret) as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=reg_ret) as mock_reg:

        patterns = analyzer.analyze_patterns(activities)

        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)

        assert patterns == peak_ret + seq_ret + reg_ret
        assert len(patterns) == 1 + 2 + 1


def test_activityanalyzer_analyze_patterns_empty_does_not_call_helpers(analyzer):
    """Test analyze_patterns returns empty and does not call helpers when no activities."""
    with patch.object(ActivityAnalyzer, "_detect_peak_hours") as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences") as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity") as mock_reg:

        patterns = analyzer.analyze_patterns([])

        assert patterns == []
        mock_peak.assert_not_called()
        mock_seq.assert_not_called()
        mock_reg.assert_not_called()


def test_activityanalyzer_get_user_score_empty_returns_zero(analyzer):
    """Test get_user_score returns 0.0 when no activities are provided."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_valid_data(analyzer, base_time):
    """Test get_user_score with valid timestamps and action diversity."""
    activities = []
    # 10 actions within the same day, 5 unique actions
    actions = ["A", "B", "A", "C", "A", "D", "E", "A", "B", "C"]
    for i, a in enumerate(actions):
        activities.append({"action": a, "timestamp": mk_ts(base_time + timedelta(minutes=i))})

    score = analyzer.get_user_score(activities)
    # diversity=0.5, frequency=1.0 (10/day), volume=0.1 (10/100)
    # final = (0.5*0.3 + 1.0*0.4 + 0.1*0.3)*100 = (0.15 + 0.4 + 0.03)*100 = 58.0
    assert score == 58.0


def test_activityanalyzer_get_user_score_invalid_timestamps(analyzer):
    """Test get_user_score when timestamps are invalid strings."""
    activities = [
        {"action": "A", "timestamp": "not-a-date"},
        {"action": "B", "timestamp": "still-bad"},
        {"action": "A", "timestamp": "invalid"},
    ]
    score = analyzer.get_user_score(activities)
    # total=3, unique=2 -> diversity=2/3=0.666...
    # frequency=3/10=0.3 (since actions_per_day=total_actions when timestamps invalid)
    # volume=3/100=0.03
    # final = (0.6667*0.3 + 0.3*0.4 + 0.03*0.3)*100 = (0.2 + 0.12 + 0.009)*100 = 32.9
    assert score == 32.9


def test_activityanalyzer_get_user_score_spanning_days(analyzer, base_time):
    """Test get_user_score calculates actions per day across multiple days."""
    activities = []
    # 9 actions across 3 days
    for i in range(9):
        ts = base_time + timedelta(hours=i * 24 // 3)  # spread evenly across 3 days
        activities.append({"action": "A" if i % 3 == 0 else ("B" if i % 3 == 1 else "C"), "timestamp": mk_ts(ts)})

    score = analyzer.get_user_score(activities)
    # total=9, unique=3 -> diversity=1/3
    # days_active = 3 -> actions_per_day=3 -> frequency=0.3
    # volume=0.09
    # final = ((1/3)*0.3 + 0.3*0.4 + 0.09*0.3)*100 = (0.1 + 0.12 + 0.027)*100 = 24.7
    assert score == 24.7


def test_activityanalyzer_detect_anomalies_insufficient_data_returns_empty(analyzer, base_time):
    """Test detect_anomalies returns empty when not enough activities."""
    activities = [{"action": "A", "timestamp": mk_ts(base_time + timedelta(seconds=i * 10))} for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_interval_spike(analyzer, base_time):
    """Test detect_anomalies flags a large unusual interval as anomaly."""
    # Lower threshold to make detection easier
    analyzer.anomaly_threshold = 1.5

    # Create 5 timestamps for the same action with intervals: 10, 10, 10, 1000 seconds
    times = [
        base_time,
        base_time + timedelta(seconds=10),
        base_time + timedelta(seconds=20),
        base_time + timedelta(seconds=30),
        base_time + timedelta(seconds=1030),
    ]
    activities = [{"action": "login", "timestamp": mk_ts(t)} for t in times]

    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "login"
    assert "Unusual interval" in anomaly["reason"]
    # Timestamp should correspond to the end of the anomalous interval (the 5th timestamp)
    assert anomaly["timestamp"] == times[-1].isoformat()
    assert anomaly["z_score"] > 1.5


def test_detect_peak_hours_identifies_hours_above_threshold(analyzer, base_time):
    """Test _detect_peak_hours identifies hours with counts above threshold."""
    activities = []
    # 10 activities total; hour 9 -> 3, hour 15 -> 3, other hours -> 4
    for i in range(3):
        activities.append({"action": "A", "timestamp": mk_ts(base_time.replace(hour=9) + timedelta(minutes=i))})
    for i in range(3):
        activities.append({"action": "B", "timestamp": mk_ts(base_time.replace(hour=15) + timedelta(minutes=i))})
    for i in range(4):
        activities.append({"action": "C", "timestamp": mk_ts(base_time.replace(hour=8) + timedelta(minutes=i))})

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "High activity during hours: 09:00, 15:00" in p.description
    assert p.confidence == 0.85


def test_detect_peak_hours_no_hour_above_threshold(analyzer, base_time):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold (>0.2)."""
    activities = []
    # 5 activities at 5 distinct hours -> each hour fraction = 0.2 -> not included
    for i, hour in enumerate([8, 9, 10, 11, 12]):
        activities.append({"action": "X", "timestamp": mk_ts(base_time.replace(hour=hour) + timedelta(minutes=i))})

    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_detect_action_sequences_counts_top_sequences(analyzer, base_time):
    """Test _detect_action_sequences identifies repeated triple sequences."""
    actions = ["A", "B", "C", "D", "A", "B", "C", "E"]
    activities = [{"action": a, "timestamp": mk_ts(base_time + timedelta(minutes=i))} for i, a in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    # Only "A -> B -> C" occurs twice
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "Common sequence: A → B → C (occurred 2 times)" in p.description
    assert p.confidence == 0.75


def test_detect_action_sequences_less_than_three_returns_empty(analyzer, base_time):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [{"action": "A", "timestamp": mk_ts(base_time)}, {"action": "B", "timestamp": mk_ts(base_time)}]
    assert analyzer._detect_action_sequences(activities) == []


def test_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity flags highly regular activity with low CV."""
    # 6 activities exactly 60 minutes apart -> constant intervals
    activities = [{"action": "A", "timestamp": mk_ts(base_time + timedelta(minutes=60 * i))} for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert p.confidence == 0.9


def test_detect_regularity_irregular_returns_empty(analyzer, base_time):
    """Test _detect_regularity returns empty for irregular intervals."""
    # Irregular intervals: 5 activities with varied gaps
    deltas = [0, 1, 4, 10, 25, 40]  # minutes
    activities = [{"action": "A", "timestamp": mk_ts(base_time + timedelta(minutes=m))} for m in deltas]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_parse_timestamp_handles_datetime(analyzer, base_time):
    """Test _parse_timestamp returns the same datetime when input is datetime."""
    dt = base_time
    parsed = analyzer._parse_timestamp(dt)
    assert isinstance(parsed, datetime)
    assert parsed == dt


def test_parse_timestamp_handles_iso_string_with_z(analyzer):
    """Test _parse_timestamp parses ISO 8601 string with 'Z' suffix."""
    ts = "2023-02-01T12:34:56Z"
    parsed = analyzer._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2023
    assert parsed.month == 2
    assert parsed.day == 1
    assert parsed.hour == 12
    assert parsed.minute == 34
    assert parsed.second == 56


def test_parse_timestamp_handles_iso_string_without_z(analyzer):
    """Test _parse_timestamp parses ISO 8601 string without 'Z' suffix."""
    ts = "2023-02-01T12:34:56"
    parsed = analyzer._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2023
    assert parsed.hour == 12


def test_parse_timestamp_invalid_string_returns_none(analyzer):
    """Test _parse_timestamp returns None for invalid string input."""
    assert analyzer._parse_timestamp("not a timestamp") is None


def test_parse_timestamp_unsupported_type_returns_none(analyzer):
    """Test _parse_timestamp returns None for unsupported types."""
    assert analyzer._parse_timestamp(1672531200) is None  # int timestamp not supported in this implementation