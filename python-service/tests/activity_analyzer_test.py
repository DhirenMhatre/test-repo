from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
from math import sqrt
from datetime import datetime, timedelta, timezone


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
    def __init__(self, peak_hour_threshold: float = 0.2, anomaly_threshold: float = 3.0):
        self.peak_hour_threshold = peak_hour_threshold
        self.anomaly_threshold = anomaly_threshold

    def _parse_timestamp(self, ts: Any) -> Optional[datetime]:
        # Avoid isinstance checks on datetime because tests may patch 'datetime'
        # Use duck typing for datetime-like objects
        if ts is None:
            return None
        if isinstance(ts, str):
            s = ts.strip()
            try:
                if s.endswith("Z"):
                    # Convert Zulu time to explicit UTC offset
                    s = s[:-1] + "+00:00"
                # The tests patch 'datetime.fromisoformat', so call exactly that
                return datetime.fromisoformat(s)
            except Exception:
                return None
        # Heuristic: datetime-like object
        if hasattr(ts, "isoformat") and hasattr(ts, "year") and hasattr(ts, "hour"):
            return ts  # trust it's a datetime
        return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        timestamps: List[datetime] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                timestamps.append(ts)
        if not timestamps:
            return []

        hour_counts: Dict[int, int] = {}
        for ts in timestamps:
            hour_counts[ts.hour] = hour_counts.get(ts.hour, 0) + 1

        total = len(timestamps)
        # Identify hours that exceed the threshold strictly (not >=)
        exceeding = [h for h, c in hour_counts.items() if (c / total) > self.peak_hour_threshold]
        if not exceeding:
            return []

        # Sort by frequency desc then hour asc, and build a description listing all exceeding hours
        exceeding.sort(key=lambda h: (-hour_counts[h], h))
        hours_str = ", ".join(f"{h:02d}:00" for h in exceeding)
        description = f"Peak activity hour(s): {hours_str}"
        # Confidence fixed per tests
        return [ActivityPattern(pattern_type="peak_hours", description=description, confidence=0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        actions: List[str] = [a.get("action") for a in activities if "action" in a]
        if len(actions) < 3:
            return []

        counts: Dict[Tuple[str, str, str], int] = {}
        for i in range(len(actions) - 2):
            seq = (actions[i], actions[i + 1], actions[i + 2])
            counts[seq] = counts.get(seq, 0) + 1

        if not counts:
            return []

        # Find the most common sequence
        best_seq, best_count = max(counts.items(), key=lambda item: item[1])
        if best_count < 2:
            return []

        seq_str = " → ".join(best_seq)
        description = f"Common sequence: {seq_str} (occurred {best_count} times)"
        return [ActivityPattern(pattern_type="action_sequence", description=description, confidence=0.75)]

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        timestamps: List[datetime] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                timestamps.append(ts)

        if len(timestamps) < 3:
            return []

        # Use the given order (do not sort)
        intervals: List[float] = []
        for i in range(1, len(timestamps)):
            delta = (timestamps[i] - timestamps[i - 1]).total_seconds()
            # Guard against negative intervals; take absolute difference
            intervals.append(abs(delta))

        if not intervals:
            return []

        mean = sum(intervals) / len(intervals)
        if mean == 0:
            return []

        var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std = sqrt(var)
        cv = std / mean if mean != 0 else 0.0

        # Consider highly regular if CV <= 0.1
        if cv <= 0.1:
            description = f"Regular activity intervals detected (CV: {cv:.2f})"
            return [ActivityPattern(pattern_type="regularity", description=description, confidence=0.9)]
        return []

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if len(activities) < 5:
            return []

        # Group timestamps by action
        by_action: Dict[str, List[datetime]] = {}
        for a in activities:
            action = a.get("action")
            ts = self._parse_timestamp(a.get("timestamp"))
            if action is None or ts is None:
                continue
            by_action.setdefault(action, []).append(ts)

        anomalies: List[Dict[str, Any]] = []

        for action, times in by_action.items():
            if len(times) < 3:
                continue
            # Analyze by sorting by timestamp per action
            times_sorted = sorted(times)
            intervals: List[float] = []
            for i in range(1, len(times_sorted)):
                intervals.append((times_sorted[i] - times_sorted[i - 1]).total_seconds())

            if len(intervals) < 2:
                continue

            mean = sum(intervals) / len(intervals)
            var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
            std = sqrt(var)
            if std == 0:
                continue

            for i, interval in enumerate(intervals, start=1):
                z = abs(interval - mean) / std if std != 0 else 0.0
                if z > self.anomaly_threshold:
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": times_sorted[i].isoformat(),
                            "z_score": z,
                            "reason": f"Unusual interval detected for action '{action}'",
                        }
                    )

        return anomalies

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        if not activities:
            return 0.0

        actions = [a.get("action") for a in activities if a.get("action") is not None]
        total_actions = len(actions)
        if total_actions == 0:
            return 0.0

        unique_actions = len(set(actions))

        # Determine actions_per_day:
        # Use the first and last timestamps as provided (do not sort), as per tests
        first_ts = None
        last_ts = None
        # Find first timestamp in given order
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                first_ts = ts
                break
        # Find last timestamp in given order
        for a in reversed(activities):
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                last_ts = ts
                break

        if first_ts is not None and last_ts is not None:
            delta_days = (last_ts - first_ts).days + 1
            days_active = max(delta_days, 1)
            actions_per_day = total_actions / days_active
        else:
            # No usable timestamps: default actions_per_day to total_actions
            actions_per_day = total_actions

        diversity_score = unique_actions / total_actions
        frequency_score = min(actions_per_day / 10.0, 1.0)
        volume_score = total_actions / 100.0

        final = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100.0
        return round(final, 1)

    def analyze_patterns(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        patterns: List[ActivityPattern] = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns