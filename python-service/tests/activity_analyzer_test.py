from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import math
from collections import Counter, defaultdict


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
                # Handle 'Z' suffix for UTC
                if ts.endswith("Z"):
                    ts = ts[:-1] + "+00:00"
                return datetime.fromisoformat(ts)
            except Exception:
                return None
        return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hours = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is None:
                continue
            hour = ts.hour
            hours.append(hour)

        if not hours:
            return []

        total = len(hours)
        counts = Counter(hours)
        exceeding = sorted(h for h, c in counts.items() if (c / total) > self.peak_hour_threshold)

        if not exceeding:
            return []

        hour_labels = ", ".join(f"{h:02d}:00" for h in exceeding)
        description = f"Peak activity during hours: {hour_labels}"
        # Confidence as average of ratios for the included hours
        confidence = sum(counts[h] / total for h in exceeding) / max(1, len(exceeding))
        return [ActivityPattern("peak_hours", description, confidence)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        actions = [a.get("action") for a in activities]
        seq_counts: Dict[str, int] = defaultdict(int)

        for i in range(len(actions) - 2):
            seq = tuple(actions[i : i + 3])
            key = " → ".join(seq)
            seq_counts[key] += 1

        patterns: List[ActivityPattern] = []
        total_sequences = max(1, len(actions) - 2)
        for seq_str, count in seq_counts.items():
            if count > 1:
                description = f"Common sequence: {seq_str} (occurred {count} times)"
                confidence = count / total_sequences
                patterns.append(ActivityPattern("action_sequence", description, confidence))

        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        timestamps: List[datetime] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                timestamps.append(ts)

        if len(timestamps) < 5:
            return []

        timestamps.sort()
        intervals = [(timestamps[i] - timestamps[i - 1]).total_seconds() for i in range(1, len(timestamps))]

        if len(intervals) < 4:
            return []

        mean_interval = sum(intervals) / len(intervals)
        if mean_interval <= 0:
            return []

        # Standard deviation
        variance = sum((x - mean_interval) ** 2 for x in intervals) / len(intervals)
        std = math.sqrt(variance)

        # Coefficient of variation
        cv = std / mean_interval if mean_interval != 0 else float("inf")

        # Threshold for "highly regular" activity
        if cv < 0.2:
            description = f"Highly regular activity pattern detected (CV={cv:.2f})"
            confidence = max(0.0, min(1.0, 1.0 - cv))
            return [ActivityPattern("regularity", description, confidence)]

        return []

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if len(activities) < 5:
            return []

        # Group timestamps by action
        grouped: Dict[str, List[datetime]] = defaultdict(list)
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            action = a.get("action")
            if ts is not None and action is not None:
                grouped[action].append(ts)

        anomalies: List[Dict[str, Any]] = []

        for action, ts_list in grouped.items():
            if len(ts_list) < 5:
                continue
            ts_list.sort()
            intervals = [(ts_list[i] - ts_list[i - 1]).total_seconds() for i in range(1, len(ts_list))]
            if len(intervals) < 3:
                continue

            for i, interval in enumerate(intervals):
                # Leave-one-out statistics to better capture single outliers
                others = [intervals[j] for j in range(len(intervals)) if j != i]
                if len(others) < 2:
                    continue
                mean_other = sum(others) / len(others)
                var_other = sum((x - mean_other) ** 2 for x in others) / len(others)
                std_other = math.sqrt(var_other)

                if std_other == 0:
                    z = float("inf") if abs(interval - mean_other) > 0 else 0.0
                else:
                    z = abs(interval - mean_other) / std_other

                if z > self.anomaly_threshold:
                    anomaly_ts = ts_list[i + 1]  # interval leads to the later timestamp
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": anomaly_ts.isoformat(),
                            "z_score": z,
                            "reason": f"Unusual interval of {interval:.2f} seconds detected",
                        }
                    )

        return anomalies

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        if not activities:
            return 0.0

        total = len(activities)
        unique_actions = len({a.get("action") for a in activities})

        diversity = unique_actions / total if total > 0 else 0.0

        # Frequency: based on first and last provided timestamps (not sorted), clamp days >= 1
        first_ts = self._parse_timestamp(activities[0].get("timestamp"))
        last_ts = self._parse_timestamp(activities[-1].get("timestamp"))

        if first_ts and last_ts and last_ts >= first_ts:
            days_active = (last_ts - first_ts).days + 1
        else:
            days_active = 1

        days_active = max(1, days_active)
        actions_per_day = total / days_active
        frequency = min(actions_per_day / 10.0, 1.0)

        # Volume: scaled by 100 actions
        volume = min(total / 100.0, 1.0)

        score = (diversity * 0.3 + frequency * 0.4 + volume * 0.3) * 100.0
        # Keep one decimal if necessary (tests expect precise values like 52.0 and 51.5)
        return float(score)

    def analyze_patterns(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []

        patterns = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns