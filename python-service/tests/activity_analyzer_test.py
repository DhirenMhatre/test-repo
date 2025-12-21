import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide a fresh ActivityAnalyzer instance for each test."""
    return ActivityAnalyzer()


@pytest.fixture
def base_time():
    """Base datetime for constructing activity timestamps."""
    return datetime(2021, 1, 1, 9, 0, 0)


def make_activity(action: str, ts: datetime | str | None):
    """Helper to make an activity dict."""
    return {"action": action, "timestamp": ts}


def test_activitypattern_init_and_to_dict_basic():
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


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default initialization values."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


def test_activityanalyzer_parse_timestamp_variants(analyzer):
    """Test _parse_timestamp with datetime, ISO strings, Z suffix, and invalid values."""
    # Direct datetime
    dt = datetime(2020, 1, 1, 0, 0, 0)
    assert analyzer._parse_timestamp(dt) == dt

    # Naive ISO string
    naive = "2020-01-01T00:00:00"
    parsed = analyzer._parse_timestamp(naive)
    assert isinstance(parsed, datetime)
    assert parsed.tzinfo is None
    assert parsed == datetime(2020, 1, 1, 0, 0, 0)

    # Z suffix ISO string
    zstr = "2020-01-01T00:00:00Z"
    parsed_z = analyzer._parse_timestamp(zstr)
    assert isinstance(parsed_z, datetime)
    assert parsed_z.tzinfo is not None
    # normalize to UTC
    assert parsed_z == datetime(2020, 1, 1, 0, 0, 0, tzinfo=timezone.utc)

    # Invalid string
    assert analyzer._parse_timestamp("not-a-date") is None

    # Other types
    assert analyzer._parse_timestamp(12345) is None
    assert analyzer._parse_timestamp(None) is None


def test_activityanalyzer_detect_peak_hours_basic(analyzer, base_time):
    """Test _detect_peak_hours identifies hours exceeding threshold and ignores borderline."""
    activities = []
    # Total 10 activities:
    # 3 at 09:00
    activities += [make_activity("act", base_time + timedelta(minutes=5 * i)) for i in range(3)]
    # 3 at 10:00
    activities += [make_activity("act", base_time.replace(hour=10) + timedelta(minutes=7 * i)) for i in range(3)]
    # 2 at 11:00 (exactly 20%, should NOT be included because threshold is '>')
    activities += [make_activity("act", base_time.replace(hour=11) + timedelta(minutes=13 * i)) for i in range(2)]
    # 2 at 12:00
    activities += [make_activity("act", base_time.replace(hour=12) + timedelta(minutes=17 * i)) for i in range(2)]

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "peak_hours"
    assert "09:00" in pat.description
    assert "10:00" in pat.description
    assert "11:00" not in pat.description  # borderline 20% should not appear
    assert pat.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """Test _detect_peak_hours returns empty when timestamps are invalid."""
    activities = [
        make_activity("act", "invalid"),
        make_activity("act", None),
        make_activity("act", 123),
    ]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_top3(analyzer, base_time):
    """Test _detect_action_sequences finds common sequences occurring at least twice."""
    actions = ["a", "b", "c", "a", "b", "c", "a", "b", "c"]
    activities = [
        make_activity(actions[i], base_time + timedelta(seconds=i)) for i in range(len(actions))
    ]
    patterns = analyzer._detect_action_sequences(activities)
    # Should include 'a → b → c' occurred 3 times and 'b → c → a' occurred 2 times
    descs = [p.description for p in patterns]
    types = [p.pattern_type for p in patterns]
    assert all(t == "action_sequence" for t in types)
    assert any("a → b → c" in d and "occurred 3 times" in d for d in descs)
    assert any("b → c → a" in d and "occurred 2 times" in d for d in descs)
    assert all(p.confidence == 0.75 for p in patterns)


def test_activityanalyzer_detect_action_sequences_too_short(analyzer):
    """Test _detect_action_sequences returns empty when there are fewer than 3 activities."""
    activities = [make_activity("a", datetime(2021, 1, 1))]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer, base_time):
    """Test _detect_regularity identifies highly regular patterns when CV < 0.3."""
    activities = [make_activity("act", base_time + timedelta(seconds=60 * i)) for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    pat = patterns[0]
    assert pat.pattern_type == "regularity"
    assert "CV: 0.00" in pat.description
    assert pat.confidence == 0.9


def test_activityanalyzer_detect_regularity_insufficient_valid_timestamps(analyzer):
    """Test _detect_regularity returns empty if not enough valid timestamps."""
    activities = [
        make_activity("act", "invalid"),
        make_activity("act", datetime(2021, 1, 1)),
        make_activity("act", None),
        make_activity("act", "2021-01-01T10:00:00Z"),
    ]
    assert analyzer._detect_regularity(activities) == []


def test_activityanalyzer_analyze_patterns_aggregates_and_calls_private(analyzer):
    """Test analyze_patterns aggregates results from private detectors and uses mocks."""
    activities = [
        make_activity("x", datetime(2021, 1, 1, 9)),
        make_activity("y", datetime(2021, 1, 1, 10)),
        make_activity("z", datetime(2021, 1, 1, 11)),
    ]
    mock_peak = [ActivityPattern("peak_hours", "ph", 1.0)]
    mock_seq = [ActivityPattern("action_sequence", "seq", 0.5)]
    mock_reg = []

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=mock_peak) as p_peak, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=mock_seq) as p_seq, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=mock_reg) as p_reg:

        result = analyzer.analyze_patterns(activities)

        p_peak.assert_called_once_with(activities)
        p_seq.assert_called_once_with(activities)
        p_reg.assert_called_once_with(activities)

        assert result == mock_peak + mock_seq + mock_reg


def test_activityanalyzer_analyze_patterns_empty_returns_empty(analyzer):
    """Test analyze_patterns returns empty list when given no activities."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_non_empty_with_dates(analyzer, base_time):
    """Test get_user_score computes score based on diversity, frequency, and volume."""
    # 10 activities, 4 unique actions, over 5 calendar days (difference 4 days)
    actions = ["a", "b", "a", "c", "a", "b", "d", "a", "c", "d"]
    activities = [
        make_activity(actions[i], base_time + timedelta(days=i // 2, seconds=i)) for i in range(10)
    ]
    score = analyzer.get_user_score(activities)
    # diversity = 4/10 = 0.4
    # days_active = 4, actions_per_day = 10/4 = 2.5 => freq = 0.25
    # volume = 10/100 = 0.1
    # final = (0.4*0.3 + 0.25*0.4 + 0.1*0.3) * 100 = 25.0
    assert score == 25.0


def test_activityanalyzer_get_user_score_no_timestamps(analyzer):
    """Test get_user_score falls back to total_actions when timestamps are missing/invalid."""
    activities = [
        make_activity("x", None),
        make_activity("y", "invalid"),
        make_activity("x", None),
        make_activity("y", "invalid"),
        make_activity("x", None),
        make_activity("y", "invalid"),
        make_activity("x", None),
        make_activity("y", "invalid"),
    ]
    score = analyzer.get_user_score(activities)
    # total=8, unique=2 -> diversity=0.25
    # actions_per_day = total = 8 -> frequency = 0.8
    # volume = 0.08
    # final = (0.25*0.3 + 0.8*0.4 + 0.08*0.3)*100 = 41.9
    assert score == 41.9


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list."""
    assert analyzer.get_user_score([]) == 0.0


def test_activityanalyzer_detect_anomalies_requires_min_activities(analyzer, base_time):
    """Test detect_anomalies returns empty when fewer than 5 total activities are provided."""
    activities = [make_activity("a", base_time + timedelta(seconds=i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_identical_intervals_no_std(analyzer, base_time):
    """Test detect_anomalies returns no anomalies when intervals are identical (std_dev=0)."""
    activities = [make_activity("click", base_time + timedelta(seconds=60 * i)) for i in range(6)]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_detects_outlier_interval(analyzer, base_time):
    """Test detect_anomalies flags an interval with a large deviation using default threshold."""
    # For a single action, create 11 timestamps => 10 intervals.
    # 9 intervals are 1 second, 1 interval is very large to produce z > 3.
    timestamps = []
    t = base_time
    for i in range(5):
        timestamps.append(t)
        t = t + timedelta(seconds=1)
    # large jump
    t = t + timedelta(seconds=100000)
    timestamps.append(t)
    for i in range(5):
        t = t + timedelta(seconds=1)
        timestamps.append(t)
    # Ensure we have 11 timestamps
    assert len(timestamps) == 11

    activities = [make_activity("click", ts) for ts in timestamps]
    anomalies = analyzer.detect_anomalies(activities)
    # Should detect one anomaly for the large interval
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "click"
    assert "Unusual interval" in anomaly["reason"]
    # Timestamp should be the timestamp at the end of the anomalous interval (after the big jump)
    big_jump_end_ts = timestamps[6]  # after the large jump, index 5->6, anomaly index maps to i+1
    assert anomaly["timestamp"] == big_jump_end_ts.isoformat()
    assert anomaly["z_score"] > 3.0


def test_activityanalyzer_detect_anomalies_ignores_insufficient_action_timestamps(analyzer, base_time):
    """Test detect_anomalies ignores actions with fewer than 3 valid timestamps."""
    activities = [
        make_activity("a", base_time + timedelta(seconds=0)),
        make_activity("a", base_time + timedelta(seconds=10)),
        # Only 2 timestamps for 'b'
        make_activity("b", base_time + timedelta(seconds=0)),
        make_activity("b", base_time + timedelta(seconds=10)),
        # Add more to reach total >= 5
        make_activity("c", base_time + timedelta(seconds=20)),
    ]
    anomalies = analyzer.detect_anomalies(activities)
    # 'b' should be ignored and 'a' has identical intervals so no anomalies
    assert anomalies == []


def test_activityanalyzer_analyze_patterns_handles_private_errors(analyzer, base_time):
    """Test analyze_patterns propagates exceptions from private detectors (demonstrates error handling)."""
    activities = [
        make_activity("x", base_time),
        make_activity("y", base_time + timedelta(hours=1)),
    ]
    with patch.object(ActivityAnalyzer, "_detect_peak_hours", side_effect=RuntimeError("boom")):
        with pytest.raises(RuntimeError):
            analyzer.analyze_patterns(activities)