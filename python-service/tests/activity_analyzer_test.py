from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple
import math
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

    def _parse_timestamp(self, ts: Any) -> Optional[datetime]:
        try:
            if isinstance(ts, datetime):
                return ts
            if isinstance(ts, str):
                s = ts.strip()
                if s.endswith("Z"):
                    s = s[:-1] + "+00:00"
                dt = datetime.fromisoformat(s)
                return dt
        except Exception:
            return None
        return None

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hours: Counter[int] = Counter()
        total = 0
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is None:
                continue
            hour = ts.hour
            hours[hour] += 1
            total += 1

        if total == 0:
            return []

        # Determine peak hours exceeding threshold strictly
        peak_hours = sorted([h for h, c in hours.items() if (c / total) > self.peak_hour_threshold])

        if not peak_hours:
            return []

        # Format hours as HH:MM strings and join sorted ascending
        hour_strs = [f"{h:02d}:00" for h in peak_hours]
        desc = f"High activity during hours: {', '.join(hour_strs)}"
        # Confidence fixed as per tests
        return [ActivityPattern("peak_hours", desc, 0.85)]

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        # Sort by timestamp where possible; ignore invalid timestamps
        valid: List[Tuple[datetime, str]] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is None:
                continue
            valid.append((ts, str(a.get("action"))))

        if len(valid) < 3:
            return []

        valid.sort(key=lambda x: x[0])

        # Build sliding windows of 3
        triples: Counter[Tuple[str, str, str]] = Counter()
        actions_seq = [act for _, act in valid]
        for i in range(len(actions_seq) - 2):
            triples[(actions_seq[i], actions_seq[i + 1], actions_seq[i + 2])] += 1

        if not triples:
            return []

        # Keep those that occurred at least twice
        frequent = [(seq, cnt) for seq, cnt in triples.items() if cnt >= 2]
        if not frequent:
            return []

        # Sort by count desc then lexicographically for determinism
        frequent.sort(key=lambda x: (-x[1], x[0]))

        # Build description for top sequences (limit to a few for readability)
        parts = []
        for (a, b, c), cnt in frequent[:5]:
            parts.append(f"{a} → {b} → {c} (occurred {cnt} times)")
        desc = "Frequent 3-action sequences: " + "; ".join(parts)

        # Confidence based on the top sequence share
        total_windows = max(1, len(actions_seq) - 2)
        top_cnt = frequent[0][1]
        confidence = min(0.99, max(0.0, top_cnt / total_windows))

        return [ActivityPattern("action_sequence", desc, round(confidence, 2))]

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        # Need at least 5 activities to assess regularity per tests
        if len(activities) < 5:
            return []

        timestamps: List[datetime] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                timestamps.append(ts)

        if len(timestamps) < 5:
            return []

        timestamps.sort()
        intervals: List[float] = []
        for i in range(1, len(timestamps)):
            delta = (timestamps[i] - timestamps[i - 1]).total_seconds()
            if delta > 0:
                intervals.append(delta)

        if len(intervals) < 4:
            return []

        mean = sum(intervals) / len(intervals)
        if mean <= 0:
            return []

        var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std = math.sqrt(var)
        if std == 0:
            cv = 0.0
        else:
            cv = std / mean

        # Low coefficient of variation indicates regularity
        if cv <= 0.1:
            desc = f"Regular activity intervals detected (CV: {cv:.3f}, mean interval: {mean:.1f}s)"
            # Confidence inversely related to CV
            confidence = float(max(0.5, 1.0 - cv))
            return [ActivityPattern("regularity", desc, round(confidence, 2))]

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

        total_actions = len(activities)
        unique_actions = len(set(str(a.get("action")) for a in activities))
        diversity = unique_actions / total_actions if total_actions else 0.0

        # Gather valid timestamps
        valid_ts: List[datetime] = []
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is not None:
                valid_ts.append(ts)

        frequency: float
        if len(valid_ts) >= 2:
            valid_ts.sort()
            elapsed_days = (valid_ts[-1] - valid_ts[0]).total_seconds() / 86400.0
            elapsed_days = max(1.0, elapsed_days)  # Avoid division by zero
            actions_per_day = total_actions / elapsed_days
            frequency = min(1.0, actions_per_day / 10.0)
        else:
            # Fallback when timestamps are missing/invalid
            frequency = min(1.0, total_actions / 10.0)

        volume = min(1.0, total_actions / 100.0)

        score = (0.3 * diversity + 0.4 * frequency + 0.3 * volume) * 100.0
        return round(score, 1)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if len(activities) < 5:
            return []

        # Group timestamps by action
        per_action: Dict[str, List[datetime]] = defaultdict(list)
        for a in activities:
            ts = self._parse_timestamp(a.get("timestamp"))
            if ts is None:
                continue
            action = str(a.get("action"))
            per_action[action].append(ts)

        anomalies: List[Dict[str, Any]] = []

        for action, tlist in per_action.items():
            if len(tlist) < 3:
                continue
            tlist.sort()
            intervals = [(tlist[i] - tlist[i - 1]).total_seconds() for i in range(1, len(tlist))]
            if len(intervals) < 2:
                continue
            mean = sum(intervals) / len(intervals)
            var = sum((x - mean) ** 2 for x in intervals) / len(intervals)
            std = math.sqrt(var)
            if std == 0:
                continue

            for idx, iv in enumerate(intervals):
                # Consider only large positive deviations as anomalies
                z = (iv - mean) / std
                if z > self.anomaly_threshold:
                    anomalies.append(
                        {
                            "action": action,
                            "interval": iv,
                            "z_score": z,
                            "index": idx + 1,  # index of the later timestamp in the pair
                        }
                    )

        return anomalies