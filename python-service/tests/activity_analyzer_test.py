from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
import datetime


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
        if isinstance(ts, datetime.datetime):
            return ts
        if isinstance(ts, str):
            s = ts.strip()
            if s.endswith("Z"):
                s = s[:-1] + "+00:00"
            try:
                # Allow patching of module-level datetime.fromisoformat in tests
                fromiso = getattr(datetime, "fromisoformat", None)
                if callable(fromiso):
                    return fromiso(s)
                return datetime.datetime.fromisoformat(s)
            except Exception:
                return None
        return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hours_count: Dict[int, int] = {}
        total = 0
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            hour = ts.hour
            hours_count[hour] = hours_count.get(hour, 0) + 1
            total += 1
        if total == 0:
            return []

        # Determine hours exceeding the threshold
        significant_hours = sorted(
            [h for h, c in hours_count.items() if (c / total) >= self.peak_hour_threshold]
        )
        if not significant_hours:
            return []

        hour_labels = [f"{h:02d}:00" for h in significant_hours]
        desc = f"Peak hours: {', '.join(hour_labels)} (≥{int(self.peak_hour_threshold*100)}%)"
        return [ActivityPattern(pattern_type="peak_hours", description=desc, confidence=0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        # Try to sort by timestamp if possible, using index as fallback tie-breaker
        indexed = list(enumerate(activities))
        def sort_key(item: Tuple[int, Dict[str, Any]]) -> Tuple[int, int]:
            idx, act = item
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                # Keep relative order by using large sentinel
                return (2**31 - 1, idx)
            # Use timestamp ordinal seconds
            return (int(ts.timestamp()), idx)
        ordered = [act for _, act in sorted(indexed, key=sort_key)]

        actions = [a.get("action") for a in ordered]
        if len(actions) < 3:
            return []

        # Count 3-step sequences
        counts: Dict[Tuple[Any, Any, Any], int] = {}
        for i in range(len(actions) - 2):
            seq = (actions[i], actions[i + 1], actions[i + 2])
            counts[seq] = counts.get(seq, 0) + 1

        patterns: List[ActivityPattern] = []
        for seq, cnt in counts.items():
            if cnt >= 2:
                a, b, c = seq
                desc = f"Common sequence: {a} → {b} → {c} (occurred {cnt} times)"
                # Confidence proportional to frequency but capped
                confidence = min(0.5 + 0.1 * cnt, 0.95)
                patterns.append(ActivityPattern("action_sequence", desc, confidence))
        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Collect valid timestamps sorted
        times: List[datetime.datetime] = []
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is not None:
                times.append(ts)
        times.sort()
        if len(times) < 3:
            return []

        # Compute intervals in seconds
        intervals = [(t2 - t1).total_seconds() for t1, t2 in zip(times, times[1:])]
        if not intervals:
            return []

        mean = sum(intervals) / len(intervals)
        if mean <= 0:
            return []

        # Standard deviation
        var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std = var ** 0.5
        cv = 0.0 if mean == 0 else (std / mean)

        # Highly regular if CV small
        if cv <= 0.1:
            desc = f"Regular intervals detected (CV: {cv:.2f})"
            return [ActivityPattern("regularity", desc, 0.9)]
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

        total = len(activities)
        unique_actions = len({a.get("action") for a in activities})
        diversity_score = (unique_actions / total) if total > 0 else 0.0

        # Frequency component based on actions per day
        times = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        valid_times = [t for t in times if t is not None]
        if valid_times:
            valid_times.sort()
            first, last = valid_times[0], valid_times[-1]
            days = (last.date() - first.date()).days
            if days <= 0:
                days = 1
            actions_per_day = total / days
        else:
            # Fallback: use total actions as baseline (as per tests)
            actions_per_day = total

        freq_score = min(actions_per_day / 10.0, 1.0)
        volume_score = min(total / 100.0, 1.0)

        weighted = 0.3 * diversity_score + 0.4 * freq_score + 0.3 * volume_score
        # Round to 1 decimal place for stable comparisons
        return round(weighted * 100.0, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Require a minimum number of activities overall
        if len(activities) < 5:
            return []

        # Group timestamps by action
        action_ts: Dict[Any, List[datetime.datetime]] = {}
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is None:
                continue
            action = a.get("action")
            action_ts.setdefault(action, []).append(ts)

        anomalies: List[Dict[str, Any]] = []
        for action, times in action_ts.items():
            if len(times) < 4:
                # Need at least 4 timestamps => 3 intervals to assess variability
                continue
            times.sort()
            intervals = [(t2 - t1).total_seconds() for t1, t2 in zip(times, times[1:])]
            if len(intervals) < 2:
                continue

            mean = sum(intervals) / len(intervals)
            var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
            std = var ** 0.5
            if std == 0:
                # No variability -> no anomalies
                continue

            # Compute z-scores and flag those above threshold
            for idx, interval in enumerate(intervals):
                z = abs((interval - mean) / std)
                if z >= self.anomaly_threshold:
                    # An interval outlier corresponds to the event at times[idx + 1]
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": times[idx + 1],
                            "reason": f"Unusual interval detected (z={z:.2f})",
                            "z_score": z,
                        }
                    )

        return anomalies