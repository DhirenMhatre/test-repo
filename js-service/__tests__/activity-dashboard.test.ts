import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

const d = (y: number, m: number, day: number, h = 0, min = 0, s = 0) => new Date(y, m, day, h, min, s)

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes summary metrics correctly for a user', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2023, 0, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'click', timestamp: d(2023, 0, 1, 9, 45) },
      { id: '4', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 1, 10, 5) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 2, 8, 0) },
      { id: '6', user_id: 'u1', action: 'login', timestamp: d(2023, 0, 4, 12, 0) },
      { id: '7', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 4, 12, 40) },
      { id: '8', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 4, 13, 0) },
      { id: '9', user_id: 'u2', action: 'view', timestamp: d(2023, 0, 3, 12, 0) }
    ] as any
    const dashboard = new ActivityDashboard(activities)

    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(8)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.actionsPerDay).toBe(2) // 8 actions over ceil(3.16)=4 days => 2.00
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.averageActionsPerSession).toBe(1.6) // 5 sessions => 8 / 5 = 1.6
  })

  it('rounds averages to 2 decimals', () => {
    // Create 5 actions forming 3 sessions to get 1.666... => 1.67
    const activities = [
      { id: 'a1', user_id: 'u1', action: 'x', timestamp: d(2023, 0, 1, 9, 0) },
      { id: 'a2', user_id: 'u1', action: 'x', timestamp: d(2023, 0, 1, 9, 10) }, // same session
      { id: 'a3', user_id: 'u1', action: 'x', timestamp: d(2023, 0, 1, 10, 0) }, // new session (>30 min)
      { id: 'a4', user_id: 'u1', action: 'x', timestamp: d(2023, 0, 1, 11, 0) }, // new session (>30 min)
      { id: 'a5', user_id: 'u1', action: 'x', timestamp: d(2023, 0, 1, 11, 10) } // same session
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(1.67) // 5 / 3 => 1.666.. => 1.67
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const trends = dashboard.getActivityTrends('uX')
    expect(trends).toEqual([])
  })

  it('groups by day by default and computes growth rate', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 10, 0) },
      { id: '2', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 11, 0) },
      { id: '3', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 2, 12, 0) },
      { id: '4', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 4, 8, 0) },
      { id: '5', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 4, 9, 0) }
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1')
    expect(trends.map(t => t.period)).toEqual(['2023-01-01', '2023-01-02', '2023-01-04'])
    expect(trends.map(t => t.count)).toEqual([2, 1, 2])
    // growth: first -> 0; second: ((1-2)/2)*100 = -50; third: ((2-1)/1)*100 = 100
    expect(trends.map(t => t.growthRate)).toEqual([0, -50, 100])
  })

  it('groups by hour', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 9, 5) },
      { id: '2', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 9, 50) },
      { id: '3', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 10, 0) }
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'hour')
    expect(trends.map(t => t.period)).toEqual(['2023-01-01 09:00', '2023-01-01 10:00'])
    expect(trends.map(t => t.count)).toEqual([2, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50]) // ((1-2)/2)*100
  })

  it('groups by week using getWeekNumber', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 12, 0) }, // 2023-W01
      { id: '2', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 8, 12, 0) }  // 2023-W02
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends.map(t => t.period)).toEqual(['2023-W01', '2023-W02'])
    expect(trends.map(t => t.count)).toEqual([1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, 0])
  })

  it('groups by month and sorts correctly', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 1, 1, 0, 0) }, // Feb
      { id: '2', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 15, 0, 0) }, // Jan
      { id: '3', user_id: 'u1', action: 'a', timestamp: d(2023, 1, 2, 0, 0) }  // Feb
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends.map(t => t.period)).toEqual(['2023-01', '2023-02'])
    expect(trends.map(t => t.count)).toEqual([1, 2])
    // growth from 1 to 2 => 100
    expect(trends.map(t => t.growthRate)).toEqual([0, 100])
  })

  it('handles prev period with zero count by setting growthRate to 0', () => {
    // Create a user with only one period; growth of first is 0
    const activities = [{ id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 5, 1, 0, 0) }] as any
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends).toHaveLength(1)
    expect(trends[0].growthRate).toBe(0)
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters by inclusive start and end dates', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2023, 0, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d(2023, 0, 1, 9, 45) },
      { id: '4', user_id: 'u1', action: 'd', timestamp: d(2023, 0, 1, 10, 5) },
      { id: '5', user_id: 'u2', action: 'e', timestamp: d(2023, 0, 1, 9, 10) }
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const results = dashboard.filterByDateRange('u1', d(2023, 0, 1, 9, 10), d(2023, 0, 1, 9, 45))
    expect(results.map(r => r.id)).toEqual(['2', '3'])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array for user with no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.aggregateByAction('none')).toEqual([])
  })

  it('aggregates actions with counts, percentages, and first/last occurrences, sorted by count desc', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 1, 9, 10) },
      { id: '2', user_id: 'u1', action: 'login', timestamp: d(2023, 0, 1, 9, 0) },
      { id: '3', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 1, 10, 5) },
      { id: '4', user_id: 'u1', action: 'click', timestamp: d(2023, 0, 1, 9, 45) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 2, 8, 0) },
      { id: '6', user_id: 'u1', action: 'login', timestamp: d(2023, 0, 4, 12, 0) },
      { id: '7', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 4, 12, 40) },
      { id: '8', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 4, 13, 0) }
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups.map(g => g.action)).toEqual(['view', 'login', 'click'])
    const view = groups[0]
    expect(view.count).toBe(5)
    expect(view.percentage).toBe(62.5) // 5 / 8 * 100
    expect(view.firstOccurrence.getTime()).toBe(d(2023, 0, 1, 9, 10).getTime())
    expect(view.lastOccurrence.getTime()).toBe(d(2023, 0, 4, 13, 0).getTime())

    const login = groups[1]
    expect(login.count).toBe(2)
    expect(login.percentage).toBe(25)

    const click = groups[2]
    expect(click.count).toBe(1)
    expect(click.percentage).toBe(12.5)
  })
})

describe('ActivityDashboard - getTopActions_old', () => {
  it('returns all groups sorted by count desc, ignoring limit parameter', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2023, 0, 1, 9, 5) },
      { id: '3', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 9, 10) },
      { id: '4', user_id: 'u1', action: 'c', timestamp: d(2023, 0, 1, 9, 15) }
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.getTopActions_old('u1', 1)
    expect(groups.map(g => g.action)).toEqual(['a', 'b', 'c'])
    expect(groups[0].count).toBe(2)
    expect(groups[1].count).toBe(1)
    expect(groups[2].count).toBe(1)
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('limits results to the specified number', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2023, 0, 1, 9, 5) },
      { id: '3', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 9, 10) },
      { id: '4', user_id: 'u1', action: 'c', timestamp: d(2023, 0, 1, 9, 15) },
      { id: '5', user_id: 'u1', action: 'b', timestamp: d(2023, 0, 1, 9, 20) }
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const top2 = dashboard.getTopActions('u1', 2)
    expect(top2.map(g => g.action)).toEqual(['a', 'b'])
    expect(top2).toHaveLength(2)
  })

  it('returns empty array when user has no actions', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.getTopActions('u1')).toEqual([])
  })

  it('returns all when limit exceeds available actions', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2023, 0, 1, 9, 10) }
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const top5 = dashboard.getTopActions('u1', 5)
    expect(top5.map(g => g.action).sort()).toEqual(['a', 'b'])
  })

  it('returns empty when limit is 0', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2023, 0, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2023, 0, 1, 9, 10) }
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const top0 = dashboard.getTopActions('u1', 0)
    expect(top0).toEqual([])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when no summary is available for user', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('u1')).toBe(0)
  })

  it('calculates engagement score with caps and rounding', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2023, 0, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'click', timestamp: d(2023, 0, 1, 9, 45) },
      { id: '4', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 1, 10, 5) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 2, 8, 0) },
      { id: '6', user_id: 'u1', action: 'login', timestamp: d(2023, 0, 4, 12, 0) },
      { id: '7', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 4, 12, 40) },
      { id: '8', user_id: 'u1', action: 'view', timestamp: d(2023, 0, 4, 13, 0) }
    ] as any
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('u1')
    // total 8 => volume 2.4; unique 3 => diversity 9; actionsPerDay 2 => frequency 16; total 27.4
    expect(score).toBe(27.4)
  })

  it('caps each component at its maximum', () => {
    // Create heavy usage to hit caps
    const acts: any[] = []
    // 120 actions over same day => actionsPerDay >= 5 => cap; unique actions 12 => cap
    for (let i = 0; i < 120; i++) {
      acts.push({ id: String(i + 1), user_id: 'u1', action: 'a' + (i % 12), timestamp: d(2023, 0, 1, 0, 0 + i % 60) })
    }
    const dashboard = new ActivityDashboard(acts)
    const score = dashboard.calculateEngagementScore('u1')
    // volume: min(120/100,1)*30 = 30
    // diversity: min(12/10,1)*30 = 30
    // frequency: min(120/1 / 5,1)*40 = 40 (all on same day; actionsPerDay = 120 / 1 = 120 => cap)
    expect(score).toBe(100)
  })
})