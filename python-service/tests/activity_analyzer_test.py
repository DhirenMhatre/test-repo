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
    """Provide a base datetime for timestamp generation."""
    return datetime(2024, 1, 1, 0, 0, 0)


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and serialization to dict."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="High activity at 09:00", confidence=0.85)
    d = pattern.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "High activity at 09:00",
        "confidence": 0.85,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default initialization values."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_analyze_patterns_empty_returns_empty(analyzer):
    """Test analyze_patterns returns empty list for empty activities and does not call detectors."""
    activities = []

    with patch.object(ActivityAnalyzer, "_detect_peak_hours") as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences") as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity") as mock_reg:
        result = analyzer.analyze_patterns(activities)
        assert result == []
        mock_peak.assert_not_called()
        mock_seq.assert_not_called()
        mock_reg.assert_not_called()


def test_activityanalyzer_analyze_patterns_combines_detector_results(analyzer):
    """Test analyze_patterns combines results from all detector methods."""
    activities = [{"action": "A", "timestamp": datetime(2024, 1, 1, 9)}]

    p1 = ActivityPattern("peak_hours", "desc1", 0.85)
    p2 = ActivityPattern("action_sequence", "desc2", 0.75)
    p3 = ActivityPattern("regularity", "desc3", 0.9)

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=[p1]) as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[p2]) as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[p3]) as mock_reg:
        result = analyzer.analyze_patterns(activities)
        assert result == [p1, p2, p3]

        # verify calls with correct args (self, activities)
        assert mock_peak.call_count == 1
        assert mock_seq.call_count == 1
        assert mock_reg.call_count == 1

        args, _ = mock_peak.call_args
        assert args[0] is analyzer
        assert args[1] == activities

        args, _ = mock_seq.call_args
        assert args[0] is analyzer
        assert args[1] == activities

        args, _ = mock_reg.call_args
        assert args[0] is analyzer
        assert args[1] == activities


def test_activityanalyzer_detect_anomalies_finds_interval_outlier(analyzer, base_time):
    """Test detect_anomalies identifies large interval anomaly for an action."""
    # Build 21 timestamps for 'click' with 19 intervals of 60s and one large interval
    timestamps = [base_time]
    for i in range(1, 20):
        timestamps.append(timestamps[-1] + timedelta(seconds=60))
    # Large gap to create an anomaly
    timestamps.append(timestamps[-1] + timedelta(seconds=20000))

    activities = [{"action": "click", "timestamp": ts} for ts in timestamps]
    # Add additional activities for other actions to ensure overall list length >= 5
    activities += [
        {"action": "view", "timestamp": base_time + timedelta(days=1)},
        {"action": "view", "timestamp": base_time + timedelta(days=2)},
    ]

    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) >= 1
    outliers = [a for a in anomalies if a["action"] == "click"]
    assert len(outliers) >= 1
    # Expect anomaly on the last timestamp of the big interval
    expected_ts = timestamps[-1].isoformat()
    assert any(a["timestamp"] == expected_ts for a in outliers)
    assert all(a["z_score"] > analyzer.anomaly_threshold for a in outliers)
    assert all("Unusual interval" in a["reason"] for a in outliers)


def test_activityanalyzer_detect_anomalies_insufficient_data_returns_empty(analyzer, base_time):
    """Test detect_anomalies returns empty list when there is insufficient data."""
    # Fewer than 5 activities in total
    activities = [
        {"action": "click", "timestamp": base_time},
        {"action": "click", "timestamp": base_time + timedelta(seconds=60)},
        {"action": "click", "timestamp": base_time + timedelta(seconds=120)},
        {"action": "view", "timestamp": base_time + timedelta(seconds=180)},
    ]
    assert analyzer.detect_anomalies(activities) == []

    # Enough total but less than 3 timestamps for a given action
    activities = [
        {"action": "click", "timestamp": base_time},
        {"action": "click", "timestamp": base_time + timedelta(seconds=60)},
        {"action": "view", "timestamp": base_time + timedelta(seconds=120)},
        {"action": "view", "timestamp": base_time + timedelta(seconds=180)},
        {"action": "view", "timestamp": base_time + timedelta(seconds=240)},
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_zero_std_dev_no_anomaly(analyzer, base_time):
    """Test detect_anomalies handles zero std deviation safely and returns no anomalies."""
    # For 'click', intervals are identical, so std_dev = 0; should not create anomalies
    clicks = [
        {"action": "click", "timestamp": base_time + timedelta(seconds=i * 60)}
        for i in range(4 + 1)  # 5 timestamps -> 4 intervals, all 60s
    ]
    # Ensure total activities >= 5 by adding other actions
    others = [
        {"action": "view", "timestamp": base_time + timedelta(days=1)},
        {"action": "view", "timestamp": base_time + timedelta(days=2)},
    ]
    activities = clicks + others
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_get_user_score_with_valid_dates(analyzer, base_time):
    """Test get_user_score calculates expected score with valid timestamps."""
    # total_actions = 10; unique_actions = 4; days_active = 2 -> actions_per_day = 5
    # diversity_score = 4/10 = 0.4
    # frequency_score = 5/10 = 0.5
    # volume_score = 10/100 = 0.1
    # final = (0.4*0.3 + 0.5*0.4 + 0.1*0.3)*100 = (0.12 + 0.2 + 0.03)*100 = 35.0
    actions = ["a1", "a2", "a3", "a4", "a1", "a2", "a3", "a4", "a1", "a2"]
    activities = []
    for idx, action in enumerate(actions):
        if idx == 0:
            ts = base_time
        elif idx == len(actions) - 1:
            ts = base_time + timedelta(days=2)
        else:
            ts = base_time + timedelta(hours=idx)
        activities.append({"action": action, "timestamp": ts})

    score = analyzer.get_user_score(activities)
    assert score == 35.0


def test_activityanalyzer_get_user_score_with_invalid_timestamps(analyzer):
    """Test get_user_score handles invalid timestamps by using total actions for frequency."""
    # total_actions = 5; unique_actions = 1
    # frequency_score = min(5/10,1) = 0.5
    # volume_score = min(5/100,1) = 0.05
    # diversity_score = 1/5 = 0.2
    # final = (0.2*0.3 + 0.5*0.4 + 0.05*0.3)*100 = 27.5
    activities = [{"action": "only", "timestamp": "not-a-date"} for _ in range(5)]
    score = analyzer.get_user_score(activities)
    assert score == 27.5


def test_activityanalyzer_detect_peak_hours_identifies_hours(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    activities = []
    # 3 at 09:00, 3 at 10:00, 4 at 11:00 => all above 0.2 threshold
    for _ in range(3):
        activities.append({"action": "a", "timestamp": base_time.replace(hour=9)})
    for _ in range(3):
        activities.append({"action": "b", "timestamp": base_time.replace(hour=10)})
    for _ in range(4):
        activities.append({"action": "c", "timestamp": base_time.replace(hour=11)})

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "09:00" in p.description
    assert "10:00" in p.description
    assert "11:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_below_threshold_returns_empty(analyzer, base_time):
    """Test _detect_peak_hours returns empty when no hour exceeds the threshold."""
    activities = []
    # 5 unique hours, each 1 out of 5 -> exactly 0.2 (not greater), so none qualify
    for i in range(5):
        activities.append({"action": "x", "timestamp": base_time.replace(hour=i)})

    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_detects_common_sequence(analyzer, base_time):
    """Test _detect_action_sequences identifies a repeated 3-action sequence."""
    actions = ["A", "B", "C", "A", "B", "C"]
    activities = [{"action": a, "timestamp": base_time + timedelta(minutes=i)} for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "A → B → C" in p.description
    assert "(occurred 2 times)" in p.description
    assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_no_repetition_returns_empty(analyzer, base_time):
    """Test _detect_action_sequences returns empty when sequences do not repeat."""
    actions = ["A", "B", "C", "D", "E"]
    activities = [{"action": a, "timestamp": base_time + timedelta(minutes=i)} for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert patterns == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity identifies highly regular activity patterns."""
    # 6 timestamps, each 60s apart -> zero variance -> CV 0.0
    activities = [{"action": "a", "timestamp": base_time + timedelta(seconds=60 * i)} for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV: 0.00" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular_returns_empty(analyzer, base_time):
    """Test _detect_regularity returns empty when pattern is not regular."""
    # Irregular intervals to increase CV
    times = [0, 60, 300, 900, 2100, 4320]
    activities = [{"action": "a", "timestamp": base_time + timedelta(seconds=t)} for t in times]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_parse_timestamp_supports_datetime_and_iso_z(analyzer, base_time):
    """Test _parse_timestamp with datetime, ISO string with 'Z', and invalid values."""
    # datetime instance
    assert analyzer._parse_timestamp(base_time) == base_time

    # ISO string with Z (UTC)
    ts_str_z = "2024-01-01T12:34:56Z"
    parsed_z = analyzer._parse_timestamp(ts_str_z)
    assert isinstance(parsed_z, datetime)
    assert parsed_z.isoformat().endswith("+00:00")

    # ISO string without Z (naive)
    ts_str = "2024-01-01T12:34:56"
    parsed = analyzer._parse_timestamp(ts_str)
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is None

    # Invalid string returns None
    assert analyzer._parse_timestamp("not-a-timestamp") is None

    # Non-string, non-datetime returns None
    assert analyzer._parse_timestamp(12345) is None


def test_activityanalyzer_methods_handle_invalid_timestamps_gracefully(analyzer):
    """Test methods handle invalid timestamps without raising exceptions."""
    activities = [
        {"action": "a", "timestamp": "invalid-1"},
        {"action": "b", "timestamp": "invalid-2"},
        {"action": "c", "timestamp": "invalid-3"},
        {"action": "d", "timestamp": "invalid-4"},
        {"action": "e", "timestamp": "invalid-5"},
    ]

    # Should not raise
    assert analyzer._detect_peak_hours(activities) == []
    assert analyzer._detect_regularity(activities) == []

    # detect_anomalies should handle gracefully and return empty because timestamps are invalid
    assert analyzer.detect_anomalies(activities) == []