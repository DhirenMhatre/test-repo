import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide a fresh ActivityAnalyzer instance for each test."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Base datetime for constructing predictable timestamps."""
    return datetime(2023, 1, 1, 10, 0, 0)


def make_activity(ts, action):
    return {"timestamp": ts, "action": action}


def test_activitypattern_initialization_and_to_dict():
    """Test ActivityPattern initialization and to_dict output."""
    pat = ActivityPattern("peak_hours", "High activity during hours: 09:00", 0.85)
    assert pat.pattern_type == "peak_hours"
    assert pat.description == "High activity during hours: 09:00"
    assert pat.confidence == 0.85

    d = pat.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "High activity during hours: 09:00",
        "confidence": 0.85,
    }


def test_activityanalyzer_initialization_defaults(analyzer):
    """Test ActivityAnalyzer default configuration."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_valid_variants(analyzer):
    """Test _parse_timestamp with datetime and ISO string inputs."""
    dt = datetime(2023, 1, 1, 0, 0, 0)
    assert analyzer._parse_timestamp(dt) == dt

    iso_str = "2023-01-01T00:00:00"
    parsed = analyzer._parse_timestamp(iso_str)
    assert isinstance(parsed, datetime)
    assert parsed == datetime(2023, 1, 1, 0, 0, 0)

    iso_z = "2023-01-01T00:00:00Z"
    parsed_z = analyzer._parse_timestamp(iso_z)
    assert parsed_z is not None
    # Ensure parsing doesn't crash and returns a datetime
    assert isinstance(parsed_z, datetime)


def test_activityanalyzer_parse_timestamp_invalid(analyzer):
    """Test _parse_timestamp handles invalid inputs without raising exceptions."""
    assert analyzer._parse_timestamp("not-a-date") is None
    assert analyzer._parse_timestamp(12345) is None
    class Dummy:
        pass
    assert analyzer._parse_timestamp(Dummy()) is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold and formats description."""
    activities = []
    # 3 at 09:00
    for i in range(3):
        activities.append(make_activity(base_time.replace(hour=9) + timedelta(minutes=i), "A"))
    # 3 at 10:00
    for i in range(3):
        activities.append(make_activity(base_time.replace(hour=10) + timedelta(minutes=i), "B"))
    # 2 at 11:00
    for i in range(2):
        activities.append(make_activity(base_time.replace(hour=11) + timedelta(minutes=i), "C"))
    # 2 at 12:00
    for i in range(2):
        activities.append(make_activity(base_time.replace(hour=12) + timedelta(minutes=i), "D"))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert isinstance(pat, ActivityPattern)
    assert pat.pattern_type == "peak_hours"
    assert "High activity during hours: 09:00, 10:00" in pat.description
    assert pat.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when timestamps are invalid."""
    activities = [
        {"timestamp": "invalid", "action": "A"},
        {"timestamp": None, "action": "B"},
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_min_length(analyzer, base_time):
    """Test _detect_action_sequences returns empty for fewer than 3 activities."""
    activities = [
        make_activity(base_time, "A"),
        make_activity(base_time + timedelta(minutes=1), "B"),
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_action_sequences_top3(analyzer, base_time):
    """Test _detect_action_sequences returns up to top 3 frequent sequences with counts."""
    # Create actions repeating to yield 3 common sequences: ABC (3x), BCA (2x), CAB (2x)
    actions = list("ABCABCABC")
    activities = [
        make_activity(base_time + timedelta(seconds=60 * i), action)
        for i, action in enumerate(actions)
    ]
    patterns = analyzer._detect_action_sequences(activities)
    # Should include 3 patterns
    assert len(patterns) == 3
    texts = [p.description for p in patterns]
    assert "Common sequence: A → B → C (occurred 3 times)" in texts
    assert any("Common sequence: B → C → A (occurred 2 times)" in t for t in texts)
    assert any("Common sequence: C → A → B (occurred 2 times)" in t for t in texts)
    assert all(p.pattern_type == "action_sequence" for p in patterns)
    assert all(p.confidence == 0.75 for p in patterns)


def test_activityanalyzer_detect_regularity_regular(analyzer, base_time):
    """Test _detect_regularity identifies highly regular intervals."""
    activities = [
        make_activity(base_time + timedelta(seconds=60 * i), "A")
        for i in range(6)
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular_or_insufficient(analyzer, base_time):
    """Test _detect_regularity returns empty for irregular or insufficient activity."""
    # Insufficient activities
    activities_insufficient = [
        make_activity(base_time + timedelta(seconds=60 * i), "A")
        for i in range(4)
    ]
    assert analyzer._detect_regularity(activities_insufficient) == []

    # Irregular intervals
    ts = [base_time]
    for inc in [30, 90, 10, 300, 45]:
        ts.append(ts[-1] + timedelta(seconds=inc))
    activities_irregular = [make_activity(t, "A") for t in ts]
    assert analyzer._detect_regularity(activities_irregular) == []


def test_activityanalyzer_analyze_patterns_calls_internal_detectors(analyzer):
    """Test analyze_patterns aggregates results from internal detectors and calls them."""
    activities = [{"timestamp": datetime.now(), "action": "X"} for _ in range(10)]
    mock_peak = [ActivityPattern("peak_hours", "mock peak", 0.85)]
    mock_seq = [ActivityPattern("action_sequence", "mock seq", 0.75)]
    mock_reg = [ActivityPattern("regularity", "mock reg", 0.9)]
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as p1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as p2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as p3:
        patterns = analyzer.analyze_patterns(activities)
        assert patterns == mock_peak + mock_seq + mock_reg
        p1.assert_called_once_with(activities)
        p2.assert_called_once_with(activities)
        p3.assert_called_once_with(activities)


def test_activityanalyzer_analyze_patterns_empty_input(analyzer):
    """Test analyze_patterns returns empty list for empty activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_basic_same_day(analyzer, base_time):
    """Test get_user_score computation with all timestamps on the same day."""
    # 10 actions, 5 unique
    actions = ["A", "B", "C", "D", "E", "A", "B", "C", "D", "E"]
    activities = [
        make_activity(base_time + timedelta(minutes=i), act)
        for i, act in enumerate(actions)
    ]
    score = analyzer.get_user_score(activities)
    # diversity_score = 5/10 = 0.5
    # frequency_score = min(10/10, 1.0) = 1.0
    # volume_score = min(10/100, 1.0) = 0.1
    # final = (0.5*0.3 + 1.0*0.4 + 0.1*0.3) * 100 = 58.0
    assert score == 58.0


def test_activityanalyzer_get_user_score_multi_day(analyzer, base_time):
    """Test get_user_score across multiple days uses days delta."""
    # 20 actions over 5 days, 4 unique actions
    actions = ["A", "B", "C", "D"] * 5
    activities = []
    for i, act in enumerate(actions):
        ts = base_time + timedelta(days=i // 4)  # 4 per day
        activities.append(make_activity(ts, act))
    # Ensure first and last explicitly span 5 days
    activities[0]["timestamp"] = base_time
    activities[-1]["timestamp"] = base_time + timedelta(days=5)
    score = analyzer.get_user_score(activities)
    # diversity = 4/20 = 0.2; actions/day = 20/5 = 4 => freq=0.4; volume=0.2
    # final = (0.2*0.3 + 0.4*0.4 + 0.2*0.3)*100 = 28.0
    assert score == 28.0


def test_activityanalyzer_get_user_score_invalid_timestamps(analyzer):
    """Test get_user_score handles unparseable timestamps gracefully."""
    activities = [{"timestamp": "invalid", "action": f"A{i}"} for i in range(5)]
    score = analyzer.get_user_score(activities)
    # diversity=1.0 (all unique), frequency=min(5/10,1)=0.5, volume=0.05 -> (0.3 + 0.2 + 0.015)*100 = 51.5
    assert score == 51.5


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_detect_anomalies_minimum_activities(analyzer, base_time):
    """Test detect_anomalies returns empty when there are fewer than 5 activities."""
    activities = [make_activity(base_time + timedelta(minutes=i), "A") for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_no_std_dev(analyzer, base_time):
    """Test detect_anomalies does not flag anomalies when intervals have zero std dev."""
    # Equal intervals for 'A'
    ts = [base_time + timedelta(seconds=60 * i) for i in range(6)]
    activities = [make_activity(t, "A") for t in ts]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_flags_outlier(analyzer, base_time):
    """Test detect_anomalies flags an interval with high z-score."""
    # Build timestamps for action 'A' with 10 intervals of 10s and one interval of 1000s
    ts = [base_time]
    for _ in range(10):
        ts.append(ts[-1] + timedelta(seconds=10))
    ts.append(ts[-1] + timedelta(seconds=1000))
    activities = [make_activity(t, "A") for t in ts]
    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "A"
    assert anomaly["timestamp"] == ts[-1].isoformat()
    # Check z-score rounded to 2 decimals
    assert isinstance(anomaly["z_score"], float)
    assert anomaly["z_score"] >= 3.0
    assert "Unusual interval" in anomaly["reason"]


def test_activityanalyzer_detect_anomalies_multiple_actions(analyzer, base_time):
    """Test detect_anomalies processes actions independently."""
    # Action A - normal
    ts_a = [base_time + timedelta(seconds=30 * i) for i in range(6)]
    # Action B - one outlier
    ts_b = [base_time + timedelta(seconds=20 * i) for i in range(10)]
    ts_b.append(ts_b[-1] + timedelta(seconds=1000))
    activities = [make_activity(t, "A") for t in ts_a] + [make_activity(t, "B") for t in ts_b]
    anomalies = analyzer.detect_anomalies(activities)
    # Expect one anomaly for B
    assert len(anomalies) == 1
    assert anomalies[0]["action"] == "B"


def test_activityanalyzer_analyze_patterns_integration(analyzer, base_time):
    """Integration test: analyze_patterns returns aggregated patterns based on data."""
    # 7 events, equal spacing, all within same hour, action sequence ABC D ABC
    actions = ["A", "B", "C", "D", "A", "B", "C"]
    activities = [
        make_activity(base_time + timedelta(seconds=60 * i), actions[i])
        for i in range(len(actions))
    ]
    patterns = analyzer.analyze_patterns(activities)
    types = [p.pattern_type for p in patterns]
    assert "peak_hours" in types
    assert "action_sequence" in types
    assert "regularity" in types


def test_activityanalyzer_analyze_patterns_uses_mocks(analyzer):
    """Test analyze_patterns uses mocked detector methods to simulate exceptions and behavior."""
    activities = [{"timestamp": datetime.now(), "action": "X"} for _ in range(6)]
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", side_effect=[[]]) as mock_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=[]) as mock_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=[]) as mock_reg:
        result = analyzer.analyze_patterns(activities)
        assert result == []
        mock_peak.assert_called_once()
        mock_seq.assert_called_once()
        mock_reg.assert_called_once()