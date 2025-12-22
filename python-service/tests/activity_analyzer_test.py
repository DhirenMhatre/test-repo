import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta, timezone

from src.activity_analyzer import ActivityPattern, ActivityAnalyzer


@pytest.fixture
def analyzer():
    """Create an ActivityAnalyzer instance for testing."""
    return ActivityAnalyzer()


def make_activity(action, ts):
    """Helper to create an activity dict."""
    return {"action": action, "timestamp": ts}


def test_activitypattern_init_and_to_dict_basic():
    """Test ActivityPattern initialization and to_dict output."""
    pattern = ActivityPattern("peak_hours", "High activity during certain hours", 0.85)
    assert pattern.pattern_type == "peak_hours"
    assert pattern.description == "High activity during certain hours"
    assert pattern.confidence == pytest.approx(0.85)

    d = pattern.to_dict()
    assert d["pattern_type"] == "peak_hours"
    assert d["description"] == "High activity during certain hours"
    assert d["confidence"] == pytest.approx(0.85)


def test_activityanalyzer_init_defaults(analyzer):
    """Test ActivityAnalyzer default initialization values."""
    assert analyzer.peak_hour_threshold == pytest.approx(0.2)
    assert analyzer.anomaly_threshold == pytest.approx(3.0)


@pytest.mark.parametrize(
    "input_ts, expect_dt, expect_tzinfo",
    [
        (datetime(2024, 1, 1, 12, 0, 0), datetime(2024, 1, 1, 12, 0, 0), None),
        ("2024-01-01T12:00:00Z", datetime(2024, 1, 1, 12, 0, 0, tzinfo=timezone.utc), timezone.utc),
        ("2024-01-01T12:00:00", datetime(2024, 1, 1, 12, 0, 0), None),
        ("not-a-date", None, None),
    ],
)
def test_activityanalyzer_parse_timestamp_various(analyzer, input_ts, expect_dt, expect_tzinfo):
    """Test _parse_timestamp with datetime, ISO-8601 with Z, naive ISO, and invalid strings."""
    result = analyzer._parse_timestamp(input_ts)
    if expect_dt is None:
        assert result is None
    else:
        # Compare the critical components
        assert result.year == expect_dt.year
        assert result.month == expect_dt.month
        assert result.day == expect_dt.day
        assert result.hour == expect_dt.hour
        assert result.minute == expect_dt.minute
        # tzinfo check: for naive -> None; for Z -> offset 0
        if expect_tzinfo is None:
            assert result.tzinfo is None
        else:
            assert result.utcoffset() == expect_dt.utcoffset()


def test_activityanalyzer_detect_peak_hours_basic(analyzer):
    """Test _detect_peak_hours identifies hours exceeding threshold (> 0.2)."""
    base = datetime(2024, 1, 1, 10, 0, 0)
    activities = []
    # 3 activities at hour 10
    for i in range(3):
        activities.append(make_activity("A", base + timedelta(minutes=i)))
    # 7 activities spread across other hours
    for h in [0, 1, 2, 3, 4, 5, 6]:
        activities.append(make_activity("B", datetime(2024, 1, 1, h, 0, 0)))

    patterns = analyzer._detect_peak_hours(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "peak_hours"
    assert "10:00" in p.description
    assert p.confidence == pytest.approx(0.85)


def test_activityanalyzer_detect_peak_hours_threshold_boundary(analyzer):
    """Test _detect_peak_hours does not include hours with exactly threshold proportion (== 0.2)."""
    # 5 activities, each in a different hour -> each hour has 20% (== threshold), not included
    activities = [
        make_activity("A", datetime(2024, 1, 1, h, 0, 0)) for h in [0, 1, 2, 3, 4]
    ]
    patterns = analyzer._detect_peak_hours(activities)
    assert patterns == []


def test_activityanalyzer_detect_action_sequences_common(analyzer):
    """Test _detect_action_sequences identifies common 3-action sequences occurring >= 2 times."""
    actions = ["A", "B", "C", "D", "A", "B", "C"]
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [make_activity(a, base + timedelta(minutes=i)) for i, a in enumerate(actions)]

    patterns = analyzer._detect_action_sequences(activities)
    # Expect one common sequence: A → B → C occurred twice
    assert any(
        p.pattern_type == "action_sequence" and "A → B → C" in p.description and "occurred 2 times" in p.description
        for p in patterns
    )
    # Confidence should be 0.75 for these patterns
    for p in patterns:
        if p.pattern_type == "action_sequence":
            assert p.confidence == pytest.approx(0.75)


def test_activityanalyzer_detect_action_sequences_short_input(analyzer):
    """Test _detect_action_sequences returns empty list when fewer than 3 activities are provided."""
    activities = [make_activity("A", datetime(2024, 1, 1, 0, 0, 0)), make_activity("B", datetime(2024, 1, 1, 0, 1, 0))]
    assert analyzer._detect_action_sequences(activities) == []


def test_activityanalyzer_detect_regularity_highly_regular(analyzer):
    """Test _detect_regularity identifies highly regular activity (CV < 0.3)."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    # 6 timestamps exactly 60 seconds apart -> 5 identical intervals => CV = 0.0
    activities = [make_activity("X", base + timedelta(seconds=60 * i)) for i in range(6)]

    patterns = analyzer._detect_regularity(activities)
    assert len(patterns) == 1
    p = patterns[0]
    assert p.pattern_type == "regularity"
    assert "CV: 0.00" in p.description
    assert p.confidence == pytest.approx(0.9)


def test_activityanalyzer_detect_regularity_insufficient_or_invalid(analyzer):
    """Test _detect_regularity returns empty when fewer than 5 valid timestamps are present."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    # 5 activities provided but one invalid timestamp -> only 4 valid parsed
    activities = [
        make_activity("X", base + timedelta(seconds=60 * i)) for i in range(4)
    ] + [make_activity("X", "invalid-timestamp")]

    patterns = analyzer._detect_regularity(activities)
    assert patterns == []


def test_activityanalyzer_get_user_score_basic(analyzer):
    """Test get_user_score with valid timestamps calculates correct composite score."""
    # 20 actions over 5 days difference: first on Jan 1, last on Jan 6 -> days = 5
    first = datetime(2024, 1, 1, 0, 0, 0)
    last = datetime(2024, 1, 6, 0, 0, 0)
    activities = []
    # 10 A then 10 B
    for i in range(10):
        activities.append(make_activity("A", first + timedelta(hours=i)))
    # Spread remaining to reach last date
    for i in range(10, 20):
        # ensure last timestamp aligns with 'last'
        ts = first + timedelta(hours=i)
        if i == 19:
            ts = last
        activities.append(make_activity("B", ts))

    score = analyzer.get_user_score(activities)
    # Expected 25.0 as per calculation in analysis
    assert score == pytest.approx(25.0)


def test_activityanalyzer_get_user_score_no_valid_timestamps(analyzer):
    """Test get_user_score when first or last timestamp is invalid; falls back to total_actions for frequency."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [
        make_activity("X", "bad-timestamp"),  # first invalid
        make_activity("X", base + timedelta(hours=1)),
        make_activity("Y", base + timedelta(hours=2)),
        make_activity("Y", base + timedelta(hours=3)),
        make_activity("Z", base + timedelta(hours=4)),  # last valid
    ]

    score = analyzer.get_user_score(activities)
    # Calculation with total_actions=5, unique_actions=3, actions_per_day = total_actions (fallback)
    # diversity = 3/5=0.6, frequency=min(5/10,1)=0.5, volume=min(5/100,1)=0.05
    # final = (0.6*0.3 + 0.5*0.4 + 0.05*0.3)*100 = 39.5
    assert score == pytest.approx(39.5)


def test_activityanalyzer_get_user_score_empty(analyzer):
    """Test get_user_score returns 0.0 for empty activity list."""
    assert analyzer.get_user_score([]) == pytest.approx(0.0)


def test_activityanalyzer_detect_anomalies_flags_outlier(analyzer):
    """Test detect_anomalies flags an interval outlier based on z-score threshold."""
    analyzer.anomaly_threshold = 1.0  # relax threshold for easier detection in test
    base = datetime(2024, 1, 1, 12, 0, 0)

    activities = []
    # 'click' with mostly 60s intervals, one large interval
    click_times = [base, base + timedelta(seconds=60), base + timedelta(seconds=120),
                   base + timedelta(seconds=180), base + timedelta(seconds=1000)]
    for t in click_times:
        activities.append(make_activity("click", t))

    # 'view' regular intervals (should not produce anomalies)
    view_times = [base + timedelta(minutes=30 + i * 5) for i in range(6)]
    for t in view_times:
        activities.append(make_activity("view", t))

    anomalies = analyzer.detect_anomalies(activities)
    # Expect at least one anomaly for 'click' at the timestamp after the large interval (1000s)
    assert any(a["action"] == "click" for a in anomalies)
    click_anoms = [a for a in anomalies if a["action"] == "click"]
    assert len(click_anoms) >= 1
    # The anomalous timestamp should be the last 'click' timestamp
    assert click_anoms[0]["timestamp"] == click_times[-1].isoformat()
    assert "Unusual interval" in click_anoms[0]["reason"]
    # z_score has been rounded to two decimals; ensure it's greater than the set threshold
    assert click_anoms[0]["z_score"] > analyzer.anomaly_threshold


def test_activityanalyzer_detect_anomalies_insufficient_activities(analyzer):
    """Test detect_anomalies returns empty list when fewer than 5 activities overall."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = [make_activity("A", base + timedelta(minutes=i)) for i in range(4)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_detect_anomalies_ignores_groups_with_few_timestamps(analyzer):
    """Test detect_anomalies ignores actions with fewer than 3 timestamps."""
    base = datetime(2024, 1, 1, 0, 0, 0)
    activities = []
    # Action A only 2 timestamps
    activities += [make_activity("A", base), make_activity("A", base + timedelta(minutes=1))]
    # Action B enough timestamps but regular
    activities += [make_activity("B", base + timedelta(minutes=10 * i)) for i in range(5)]
    assert analyzer.detect_anomalies(activities) == []


def test_activityanalyzer_analyze_patterns_orchestration_with_mocks(analyzer):
    """Test analyze_patterns composes results from the three detection methods."""
    activities = [
        make_activity("A", datetime(2024, 1, 1, 0, 0, 0)),
        make_activity("B", datetime(2024, 1, 1, 1, 0, 0)),
        make_activity("C", datetime(2024, 1, 1, 2, 0, 0)),
        make_activity("A", datetime(2024, 1, 1, 3, 0, 0)),
        make_activity("B", datetime(2024, 1, 1, 4, 0, 0)),
    ]

    mock_peak = [ActivityPattern("peak_hours", "Mock peak", 0.85)]
    mock_seq = [ActivityPattern("action_sequence", "Mock sequence", 0.75)]
    mock_reg = [ActivityPattern("regularity", "Mock regularity", 0.9)]

    with patch.object(analyzer, "_detect_peak_hours", return_value=mock_peak) as m_peak, \
         patch.object(analyzer, "_detect_action_sequences", return_value=mock_seq) as m_seq, \
         patch.object(analyzer, "_detect_regularity", return_value=mock_reg) as m_reg:
        patterns = analyzer.analyze_patterns(activities)

        m_peak.assert_called_once_with(activities)
        m_seq.assert_called_once_with(activities)
        m_reg.assert_called_once_with(activities)

        # Combined results in order of extension
        assert patterns == mock_peak + mock_seq + mock_reg


def test_activityanalyzer_analyze_patterns_empty_short_circuits(analyzer):
    """Test analyze_patterns returns empty for no activities and does not call detection methods."""
    with patch.object(analyzer, "_detect_peak_hours") as m_peak, \
         patch.object(analyzer, "_detect_action_sequences") as m_seq, \
         patch.object(analyzer, "_detect_regularity") as m_reg:
        patterns = analyzer.analyze_patterns([])
        assert patterns == []
        m_peak.assert_not_called()
        m_seq.assert_not_called()
        m_reg.assert_not_called()


def test_activityanalyzer_detect_peak_hours_raises_when_parse_raises(analyzer):
    """Test that _detect_peak_hours propagates exceptions from _parse_timestamp (mocked)."""
    activities = [make_activity("A", "any")]
    with patch.object(analyzer, "_parse_timestamp", side_effect=ValueError("bad-timestamp")):
        with pytest.raises(ValueError):
            analyzer._detect_peak_hours(activities)