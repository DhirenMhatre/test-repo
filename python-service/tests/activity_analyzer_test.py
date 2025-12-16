from dataclasses import dataclass
from datetime import datetime, timedelta
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
            # Handle Zulu suffix
            if s.endswith("Z"):
                s = s[:-1] + "+00:00"
            try:
                return datetime.fromisoformat(s)
            except ValueError:
                return None
        return None

    def _sorted_activities_by_time(self, activities: List[Dict[str, Any]]) -> List[Tuple[Dict[str, Any], datetime]]:
        parsed = []
        for a in activities:
            dt = self._parse_timestamp(a.get("timestamp"))
            if dt is not None:
                parsed.append((a, dt))
        parsed.sort(key=lambda x: x[1])
        return parsed

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        parsed = self._sorted_activities_by_time(activities)
        total = len(parsed)
        if total == 0:
            return []

        hour_counts: Dict[int, int] = defaultdict(int)
        for _, dt in parsed:
            hour_counts[dt.hour] += 1

        peaks = []
        for hour in sorted(hour_counts):
            fraction = hour_counts[hour] / total
            if fraction > self.peak_hour_threshold:
                peaks.append(f"{hour:02d}:00")

        if not peaks:
            return []

        description = f"High activity during hours: {', '.join(peaks)}"
        return [ActivityPattern(pattern_type="peak_hours", description=description, confidence=0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        parsed = self._sorted_activities_by_time(activities)
        if len(parsed) < 3:
            return []

        actions = [a["action"] for a, _ in parsed]
        triples = []
        for i in range(len(actions) - 2):
            triples.append(tuple(actions[i : i + 3]))

        if not triples:
            return []

        counts = Counter(triples)
        top_seq, top_count = counts.most_common(1)[0]
        if top_count < 2:
            return []

        seq_str = " → ".join(top_seq)
        description = f"Common sequence: {seq_str} (occurred {top_count} times)"
        return [ActivityPattern(pattern_type="action_sequence", description=description, confidence=0.75)]

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        parsed = self._sorted_activities_by_time(activities)
        if len(parsed) < 4:
            return []

        times = [dt for _, dt in parsed]
        intervals = []
        for i in range(len(times) - 1):
            delta = (times[i + 1] - times[i]).total_seconds()
            if delta <= 0:
                # Ignore non-positive intervals
                continue
            intervals.append(delta)

        if len(intervals) < 3:
            return []

        mean = sum(intervals) / len(intervals)
        if mean <= 0:
            return []

        # Sample standard deviation
        var_num = sum((x - mean) ** 2 for x in intervals)
        denom = len(intervals) - 1
        std = math.sqrt(var_num / denom) if denom > 0 else 0.0

        if std == 0:
            cv = 0.0
        else:
            cv = std / mean

        if cv < 0.1:
            description = f"Highly regular activity pattern (CV: {cv:.2f})"
            return [ActivityPattern(pattern_type="regularity", description=description, confidence=0.9)]
        return []

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Return empty when overall activities are too few
        if len(activities) < 5:
            return []

        # Group by action with sorted timestamps
        grouped: Dict[str, List[datetime]] = defaultdict(list)
        for a, dt in self._sorted_activities_by_time(activities):
            action = a.get("action")
            grouped[action].append(dt)

        anomalies: List[Dict[str, Any]] = []
        for action, times in grouped.items():
            if len(times) < 3:
                continue
            intervals = [(times[i + 1] - times[i]).total_seconds() for i in range(len(times) - 1)]
            if len(intervals) < 2:
                continue

            mean = sum(intervals) / len(intervals)
            var_num = sum((x - mean) ** 2 for x in intervals)
            # Use population std to be conservative
            std = math.sqrt(var_num / len(intervals)) if len(intervals) > 0 else 0.0
            if std == 0:
                continue

            for i, interval in enumerate(intervals):
                z = abs(interval - mean) / std
                if z > self.anomaly_threshold:
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": times[i + 1].isoformat(),
                            "reason": f"Unusual interval detected ({interval:.2f}s)",
                            "z_score": z,
                        }
                    )

        return anomalies

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
        unique_actions = len({a.get("action") for a in activities})

        # Determine actions_per_day
        first_ts = self._parse_timestamp(activities[0].get("timestamp"))
        last_ts = self._parse_timestamp(activities[-1].get("timestamp"))
        if first_ts is not None and last_ts is not None:
            diff = last_ts - first_ts
            days_active = diff.days
            if days_active <= 0:
                days_active = 1
            actions_per_day = total_actions / days_active
        else:
            # Fallback when timestamps cannot be parsed
            actions_per_day = total_actions

        frequency_score = min(actions_per_day / 10.0, 1.0)
        diversity_score = unique_actions / total_actions if total_actions > 0 else 0.0
        volume_score = min(total_actions / 100.0, 1.0)

        final_score = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100.0
        return round(final_score, 2)