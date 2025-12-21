from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple
from collections import Counter, defaultdict
import statistics


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
        patterns = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Require at least 5 activities overall
        if len(activities) < 5:
            return []

        # Group timestamps by action with valid timestamps
        ts_by_action: Dict[str, List[datetime]] = defaultdict(list)
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            ts_by_action[act.get("action")].append(ts)

        anomalies: List[Dict[str, Any]] = []

        for action, ts_list in ts_by_action.items():
            if len(ts_list) < 3:
                continue
            ts_list.sort()
            # compute intervals in seconds between consecutive timestamps
            intervals: List[float] = []
            for i in range(1, len(ts_list)):
                delta = (ts_list[i] - ts_list[i - 1]).total_seconds()
                intervals.append(delta)

            if len(intervals) < 2:
                continue

            mean_interval = statistics.mean(intervals)
            std_dev = statistics.pstdev(intervals) if len(intervals) > 1 else 0.0

            # If std dev is 0, cannot compute z-score; skip anomalies
            if std_dev == 0:
                continue

            # For each interval, compute z-score and flag anomalies
            for i, interval in enumerate(intervals, start=1):
                z = (interval - mean_interval) / std_dev
                if abs(z) > self.anomaly_threshold:
                    # Attribute anomaly to the timestamp at the end of the interval
                    anomaly_ts = ts_list[i]
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": anomaly_ts.isoformat(),
                            "z_score": abs(z),
                            "reason": f"Unusual interval: {interval:.2f}s (z={z:.2f})",
                        }
                    )

        return anomalies

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        total_actions = len(activities)
        if total_actions == 0:
            return 0.0

        unique_actions = len({a.get("action") for a in activities})

        # Collect unique active days from valid timestamps
        unique_days = set()
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is not None:
                unique_days.add(ts.date())

        days_active = len(unique_days) if len(unique_days) > 0 else 1

        actions_per_day = total_actions / days_active

        diversity_score = unique_actions / total_actions if total_actions > 0 else 0.0
        frequency_score = min(actions_per_day / 10.0, 1.0)
        volume_score = min(total_actions / 100.0, 1.0)

        final_score = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100.0
        return round(final_score, 2)

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hours: List[int] = []
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            hours.append(ts.hour)

        if not hours:
            return []

        total = len(hours)
        counts = Counter(hours)

        # Hours exceeding threshold strictly greater than
        qualifying_hours = sorted(h for h, c in counts.items() if (c / total) > self.peak_hour_threshold)

        if not qualifying_hours:
            return []

        # Format hours as HH:MM
        hour_strings = [f"{h:02d}:00" for h in qualifying_hours]
        description = "Peak activity hours: " + ", ".join(hour_strings)
        return [ActivityPattern(pattern_type="peak_hours", description=description, confidence=0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Sort activities by valid timestamp and build action list
        items: List[Tuple[datetime, str]] = []
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            items.append((ts, act.get("action")))

        if len(items) < 3:
            return []

        items.sort(key=lambda x: x[0])
        actions_seq = [a for _, a in items]

        n = 3
        if len(actions_seq) < n:
            return []

        windows = [tuple(actions_seq[i : i + n]) for i in range(0, len(actions_seq) - n + 1)]
        if not windows:
            return []

        counts = Counter(windows)
        most_common_seq, count = counts.most_common(1)[0]
        if count < 2:
            return []

        seq_str = " → ".join(most_common_seq)
        description = f"Common action sequence: {seq_str} (occurred {count} times)"
        return [ActivityPattern(pattern_type="action_sequence", description=description, confidence=0.75)]

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        timestamps: List[datetime] = []
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            timestamps.append(ts)

        if len(timestamps) < 3:
            return []

        timestamps.sort()
        intervals = [(timestamps[i] - timestamps[i - 1]).total_seconds() for i in range(1, len(timestamps))]
        if len(intervals) < 2:
            return []

        mean_interval = statistics.mean(intervals)
        if mean_interval <= 0:
            return []

        std_dev = statistics.pstdev(intervals) if len(intervals) > 1 else 0.0
        cv = std_dev / mean_interval if mean_interval > 0 else float("inf")

        # Highly regular if coefficient of variation is small
        if cv <= 0.1:
            description = f"Activities occur at regular intervals (CV: {cv:.2f})"
            return [ActivityPattern(pattern_type="regularity", description=description, confidence=0.9)]

        return []

    def _parse_timestamp(self, ts: Any) -> Optional[datetime]:
        if isinstance(ts, datetime):
            return ts
        if isinstance(ts, str):
            s = ts.strip()
            try:
                if s.endswith("Z"):
                    # Convert Zulu time to aware UTC datetime
                    return datetime.fromisoformat(s[:-1] + "+00:00")
                else:
                    return datetime.fromisoformat(s)
            except ValueError:
                return None
        return None