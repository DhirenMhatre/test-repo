import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for timestamp generation."""
    return datetime(2023, 1, 1, 9, 0, 0)


def test_activitypattern_init_and_to_dict_basic():
    """Test ActivityPattern initialization and to_dict output."""
    ap = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.9)
    assert ap.pattern_type == "peak_hours"
    assert ap.description == "desc"
    assert ap.confidence == 0.9

    d = ap.to_dict()
    assert d == {"pattern_type": "peak_hours", "description": "desc", "confidence": 0.9}


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_analyze_patterns_orchestrates_calls(analyzer):
    """Test analyze_patterns orchestrates by calling sub-detectors and combining results."""
    activities = [
        {"action": "a", "timestamp": datetime(2023, 1, 1, 9)},
        {"action": "b", "timestamp": datetime(2023, 1, 1, 10)},
    ]
    peak_pattern = [ActivityPattern("peak_hours", "peak", 0.85)]
    seq_pattern = [ActivityPattern("action_sequence", "seq", 0.75)]
    reg_pattern = [ActivityPattern("regularity", "reg", 0.9)]

    with patch.object(analyzer, "_detect_peak_hours", return_value=peak_pattern) as m_peak, \
         patch.object(analyzer, "_detect_action_sequences", return_value=seq_pattern) as m_seq, \
         patch.object(analyzer, "_detect_regularity", return_value=reg_pattern) as m_reg:
        result = analyzer.analyze_patterns(activities)

        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)

        # Verify combined order
        assert [p.to_dict() for p in result] == [p.to_dict() for p in peak_pattern + seq_pattern + reg_pattern]


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for empty activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_empty_returns_zero(analyzer):
    """Test get_user_score returns 0.0 for empty activities list."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_valid_data(analyzer, base_time):
    """Test get_user_score computes expected score with valid timestamps."""
    # Create 10 actions from day 0 to day 4 (inclusive) using first and last timestamps for days_active=4
    activities = []
    # First timestamp
    activities.append({"action": "A", "timestamp": base_time})
    # 8 middle actions on day 2
    middle_time = base_time + timedelta(days=2)
    actions_middle = ["B", "C", "D", "E", "F", "A", "B", "C"]
    for act in actions_middle:
        activities.append({"action": act, "timestamp": middle_time})
    # Last timestamp on day 4
    activities.append({"action": "G", "timestamp": base_time + timedelta(days=4)})

    # total_actions = 10
    # unique_actions = A,B,C,D,E,F,G = 7 unique
    # first_ts=day0, last_ts=day4, days_active=4
    # actions_per_day = 10/4 = 2.5
    # diversity_score = 7/10 = 0.7
    # frequency_score = min(2.5/10,1)=0.25
    # volume_score = min(10/100,1)=0.1
    # final = (0.7*0.3 + 0.25*0.4 + 0.1*0.3)*100 = (0.21 + 0.10 + 0.03)*100 = 34.0
    expected = 34.0
    score = analyzer.get_user_score(activities)
    assert score == expected


def test_activityanalyzer_get_user_score_with_unparseable_timestamps_uses_total_actions(analyzer):
    """Test get_user_score when timestamps cannot be parsed falls back to total_actions frequency."""
    activities = [{"action": "A", "timestamp": "invalid"} for _ in range(5)]
    activities += [{"action": "B", "timestamp": "invalid"} for _ in range(5)]
    # total_actions=10
    # unique_actions=2 => diversity=0.2
    # actions_per_day defaults to total_actions=10 => frequency_score=1.0
    # volume_score=0.1
    # final = (0.2*0.3 + 1.0*0.4 + 0.1*0.3)*100 = (0.06+0.4+0.03)*100 = 49.0
    assert analyzer.get_user_score(activities) == 49.0


def test_activityanalyzer_detect_anomalies_returns_empty_when_insufficient_data(analyzer, base_time):
    """Test detect_anomalies returns empty list when not enough activities."""
    activities = [{"action": "A", "timestamp": base_time + timedelta(seconds=i*10)} for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_flags_outlier_interval(analyzer, base_time):
    """Test detect_anomalies flags an interval with z-score larger than threshold."""
    # Build 12 timestamps for one action with 10 intervals of 10s and one outlier interval.
    activities = []
    t = base_time
    activities.append({"action": "click", "timestamp": t})
    # 10 small intervals
    for _ in range(10):
        t = t + timedelta(seconds=10)
        activities.append({"action": "click", "timestamp": t})
    # one large interval outlier
    t = t + timedelta(seconds=300)
    activities.append({"action": "click", "timestamp": t})

    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "click"
    assert anomaly["z_score"] > analyzer.anomaly_threshold
    assert "Unusual interval" in anomaly["reason"]
    # Validate timestamp string format
    assert isinstance(anomaly["timestamp"], str)


def test_activityanalyzer_detect_anomalies_handles_mixed_valid_invalid_timestamps(analyzer, base_time):
    """Test detect_anomalies safely ignores invalid timestamps and does not raise."""
    activities = [
        {"action": "view", "timestamp": base_time},
        {"action": "view", "timestamp": "invalid"},
        {"action": "view", "timestamp": base_time + timedelta(seconds=10)},
        {"action": "view", "timestamp": "2023-13-01T00:00:00"},  # invalid month
        {"action": "view", "timestamp": base_time + timedelta(seconds=20)},
        {"action": "edit", "timestamp": base_time + timedelta(seconds=5)},
    ]
    # Only two valid timestamps for "view" -> less than 3 => skipped
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_equal_intervals_no_anomaly(analyzer, base_time):
    """Test detect_anomalies does not flag when intervals are equal (std_dev=0)."""
    activities = []
    t = base_time
    # 6 timestamps -> 5 equal intervals
    for _ in range(6):
        activities.append({"action": "save", "timestamp": t})
        t = t + timedelta(seconds=60)
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_peak_hours_identifies_hours(analyzer):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    # 10 activities: 3 at 9:00, 3 at 10:00, 2 at 11:00, 1 at 12:00, 1 invalid
    acts = []
    for _ in range(3):
        acts.append({"action": "a", "timestamp": datetime(2023, 1, 1, 9, 15, 0)})
    for _ in range(3):
        acts.append({"action": "b", "timestamp": datetime(2023, 1, 1, 10, 30, 0)})
    for _ in range(2):
        acts.append({"action": "c", "timestamp": datetime(2023, 1, 1, 11, 0, 0)})
    acts.append({"action": "d", "timestamp": datetime(2023, 1, 1, 12, 0, 0)})
    acts.append({"action": "e", "timestamp": "invalid"})

    patterns = analyzer._detect_peak_hours(acts)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert p.confidence == 0.85
    assert "09:00" in p.description and "10:00" in p.description
    assert "11:00" not in p.description  # equals threshold 0.2 -> should not include


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps_returns_empty(analyzer):
    """Test _detect_peak_hours returns empty when no valid timestamps."""
    acts = [{"action": "a", "timestamp": "not a date"} for _ in range(5)]
    assert analyzer._detect_peak_hours(acts) == []


def test_activityanalyzer_detect_action_sequences_finds_common_sequences(analyzer):
    """Test _detect_action_sequences identifies common 3-step sequences."""
    actions = ["A", "B", "C", "D", "A", "B", "C"]
    acts = [{"action": a, "timestamp": datetime(2023, 1, 1) + timedelta(seconds=i)} for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(acts)
    assert any(p.pattern_type == "action_sequence" for p in patterns)
    # Expect "A → B → C" occurred twice
    descriptions = [p.description for p in patterns]
    assert any("A → B → C" in d and "occurred 2 times" in d for d in descriptions)


def test_activityanalyzer_detect_action_sequences_short_list_returns_empty(analyzer):
    """Test _detect_action_sequences returns empty for fewer than 3 activities."""
    acts = [{"action": "A", "timestamp": datetime(2023, 1, 1)},
            {"action": "B", "timestamp": datetime(2023, 1, 1, 0, 0, 1)}]
    assert analyzer._detect_action_sequences(acts) == []


def test_activityanalyzer_detect_regularity_detects_regular_pattern(analyzer, base_time):
    """Test _detect_regularity identifies highly regular activity (low CV)."""
    acts = []
    t = base_time
    for _ in range(6):
        acts.append({"action": "ping", "timestamp": t})
        t = t + timedelta(minutes=10)
    patterns = analyzer._detect_regularity(acts)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert p.confidence == 0.9
    assert "Highly regular activity pattern" in p.description


def test_activityanalyzer_detect_regularity_irregular_returns_empty(analyzer, base_time):
    """Test _detect_regularity returns empty when intervals are irregular (high CV)."""
    times = [
        base_time,
        base_time + timedelta(minutes=1),
        base_time + timedelta(minutes=5),
        base_time + timedelta(minutes=6),
        base_time + timedelta(minutes=20),
        base_time + timedelta(minutes=21),
    ]
    acts = [{"action": "x", "timestamp": t} for t in times]
    assert analyzer._detect_regularity(acts) == []


def test_activityanalyzer_parse_timestamp_with_datetime_object(analyzer, base_time):
    """Test _parse_timestamp returns the same datetime object if already a datetime."""
    dt = base_time
    parsed = analyzer._parse_timestamp(dt)
    assert parsed is dt
    assert parsed == dt


def test_activityanalyzer_parse_timestamp_with_iso_string_and_z(analyzer):
    """Test _parse_timestamp parses ISO format string with Z timezone."""
    ts = "2023-01-01T12:30:00Z"
    parsed = analyzer._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is not None
    # isoformat should end with +00:00 if we serialize it back
    assert parsed.isoformat().endswith("+00:00")


def test_activityanalyzer_parse_timestamp_with_invalid_string_returns_none(analyzer):
    """Test _parse_timestamp returns None for invalid timestamp string."""
    assert analyzer._parse_timestamp("not-a-timestamp") is None


def test_activityanalyzer_parse_timestamp_handles_fromisoformat_exception(analyzer):
    """Test _parse_timestamp gracefully handles exceptions from datetime.fromisoformat."""
    # Patch the fromisoformat method on the datetime class used in the module
    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=ValueError):
        assert analyzer._parse_timestamp("2023-01-01T00:00:00") is None

    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=AttributeError):
        assert analyzer._parse_timestamp("2023-01-01T00:00:00") is None