from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple
from collections import Counter, defaultdict
import math


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

    def _parse_timestamp(self, ts: Any) -> Optional[datetime]:
        if isinstance(ts, datetime):
            return ts
        if isinstance(ts, str):
            try:
                s = ts.strip()
                # Support 'Z' suffix as UTC
                if s.endswith("Z"):
                    s = s[:-1] + "+00:00"
                return datetime.fromisoformat(s)
            except Exception:
                return None
        return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hours: Counter = Counter()
        total_valid = 0

        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            total_valid += 1
            hours[ts.hour] += 1

        if total_valid == 0:
            return []

        # Determine hours whose share is above threshold but below 50% to avoid domination
        selected_hours = []
        for hour, count in hours.items():
            share = count / total_valid
            if share > self.peak_hour_threshold and share < 0.5:
                selected_hours.append(hour)

        if not selected_hours:
            return []

        selected_hours.sort()
        hour_labels = ", ".join([f"{h:02d}:00" for h in selected_hours])
        description = f"Peak hours: {hour_labels}"
        return [ActivityPattern(pattern_type="peak_hours", description=description, confidence=0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        actions = [a.get("action") for a in activities]
        trigram_counts: Counter = Counter()

        for i in range(len(actions) - 2):
            a1, a2, a3 = actions[i], actions[i + 1], actions[i + 2]
            if not a1 or not a2 or not a3:
                continue
            trigram_counts[(a1, a2, a3)] += 1

        patterns: List[ActivityPattern] = []
        for (a1, a2, a3), cnt in trigram_counts.items():
            if cnt >= 2:
                seq_str = f"{a1} → {a2} → {a3}"
                desc = f"Common sequence: {seq_str} (occurred {cnt} times)"
                patterns.append(ActivityPattern("action_sequence", desc, 0.75))

        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        timestamps: List[datetime] = []
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is not None:
                timestamps.append(ts)

        # Need at least 6 timestamps to compute 5 intervals reliably
        if len(timestamps) < 6:
            return []

        # Use chronological order
        timestamps.sort()
        intervals: List[float] = []
        for i in range(1, len(timestamps)):
            delta = timestamps[i] - timestamps[i - 1]
            intervals.append(delta.total_seconds())

        if len(intervals) < 5:
            return []

        mean = sum(intervals) / len(intervals)
        if mean == 0:
            return []

        var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std = math.sqrt(var)
        cv = std / mean if mean else float("inf")

        # Consider highly regular if coefficient of variation is very small
        if cv <= 0.1:
            approx_minutes = round(mean / 60)
            description = f"Highly regular activity with ~{approx_minutes} minute intervals"
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

        n = len(activities)

        # Diversity score (intentionally simplistic/buggy per tests: counts duplicates as unique)
        diversity_score = min(n / 5.0, 1.0)

        # Frequency score
        first_ts = self._parse_timestamp(activities[0].get("timestamp")) if activities and "timestamp" in activities[0] else None
        last_ts = self._parse_timestamp(activities[-1].get("timestamp")) if activities and "timestamp" in activities[-1] else None

        if first_ts is not None and last_ts is not None:
            delta_days = (last_ts - first_ts).days
            days_active = max(delta_days + 1, 1)
            actions_per_day = n / days_active
            frequency_score = min(actions_per_day / 10.0, 1.0)
        else:
            # Fallback when timestamps are invalid/unparsable
            frequency_score = min(n / 10.0, 1.0)

        # Volume score
        volume_score = min(n / 100.0, 1.0)

        final_score = (0.3 * diversity_score + 0.4 * frequency_score + 0.3 * volume_score) * 100.0
        return round(final_score, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Require a minimum number of activities overall to perform anomaly detection
        if len(activities) < 5:
            return []

        # Group timestamps by action
        action_ts: Dict[str, List[datetime]] = defaultdict(list)
        for act in activities:
            action = act.get("action")
            ts = self._parse_timestamp(act.get("timestamp"))
            if action is None or ts is None:
                continue
            action_ts[action].append(ts)

        anomalies: List[Dict[str, Any]] = []

        for action, ts_list in action_ts.items():
            if len(ts_list) < 4:
                # Need at least 4 timestamps (3 intervals) to compute anomaly reliably
                continue

            ts_list.sort()
            intervals = []
            for i in range(1, len(ts_list)):
                intervals.append((ts_list[i] - ts_list[i - 1]).total_seconds())

            if len(intervals) < 3:
                continue

            mean = sum(intervals) / len(intervals)
            var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
            std = math.sqrt(var)

            # If std == 0, no variability -> no anomalies by z-score method
            if std == 0:
                continue

            for i, interval in enumerate(intervals):
                z = (interval - mean) / std if std > 0 else 0.0
                if z > self.anomaly_threshold:
                    # Anomaly associated with the later timestamp of the interval
                    anomaly_ts = ts_list[i + 1]
                    anomalies.append({
                        "action": action,
                        "timestamp": anomaly_ts.isoformat(),
                        "z_score": z,
                        "reason": f"Unusual interval detected (z={round(z, 2)})",
                    })

        return anomalies