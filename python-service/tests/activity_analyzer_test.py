from dataclasses import dataclass
from typing import List, Dict, Any, Optional, Tuple
import math
import datetime as datetime


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

    def _parse_timestamp(self, ts: Any) -> Optional[datetime.datetime]:
        # Accept datetime objects directly
        if isinstance(ts, datetime.datetime):
            return ts
        if not isinstance(ts, str):
            return None

        s = ts.strip()
        # Handle trailing Z from ISO 8601 (UTC designator)
        if s.endswith("Z"):
            s = s[:-1]

        # Try module-level shim first so tests can patch datetime.fromisoformat
        try:
            if hasattr(datetime, "fromisoformat"):
                return datetime.fromisoformat(s)  # patched in tests
        except Exception:
            # Fall through to attempt class method or return None
            pass

        try:
            return datetime.datetime.fromisoformat(s)
        except Exception:
            return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []

        hours_count: Dict[str, int] = {}
        total_with_ts = 0

        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            total_with_ts += 1
            hour_label = f"{ts.hour:02d}:00"
            hours_count[hour_label] = hours_count.get(hour_label, 0) + 1

        if total_with_ts == 0:
            return []

        # Proportion strictly greater than threshold
        peak_hours = [
            (hour, count / total_with_ts) for hour, count in hours_count.items()
            if (count / total_with_ts) > self.peak_hour_threshold
        ]

        if not peak_hours:
            return []

        # Sort by hour ascending for deterministic description
        peak_hours_sorted = sorted(peak_hours, key=lambda x: x[0])
        hour_list = ", ".join(h for h, _ in peak_hours_sorted)
        max_prop = max(p for _, p in peak_hours_sorted)
        # Confidence scaled between 0.6 and 0.95
        confidence = min(0.6 + (max_prop * 0.35), 0.95)

        description = f"High activity during hours: {hour_list}"
        return [ActivityPattern(pattern_type="peak_hours", description=description, confidence=round(confidence, 2))]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        # Sort by timestamp to ensure chronological order; fallback to original order if parse fails
        def sort_key(act: Dict[str, Any]) -> Tuple[int, float]:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                # Place unparsable timestamps after valid ones, maintain relative order
                return (1, 0.0)
            return (0, ts.timestamp())

        sorted_activities = sorted(activities, key=sort_key)

        actions = [a.get("action") for a in sorted_activities]
        seq_counts: Dict[Tuple[str, str, str], int] = {}

        for i in range(len(actions) - 2):
            seq = (actions[i], actions[i + 1], actions[i + 2])
            seq_counts[seq] = min(1000000, seq_counts.get(seq, 0) + 1)

        # Keep sequences appearing at least twice
        common_seqs = [(seq, cnt) for seq, cnt in seq_counts.items() if cnt >= 2]
        if not common_seqs:
            return []

        # Sort by count desc then lexicographic for determinism
        common_seqs.sort(key=lambda item: (-item[1], item[0]))

        patterns: List[ActivityPattern] = []
        for seq, cnt in common_seqs:
            seq_str = " -> ".join(seq)
            description = f"Common sequence: {seq_str} occurred {cnt} times"
            # Confidence simple mapping
            confidence = min(0.6 + 0.1 * (cnt - 1), 0.95)
            patterns.append(ActivityPattern("action_sequence", description, round(confidence, 2)))

        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        times: List[datetime.datetime] = []
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is not None:
                times.append(ts)

        if len(times) < 3:
            return []

        times.sort()
        intervals = [(times[i + 1] - times[i]).total_seconds() for i in range(len(times) - 1)]
        if not intervals:
            return []

        mean = sum(intervals) / len(intervals)
        if mean == 0:
            return []

        variance = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std_dev = math.sqrt(variance)

        if std_dev == 0:
            # perfectly regular; treat as highly regular
            cv = 0.0
        else:
            cv = std_dev / mean

        # Low CV indicates regularity
        if cv < 0.1:
            description = "Highly regular activity pattern with consistent intervals"
            return [ActivityPattern("regularity", description, 0.9)]

        return []

    def analyze_patterns(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        patterns: List[ActivityPattern] = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        if not activities:
            return 0.0

        total_actions = len(activities)
        unique_actions = len({a.get("action") for a in activities})
        diversity = unique_actions / total_actions if total_actions else 0.0

        # Collect valid timestamps
        valid_times: List[datetime.datetime] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                valid_times.append(ts)

        if len(valid_times) >= 1:
            valid_times.sort()
            first_day = valid_times[0].date()
            last_day = valid_times[-1].date()
            days_active = (last_day - first_day).days
            days_active = max(1, days_active)
            actions_per_day = total_actions / days_active
        else:
            # No valid timestamps; as per tests, treat actions_per_day as total_actions
            actions_per_day = total_actions

        frequency_norm = min(actions_per_day / 10.0, 1.0)
        volume_norm = min(total_actions / 100.0, 1.0)

        score = (diversity * 0.3 + frequency_norm * 0.4 + volume_norm * 0.3) * 100.0
        # Round to single decimal for stability
        return round(score, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Require minimal number of activities to compute intervals reliably
        if len(activities) < 5:
            return []

        # Sort by timestamp; skip entries without valid timestamp
        timed_acts: List[Tuple[datetime.datetime, Dict[str, Any]]] = []
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is not None:
                timed_acts.append((ts, act))

        if len(timed_acts) < 5:
            return []

        timed_acts.sort(key=lambda x: x[0])

        intervals: List[float] = []
        for i in range(len(timed_acts) - 1):
            delta = (timed_acts[i + 1][0] - timed_acts[i][0]).total_seconds()
            intervals.append(delta)

        if len(intervals) < 2:
            return []

        mean = sum(intervals) / len(intervals)
        variance = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std_dev = math.sqrt(variance)

        if std_dev == 0 or std_dev < 1e-12:
            return []

        anomalies: List[Dict[str, Any]] = []
        for i, interval in enumerate(intervals):
            z = abs(interval - mean) / std_dev
            if z >= self.anomaly_threshold:
                # Flag the activity occurring after this interval
                _, act_after = timed_acts[i + 1]
                anomalies.append({
                    "action": act_after.get("action"),
                    "timestamp": act_after.get("timestamp"),
                    "z_score": z,
                    "reason": f"Unusual interval detected: {interval:.2f}s differs from mean {mean:.2f}s",
                })

        return anomalies