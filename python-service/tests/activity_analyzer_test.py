from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
import datetime as _dt


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


class _DateTimeShim:
    # Shim to allow monkeypatching .fromisoformat in tests
    def fromisoformat(self, s: str) -> _dt.datetime:
        # Handle 'Z' suffix as UTC
        if isinstance(s, str):
            s = s.replace("Z", "+00:00")
        return _dt.datetime.fromisoformat(s)


# Expose a patchable object named `datetime` as expected by tests
datetime = _DateTimeShim()


class ActivityAnalyzer:
    def __init__(self, peak_hour_threshold: float = 0.2, anomaly_threshold: float = 3.0):
        self.peak_hour_threshold = peak_hour_threshold
        self.anomaly_threshold = anomaly_threshold

    def _parse_timestamp(self, ts: Any) -> Optional[_dt.datetime]:
        if isinstance(ts, _dt.datetime):
            return ts
        if isinstance(ts, str):
            try:
                return datetime.fromisoformat(ts)
            except Exception:
                return None
        return None

    def analyze_patterns(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        # Do not swallow exceptions; let them propagate as per tests
        patterns: List[ActivityPattern] = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        total_actions = len(activities)
        if total_actions == 0:
            return 0.0

        unique_actions = len({a.get("action") for a in activities})
        diversity_score = unique_actions / total_actions if total_actions else 0.0

        # Determine frequency based on first and last valid timestamps in the provided order
        first_valid: Optional[_dt.datetime] = None
        last_valid: Optional[_dt.datetime] = None
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                if first_valid is None:
                    first_valid = ts
                last_valid = ts

        if first_valid is None or last_valid is None:
            days_active = 1
        else:
            delta_days = (last_valid - first_valid).days
            # Minimum of 1 day as per tests, even if negative due to unsorted inputs
            days_active = max(delta_days, 1)

        actions_per_day = total_actions / max(days_active, 1)
        # Normalize frequency to [0,1] using factor 10 as per test expectations
        frequency_score = min(actions_per_day / 10.0, 1.0)

        # Volume score normalized by 100 actions
        volume_score = min(total_actions / 100.0, 1.0)

        final = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100.0
        # Round to 1 decimal to match expectations precisely
        return round(final, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Require at least 5 activities overall
        if len(activities) < 5:
            return []

        # Group timestamps by action
        action_ts: Dict[str, List[_dt.datetime]] = {}
        for a in activities:
            action = a.get("action")
            ts = self._parse_timestamp(a.get("timestamp"))
            if action is None or ts is None:
                continue
            action_ts.setdefault(action, []).append(ts)

        anomalies: List[Dict[str, Any]] = []
        for action, ts_list in action_ts.items():
            if len(ts_list) < 3:
                continue
            ts_list_sorted = sorted(ts_list)
            intervals: List[float] = []
            for i in range(1, len(ts_list_sorted)):
                intervals.append((ts_list_sorted[i] - ts_list_sorted[i - 1]).total_seconds())

            if len(intervals) < 2:
                continue

            mean = sum(intervals) / len(intervals)
            # Compute sample standard deviation
            var_num = sum((x - mean) ** 2 for x in intervals)
            denom = max(len(intervals) - 1, 1)
            std_dev = (var_num / denom) ** 0.5

            if std_dev == 0:
                continue

            # Flag intervals with z-score >= threshold
            for idx, interval in enumerate(intervals, start=1):
                z = abs((interval - mean) / std_dev)
                if z >= self.anomaly_threshold:
                    # Interval idx corresponds to timestamp at ts_list_sorted[idx]
                    ts_outlier = ts_list_sorted[idx]
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": ts_outlier.isoformat(),
                            "reason": f"Unusual interval detected for action '{action}'",
                            "z_score": float(z),
                        }
                    )

        return anomalies

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hours_count: Dict[int, int] = {}
        total_valid = 0
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is None:
                continue
            total_valid += 1
            hours_count[ts.hour] = hours_count.get(ts.hour, 0) + 1

        if total_valid == 0:
            return []

        # Find hours exceeding threshold
        peaks: List[int] = []
        for h, c in hours_count.items():
            proportion = c / total_valid
            if proportion >= self.peak_hour_threshold:
                peaks.append(h)

        if not peaks:
            return []

        peaks_sorted = sorted(peaks)
        hours_str = ", ".join(f"{h:02d}:00" for h in peaks_sorted)
        description = f"Peak activity hours detected around: {hours_str}"
        # Confidence expected to be 0.85 in tests
        return [ActivityPattern(pattern_type="peak_hours", description=description, confidence=0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        # Sort by timestamp if possible; fallback to original order
        parsed: List[Tuple[Optional[_dt.datetime], str]] = []
        for a in activities:
            parsed.append((self._parse_timestamp(a.get("timestamp")), a.get("action", "")))

        # If at least two timestamps are valid, sort by ts; else use original order
        valid_count = sum(1 for ts, _ in parsed if ts is not None)
        if valid_count >= 2:
            parsed.sort(key=lambda x: (x[0] is None, x[0]))

        actions_ordered = [act for _, act in parsed]
        # Count 3-length sequences
        seq_counts: Dict[Tuple[str, str, str], int] = {}
        for i in range(len(actions_ordered) - 2):
            seq = tuple(actions_ordered[i : i + 3])
            seq_counts[seq] = max(seq_counts.get(seq, 0), 0) + 1

        patterns: List[ActivityPattern] = []
        for seq, count in seq_counts.items():
            if count >= 2:
                seq_str = " → ".join(seq)
                description = f"Common sequence: {seq_str} (occurred {count} times)"
                patterns.append(
                    ActivityPattern(
                        pattern_type="action_sequence",
                        description=description,
                        confidence=0.8,
                    )
                )
        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Need at least 6 timestamps (=> 5 intervals) to assess regularity per tests
        ts_list = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        ts_valid = [ts for ts in ts_list if ts is not None]
        if len(ts_valid) < 6:
            return []

        ts_valid.sort()
        intervals = [(ts_valid[i] - ts_valid[i - 1]).total_seconds() for i in range(1, len(ts_valid))]
        if len(intervals) < 5:
            return []

        mean = sum(intervals) / len(intervals) if intervals else 0.0
        if mean == 0:
            return []

        var_num = sum((x - mean) ** 2 for x in intervals)
        denom = max(len(intervals) - 1, 1)
        std_dev = (var_num / denom) ** 0.5
        cv = std_dev / mean if mean > 0 else 0.0

        # Threshold for high regularity
        if cv <= 0.1:
            avg_minutes = mean / 60.0
            description = f"Highly regular activity. Avg interval: {avg_minutes:.2f} minutes, CV: {cv:.2f}"
            return [ActivityPattern(pattern_type="regularity", description=description, confidence=0.9)]

        return []