from dataclasses import dataclass
from datetime import datetime, timezone
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
    def __init__(self, peak_hour_threshold: float = 0.2, anomaly_threshold: float = 3.0):
        self.peak_hour_threshold = peak_hour_threshold
        self.anomaly_threshold = anomaly_threshold

    def analyze_patterns(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        patterns: List[ActivityPattern] = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Require at least 5 activities overall
        if len(activities) < 5:
            return []

        # Group timestamps by action
        grouped: Dict[str, List[datetime]] = defaultdict(list)
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                grouped[a.get("action")] .append(ts)

        anomalies: List[Dict[str, Any]] = []

        for action, timestamps in grouped.items():
            # Need at least 3 timestamps to consider intervals
            if len(timestamps) < 3:
                continue
            timestamps.sort()
            # Compute intervals (seconds) between consecutive timestamps
            intervals: List[float] = []
            for i in range(1, len(timestamps)):
                delta = (timestamps[i] - timestamps[i - 1]).total_seconds()
                intervals.append(delta)

            if not intervals:
                continue

            mean = sum(intervals) / len(intervals)
            var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
            std = math.sqrt(var)

            # If no variance, can't compute meaningful z-scores -> no anomalies
            if std == 0:
                continue

            # Compute z-score for each interval and flag if above threshold
            for i, interval in enumerate(intervals, start=1):
                z = abs((interval - mean) / std)
                if z > self.anomaly_threshold:
                    ts = timestamps[i]  # anomaly associated with the ending timestamp of that interval
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": ts.isoformat(),
                            "z_score": z,
                            "reason": "Unusual interval detected",
                        }
                    )

        return anomalies

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        total_actions = len(activities)
        if total_actions == 0:
            return 0.0

        unique_actions = len({a.get("action") for a in activities})

        # Collect valid timestamps
        valid_ts: List[datetime] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                valid_ts.append(ts)

        # Diversity score
        diversity_score = unique_actions / total_actions if total_actions > 0 else 0.0

        # Frequency score
        if len(valid_ts) == 0:
            # Use total actions when timestamps are invalid
            actions_per_day = total_actions
        else:
            min_ts = min(valid_ts)
            max_ts = max(valid_ts)
            days_active = (max_ts.date() - min_ts.date()).days
            days_active = max(1, days_active)  # avoid division by zero
            actions_per_day = total_actions / days_active

        frequency_score = min(actions_per_day / 10.0, 1.0)

        # Volume score
        volume_score = min(total_actions / 100.0, 1.0)

        # Weighted final score
        final = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100.0
        # Round to one decimal as tests use exact equality with .0 or .5 etc.
        return round(final, 1)

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hours_count: Counter = Counter()
        valid_count = 0
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is None:
                continue
            valid_count += 1
            hours_count[ts.hour] += 1

        if valid_count == 0:
            return []

        # Compute frequency per hour and select those above the threshold (strictly greater)
        qualifying_hours = []
        for hour, count in hours_count.items():
            frac = count / valid_count
            if frac > self.peak_hour_threshold:
                qualifying_hours.append(hour)

        if not qualifying_hours:
            return []

        qualifying_hours.sort()
        # Format "HH:MM"
        hours_str = ", ".join(f"{h:02d}:00" for h in qualifying_hours)
        description = f"Peak activity at hours: {hours_str}"
        return [ActivityPattern(pattern_type="peak_hours", description=description, confidence=0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Prepare list of (timestamp, action) for valid timestamps
        items: List[Tuple[datetime, str]] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is None:
                continue
            items.append((ts, a.get("action")))
        if len(items) < 3:
            return []

        items.sort(key=lambda x: x[0])
        actions_ordered = [act for _, act in items]

        # Count sequences of length 3
        seq_counts: Counter = Counter()
        for i in range(len(actions_ordered) - 2):
            seq = tuple(actions_ordered[i : i + 3])
            seq_counts[seq] += 1

        # Find any sequence that occurred at least twice
        common = seq_counts.most_common(1)
        if not common:
            return []
        (seq, count) = common[0]
        if count < 2:
            return []

        seq_str = " → ".join(seq)
        description = f"Common action sequence detected: {seq_str} (occurred {count} times)"
        return [ActivityPattern(pattern_type="action_sequence", description=description, confidence=0.75)]

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Collect valid timestamps
        timestamps: List[datetime] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                timestamps.append(ts)

        if len(timestamps) < 5:
            return []

        timestamps.sort()
        intervals: List[float] = []
        for i in range(1, len(timestamps)):
            intervals.append((timestamps[i] - timestamps[i - 1]).total_seconds())

        if not intervals:
            return []

        mean = sum(intervals) / len(intervals)
        if mean == 0:
            return []

        var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std = math.sqrt(var)
        cv = std / mean

        # Consider highly regular if CV is very small
        if cv <= 0.1:
            description = f"Highly regular activity intervals detected (CV: {cv:.2f})"
            return [ActivityPattern(pattern_type="regularity", description=description, confidence=0.9)]

        return []

    def _parse_timestamp(self, ts: Any) -> Optional[datetime]:
        if isinstance(ts, datetime):
            return ts
        if isinstance(ts, str):
            s = ts.strip()
            try:
                if s.endswith("Z"):
                    # Convert to timezone-aware UTC
                    s2 = s.replace("Z", "+00:00")
                    return datetime.fromisoformat(s2)
                else:
                    return datetime.fromisoformat(s)
            except ValueError:
                return None
        return None