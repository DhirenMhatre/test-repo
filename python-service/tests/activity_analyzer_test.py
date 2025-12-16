import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Provide an ActivityAnalyzer instance for tests."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for timestamp generation."""
    return datetime(2024, 1, 1, 9, 0, 0)


def make_activity(action: str, ts: datetime):
    """Helper to create an activity dict with ISO timestamp string."""
    return {"action": action, "timestamp": ts.isoformat()}


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and dictionary conversion."""
    p = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.85)
    assert p.pattern_type == "peak_hours"
    assert p.description == "desc"
    assert p.confidence == 0.85

    d = p.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "desc",
        "confidence": 0.85,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp with datetime, ISO strings, Z suffix, and invalid values."""
    dt = datetime(2023, 5, 1, 12, 0, 0)
    assert analyzer._parse_timestamp(dt) == dt

    iso = "2023-05-01T12:00:00"
    parsed = analyzer._parse_timestamp(iso)
    assert parsed == datetime.fromisoformat(iso)

    iso_z = "2023-05-01T12:00:00Z"
    parsed_z = analyzer._parse_timestamp(iso_z)
    assert parsed_z == datetime.fromisoformat("2023-05-01T12:00:00+00:00")
    assert parsed_z.tzinfo is not None

    assert analyzer._parse_timestamp("not a date") is None
    assert analyzer._parse_timestamp(None) is None


def test_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours returns a pattern with aggregated peak hours."""
    activities = []
    # 3 at 09:00
    for i in range(3):
        activities.append(make_activity("a", base_time + timedelta(minutes=i)))
    # 3 at 10:00
    for i in range(3):
        activities.append(make_activity("a", base_time.replace(hour=10) + timedelta(minutes=i)))
    # 4 at 15:00
    for i in range(4):
        activities.append(make_activity("a", base_time.replace(hour=15) + timedelta(minutes=i)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert isinstance(p, ActivityPattern)
    assert p.pattern_type == "peak_hours"
    assert p.confidence == 0.85
    assert "High activity during hours: 09:00, 10:00, 15:00" in p.description


def test_detect_peak_hours_no_peaks(analyzer, base_time):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold (> 0.2)."""
    activities = []
    # 10 activities evenly across 5 hours -> each exactly 0.2, not strictly greater
    for h in range(5):
        for i in range(2):
            activities.append(make_activity("a", base_time.replace(hour=h) + timedelta(minutes=i)))

    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_detect_action_sequences_common(analyzer, base_time):
    """Test _detect_action_sequences detects common sequences occurring 2+ times."""
    actions = [
        "A", "B", "C",
        "D",
        "A", "B", "C",
        "E",
        "A", "B", "C",
    ]
    activities = [make_activity(act, base_time + timedelta(seconds=i)) for i, act in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert "Common sequence: A → B → C (occurred 3 times)" in p.description
    assert p.confidence == 0.75


def test_detect_action_sequences_insufficient(analyzer, base_time):
    """Test _detect_action_sequences requires at least 3 activities."""
    activities = [
        make_activity("A", base_time),
        make_activity("B", base_time + timedelta(seconds=1)),
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity detects highly regular intervals (low CV)."""
    # 6 timestamps at regular 10-second intervals
    activities = [make_activity("x", base_time + timedelta(seconds=10 * i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert p.confidence == 0.9
    assert "Highly regular activity pattern (CV: 0.00)" in p.description


def test_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty when intervals are irregular (CV >= 0.3)."""
    # Irregular intervals
    times = [0, 10, 30, 60, 100, 160]
    activities = [make_activity("x", base_time + timedelta(seconds=t)) for t in times]
    assert analyzer._detect_regularity(activities) == []


def test_detect_anomalies_too_few_activities(analyzer, base_time):
    """Test detect_anomalies returns empty when less than 5 activities present."""
    activities = [make_activity("login", base_time + timedelta(seconds=10 * i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_detect_anomalies_large_interval_flagged_default_threshold(analyzer, base_time):
    """Test detect_anomalies flags a large interval using default z-score threshold."""
    # We need N small intervals and 1 large interval; z-score for the outlier ~ sqrt(N)
    # Use N=10 small intervals (10s) and one large interval (1000s) to get z > 3.
    timestamps = [base_time]
    # 10 small intervals of 10s
    for _ in range(10):
        timestamps.append(timestamps[-1] + timedelta(seconds=10))
    # one large interval of 1000s
    timestamps.append(timestamps[-1] + timedelta(seconds=1000))

    activities = [make_activity("login", ts) for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "login"
    assert "Unusual interval" in anomaly["reason"]
    # The anomaly timestamp should correspond to the timestamp after the large interval
    assert anomaly["timestamp"] == timestamps[-1].isoformat()
    assert anomaly["z_score"] > 3.0


def test_detect_anomalies_groups_by_action_and_skips_short_actions(analyzer, base_time):
    """Test detect_anomalies handles multiple actions and skips groups with <3 timestamps."""
    # Action 'a' has enough timestamps; 'b' has too few.
    timestamps_a = [base_time]
    for _ in range(10):
        timestamps_a.append(timestamps_a[-1] + timedelta(seconds=10))
    timestamps_a.append(timestamps_a[-1] + timedelta(seconds=1000))
    activities = [make_activity("a", ts) for ts in timestamps_a]
    # Action b with only 2 timestamps (ignored)
    activities += [
        make_activity("b", base_time + timedelta(seconds=5)),
        make_activity("b", base_time + timedelta(seconds=15)),
    ]

    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) == 1
    assert anomalies[0]["action"] == "a"


def test_analyze_patterns_calls_detectors_and_aggregates(analyzer, base_time):
    """Test analyze_patterns aggregates results from private detection methods."""
    activities = [
        make_activity("A", base_time),
        make_activity("B", base_time + timedelta(seconds=1)),
        make_activity("C", base_time + timedelta(seconds=2)),
        make_activity("A", base_time + timedelta(seconds=3)),
        make_activity("B", base_time + timedelta(seconds=4)),
        make_activity("C", base_time + timedelta(seconds=5)),
    ]
    peak_patterns = [ActivityPattern("peak_hours", "desc1", 0.85)]
    seq_patterns = [ActivityPattern("action_sequence", "desc2", 0.75)]
    reg_patterns = [ActivityPattern("regularity", "desc3", 0.9)]

    with patch.object(analyzer, "_detect_peak_hours", return_value=peak_patterns) as mock_peak, \
         patch.object(analyzer, "_detect_action_sequences", return_value=seq_patterns) as mock_seq, \
         patch.object(analyzer, "_detect_regularity", return_value=reg_patterns) as mock_reg:

        result = analyzer.analyze_patterns(activities)

        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)

        # Result should be concatenation in order
        assert result == peak_patterns + seq_patterns + reg_patterns


def test_analyze_patterns_empty_input_returns_empty_and_skips_detectors(analyzer):
    """Test analyze_patterns returns empty list for empty input and does not call detectors."""
    with patch.object(analyzer, "_detect_peak_hours") as mock_peak, \
         patch.object(analyzer, "_detect_action_sequences") as mock_seq, \
         patch.object(analyzer, "_detect_regularity") as mock_reg:

        result = analyzer.analyze_patterns([])
        assert result == []
        mock_peak.assert_not_called()
        mock_seq.assert_not_called()
        mock_reg.assert_not_called()


def test_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list."""
    assert analyzer.get_user_score([]) == 0.0


def test_get_user_score_computation_with_timestamps(analyzer, base_time):
    """Test get_user_score computes expected score with timestamps spanning multiple days."""
    # Build 40 activities over 4 days (first to last)
    # Unique actions: 3 ('A', 'B', 'C') with respective counts 20, 10, 10.
    activities = []
    # 20 'A'
    for i in range(20):
        activities.append(make_activity("A", base_time + timedelta(minutes=i)))
    # 10 'B'
    for i in range(10):
        activities.append(make_activity("B", base_time + timedelta(days=2, minutes=i)))
    # 10 'C' with last at day 4
    for i in range(10):
        activities.append(make_activity("C", base_time + timedelta(days=4, minutes=i)))

    # Ensure first and last positions are correct for days calculation
    activities[0]["timestamp"] = (base_time).isoformat()
    activities[-1]["timestamp"] = (base_time + timedelta(days=4, minutes=9)).isoformat()

    score = analyzer.get_user_score(activities)

    # Expected:
    # total_actions = 40
    # unique_actions = 3
    # days_active = 4
    # actions_per_day = 10 -> frequency_score = 1.0
    # diversity_score = 3/40 = 0.075
    # volume_score = 40/100 = 0.4
    # final = (0.075*0.3 + 1.0*0.4 + 0.4*0.3)*100 = (0.0225 + 0.4 + 0.12)*100 = 54.25
    assert score == 54.25


def test_get_user_score_invalid_timestamps_use_total_actions_frequency(analyzer):
    """Test get_user_score uses total_actions as actions_per_day when timestamps cannot be parsed."""
    # 5 activities with invalid first and last timestamps
    activities = [{"action": f"A{i}", "timestamp": "invalid"} for i in range(5)]
    score = analyzer.get_user_score(activities)
    # total_actions = 5
    # unique_actions = 5 (all distinct)
    # actions_per_day = 5 -> frequency_score = min(5/10, 1) = 0.5
    # diversity_score = 1.0
    # volume_score = 0.05
    # final = (1.0*0.3 + 0.5*0.4 + 0.05*0.3)*100 = (0.3 + 0.2 + 0.015)*100 = 51.5
    assert score == 51.5


def test_get_user_score_caps_and_rounding_to_100(analyzer, base_time):
    """Test get_user_score caps scores leading to 100.0 when all components max out."""
    # 200 activities within the same day; all unique actions
    activities = [make_activity(f"A{i}", base_time + timedelta(seconds=i)) for i in range(200)]
    score = analyzer.get_user_score(activities)
    assert score == 100.0