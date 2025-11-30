from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
import math
import datetime  # intentionally import module for test patching
from datetime import datetime as _dt, timezone as _tz


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
        # If already a datetime object
        if isinstance(ts, _dt):
            return ts
        # If string, attempt ISO parse
        if isinstance(ts, str):
            s = ts.strip()
            # Handle 'Z' suffix by converting to +00:00
            if s.endswith("Z"):
                s = s[:-1] + "+00:00"
            try:
                # Try module-level fromisoformat if available (so tests can patch it)
                func = getattr(datetime, "fromisoformat", None)
                if callable(func):
                    return func(s)  # type: ignore[misc]
                # Fallback to classmethod
                return _dt.fromisoformat(s)
            except Exception:
                return None
        return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        hours_count: Dict[int, int] = {}
        total_valid = 0
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            total_valid += 1
            # normalize to UTC hour if timezone-aware
            if ts.tzinfo is not None:
                ts = ts.astimezone(_tz.utc)
            hour = ts.hour
            hours_count[hour] = hours_count.get(hour, 0) + 1

        if total_valid == 0:
            return []

        patterns: List[ActivityPattern] = []
        # Determine hours exceeding threshold
        for hour, count in sorted(hours_count.items()):
            frac = count / total_valid
            if frac >= self.peak_hour_threshold:
                desc = f"Peak activity hours: {hour:02d}:00 (count {count}, {frac:.0%})"
                patterns.append(ActivityPattern("peak_hours", desc, 0.85))

        return patterns

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Need at least 3 activities to form a 3-action sequence
        if len(activities) < 3:
            return []
        actions = [str(a.get("action")) for a in activities]
        triples_count: Dict[Tuple[str, str, str], int] = {}
        for i in range(len(actions) - 2):
            triple = (actions[i], actions[i + 1], actions[i + 2])
            triples_count[triple] = triples_count.get(triple, 0) + 1

        patterns: List[ActivityPattern] = []
        for triple, cnt in triples_count.items():
            if cnt >= 2:
                seq_str = " → ".join(triple)
                desc = f"{seq_str} (occurred {cnt} times)"
                patterns.append(ActivityPattern("action_sequence", desc, 0.75))
        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        # Collect and sort valid timestamps
        timestamps: List[_dt] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                timestamps.append(ts)
        if len(timestamps) < 3:
            return []

        timestamps.sort()
        intervals: List[float] = []
        for i in range(1, len(timestamps)):
            delta = (timestamps[i] - timestamps[i - 1]).total_seconds()
            # Ignore non-positive intervals
            if delta > 0:
                intervals.append(delta)

        if len(intervals) < 3:
            return []

        mean = sum(intervals) / len(intervals)
        if mean == 0:
            return []

        var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std = math.sqrt(var)
        # Coefficient of variation: std/mean. Treat highly regular if CV < 0.1
        if std / mean < 0.1:
            desc = f"Highly regular intervals detected (~{mean:.1f}s)"
            return [ActivityPattern("regularity", desc, 0.9)]
        return []

    def analyze_patterns(self, activities: Optional[List[Dict[str, Any]]]) -> List[ActivityPattern]:
        if not activities:
            return []
        patterns: List[ActivityPattern] = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        total_actions = len(activities)
        if total_actions == 0:
            return 0.0

        # Diversity: unique actions
        unique_actions = len({a.get("action") for a in activities})
        diversity = unique_actions / total_actions if total_actions else 0.0

        # Frequency: actions per day normalized to [0,1] with 10 as cap
        dates: List[_dt] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                dates.append(ts)
        if dates:
            days = len({(dt.astimezone(_tz.utc).date() if dt.tzinfo else dt.date()) for dt in dates})
            days = max(days, 1)
            actions_per_day = total_actions / days
        else:
            # Fallback when timestamps cannot be parsed at all: use total
            actions_per_day = total_actions

        frequency = min(actions_per_day / 10.0, 1.0)

        # Volume: scale by 100 actions
        volume = min(total_actions / 100.0, 1.0)

        score = (0.3 * diversity + 0.4 * frequency + 0.3 * volume) * 100.0
        return round(score, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if len(activities) < 5:
            return []

        # Group timestamps by action
        by_action: Dict[str, List[_dt]] = {}
        for a in activities:
            action = str(a.get("action"))
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is None:
                continue
            by_action.setdefault(action, []).append(ts)

        anomalies: List[Dict[str, Any]] = []

        for action, ts_list in by_action.items():
            if len(ts_list) < 3:
                continue
            ts_list.sort()
            intervals: List[float] = []
            # Keep mapping interval index -> timestamp (ending time)
            end_timestamps: List[_dt] = []
            for i in range(1, len(ts_list)):
                delta = (ts_list[i] - ts_list[i - 1]).total_seconds()
                if delta > 0:
                    intervals.append(delta)
                    end_timestamps.append(ts_list[i])

            if len(intervals) < 3:
                continue

            mean = sum(intervals) / len(intervals)
            var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
            std = math.sqrt(var)
            if std == 0:
                continue

            for interval, end_ts in zip(intervals, end_timestamps):
                z = (interval - mean) / std
                if z >= self.anomaly_threshold:
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": self._to_iso_z(end_ts),
                            "z_score": round(z, 2),
                            "reason": f"Unusual interval detected for action '{action}'",
                        }
                    )

        return anomalies

    @staticmethod
    def _to_iso_z(dt: _dt) -> str:
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=_tz.utc)
        else:
            dt = dt.astimezone(_tz.utc)
        return dt.isoformat().replace("+00:00", "Z")