import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

const d = (y: number, m: number, day: number, h = 0, mi = 0) => new Date(y, m - 1, day, h, mi)

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.getUserSummary('u1')).toBeNull()
  })

  it('computes correct summary including most frequent action and averages', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2023, 1, 1, 10, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 10, 10) },
      { id: '3', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 11, 0) },
      { id: '4', user_id: 'u1', action: 'purchase', timestamp: d(2023, 1, 3, 9, 0) },
      { id: '5', user_id: 'u2', action: 'other', timestamp: d(2023, 1, 1, 9, 0) }
    ]
    const dashboard = new ActivityDashboard(activities as any)

    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(4)
    expect(summary!.uniqueActions).toBe(3)
    // First = Jan 1 10:00, Last = Jan 3 09:00 -> ceil((~47h)/24)=2 days; 4/2 = 2.00
    expect(summary!.actionsPerDay).toBe(2)
    expect(summary!.mostFrequentAction).toBe('view')
    // Sessions: [10:00,10:10] (same), 11:00 (>30m), Jan3 9:00 (>30m) => 3 sessions => 4/3 = 1.33
    expect(summary!.averageActionsPerSession).toBe(1.33)
  })

  it('averageActionsPerSession is total when all actions within one session (<=30m gaps)', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 2, 1, 10, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 2, 1, 10, 10) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d(2024, 2, 1, 10, 30) }
    ]
    const dashboard = new ActivityDashboard(activities as any)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(3)
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.getActivityTrends('none', 'day')).toEqual([])
  })

  it('groups by day and computes growth rate across non-consecutive days', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2023, 1, 1, 10, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 10, 10) },
      { id: '3', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 11, 0) },
      { id: '4', user_id: 'u1', action: 'purchase', timestamp: d(2023, 1, 3, 9, 0) }
    ]
    const dashboard = new ActivityDashboard(activities as any)
    const trends = dashboard.getActivityTrends('u1', 'day')

    expect(trends.length).toBe(2)
    expect(trends[0].count).toBe(3)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-66.67)
  })

  it('groups by hour and computes growth rate', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 5, 10, 10, 5) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2023, 5, 10, 10, 25) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d(2023, 5, 10, 11, 0) }
    ]
    const dashboard = new ActivityDashboard(activities as any)
    const trends = dashboard.getActivityTrends('u1', 'hour')

    expect(trends.length).toBe(2)
    expect(trends[0].count).toBe(2)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50)
  })

  it('groups by week into a single bucket when all activities in same week', () => {
    const activities = [
      { id: '1', user_id: 'u3', action: 'a', timestamp: d(2023, 4, 3, 9, 0) },  // Monday
      { id: '2', user_id: 'u3', action: 'b', timestamp: d(2023, 4, 5, 14, 0) }, // Wednesday
      { id: '3', user_id: 'u3', action: 'c', timestamp: d(2023, 4, 6, 18, 0) }  // Thursday
    ]
    const dashboard = new ActivityDashboard(activities as any)
    const trends = dashboard.getActivityTrends('u3', 'week')

    expect(trends.length).toBe(1)
    expect(trends[0].count).toBe(3)
    expect(trends[0].growthRate).toBe(0)
    expect(typeof trends[0].period).toBe('string')
    expect(trends[0].period.includes('-W')).toBe(true)
  })

  it('groups by month and computes growth rate across months', () => {
    const activities = [
      { id: '1', user_id: 'u5', action: 'a', timestamp: d(2023, 1, 15, 10, 0) },
      { id: '2', user_id: 'u5', action: 'b', timestamp: d(2023, 2, 3, 12, 0) }
    ]
    const dashboard = new ActivityDashboard(activities as any)
    const trends = dashboard.getActivityTrends('u5', 'month')

    expect(trends.length).toBe(2)
    expect(trends[0].count).toBe(1)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(0)
    expect(trends[0].period).toBe('2023-01')
    expect(trends[1].period).toBe('2023-02')
  })

  it('default periodType is "day"', () => {
    const activities = [
      { id: '1', user_id: 'u6', action: 'a', timestamp: d(2024, 3, 1, 8, 0) },
      { id: '2', user_id: 'u6', action: 'b', timestamp: d(2024, 3, 1, 9, 0) },
      { id: '3', user_id: 'u6', action: 'c', timestamp: d(2024, 3, 2, 9, 0) }
    ]
    const dashboard = new ActivityDashboard(activities as any)
    const defaultTrends = dashboard.getActivityTrends('u6')
    const dayTrends = dashboard.getActivityTrends('u6', 'day')
    expect(defaultTrends).toEqual(dayTrends)
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('returns activities within inclusive date range for the specified user', () => {
    const a1 = { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 6, 1, 9, 0) }
    const a2 = { id: '2', user_id: 'u1', action: 'b', timestamp: d(2023, 6, 2, 9, 0) }
    const a3 = { id: '3', user_id: 'u1', action: 'c', timestamp: d(2023, 6, 3, 9, 0) }
    const a4 = { id: '4', user_id: 'u2', action: 'x', timestamp: d(2023, 6, 2, 10, 0) }
    const dashboard = new ActivityDashboard([a1, a2, a3, a4] as any)

    const res = dashboard.filterByDateRange('u1', d(2023, 6, 2, 9, 0), d(2023, 6, 3, 9, 0))
    expect(res.map(r => r.id)).toEqual(['2', '3'])
  })

  it('filters only activities of target user', () => {
    const a1 = { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 7, 1, 9, 0) }
    const a2 = { id: '2', user_id: 'u2', action: 'b', timestamp: d(2023, 7, 1, 9, 0) }
    const a3 = { id: '3', user_id: 'u1', action: 'c', timestamp: d(2023, 7, 2, 10, 0) }
    const dashboard = new ActivityDashboard([a1, a2, a3] as any)

    const res = dashboard.filterByDateRange('u1', d(2023, 7, 1, 0, 0), d(2023, 7, 3, 0, 0))
    expect(res.map(r => r.user_id).every(u => u === 'u1')).toBe(true)
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('aggregates counts, percentages, and occurrence dates, sorted by count desc', () => {
    const acts = [
      { id: '1', user_id: 'uA', action: 'view', timestamp: d(2023, 1, 1, 9, 0) },
      { id: '2', user_id: 'uA', action: 'login', timestamp: d(2023, 1, 1, 8, 0) },
      { id: '3', user_id: 'uA', action: 'view', timestamp: d(2023, 1, 2, 9, 0) },
      { id: '4', user_id: 'uA', action: 'click', timestamp: d(2023, 1, 3, 12, 0) },
      { id: '5', user_id: 'uA', action: 'click', timestamp: d(2023, 1, 3, 13, 0) },
      { id: '6', user_id: 'uA', action: 'view', timestamp: d(2023, 1, 2, 10, 0) }
    ]
    const dashboard = new ActivityDashboard(acts as any)
    const groups = dashboard.aggregateByAction('uA')

    expect(groups.length).toBe(3)
    // Sorted by count: view(3), click(2), login(1)
    expect(groups[0].action).toBe('view')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(50)
    expect(groups[0].firstOccurrence).toEqual(d(2023, 1, 1, 9, 0))
    expect(groups[0].lastOccurrence).toEqual(d(2023, 1, 2, 10, 0))

    expect(groups[1].action).toBe('click')
    expect(groups[1].count).toBe(2)
    expect(groups[1].percentage).toBe(33.33)
    expect(groups[1].firstOccurrence).toEqual(d(2023, 1, 3, 12, 0))
    expect(groups[1].lastOccurrence).toEqual(d(2023, 1, 3, 13, 0))

    expect(groups[2].action).toBe('login')
    expect(groups[2].count).toBe(1)
    expect(groups[2].percentage).toBe(16.67)
    expect(groups[2].firstOccurrence).toEqual(d(2023, 1, 1, 8, 0))
    expect(groups[2].lastOccurrence).toEqual(d(2023, 1, 1, 8, 0))
  })

  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.aggregateByAction('none')).toEqual([])
  })
})

describe('ActivityDashboard - getTopActions and getTopActions_old', () => {
  it('getTopActions_old returns all aggregated actions ignoring limit', () => {
    const acts = [
      { id: '1', user_id: 'uB', action: 'x', timestamp: d(2023, 1, 1, 10, 0) },
      { id: '2', user_id: 'uB', action: 'y', timestamp: d(2023, 1, 1, 11, 0) },
      { id: '3', user_id: 'uB', action: 'x', timestamp: d(2023, 1, 2, 12, 0) }
    ]
    const dashboard = new ActivityDashboard(acts as any)
    const all = dashboard.getTopActions_old('uB', 1)
    expect(all.length).toBe(2)
    expect(all[0].action).toBe('x')
    expect(all[0].count).toBe(2)
    expect(all[1].action).toBe('y')
    expect(all[1].count).toBe(1)
  })

  it('getTopActions limits the number of returned action groups and sorts by count', () => {
    const acts = [
      { id: '1', user_id: 'uC', action: 'a', timestamp: d(2023, 2, 1, 9, 0) },
      { id: '2', user_id: 'uC', action: 'b', timestamp: d(2023, 2, 1, 10, 0) },
      { id: '3', user_id: 'uC', action: 'a', timestamp: d(2023, 2, 1, 11, 0) },
      { id: '4', user_id: 'uC', action: 'c', timestamp: d(2023, 2, 2, 12, 0) },
      { id: '5', user_id: 'uC', action: 'b', timestamp: d(2023, 2, 2, 13, 0) },
      { id: '6', user_id: 'uC', action: 'b', timestamp: d(2023, 2, 3, 14, 0) }
    ]
    const dashboard = new ActivityDashboard(acts as any)
    const top2 = dashboard.getTopActions('uC', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('b')
    expect(top2[0].count).toBe(3)
    expect(top2[1].action).toBe('a')
    expect(top2[1].count).toBe(2)
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('none')).toBe(0)
  })

  it('computes weighted score based on volume, diversity, and frequency', () => {
    const acts = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2023, 1, 1, 10, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 10, 10) },
      { id: '3', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 11, 0) },
      { id: '4', user_id: 'u1', action: 'purchase', timestamp: d(2023, 1, 3, 9, 0) }
    ]
    const dashboard = new ActivityDashboard(acts as any)
    // From previous summary test: total=4, unique=3, actionsPerDay=2
    // volumeScore = min(4/100,1)*30 = 1.2
    // diversityScore = min(3/10,1)*30 = 9
    // frequencyScore = min(2/5,1)*40 = 16
    // total = 26.2
    expect(dashboard.calculateEngagementScore('u1')).toBe(26.2)
  })
})

describe('ActivityDashboard - integration checks', () => {
  it('getActivityTrends only returns periods with activity (no zero-count periods)', () => {
    const acts = [
      { id: '1', user_id: 'uZ', action: 'a', timestamp: d(2023, 1, 1, 9, 0) },
      { id: '2', user_id: 'uZ', action: 'b', timestamp: d(2023, 1, 3, 9, 0) }
    ]
    const dashboard = new ActivityDashboard(acts as any)
    const trends = dashboard.getActivityTrends('uZ', 'day')
    // Only two periods even though Jan 2 has no activity
    expect(trends.length).toBe(2)
    expect(trends[0].count).toBe(1)
    expect(trends[1].count).toBe(1)
  })

  it('handles large limit in getTopActions gracefully by returning all available groups', () => {
    const acts = [
      { id: '1', user_id: 'uY', action: 'x', timestamp: d(2023, 3, 1, 9, 0) },
      { id: '2', user_id: 'uY', action: 'y', timestamp: d(2023, 3, 1, 10, 0) }
    ]
    const dashboard = new ActivityDashboard(acts as any)
    const top10 = dashboard.getTopActions('uY', 10)
    expect(top10.length).toBe(2)
    const actions = top10.map(g => g.action).sort()
    expect(actions).toEqual(['x', 'y'])
  })
})