from dataclasses import dataclass
from datetime import datetime
from collections import Counter, defaultdict
from statistics import pstdev, mean
from typing import List, Dict, Any, Optional


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
        if isinstance(ts, datetime):
            return ts
        if isinstance(ts, str):
            try:
                # Handle trailing 'Z' as UTC
                if ts.endswith("Z"):
                    # Use fromisoformat with timezone info
                    return datetime.fromisoformat(ts.replace("Z", "+00:00"))
                return datetime.fromisoformat(ts)
            except Exception:
                return None
        return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hours = []
        for act in activities:
            dt = self._parse_timestamp(act.get("timestamp"))
            if dt is not None:
                hours.append(dt.hour)

        if not hours:
            return []

        total = len(hours)
        counts = Counter(hours)
        # Use strict greater-than to match test expectation for threshold edge
        peak_hours = sorted(
            [h for h, c in counts.items() if (c / total) > self.peak_hour_threshold]
        )
        if not peak_hours:
            return []

        hours_str = ", ".join(f"{h:02d}:00" for h in peak_hours)
        desc = f"High activity during hours: {hours_str}"
        return [ActivityPattern("peak_hours", desc, 0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        # Maintain the order provided (activities already have chronological order in tests)
        actions = [a.get("action") for a in activities]
        sequences = []
        for i in range(len(actions) - 2):
            seq = (actions[i], actions[i + 1], actions[i + 2])
            sequences.append(seq)

        if not sequences:
            return []

        counts = Counter(sequences)
        # Top 3 by count descending, then lexicographically for stability
        top = sorted(counts.items(), key=lambda x: (-x[1], x[0]))[:3]

        patterns = []
        for seq, cnt in top:
            seq_str = " → ".join(seq)
            desc = f"Common sequence: {seq_str} (occurred {cnt} times)"
            patterns.append(ActivityPattern("action_sequence", desc, 0.75))
        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 5:
            return []

        # Use timestamps and sort by time
        ts = []
        for a in activities:
            dt = self._parse_timestamp(a.get("timestamp"))
            if dt is not None:
                ts.append(dt)

        if len(ts) < 5:
            return []

        ts.sort()
        intervals = [(ts[i] - ts[i - 1]).total_seconds() for i in range(1, len(ts))]
        if len(intervals) < 4:
            return []

        avg = mean(intervals)
        # If average is zero or near-zero, cannot compute meaningful regularity
        if avg <= 0:
            return []

        sd = pstdev(intervals)
        # Consider highly regular if coefficient of variation is small
        if sd == 0 or (sd / avg) <= 0.1:
            desc = "Highly regular activity pattern detected"
            return [ActivityPattern("regularity", desc, 0.9)]
        return []

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
        unique_actions = len(set(a.get("action") for a in activities))
        diversity_score = unique_actions / total_actions if total_actions > 0 else 0.0

        # Compute days span from first to last valid timestamp
        timestamps = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        timestamps = [t for t in timestamps if t is not None]
        if timestamps:
            timestamps.sort()
            # days difference as integer days; use at least 1
            days_span = max((timestamps[-1] - timestamps[0]).days, 1)
        else:
            days_span = 1

        actions_per_day = total_actions / days_span
        frequency_score = min(actions_per_day / 10.0, 1.0)

        volume_score = min(total_actions / 100.0, 1.0)

        final = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100.0
        return round(final, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if len(activities) < 5:
            return []

        # Group timestamps by action
        per_action: Dict[str, List[datetime]] = defaultdict(list)
        for act in activities:
            action = act.get("action")
            ts = self._parse_timestamp(act.get("timestamp"))
            if action is None or ts is None:
                continue
            per_action[action].append(ts)

        anomalies: List[Dict[str, Any]] = []
        for action, ts_list in per_action.items():
            if len(ts_list) < 5:
                continue
            ts_list.sort()
            intervals = [(ts_list[i] - ts_list[i - 1]).total_seconds() for i in range(1, len(ts_list))]
            if len(intervals) < 3:
                continue

            avg = mean(intervals)
            sd = pstdev(intervals)
            if sd == 0:
                continue

            for i, interval in enumerate(intervals, start=1):
                z = (interval - avg) / sd
                if z >= self.anomaly_threshold:
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": ts_list[i].isoformat(),
                            "z_score": float(z),
                            "reason": "Unusual interval detected relative to typical activity",
                        }
                    )

        return anomalies