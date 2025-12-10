import pytest
from unittest.mock import patch
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityAnalyzer, ActivityPattern


@pytest.fixture
def analyzer():
    """Provide a fresh ActivityAnalyzer instance for each test."""
    return ActivityAnalyzer()


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict serialization."""
    pattern = ActivityPattern(pattern_type="peak_hours", description="High activity", confidence=0.85)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "High activity"
    assert pattern.confidence == 0.85

    d = pattern.to_dict()
    assert d == {
        "pattern_type": "peak_hours",
        "description": "High activity",
        "confidence": 0.85,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default initialization values."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants_and_exception(analyzer, monkeypatch):
    """Test _parse_timestamp with datetime, ISO string, invalid string, and exception handling."""
    dt = datetime(2024, 1, 1, 12, 0, 0)
    # Pass-through datetime
    assert analyzer._parse_timestamp(dt) == dt

    # Valid ISO string with Z
    parsed = analyzer._parse_timestamp("2024-01-01T12:00:00Z")
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is not None  # should be timezone-aware due to +00:00 replacement

    # Valid ISO string with explicit offset
    parsed2 = analyzer._parse_timestamp("2024-01-01T12:00:00+00:00")
    assert isinstance(parsed2, datetime)
    assert parsed2.tzinfo is not None

    # Invalid string returns None
    assert analyzer._parse_timestamp("not-a-timestamp") is None

    # Exception in fromisoformat is handled and returns None
    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=ValueError):
        assert analyzer._parse_timestamp("2024-01-01T12:00:00") is None


def test_activityanalyzer_detect_peak_hours_identifies_hours(analyzer):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 3 activities at 10:xx
    for i in range(3):
        activities.append({"action": "a", "timestamp": base + timedelta(minutes=i)})
    # 3 activities at 11:xx
    for i in range(3):
        activities.append({"action": "a", "timestamp": base.replace(hour=11) + timedelta(minutes=i)})
    # 4 activities at various other hours
    activities.append({"action": "a", "timestamp": base.replace(hour=9)})
    activities.append({"action": "a", "timestamp": base.replace(hour=12)})
    activities.append({"action": "a", "timestamp": base.replace(hour=13)})
    activities.append({"action": "a", "timestamp": base.replace(hour=14)})

    # total = 10; 10:00 has 3 -> 30% and 11:00 has 3 -> 30%, both > 20%
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert isinstance(pat, ActivityPattern)
    assert pat.pattern_type == "peak_hours"
    assert "10:00" in pat.description
    assert "11:00" in pat.description
    assert pat.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when no valid timestamps."""
    activities = [{"action": "a", "timestamp": "invalid-ts"} for _ in range(5)]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_common_sequence(analyzer):
    """Test _detect_action_sequences detects frequent 3-step sequences."""
    activities = [
        {"action": "A", "timestamp": datetime(2024, 1, 1, 10, 0, 0)},
        {"action": "B", "timestamp": datetime(2024, 1, 1, 10, 1, 0)},
        {"action": "C", "timestamp": datetime(2024, 1, 1, 10, 2, 0)},
        {"action": "D", "timestamp": datetime(2024, 1, 1, 10, 3, 0)},
        {"action": "A", "timestamp": datetime(2024, 1, 1, 10, 4, 0)},
        {"action": "B", "timestamp": datetime(2024, 1, 1, 10, 5, 0)},
        {"action": "C", "timestamp": datetime(2024, 1, 1, 10, 6, 0)},
    ]
    # Sequence (A,B,C) occurs twice
    patterns = analyzer._detect_action_sequences(activities)
    assert patterns
    found = any("Common sequence: A → B → C (occurred 2 times)" in p.description for p in patterns)
    assert found
    assert all(p.pattern_type == "action_sequence" for p in patterns)


def test_activityanalyzer_detect_action_sequences_insufficient_length(analyzer):
    """Test _detect_action_sequences returns empty when fewer than 3 activities."""
    activities = [
        {"action": "A", "timestamp": datetime(2024, 1, 1, 10, 0, 0)},
        {"action": "B", "timestamp": datetime(2024, 1, 1, 10, 1, 0)},
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer):
    """Test _detect_regularity returns a pattern for highly regular intervals."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    for i in range(6):
        activities.append({"action": "a", "timestamp": base + timedelta(minutes=10 * i)})
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "regularity"
    assert "CV: 0.00" in pat.description
    assert pat.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer):
    """Test _detect_regularity returns empty for irregular intervals."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    intervals = [1, 5, 2, 20, 3, 7]  # irregular
    activities = []
    t = base
    for inc in intervals:
        t = t + timedelta(minutes=inc)
        activities.append({"action": "a", "timestamp": t})
    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_analyze_patterns_combines_results_and_calls_helpers(analyzer):
    """Test analyze_patterns orchestrates helper methods and combines their outputs."""
    activities = [{"action": "x", "timestamp": datetime(2024, 1, 1, 0, 0, 0)} for _ in range(10)]

    fake_peak = [ActivityPattern("peak_hours", "peak", 0.85)]
    fake_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    fake_reg = [ActivityPattern("regularity", "reg", 0.9)]

    with patch.object(analyzer, "_detect_peak_hours", return_value=fake_peak) as m_peak, \
         patch.object(analyzer, "_detect_action_sequences", return_value=fake_seq) as m_seq, \
         patch.object(analyzer, "_detect_regularity", return_value=fake_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)

        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)

        assert patterns == fake_peak + fake_seq + fake_reg

    # Empty activities returns empty list without calling helpers
    with patch.object(analyzer, "_detect_peak_hours") as m1, \
         patch.object(analyzer, "_detect_action_sequences") as m2, \
         patch.object(analyzer, "_detect_regularity") as m3:
        assert analyzer.analyze_patterns([]) == []
        m1.assert_not_called()
        m2.assert_not_called()
        m3.assert_not_called()


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activities."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_valid_timestamps(analyzer):
    """Test get_user_score calculation with valid timestamps and multiple days."""
    # 10 actions over 2 days, 5 unique actions
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    actions = ["a1", "a2", "a3", "a4", "a5"] + ["a1", "a2", "a3", "a4", "a5"]
    for i, act in enumerate(actions):
        ts = base + timedelta(hours=i)
        activities.append({"action": act, "timestamp": ts})
    # last timestamp at base+9h, ensure last day is 2 days ahead to create (last-first).days = 2
    activities[-1]["timestamp"] = base + timedelta(days=2)

    score = analyzer.get_user_score(activities)
    # diversity_score = 5/10=0.5 -> 0.5*0.3=0.15
    # actions_per_day = 10/2=5 -> 0.5*0.4=0.2
    # volume_score = 10/100=0.1 -> 0.1*0.3=0.03
    # total = 0.38 * 100 = 38.0
    assert score == 38.0


def test_activityanalyzer_get_user_score_without_valid_timestamps(analyzer):
    """Test get_user_score when timestamps are invalid (falls back to total actions as frequency baseline)."""
    activities = [{"action": "same", "timestamp": "invalid"} for _ in range(5)]
    score = analyzer.get_user_score(activities)
    # unique_actions = 1, total=5 -> diversity = 0.2 -> 0.2*0.3=0.06
    # actions_per_day = total=5 -> freq = 0.5 -> 0.5*0.4=0.2
    # volume = 5/100=0.05 -> 0.05*0.3=0.015
    # total = 0.275 * 100 = 27.5
    assert score == 27.5


def test_activityanalyzer_detect_anomalies_minimum_length(analyzer):
    """Test detect_anomalies returns empty if less than 5 activities provided."""
    activities = [{"action": "a", "timestamp": datetime(2024, 1, 1, 0, 0, 0)} for _ in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_flags_unusual_interval(analyzer):
    """Test detect_anomalies flags intervals with high z-score based on threshold."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    # Build at least 5 activities total to pass initial length check
    activities = []
    # For action 'click': timestamps produce intervals [10, 10, 100] seconds
    click_times = [
        base,
        base + timedelta(seconds=10),
        base + timedelta(seconds=20),
        base + timedelta(seconds=120),
    ]
    for t in click_times:
        activities.append({"action": "click", "timestamp": t})
    # Add extra activity for another action to reach len >= 5
    activities.append({"action": "view", "timestamp": base + timedelta(seconds=5)})

    # Lower threshold to catch the outlier
    analyzer.anomaly_threshold = 1.0
    anomalies = analyzer.detect_anomalies(activities)
    # Expect one anomaly for 'click' at the timestamp corresponding to the last time (index 3)
    assert len(anomalies) == 1
    a = anomalies[0]
    assert a["action"] == "click"
    assert "Unusual interval" in a["reason"]
    # z_score should be > 1
    assert a["z_score"] >= 1.0


def test_activityanalyzer_detect_anomalies_no_std_dev(analyzer):
    """Test detect_anomalies when intervals have zero standard deviation (no anomalies)."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    # Equal intervals for 'ping': [60, 60, 60] seconds -> std_dev = 0
    ping_times = [
        base,
        base + timedelta(seconds=60),
        base + timedelta(seconds=120),
        base + timedelta(seconds=180),
    ]
    for t in ping_times:
        activities.append({"action": "ping", "timestamp": t})
    # Add extra unrelated activities to ensure total len >= 5
    activities.append({"action": "view", "timestamp": base + timedelta(seconds=10)})
    activities.append({"action": "view", "timestamp": base + timedelta(seconds=20)})

    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []