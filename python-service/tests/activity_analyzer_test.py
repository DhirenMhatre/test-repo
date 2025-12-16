import pytest
from unittest.mock import patch
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing timestamps."""
    return datetime(2023, 1, 1, 9, 0, 0)


def test_activitypattern_initialization_and_to_dict():
    """Test ActivityPattern initialization and dictionary serialization."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="High activity", confidence=0.85)
    d = pattern.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "High activity"
    assert d["confidence"] == 0.85


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default thresholds are set."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_datetime_input(analyzer, base_time):
    """Test _parse_timestamp returns same datetime when given a datetime object."""
    assert analyzer._parse_timestamp(base_time) == base_time


def test_activityanalyzer_parse_timestamp_iso_string_with_z(analyzer):
    """Test _parse_timestamp handles ISO string with Z (UTC) suffix."""
    ts = "2023-01-01T10:00:00Z"
    parsed = analyzer._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    # Ensure it parsed something reasonable: isoformat should end with +00:00
    assert parsed.tzinfo is not None
    assert parsed.isoformat().endswith("+00:00")


def test_activityanalyzer_parse_timestamp_iso_string_without_z(analyzer):
    """Test _parse_timestamp handles ISO string without Z suffix."""
    ts = "2023-01-01T10:00:00"
    parsed = analyzer._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is None


def test_activityanalyzer_parse_timestamp_invalid_string(analyzer):
    """Test _parse_timestamp returns None for invalid string."""
    assert analyzer._parse_timestamp("not-a-valid-timestamp") is None


def test_activityanalyzer_parse_timestamp_exception_handling(analyzer):
    """Test _parse_timestamp handles exceptions from datetime.fromisoformat gracefully."""
    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=ValueError):
        assert analyzer._parse_timestamp("2023-01-01T10:00:00") is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours with activity above threshold and formats description."""
    activities = []
    # 8 activities at 09:xx, 2 at 10:xx, 2 at 11:xx -> total 12; hour 09 has 8/12 = 0.666.. (>0.2)
    for i in range(8):
        activities.append({"timestamp": base_time + timedelta(minutes=i), "action": "a"})
    for i in range(2):
        activities.append({"timestamp": base_time.replace(hour=10) + timedelta(minutes=i), "action": "b"})
    for i in range(2):
        activities.append({"timestamp": base_time.replace(hour=11) + timedelta(minutes=i), "action": "c"})

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "High activity during hours" in p.description
    # Ensure it includes 09:00 and sorted formatting
    assert "09:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_threshold_boundary(analyzer, base_time):
    """Test _detect_peak_hours does not include hours exactly at threshold (strictly greater required)."""
    # 5 activities in distinct hours -> each hour has 1/5 = 0.2 == threshold; no peak hours
    activities = [
        {"timestamp": base_time.replace(hour=h), "action": "a"} for h in range(5)
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when no valid timestamps are present."""
    activities = [{"timestamp": "invalid", "action": "x"} for _ in range(5)]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_common(analyzer, base_time):
    """Test _detect_action_sequences captures common sequences occurring at least twice."""
    actions = [
        "login", "view", "logout",  # seq 1
        "login", "view", "logout",  # seq 2
        "search", "view", "add_to_cart",
        "login", "view", "logout",  # seq 3
        "browse", "view", "logout",
    ]
    activities = [{"timestamp": base_time + timedelta(minutes=i), "action": a} for i, a in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    # At least one common "login → view → logout" with count >= 2
    assert any("Common sequence: login → view → logout" in p.description for p in patterns)
    assert all(p.pattern_type == "action_sequence" for p in patterns)
    assert all(p.confidence == 0.75 for p in patterns)


def test_activityanalyzer_detect_action_sequences_insufficient_length(analyzer):
    """Test _detect_action_sequences returns empty when fewer than 3 activities exist."""
    activities = [{"timestamp": datetime(2023, 1, 1, 0, 0), "action": "a"}]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity identifies highly regular intervals."""
    activities = []
    for i in range(6):
        activities.append({"timestamp": base_time + timedelta(seconds=60 * i), "action": "a"})
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty for irregular activity intervals."""
    intervals = [10, 200, 30, 500, 100, 700]  # irregular
    ts = base_time
    activities = []
    for inc in intervals:
        ts = ts + timedelta(seconds=inc)
        activities.append({"timestamp": ts, "action": "a"})
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_insufficient_valid_timestamps(analyzer):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps exist."""
    activities = [{"timestamp": "invalid", "action": "a"} for _ in range(6)]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_analyze_patterns_calls_and_aggregates(analyzer):
    """Test analyze_patterns aggregates patterns from internal detectors and calls them with activities."""
    activities = [{"timestamp": datetime(2023, 1, 1, 10, 0), "action": "a"} for _ in range(10)]
    mock_peak = [ActivityPattern("peak_hours", "desc peak", 0.9)]
    mock_seq = [ActivityPattern("action_sequence", "desc seq", 0.8)]
    mock_reg = [ActivityPattern("regularity", "desc reg", 0.7)]
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)
        assert patterns == mock_peak + mock_seq + mock_reg
        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)


def test_activityanalyzer_analyze_patterns_empty_input(analyzer):
    """Test analyze_patterns returns empty list for empty activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_same_day_high_frequency(analyzer, base_time):
    """Test get_user_score for same-day activities with mixed diversity and volume."""
    actions = ["A", "B", "C", "D", "E"] * 2  # 10 total, 5 unique
    activities = [{"timestamp": base_time + timedelta(minutes=i), "action": a} for i, a in enumerate(actions)]
    score = analyzer.get_user_score(activities)
    # diversity = 5/10=0.5, frequency=min(10/10,1)=1.0, volume=min(10/100,1)=0.1
    # final = (0.5*0.3 + 1.0*0.4 + 0.1*0.3) * 100 = 58.0
    assert score == 58.0


def test_activityanalyzer_get_user_score_no_timestamps(analyzer):
    """Test get_user_score when timestamps are missing; frequency uses total_actions."""
    activities = [{"action": f"a{i}"} for i in range(25)]
    score = analyzer.get_user_score(activities)
    # diversity = 25/25=1.0, frequency=min(25/10,1)=1.0, volume=min(25/100,1)=0.25
    # final = (1.0*0.3 + 1.0*0.4 + 0.25*0.3)*100 = 77.5
    assert score == 77.5


def test_activityanalyzer_detect_anomalies_insufficient_data(analyzer, base_time):
    """Test detect_anomalies returns empty when fewer than 5 activities exist."""
    activities = [{"timestamp": base_time + timedelta(minutes=i), "action": "click"} for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_no_variance_default_threshold(analyzer, base_time):
    """Test detect_anomalies returns empty when inter-arrival intervals have zero variance."""
    activities = [{"timestamp": base_time + timedelta(minutes=i), "action": "click"} for i in range(6)]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_flags_when_threshold_lower(analyzer, base_time):
    """Test detect_anomalies flags an outlier interval when anomaly threshold is lowered."""
    # Create 12 'click' events, with one large gap to create an outlier
    timestamps = []
    ts = base_time
    for i in range(6):
        timestamps.append(ts)
        ts = ts + timedelta(seconds=60)  # regular 1-minute intervals
    # Introduce a large gap
    ts = ts + timedelta(seconds=5000)
    timestamps.append(ts)
    # Continue with regular intervals
    for i in range(5):
        ts = ts + timedelta(seconds=60)
        timestamps.append(ts)

    activities = [{"timestamp": t, "action": "click"} for t in timestamps]
    analyzer.anomaly_threshold = 1.0  # lower threshold to ensure detection
    anomalies = analyzer.detect_anomalies(activities)
    # Expect at least one anomaly corresponding to the large gap; the timestamp should be the later time in that gap
    assert len(anomalies) >= 1
    anomaly_ts = anomalies[0]["timestamp"]
    # The anomaly timestamp should match the timestamp right after the large gap
    expected_ts = timestamps[6].isoformat()
    assert anomaly_ts == expected_ts
    assert anomalies[0]["action"] == "click"
    assert "Unusual interval" in anomalies[0]["reason"]