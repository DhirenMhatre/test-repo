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
    def __init__(self, peak_hour_threshold: float = 0.2, anomaly_threshold: float = 3.0):
        self.peak_hour_threshold = peak_hour_threshold
        self.anomaly_threshold = anomaly_threshold

    def _parse_timestamp(self, ts: Any) -> Optional[datetime]:
        if isinstance(ts, datetime):
            return ts
        if isinstance(ts, str):
            s = ts.strip()
            try:
                # Handle 'Z' suffix (UTC)
                if s.endswith("Z"):
                    s = s[:-1] + "+00:00"
                return datetime.fromisoformat(s)
            except Exception:
                return None
        return None

    def analyze_patterns(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        patterns: List[ActivityPattern] = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hours_count: Counter = Counter()
        total = 0
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            total += 1
            hours_count[ts.hour] += 1
        if total == 0:
            return []

        threshold_count = self.peak_hour_threshold * total
        peak_hours = sorted([h for h, c in hours_count.items() if c >= threshold_count])
        if not peak_hours:
            return []
        hours_str = ", ".join(f"{h:02d}:00" for h in peak_hours)
        desc = f"Peak hours detected: {hours_str}"
        return [ActivityPattern("peak_hours", desc, 0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        # Sort by timestamp if possible, otherwise keep given order
        def sort_key(a: Dict[str, Any]) -> Tuple[int, Any]:
            ts = self._parse_timestamp(a.get("timestamp"))
            # Keep original order when timestamps invalid by using index marker
            return (0, ts) if ts is not None else (1, None)

        sorted_acts = sorted(activities, key=sort_key)

        actions = [a.get("action") for a in sorted_acts]
        windows = []
        for i in range(len(actions) - 2):
            seq = tuple(actions[i : i + 3])
            windows.append(seq)

        if not windows:
            return []

        counts: Counter = Counter(windows)
        # Find most common sequence with at least 2 occurrences
        seq, cnt = counts.most_common(1)[0]
        if cnt < 2:
            return []
        seq_str = " → ".join(str(s) for s in seq)
        desc = f"Common action sequence: {seq_str} (occurred {cnt} times)"
        return [ActivityPattern("action_sequence", desc, 0.75)]

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Collect valid timestamps
        ts_list = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                ts_list.append(ts)
        if len(ts_list) < 5:
            return []

        ts_list.sort()
        intervals = [(ts_list[i] - ts_list[i - 1]).total_seconds() for i in range(1, len(ts_list))]
        if len(intervals) < 4:
            return []

        mean = sum(intervals) / len(intervals)
        if mean <= 0:
            return []

        # population std deviation
        variance = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std = math.sqrt(variance)

        cv = (std / mean) if mean != 0 else float("inf")
        # Consider highly regular if CV <= 0.1
        if cv <= 0.1:
            desc = f"Regular intervals detected (CV: {cv:.2f})"
            return [ActivityPattern("regularity", desc, 0.9)]
        return []

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        total = len(activities)
        if total == 0:
            return 0.0

        # Diversity: unique actions / total actions
        actions = [a.get("action") for a in activities]
        unique_actions = len(set(actions))
        diversity = unique_actions / total if total > 0 else 0.0

        # Frequency: actions per day normalized by 10, using valid dates;
        # fallback to total actions when invalid timestamps
        valid_dates = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                valid_dates.append(ts.date())

        if valid_dates:
            num_days = len(set(valid_dates))
            actions_per_day = total / num_days if num_days > 0 else total
            frequency_score = min(actions_per_day / 10.0, 1.0)
        else:
            frequency_score = min(total / 10.0, 1.0)

        # Volume: total actions normalized by 100
        volume = min(total / 100.0, 1.0)

        score = (diversity * 0.3 + frequency_score * 0.4 + volume * 0.3) * 100.0
        return round(score, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if len(activities) < 5:
            return []

        # Group by action with valid timestamps
        grouped: Dict[str, List[datetime]] = defaultdict(list)
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                action = a.get("action")
                grouped[action].append(ts)

        anomalies: List[Dict[str, Any]] = []

        for action, ts_list in grouped.items():
            if len(ts_list) < 5:
                continue
            ts_list.sort()
            intervals = [(ts_list[i] - ts_list[i - 1]).total_seconds() for i in range(1, len(ts_list))]
            if len(intervals) < 2:
                continue

            mean = sum(intervals) / len(intervals)
            variance = sum((x - mean) ** 2 for x in intervals) / len(intervals)
            std = math.sqrt(variance)
            if std == 0:
                continue

            for idx, interval in enumerate(intervals, start=1):
                z = (interval - mean) / std
                if z >= self.anomaly_threshold:
                    # idx corresponds to the end timestamp of the interval at ts_list[idx]
                    end_ts = ts_list[idx]
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": end_ts.isoformat(),
                            "z_score": f"{z:.2f}",
                            "reason": f"Unusual interval detected (z={z:.2f})",
                        }
                    )
        return anomalies