from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
from math import sqrt

# Create a patchable wrapper for fromisoformat while still using the real datetime class internally
from datetime import datetime as _dt, timedelta, timezone


class _DatetimeWrapper:
    @staticmethod
    def fromisoformat(value: str) -> _dt:
        return _dt.fromisoformat(value)


# Expose a name that tests can patch: src.activity_analyzer.datetime.fromisoformat
datetime = _DatetimeWrapper


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

    def _parse_timestamp(self, ts: Any) -> Optional[_dt]:
        if isinstance(ts, _dt):
            return ts
        if not isinstance(ts, str):
            return None
        s = ts.strip()
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        try:
            # Use the patchable wrapper
            parsed = datetime.fromisoformat(s)
        except Exception:
            return None
        return parsed

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []

        hours_counter: Counter[int] = Counter()
        valid_count = 0
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            valid_count += 1
            hours_counter[ts.hour] += 1

        if valid_count == 0:
            return []

        peak_hours = sorted(
            [h for h, c in hours_counter.items() if (c / valid_count) > self.peak_hour_threshold]
        )
        if not peak_hours:
            return []

        hours_str = ", ".join(f"{h:02d}:00" for h in peak_hours)
        description = f"High activity during hours: {hours_str}"
        return [ActivityPattern("peak_hours", description, 0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []

        # Preserve original order as provided
        actions: List[str] = []
        for act in activities:
            a = act.get("action")
            if isinstance(a, str) and a:
                actions.append(a)

        # Consider sequences of length 3
        if len(actions) < 3:
            return []

        seq_counts: Counter[Tuple[str, str, str]] = Counter()
        for i in range(len(actions) - 2):
            seq = (actions[i], actions[i + 1], actions[i + 2])
            seq_counts[seq] += 1

        # Filter sequences that occurred at least twice
        frequent = [(seq, cnt) for seq, cnt in seq_counts.items() if cnt >= 2]
        if not frequent:
            return []

        # Sort by frequency desc, then by sequence lexicographically for determinism; take top 3
        frequent.sort(key=lambda x: (-x[1], x[0]))
        top = frequent[:3]

        patterns: List[ActivityPattern] = []
        for seq, cnt in top:
            seq_str = " → ".join(seq)
            description = f"Common sequence: {seq_str} (occurred {cnt} times)"
            patterns.append(ActivityPattern("action_sequence", description, 0.75))
        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []

        timestamps: List[_dt] = []
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is not None:
                timestamps.append(ts)

        if len(timestamps) < 3:
            return []

        timestamps.sort()
        intervals: List[float] = []
        for i in range(len(timestamps) - 1):
            delta = timestamps[i + 1] - timestamps[i]
            intervals.append(delta.total_seconds())

        if not intervals:
            return []

        mean = sum(intervals) / len(intervals)
        if mean <= 0:
            return []

        # Population standard deviation
        var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std = sqrt(var)
        if std == 0:
            cv = 0.0
        else:
            cv = std / mean

        # Threshold for being considered highly regular
        if cv <= 0.05:
            description = f"Highly regular activity pattern (CV: {cv:.2f})"
            return [ActivityPattern("regularity", description, 0.9)]
        return []

    def analyze_patterns(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        patterns: List[ActivityPattern] = []
        # Order matters for tests
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        total_actions = len(activities)
        if total_actions == 0:
            return 0.0

        unique_actions = len({act.get("action") for act in activities})
        diversity = unique_actions / total_actions if total_actions > 0 else 0.0

        # Frequency: actions per day; if no valid timestamps, treat as same day
        valid_ts: List[_dt] = []
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is not None:
                valid_ts.append(ts)

        if valid_ts:
            valid_ts.sort()
            days_active = (valid_ts[-1].date() - valid_ts[0].date()).days
            if days_active == 0:
                actions_per_day = float(total_actions)
            else:
                actions_per_day = total_actions / days_active
        else:
            actions_per_day = float(total_actions)

        frequency = min(actions_per_day / 10.0, 1.0)
        volume = min(total_actions / 100.0, 1.0)

        score = (diversity * 0.3 + frequency * 0.4 + volume * 0.3) * 100.0
        return round(score, 2)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Require a minimum total activity count
        if len(activities) < 5:
            return []

        # Group valid timestamps by action
        grouped: defaultdict[str, List[_dt]] = defaultdict(list)
        actions_present: set[str] = set()
        for act in activities:
            action = act.get("action")
            actions_present.add(action)
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is not None and isinstance(action, str):
                grouped[action].append(ts)

        anomalies: List[Dict[str, Any]] = []
        for action, ts_list in grouped.items():
            if len(ts_list) < 3:
                continue
            ts_list.sort()
            intervals = [(ts_list[i + 1] - ts_list[i]).total_seconds() for i in range(len(ts_list) - 1)]
            if not intervals:
                continue
            mean = sum(intervals) / len(intervals)
            var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
            std = sqrt(var)
            if std == 0:
                continue

            for i, interval in enumerate(intervals):
                z = (interval - mean) / std
                if z >= self.anomaly_threshold:
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": ts_list[i + 1].isoformat(),
                            "z_score": round(z, 2),
                            "reason": f"Unusual interval detected: {int(interval)}s vs avg {int(mean)}s",
                        }
                    )

        return anomalies