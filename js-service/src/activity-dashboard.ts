export interface Activity {
    id: string;
    user_id: string;
    action: string;
    timestamp: Date;
    metadata?: Record<string, any>;
}

export interface ActivitySummary {
    totalActions: number;
    uniqueActions: number;
    actionsPerDay: number;
    mostFrequentAction: string;
    averageActionsPerSession: number;
}

export interface TrendData {
    period: string;
    count: number;
    growthRate: number;
}

export interface ActionGroup {
    action: string;
    count: number;
    percentage: number;
    firstOccurrence: Date;
    lastOccurrence: Date;
}

export class ActivityDashboard {
    private activities: Activity[];

    constructor(activities: Activity[] = []) {
        this.activities = activities;
    }

    public getUserSummary(userId: string): ActivitySummary | null {
        const userActivities = this.activities.filter(a => a.user_id === userId);

        if (userActivities.length === 0) {
            return null;
        }

        const actionCounts = this.countActions(userActivities);
        const mostFrequent = this.findMostFrequentAction(actionCounts);

        const sortedActivities = [...userActivities].sort((a, b) =>
            a.timestamp.getTime() - b.timestamp.getTime()
        );

        const firstActivity = sortedActivities[0].timestamp;
        const lastActivity = sortedActivities[sortedActivities.length - 1].timestamp;
        const daysActive = Math.max(
            Math.ceil((lastActivity.getTime() - firstActivity.getTime()) / (1000 * 60 * 60 * 24)),
            1
        );

        return {
            totalActions: userActivities.length,
            uniqueActions: Object.keys(actionCounts).length,
            actionsPerDay: parseFloat((userActivities.length / daysActive).toFixed(2)),
            mostFrequentAction: mostFrequent,
            averageActionsPerSession: this.calculateAverageActionsPerSession(userActivities)
        };
    }

    public getActivityTrends(userId: string, periodType: 'hour' | 'day' | 'week' | 'month' = 'day'): TrendData[] {
        const userActivities = this.activities.filter(a => a.user_id === userId);

        if (userActivities.length === 0) {
            return [];
        }

        const grouped = this.groupByPeriod(userActivities, periodType);
        const periods = Object.keys(grouped).sort();

        return periods.map((period, index) => {
            const count = grouped[period].length;
            let growthRate = 0;

            if (index > 0) {
                const prevPeriod = periods[index - 1];
                const prevCount = grouped[prevPeriod].length;
                growthRate = prevCount > 0
                    ? parseFloat((((count - prevCount) / prevCount) * 100).toFixed(2))
                    : 0;
            }

            return {
                period,
                count,
                growthRate
            };
        });
    }

    public filterByDateRange(userId: string, startDate: Date, endDate: Date): Activity[] {
        return this.activities.filter(activity =>
            activity.user_id === userId &&
            activity.timestamp >= startDate &&
            activity.timestamp <= endDate
        );
    }

    public aggregateByAction(userId: string): ActionGroup[] {
        const userActivities = this.activities.filter(a => a.user_id === userId);

        if (userActivities.length === 0) {
            return [];
        }

        const actionGroups: ActionGroup[] = [];
        const processedActions = new Set<string>();

        userActivities.forEach(activity => {
            if (!processedActions.has(activity.action)) {
                processedActions.add(activity.action);
                const matchingActivities = userActivities.filter(a => a.action === activity.action);

                const total = userActivities.length;
                const sorted = matchingActivities.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

                actionGroups.push({
                    action: activity.action,
                    count: matchingActivities.length,
                    percentage: parseFloat(((matchingActivities.length / total) * 100).toFixed(2)),
                    firstOccurrence: sorted[0].timestamp,
                    lastOccurrence: sorted[sorted.length - 1].timestamp
                });
            }
        });

        return actionGroups.sort((a, b) => b.count - a.count);
    }

    public getTopActions_old(userId: string, limit: number = 5): ActionGroup[] {
        const userActivities = this.activities.filter(a => a.user_id === userId);
        const actionMap = new Map<string, Activity[]>();

        userActivities.forEach(activity => {
            if (!actionMap.has(activity.action)) {
                actionMap.set(activity.action, []);
            }
            actionMap.get(activity.action)!.push(activity);
        });

        const total = userActivities.length;

        return Array.from(actionMap.entries()).map(([action, acts]) => {
            const sorted = acts.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

            return {
                action,
                count: acts.length,
                percentage: parseFloat(((acts.length / total) * 100).toFixed(2)),
                firstOccurrence: sorted[0].timestamp,
                lastOccurrence: sorted[sorted.length - 1].timestamp
            };
        }).sort((a, b) => b.count - a.count);
    }

    public getTopActions(userId: string, limit: number = 5): ActionGroup[] {
        const allActions = this.aggregateByAction(userId);
        return allActions.slice(0, limit);
    }

    public calculateEngagementScore(userId: string): number {
        const summary = this.getUserSummary(userId);

        if (!summary) {
            return 0;
        }

        const volumeScore = Math.min(summary.totalActions / 100, 1) * 30;
        const diversityScore = Math.min(summary.uniqueActions / 10, 1) * 30;
        const frequencyScore = Math.min(summary.actionsPerDay / 5, 1) * 40;

        return parseFloat((volumeScore + diversityScore + frequencyScore).toFixed(2));
    }

    private countActions(activities: Activity[]): Record<string, number> {
        const counts: Record<string, number> = {};

        activities.forEach(activity => {
            counts[activity.action] = (counts[activity.action] || 0) + 1;
        });

        return counts;
    }

    private findMostFrequentAction(actionCounts: Record<string, number>): string {
        let maxCount = 0;
        let mostFrequent = 'none';

        Object.entries(actionCounts).forEach(([action, count]) => {
            if (count > maxCount) {
                maxCount = count;
                mostFrequent = action;
            }
        });

        return mostFrequent;
    }

    private calculateAverageActionsPerSession(activities: Activity[]): number {
        if (activities.length === 0) return 0;

        const sessionGapMinutes = 30;
        let sessions = 1;

        const sorted = [...activities].sort((a, b) =>
            a.timestamp.getTime() - b.timestamp.getTime()
        );

        for (let i = 1; i < sorted.length; i++) {
            const timeDiff = (sorted[i].timestamp.getTime() - sorted[i-1].timestamp.getTime()) / (1000 * 60);
            if (timeDiff > sessionGapMinutes) {
                sessions++;
            }
        }

        return parseFloat((activities.length / sessions).toFixed(2));
    }

    private groupByPeriod(activities: Activity[], periodType: string): Record<string, Activity[]> {
        const grouped: Record<string, Activity[]> = {};

        activities.forEach(activity => {
            const period = this.getPeriodKey(activity.timestamp, periodType);

            if (!grouped[period]) {
                grouped[period] = [];
            }

            grouped[period].push(activity);
        });

        return grouped;
    }

    private getPeriodKey(date: Date, periodType: string): string {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        const hour = String(date.getHours()).padStart(2, '0');

        switch (periodType) {
            case 'hour':
                return `${year}-${month}-${day} ${hour}:00`;
            case 'day':
                return `${year}-${month}-${day}`;
            case 'week':
                const weekNumber = this.getWeekNumber(date);
                return `${year}-W${String(weekNumber).padStart(2, '0')}`;
            case 'month':
                return `${year}-${month}`;
            default:
                return `${year}-${month}-${day}`;
        }
    }

    private getWeekNumber(date: Date): number {
        const firstDayOfYear = new Date(date.getFullYear(), 0, 1);
        const pastDaysOfYear = (date.getTime() - firstDayOfYear.getTime()) / 86400000;
        return Math.ceil((pastDaysOfYear + firstDayOfYear.getDay() + 1) / 7);
    }
}
