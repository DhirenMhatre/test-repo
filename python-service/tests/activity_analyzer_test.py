import pytest
from unittest.mock import patch

from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide a fresh ActivityAnalyzer instance for each test."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a deterministic base datetime for timestamp calculations."""
    return datetime(2024, 1, 1, 9, 0, 0)


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict serialization."""
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
    """Test ActivityAnalyzer initialization sets default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_various_inputs(analyzer):
    """Test _parse_timestamp handles datetime, ISO strings with Z, and invalid strings."""
    dt = datetime(2024, 1, 1, 0, 0, 0)
    assert analyzer._parse_timestamp(dt) == dt

    iso_z = "2024-01-01T00:00:00Z"
    parsed = analyzer._parse_timestamp(iso_z)
    assert parsed is not None
    assert parsed.isoformat().endswith("+00:00")

    invalid = "not-a-timestamp"
    assert analyzer._parse_timestamp(invalid) is None

    assert analyzer._parse_timestamp(None) is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies multiple peak hours."""
    activities = []
    # 5 activities at 09:00
    for i in range(5):
        activities.append({"action": "a", "timestamp": base_time + timedelta(minutes=i)})
    # 5 activities at 10:00
    for i in range(5):
        activities.append({"action": "a", "timestamp": base_time.replace(hour=10) + timedelta(minutes=i)})

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "High activity during hours:" in p.description
    assert "09:00" in p.description
    assert "10:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_peak(analyzer, base_time):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold."""
    activities = []
    # 24 activities, one per hour -> each hour below 0.2 threshold
    for h in range(24):
        activities.append({"action": "a", "timestamp": base_time.replace(hour=h)})

    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_ignores_invalid_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when timestamps are invalid."""
    activities = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "a", "timestamp": None},
        {"action": "a"},  # missing timestamp
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_basic(analyzer, base_time):
    """Test _detect_action_sequences identifies top repeating sequences (up to 3)."""
    # Build actions that create three repeating sequences: A→B→C, D→E→F, G→H→I each occurs 2 times.
    actions = ["A", "B", "C", "A", "B", "C", "D", "E", "F", "D", "E", "F", "G", "H", "I", "G", "H", "I"]
    activities = [{"action": act, "timestamp": base_time + timedelta(seconds=i)} for i, act in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    assert 1 <= len(patterns) <= 3  # should be up to 3 patterns
    descs = [p.description for p in patterns]
    # Ensure the three expected repeating sequences appear
    assert any("A → B → C" in d and "occurred 2 times" in d for d in descs)
    assert any("D → E → F" in d and "occurred 2 times" in d for d in descs)
    assert any("G → H → I" in d and "occurred 2 times" in d for d in descs)
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert p.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_insufficient_activities(analyzer):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [{"action": "A", "timestamp": datetime(2024, 1, 1, 0, 0, 0)}]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity returns a pattern for highly regular intervals."""
    # 6 timestamps at consistent 60s intervals
    activities = [{"action": "a", "timestamp": base_time + timedelta(seconds=60 * i)} for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern (CV:" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty for irregular activity."""
    # Irregular intervals
    offsets = [0, 60, 240, 360, 660, 900]
    activities = [{"action": "a", "timestamp": base_time + timedelta(seconds=s)} for s in offsets]
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_detect_anomalies_insufficient(analyzer, base_time):
    """Test detect_anomalies returns empty when there are fewer than 5 activities overall."""
    activities = [{"action": "login", "timestamp": base_time + timedelta(seconds=10 * i)} for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_flags_large_gap(analyzer, base_time):
    """Test detect_anomalies flags a large interval as an anomaly with z_score > threshold."""
    # Build 12 timestamps for 'login': 11 intervals with 10 small (60s) and 1 big (5000s)
    timestamps = [base_time]
    for i in range(10):
        timestamps.append(timestamps[-1] + timedelta(seconds=60))
    # Add a large gap
    timestamps.append(timestamps[-1] + timedelta(seconds=5000))
    # Optionally one more small interval
    timestamps.append(timestamps[-1] + timedelta(seconds=60))

    activities = [{"action": "login", "timestamp": ts} for ts in timestamps]
    # Add another action with insufficient timestamps to ensure it's ignored
    activities += [{"action": "click", "timestamp": base_time + timedelta(seconds=5)}]

    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) >= 1
    # Only intervals for 'login' should be considered, find the anomaly for 'login'
    login_anomalies = [a for a in anomalies if a["action"] == "login"]
    assert len(login_anomalies) >= 1
    a = login_anomalies[0]
    assert a["z_score"] > analyzer.anomaly_threshold
    assert a["z_score"] == pytest.approx(3.16, abs=0.01)
    assert a["reason"].startswith("Unusual interval:")
    # The timestamp should be the end of the large interval
    # The large interval ends at timestamps[11] (after adding the large gap)
    assert a["timestamp"] == timestamps[11].isoformat()


def test_activityanalyzer_analyze_patterns_calls_internal_methods(analyzer):
    """Test analyze_patterns aggregates results from internal detectors and calls them."""
    activities = [{"action": "a", "timestamp": datetime(2024, 1, 1, 0, 0, 0)}]
    peak_ret = [ActivityPattern("peak_hours", "peak", 0.85)]
    seq_ret = [ActivityPattern("action_sequence", "seq", 0.75)]
    reg_ret = [ActivityPattern("regularity", "reg", 0.9)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=peak_ret) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=seq_ret) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=reg_ret) as m_reg:
        result = analyzer.analyze_patterns(activities)

        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)

        # The result should be concatenation in the order: peak, sequences, regularity
        assert result == peak_ret + seq_ret + reg_ret


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for empty input."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_timestamps_and_diversity(analyzer, base_time):
    """Test get_user_score with valid timestamps and all unique actions."""
    activities = []
    # 10 unique actions over 9 days (actions_per_day ~ 1.11)
    for i in range(10):
        activities.append({
            "action": f"act_{i}",
            "timestamp": base_time + timedelta(days=i)
        })
    score = analyzer.get_user_score(activities)
    # Expected calculation:
    # diversity = 10/10 = 1.0
    # days_active = 9 -> actions_per_day = 10/9 ~= 1.111... -> frequency = 0.1111
    # volume = 10/100 = 0.1
    # final = (1.0*0.3 + 0.1111*0.4 + 0.1*0.3)*100 = ~37.44
    assert score == pytest.approx(37.44, abs=0.01)


def test_activityanalyzer_get_user_score_duplicate_bug_behavior(analyzer, base_time):
    """Test get_user_score with duplicate actions reflects current unique count logic."""
    # Actions: A, A, B, B on same day
    activities = [
        {"action": "A", "timestamp": base_time + timedelta(minutes=0)},
        {"action": "A", "timestamp": base_time + timedelta(minutes=1)},
        {"action": "B", "timestamp": base_time + timedelta(minutes=2)},
        {"action": "B", "timestamp": base_time + timedelta(minutes=3)},
    ]
    score = analyzer.get_user_score(activities)
    # With current logic, unique_actions will count each occurrence (4),
    # diversity = 4/4 = 1.0; frequency = 4/10 = 0.4; volume = 4/100 = 0.04
    # final = (1.0*0.3 + 0.4*0.4 + 0.04*0.3)*100 = 47.2
    assert score == pytest.approx(47.2, abs=0.001)


def test_activityanalyzer_get_user_score_missing_timestamps(analyzer):
    """Test get_user_score falls back to total_actions for frequency when timestamps invalid."""
    activities = [{"action": f"act_{i}", "timestamp": "invalid"} for i in range(5)]
    score = analyzer.get_user_score(activities)
    # diversity = 5/5 = 1.0; frequency = 5/10 = 0.5; volume = 5/100 = 0.05
    # final = (0.3 + 0.2 + 0.015)*100 = 51.5
    assert score == pytest.approx(51.5, abs=0.001)