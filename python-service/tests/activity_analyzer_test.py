import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide a fresh ActivityAnalyzer instance for each test."""
    return ActivityAnalyzer()


def make_activity(ts: datetime, action: str):
    return {"timestamp": ts, "action": action}


def test_ActivityPattern_to_dict_basic():
    """ActivityPattern.to_dict should return a correct serializable dict."""
    p = ActivityPattern(pattern_type="peak_hours", description="desc", confidence=0.77)
    d = p.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "desc"
    assert d["confidence"] == pytest.approx(0.77)


def test_ActivityAnalyzer_init_defaults(analyzer):
    """ActivityAnalyzer.__init__ should set default thresholds."""
    assert analyzer.peak_hour_threshold == pytest.approx(0.2)
    assert analyzer.anomaly_threshold == pytest.approx(3.0)


def test_ActivityAnalyzer_parse_timestamp_variants(analyzer):
    """_parse_timestamp should handle datetime, ISO strings with Z, invalid strings, and non-strings."""
    # datetime instance returns same value
    dt = datetime(2024, 5, 1, 12, 30, 0)
    assert analyzer._parse_timestamp(dt) == dt

    # ISO string with Z should become timezone-aware +00:00
    parsed = analyzer._parse_timestamp("2024-05-01T12:30:00Z")
    assert parsed is not None
    assert parsed.tzinfo is not None
    assert parsed.isoformat().endswith("+00:00")

    # Invalid string should return None
    assert analyzer._parse_timestamp("not-a-timestamp") is None

    # Non-string should return None
    assert analyzer._parse_timestamp(12345) is None


def test_ActivityAnalyzer_parse_timestamp_handles_exception(analyzer):
    """_parse_timestamp should return None if datetime.fromisoformat raises ValueError."""
    with patch("src.activity_analyzer.datetime.fromisoformat", side_effect=ValueError):
        assert analyzer._parse_timestamp("2024-05-01T12:30:00") is None


def test_ActivityAnalyzer_detect_peak_hours_basic(analyzer):
    """_detect_peak_hours should flag hours with share strictly greater than threshold."""
    base = datetime(2024, 1, 1, 9, 0, 0)
    activities = []
    # 3 at 09:00
    for i in range(3):
        activities.append(make_activity(base + timedelta(minutes=i), "a"))
    # 2 at 10:00 (at threshold 0.2 if total 10; should not be included)
    for i in range(2):
        activities.append(make_activity(datetime(2024, 1, 1, 10, i, 0), "b"))
    # 5 at other distinct hours (one each)
    for h in [11, 12, 13, 14, 15]:
        activities.append(make_activity(datetime(2024, 1, 1, h, 0, 0), "c"))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert p.confidence == pytest.approx(0.85)
    assert "09:00" in p.description
    assert "10:00" not in p.description  # exactly at threshold; excluded


def test_ActivityAnalyzer_detect_peak_hours_no_valid_timestamps(analyzer):
    """_detect_peak_hours should return empty if no valid timestamps."""
    activities = [{"timestamp": "invalid", "action": "x"}, {"timestamp": None, "action": "y"}]
    assert analyzer._detect_peak_hours(activities) == []


def test_ActivityAnalyzer_detect_action_sequences_repeated(analyzer):
    """_detect_action_sequences should identify sequences that occur at least twice."""
    actions = ["x", "y", "z", "x", "y", "z", "w"]
    activities = [{"action": a} for a in actions]
    patterns = analyzer._detect_action_sequences(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "action_sequence"
    assert p.confidence == pytest.approx(0.75)
    assert "x → y → z" in p.description
    assert "(occurred 2 times)" in p.description


def test_ActivityAnalyzer_detect_action_sequences_insufficient(analyzer):
    """_detect_action_sequences should return empty when fewer than 3 activities."""
    activities = [{"action": "a"}, {"action": "b"}]
    assert analyzer._detect_action_sequences(activities) == []


def test_ActivityAnalyzer_detect_regularity_regular(analyzer):
    """_detect_regularity should identify highly regular intervals with low CV."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [make_activity(base + timedelta(seconds=60 * i), "ping") for i in range(6)]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert p.confidence == pytest.approx(0.9)
    assert "CV: 0.00" in p.description


def test_ActivityAnalyzer_detect_regularity_insufficient(analyzer):
    """_detect_regularity should return empty when fewer than 5 valid timestamps."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        make_activity(base + timedelta(seconds=60 * i), "ping") for i in range(4)
    ] + [{"timestamp": "invalid", "action": "ping"}]
    assert analyzer._detect_regularity(activities) == []


def test_ActivityAnalyzer_analyze_patterns_empty(analyzer):
    """analyze_patterns should return empty for empty input."""
    assert analyzer.analyze_patterns([]) == []


def test_ActivityAnalyzer_analyze_patterns_integration_with_mocks(analyzer):
    """analyze_patterns should aggregate results from internal detectors."""
    p1 = [ActivityPattern("peak_hours", "ph", 0.1)]
    p2 = [ActivityPattern("action_sequence", "seq", 0.2)]
    p3 = [ActivityPattern("regularity", "reg", 0.3)]
    activities = [{"action": "a", "timestamp": datetime(2024, 1, 1, 0, 0, 0)}]

    with patch.object(ActivityAnalyzer, "_detect_peak_hours", return_value=p1) as m1, \
         patch.object(ActivityAnalyzer, "_detect_action_sequences", return_value=p2) as m2, \
         patch.object(ActivityAnalyzer, "_detect_regularity", return_value=p3) as m3:
        patterns = analyzer.analyze_patterns(activities)
        assert patterns == p1 + p2 + p3
        m1.assert_called_once_with(activities)
        m2.assert_called_once_with(activities)
        m3.assert_called_once_with(activities)


def test_ActivityAnalyzer_get_user_score_with_timestamps(analyzer):
    """get_user_score should compute score using days_active when timestamps are provided."""
    # 20 actions within the same day; diversity score always computed as 1.0 by current logic
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [make_activity(base + timedelta(minutes=i), "click") for i in range(20)]
    score = analyzer.get_user_score(activities)
    # diversity=1.0, freq=min(20/1/10,1)=1.0, volume=min(20/100,1)=0.2
    # final = (0.3*1 + 0.4*1 + 0.3*0.2)*100 = 76.0
    assert score == pytest.approx(76.0)


def test_ActivityAnalyzer_get_user_score_without_timestamps(analyzer):
    """get_user_score should fall back to total_actions for frequency when timestamps are missing/invalid."""
    activities = [{"action": "a"} for _ in range(15)]
    score = analyzer.get_user_score(activities)
    # diversity=1.0, freq=min(15/10,1)=1.0, volume=min(15/100,1)=0.15
    # final = (0.3 + 0.4 + 0.3*0.15)*100 = 74.5
    assert score == pytest.approx(74.5)


def test_ActivityAnalyzer_detect_anomalies_threshold_and_filtering(analyzer):
    """detect_anomalies should flag unusual intervals per action based on z-score and ignore short series."""
    base = datetime(2024, 1, 1, 0, 0, 0)

    # Action A: 6 timestamps; one large gap to create anomaly
    a_times = [
        base,
        base + timedelta(seconds=60),
        base + timedelta(seconds=120),
        base + timedelta(seconds=180),
        base + timedelta(seconds=780),   # large 600s gap from previous
        base + timedelta(seconds=840),
    ]
    activities = [make_activity(t, "A") for t in a_times]

    # Action B: only 2 timestamps -> ignored
    b_times = [base + timedelta(seconds=5), base + timedelta(seconds=10)]
    activities += [make_activity(t, "B") for t in b_times]

    # Lower threshold to make detection easier
    analyzer.anomaly_threshold = 1.0
    anomalies = analyzer.detect_anomalies(activities)

    # Expect exactly one anomaly for A at the time ending the large interval
    assert isinstance(anomalies, list)
    assert len(anomalies) >= 1
    # Find the anomaly for action A with the expected timestamp
    expected_ts = (base + timedelta(seconds=780)).isoformat()
    a_anoms = [a for a in anomalies if a["action"] == "A" and a["timestamp"] == expected_ts]
    assert len(a_anoms) == 1
    assert "Unusual interval" in a_anoms[0]["reason"]
    # z_score should be >= threshold (1.0) here
    assert a_anoms[0]["z_score"] >= pytest.approx(1.0)


def test_ActivityAnalyzer_detect_anomalies_insufficient_data(analyzer):
    """detect_anomalies should return empty when fewer than 5 activities overall."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [make_activity(base + timedelta(seconds=i * 60), "A") for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_ActivityAnalyzer_detect_anomalies_no_stddev(analyzer):
    """detect_anomalies should return no anomalies when intervals have zero standard deviation."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    # 6 timestamps all equally spaced for action 'A'
    activities = [make_activity(base + timedelta(seconds=60 * i), "A") for i in range(6)]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []