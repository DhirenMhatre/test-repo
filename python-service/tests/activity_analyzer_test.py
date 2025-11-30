import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide a default ActivityAnalyzer instance for tests."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing event times."""
    return datetime(2021, 1, 1, 0, 0, 0)


def make_activity(action, timestamp):
    """Helper to create an activity dict."""
    return {"action": action, "timestamp": timestamp}


def test_activitypattern_to_dict_basic():
    """ActivityPattern.to_dict returns the expected mapping."""
    ap = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.85)
    d = ap.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "desc",
        "confidence": 0.85,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """ActivityAnalyzer initializes with expected default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer):
    """_parse_timestamp handles datetime, ISO strings with and without Z, and invalid values."""
    dt = datetime(2022, 5, 1, 10, 30, 0)
    assert analyzer._parse_timestamp(dt) == dt

    s_with_z = "2022-05-01T10:30:00Z"
    parsed_z = analyzer._parse_timestamp(s_with_z)
    assert isinstance(parsed_z, datetime)
    assert parsed_z.hour == 10  # Basic sanity check

    s_no_z = "2022-05-01T10:30:00"
    parsed_no_z = analyzer._parse_timestamp(s_no_z)
    assert isinstance(parsed_no_z, datetime)
    assert parsed_no_z.hour == 10

    assert analyzer._parse_timestamp("not-a-timestamp") is None
    assert analyzer._parse_timestamp(12345) is None
    assert analyzer._parse_timestamp(None) is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """_detect_peak_hours identifies hours exceeding the configured threshold."""
    activities = []
    # 3 events at 10:00
    for i in range(3):
        activities.append(make_activity("login", base_time.replace(hour=10) + timedelta(minutes=i)))
    # 3 events at 15:00
    for i in range(3):
        activities.append(make_activity("view", base_time.replace(hour=15) + timedelta(minutes=i)))
    # 4 events at other hours
    activities.extend([
        make_activity("edit", base_time.replace(hour=1)),
        make_activity("edit", base_time.replace(hour=2)),
        make_activity("edit", base_time.replace(hour=3)),
        make_activity("edit", base_time.replace(hour=4)),
    ])

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "10:00" in p.description
    assert "15:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_action_sequences_common(analyzer, base_time):
    """_detect_action_sequences finds frequent 3-action sequences."""
    # Build actions so that A → B → C occurs 3 times
    actions = [
        "A", "B", "C",
        "D",
        "A", "B", "C",
        "E",
        "A", "B", "C",
    ]
    activities = [
        make_activity(a, base_time + timedelta(minutes=i)) for i, a in enumerate(actions)
    ]

    patterns = analyzer._detect_action_sequences(activities)
    # Ensure at least the 'A → B → C' sequence is found with correct count
    matched = [p for p in patterns if p.pattern_type == "action_sequence" and "A → B → C" in p.description]
    assert matched, "Expected to find the 'A → B → C' sequence"
    assert "(occurred 3 times)" in matched[0].description
    assert matched[0].confidence == 0.75


def test_activityanalyzer_detect_regularity_positive(analyzer, base_time):
    """_detect_regularity returns a pattern when intervals are highly regular."""
    # 7 timestamps, equally spaced by 60 seconds -> CV = 0
    activities = [
        make_activity("tick", base_time + timedelta(seconds=60 * i)) for i in range(7)
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV: 0.00" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_negative(analyzer, base_time):
    """_detect_regularity returns empty when activity is irregular."""
    # 7 timestamps, irregular spacing
    intervals = [10, 300, 50, 1000, 70, 5]
    timestamps = [base_time]
    for sec in intervals:
        timestamps.append(timestamps[-1] + timedelta(seconds=sec))

    activities = [make_activity("irregular", ts) for ts in timestamps]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_analyze_patterns_calls_internal(analyzer):
    """analyze_patterns calls internal detection methods and aggregates results."""
    dummy_activities = [make_activity("x", datetime(2021, 1, 1, 0, 0, 0))]

    peak_pat = ActivityPattern("peak_hours", "peak", 0.85)
    seq_pat = ActivityPattern("action_sequence", "seq", 0.75)
    reg_pat = ActivityPattern("regularity", "reg", 0.90)

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[peak_pat]) as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[seq_pat]) as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[reg_pat]) as mock_reg:
        patterns = analyzer.analyze_patterns(dummy_activities)

        mock_peak.assert_called_once_with(dummy_activities)
        mock_seq.assert_called_once_with(dummy_activities)
        mock_reg.assert_called_once_with(dummy_activities)

        assert patterns == [peak_pat, seq_pat, reg_pat]


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """analyze_patterns returns empty list for empty input."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """get_user_score returns 0.0 for empty input."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_dates(analyzer, base_time):
    """get_user_score computes score using days_active when timestamps are valid."""
    # 10 actions over 5 days (Jan1 to Jan6) with 2 unique actions
    activities = []
    for i in range(10):
        ts = base_time + timedelta(days=i // 2)  # two actions per day
        act = "A" if i % 2 == 0 else "B"
        activities.append(make_activity(act, ts))

    # Ensure first and last timestamps span 5 days: Jan1 to Jan6
    activities[0]["timestamp"] = base_time  # Jan1
    activities[-1]["timestamp"] = base_time + timedelta(days=5)  # Jan6

    score = analyzer.get_user_score(activities)

    # Expected:
    # total_actions = 10; unique_actions = 2; diversity = 0.2
    # days_active = 5; actions_per_day = 2; freq = 0.2
    # volume = 0.1
    # final = (0.2*0.3 + 0.2*0.4 + 0.1*0.3) * 100 = 17.0
    assert score == 17.0


def test_activityanalyzer_get_user_score_without_dates(analyzer):
    """get_user_score uses total_actions for frequency when timestamps are invalid."""
    activities = []
    for i in range(10):
        act = "A" if i % 5 == 0 else "B"
        # Invalid timestamps to force fallback path
        activities.append(make_activity(act, "invalid-timestamp"))

    score = analyzer.get_user_score(activities)

    # Expected:
    # total_actions = 10; unique_actions = 2; diversity = 0.2
    # actions_per_day = total_actions = 10 -> freq = 1.0
    # volume = 0.1
    # final = (0.2*0.3 + 1.0*0.4 + 0.1*0.3) * 100 = 49.0
    assert score == 49.0


def test_activityanalyzer_detect_anomalies_minimum_length(analyzer, base_time):
    """detect_anomalies returns empty when fewer than 5 activities are provided."""
    activities = [
        make_activity("login", base_time + timedelta(minutes=i)) for i in range(4)
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_with_outlier_interval(analyzer, base_time):
    """detect_anomalies flags anomalies when intervals exhibit a high z-score."""
    activities = []

    # Create 12 timestamps for 'login' so there are 11 intervals.
    # 10 intervals of 60s and 1 outlier interval of 3600s to achieve z > 3 (sqrt(10) ~ 3.16).
    current = base_time
    for i in range(11):
        activities.append(make_activity("login", current))
        # Insert a large gap before the last timestamp
        gap = 3600 if i == 9 else 60
        current = current + timedelta(seconds=gap)
    # Append last timestamp for the 11th interval
    activities.append(make_activity("login", current))

    # Add some other activities to increase overall activities count
    for i in range(3):
        activities.append(make_activity("view", base_time + timedelta(hours=i)))

    anomalies = analyzer.detect_anomalies(activities)
    # Expect at least one anomaly for 'login' with z_score >= 3.0
    assert any(a["action"] == "login" and a["z_score"] >= 3.0 for a in anomalies)
    # Ensure anomaly dict has required fields
    for a in anomalies:
        assert "action" in a and "timestamp" in a and "z_score" in a and "reason" in a


def test_activityanalyzer_detect_anomalies_handles_invalid_timestamps(analyzer):
    """detect_anomalies should skip invalid timestamps without raising exceptions."""
    activities = [
        {"action": "login", "timestamp": "invalid"},
        {"action": "login", "timestamp": 12345},
        {"action": "login", "timestamp": None},
        {"action": "login", "timestamp": "2021-01-01T00:00:00Z"},
        {"action": "login", "timestamp": "2021-01-01T00:00:10Z"},
    ]
    # Should not raise and likely return empty due to not enough valid intervals
    anomalies = analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """_detect_peak_hours returns empty when there are no valid timestamps."""
    activities = [
        make_activity("a", "invalid"),
        make_activity("b", None),
        make_activity("c", 123),
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_too_short(analyzer):
    """_detect_action_sequences returns empty when not enough activities."""
    activities = [make_activity("A", datetime(2021, 1, 1, 0, 0, 0))]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_not_enough(analyzer):
    """_detect_regularity returns empty when fewer than 5 timestamps are present."""
    activities = [
        make_activity("A", datetime(2021, 1, 1, 0, 0, 0) + timedelta(minutes=i))
        for i in range(4)
    ]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_analyze_patterns_handles_empty_subcalls(analyzer, base_time):
    """analyze_patterns handles cases where internal detectors return empty lists."""
    dummy_activities = [make_activity("x", base_time)]
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[]) as mp, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[]) as ms, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[]) as mr:
        patterns = analyzer.analyze_patterns(dummy_activities)
        mp.assert_called_once()
        ms.assert_called_once()
        mr.assert_called_once()
        assert patterns == []


def test_activityanalyzer_get_user_score_mixed_invalid_and_valid_timestamps(analyzer, base_time):
    """get_user_score should compute using valid dates when possible and ignore invalid timestamps."""
    # Mix valid and invalid timestamps; first and last are valid to compute days_active
    activities = []
    activities.append(make_activity("A", base_time))  # valid start
    for i in range(8):
        activities.append(make_activity("B", "invalid"))
    activities.append(make_activity("A", base_time + timedelta(days=2)))  # valid end

    # total_actions = 10, unique_actions = 2
    # days_active = 2, actions_per_day = 5.0 -> frequency_score = 0.5
    # diversity = 0.2, volume = 0.1
    # final = (0.2*0.3 + 0.5*0.4 + 0.1*0.3) * 100 = (0.06 + 0.2 + 0.03)*100 = 29.0
    score = analyzer.get_user_score(activities)
    assert score == 29.0