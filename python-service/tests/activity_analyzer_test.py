import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Provide a base datetime for constructing test activities"""
    return datetime(2025, 1, 1, 9, 0, 0)


def test_activitypattern_init_sets_fields():
    """Test ActivityPattern initialization assigns fields correctly"""
    ap = ActivityPattern("peak_hours", "desc", 0.9)
    assert ap.pattern_type == "peak_hours"
    assert ap.description == "desc"
    assert ap.confidence == 0.9


def test_activitypattern_to_dict():
    """Test ActivityPattern.to_dict returns expected dictionary"""
    ap = ActivityPattern("regularity", "Highly regular", 0.95)
    d = ap.to_dict()
    assert d["pattern_type"] == "regularity"
    assert d["description"] == "Highly regular"
    assert d["confidence"] == 0.95


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization sets default thresholds"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_datetime_input(analyzer, base_time):
    """Test _parse_timestamp returns datetime as-is for datetime input"""
    ts = analyzer._parse_timestamp(base_time)
    assert ts == base_time


def test_activityanalyzer_parse_timestamp_iso_z(analyzer):
    """Test _parse_timestamp parses ISO 8601 string with Z suffix"""
    dt_str = "2023-01-01T12:00:00Z"
    ts = analyzer._parse_timestamp(dt_str)
    assert ts is not None
    # fromisoformat('...+00:00') is the expected equivalent
    expected = datetime.fromisoformat("2023-01-01T12:00:00+00:00")
    assert ts == expected
    assert ts.tzinfo is not None
    assert ts.utcoffset() == timedelta(0)


def test_activityanalyzer_parse_timestamp_invalid_string_returns_none(analyzer):
    """Test _parse_timestamp returns None for invalid timestamp strings"""
    assert analyzer._parse_timestamp("not-a-timestamp") is None


def test_activityanalyzer_parse_timestamp_non_string_non_datetime(analyzer):
    """Test _parse_timestamp returns None for unsupported types"""
    assert analyzer._parse_timestamp(12345) is None
    assert analyzer._parse_timestamp({"ts": "2023-01-01"}) is None


def test_activityanalyzer_parse_timestamp_fromisoformat_exception_handled(analyzer):
    """Test _parse_timestamp gracefully handles exceptions from datetime.fromisoformat"""
    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=ValueError):
        assert analyzer._parse_timestamp("2023-01-01T12:00:00+00:00") is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding the threshold"""
    activities = []
    # 3 activities at 09:00
    for i in range(3):
        activities.append({"action": "a", "timestamp": base_time + timedelta(minutes=i)})
    # 3 activities at 18:00
    for i in range(3):
        activities.append({"action": "b", "timestamp": base_time.replace(hour=18) + timedelta(minutes=i)})
    # 4 activities spread across other hours
    for i in range(4):
        activities.append({"action": "c", "timestamp": base_time.replace(hour=10 + i)})

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "High activity during hours:" in p.description
    # Ensure both 09:00 and 18:00 are present and sorted/zero-padded
    assert "09:00" in p.description
    assert "18:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_threshold_edge_equal_not_included(analyzer, base_time):
    """Test _detect_peak_hours does not include hours exactly equal to the threshold"""
    # 5 activities total, 1 at 09:00 => 0.2 fraction, should not be included (> threshold needed)
    activities = [
        {"action": "a", "timestamp": base_time},
        {"action": "b", "timestamp": base_time.replace(hour=10)},
        {"action": "c", "timestamp": base_time.replace(hour=11)},
        {"action": "d", "timestamp": base_time.replace(hour=12)},
        {"action": "e", "timestamp": base_time.replace(hour=13)},
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when no timestamps are valid"""
    activities = [{"action": "a", "timestamp": "invalid"} for _ in range(5)]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_top3_and_format(analyzer, base_time):
    """Test _detect_action_sequences returns up to top 3 common sequences with proper formatting"""
    # Create actions that yield exactly three sequences that occur twice each:
    # Sequences ABC, STU, PQR each repeated twice; others occur once.
    actions = [
        "A", "B", "C", "D", "E", "F",
        "A", "B", "C", "G", "H", "I",
        "S", "T", "U", "J", "K", "L",
        "S", "T", "U",
        "P", "Q", "R", "M", "N", "O",
        "P", "Q", "R"
    ]
    activities = [{"action": a, "timestamp": base_time + timedelta(minutes=i)} for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 3
    descriptions = [p.description for p in patterns]
    assert any("Common sequence: A → B → C (occurred 2 times)" in d for d in descriptions)
    assert any("Common sequence: S → T → U (occurred 2 times)" in d for d in descriptions)
    assert any("Common sequence: P → Q → R (occurred 2 times)" in d for d in descriptions)
    assert all(p.pattern_type == "action_sequence" and p.confidence == 0.75 for p in patterns)


def test_activityanalyzer_detect_action_sequences_too_short(analyzer):
    """Test _detect_action_sequences returns empty for fewer than 3 activities"""
    activities = [{"action": "A", "timestamp": datetime(2025, 1, 1, 0, 0)}]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity identifies highly regular patterns with low CV"""
    activities = [
        {"action": "x", "timestamp": base_time + timedelta(minutes=10 * i)}
        for i in range(6)
    ]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "Highly regular activity pattern (CV:" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular(analyzer, base_time):
    """Test _detect_regularity returns empty when pattern is not regular enough"""
    times = [0, 10, 310, 330, 930, 940]  # highly variable
    activities = [{"action": "y", "timestamp": base_time + timedelta(seconds=t)} for t in times]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_detect_regularity_insufficient_data(analyzer, base_time):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps"""
    activities = [{"action": "z", "timestamp": base_time + timedelta(minutes=i)} for i in range(4)]
    assert analyzer._detect_regularity(activities) == []

    # Mix valid and invalid to end up with <5 valid timestamps
    activities = [
        {"action": "z", "timestamp": base_time + timedelta(minutes=i)} for i in range(3)
    ] + [
        {"action": "z", "timestamp": "invalid"},
        {"action": "z", "timestamp": "also-invalid"},
    ]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_detect_anomalies_flags_outlier_interval(analyzer, base_time):
    """Test detect_anomalies flags intervals with z-score exceeding threshold"""
    # Build activities with one action showing anomalous interval
    activities = []
    # Click action at 60s, 60s, 600s intervals
    click_times = [base_time, base_time + timedelta(seconds=60),
                   base_time + timedelta(seconds=120),
                   base_time + timedelta(seconds=720)]
    for t in click_times:
        activities.append({"action": "click", "timestamp": t})
    # Add other actions to exceed len(activities) >= 5
    activities.append({"action": "view", "timestamp": base_time + timedelta(seconds=30)})
    activities.append({"action": "view", "timestamp": base_time + timedelta(seconds=90)})

    analyzer.anomaly_threshold = 1.0  # Easier to flag
    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) >= 1
    # The anomaly should be tied to the interval leading to the last click time (720s)
    expected_ts = click_times[-1].isoformat()
    assert any(a["action"] == "click" and a["timestamp"] == expected_ts for a in anomalies)
    # Check structure of anomaly entry
    a0 = next(a for a in anomalies if a["action"] == "click" and a["timestamp"] == expected_ts)
    assert "z_score" in a0 and isinstance(a0["z_score"], float)
    assert "reason" in a0 and "Unusual interval" in a0["reason"]


def test_activityanalyzer_detect_anomalies_insufficient_data(analyzer, base_time):
    """Test detect_anomalies returns empty for insufficient total activities or per-action timestamps"""
    # Fewer than 5 activities globally
    activities = [{"action": "a", "timestamp": base_time + timedelta(minutes=i)} for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []

    # Enough global activities but per-action less than 3 timestamps
    activities = []
    activities += [{"action": "x", "timestamp": base_time + timedelta(minutes=i)} for i in range(2)]
    activities += [{"action": "y", "timestamp": base_time + timedelta(minutes=10 + i)} for i in range(2)]
    activities += [{"action": "z", "timestamp": base_time + timedelta(minutes=20)}]
    # No action has >=3 timestamps, should return []
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_get_user_score_with_valid_dates(analyzer, base_time):
    """Test get_user_score computes expected score with valid timestamps"""
    # 20 actions over 2 days (difference in whole days = 2), 5 unique actions repeated equally
    actions = ["a1", "a2", "a3", "a4", "a5"] * 4  # 20 total, 5 unique
    activities = []
    # First 10 on day 1, next 10 on day 3 -> 2 days difference
    for i, action in enumerate(actions[:10]):
        activities.append({"action": action, "timestamp": base_time + timedelta(hours=i)})
    for i, action in enumerate(actions[10:]):
        activities.append({"action": action, "timestamp": base_time + timedelta(days=2, hours=i)})

    score = analyzer.get_user_score(activities)
    # diversity_score = 5/20 = 0.25
    # actions_per_day = 20 / 2 = 10 -> frequency_score = 1.0
    # volume_score = 20/100 = 0.2
    # final = (0.25*0.3 + 1.0*0.4 + 0.2*0.3) * 100 = 53.5
    assert score == 53.5


def test_activityanalyzer_get_user_score_invalid_timestamps(analyzer):
    """Test get_user_score uses total actions for frequency when timestamps are invalid"""
    actions = ["x", "y", "z"] * 5  # 15 total, 3 unique
    activities = [{"action": a, "timestamp": "invalid"} for a in actions]
    score = analyzer.get_user_score(activities)
    # diversity = 3/15 = 0.2
    # actions_per_day = total_actions = 15 -> frequency_score = 1.0
    # volume = 15/100 = 0.15
    # final = (0.2*0.3 + 1.0*0.4 + 0.15*0.3) * 100 = 50.5
    assert score == 50.5


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list"""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_analyze_patterns_empty(analyzer):
    """Test analyze_patterns returns empty list for empty input"""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_analyze_patterns_combines_private_detectors(analyzer, base_time):
    """Test analyze_patterns aggregates results from private detection methods in correct order"""
    activities = [{"action": "a", "timestamp": base_time}]

    mock_peak = [ActivityPattern("peak_hours", "peak", 0.8)]
    mock_seq = [ActivityPattern("action_sequence", "seq", 0.7)]
    mock_reg = [ActivityPattern("regularity", "reg", 0.9)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as m3:
        result = analyzer.analyze_patterns(activities)
        m1.assert_called_once_with(activities)
        m2.assert_called_once_with(activities)
        m3.assert_called_once_with(activities)

    # Ensure order: peak, sequences, regularity
    assert result == mock_peak + mock_seq + mock_reg