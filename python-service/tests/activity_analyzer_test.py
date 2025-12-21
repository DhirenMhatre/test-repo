from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
import datetime as _dt
from collections import Counter, defaultdict
import math


# Provide a shim so tests can patch `src.activity_analyzer.datetime.fromisoformat`
class _DatetimeShim:
    @staticmethod
    def fromisoformat(s: str) -> _dt.datetime:
        return _dt.datetime.fromisoformat(s)


# Expose shim as `datetime` in this module for patching
datetime = _DatetimeShim()


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

    def _parse_timestamp(self, ts: Any) -> Optional[_dt.datetime]:
        if isinstance(ts, _dt.datetime):
            return ts
        if isinstance(ts, str):
            s = ts.strip()
            try:
                if s.endswith("Z"):
                    # ISO8601 Zulu time; remove Z and attach UTC tzinfo
                    base = s[:-1]
                    dt = datetime.fromisoformat(base)  # patched in tests
                    if dt.tzinfo is None:
                        dt = dt.replace(tzinfo=_dt.timezone.utc)
                    return dt
                # Try direct ISO parsing
                return datetime.fromisoformat(s)  # patched in tests
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
        hours: Counter = Counter()
        total_valid = 0
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            total_valid += 1
            # Normalize to naive hour for counting irrespective of tz
            hour = ts.hour
            hours[hour] += 1

        if total_valid == 0 or not hours:
            return []

        hour, count = hours.most_common(1)[0]
        ratio = count / total_valid if total_valid else 0.0
        if ratio >= self.peak_hour_threshold:
            desc = f"Peak activity during {hour:02d}:00 hour ({ratio:.0%} of events)"
            return [ActivityPattern("peak_hours", desc, 0.85)]
        return []

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []
        actions = [act.get("action") for act in activities]
        if len(actions) < 3:
            return []

        triples: Counter = Counter()
        for i in range(len(actions) - 2):
            triple = tuple(actions[i : i + 3])
            triples[triple] += 1

        if not triples:
            return []

        seq, count = triples.most_common(1)[0]
        if count >= 2:
            seq_str = " → ".join(str(x) for x in seq)
            desc = f"Common sequence: {seq_str} (occurred {count} times)"
            return [ActivityPattern("action_sequence", desc, 0.75)]
        return []

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        timestamps = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        timestamps = [t for t in timestamps if t is not None]
        if len(timestamps) < 3:
            return []

        timestamps.sort()
        intervals: List[float] = []
        for i in range(1, len(timestamps)):
            delta = timestamps[i] - timestamps[i - 1]
            intervals.append(delta.total_seconds())

        if len(intervals) < 2:
            return []

        mean = sum(intervals) / len(intervals)
        if mean == 0:
            return []

        # Sample standard deviation
        if len(intervals) > 1:
            variance = sum((x - mean) ** 2 for x in intervals) / (len(intervals) - 1)
        else:
            variance = 0.0
        std_dev = math.sqrt(variance)
        if std_dev == 0:
            cv = 0.0
        else:
            cv = std_dev / mean

        # Consider highly regular if CV < 0.1
        if cv < 0.1:
            desc = f"Highly regular activity intervals detected (CV: {cv:.2f})"
            return [ActivityPattern("regularity", desc, 0.9)]
        return []

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        total = len(activities)
        if total == 0:
            return 0.0

        unique_actions = len(set(a.get("action") for a in activities))
        diversity = unique_actions / total if total else 0.0

        parsed = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        valid_ts = [t for t in parsed if t is not None]
        if valid_ts:
            valid_ts.sort()
            first = valid_ts[0]
            last = valid_ts[-1]
            days_active = max((last - first).days, 1)
            actions_per_day = total / days_active
        else:
            # Fallback as per tests
            actions_per_day = total

        frequency = min(actions_per_day / 10.0, 1.0)
        volume = min(total / 100.0, 1.0)

        score = (diversity * 0.3 + frequency * 0.4 + volume * 0.3) * 100.0
        # Round to 1 decimal to match expected precise values
        return round(score, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Group timestamps by action
        grouped: Dict[Any, List[_dt.datetime]] = defaultdict(list)
        for act in activities:
            ts = self._parse_timestamp(act.get("timestamp"))
            if ts is None:
                continue
            grouped[act.get("action")].append(ts)

        anomalies: List[Dict[str, Any]] = []
        for action, times in grouped.items():
            if len(times) < 5:
                continue
            times.sort()
            intervals: List[float] = []
            for i in range(1, len(times)):
                intervals.append((times[i] - times[i - 1]).total_seconds())

            if len(intervals) < 2:
                continue

            mean = sum(intervals) / len(intervals)
            # Sample std deviation
            variance = sum((x - mean) ** 2 for x in intervals) / (len(intervals) - 1)
            std_dev = math.sqrt(variance)
            if std_dev == 0:
                # Perfect regularity; no anomalies
                continue

            for idx, interval in enumerate(intervals):
                z = abs((interval - mean) / std_dev)
                if z >= self.anomaly_threshold:
                    end_time = times[idx + 1]
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": end_time.isoformat(),
                            "z_score": round(z, 2),
                            "reason": f"Unusual interval detected before {end_time.isoformat()} (z={z:.2f})",
                        }
                    )

        return anomalies