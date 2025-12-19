from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple
from collections import Counter, defaultdict


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

    def analyze_patterns(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []
        patterns: List[ActivityPattern] = []
        patterns.extend(self._detect_peak_hours(activities))
        patterns.extend(self._detect_action_sequences(activities))
        patterns.extend(self._detect_regularity(activities))
        return patterns

    def get_user_score(self, activities: List[Dict[str, Any]]) -> float:
        total = len(activities)
        if total == 0:
            return 0.0

        # Diversity: ratio of unique actions
        unique_actions = len({a.get("action") for a in activities})
        diversity = unique_actions / total if total > 0 else 0.0

        # Frequency: actions per active day normalized to 10/day
        dts = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        valid_dts = [dt for dt in dts if isinstance(dt, datetime)]
        if valid_dts:
            days_active = len({dt.date() for dt in valid_dts})
            days_active = max(days_active, 1)
        else:
            days_active = 1  # If timestamps invalid, assume single day

        actions_per_day = total / days_active
        frequency = min(actions_per_day / 10.0, 1.0)

        # Volume: normalized to 100 actions
        volume = min(total / 100.0, 1.0)

        score = (diversity * 0.3 + frequency * 0.4 + volume * 0.3) * 100.0
        return round(score, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Group activities by action and sort by timestamp
        grouped: Dict[str, List[datetime]] = defaultdict(list)
        for a in activities:
            action = a.get("action")
            dt = self._parse_timestamp(a.get("timestamp"))
            if action and isinstance(dt, datetime):
                grouped[action].append(dt)

        anomalies: List[Dict[str, Any]] = []
        for action, times in grouped.items():
            times.sort()
            # Need at least 5 timestamps (4 intervals) to compare last interval against history
            if len(times) < 5:
                continue
            intervals = [(times[i] - times[i - 1]).total_seconds() for i in range(1, len(times))]
            # Evaluate each interval starting from the 4th one against previous intervals
            for idx in range(3, len(intervals)):
                hist = intervals[:idx]
                mean_hist = sum(hist) / len(hist)
                # Standard deviation (sample or population doesn't matter for constant intervals; use population)
                var_hist = sum((x - mean_hist) ** 2 for x in hist) / len(hist)
                std_hist = var_hist ** 0.5
                z = 0.0
                if std_hist == 0.0:
                    # If history is perfectly regular, any deviation is anomalous; scale by relative change
                    if mean_hist > 0:
                        z = abs(intervals[idx] - mean_hist) / (mean_hist + 1e-9)
                    else:
                        z = float("inf")
                else:
                    z = abs(intervals[idx] - mean_hist) / std_hist

                if z > self.anomaly_threshold:
                    anomalies.append(
                        {
                            "action": action,
                            "timestamp": times[idx + 1].isoformat(),  # end of anomalous interval
                            "reason": "Unusual interval compared to historical average",
                            "z_score": z,
                        }
                    )
        return anomalies

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if not activities:
            return []

        dts = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        valid_dts = [dt for dt in dts if isinstance(dt, datetime)]
        if not valid_dts:
            return []

        total = len(valid_dts)
        hour_counts = Counter(dt.hour for dt in valid_dts)

        # Determine a "peak" level using the second-highest distinct count heuristic
        distinct_counts = sorted(set(hour_counts.values()), reverse=True)
        if not distinct_counts:
            return []
        if len(distinct_counts) >= 2:
            target_count = distinct_counts[1]  # second-highest
        else:
            target_count = distinct_counts[0]

        selected_hours = sorted(
            [
                h
                for h, c in hour_counts.items()
                if c >= target_count and (c / total) > self.peak_hour_threshold
            ]
        )

        # Fallback: if heuristic results in none, include all hours above threshold
        if not selected_hours:
            selected_hours = sorted([h for h, c in hour_counts.items() if (c / total) > self.peak_hour_threshold])

        if not selected_hours:
            return []

        hours_str = ", ".join(f"{h:02d}:00" for h in selected_hours)
        desc = f"High activity during hours: {hours_str}"
        return [ActivityPattern(pattern_type="peak_hours", description=desc, confidence=0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        # Sort by timestamp to ensure proper sequence
        items: List[Tuple[datetime, str]] = []
        for a in activities:
            dt = self._parse_timestamp(a.get("timestamp"))
            action = a.get("action")
            if isinstance(dt, datetime) and action is not None:
                items.append((dt, action))
        if len(items) < 3:
            return []

        items.sort(key=lambda x: x[0])
        actions_ordered = [act for _, act in items]

        seq_counts: Counter = Counter()
        for i in range(len(actions_ordered) - 2):
            seq = tuple(actions_ordered[i : i + 3])
            seq_counts[seq] += 1

        if not seq_counts:
            return []

        most_common_seq, count = seq_counts.most_common(1)[0]
        if count < 2:
            return []  # Only consider sequences that repeat

        seq_str = " → ".join(most_common_seq)
        desc = f"Common sequence: {seq_str} (occurred {count} times)"
        return [ActivityPattern(pattern_type="action_sequence", description=desc, confidence=0.75)]

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 6:
            return []

        dts = [self._parse_timestamp(a.get("timestamp")) for a in activities]
        valid_dts = [dt for dt in dts if isinstance(dt, datetime)]
        if len(valid_dts) < 6:
            return []

        valid_dts.sort()
        intervals = [(valid_dts[i] - valid_dts[i - 1]).total_seconds() for i in range(1, len(valid_dts))]
        if len(intervals) < 5:
            return []

        mean_interval = sum(intervals) / len(intervals)
        if mean_interval == 0:
            return []

        var = sum((x - mean_interval) ** 2 for x in intervals) / len(intervals)
        std = var ** 0.5
        cv = std / mean_interval  # coefficient of variation

        if cv < 0.05:  # highly regular
            minutes = mean_interval / 60.0
            desc = f"Highly regular activity pattern (avg interval {minutes:.1f} minutes)"
            return [ActivityPattern(pattern_type="regularity", description=desc, confidence=0.9)]
        return []

    def _parse_timestamp(self, ts: Any) -> Optional[datetime]:
        if isinstance(ts, datetime):
            return ts
        if isinstance(ts, str):
            s = ts.strip()
            # Handle ISO 8601 with 'Z'
            if s.endswith("Z"):
                s = s[:-1]
            try:
                return datetime.fromisoformat(s)
            except Exception:
                return None
        return None