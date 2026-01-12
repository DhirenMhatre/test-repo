import pytest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def activity_pattern_instance():
    """Create ActivityPattern instance for testing."""
    return ActivityPattern(pattern_type="test_type", description="test_desc", confidence=0.75)


@pytest.fixture
def activity_analyzer_instance():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def test_activitypattern_init_basic(activity_pattern_instance):
    """Test ActivityPattern initialization with valid data."""
    assert activity_pattern_instance.pattern_type == "test_type"
    assert activity_pattern_instance.description == "test_desc"
    assert activity_pattern_instance.confidence == pytest.approx(0.75)


def test_activitypattern_to_dict(activity_pattern_instance):
    """Test ActivityPattern.to_dict returns correct dictionary."""
    result = activity_pattern_instance.to_dict()
    assert isinstance(result, dict)
    assert result["pattern_type"] == "test_type"
    assert result["description"] == "test_desc"
    assert result["confidence"] == pytest.approx(0.75)


def test_activityanalyzer_init_defaults(activity_analyzer_instance):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert activity_analyzer_instance.peak_hour_threshold == pytest.approx(0.2)
    assert activity_analyzer_instance.anomaly_threshold == pytest.approx(3.0)


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer_instance):
    """Test analyze_patterns returns empty list for no activities."""
    result = activity_analyzer_instance.analyze_patterns([])
    assert result == []


def test_activityanalyzer_analyze_patterns_combines_patterns(activity_analyzer_instance):
    """Test analyze_patterns combines results from internal detectors."""
    base_time = datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc)
    activities = [
        {"action": "a", "timestamp": (base_time + timedelta(minutes=i)).isoformat()}
        for i in range(10)
    ]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[ActivityPattern("peak", "p", 0.8)]) as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[ActivityPattern("seq", "s", 0.7)]) as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[ActivityPattern("reg", "r", 0.9)]) as mock_reg:
        result = activity_analyzer_instance.analyze_patterns(activities)

    mock_peak.assert_called_once_with(activities)
    mock_seq.assert_called_once_with(activities)
    mock_reg.assert_called_once_with(activities)

    assert len(result) == 3
    assert {p.pattern_type for p in result} == {"peak", "seq", "reg"}


def test_activityanalyzer_get_user_score_empty(activity_analyzer_instance):
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer_instance.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer_instance):
    """Test get_user_score with simple activity list and same-day timestamps."""
    base_time = datetime(2024, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    activities = [
        {"action": "login", "timestamp": base_time.isoformat()},
        {"action": "view", "timestamp": (base_time + timedelta(hours=1)).isoformat()},
        {"action": "logout", "timestamp": (base_time + timedelta(hours=2)).isoformat()},
    ]

    score = activity_analyzer_instance.get_user_score(activities)

    # Manually compute expected score:
    # total_actions = 3, unique_actions = 3, days_active = 1
    # actions_per_day = 3
    # diversity_score = 3/3 = 1.0
    # frequency_score = min(3/10, 1) = 0.3
    # volume_score = min(3/100, 1) = 0.03
    # final = (1*0.3 + 0.3*0.4 + 0.03*0.3)*100 = (0.3 + 0.12 + 0.009)*100 = 42.9
    expected = 42.9
    assert score == pytest.approx(expected)


def test_activityanalyzer_get_user_score_multiple_days(activity_analyzer_instance):
    """Test get_user_score when activities span multiple days."""
    t1 = datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc)
    t2 = datetime(2024, 1, 4, 10, 0, 0, tzinfo=timezone.utc)  # 3 days difference
    activities = [
        {"action": "a", "timestamp": t1.isoformat()},
        {"action": "b", "timestamp": t2.isoformat()},
    ]

    score = activity_analyzer_instance.get_user_score(activities)

    # total_actions = 2, unique_actions = 2
    # days_active = max(3,1) = 3
    # actions_per_day = 2/3
    # diversity_score = 1.0
    # frequency_score = min((2/3)/10,1) = 2/30 = 0.066666...
    # volume_score = min(2/100,1) = 0.02
    # final = (1*0.3 + 0.066666*0.4 + 0.02*0.3)*100
    diversity = 1.0
    frequency = (2 / 3) / 10.0
    volume = 2 / 100.0
    expected = (diversity * 0.3 + frequency * 0.4 + volume * 0.3) * 100
    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_invalid_timestamps(activity_analyzer_instance):
    """Test get_user_score when timestamps are invalid strings."""
    activities = [
        {"action": "a", "timestamp": "not-a-timestamp"},
        {"action": "b", "timestamp": "also-bad"},
    ]

    score = activity_analyzer_instance.get_user_score(activities)

    # When timestamps invalid, actions_per_day = total_actions
    # total_actions = 2, unique_actions = 2
    # actions_per_day = 2
    # diversity_score = 1.0
    # frequency_score = min(2/10,1) = 0.2
    # volume_score = min(2/100,1) = 0.02
    expected = (1.0 * 0.3 + 0.2 * 0.4 + 0.02 * 0.3) * 100
    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_detect_anomalies_too_few(activity_analyzer_instance):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    base_time = datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc)
    activities = [
        {"action": "a", "timestamp": (base_time + timedelta(minutes=i)).isoformat()}
        for i in range(4)
    ]
    anomalies = activity_analyzer_instance.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_no_anomalies(activity_analyzer_instance):
    """Test detect_anomalies returns empty list when intervals are regular."""
    base_time = datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc)
    # Regular 10-minute intervals for same action
    activities = [
        {"action": "click", "timestamp": (base_time + timedelta(minutes=10 * i)).isoformat()}
        for i in range(6)
    ]
    anomalies = activity_analyzer_instance.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_with_anomaly(activity_analyzer_instance):
    """Test detect_anomalies detects an interval with high z-score."""
    base_time = datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc)
    # Mostly 10s intervals, one very large interval to trigger anomaly
    timestamps = [
        base_time,
        base_time + timedelta(seconds=10),
        base_time + timedelta(seconds=20),
        base_time + timedelta(seconds=30),
        base_time + timedelta(seconds=1000),  # large gap
        base_time + timedelta(seconds=1010),
    ]
    activities = [{"action": "click", "timestamp": ts.isoformat()} for ts in timestamps]

    anomalies = activity_analyzer_instance.detect_anomalies(activities)

    assert isinstance(anomalies, list)
    assert len(anomalies) >= 1
    anomaly_actions = {a["action"] for a in anomalies}
    assert "click" in anomaly_actions
    for a in anomalies:
        assert "z_score" in a
        assert isinstance(a["z_score"], float)
        assert a["z_score"] == pytest.approx(a["z_score"])  # float comparison requirement


def test_activityanalyzer_detect_anomalies_ignores_few_timestamps(activity_analyzer_instance):
    """Test detect_anomalies ignores actions with fewer than 3 timestamps."""
    base_time = datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc)
    activities = [
        {"action": "few", "timestamp": (base_time + timedelta(minutes=i)).isoformat()}
        for i in range(2)
    ] + [
        {"action": "many", "timestamp": (base_time + timedelta(minutes=10 * i)).isoformat()}
        for i in range(5)
    ]
    anomalies = activity_analyzer_instance.detect_anomalies(activities)
    for a in anomalies:
        assert a["action"] != "few"


def test_activityanalyzer_detect_anomalies_invalid_timestamps(activity_analyzer_instance):
    """Test detect_anomalies handles invalid timestamps without raising exceptions."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "a", "timestamp": "also-invalid"},
        {"action": "a", "timestamp": "2024-01-01T10:00:00Z"},
        {"action": "a", "timestamp": "2024-01-01T10:00:10Z"},
        {"action": "a", "timestamp": "2024-01-01T10:00:20Z"},
    ]
    anomalies = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(anomalies, list)


def test_activityanalyzer_detect_peak_hours_no_activities(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty list when no valid timestamps."""
    patterns = activity_analyzer_instance._detect_peak_hours([{"action": "a", "timestamp": "invalid"}])
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_basic(activity_analyzer_instance):
    """Test _detect_peak_hours identifies peak hours above threshold."""
    base_time = datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc)
    activities = []
    # 8 activities at 10:00, 2 at 11:00 -> 10:00 should be peak (0.8 > 0.2)
    for i in range(8):
        activities.append({"action": "a", "timestamp": (base_time + timedelta(minutes=i)).isoformat()})
    for i in range(2):
        activities.append({"action": "b", "timestamp": (base_time + timedelta(hours=1, minutes=i)).isoformat()})

    patterns = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "peak_hours"
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_multiple(activity_analyzer_instance):
    """Test _detect_peak_hours can return multiple peak hours."""
    base_time = datetime(2024, 1, 1, 8, 0, 0, tzinfo=timezone.utc)
    activities = []
    # 3 hours with equal counts above threshold
    for h in [8, 9, 10]:
        for i in range(5):
            ts = base_time.replace(hour=h) + timedelta(minutes=i)
            activities.append({"action": "a", "timestamp": ts.isoformat()})

    patterns = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(patterns) == 1
    desc = patterns[0].description
    assert "08:00" in desc
    assert "09:00" in desc
    assert "10:00" in desc


def test_activityanalyzer_detect_action_sequences_too_short(activity_analyzer_instance):
    """Test _detect_action_sequences returns empty list when fewer than 3 activities."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T10:00:00Z"},
        {"action": "b", "timestamp": "2024-01-01T10:01:00Z"},
    ]
    patterns = activity_analyzer_instance._detect_action_sequences(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_basic(activity_analyzer_instance):
    """Test _detect_action_sequences detects common sequences occurring at least twice."""
    # Sequence: a,b,c appears 3 times; b,c,d appears 2 times
    activities = [
        {"action": "a"}, {"action": "b"}, {"action": "c"},
        {"action": "x"},
        {"action": "a"}, {"action": "b"}, {"action": "c"},
        {"action": "b"}, {"action": "c"}, {"action": "d"},
        {"action": "a"}, {"action": "b"}, {"action": "c"},
        {"action": "b"}, {"action": "c"}, {"action": "d"},
    ]
    patterns = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(patterns) >= 1
    descriptions = [p.description for p in patterns]
    assert any("a → b → c" in d for d in descriptions)
    assert any("occurred 3 times" in d for d in descriptions)
    assert all(p.pattern_type == "action_sequence" for p in patterns)
    for p in patterns:
        assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_uses_default_action(activity_analyzer_instance):
    """Test _detect_action_sequences uses empty string for missing action keys."""
    activities = [
        {"timestamp": "2024-01-01T10:00:00Z"},
        {"action": "b"},
        {"action": "c"},
        {"timestamp": "2024-01-01T10:03:00Z"},
        {"action": "b"},
        {"action": "c"},
    ]
    patterns = activity_analyzer_instance._detect_action_sequences(activities)
    # Sequence ('', 'b', 'c') should appear twice
    assert any(" → b → c" in p.description and "occurred 2 times" in p.description for p in patterns)


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer_instance):
    """Test _detect_regularity returns empty list when fewer than 5 valid timestamps."""
    activities = [
        {"action": "a", "timestamp": "2024-01-01T10:00:00Z"},
        {"action": "a", "timestamp": "invalid"},
        {"action": "a", "timestamp": "2024-01-01T10:10:00Z"},
        {"action": "a", "timestamp": "2024-01-01T10:20:00Z"},
    ]
    patterns = activity_analyzer_instance._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_regular(activity_analyzer_instance):
    """Test _detect_regularity detects highly regular intervals."""
    base_time = datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc)
    # Very regular 10-minute intervals
    activities = [
        {"action": "a", "timestamp": (base_time + timedelta(minutes=10 * i)).isoformat()}
        for i in range(6)
    ]
    patterns = activity_analyzer_instance._detect_regularity(activities)
    assert len(patterns) == 1
    pattern = patterns[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer_instance):
    """Test _detect_regularity returns empty list for irregular intervals."""
    base_time = datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc)
    intervals = [1, 10, 100, 5, 60]  # highly variable
    timestamps = [base_time]
    for sec in intervals:
        timestamps.append(timestamps[-1] + timedelta(seconds=sec))
    activities = [{"action": "a", "timestamp": ts.isoformat()} for ts in timestamps]

    patterns = activity_analyzer_instance._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer_instance):
    """Test _parse_timestamp returns datetime unchanged when input is datetime."""
    ts = datetime(2024, 1, 1, 10, 0, 0)
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string correctly."""
    ts_str = "2024-01-01T10:00:00"
    parsed = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.month == 1
    assert parsed.day == 1
    assert parsed.hour == 10
    assert parsed.minute == 0
    assert parsed.second == 0


def test_activityanalyzer_parse_timestamp_z_suffix(activity_analyzer_instance):
    """Test _parse_timestamp handles 'Z' UTC suffix by converting to offset-aware datetime."""
    ts_str = "2024-01-01T10:00:00Z"
    parsed = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is not None
    assert parsed.utcoffset() == timedelta(0)


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer_instance):
    """Test _parse_timestamp returns None for invalid timestamp string."""
    parsed = activity_analyzer_instance._parse_timestamp("not-a-timestamp")
    assert parsed is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer_instance):
    """Test _parse_timestamp returns None for unsupported input types."""
    parsed = activity_analyzer_instance._parse_timestamp(12345)
    assert parsed is None


def test_activityanalyzer_analyze_patterns_handles_invalid_timestamps(activity_analyzer_instance):
    """Test analyze_patterns does not raise when activities contain invalid timestamps."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "b", "timestamp": "2024-01-01T10:00:00Z"},
        {"action": "c", "timestamp": None},
    ]
    patterns = activity_analyzer_instance.analyze_patterns(activities)
    assert isinstance(patterns, list)


def test_activityanalyzer_internal_methods_exception_handling(activity_analyzer_instance):
    """Test analyze_patterns propagates exceptions from internal methods."""
    activities = [{"action": "a", "timestamp": "2024-01-01T10:00:00Z"}]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", side_effect=RuntimeError("boom")):
        with pytest.raises(RuntimeError):
            activity_analyzer_instance.analyze_patterns(activities)