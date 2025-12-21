from __future__ import annotations

import statistics
from collections import Counter, defaultdict
import datetime as _dt
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional


class _DateTimeShim:
    """
    Shim to expose a fromisoformat attribute that tests can monkeypatch.
    By default, it delegates to datetime.datetime.fromisoformat.
    """

    def __init__(self) -> None:
        # Keep a reference to the real fromisoformat to delegate to
        self._delegate = _dt.datetime.fromisoformat

    def fromisoformat(self, s: str) -> _dt.datetime:
        return self._delegate(s)


# Expose a mutable attribute `fromisoformat` that tests can patch
datetime = _DateTimeShim()


@dataclass
class ActivityPattern:
    pattern_type: str
    description: str
    confidence: float

    def to_dict(self) -> Dict[str, Any]:
        return {
            "pattern_type": self.pattern_type,
            "description": self.description,
            "confidence": self.confidence,
        }


class ActivityAnalyzer:
    def __init__(self, peak_hour_threshold: float = 0.2, anomaly_threshold: float = 3.0) -> None:
        self.peak_hour_threshold = peak_hour_threshold
        self.anomaly_threshold = anomaly_threshold

    def _parse_timestamp(self, ts: Any) -> Optional[_dt.datetime]:
        if isinstance(ts, _dt.datetime):
            return ts
        if isinstance(ts, str):
            try:
                # Support Zulu suffix by converting to +00:00
                if ts.endswith("Z"):
                    ts = ts[:-1] + "+00:00"
                # Delegate via shim to allow monkeypatching in tests
                return datetime.fromisoformat(ts)
            except Exception:
                return None
        # Unsupported type
        return None

    def analyze_patterns(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        patterns = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        if not activities:
            return 0.0

        total_actions = len(activities)
        unique_actions = len({a.get("action") for a in activities})

        # Diversity: unique actions / total actions
        diversity = (unique_actions / total_actions) if total_actions else 0.0

        # Determine actions per day: need valid timestamps
        timestamps: List[_dt.datetime] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                timestamps.append(ts)

        if timestamps:
            timestamps.sort()
            days_span = (timestamps[-1] - timestamps[0]).days
            # Avoid division by zero; if same day, treat as 1 day span for per-day frequency
            if days_span <= 0:
                actions_per_day = float(total_actions)
            else:
                actions_per_day = total_actions / days_span
        else:
            # Fallback when no valid timestamps: assume 1 day span
            actions_per_day = float(total_actions)

        # Frequency component normalized to [0,1] assuming 10 actions/day is high
        freq = min(actions_per_day / 10.0, 1.0)
        # Volume component normalized to [0,1] assuming 100 actions total is high
        volume = min(total_actions / 100.0, 1.0)

        score = (0.3 * diversity + 0.4 * freq + 0.3 * volume) * 100.0
        # Keep a single decimal as tests expect exact values like 20.0, 47.2
        return round(score, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if not activities:
            return []

        # Group timestamps by action
        by_action: Dict[Any, List[_dt.datetime]] = defaultdict(list)
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            action = a.get("action")
            if ts is not None and action is not None:
                by_action[action].append(ts)

        anomalies: List[Dict[str, Any]] = []
        for action, ts_list in by_action.items():
            if len(ts_list) < 3:
                # Need at least 3 timestamps to compute 2+ intervals and meaningful stats
                continue
            ts_list.sort()
            intervals = [int((ts_list[i + 1] - ts_list[i]).total_seconds()) for i in range(len(ts_list) - 1)]
            if not intervals:
                continue
            # If all intervals equal, no anomalies
            if all(iv == intervals[0] for iv in intervals):
                continue
            # Compute population std deviation; if zero, skip
            mean = statistics.fmean(intervals)
            stdev = statistics.pstdev(intervals)
            if stdev == 0:
                continue
            # Identify intervals with z-score above threshold
            for idx, iv in enumerate(intervals):
                z = abs((iv - mean) / stdev)
                if z >= self.anomaly_threshold:
                    # Use end timestamp of the interval
                    end_ts = ts_list[idx + 1]
                    anomalies.append({
                        "action": action,
                        "timestamp": end_ts.isoformat(),
                        "reason": f"Unusual interval of {iv}s detected (z={z:.2f})",
                        "z_score": z,
                    })
        return anomalies

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Count occurrences per hour among valid timestamps
        hours: List[int] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                hours.append(ts.hour)
        if not hours:
            return []

        counts = Counter(hours)
        total = sum(counts.values())
        # Select hour with maximum count; break ties by earliest hour
        max_count = max(counts.values())
        candidate_hours = [h for h, c in counts.items() if c == max_count]
        peak_hour = min(candidate_hours)
        fraction = max_count / total if total else 0.0

        if fraction >= self.peak_hour_threshold:
            desc = f"High activity during hours: {peak_hour:02d}:00 (share: {fraction:.0%})"
            return [ActivityPattern(pattern_type="peak_hours", description=desc, confidence=0.85)]
        return []

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        # Sort by timestamp if available; otherwise keep order
        enriched: List[tuple[Optional[_dt.datetime], Any]] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            enriched.append((ts, a.get("action")))
        # Sort with None timestamps placed at end preserving original order among Nones
        enriched_sorted = sorted(
            enumerate(enriched),
            key=lambda x: ((x[1][0] is None), x[1][0] if x[1][0] is not None else _dt.datetime.max, x[0]),
        )
        ordered_actions = [enriched[i][1] for i, _ in enriched_sorted]

        # Collect 3-step sequences
        seq_counts: Counter = Counter()
        for i in range(len(ordered_actions) - 2):
            seq = tuple(ordered_actions[i : i + 3])
            if None in seq:
                continue
            seq_counts[seq] += 1

        patterns: List[ActivityPattern] = []
        for seq, cnt in seq_counts.items():
            if cnt >= 2:
                seq_str = " → ".join(str(s) for s in seq)
                desc = f"Common sequence: {seq_str} occurred {cnt} times"
                patterns.append(ActivityPattern(pattern_type="action_sequence", description=desc, confidence=0.75))
        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Require enough data points
        timestamps: List[_dt.datetime] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                timestamps.append(ts)
        if len(timestamps) < 5:
            return []

        timestamps.sort()
        intervals = [(timestamps[i + 1] - timestamps[i]).total_seconds() for i in range(len(timestamps) - 1)]
        if not intervals:
            return []

        mean = statistics.fmean(intervals)
        # If mean is zero, cannot compute CV meaningfully
        if mean == 0:
            return []

        stdev = statistics.pstdev(intervals)
        cv = stdev / mean if mean else float("inf")

        # Consider highly regular when CV is very low
        if cv <= 0.05:
            desc = f"Highly regular activity intervals detected (CV: {cv:.2f})"
            return [ActivityPattern(pattern_type="regularity", description=desc, confidence=0.9)]
        return []