import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Provide a fresh ActivityAnalyzer instance for each test."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing test timestamps."""
    return datetime(2021, 1, 1, 0, 0, 0)


def make_activity(action: str, ts):
    """Helper to create an activity dict."""
    return {"action": action, "timestamp": ts}


def iso_z(dt: datetime) -> str:
    """Return an ISO string with Z suffix representing UTC."""
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def test_activitypattern_to_dict_roundtrip():
    """ActivityPattern.to_dict should return the expected dictionary."""
    ap = ActivityPattern(pattern_type="peak_hours", description="Test description", confidence=0.95)
    d = ap.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "Test description",
        "confidence": 0.95,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """ActivityAnalyzer should initialize with correct default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer, base_time):
    """_parse_timestamp should handle datetime object and ISO strings (with and without Z)."""
    # datetime object
    dt = analyzer._parse_timestamp(base_time)
    assert isinstance(dt, datetime)
    assert dt == base_time

    # ISO string with Z (UTC)
    ts_z = iso_z(base_time.replace(hour=12, minute=34, second=56))
    dt_z = analyzer._parse_timestamp(ts_z)
    assert isinstance(dt_z, datetime)
    assert dt_z.isoformat().startswith("2021-01-01T12:34:56")

    # ISO string without timezone
    ts_naive = "2021-01-02T03:04:05"
    dt_naive = analyzer._parse_timestamp(ts_naive)
    assert isinstance(dt_naive, datetime)
    assert dt_naive.isoformat() == "2021-01-02T03:04:05"


def test_activityanalyzer_parse_timestamp_invalid(analyzer):
    """_parse_timestamp should return None for invalid inputs."""
    assert analyzer._parse_timestamp("not-a-date") is None
    assert analyzer._parse_timestamp(None) is None
    assert analyzer._parse_timestamp(12345) is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer):
    """_detect_peak_hours should detect hours exceeding threshold and format description."""
    activities = [
        make_activity("a", "2021-01-01T01:00:00Z"),
        make_activity("b", "2021-01-01T01:15:00Z"),
        make_activity("c", "2021-01-01T02:00:00Z"),
        make_activity("d", "2021-01-01T03:00:00Z"),
        make_activity("e", "2021-01-01T04:00:00Z"),
    ]
    # 5 total: hour 1 has 2/5 = 0.4 (> 0.2) should be included; hours with 1/5 = 0.2 should NOT be included
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert isinstance(p, ActivityPattern)
    assert p.pattern_type == "peak_hours"
    assert "01:00" in p.description
    assert "02:00" not in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """_detect_peak_hours should return empty list when timestamps are invalid."""
    activities = [
        make_activity("a", "invalid"),
        make_activity("b", None),
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_top_counts(analyzer):
    """_detect_action_sequences should return frequent 3-grams occurring at least twice."""
    actions = [
        "A", "B", "C",  # ABC (1)
        "X",
        "A", "B", "C",  # ABC (2)
        "B", "C", "D",  # BCD (1)
        "Y",
        "B", "C", "D",  # BCD (2)
        "E", "F", "G",  # EFG (1)
        "H", "I", "J",  # HIJ (1)
        "K", "L", "M",  # KLM (1)
    ]
    activities = [make_activity(a, iso_z(datetime(2021, 1, 1, 0, 0, 0) + timedelta(minutes=i))) for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    # Should include ABC and BCD (occurred 2 times each)
    descriptions = {p.description for p in patterns}
    assert any("A → B → C" in d for d in descriptions)
    assert any("B → C → D" in d for d in descriptions)
    # Ensure only sequences with count >= 2 are included
    assert all("occurred" in p.description and "2 times" in p.description for p in patterns)


def test_activityanalyzer_detect_action_sequences_too_short(analyzer):
    """_detect_action_sequences should return empty when fewer than 3 activities."""
    activities = [make_activity("A", "2021-01-01T00:00:00Z"), make_activity("B", "2021-01-01T00:01:00Z")]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """_detect_regularity should detect highly regular intervals (low CV)."""
    activities = [
        make_activity("A", iso_z(base_time + timedelta(seconds=i * 60)))
        for i in range(6)  # 5 equal intervals of 60s
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV:" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer, base_time):
    """_detect_regularity should return empty for irregular intervals."""
    times = [0, 60, 300, 360, 1200, 1260]  # Irregular gaps
    activities = [make_activity("A", iso_z(base_time + timedelta(seconds=t))) for t in times]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_analyze_patterns_integration(analyzer, base_time):
    """analyze_patterns should combine peak_hours, action_sequence, and regularity patterns."""
    activities = [
        make_activity(a, iso_z(base_time.replace(hour=1) + timedelta(seconds=i * 60)))
        for i, a in enumerate(["A", "B", "C", "A", "B", "C"])  # regular, and ABC repeats twice
    ]
    patterns = analyzer.analyze_patterns(activities)
    types = {p.pattern_type for p in patterns}
    assert "peak_hours" in types
    assert "action_sequence" in types
    assert "regularity" in types


def test_activityanalyzer_analyze_patterns_calls_private_methods_with_mock(analyzer):
    """analyze_patterns should call private methods and concatenate their results in order."""
    activities = [make_activity("A", "2021-01-01T00:00:00Z")]
    ph = [ActivityPattern("peak_hours", "PH", 0.1)]
    seq = [ActivityPattern("action_sequence", "SEQ", 0.2)]
    reg = [ActivityPattern("regularity", "REG", 0.3)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=ph) as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=seq) as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=reg) as m3:
        result = analyzer.analyze_patterns(activities)

        m1.assert_called_once_with(activities)
        m2.assert_called_once_with(activities)
        m3.assert_called_once_with(activities)

        # Order should be peak_hours + action_sequences + regularity
        assert result == ph + seq + reg


def test_activityanalyzer_analyze_patterns_propagates_exception(analyzer):
    """analyze_patterns should propagate exceptions from private detectors."""
    activities = [make_activity("A", "2021-01-01T00:00:00Z")]
    with patch.object(ActivityAnalyzer, "_detect_action_sequences", side_effect=RuntimeError("boom")):
        with pytest.raises(RuntimeError):
            analyzer.analyze_patterns(activities)


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """analyze_patterns should return empty list when input activities are empty."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_empty_returns_zero(analyzer):
    """get_user_score should return 0.0 when there are no activities."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_valid_timestamps_same_day(analyzer, base_time):
    """get_user_score should compute scores with same-day timestamps (days_active=1)."""
    # 20 actions, 5 unique actions, all within the same day
    actions = ["A", "B", "C", "D", "E"] * 4  # 20 total
    activities = [
        make_activity(a, iso_z(base_time + timedelta(minutes=i)))
        for i, a in enumerate(actions)
    ]
    # Expected:
    # total_actions = 20
    # unique_actions = 5 => diversity = 5/20 = 0.25
    # days_active = 1 => actions_per_day = 20 => frequency = 1.0
    # volume = 20/100 = 0.2
    # final = (0.25*0.3 + 1.0*0.4 + 0.2*0.3) * 100 = 53.5
    score = analyzer.get_user_score(activities)
    assert score == 53.5


def test_activityanalyzer_get_user_score_invalid_timestamps_fallback(analyzer):
    """get_user_score should fall back when timestamps cannot be parsed."""
    activities = [
        make_activity("A", "invalid"),
        make_activity("B", "also-bad"),
        make_activity("A", "nope"),
        make_activity("B", None),
    ]
    # total_actions=4, unique=2 => diversity=0.5
    # actions_per_day fallback to total_actions=4 => frequency=0.4
    # volume=0.04
    # final=(0.5*0.3 + 0.4*0.4 + 0.04*0.3)*100 = 32.2
    score = analyzer.get_user_score(activities)
    assert score == 32.2


def test_activityanalyzer_detect_anomalies_not_enough_activities(analyzer):
    """detect_anomalies should return empty when there are fewer than 5 activities overall."""
    activities = [
        make_activity("login", "2021-01-01T00:00:00Z"),
        make_activity("login", "2021-01-01T00:01:00Z"),
        make_activity("login", "2021-01-01T00:02:00Z"),
        make_activity("login", "2021-01-01T00:03:00Z"),
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_flags_outlier_interval(analyzer, base_time):
    """detect_anomalies should flag an interval with z-score greater than threshold."""
    # Build 13 timestamps (12 intervals) for 'login': 11 intervals of 60s, 1 interval of 600s
    timestamps = [base_time]
    for i in range(12):
        delta = 600 if i == 5 else 60  # outlier at interval index 5
        timestamps.append(timestamps[-1] + timedelta(seconds=delta))

    activities = [make_activity("login", t) for t in timestamps]
    anomalies = analyzer.detect_anomalies(activities)

    # With 12 intervals, z for the outlier = sqrt(12) > 3, so one anomaly expected
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "login"
    # The anomaly timestamp should be timestamps[i+1] where the outlier interval occurred (i=5)
    assert anomaly["timestamp"] == timestamps[6].isoformat()
    assert anomaly["z_score"] > 3.0
    assert "Unusual interval:" in anomaly["reason"]
    assert "avg" in anomaly["reason"]


def test_activityanalyzer_detect_anomalies_std_zero_no_anomalies(analyzer, base_time):
    """detect_anomalies should not flag anomalies when intervals have zero std deviation."""
    # 6 timestamps with equal intervals => std_dev == 0 => no anomalies
    timestamps = [base_time + timedelta(minutes=i) for i in range(6)]
    activities = [make_activity("click", t) for t in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_ignores_insufficient_per_action(analyzer, base_time):
    """detect_anomalies should skip actions with fewer than 3 timestamps."""
    activities = [
        make_activity("a1", base_time),
        make_activity("a1", base_time + timedelta(minutes=1)),
        make_activity("a2", base_time),
        make_activity("a2", base_time + timedelta(minutes=1)),
        make_activity("a2", base_time + timedelta(minutes=2)),
    ]
    # a1 has only 2 timestamps -> ignored; a2 has 3 equal intervals -> no anomalies
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_calls_parse_timestamp(analyzer, base_time):
    """detect_anomalies should call _parse_timestamp for each activity."""
    activities = [
        make_activity("x", iso_z(base_time + timedelta(minutes=i)))
        for i in range(6)
    ]
    with patch.object(analyzer, "_parse_timestamp", wraps=analyzer._parse_timestamp) as wrapped:
        _ = analyzer.detect_anomalies(activities)
        assert wrapped.call_count == len(activities)