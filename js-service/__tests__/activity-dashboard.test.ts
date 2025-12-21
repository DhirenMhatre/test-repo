import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

function createDefaultActivities() {
  return [
    { id: 'a1', user_id: 'u1', action: 'login', timestamp: new Date(2023, 0, 1, 10, 0, 0) },
    { id: 'a2', user_id: 'u1', action: 'view', timestamp: new Date(2023, 0, 1, 10, 5, 0) },
    { id: 'a3', user_id: 'u1', action: 'view', timestamp: new Date(2023, 0, 1, 10, 10, 0) },
    { id: 'a4', user_id: 'u1', action: 'click', timestamp: new Date(2023, 0, 1, 11, 0, 0) },
    { id: 'a5', user_id: 'u1', action: 'view', timestamp: new Date(2023, 0, 2, 12, 0, 0) },
    { id: 'a6', user_id: 'u1', action: 'logout', timestamp: new Date(2023, 0, 3, 12, 0, 0) },
    { id: 'a7', user_id: 'u1', action: 'login', timestamp: new Date(2023, 0, 3, 13, 0, 0) },
    { id: 'a8', user_id: 'u1', action: 'view', timestamp: new Date(2023, 0, 3, 14, 0, 0) },

    { id: 'b1', user_id: 'u2', action: 'login', timestamp: new Date(2023, 0, 1, 10, 5, 0) },
    { id: 'b2', user_id: 'u2', action: 'view', timestamp: new Date(2023, 0, 8, 9, 0, 0) }
  ]
}

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard.getUserSummary', () => {
  it('returns computed summary for a user', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary?.totalActions).toBe(8)
    expect(summary?.uniqueActions).toBe(4)
    expect(summary?.actionsPerDay).toBe(2.67) // 8 actions across ceil(2.1667)=3 days
    expect(summary?.mostFrequentAction).toBe('view')
    expect(summary?.averageActionsPerSession).toBe(1.6) // sessions=5
  })

  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const summary = dashboard.getUserSummary('u-missing')
    expect(summary).toBeNull()
  })

  it('calculates averageActionsPerSession with 30-minute boundary correctly', () => {
    const activities = [
      { id: 'c1', user_id: 'u3', action: 'a', timestamp: new Date(2023, 0, 1, 10, 0, 0) },
      { id: 'c2', user_id: 'u3', action: 'b', timestamp: new Date(2023, 0, 1, 10, 30, 0) }, // exactly 30 min -> same session
      { id: 'c3', user_id: 'u3', action: 'c', timestamp: new Date(2023, 0, 1, 11, 1, 0) } // 31 min -> new session
    ]
    const dashboard = new ActivityDashboard(activities as any)
    const summary = dashboard.getUserSummary('u3')
    expect(summary).not.toBeNull()
    expect(summary?.averageActionsPerSession).toBe(1.5) // 3 actions / 2 sessions
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns weighted score based on volume, diversity, frequency', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(35.76)
  })

  it('returns 0 for users without activity', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const score = dashboard.calculateEngagementScore('nope')
    expect(score).toBe(0)
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('groups by day and computes growth rates', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends.length).toBe(3)
    expect(trends[0]).toEqual({ period: '2023-01-01', count: 4, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2023-01-02', count: 1, growthRate: -75 })
    expect(trends[2]).toEqual({ period: '2023-01-03', count: 3, growthRate: 200 })
  })

  it('groups by hour with lexicographic sorting and growth rates', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const trends = dashboard.getActivityTrends('u1', 'hour')
    const expected = [
      { period: '2023-01-01 10:00', count: 3, growthRate: 0 },
      { period: '2023-01-01 11:00', count: 1, growthRate: -66.67 },
      { period: '2023-01-02 12:00', count: 1, growthRate: 0 },
      { period: '2023-01-03 12:00', count: 1, growthRate: 0 },
      { period: '2023-01-03 13:00', count: 1, growthRate: 0 },
      { period: '2023-01-03 14:00', count: 1, growthRate: 0 }
    ]
    expect(trends).toEqual(expected)
  })

  it('groups by week into a single period for the dataset', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(1)
    expect(trends[0].period).toBe('2023-W01')
    expect(trends[0].count).toBe(8)
    expect(trends[0].growthRate).toBe(0)
  })

  it('groups by month into a single period', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends.length).toBe(1)
    expect(trends[0]).toEqual({ period: '2023-01', count: 8, growthRate: 0 })
  })

  it('returns empty array for users with no activity', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const trends = dashboard.getActivityTrends('nobody', 'day')
    expect(trends).toEqual([])
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('filters by inclusive start and end dates for a specific user', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const start = new Date(2023, 0, 1, 10, 5, 0) // include
    const end = new Date(2023, 0, 1, 11, 0, 0) // include
    const results = dashboard.filterByDateRange('u1', start, end)
    const ids = results.map(r => r.id).sort()
    expect(ids).toEqual(['a2', 'a3', 'a4']) // 10:05, 10:10, 11:00
    // confirm u2 activity at same time is not included
    const u2Results = dashboard.filterByDateRange('u2', start, end)
    expect(u2Results.map(r => r.id)).toEqual(['b1'])
  })

  it('returns empty array when user has no activity in range', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const start = new Date(2024, 0, 1)
    const end = new Date(2024, 0, 2)
    const results = dashboard.filterByDateRange('u1', start, end)
    expect(results).toEqual([])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('aggregates counts, percentages, and occurrence dates, sorted by count desc', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const groups = dashboard.aggregateByAction('u1')
    // top two groups should be view then login
    expect(groups[0].action).toBe('view')
    expect(groups[0].count).toBe(4)
    expect(groups[0].percentage).toBe(50)
    expect(groups[0].firstOccurrence).toEqual(new Date(2023, 0, 1, 10, 5, 0))
    expect(groups[0].lastOccurrence).toEqual(new Date(2023, 0, 3, 14, 0, 0))

    expect(groups[1].action).toBe('login')
    expect(groups[1].count).toBe(2)
    expect(groups[1].percentage).toBe(25)
    expect(groups.find(g => g.action === 'click')?.count).toBe(1)
    expect(groups.find(g => g.action === 'click')?.percentage).toBe(12.5)
    expect(groups.find(g => g.action === 'logout')?.count).toBe(1)
    expect(groups.find(g => g.action === 'logout')?.percentage).toBe(12.5)
  })

  it('returns empty array for unknown user', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const groups = dashboard.aggregateByAction('missing')
    expect(groups).toEqual([])
  })
})

describe('ActivityDashboard.getTopActions_old', () => {
  it('returns action groups sorted by count with correct stats', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const top = dashboard.getTopActions_old('u1')
    expect(top.length).toBe(4)
    expect(top[0].action).toBe('view')
    expect(top[0].count).toBe(4)
    expect(top[0].percentage).toBe(50)
    expect(top[0].firstOccurrence).toEqual(new Date(2023, 0, 1, 10, 5, 0))
    expect(top[0].lastOccurrence).toEqual(new Date(2023, 0, 3, 14, 0, 0))
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('returns top N actions via aggregateByAction', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const top2 = dashboard.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('view')
    expect(top2[1].action).toBe('login')
  })

  it('returns all actions when limit exceeds groups', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const top10 = dashboard.getTopActions('u1', 10)
    expect(top10.length).toBe(4)
  })

  it('returns empty array for user without actions', () => {
    const dashboard = new ActivityDashboard(createDefaultActivities())
    const top = dashboard.getTopActions('nobody', 3)
    expect(top).toEqual([])
  })
})