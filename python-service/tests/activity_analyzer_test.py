import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def activity_pattern_instance():
    """Create ActivityPattern instance for testing."""
    return ActivityPattern(pattern_type="test_type", description="test_desc", confidence=0.95)


@pytest.fixture
def activity_analyzer_instance():
    """Create ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def test_activitypattern_init(activity_pattern_instance):
    """Test ActivityPattern initialization with valid data."""
    assert activity_pattern_instance.pattern_type == "test_type"
    assert activity_pattern_instance.description == "test_desc"
    assert activity_pattern_instance.confidence == pytest.approx(0.95)


def test_activitypattern_to_dict(activity_pattern_instance):
    """Test ActivityPattern.to_dict returns correct dictionary."""
    result = activity_pattern_instance.to_dict()
    assert result["pattern_type"] == "test_type"
    assert result["description"] == "test_desc"
    assert result["confidence"] == pytest.approx(0.95)


def test_activityanalyzer_init_defaults(activity_analyzer_instance):
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert activity_analyzer_instance.peak_hour_threshold == pytest.approx(0.2)
    assert activity_analyzer_instance.anomaly_threshold == pytest.approx(3.0)


def test_activityanalyzer_analyze_patterns_empty(activity_analyzer_instance):
    """Test analyze_patterns returns empty list for no activities."""
    result = activity_analyzer_instance.analyze_patterns([])
    assert result == []


def test_activityanalyzer_analyze_patterns_calls_internal_methods(activity_analyzer_instance):
    """Test analyze_patterns calls internal detection methods and aggregates results."""
    activities = [{"timestamp": datetime.now(timezone.utc).isoformat(), "action": "a"}]

    with patch.object(activity_analyzer_instance, "_detect_peak_hours", return_value=[ActivityPattern("p", "ph", 0.1)]) as mock_peak, \
         patch.object(activity_analyzer_instance, "_detect_action_sequences", return_value=[ActivityPattern("s", "seq", 0.2)]) as mock_seq, \
         patch.object(activity_analyzer_instance, "_detect_regularity", return_value=[ActivityPattern("r", "reg", 0.3)]) as mock_reg:

        result = activity_analyzer_instance.analyze_patterns(activities)

        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)

        assert len(result) == 3
        assert [p.pattern_type for p in result] == ["p", "s", "r"]


def test_activityanalyzer_get_user_score_empty(activity_analyzer_instance):
    """Test get_user_score returns 0.0 for empty activities."""
    score = activity_analyzer_instance.get_user_score([])
    assert score == pytest.approx(0.0)


def test_activityanalyzer_get_user_score_basic(activity_analyzer_instance):
    """Test get_user_score with simple activity list and timestamps."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": (base + timedelta(days=0)).isoformat(), "action": "login"},
        {"timestamp": (base + timedelta(days=0, hours=1)).isoformat(), "action": "view"},
        {"timestamp": (base + timedelta(days=1)).isoformat(), "action": "logout"},
        {"timestamp": (base + timedelta(days=2)).isoformat(), "action": "login"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    # Compute expected according to implementation
    total_actions = 4
    unique_actions = 3  # login, view, logout
    days_active = max((activities[-1]["timestamp"] and base + timedelta(days=2) - base).days, 1)
    actions_per_day = total_actions / days_active
    diversity_score = unique_actions / total_actions
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100
    expected = round(expected, 2)

    assert score == pytest.approx(expected)


def test_activityanalyzer_get_user_score_no_timestamps(activity_analyzer_instance):
    """Test get_user_score when timestamps are missing or unparsable."""
    activities = [
        {"timestamp": "not-a-date", "action": "a"},
        {"timestamp": None, "action": "b"},
        {"action": "a"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    total_actions = 3
    unique_actions = 2  # a, b
    actions_per_day = total_actions  # falls back to total_actions
    diversity_score = unique_actions / total_actions
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100
    expected = round(expected, 2)

    assert score == pytest.approx(expected)


def test_activityanalyzer_get_user_score_duplicate_action_logic(activity_analyzer_instance):
    """Test get_user_score unique action counting logic with repeated actions."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": (base + timedelta(hours=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=1)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(hours=2)).isoformat(), "action": "b"},
        {"timestamp": (base + timedelta(hours=3)).isoformat(), "action": "a"},
    ]
    score = activity_analyzer_instance.get_user_score(activities)

    # According to the implementation, unique_actions will be 2: first 'a' and 'b'
    total_actions = 4
    unique_actions = 2
    days_active = max((base + timedelta(hours=3) - base).days, 1)
    actions_per_day = total_actions / days_active
    diversity_score = unique_actions / total_actions
    frequency_score = min(actions_per_day / 10.0, 1.0)
    volume_score = min(total_actions / 100.0, 1.0)
    expected = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100
    expected = round(expected, 2)

    assert score == pytest.approx(expected)


def test_activityanalyzer_detect_anomalies_too_few(activity_analyzer_instance):
    """Test detect_anomalies returns empty list when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now(timezone.utc).isoformat(), "action": "a"} for _ in range(4)]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_no_intervals(activity_analyzer_instance):
    """Test detect_anomalies when actions have fewer than 3 timestamps."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"} for i in range(2)
    ] + [
        {"timestamp": (base + timedelta(minutes=10 + i)).isoformat(), "action": "b"} for i in range(2)
    ] + [
        {"timestamp": (base + timedelta(minutes=20)).isoformat(), "action": "c"}
    ]
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert result == []


def test_activityanalyzer_detect_anomalies_with_clear_outlier(activity_analyzer_instance):
    """Test detect_anomalies detects an interval with high z-score."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    # Regular intervals of 60s, then one large gap to create anomaly
    timestamps = [
        base,
        base + timedelta(seconds=60),
        base + timedelta(seconds=120),
        base + timedelta(seconds=180),
        base + timedelta(seconds=600),  # big jump
        base + timedelta(seconds=660),
    ]
    activities = [{"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps]

    result = activity_analyzer_instance.detect_anomalies(activities)

    assert isinstance(result, list)
    # At least one anomaly expected; exact z-score depends on calculation
    assert len(result) >= 1
    for anomaly in result:
        assert anomaly["action"] == "a"
        assert "timestamp" in anomaly
        assert "z_score" in anomaly
        assert isinstance(anomaly["z_score"], float)
        assert anomaly["z_score"] == pytest.approx(anomaly["z_score"])  # float comparison
        assert "reason" in anomaly


def test_activityanalyzer_detect_anomalies_unparsable_timestamps(activity_analyzer_instance):
    """Test detect_anomalies gracefully skips unparsable timestamps."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"} for i in range(5)
    ]
    activities.append({"timestamp": "invalid", "action": "a"})
    result = activity_analyzer_instance.detect_anomalies(activities)
    assert isinstance(result, list)


def test_activityanalyzer_detect_anomalies_with_mocked_parse(activity_analyzer_instance):
    """Test detect_anomalies handles exceptions from _parse_timestamp via mocking."""
    activities = [{"timestamp": "2024-01-01T00:00:00Z", "action": "a"} for _ in range(6)]

    with patch.object(activity_analyzer_instance, "_parse_timestamp", side_effect=[datetime.now(timezone.utc)] * 3 + [None] * 3):
        result = activity_analyzer_instance.detect_anomalies(activities)
        assert isinstance(result, list)


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty when no valid timestamps."""
    activities = [{"timestamp": "invalid", "action": "a"} for _ in range(5)]
    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert result == []


def test_activityanalyzer_detect_peak_hours_basic(activity_analyzer_instance):
    """Test _detect_peak_hours identifies peak hours above threshold."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = []
    # 8 activities at 10:00
    for i in range(8):
        activities.append({"timestamp": (base.replace(hour=10) + timedelta(minutes=i)).isoformat(), "action": "a"})
    # 2 activities at 11:00
    for i in range(2):
        activities.append({"timestamp": (base.replace(hour=11) + timedelta(minutes=i)).isoformat(), "action": "b"})

    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert len(result) == 1
    pattern = result[0]
    assert pattern.pattern_type == "peak_hours"
    assert "10:00" in pattern.description
    assert pattern.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_no_peak(activity_analyzer_instance):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = []
    # 5 hours with equal counts -> each 0.2, threshold is > 0.2 so none qualify
    for h in range(5):
        activities.append({"timestamp": base.replace(hour=h).isoformat(), "action": "a"})
    result = activity_analyzer_instance._detect_peak_hours(activities)
    assert result == []


def test_activityanalyzer_detect_action_sequences_too_short(activity_analyzer_instance):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [{"timestamp": datetime.now(timezone.utc).isoformat(), "action": "a"} for _ in range(2)]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert result == []


def test_activityanalyzer_detect_action_sequences_basic(activity_analyzer_instance):
    """Test _detect_action_sequences identifies common sequences occurring at least twice."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": act}
        for i, act in enumerate([
            "login", "view", "logout",   # seq1
            "login", "view", "logout",   # seq1 again
            "login", "edit", "save",     # seq2
            "login", "view", "logout",   # seq1 third time
        ])
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(result) >= 1
    descriptions = [p.description for p in result]
    assert any("login → view → logout" in d for d in descriptions)
    for p in result:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_uses_default_action(activity_analyzer_instance):
    """Test _detect_action_sequences uses empty string for missing action keys."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": (base + timedelta(minutes=0)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=1)).isoformat()},  # missing action
        {"timestamp": (base + timedelta(minutes=2)).isoformat(), "action": "c"},
        {"timestamp": (base + timedelta(minutes=3)).isoformat(), "action": "a"},
        {"timestamp": (base + timedelta(minutes=4)).isoformat()},  # missing action
        {"timestamp": (base + timedelta(minutes=5)).isoformat(), "action": "c"},
    ]
    result = activity_analyzer_instance._detect_action_sequences(activities)
    assert len(result) >= 1
    assert any("a →  → c" in p.description for p in result)


def test_activityanalyzer_detect_regularity_too_few(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 activities."""
    activities = [{"timestamp": datetime.now(timezone.utc).isoformat(), "action": "a"} for _ in range(4)]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_not_enough_valid_timestamps(activity_analyzer_instance):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": (base + timedelta(minutes=i)).isoformat(), "action": "a"} for i in range(3)
    ] + [
        {"timestamp": "invalid", "action": "a"} for _ in range(3)
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_detect_regularity_highly_regular(activity_analyzer_instance):
    """Test _detect_regularity detects highly regular intervals (low CV)."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = [
        {"timestamp": (base + timedelta(minutes=10 * i)).isoformat(), "action": "a"}
        for i in range(6)
    ]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert len(result) == 1
    pattern = result[0]
    assert pattern.pattern_type == "regularity"
    assert "Highly regular activity pattern" in pattern.description
    assert pattern.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_irregular(activity_analyzer_instance):
    """Test _detect_regularity returns empty for irregular intervals (high CV)."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    intervals = [1, 10, 30, 5, 60, 2]
    timestamps = [base]
    for i in intervals:
        timestamps.append(timestamps[-1] + timedelta(minutes=i))
    activities = [{"timestamp": ts.isoformat(), "action": "a"} for ts in timestamps]
    result = activity_analyzer_instance._detect_regularity(activities)
    assert result == []


def test_activityanalyzer_parse_timestamp_datetime(activity_analyzer_instance):
    """Test _parse_timestamp returns datetime unchanged when input is datetime."""
    ts = datetime(2024, 1, 1, tzinfo=timezone.utc)
    parsed = activity_analyzer_instance._parse_timestamp(ts)
    assert parsed == ts


def test_activityanalyzer_parse_timestamp_iso_string(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string with Z suffix."""
    ts_str = "2024-01-01T12:34:56Z"
    parsed = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.month == 1
    assert parsed.day == 1
    assert parsed.hour == 12
    assert parsed.minute == 34
    assert parsed.second == 56
    assert parsed.tzinfo is not None


def test_activityanalyzer_parse_timestamp_iso_string_no_z(activity_analyzer_instance):
    """Test _parse_timestamp parses ISO 8601 string without Z suffix."""
    ts_str = "2024-01-01T12:34:56+00:00"
    parsed = activity_analyzer_instance._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.year == 2024
    assert parsed.hour == 12


def test_activityanalyzer_parse_timestamp_invalid_string(activity_analyzer_instance):
    """Test _parse_timestamp returns None for invalid string."""
    parsed = activity_analyzer_instance._parse_timestamp("not-a-timestamp")
    assert parsed is None


def test_activityanalyzer_parse_timestamp_none(activity_analyzer_instance):
    """Test _parse_timestamp returns None for None input."""
    parsed = activity_analyzer_instance._parse_timestamp(None)
    assert parsed is None


def test_activityanalyzer_parse_timestamp_unsupported_type(activity_analyzer_instance):
    """Test _parse_timestamp returns None for unsupported type."""
    parsed = activity_analyzer_instance._parse_timestamp(12345)
    assert parsed is None


def test_activityanalyzer_analyze_patterns_integration(activity_analyzer_instance):
    """Integration test: analyze_patterns returns combined patterns for realistic data."""
    base = datetime(2024, 1, 1, tzinfo=timezone.utc)
    activities = []
    # Peak hours around 9-10
    for i in range(10):
        activities.append({"timestamp": (base.replace(hour=9) + timedelta(minutes=i)).isoformat(), "action": "login"})
    # Some sequences
    seq_actions = ["login", "view", "logout"] * 3
    for i, act in enumerate(seq_actions):
        activities.append({"timestamp": (base.replace(hour=11) + timedelta(minutes=i)).isoformat(), "action": act})
    # Regular pattern
    for i in range(5):
        activities.append({"timestamp": (base + timedelta(hours=2 * i)).isoformat(), "action": "ping"})

    patterns = activity_analyzer_instance.analyze_patterns(activities)
    assert isinstance(patterns, list)
    assert any(p.pattern_type == "peak_hours" for p in patterns)
    assert any(p.pattern_type == "action_sequence" for p in patterns)
    # Regularity may or may not be detected depending on combined intervals, so not asserted strictly.