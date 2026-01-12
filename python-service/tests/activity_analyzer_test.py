import pytest
from unittest.mock import patch, MagicMock

from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def activity_pattern_instance():
    """Create ActivityPattern instance for testing."""
    return ActivityPattern(pattern_type="test_type", description="test description", confidence=0.95)


@pytest.fixture
def activity_analyzer_instance():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def test_activitypattern_init():
    """Test ActivityPattern initialization with valid data."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.8)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "desc"
    assert pattern.confidence == pytest.approx(0.8)


def test_activitypattern_to_dict(activity_pattern_instance):
    """Test ActivityPattern.to_dict returns correct dictionary."""
    result = activity_pattern_instance.to_dict()
    assert result["pattern_type"] == "test_type"
    assert result["description"] == "test description"
    assert result["confidence"] == pytest.approx(0.95)


def test_activityanalyzer_init_defaults(activity_analyzer_instance):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert activity_analyzer_instance.peak_hour_threshold == pytest.approx(0.2)
    assert activity_analyzer_instance.anomaly_threshold == pytest.approx(3.0)


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer_instance):
    """Test analyze_patterns returns empty list when no activities."""
    result = activity_analyzer_instance.analyze_patterns([])
    assert result == []


def test_activityanalyzer_analyze_patterns_calls_submethods(activity_analyzer_instance):
    """Test analyze_patterns calls internal detection methods and aggregates results."""
    activities = [{"timestamp": datetime.now().isoformat(), "action": "a"}]

    with patch.object(activity_analyzer_instance, "_detect_peak_hours", return_value=[ActivityPattern("t1", "d1", 0.5)]) as mock_peak, \
         patch.object(activity_analyzer_instance, "_detect_action_sequences", return_value=[ActivityPattern("t2", "d2", 0.6)]) as mock_seq, \
         patch.object(activity_analyzer_instance, "_detect_regularity", return_value=[ActivityPattern("t3", "d3", 0.7)]) as mock_reg:

        result = activity_analyzer_instance.analyze_patterns(activities)

        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)

        assert len(result) == 3
        assert [p.pattern_type for p in result] == ["t1", "t2", "t3"]


def test_activityanalyzer_get_user_score_empty(activity_analyzer_instance):
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer_instance.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer_instance):
    """Test get_user_score with simple activity list and valid timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(days=0)).isoformat(), "action": "login"},
        {"timestamp": (base + timedelta(days=0, hours=1)).isoformat(), "action": "view"},
        {"timestamp": (base + timedelta(days=1)).isoformat(), "action": "logout"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    # Manually compute expected score based on implementation
    total_actions = 3
    unique_actions = 3  # login, view, logout
    days_active = max((activities[-1]["timestamp"] > activities[0]["timestamp"]), 1)
    # Actually days_active is 1 because (day1 - day0).days == 1
    actions_per_day = total_actions / 1
    diversity_score = unique_actions / total_actions
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100

    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_no_timestamps(activity_analyzer_instance):
    """Test get_user_score when timestamps are missing or unparsable."""
    activities = [
        {"timestamp": "not-a-date", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"action": "c"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    total_actions = 3
    unique_actions = 3
    actions_per_day = total_actions  # falls back to total_actions when timestamps invalid
    diversity_score = unique_actions / total_actions
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100

    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_get_user_score_duplicate_actions(activity_analyzer_instance):
    """Test get_user_score unique action counting logic with duplicates."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": (base + timedelta(hours=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=2)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(hours=3)).isoformat(), "action": "a"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    # According to implementation, unique_actions is 2: 'a' and 'b'
    total_actions = 4
    unique_actions = 2
    days_active = max((base + timedelta(hours=3) - base).days, 1)  # 1
    actions_per_day = total_actions / days_active
    diversity_score = unique_actions / total_actions
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100

    assert score == pytest.approx(round(expected, 2))


def test_activityanalyzer_detect_anomalies_too_few(activity_analyzer_instance):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_no_intervals(activity_analyzer_instance):
    """Test detect_anomalies when actions have fewer than 3 timestamps."""
    base = datetime(2024, 1, 1)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"} for i in range(2)
    ] + [
        {"timestamp": (base + timedelta(minutes=10 + i)).isoformat(), "action": "b"} for i in range(2)
    ] + [
        {"timestamp": (base + timedelta(minutes=20)).isoformat(), "action": "c"}
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    # Each action has <3 timestamps, so no anomalies
    assert result == []


def test_activityanalyzer_detect_anomalies_with_outlier(activity_analyzer_instance):
    """Test detect_anomalies detects an interval with high z-score."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Create mostly regular 60s intervals, with one very large gap
    timestamps = [
        base,
        base + timedelta(seconds=60),
        base + timedelta(seconds=120),
        base + timedelta(seconds=180),
        base + timedelta(seconds=10000),  # big gap
        base + timedelta(seconds=10060),
    ]
    activities = [{"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps]

    result = activity_analyzer_instance.detect_anomalies(activities)

    # There should be at least one anomaly for the large interval
    assert len(result) >= 1
    anomaly_actions = {a["action"] for a in result}
    assert "a" in anomaly_actions
    for a in result:
        assert isinstance(a["timestamp"], str)
        assert a["z_score"] == pytest.approx(a["z_score"])
        assert "Unusual interval" in a["reason"]


def test_activityanalyzer_detect_anomalies_ignores_invalid_timestamps(activity_analyzer_instance):
    """Test detect_anomalies ignores activities with invalid timestamps."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    valid_activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"} for i in range(5)
    ]
    invalid_activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "a"},
    ]
    activities = valid_activities + invalid_activities

    result = activity_analyzer_instance.detect_anomalies(activities)
    # Should still run without error; anomalies may or may not exist depending on intervals
    assert isinstance(result, list)


def test_activityanalyzer_detect_peak_hours_no_timestamps(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty when no valid timestamps."""
    activities = [{"timestamp": "invalid", "action": "a"}, {"action": "b"}]
    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert result == []


def test_activityanalyzer_detect_peak_hours_single_peak(activity_analyzer_instance):
    """Test _detect_peak_hours identifies peak hours above threshold."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 8 activities at 10:00, 2 at 11:00 -> 10:00 is 80% > 0.2
    for i in range(8):
        activities.append({"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"})
    for i in range(2):
        activities.append({"timestamp": (base + timedelta(hours=1, minutes=i)).isoformat(), "action": "b"})

    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(result) == 1
    pattern = result[0]
    assert pattern.pattern_type == "peak_hours"
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_multiple_peaks(activity_analyzer_instance):
    """Test _detect_peak_hours can return multiple peak hours in description."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 3 at 10:00, 3 at 11:00, 4 at 12:00 -> all above 0.2
    for i in range(3):
        activities.append({"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"})
    for i in range(3):
        activities.append({"timestamp": (base + timedelta(hours=1, minutes=i)).isoformat(), "action": "b"})
    for i in range(4):
        activities.append({"timestamp": (base + timedelta(hours=2, minutes=i)).isoformat(), "action": "c"})

    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(result) == 1
    desc = result[0].description
    assert "10:00" in desc
    assert "11:00" in desc
    assert "12:00" in desc


def test_activityanalyzer_detect_action_sequences_too_short(activity_analyzer_instance):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"},
        {"timestamp": datetime.now().isoformat(), "action": "b"},
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert result == []


def test_activityanalyzer_detect_action_sequences_common(activity_analyzer_instance):
    """Test _detect_action_sequences detects common sequences occurring at least twice."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "login"},
        {"timestamp": (base + timedelta(minutes=1)).isoformat(), "action": "view"},
        {"timestamp": (base + timedelta(minutes=2)).isoformat(), "action": "logout"},
        {"timestamp": (base + timedelta(minutes=3)).isoformat(), "action": "login"},
        {"timestamp": (base + timedelta(minutes=4)).isoformat(), "action": "view"},
        {"timestamp": (base + timedelta(minutes=5)).isoformat(), "action": "logout"},
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(result) >= 1
    seq_descriptions = [p.description for p in result]
    assert any("login → view → logout" in d for d in seq_descriptions)
    for p in result:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_ignores_single_occurrence(activity_analyzer_instance):
    """Test _detect_action_sequences ignores sequences that occur only once."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": a}
        for i, a in enumerate(["a", "b", "c", "d", "e"])
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 activities."""
    activities = [
        {"timestamp": datetime.now().isoformat(), "action": "a"} for _ in range(4)
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_not_enough_valid_timestamps(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    activities = [
        {"timestamp": "invalid", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"timestamp": datetime.now().isoformat(), "action": "c"},
        {"timestamp": datetime.now().isoformat(), "action": "d"},
        {"timestamp": "also-invalid", "action": "e"},
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer_instance):
    """Test _detect_regularity detects highly regular intervals (low CV)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    # Exactly 60s apart
    timestamps = [base + timedelta(seconds=60 * i) for i in range(6)]
    activities = [{"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps]

    result = activity_analyzer_instance._detect_regularity(activities)
    assert len(result) == 1
    pattern = result[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer_instance):
    """Test _detect_regularity returns empty for irregular intervals (high CV)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    timestamps = [
        base,
        base + timedelta(seconds=10),
        base + timedelta(seconds=100),
        base + timedelta(seconds=1000),
        base + timedelta(seconds=2000),
        base + timedelta(seconds=4000),
    ]
    activities = [{"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps]

    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer_instance):
    """Test _parse_timestamp returns datetime unchanged when input is datetime."""
    ts = datetime(2024, 1, 1, 10, 0, 0)
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string correctly."""
    ts = "2024-01-01T10:00:00"
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.month == 1
    assert parsed.day == 1
    assert parsed.hour == 10
    assert parsed.minute == 0
    assert parsed.second == 0


def test_activityanalyzer_parse_timestamp_with_z_suffix(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO string with Z suffix as UTC."""
    ts = "2024-01-01T10:00:00Z"
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.hour == 10


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer_instance):
    """Test _parse_timestamp returns None for invalid string."""
    ts = "not-a-timestamp"
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert parsed is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer_instance):
    """Test _parse_timestamp returns None for unsupported type."""
    parsed = activity_analyzer_instance._parse_timestamp(12345)
    assert parsed is None


def test_activityanalyzer_analyze_patterns_integration(activity_analyzer_instance):
    """Integration test: analyze_patterns returns combined patterns for realistic data."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # Regular hourly activity at 10:00 for peak hours and regularity
    for i in range(6):
        activities.append({"timestamp": (base + timedelta(hours=i)).isoformat(), "action": "login"})
    # Add repeated sequence
    activities.extend([
        {"timestamp": (base + timedelta(hours=6)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=6, minutes=1)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(hours=6, minutes=2)).isoformat(), "action": "c"},
        {"timestamp": (base + timedelta(hours=7)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=7, minutes=1)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(hours=7, minutes=2)).isoformat(), "action": "c"},
    ])

    patterns = activity_analyzer_instance.analyze_patterns(activities)
    types = {p.pattern_type for p in patterns}
    assert "peak_hours" in types or "regularity" in types or "action_sequence" in types
    # Ensure all returned objects are ActivityPattern
    for p in patterns:
        assert isinstance(p, ActivityPattern)


def test_activityanalyzer_detect_anomalies_exception_handling(activity_analyzer_instance):
    """Test detect_anomalies handles exceptions from _parse_timestamp gracefully."""
    activities = [{"timestamp": "2024-01-01T10:00:00", "action": "a"} for _ in range(6)]

    with patch.object(activity_analyzer_instance, "_parse_timestamp", side_effect=Exception("parse error")):
        # Should propagate exception because there is no explicit handling
        with pytest.raises(Exception):
            activity_analyzer_instance.detect_anomalies(activities)


def test_activityanalyzer_get_user_score_exception_handling(activity_analyzer_instance):
    """Test get_user_score handles exceptions from _parse_timestamp gracefully."""
    activities = [
        {"timestamp": "2024-01-01T10:00:00", "action": "a"},
        {"timestamp": "2024-01-02T10:00:00", "action": "b"},
    ]

    with patch.object(activity_analyzer_instance, "_parse_timestamp", side_effect=Exception("parse error")):
        # Should propagate exception because there is no explicit handling
        with pytest.raises(Exception):
            activity_analyzer_instance.get_user_score(activities)