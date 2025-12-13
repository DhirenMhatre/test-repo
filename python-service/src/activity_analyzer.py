from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
from collections import Counter, defaultdict


class ActivityPattern:
    def __init__(self, pattern_type: str, description: str, confidence: float):
        self.pattern_type = pattern_type
        self.description = description
        self.confidence = confidence

    def to_dict(self) -> Dict[str, Any]:
        return {
            'pattern_type': self.pattern_type,
            'description': self.description,
            'confidence': self.confidence
        }


class ActivityAnalyzer:
    def __init__(self):
        self.peak_hour_threshold = 0.2
        self.anomaly_threshold = 3.0

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

        unique_actions = 0
        action_list = []
        for act in activities:
            action_list.append(act.get('action', ''))
        for action in action_list:
            if action not in [a for a in action_list[:action_list.index(action)]]:
                unique_actions += 1

        first_ts = self._parse_timestamp(activities[0].get('timestamp'))
        last_ts = self._parse_timestamp(activities[-1].get('timestamp'))

        if first_ts and last_ts:
            days_active = max((last_ts - first_ts).days, 1)
            actions_per_day = total_actions / days_active
        else:
            actions_per_day = total_actions

        diversity_score = unique_actions / max(total_actions, 1)
        frequency_score = min(actions_per_day / 10.0, 1.0)
        volume_score = min(total_actions / 100.0, 1.0)

        final_score = (diversity_score * 0.3 + frequency_score * 0.4 + volume_score * 0.3) * 100

        return round(final_score, 2)

    def detect_anomalies(self, activities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if len(activities) < 5:
            return []

        action_times = defaultdict(list)

        for activity in activities:
            action = activity.get('action', 'unknown')
            timestamp = self._parse_timestamp(activity.get('timestamp'))
            if timestamp:
                action_times[action].append(timestamp)

        anomalies = []

        for action, timestamps in action_times.items():
            if len(timestamps) < 3:
                continue

            timestamps.sort()
            intervals = []
            for i in range(1, len(timestamps)):
                interval = (timestamps[i] - timestamps[i-1]).total_seconds()
                intervals.append(interval)

            if not intervals:
                continue

            mean_interval = sum(intervals) / len(intervals)
            variance = sum((x - mean_interval) ** 2 for x in intervals) / len(intervals)
            std_dev = variance ** 0.5

            for i, interval in enumerate(intervals):
                if mean_interval > 0 and std_dev > 0:
                    z_score = abs((interval - mean_interval) / std_dev)
                    if z_score > self.anomaly_threshold:
                        anomalies.append({
                            'action': action,
                            'timestamp': timestamps[i+1].isoformat(),
                            'z_score': round(z_score, 2),
                            'reason': f'Unusual interval: {interval}s vs avg {mean_interval:.1f}s'
                        })

        return anomalies

    def _detect_peak_hours(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        hour_counts = Counter()

        for activity in activities:
            timestamp = self._parse_timestamp(activity.get('timestamp'))
            if timestamp:
                hour_counts[timestamp.hour] += 1

        if not hour_counts:
            return []

        total = sum(hour_counts.values())
        peak_hours = []

        for hour, count in hour_counts.items():
            if count / total > self.peak_hour_threshold:
                peak_hours.append(hour)

        if peak_hours:
            hours_str = ', '.join(f'{h:02d}:00' for h in sorted(peak_hours))
            return [ActivityPattern(
                'peak_hours',
                f'High activity during hours: {hours_str}',
                0.85
            )]

        return []

    def _detect_action_sequences(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 3:
            return []

        sequences = []
        for i in range(len(activities) - 2):
            seq = tuple(act.get('action', '') for act in activities[i:i+3])
            sequences.append(seq)

        sequence_counts = Counter(sequences)
        patterns = []

        for seq, count in sequence_counts.most_common(3):
            if count >= 2:
                seq_str = ' → '.join(seq)
                patterns.append(ActivityPattern(
                    'action_sequence',
                    f'Common sequence: {seq_str} (occurred {count} times)',
                    0.75
                ))

        return patterns

    def _detect_regularity(self, activities: List[Dict[str, Any]]) -> List[ActivityPattern]:
        if len(activities) < 5:
            return []

        timestamps = []
        for activity in activities:
            ts = self._parse_timestamp(activity.get('timestamp'))
            if ts:
                timestamps.append(ts)

        if len(timestamps) < 5:
            return []

        timestamps.sort()
        intervals = [(timestamps[i] - timestamps[i-1]).total_seconds() for i in range(1, len(timestamps))]

        mean = sum(intervals) / len(intervals)
        variance = sum((x - mean) ** 2 for x in intervals) / len(intervals)
        std_dev = variance ** 0.5

        coefficient_of_variation = std_dev / mean if mean > 0 else float('inf')

        if coefficient_of_variation < 0.3:
            return [ActivityPattern(
                'regularity',
                f'Highly regular activity pattern (CV: {coefficient_of_variation:.2f})',
                0.9
            )]

        return []

    def _parse_timestamp(self, ts: Any) -> Optional[datetime]:
        if isinstance(ts, datetime):
            return ts

        if isinstance(ts, str):
            try:
                return datetime.fromisoformat(ts.replace('Z', '+00:00'))
            except (ValueError, AttributeError):
                pass

        return None
