import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function d(iso: string) {
  return new Date(iso)
}

const user1 = 'u1'
const user2 = 'u2'

function buildActivities() {
  return [
    // user1
    { id: 'a1', user_id: user1, action: 'login', timestamp: d('2024-01-01T10:00:00Z') },
    { id: 'a2', user_id: user1, action: 'view', timestamp: d('2024-01-01T10:10:00Z') },
    { id: 'a3', user_id: user1, action: 'click', timestamp: d('2024-01-01T10:45:00Z') },
    { id: 'a4', user_id: user1, action: 'view', timestamp: d('2024-01-01T12:00:00Z') },
    { id: 'a5', user_id: user1, action: 'login', timestamp: d('2024-01-02T09:00:00Z') },
    { id: 'a6', user_id: user1, action: 'view', timestamp: d('2024-01-02T09:05:00Z') },
    { id: 'a7', user_id: user1, action: 'purchase', timestamp: d('2024-01-08T15:00:00Z') },
    { id: 'a8', user_id: user1, action: 'view', timestamp: d('2024-02-01T09:00:00Z') },
    // user2 (noise and for some tests)
    { id: 'b1', user_id: user2, action: 'login', timestamp: d('2024-01-01T00:00:00Z') },
    { id: 'b2', user_id: user2, action: 'view', timestamp: d('2024-01-01T01:00:00Z') }
  ]
}

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const res = dashboard.getUserSummary('missing-user')
    expect(res).toBeNull()
  })

  it('computes correct summary stats for user activities', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const summary = dashboard.getUserSummary(user1)
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(8)
    expect(summary!.uniqueActions).toBe(4)
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.actionsPerDay).toBeCloseTo(0.26, 2)
    expect(summary!.averageActionsPerSession).toBeCloseTo(1.33, 2)
  })

  it('session boundary exactly 30 minutes does not create new session', () => {
    const acts = [
      { id: 'c1', user_id: 'u3', action: 'view', timestamp: d('2024-03-01T00:00:00Z') },
      { id: 'c2', user_id: 'u3', action: 'view', timestamp: d('2024-03-01T00:30:00Z') }
    ]
    const dashboard = new ActivityDashboard(acts as any)
    const summary = dashboard.getUserSummary('u3')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(2)
    expect(summary!.averageActionsPerSession).toBe(2) // one session, two actions
    expect(summary!.actionsPerDay).toBe(2) // same day => daysActive = 1
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const res = dashboard.getActivityTrends('nope', 'day')
    expect(res).toEqual([])
  })

  it('groups by day with correct counts and growth rates', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const trends = dashboard.getActivityTrends(user1, 'day')
    expect(trends.map(t => t.period)).toEqual(['2024-01-01', '2024-01-02', '2024-01-08', '2024-02-01'])
    expect(trends.map(t => t.count)).toEqual([4, 2, 1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50, -50, 0])
  })

  it('groups by hour with formatted period and proper growth', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const trends = dashboard.getActivityTrends(user1, 'hour')
    expect(trends[0]).toEqual({ period: '2024-01-01 10:00', count: 3, growthRate: 0 })
    expect(trends[1].period).toBe('2024-01-01 12:00')
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBeCloseTo(-66.67, 2)
    expect(trends[2]).toEqual({ period: '2024-01-02 09:00', count: 2, growthRate: 100 })
  })

  it('groups by week with ISO-like labels computed by class method', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const trends = dashboard.getActivityTrends(user1, 'week')
    expect(trends.map(t => t.period)).toEqual(['2024-W01', '2024-W02', '2024-W05'])
    expect(trends.map(t => t.count)).toEqual([6, 1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -83.33, 0])
  })

  it('groups by month with correct growth rates', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const trends = dashboard.getActivityTrends(user1, 'month')
    expect(trends.map(t => t.period)).toEqual(['2024-01', '2024-02'])
    expect(trends.map(t => t.count)).toEqual([7, 1])
    expect(trends[1].growthRate).toBeCloseTo(-85.71, 2)
  })

  it('single period trend has zero growth rate', () => {
    const acts = [{ id: 'x1', user_id: 'single', action: 'view', timestamp: d('2024-01-10T00:00:00Z') }]
    const dashboard = new ActivityDashboard(acts as any)
    const trends = dashboard.getActivityTrends('single', 'day')
    expect(trends).toHaveLength(1)
    expect(trends[0].growthRate).toBe(0)
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('filters inclusively by start and end dates for a specific user', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const start = d('2024-01-01T10:10:00Z')
    const end = d('2024-01-02T09:00:00Z')
    const res = dashboard.filterByDateRange(user1, start, end)
    const ids = res.map(a => a.id)
    expect(ids).toEqual(['a2', 'a3', 'a4', 'a5'])
  })

  it('returns empty when no activities fall into range for user', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const res = dashboard.filterByDateRange(user1, d('2025-01-01T00:00:00Z'), d('2025-01-02T00:00:00Z'))
    expect(res).toEqual([])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('aggregates counts, percentages, and occurrence timestamps sorted by count desc', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const groups = dashboard.aggregateByAction(user1)
    expect(groups.map(g => g.action)).toEqual(['view', 'login', expect.any(String), expect.any(String)])
    const viewGroup = groups.find(g => g.action === 'view')!
    expect(viewGroup.count).toBe(4)
    expect(viewGroup.percentage).toBe(50)
    expect(viewGroup.firstOccurrence.getTime()).toBe(d('2024-01-01T10:10:00Z').getTime())
    expect(viewGroup.lastOccurrence.getTime()).toBe(d('2024-02-01T09:00:00Z').getTime())
    const loginGroup = groups.find(g => g.action === 'login')!
    expect(loginGroup.count).toBe(2)
    expect(loginGroup.percentage).toBe(25)
    expect(groups.find(g => g.action === 'click')!.percentage).toBe(12.5)
  })

  it('returns empty list for user with no activities', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    expect(dashboard.aggregateByAction('zzz')).toEqual([])
  })
})

describe('ActivityDashboard.getTopActions_old', () => {
  it('returns all actions sorted by count, ignoring the limit parameter', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const res = dashboard.getTopActions_old(user1, 2)
    expect(res.length).toBe(4)
    expect(res[0].action).toBe('view')
    expect(res[0].count).toBe(4)
    expect(res[1].action).toBe('login')
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('returns only limited number of top actions', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const top2 = dashboard.getTopActions(user1, 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('view')
    expect(top2[1].action).toBe('login')
  })

  it('limit greater than available returns all groups', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const top10 = dashboard.getTopActions(user1, 10)
    expect(top10.length).toBe(4)
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 for users with no activity', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    expect(dashboard.calculateEngagementScore('nope')).toBe(0)
  })

  it('calculates score based on volume, diversity, and frequency with rounding', () => {
    const dashboard = new ActivityDashboard(buildActivities())
    const score = dashboard.calculateEngagementScore(user1)
    expect(score).toBeCloseTo(16.48, 2)
  })
})