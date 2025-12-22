import pytest
from unittest.mock import Mock, patch
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Base datetime for constructing test timestamps."""
    return datetime(2021, 1, 1, 0, 0, 0)


def test_activitypattern_to_dict_basic():
    """ActivityPattern.to_dict returns a correct dictionary."""
    pat = ActivityPattern(pattern_type="test_type", description="Test description", confidence=0.88)
    d = pat.to_dict()
    assert d["pattern_type"] == "test_type"
    assert d["description"] == "Test description"
    assert d["confidence"] == pytest.approx(0.88)


def test_activityanalyzer_init_defaults(analyzer):
    """ActivityAnalyzer initializes with correct default thresholds."""
    assert analyzer.peak_hour_threshold == pytest.approx(0.2)
    assert analyzer.anomaly_threshold == pytest.approx(3.0)


def test_activityanalyzer_parse_timestamp_datetime_and_str_and_invalid(analyzer):
    """_parse_timestamp handles datetime objects, ISO strings with Z, and invalid inputs."""
    dt = datetime(2021, 1, 1, 12, 0, 0)
    parsed_dt = analyzer._parse_timestamp(dt)
    assert parsed_dt == dt

    iso = "2021-01-01T12:00:00Z"
    parsed_iso = analyzer._parse_timestamp(iso)
    # It may be timezone-aware. We assert round-trip isoformat compatibility for the 'Z' case
    assert parsed_iso is not None
    assert parsed_iso.isoformat().endswith("+00:00")

    invalid = "not-a-date"
    parsed_invalid = analyzer._parse_timestamp(invalid)
    assert parsed_invalid is None


def test_activityanalyzer_parse_timestamp_handles_fromisoformat_exception(analyzer):
    """_parse_timestamp returns None when datetime.fromisoformat raises an exception."""
    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=ValueError):
        result = analyzer._parse_timestamp("2021-01-01T00:00:00")
        assert result is None


def test_activityanalyzer_detect_peak_hours_threshold_behavior(analyzer, base_time):
    """_detect_peak_hours identifies hours strictly above the threshold and formats hours correctly."""
    activities = []
    # 5 events at 08:00
    activities += [{"timestamp": base_time.replace(hour=8, minute=i), "action": "x"} for i in range(5)]
    # 3 events at 15:00
    activities += [{"timestamp": base_time.replace(hour=15, minute=i), "action": "y"} for i in range(3)]
    # 2 events at 09:00
    activities += [{"timestamp": base_time.replace(hour=9, minute=i), "action": "z"} for i in range(2)]

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "08:00" in p.description
    assert "15:00" in p.description
    assert "09:00" not in p.description
    assert p.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_no_parsable_timestamps(analyzer):
    """_detect_peak_hours returns empty list when timestamps cannot be parsed."""
    activities = [{"timestamp": "invalid", "action": "a"} for _ in range(5)]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_common_triples(analyzer):
    """_detect_action_sequences returns most common sequences with counts >= 2."""
    actions = ["A", "B", "C"] * 3  # 9 actions
    activities = [{"timestamp": datetime(2021, 1, 1, 0, 0, i), "action": a} for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)

    # Expect 3 patterns: ABC (3 times), BCA (2 times), CAB (2 times)
    assert len(patterns) == 3
    descriptions = {p.description for p in patterns}
    expected_desc = {
        "Common sequence: A → B → C (occurred 3 times)",
        "Common sequence: B → C → A (occurred 2 times)",
        "Common sequence: C → A → B (occurred 2 times)",
    }
    assert descriptions == expected_desc
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_insufficient_length(analyzer):
    """_detect_action_sequences returns empty list when activities < 3."""
    activities = [{"timestamp": datetime(2021, 1, 1, 0, 0, i), "action": "A"} for i in range(2)]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """_detect_regularity identifies highly regular intervals (low coefficient of variation)."""
    activities = []
    for i in range(6):
        activities.append({"timestamp": base_time + timedelta(seconds=i * 10), "action": "tick"})
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV: 0.00" in p.description
    assert p.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_not_enough_valid_timestamps(analyzer, base_time):
    """_detect_regularity returns empty when fewer than 5 valid timestamps are parsed."""
    activities = [
        {"timestamp": base_time + timedelta(seconds=0), "action": "a"},
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": base_time + timedelta(seconds=10), "action": "a"},
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": base_time + timedelta(seconds=20), "action": "a"},
    ]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_analyze_patterns_composes_private_methods(analyzer):
    """analyze_patterns returns a concatenation of results from internal detectors."""
    activities = [{"timestamp": datetime(2021, 1, 1, 0, 0, 0), "action": "a"}]

    peak_patterns = [ActivityPattern("peak_hours", "desc1", 0.5)]
    seq_patterns = [ActivityPattern("action_sequence", "desc2", 0.6), ActivityPattern("action_sequence", "desc3", 0.6)]
    reg_patterns = []

    peak_mock = Mock(return_value=peak_patterns)
    seq_mock = Mock(return_value=seq_patterns)
    reg_mock = Mock(return_value=reg_patterns)

    # Replace methods on the instance to assert calls and return values
    analyzer._detect_peak_hours = peak_mock  # type: ignore
    analyzer._detect_action_sequences = seq_mock  # type: ignore
    analyzer._detect_regularity = reg_mock  # type: ignore

    result = analyzer.analyze_patterns(activities)

    peak_mock.assert_called_once_with(activities)
    seq_mock.assert_called_once_with(activities)
    reg_mock.assert_called_once_with(activities)

    assert result == peak_patterns + seq_patterns + reg_patterns


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """analyze_patterns returns empty list when there are no activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """get_user_score returns 0.0 when there are no activities."""
    assert analyzer.get_user_score([]) == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_same_day(analyzer, base_time):
    """get_user_score computes scores when all activities occur within the same day."""
    # 10 activities within the same day
    activities = [{"timestamp": base_time + timedelta(minutes=i), "action": "repeat"} for i in range(10)]
    # diversity_score=1.0 (due to implementation), frequency_score=1.0 (10 per day), volume_score=0.1
    # final = (0.3*1 + 0.4*1 + 0.3*0.1)*100 = 73.0
    score = analyzer.get_user_score(activities)
    assert score == pytest.approx(73.0)


def test_activityanalyzer_get_user_score_across_multiple_days(analyzer, base_time):
    """get_user_score accounts for days active between first and last timestamps."""
    # 10 activities from Jan 1 00:00 to Jan 6 00:00 => (last - first).days = 5
    activities = []
    activities.append({"timestamp": base_time, "action": "x"})
    for i in range(8):
        activities.append({"timestamp": base_time + timedelta(days=i // 2, minutes=i), "action": "x"})
    activities.append({"timestamp": base_time + timedelta(days=5), "action": "x"})  # last at +5 days

    # diversity_score=1.0, actions_per_day=10/5=2 -> frequency_score=0.2, volume_score=0.1
    # final = (0.3*1 + 0.4*0.2 + 0.3*0.1)*100 = 41.0
    score = analyzer.get_user_score(activities)
    assert score == pytest.approx(41.0)


def test_activityanalyzer_get_user_score_invalid_first_timestamp_else_branch(analyzer, base_time):
    """get_user_score falls back to total actions for actions_per_day when first/last timestamp is invalid."""
    # First timestamp invalid; last is valid far apart, but code uses else branch -> actions_per_day = total_actions
    activities = [{"timestamp": "invalid", "action": "x"}]
    activities += [{"timestamp": base_time + timedelta(days=i), "action": "x"} for i in range(9)]
    # With N=10: diversity=1, frequency=min(10/10,1)=1, volume=0.1 -> 73.0
    score = analyzer.get_user_score(activities)
    assert score == pytest.approx(73.0)


def test_activityanalyzer_detect_anomalies_not_enough_data(analyzer, base_time):
    """detect_anomalies returns empty list when fewer than 5 activities provided."""
    activities = [{"timestamp": base_time + timedelta(seconds=i * 10), "action": "a"} for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_detects_outlier_interval_and_threshold(analyzer, base_time):
    """detect_anomalies detects large interval outlier; respects anomaly_threshold."""
    # Build 22 timestamps for action 'login' with 21 intervals: 20 of 10s and 1 of 1000s (last)
    timestamps = [base_time]
    for i in range(20):
        timestamps.append(timestamps[-1] + timedelta(seconds=10))
    timestamps.append(timestamps[-1] + timedelta(seconds=1000))  # outlier interval at the end

    activities = [{"timestamp": ts, "action": "login"} for ts in timestamps]

    anomalies = analyzer.detect_anomalies(activities)
    # Expect at least one anomaly for 'login'
    assert any(a["action"] == "login" for a in anomalies)
    # The anomaly should be at the last timestamp
    last_ts_iso = timestamps[-1].isoformat()
    last_anoms = [a for a in anomalies if a["timestamp"] == last_ts_iso and a["action"] == "login"]
    assert len(last_anoms) >= 1

    # Check z_score and reason contents
    a = last_anoms[0]
    # Compute expected mean and std for verification
    intervals = [10] * 20 + [1000]
    mean_interval = sum(intervals) / len(intervals)
    variance = sum((x - mean_interval) ** 2 for x in intervals) / len(intervals)
    std_dev = variance ** 0.5
    expected_z = abs((1000 - mean_interval) / std_dev) if std_dev > 0 else 0.0

    assert a["z_score"] == pytest.approx(round(expected_z, 2))
    assert "Unusual interval: 1000s" in a["reason"]
    assert f"avg {mean_interval:.1f}s" in a["reason"]

    # Now raise the threshold very high to suppress anomalies
    analyzer.anomaly_threshold = 100.0
    anomalies_high_thresh = analyzer.detect_anomalies(activities)
    assert anomalies_high_thresh == []


def test_activityanalyzer_detect_anomalies_ignores_insufficient_action_history(analyzer, base_time):
    """detect_anomalies ignores actions with fewer than 3 timestamps and those with zero std deviation."""
    activities = []
    # 'click' only 2 timestamps => ignored
    activities.append({"timestamp": base_time, "action": "click"})
    activities.append({"timestamp": base_time + timedelta(seconds=10), "action": "click"})
    # 'view' 3 timestamps but equal intervals => std dev 0 -> no anomaly
    activities.append({"timestamp": base_time, "action": "view"})
    activities.append({"timestamp": base_time + timedelta(seconds=10), "action": "view"})
    activities.append({"timestamp": base_time + timedelta(seconds=20), "action": "view"})
    # total activities >= 5 to pass initial length check
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []