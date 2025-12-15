import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing"""
    return ActivityAnalyzer()


def mk_activity(ts, action="click"):
    """Helper to create an activity dict"""
    return {"timestamp": ts, "action": action}


def test_activitypattern_init_and_to_dict():
    """Test ActivityPattern initialization and to_dict serialization"""
    ap = ActivityPattern(pattern_type="peak_hours", description="High activity", confidence=0.85)
    d = ap.to_dict()
    assert isinstance(d, dict)
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "High activity"
    assert d["confidence"] == 0.85


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer initialization sets default thresholds"""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp handles datetime objects and ISO strings"""
    now = datetime(2023, 1, 1, 12, 0, 0)
    assert analyzer._parse_timestamp(now) == now

    iso_z = "2023-01-01T12:00:00Z"
    parsed = analyzer._parse_timestamp(iso_z)
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is not None

    iso_naive = "2023-01-01T12:00:00"
    parsed_naive = analyzer._parse_timestamp(iso_naive)
    assert isinstance(parsed_naive, datetime)
    assert parsed_naive.tzinfo is None


def test_activityanalyzer_parse_timestamp_invalid_no_exception(analyzer):
    """Test _parse_timestamp returns None for invalid strings without raising"""
    assert analyzer._parse_timestamp("not-a-timestamp") is None
    assert analyzer._parse_timestamp(12345) is None

    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=ValueError):
        assert analyzer._parse_timestamp("2023-01-01T12:00:00Z") is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer):
    """Test _detect_peak_hours identifies peak hours correctly"""
    base = datetime(2023, 1, 1, 10, 0, 0)
    activities = []
    # 6 activities at 10:00 hour
    for i in range(6):
        activities.append(mk_activity(base + timedelta(minutes=i), "view"))
    # 3 activities at 15:00 hour
    for i in range(3):
        activities.append(mk_activity(datetime(2023, 1, 1, 15, 0, 0) + timedelta(minutes=i), "click"))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert isinstance(p, ActivityPattern)
    assert p.pattern_type == "peak_hours"
    assert "High activity during hours" in p.description
    assert "10:00" in p.description


def test_activityanalyzer_detect_peak_hours_none_meet_threshold(analyzer):
    """Test _detect_peak_hours returns empty when no hour exceeds threshold"""
    # 5 activities at 5 distinct hours => each 0.2 -> not strictly greater than 0.2
    activities = [
        mk_activity(datetime(2023, 1, 1, 8, 0, 0), "a"),
        mk_activity(datetime(2023, 1, 1, 9, 0, 0), "b"),
        mk_activity(datetime(2023, 1, 1, 10, 0, 0), "c"),
        mk_activity(datetime(2023, 1, 1, 11, 0, 0), "d"),
        mk_activity(datetime(2023, 1, 1, 12, 0, 0), "e"),
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_basic(analyzer):
    """Test _detect_action_sequences identifies repeated sequences of length 3"""
    # Create actions such that ('A','B','C') occurs at least twice
    activities = [
        {"action": "A"},
        {"action": "B"},
        {"action": "C"},
        {"action": "A"},
        {"action": "B"},
        {"action": "C"},
        {"action": "D"},
        {"action": "E"},
        {"action": "F"},
    ]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) >= 1
    assert all(p.pattern_type == "action_sequence" for p in patterns)
    assert any("A → B → C" in p.description for p in patterns)

    # Less than 3 activities produces no sequences
    assert analyzer._detect_action_sequences([{"action": "A"}, {"action": "B"}]) == []


def test_activityanalyzer_detect_action_sequences_top3_limit(analyzer):
    """Test _detect_action_sequences returns at most top 3 frequent sequences"""
    actions = ["A", "B", "C", "D", "E", "F", "G"]
    activities = []
    # Build overlapping sequences to produce at least 4 sequences each repeated twice
    # Sequence 1: A B C, Sequence 2: B C D, Sequence 3: C D E, Sequence 4: D E F
    seq_stream = ["A", "B", "C", "A", "B", "C",  # A B C twice
                  "B", "C", "D", "B", "C", "D",  # B C D twice
                  "C", "D", "E", "C", "D", "E",  # C D E twice
                  "D", "E", "F", "D", "E", "F"]  # D E F twice
    activities = [{"action": a} for a in seq_stream]
    patterns = analyzer._detect_action_sequences(activities)
    assert 1 <= len(patterns) <= 3
    assert all(p.pattern_type == "action_sequence" for p in patterns)


def test_activityanalyzer_detect_regularity_regular_pattern(analyzer):
    """Test _detect_regularity identifies highly regular intervals"""
    base = datetime(2023, 1, 1, 0, 0, 0)
    activities = [mk_activity(base + timedelta(seconds=60 * i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV: 0.00" in p.description

    # Not enough activities -> empty
    assert analyzer._detect_regularity(activities[:4]) == []


def test_activityanalyzer_detect_regularity_invalid_timestamps(analyzer):
    """Test _detect_regularity returns empty when valid timestamps are insufficient"""
    # 6 activities but 2 have invalid timestamps, leaving <5 valid
    base = datetime(2023, 1, 1, 0, 0, 0)
    activities = [
        mk_activity(base + timedelta(minutes=i)) for i in range(4)
    ] + [{"timestamp": "invalid", "action": "x"}, {"timestamp": None, "action": "y"}]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_detect_anomalies_threshold_exceeded(analyzer):
    """Test detect_anomalies flags intervals with z-score above threshold"""
    base = datetime(2023, 1, 1, 0, 0, 0)
    # Build 12 timestamps for one action 'click' with 11 intervals:
    # 10 intervals of 60s and 1 interval of 600s to exceed z>3
    timestamps = [base]
    for i in range(5):
        timestamps.append(timestamps[-1] + timedelta(seconds=60))
    # One large gap
    timestamps.append(timestamps[-1] + timedelta(seconds=600))
    # Remaining intervals of 60s to make total intervals = 11 (timestamps = 12)
    while len(timestamps) < 12:
        timestamps.append(timestamps[-1] + timedelta(seconds=60))

    activities = [mk_activity(ts, "click") for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) >= 1
    assert any(a["action"] == "click" for a in anomalies)
    # Ensure at least one anomaly has z_score strictly greater than 3.0
    assert any(a["z_score"] > 3.0 for a in anomalies)
    assert any("Unusual interval" in a["reason"] for a in anomalies)


def test_activityanalyzer_detect_anomalies_insufficient_history(analyzer):
    """Test detect_anomalies returns empty when overall activity history is short"""
    base = datetime(2023, 1, 1, 0, 0, 0)
    activities = [mk_activity(base + timedelta(minutes=i), "click") for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty input"""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_get_user_score_with_timestamps(analyzer):
    """Test get_user_score calculation with timestamps within a single day"""
    base = datetime(2023, 1, 1, 8, 0, 0)
    activities = [mk_activity(base + timedelta(minutes=i), "action") for i in range(10)]
    # Note: get_user_score uses first and last entries as given; ensure same day
    score = analyzer.get_user_score(activities)
    # diversity_score = 1.0 due to current unique_actions logic
    # frequency_score = min(10 actions / 1 day / 10, 1) = 1.0
    # volume_score = 10 / 100 = 0.1
    # final = (0.3*1 + 0.4*1 + 0.3*0.1) * 100 = 73.0
    assert score == 73.0


def test_activityanalyzer_get_user_score_no_timestamps(analyzer):
    """Test get_user_score when timestamps are missing; frequency uses total_actions"""
    activities = [{"action": "a"}, {"action": "b"}, {"action": "c"}, {"action": "d"}, {"action": "e"}]
    score = analyzer.get_user_score(activities)
    # diversity_score = 1.0 due to unique_actions logic
    # frequency_score = min(5 / 10, 1) = 0.5
    # volume_score = 0.05
    # final = (0.3*1 + 0.4*0.5 + 0.3*0.05) * 100 = 51.5
    assert score == 51.5


def test_activityanalyzer_analyze_patterns_calls_helpers_and_aggregates(analyzer):
    """Test analyze_patterns calls helper detection methods and aggregates results"""
    activities = [{"action": "x", "timestamp": datetime(2023, 1, 1, 9, 0, 0)}]

    fake_peak = [ActivityPattern("peak_hours", "peak", 0.85)]
    fake_seq = [ActivityPattern("action_sequence", "seq", 0.75)]
    fake_reg = [ActivityPattern("regularity", "reg", 0.9)]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=fake_peak) as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=fake_seq) as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=fake_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)
        assert patterns == fake_peak + fake_seq + fake_reg
        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)


def test_activityanalyzer_analyze_patterns_empty_input(analyzer):
    """Test analyze_patterns returns empty list and does not call helpers for empty input"""
    with patch.object(ActivityAnalyzer, "_detect_peak_hours") as m_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences") as m_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity") as m_reg:
        assert analyzer.analyze_patterns([]) == []
        m_peak.assert_not_called()
        m_seq.assert_not_called()
        m_reg.assert_not_called()


def test_activityanalyzer_detect_peak_hours_with_mocked_parse(analyzer):
    """Test _detect_peak_hours behavior with mocked _parse_timestamp to control hours"""
    activities = [{"timestamp": "anything", "action": "x"} for _ in range(10)]

    # Mock _parse_timestamp to return datetimes with controlled hours:
    # 7 hits at 14:00, 3 hits at 2:00
    hours = [14] * 7 + [2] * 3
    mocked_datetimes = [datetime(2023, 1, 1, h, 0, 0) for h in hours]

    def side_effect(_):
        return mocked_datetimes.pop(0)

    with patch.object(ActivityAnalyzer, "_parse_timestamp", side_effect=side_effect):
        patterns = analyzer._detect_peak_hours(activities)

    assert len(patterns) == 1
    assert patterns[0].pattern_type == "peak_hours"
    assert "14:00" in patterns[0].description
    assert "02:00" not in patterns[0].description