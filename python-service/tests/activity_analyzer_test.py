import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Provide an ActivityAnalyzer instance for tests."""
    return ActivityAnalyzer()


@pytest.fixture
def make_activity():
    """Factory to create activity dicts with given action and timestamp."""
    def _make(action="action", ts=None):
        return {"action": action, "timestamp": ts}
    return _make


def test_activitypattern_to_dict_basic():
    """ActivityPattern.to_dict returns expected dictionary structure."""
    ap = ActivityPattern(pattern_type="peak_hours", description="High activity", confidence=0.85)
    d = ap.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "High activity"
    assert d["confidence"] == 0.85


def test_activityanalyzer_init_defaults(analyzer):
    """ActivityAnalyzer initializes with default thresholds."""
    assert analyzer.peak_hour_threshold == 0.2
    assert analyzer.anomaly_threshold == 3.0


@pytest.mark.parametrize(
    "input_ts, expect_none",
    [
        (datetime(2021, 1, 1, 12, 0, 0), False),
        ("2021-01-01T12:00:00Z", False),
        ("2021-01-01T12:00:00+00:00", False),
        ("not-a-date", True),
        (None, True),
    ],
)
def test_activityanalyzer_parse_timestamp_various_types(analyzer, input_ts, expect_none):
    """_parse_timestamp handles datetime objects, ISO strings, and invalid values."""
    result = analyzer._parse_timestamp(input_ts)
    if expect_none:
        assert result is None
    else:
        assert isinstance(result, datetime)


def test_activityanalyzer_parse_timestamp_handles_valueerror_gracefully(monkeypatch, analyzer):
    """_parse_timestamp should gracefully handle ValueError from datetime.fromisoformat."""
    # Patch datetime.fromisoformat to raise a ValueError
    import src.activity_analyzer as mod

    def boom(_):
        raise ValueError("bad format")

    monkeypatch.setattr(mod.datetime, "fromisoformat", boom, raising=True)
    # Even though the string is normally valid, our patched fromisoformat raises
    assert analyzer._parse_timestamp("2021-01-01T00:00:00Z") is None


def test_activityanalyzer_analyze_patterns_combines_internal_detectors(analyzer, make_activity):
    """analyze_patterns should call internal detectors and combine their results."""
    activities = [
        make_activity("a", "2021-01-01T00:00:00Z"),
        make_activity("b", "2021-01-01T01:00:00Z"),
    ]

    mock_peak = [ActivityPattern("peak_hours", "desc1", 0.9)]
    mock_seq = [ActivityPattern("action_sequence", "desc2", 0.8)]
    mock_reg = [ActivityPattern("regularity", "desc3", 0.7)]

    with patch.object(analyzer, "_detect_peak_hours", return_value=mock_peak) as p1, \
         patch.object(analyzer, "_detect_action_sequences", return_value=mock_seq) as p2, \
         patch.object(analyzer, "_detect_regularity", return_value=mock_reg) as p3:
        patterns = analyzer.analyze_patterns(activities)

    p1.assert_called_once_with(activities)
    p2.assert_called_once_with(activities)
    p3.assert_called_once_with(activities)

    assert len(patterns) == 3
    assert [p.pattern_type for p in patterns] == ["peak_hours", "action_sequence", "regularity"]


def test_activityanalyzer_analyze_patterns_empty_returns_empty(analyzer):
    """analyze_patterns should return empty list when no activities are provided."""
    assert analyzer.analyze_patterns([]) == []


def test_activityanalyzer_get_user_score_with_valid_data(analyzer, make_activity):
    """get_user_score computes expected score with chronological timestamps."""
    # 5 actions over 5 days; 3 unique actions
    base = datetime(2021, 1, 1, 0, 0, 0)
    activities = [
        make_activity("login", (base + timedelta(days=0)).isoformat()),
        make_activity("click", (base + timedelta(days=1)).isoformat()),
        make_activity("logout", (base + timedelta(days=2)).isoformat()),
        make_activity("login", (base + timedelta(days=3)).isoformat()),
        make_activity("click", (base + timedelta(days=5)).isoformat()),
    ]
    # Expected:
    # total_actions=5
    # unique_actions=3 -> diversity_score=0.6
    # days_active=(day5 - day0)=5 -> actions_per_day=1 -> frequency_score=0.1
    # volume_score=0.05
    # final=(0.6*0.3 + 0.1*0.4 + 0.05*0.3) * 100 = 23.5
    score = analyzer.get_user_score(activities)
    assert score == 23.5


def test_activityanalyzer_get_user_score_no_timestamps_uses_total_actions_for_frequency(analyzer, make_activity):
    """If timestamps are missing/invalid, frequency uses total actions directly."""
    activities = [make_activity("a", "invalid") for _ in range(25)]
    # total=25; unique=1; diversity=0.04; actions_per_day=25 -> freq=1.0; volume=0.25
    # final=(0.04*0.3 + 1.0*0.4 + 0.25*0.3)*100 = 48.7
    score = analyzer.get_user_score(activities)
    assert score == 48.7


def test_activityanalyzer_get_user_score_unsorted_timestamps_days_active_min_one(analyzer, make_activity):
    """Unsorted timestamps should not produce negative days_active; minimum should be 1."""
    t1 = datetime(2021, 1, 10, 0, 0, 0).isoformat()
    t0 = datetime(2021, 1, 1, 0, 0, 0).isoformat()
    activities = [
        make_activity("a", t1),
        make_activity("b", t1),
        make_activity("c", t0),  # last is earlier than first
        make_activity("d", t0),
    ]
    # total=4; unique=4 -> diversity=1.0; days_active => max(negative,1)=1 -> freq=0.4; volume=0.04
    # final=(1.0*0.3 + 0.4*0.4 + 0.04*0.3)*100=47.2
    score = analyzer.get_user_score(activities)
    assert score == 47.2


def test_activityanalyzer_detect_anomalies_flags_outlier_with_lowered_threshold(analyzer, make_activity):
    """detect_anomalies should flag an unusual interval when threshold is lowered."""
    base = datetime(2021, 1, 1, 0, 0, 0)
    # Clicks at 0m,1m,2m,3m,20m -> intervals 60,60,60,1020; outlier at last gap
    activities = [
        make_activity("click", (base + timedelta(minutes=0)).isoformat()),
        make_activity("click", (base + timedelta(minutes=1)).isoformat()),
        make_activity("click", (base + timedelta(minutes=2)).isoformat()),
        make_activity("click", (base + timedelta(minutes=3)).isoformat()),
        make_activity("click", (base + timedelta(minutes=20)).isoformat()),
    ]
    # Need at least 5 activities overall (met) and >=3 timestamps for the action (met)
    analyzer.anomaly_threshold = 1.5
    anomalies = analyzer.detect_anomalies(activities)
    assert len(anomalies) == 1
    anomaly = anomalies[0]
    assert anomaly["action"] == "click"
    assert anomaly["timestamp"] == (base + timedelta(minutes=20)).isoformat()
    assert "Unusual interval" in anomaly["reason"]
    assert isinstance(anomaly["z_score"], float)


def test_activityanalyzer_detect_anomalies_no_variation_returns_empty(analyzer, make_activity):
    """detect_anomalies should return empty when intervals are constant (std_dev == 0)."""
    base = datetime(2021, 1, 1, 0, 0, 0)
    activities = [
        make_activity("click", (base + timedelta(minutes=i)).isoformat()) for i in [0, 1, 2, 3, 4]
    ]
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_anomalies_ignores_actions_with_few_timestamps(analyzer, make_activity):
    """detect_anomalies should ignore actions that do not have enough timestamps."""
    base = datetime(2021, 1, 1, 0, 0, 0)
    activities = [
        make_activity("view", (base + timedelta(minutes=0)).isoformat()),
        make_activity("view", (base + timedelta(minutes=1)).isoformat()),
        make_activity("click", (base + timedelta(minutes=2)).isoformat()),
        make_activity("click", (base + timedelta(minutes=3)).isoformat()),
        make_activity("click", (base + timedelta(minutes=4)).isoformat()),
    ]
    # 'view' only has 2 timestamps and should be ignored; 'click' has 3 with equal intervals -> no anomalies
    anomalies = analyzer.detect_anomalies(activities)
    assert anomalies == []


def test_activityanalyzer_detect_peak_hours_identifies_hours(analyzer, make_activity):
    """_detect_peak_hours should identify hours with proportion above threshold."""
    base = datetime(2021, 1, 1, 9, 0, 0)
    activities = [
        make_activity("a", (base + timedelta(minutes=0)).isoformat()),   # 09
        make_activity("b", (base + timedelta(minutes=10)).isoformat()),  # 09
        make_activity("c", (base + timedelta(minutes=20)).isoformat()),  # 09
        make_activity("d", (base + timedelta(hours=1)).isoformat()),     # 10
        make_activity("e", (base + timedelta(hours=2)).isoformat()),     # 11
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "09:00" in p.description
    assert p.confidence == 0.85


def test_activityanalyzer_detect_peak_hours_no_valid_timestamps_returns_empty(analyzer, make_activity):
    """_detect_peak_hours should return empty when no timestamps can be parsed."""
    activities = [make_activity("a", "invalid"), make_activity("b", None)]
    assert analyzer._detect_peak_hours(activities) == []


def test_activityanalyzer_detect_action_sequences_common_sequences(analyzer, make_activity):
    """_detect_action_sequences should detect common 3-action sequences occurring at least twice."""
    # Sequence A,B,C appears twice
    actions = ["A", "B", "C", "D", "A", "B", "C", "E", "F"]
    activities = [make_activity(a, (datetime(2021, 1, 1) + timedelta(minutes=i)).isoformat()) for i, a in enumerate(actions)]
    patterns = analyzer._detect_action_sequences(activities)
    assert any(p.pattern_type == "action_sequence" and "Common sequence: A → B → C (occurred 2 times)" in p.description for p in patterns)


def test_activityanalyzer_detect_regularity_detects_regular_pattern(analyzer, make_activity):
    """_detect_regularity should identify highly regular intervals."""
    base = datetime(2021, 1, 1, 0, 0, 0)
    activities = [make_activity("x", (base + timedelta(minutes=i)).isoformat()) for i in [0, 1, 2, 3, 4, 5]]
    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV: 0.00" in p.description
    assert p.confidence == 0.9


def test_activityanalyzer_detect_regularity_irregular_or_insufficient_data(analyzer, make_activity):
    """_detect_regularity should return empty for irregular activity or insufficient data."""
    # Insufficient
    base = datetime(2021, 1, 1, 0, 0, 0)
    few = [make_activity("x", (base + timedelta(minutes=i)).isoformat()) for i in [0, 1, 2, 3]]
    assert analyzer._detect_regularity(few) == []

    # Irregular timing
    irregular = [make_activity("x", (base + timedelta(minutes=i)).isoformat()) for i in [0, 1, 5, 6, 12, 20]]
    assert analyzer._detect_regularity(irregular) == []


def test_activityanalyzer_analyze_patterns_propagates_exceptions_from_detectors(analyzer, make_activity):
    """analyze_patterns should propagate exceptions if a detector fails (no internal swallowing)."""
    activities = [make_activity("a", "2021-01-01T00:00:00Z")]

    with patch.object(analyzer, "_detect_peak_hours", side_effect=RuntimeError("boom")):
        with pytest.raises(RuntimeError):
            analyzer.analyze_patterns(activities)