import pytest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def test_ActivityPattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict output."""
    ap = ActivityPattern("test_type", "test description", 0.95)
    assert ap.pattern_type == "test_type"
    assert ap.description == "test description"
    assert ap.confidence == 0.95

    ap_dict = ap.to_dict()
    assert ap_dict == {
        "pattern_type": "test_type",
        "description": "test description",
        "confidence": 0.95,
    }


def test_ActivityAnalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer defaults on initialization."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_ActivityAnalyzer_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp with datetime, ISO string, Z suffix, and invalid inputs."""
    now = datetime(2023, 1, 1, 12, 34, 56)
    assert analyzer._parse_timestamp(now) == now

    iso_str = "2023-01-01T12:34:56"
    parsed = analyzer._parse_timestamp(iso_str)
    assert isinstance(parsed, datetime)
    assert parsed == datetime(2023, 1, 1, 12, 34, 56)

    iso_z = "2023-01-01T12:34:56Z"
    parsed_z = analyzer._parse_timestamp(iso_z)
    assert isinstance(parsed_z, datetime)
    assert parsed_z.tzinfo is not None
    assert parsed_z.isoformat().endswith("+00:00")

    invalid = "not-a-date"
    assert analyzer._parse_timestamp(invalid) is None


def test_ActivityAnalyzer_detect_peak_hours_threshold_and_output(analyzer):
    """Test _detect_peak_hours identifies hours above threshold and formats description."""
    base = datetime(2023, 1, 1, 9, 0, 0)
    activities = []

    # 3 at 09:xx
    for i in range(3):
        activities.append({"action": "a", "timestamp": base + timedelta(minutes=i)})

    # 3 at 10:xx
    for i in range(3):
        activities.append({"action": "b", "timestamp": base + timedelta(hours=1, minutes=i)})

    # 2 at 11:xx (exactly threshold 0.2 -> should NOT be included)
    for i in range(2):
        activities.append({"action": "c", "timestamp": base + timedelta(hours=2, minutes=i)})

    # 2 at 12:xx (exactly threshold 0.2 -> should NOT be included)
    for i in range(2):
        activities.append({"action": "d", "timestamp": base + timedelta(hours=3, minutes=i)})

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert p.confidence == 0.85
    assert "High activity during hours:" in p.description
    assert "09:00" in p.description and "10:00" in p.description
    assert "11:00" not in p.description and "12:00" not in p.description


def test_ActivityAnalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when timestamps are invalid."""
    activities = [{"action": "x", "timestamp": "invalid"} for _ in range(5)]
    assert analyzer._detect_peak_hours(activities) == []


def test_ActivityAnalyzer_detect_action_sequences_common_sequence(analyzer):
    """Test _detect_action_sequences finds a common 3-action sequence."""
    actions = [
        "login", "view", "click", "logout",
        "login", "view", "click", "share",
        "login", "view", "click",
    ]
    base = datetime(2023, 1, 1, 9, 0, 0)
    activities = [{"action": a, "timestamp": base + timedelta(seconds=i)} for i, a in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "Common sequence: login → view → click" in p.description
    assert "(occurred 3 times)" in p.description
    assert p.confidence == 0.75


def test_ActivityAnalyzer_detect_action_sequences_too_short(analyzer):
    """Test _detect_action_sequences returns empty when activities < 3."""
    base = datetime(2023, 1, 1, 9, 0, 0)
    activities = [
        {"action": "a", "timestamp": base},
        {"action": "b", "timestamp": base + timedelta(seconds=1)},
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_ActivityAnalyzer_detect_regularity_highly_regular(analyzer):
    """Test _detect_regularity identifies highly regular patterns."""
    base = datetime(2023, 1, 1, 9, 0, 0)
    activities = [
        {"action": "tick", "timestamp": base + timedelta(hours=i)} for i in range(6)
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern (CV: 0.00)" in p.description
    assert p.confidence == 0.9


def test_ActivityAnalyzer_detect_regularity_irregular(analyzer):
    """Test _detect_regularity returns empty for irregular intervals."""
    base = datetime(2023, 1, 1, 9, 0, 0)
    offsets = [0, 5, 15, 30, 55, 95]  # irregular minute gaps
    activities = [{"action": "tick", "timestamp": base + timedelta(minutes=m)} for m in offsets]
    assert analyzer._detect_regularity(activities) == []


def test_ActivityAnalyzer_analyze_patterns_aggregates_results(analyzer):
    """Test analyze_patterns aggregates results from internal detectors."""
    activities = [{"action": "a", "timestamp": datetime(2023, 1, 1, 9, 0, 0)} for _ in range(10)]
    mock_peak = [ActivityPattern("peak_hours", "peak desc", 0.8)]
    mock_seq = [ActivityPattern("action_sequence", "seq desc", 0.7)]
    mock_reg = []

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)
        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)

    assert len(patterns) == 2
    assert patterns[0].pattern_type == "peak_hours"
    assert patterns[1].pattern_type == "action_sequence"


def test_ActivityAnalyzer_analyze_patterns_no_activities_skips_detectors(analyzer):
    """Test analyze_patterns returns empty and does not call detectors when activities is empty."""
    activities = []
    with patch.object(ActivityAnalyzer, "_detect_peak_hours") as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences") as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity") as m_reg:
        patterns = analyzer.analyze_patterns(activities)
        m_peak.assert_not_called()
        m_seq.assert_not_called()
        m_reg.assert_not_called()
    assert patterns == []


def test_ActivityAnalyzer_get_user_score_basic_calculation(analyzer):
    """Test get_user_score with typical data and parsed timestamps."""
    base = datetime(2023, 1, 1, 0, 0, 0)
    # 10 actions across > 1 day, but .days between first and last equals 1, so actions_per_day = 10
    activities = []
    for i in range(10):
        activities.append({"action": "a" if i % 2 == 0 else "b", "timestamp": base + timedelta(hours=i)})
    # last activity at base + 9h -> days_active = 1
    score = analyzer.get_user_score(activities)
    # diversity_score becomes 1.0 due to implementation; frequency=1.0; volume=0.1
    assert score == 73.0


def test_ActivityAnalyzer_get_user_score_no_timestamps(analyzer):
    """Test get_user_score when timestamps are invalid leading to actions_per_day = total."""
    activities = [{"action": "x", "timestamp": "invalid"} for _ in range(5)]
    score = analyzer.get_user_score(activities)
    # diversity_score -> 1.0; frequency=0.5; volume=0.05
    assert score == 51.5


def test_ActivityAnalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities."""
    assert analyzer.get_user_score([]) == 0.0


def test_ActivityAnalyzer_detect_anomalies_insufficient(analyzer):
    """Test detect_anomalies returns empty when fewer than 5 activities."""
    base = datetime(2023, 1, 1, 0, 0, 0)
    acts = [{"action": "a", "timestamp": base + timedelta(seconds=i)} for i in range(4)]
    assert analyzer.detect_anomalies(acts) == []


def test_ActivityAnalyzer_detect_anomalies_outlier_interval_detected(analyzer):
    """Test detect_anomalies flags a large outlier interval using z-score threshold > 3.0."""
    base = datetime(2023, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
    # Build timestamps for one action with 11 intervals of 60s and one interval of 1200s at the end
    timestamps = [base]
    for _ in range(11):
        timestamps.append(timestamps[-1] + timedelta(seconds=60))
    timestamps.append(timestamps[-1] + timedelta(seconds=1200))  # outlier interval
    activities = [{"action": "ping", "timestamp": ts} for ts in timestamps]
    # Ensure there are at least 5 activities in total; add some other actions too
    activities.extend([
        {"action": "other", "timestamp": base + timedelta(days=1)},
        {"action": "other", "timestamp": base + timedelta(days=2)},
    ])

    anomalies = analyzer.detect_anomalies(activities)
    # Expect at least one anomaly for 'ping'
    assert any(a["action"] == "ping" for a in anomalies)
    # Find anomaly at the final timestamp
    ping_anoms = [a for a in anomalies if a["action"] == "ping"]
    assert any(a["timestamp"].endswith("+00:00") for a in ping_anoms)
    # z_score strictly greater than threshold (3.0)
    assert all(a["z_score"] > analyzer.anomaly_threshold for a in ping_anoms)


def test_ActivityAnalyzer_detect_anomalies_no_stddev_no_anomalies(analyzer):
    """Test detect_anomalies returns empty when intervals have zero standard deviation."""
    base = datetime(2023, 1, 1, 0, 0, 0)
    timestamps = [base + timedelta(minutes=i) for i in range(6)]  # equal 1-minute intervals
    activities = [{"action": "repeat", "timestamp": ts} for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_ActivityAnalyzer_detect_anomalies_ignores_few_occurrences(analyzer):
    """Test detect_anomalies ignores actions with fewer than 3 timestamps."""
    base = datetime(2023, 1, 1, 0, 0, 0)
    # 'few' has only 2 timestamps; 'stable' has many equal intervals
    activities = [
        {"action": "few", "timestamp": base},
        {"action": "few", "timestamp": base + timedelta(seconds=10)},
    ]
    activities += [{"action": "stable", "timestamp": base + timedelta(seconds=60 * i)} for i in range(7)]
    anomalies = analyzer.detect_anomalies(activities)
    # No anomalies expected and 'few' should not appear
    assert anomalies == []


def test_ActivityAnalyzer_parse_timestamp_does_not_raise_on_invalid(analyzer):
    """Test _parse_timestamp does not raise exception for invalid types."""
    class Weird:
        pass

    assert analyzer._parse_timestamp(Weird()) is None