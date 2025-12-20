from dataclasses import dataclass
from datetime import datetime, timezone
from math import sqrt
from typing import Any, Dict, List, Optional, Tuple


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
            # Handle Zulu (UTC) timestamps like 2024-01-01T12:00:00Z
            try:
                if s.endswith("Z"):
                    # Parse basic Z format
                    try:
                        dt = datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
                        return dt
                    except ValueError:
                        # Try with fractional seconds before Z
                        if "." in s:
                            # Split off Z and parse fractional
                            core = s[:-1]
                            dt = datetime.fromisoformat(core).replace(tzinfo=timezone.utc)
                            return dt
                        return None
                # Fallback to fromisoformat for other ISO strings
                return datetime.fromisoformat(s)
            except Exception:
                return None
        return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        timestamps = []
        for a in activities:
            dt = self._parse_timestamp(a.get("timestamp"))
            if dt is not None:
                timestamps.append(dt)

        total = len(timestamps)
        if total == 0:
            return []

        # Count per hour
        counts: Dict[str, int] = {}
        for dt in timestamps:
            hour_label = f"{dt.hour:02d}:00"
            counts[hour_label] = counts.get(hour_label, 0) + 1

        peaks = []
        for hour_label, cnt in counts.items():
            ratio = cnt / total
            if ratio > self.peak_hour_threshold:
                peaks.append((hour_label, ratio))

        if not peaks:
            return []

        # Sort by hour label for deterministic description
        peaks.sort(key=lambda x: x[0])
        hour_list = [h for h, _ in peaks]
        desc = f"Peak hours: {', '.join(hour_list)}"

        # Confidence heuristic: base 0.75 + 0.05 per peak hour, capped
        confidence = round(min(0.95, 0.75 + 0.05 * len(peaks)), 2)

        return [ActivityPattern(pattern_type="peak_hours", description=desc, confidence=confidence)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Maintain provided order to detect sliding sequences
        actions = [a.get("action") for a in activities if a.get("action") is not None]
        if len(actions) < 3:
            return []

        # Count sliding windows of size 3
        seq_counts: Dict[Tuple[str, str, str], int] = {}
        for i in range(len(actions) - 2):
            seq = (actions[i], actions[i + 1], actions[i + 2])
            seq_counts[seq] = seq_counts.get(seq, 0) + 1

        patterns: List[ActivityPattern] = []
        for seq, count in seq_counts.items():
            if count >= 2:
                seq_str = " → ".join(seq)
                desc = f"Common sequence: {seq_str} (occurred {count} times)"
                patterns.append(
                    ActivityPattern(pattern_type="action_sequence", description=desc, confidence=0.75)
                )

        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        timestamps = []
        for a in activities:
            dt = self._parse_timestamp(a.get("timestamp"))
            if dt is not None:
                timestamps.append(dt)

        if len(timestamps) < 5:
            return []

        timestamps.sort()
        intervals: List[float] = []
        for i in range(1, len(timestamps)):
            delta = (timestamps[i] - timestamps[i - 1]).total_seconds()
            if delta >= 0:
                intervals.append(delta)

        if len(intervals) == 0:
            return []

        mean = sum(intervals) / len(intervals)
        # population standard deviation
        variance = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std_dev = sqrt(variance)

        if mean == 0:
            return []

        # Determine regularity via coefficient of variation (std/mean)
        cv = std_dev / mean if mean else float("inf")
        if std_dev == 0 or cv < 0.1:
            desc = (
                "Highly regular activity pattern detected "
                f"(mean interval {round(mean, 2)}s, std dev {round(std_dev, 2)}s)"
            )
            return [ActivityPattern(pattern_type="regularity", description=desc, confidence=0.9)]
        return []

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        total_actions = len(activities)
        unique_actions = len({a.get("action") for a in activities if a.get("action") is not None})

        # Collect parsable timestamps to compute active days
        parsed_ts: List[datetime] = []
        for a in activities:
            dt = self._parse_timestamp(a.get("timestamp"))
            if dt is not None:
                parsed_ts.append(dt)

        if parsed_ts:
            parsed_ts.sort()
            first = parsed_ts[0]
            last = parsed_ts[-1]
            # Use date difference (in whole days); do not add +1 per tests
            days_active = (last.date() - first.date()).days
            days_active = max(1, days_active)
            actions_per_day = total_actions / days_active
        else:
            # Fallback when timestamps are not parseable
            actions_per_day = total_actions

        diversity = (unique_actions / total_actions) if total_actions > 0 else 0.0
        frequency_score = min(actions_per_day / 10.0, 1.0)
        volume_score = min(total_actions / 100.0, 1.0)

        final = (diversity * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100.0
        return round(final, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Global minimal number of activities to consider anomalies
        if len(activities) < 5:
            return []

        # Group timestamps by action
        action_ts: Dict[str, List[datetime]] = {}
        for a in activities:
            action = a.get("action")
            dt = self._parse_timestamp(a.get("timestamp"))
            if action is None or dt is None:
                continue
            action_ts.setdefault(action, []).append(dt)

        anomalies: List[Dict[str, Any]] = []

        for action, ts_list in action_ts.items():
            if len(ts_list) < 3:
                # Not enough timestamps for an action to compute meaningful intervals
                continue
            ts_list.sort()
            intervals: List[float] = []
            for i in range(1, len(ts_list)):
                intervals.append((ts_list[i] - ts_list[i - 1]).total_seconds())

            if len(intervals) < 2:
                continue

            mean = sum(intervals) / len(intervals)
            variance = sum((x - mean) ** 2 for x in intervals) / len(intervals)
            std_dev = sqrt(variance)

            if std_dev == 0:
                continue

            # Compute z-scores for each interval and flag anomalies
            for i, val in enumerate(intervals):
                z = abs((val - mean) / std_dev)
                if z >= self.anomaly_threshold:
                    # Associate anomaly with the end timestamp of the interval
                    ts_flag = ts_list[i + 1]
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": ts_flag.isoformat(),
                            "z_score": round(z, 2),
                            "reason": "Unusual interval detected based on z-score",
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