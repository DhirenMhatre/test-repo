from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional


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
                # Support Zulu ("Z") suffix for UTC
                s = ts
                if s.endswith("Z"):
                    s = s[:-1] + "+00:00"
                return datetime.fromisoformat(s)
            except Exception:
                return None
        return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []

        hour_counts = [0] * 24
        total = 0
        for act in activities:
            dt = self._parse_timestamp(act.get("timestamp"))
            if dt is None:
                continue
            hour_counts[dt.hour] += 1
            total += 1

        if total == 0:
            return []

        peak_hours = [h for h, c in enumerate(hour_counts) if (c / total) > self.peak_hour_threshold]
        if not peak_hours:
            return []

        hours_str = ", ".join(f"{h:02d}:00" for h in sorted(peak_hours))
        desc = f"High activity during hours: {hours_str}"
        # Confidence fixed as per tests
        return [ActivityPattern("peak_hours", desc, 0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        # Sort activities by timestamp, fallback to stable order for invalid timestamps
        sorted_acts: List[tuple[datetime, str]] = []
        for i, act in enumerate(activities):
            dt = self._parse_timestamp(act.get("timestamp"))
            if dt is None:
                # Place invalid timestamps deterministically at the front while preserving input order
                dt = datetime.min.replace(tzinfo=None) + timedelta(microseconds=i)
            sorted_acts.append((dt, act.get("action")))
        sorted_acts.sort(key=lambda x: x[0])

        actions = [a for _, a in sorted_acts]
        if len(actions) < 3:
            return []

        seq_counts: Dict[tuple, int] = {}
        for i in range(len(actions) - 2):
            seq = tuple(actions[i : i + 3])
            seq_counts[seq] = seq_counts.get(seq, 0) + 1

        patterns: List[ActivityPattern] = []
        for seq, count in seq_counts.items():
            if count >= 2:
                arrow = " → ".join(seq)
                times_str = f"{count} times"
                desc = f"Common action sequence detected: {arrow} occurred {times_str}"
                patterns.append(ActivityPattern("action_sequence", desc, 0.75))
        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        times: List[datetime] = []
        for act in activities:
            dt = self._parse_timestamp(act.get("timestamp"))
            if dt is not None:
                times.append(dt)

        # Require at least 5 valid timestamps
        if len(times) < 5:
            return []

        times.sort()
        intervals = [(times[i] - times[i - 1]).total_seconds() for i in range(1, len(times))]

        if not intervals:
            return []

        mean = sum(intervals) / len(intervals)
        if mean <= 0:
            return []

        variance = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        stdev = variance ** 0.5
        cv = 0.0 if mean == 0 else (stdev / mean)

        if cv < 0.3:
            desc = f"Highly regular activity pattern detected (CV: {cv:.2f})"
            return [ActivityPattern("regularity", desc, 0.9)]
        return []

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        if not activities:
            return 0.0

        total_actions = len(activities)
        unique_actions = len({a.get("action") for a in activities})

        parsed_times = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        valid_times = [t for t in parsed_times if t is not None]

        if valid_times:
            first = min(valid_times)
            last = max(valid_times)
            # At least 1 day to avoid division by zero
            days = max((last - first).days, 1)
            actions_per_day = total_actions / days
        else:
            # Fallback as per tests: actions_per_day == total_actions
            actions_per_day = total_actions

        diversity = (unique_actions / total_actions) if total_actions else 0.0
        frequency = min(actions_per_day / 10.0, 1.0)
        volume = min(total_actions / 100.0, 1.0)

        score = (diversity * 0.3 + frequency * 0.4 + volume * 0.3) * 100.0
        return round(score, 2)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Require at least 5 activities overall (as per tests)
        if len(activities) < 5:
            return []

        by_action: Dict[str, List[datetime]] = {}
        for act in activities:
            name = act.get("action")
            dt = self._parse_timestamp(act.get("timestamp"))
            if dt is None:
                continue
            by_action.setdefault(name, []).append(dt)

        anomalies: List[Dict[str, Any]] = []
        for action, times in by_action.items():
            if len(times) < 3:
                continue
            times.sort()
            intervals = [(times[i] - times[i - 1]).total_seconds() for i in range(1, len(times))]
            if len(intervals) < 2:
                continue

            mean = sum(intervals) / len(intervals)
            variance = sum((x - mean) ** 2 for x in intervals) / len(intervals)
            stdev = variance ** 0.5

            if stdev == 0:
                continue

            for i, interval in enumerate(intervals):
                z = abs(interval - mean) / stdev if stdev > 0 else 0.0
                if z > self.anomaly_threshold:
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": times[i + 1].isoformat(),
                            "reason": f"Unusual interval detected for action '{action}'",
                            "z_score": round(z, 2),
                        }
                    )

        return anomalies

    def analyze_patterns(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        patterns: List[ActivityPattern] = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns