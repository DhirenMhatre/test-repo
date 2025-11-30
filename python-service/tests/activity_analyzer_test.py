import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing test timestamps."""
    return datetime(2023, 1, 1, 0, 0, 0)


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and dictionary conversion."""
    ap = ActivityPattern(pattern_type="peak_hours", description="High activity", confidence=0.9)
    d = ap.to_dict()
    assert ap.pattern_type == "peak_hours"
    assert ap.description == "High activity"
    assert ap.confidence == 0.9
    assert d == {
        "pattern_type": "peak_hours",
        "description": "High activity",
        "confidence": 0.9,
    }


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization default attributes."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_valid_datetime(analyzer, base_time):
    """Test _parse_timestamp returns the same datetime object if already a datetime."""
    parsed = analyzer._parse_timestamp(base_time)
    assert isinstance(parsed, datetime)
    assert parsed == base_time


def test_activityanalyzer_parse_timestamp_valid_iso(analyzer):
    """Test _parse_timestamp with valid ISO-8601 strings with and without Z suffix."""
    ts1 = "2023-05-01T12:34:56"
    parsed1 = analyzer._parse_timestamp(ts1)
    assert isinstance(parsed1, datetime)
    assert parsed1.year == 2023 and parsed1.month == 5 and parsed1.day == 1
    assert parsed1.hour == 12 and parsed1.minute == 34 and parsed1.second == 56

    ts2 = "2023-05-01T12:34:56Z"
    parsed2 = analyzer._parse_timestamp(ts2)
    assert isinstance(parsed2, datetime)
    # Ensure timezone-aware when 'Z' is present
    assert parsed2.tzinfo is not None
    assert parsed2.utcoffset() == timedelta(0)


def test_activityanalyzer_parse_timestamp_invalid(analyzer):
    """Test _parse_timestamp returns None for invalid inputs."""
    assert analyzer._parse_timestamp("not-a-timestamp") is None
    assert analyzer._parse_timestamp(12345) is None
    assert analyzer._parse_timestamp(None) is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold."""
    activities = []
    # 3 events at 09:00, 3 events at 14:00, 2 events at 01:00, 2 events at 22:00 => total 10
    for _ in range(3):
        activities.append({"action": "a", "timestamp": (base_time.replace(hour=9)).isoformat()})
    for _ in range(3):
        activities.append({"action": "b", "timestamp": (base_time.replace(hour=14)).isoformat()})
    for _ in range(2):
        activities.append({"action": "c", "timestamp": (base_time.replace(hour=1)).isoformat()})
    for _ in range(2):
        activities.append({"action": "d", "timestamp": (base_time.replace(hour=22)).isoformat()})

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert isinstance(p, ActivityPattern)
    assert p.pattern_type == "peak_hours"
    assert "09:00" in p.description
    assert "14:00" in p.description
    # Ensure not listing hours that should not exceed threshold
    assert "01:00" not in p.description
    assert "22:00" not in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_peak(analyzer, base_time):
    """Test _detect_peak_hours returns empty when no hour strictly exceeds threshold."""
    activities = []
    # 5 events across 5 unique hours -> each 1/5 = 0.2 equals threshold, not strictly greater
    hours = [0, 5, 10, 15, 20]
    for h in hours:
        activities.append({"action": "a", "timestamp": (base_time.replace(hour=h)).isoformat()})

    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_common(analyzer, base_time):
    """Test _detect_action_sequences detects common sequences occurring at least twice."""
    # Sequence: A,B,C repeated twice
    activities = [
        {"action": "A", "timestamp": (base_time + timedelta(minutes=0)).isoformat()},
        {"action": "B", "timestamp": (base_time + timedelta(minutes=1)).isoformat()},
        {"action": "C", "timestamp": (base_time + timedelta(minutes=2)).isoformat()},
        {"action": "X", "timestamp": (base_time + timedelta(minutes=3)).isoformat()},
        {"action": "A", "timestamp": (base_time + timedelta(minutes=4)).isoformat()},
        {"action": "B", "timestamp": (base_time + timedelta(minutes=5)).isoformat()},
        {"action": "C", "timestamp": (base_time + timedelta(minutes=6)).isoformat()},
        {"action": "Y", "timestamp": (base_time + timedelta(minutes=7)).isoformat()},
    ]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) >= 1
    p0 = patterns[0]
    assert p0.pattern_type == "action_sequence"
    assert "Common sequence: A → B → C (occurred 2 times)" in p0.description
    assert p0.confidence == 0.75


def test_activityanalyzer_detect_action_sequences_limit_top_three(analyzer, base_time):
    """Test _detect_action_sequences returns at most top 3 common sequences."""
    # Construct 4 different sequences each occurring twice; should return only top 3
    actions_sets = [
        ["A1", "B1", "C1"],
        ["A2", "B2", "C2"],
        ["A3", "B3", "C3"],
        ["A4", "B4", "C4"],
    ]
    activities = []
    offset = 0
    for seq in actions_sets:
        for _ in range(2):
            for a in seq:
                activities.append({"action": a, "timestamp": (base_time + timedelta(minutes=offset)).isoformat()})
                offset += 1
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) <= 3
    for p in patterns:
        assert p.pattern_type == "action_sequence"
        assert "Common sequence" in p.description


def test_activityanalyzer_detect_action_sequences_short_list(analyzer, base_time):
    """Test _detect_action_sequences returns empty for fewer than 3 activities."""
    activities = [
        {"action": "A", "timestamp": base_time.isoformat()},
        {"action": "B", "timestamp": (base_time + timedelta(minutes=1)).isoformat()},
    ]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity detects highly regular intervals (low CV)."""
    activities = []
    for i in range(6):
        activities.append({"action": "tick", "timestamp": (base_time + timedelta(seconds=60 * i)).isoformat()})

    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern" in p.description
    assert "(CV:" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_insufficient_data(analyzer, base_time):
    """Test _detect_regularity requires at least 5 valid timestamps."""
    activities = [
        {"action": "a", "timestamp": (base_time + timedelta(seconds=0)).isoformat()},
        {"action": "a", "timestamp": (base_time + timedelta(seconds=60)).isoformat()},
        {"action": "a", "timestamp": (base_time + timedelta(seconds=120)).isoformat()},
        {"action": "a", "timestamp": (base_time + timedelta(seconds=180)).isoformat()},
    ]
    assert analyzer._detect_regularity(activities) == []

    # Include invalid timestamps resulting in <5 valid timestamps
    activities_invalid = [
        {"action": "a", "timestamp": "invalid"},
        {"action": "a", "timestamp": (base_time + timedelta(seconds=60)).isoformat()},
        {"action": "a", "timestamp": (base_time + timedelta(seconds=120)).isoformat()},
        {"action": "a", "timestamp": (base_time + timedelta(seconds=180)).isoformat()},
        {"action": "a", "timestamp": "also-invalid"},
    ]
    assert analyzer._detect_regularity(activities_invalid) == []


def test_activityanalyzer_detect_anomalies_interval_zscore(analyzer, base_time):
    """Test detect_anomalies flags unusual inter-event intervals per action."""
    # Build many regular 60s intervals and one large 3600s interval for 'click'
    timestamps = [base_time + timedelta(seconds=60 * i) for i in range(21)]
    timestamps.append(timestamps[-1] + timedelta(seconds=3600))
    activities = [{"action": "click", "timestamp": ts.isoformat()} for ts in timestamps]

    anomalies = analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "click"
    assert anomaly["timestamp"] == timestamps[-1].isoformat()
    assert anomaly["z_score"] > analyzer.anomaly_threshold
    assert "Unusual interval" in anomaly["reason"]


def test_activityanalyzer_detect_anomalies_ignores_small_samples(analyzer, base_time):
    """Test detect_anomalies returns empty for fewer than 5 activities overall."""
    activities = [
        {"action": "click", "timestamp": (base_time + timedelta(minutes=i)).isoformat()}
        for i in range(4)
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_requires_enough_per_action(analyzer, base_time):
    """Test detect_anomalies ignores actions with fewer than 3 timestamps or zero std dev."""
    # Action 'A' has only 2 timestamps; 'B' has 3 timestamps but constant intervals -> std_dev 0
    activities = [
        {"action": "A", "timestamp": (base_time + timedelta(minutes=0)).isoformat()},
        {"action": "A", "timestamp": (base_time + timedelta(minutes=1)).isoformat()},
        {"action": "B", "timestamp": (base_time + timedelta(minutes=0)).isoformat()},
        {"action": "B", "timestamp": (base_time + timedelta(minutes=1)).isoformat()},
        {"action": "B", "timestamp": (base_time + timedelta(minutes=2)).isoformat()},
    ]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_handles_invalid_timestamps(analyzer, base_time):
    """Test detect_anomalies skips invalid timestamps without raising exceptions."""
    # Include invalid timestamps; ensure processing continues
    activities = [
        {"action": "click", "timestamp": "not-a-timestamp"},
        {"action": "click", "timestamp": (base_time + timedelta(minutes=0)).isoformat()},
        {"action": "click", "timestamp": (base_time + timedelta(minutes=1)).isoformat()},
        {"action": "click", "timestamp": (base_time + timedelta(minutes=2)).isoformat()},
        {"action": "click", "timestamp": (base_time + timedelta(minutes=3)).isoformat()},
        {"action": "click", "timestamp": (base_time + timedelta(minutes=30)).isoformat()},
    ]
    anomalies = analyzer.detect_anomalies(activities)
    # There might be an anomaly due to jump to 30 minutes; assert no exception and anomalies is a list
    assert isinstance(anomalies, list)


def test_activityanalyzer_analyze_patterns_calls_internal(analyzer, base_time):
    """Test analyze_patterns aggregates patterns from internal detectors."""
    activities = [
        {"action": "A", "timestamp": (base_time + timedelta(minutes=i)).isoformat()}
        for i in range(10)
    ]
    peak_pattern = ActivityPattern("peak_hours", "Mock peak", 0.85)
    seq_pattern = ActivityPattern("action_sequence", "Mock sequence", 0.75)
    reg_pattern = ActivityPattern("regularity", "Mock regularity", 0.9)

    with patch.object(analyzer, "_detect_peak_hours", return_value=[peak_pattern]) as mock_peak, \
         patch.object(analyzer, "_detect_action_sequences", return_value=[seq_pattern]) as mock_seq, \
         patch.object(analyzer, "_detect_regularity", return_value=[reg_pattern]) as mock_reg:
        patterns = analyzer.analyze_patterns(activities)

        mock_peak.assert_called_once_with(activities)
        mock_seq.assert_called_once_with(activities)
        mock_reg.assert_called_once_with(activities)

        assert patterns == [peak_pattern, seq_pattern, reg_pattern]


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list and does not call internal detectors when activities empty."""
    with patch.object(analyzer, "_detect_peak_hours") as mock_peak, \
         patch.object(analyzer, "_detect_action_sequences") as mock_seq, \
         patch.object(analyzer, "_detect_regularity") as mock_reg:
        patterns = analyzer.analyze_patterns([])
        assert patterns == []
        mock_peak.assert_not_called()
        mock_seq.assert_not_called()
        mock_reg.assert_not_called()


def test_activityanalyzer_get_user_score_basic(analyzer, base_time):
    """Test get_user_score combines diversity, frequency, and volume correctly."""
    # Build 20 activities spanning 10 days from first to last
    actions = ["a1", "a2", "a3", "a4"]
    activities = []
    # 19 activities over 0..9 days
    for i in range(19):
        activities.append({
            "action": actions[i % 4],
            "timestamp": (base_time + timedelta(days=i // 2)).isoformat()
        })
    # Last activity at day 10
    activities.append({
        "action": actions[19 % 4],
        "timestamp": (base_time + timedelta(days=10)).isoformat()
    })

    score = analyzer.get_user_score(activities)
    # total_actions=20, unique_actions=4 -> diversity=0.2
    # days_active=(last-first).days=10 -> actions_per_day=2 -> frequency=0.2
    # volume = min(20/100,1)=0.2
    # final = (0.2*0.3 + 0.2*0.4 + 0.2*0.3)*100 = 20.0
    assert score == 20.0


def test_activityanalyzer_get_user_score_invalid_timestamps(analyzer):
    """Test get_user_score when timestamps are invalid uses total_actions for frequency."""
    # 10 activities, 1 unique action, invalid timestamps
    activities = [{"action": "only", "timestamp": "invalid"} for _ in range(10)]
    score = analyzer.get_user_score(activities)
    # diversity = 1/10 = 0.1, frequency = min(10/10, 1) = 1.0, volume = 0.1
    # final = (0.1*0.3 + 1.0*0.4 + 0.1*0.3) * 100 = 46.0
    assert score == 46.0


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_handles_missing_action_key(analyzer, base_time):
    """Test methods handle activities missing the 'action' key without errors."""
    activities = [
        {"timestamp": (base_time + timedelta(minutes=0)).isoformat()},  # missing action
        {"action": None, "timestamp": (base_time + timedelta(minutes=1)).isoformat()},
        {"action": "X", "timestamp": (base_time + timedelta(minutes=2)).isoformat()},
        {"action": "X", "timestamp": (base_time + timedelta(minutes=3)).isoformat()},
        {"action": "X", "timestamp": (base_time + timedelta(minutes=50)).isoformat()},
    ]
    # Should not raise
    patterns = analyzer.analyze_patterns(activities)
    assert isinstance(patterns, list)
    anomalies = analyzer.detect_anomalies(activities)
    assert isinstance(anomalies, list)