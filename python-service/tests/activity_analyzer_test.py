from datetime import datetime, timedelta, timezone
from collections import Counter, defaultdict
from typing import Any, Dict, List, Optional


class ActivityPattern:
    def __init__(self, pattern_type: str, description: str, confidence: float) -> None:
        self.pattern_type = pattern_type
        self.description = description
        self.confidence = confidence

    def to_dict(self) -> Dict[str, Any]:
        return {
            "pattern_type": self.pattern_type,
            "description": self.description,
            "confidence": self.confidence,
        }


class ActivityAnalyzer:
    def __init__(self) -> None:
        self.peak_hour_threshold = 0.2
        self.anomaly_threshold = 3.0

    def _parse_timestamp(self, ts: Any) -> Optional[datetime]:
        if ts is None:
            return None
        if isinstance(ts, datetime):
            return ts
        if isinstance(ts, str):
            try:
                if ts.endswith("Z"):
                    # Convert Zulu to explicit UTC offset
                    return datetime.fromisoformat(ts.replace("Z", "+00:00"))
                # Try plain ISO
                return datetime.fromisoformat(ts)
            except Exception:
                return None
        return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hours: Dict[int, int] = defaultdict(int)
        valid_count = 0
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            valid_count += 1
            hours[ts.hour] += 1

        if valid_count == 0:
            return []

        peak_hours = [h for h, c in hours.items() if (c / valid_count) >= self.peak_hour_threshold]
        if not peak_hours:
            return []

        peak_hours_sorted = sorted(peak_hours)
        hours_str = ", ".join(f"{h:02d}:00" for h in peak_hours_sorted)
        description = f"High activity during hours: {hours_str}"
        return [ActivityPattern("peak_hours", description, 0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        # Ensure order by timestamp if available; otherwise preserve original order
        def sort_key(item: Dict[str, Any]):
            ts = self._parse_timestamp(item.get("timestamp"))
            return ts if ts is not None else datetime.min

        sorted_acts = sorted(activities, key=sort_key)

        # Build sequences of 3 consecutive actions
        seq_counter: Counter = Counter()
        actions_only = [a.get("action") for a in sorted_acts]
        for i in range(len(actions_only) - 2):
            a, b, c = actions_only[i], actions_only[i + 1], actions_only[i + 2]
            if a is None or b is None or c is None:
                continue
            seq_counter[(a, b, c)] += 1

        # Consider repeating sequences (occurred at least twice)
        repeating = [(seq, cnt) for seq, cnt in seq_counter.items() if cnt >= 2]
        if not repeating:
            return []

        # Top 3 by count desc then by sequence lexicographically for determinism
        repeating.sort(key=lambda x: (-x[1], x[0]))
        top = repeating[:3]

        patterns: List[ActivityPattern] = []
        for seq, cnt in top:
            seq_str = " → ".join(seq)
            desc = f"Sequence: {seq_str} occurred {cnt} times"
            patterns.append(ActivityPattern("action_sequence", desc, 0.75))

        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        timestamps = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        timestamps = [t for t in timestamps if t is not None]
        if len(timestamps) < 5:
            return []

        timestamps.sort()
        intervals = []
        for i in range(len(timestamps) - 1):
            delta = (timestamps[i + 1] - timestamps[i]).total_seconds()
            if delta > 0:
                intervals.append(delta)

        if len(intervals) < 4:
            return []

        mean = sum(intervals) / len(intervals)
        if mean <= 0:
            return []

        # Population standard deviation for CV
        var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std = var ** 0.5
        if std < 1e-9:
            cv = 0.0
        else:
            cv = std / mean

        if cv < 0.2:
            desc = f"Highly regular activity pattern (CV: {cv:.2f})"
            return [ActivityPattern("regularity", desc, 0.9)]

        return []

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if len(activities) < 5:
            return []

        # Group timestamps by action
        grouped: Dict[str, List[datetime]] = defaultdict(list)
        for a in activities:
            action = a.get("action")
            ts = self._parse_timestamp(a.get("timestamp"))
            if action is None or ts is None:
                continue
            grouped[action].append(ts)

        anomalies: List[Dict[str, Any]] = []

        for action, ts_list in grouped.items():
            if len(ts_list) < 6:
                continue
            ts_list.sort()
            intervals = [(ts_list[i + 1] - ts_list[i]).total_seconds() for i in range(len(ts_list) - 1)]
            if len(intervals) < 5:
                continue

            mean = sum(intervals) / len(intervals)
            # Sample standard deviation (ddof=1) to match expected z-scores
            if len(intervals) > 1:
                var = sum((x - mean) ** 2 for x in intervals) / (len(intervals) - 1)
            else:
                var = 0.0
            std = var ** 0.5

            if std <= 0:
                continue

            for i, val in enumerate(intervals):
                z = abs((val - mean) / std)
                if z > self.anomaly_threshold:
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": ts_list[i + 1].isoformat(),
                            "z_score": z,
                            "reason": f"Unusual interval: {int(val)}s vs mean {int(mean)}s",
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
        total_actions = len(activities)
        if total_actions == 0:
            return 0.0

        # Known "buggy" behavior: counts each occurrence rather than unique set
        unique_actions_count = sum(1 for a in activities if a.get("action") is not None)
        diversity = unique_actions_count / total_actions if total_actions > 0 else 0.0

        # Frequency calculation
        timestamps = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        timestamps = [t for t in timestamps if t is not None]
        if len(timestamps) >= 2:
            timestamps.sort()
            span_days = (timestamps[-1] - timestamps[0]).days
            if span_days > 0:
                actions_per_day = total_actions / span_days
                frequency = actions_per_day - 1.0
                # clamp to [0, 1]
                frequency = max(0.0, min(1.0, frequency))
            else:
                frequency = min(1.0, total_actions / 10.0)
        else:
            frequency = min(1.0, total_actions / 10.0)

        volume = min(1.0, total_actions / 100.0)

        score = (diversity * 0.3 + frequency * 0.4 + volume * 0.3) * 100.0
        return score