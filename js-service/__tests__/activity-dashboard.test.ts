import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function createBaselineActivities() {
  const t0 = new Date(2023, 0, 1, 9, 0, 0)
  const t1 = new Date(2023, 0, 1, 9, 15, 0)
  const t2 = new Date(2023, 0, 1, 10, 0, 0)
  const t3 = new Date(2023, 0, 2, 11, 0, 0)
  const t4 = new Date(2023, 0, 3, 12, 0, 0)
  const t5 = new Date(2023, 0, 3, 12, 20, 0)
  const t6 = new Date(2023, 0, 5, 8, 0, 0)

  const activities = [
    { id: 'a0', user_id: 'u1', action: 'view', timestamp: t0 },
    { id: 'a1', user_id: 'u1', action: 'click', timestamp: t1 },
    { id: 'a2', user_id: 'u1', action: 'view', timestamp: t2 },
    { id: 'a3', user_id: 'u1', action: 'purchase', timestamp: t3 },
    { id: 'a4', user_id: 'u1', action: 'view', timestamp: t4 },
    { id: 'a5', user_id: 'u1', action: 'click', timestamp: t5 },
    { id: 'a6', user_id: 'u1', action: 'click', timestamp: t6 },
    // another user to ensure filtering by user works
    { id: 'b0', user_id: 'u2', action: 'view', timestamp: new Date(2023, 0, 1, 9, 0, 0) }
  ]
  return { activities, t0, t1, t2, t3, t4, t5, t6 }
}

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    expect(dash.getUserSummary('nope')).toBeNull()
  })

  it('computes total, unique, actionsPerDay, mostFrequentAction, averageActionsPerSession', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(7)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.actionsPerDay).toBe(1.75) // 7 actions over 4 days
    expect(summary!.mostFrequentAction).toBe('view') // tie between view and click, view seen first
    expect(summary!.averageActionsPerSession).toBe(1.4) // 7 actions over 5 sessions
  })

  it('resolves tie for most frequent action by first appeared action', () => {
    const t0 = new Date(2023, 0, 1, 9, 0, 0)
    const t1 = new Date(2023, 0, 1, 9, 10, 0)
    const t2 = new Date(2023, 0, 1, 9, 20, 0)
    const t3 = new Date(2023, 0, 1, 9, 30, 0)
    const acts = [
      { id: '1', user_id: 'u', action: 'alpha', timestamp: t0 },
      { id: '2', user_id: 'u', action: 'beta', timestamp: t1 },
      { id: '3', user_id: 'u', action: 'alpha', timestamp: t2 },
      { id: '4', user_id: 'u', action: 'beta', timestamp: t3 }
    ]
    const dash = new ActivityDashboard(acts as any)
    const summary = dash.getUserSummary('u')
    expect(summary).not.toBeNull()
    expect(summary!.mostFrequentAction).toBe('alpha')
  })

  it('calculates average actions per session with 30-minute threshold (boundary conditions)', () => {
    const base = new Date(2023, 0, 1, 9, 0, 0)
    const a = { id: '1', user_id: 'u', action: 'x', timestamp: new Date(base) }
    const b = { id: '2', user_id: 'u', action: 'x', timestamp: new Date(2023, 0, 1, 9, 30, 0) } // exactly 30 -> same session
    const c = { id: '3', user_id: 'u', action: 'x', timestamp: new Date(2023, 0, 1, 10, 31, 0) } // >30 -> new session
    const dash = new ActivityDashboard([a, b, c] as any)
    const summary = dash.getUserSummary('u')
    expect(summary).not.toBeNull()
    // First two are same session, third is another -> 2 sessions -> 3/2 = 1.5
    expect(summary!.averageActionsPerSession).toBe(1.5)
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    expect(dash.getActivityTrends('x')).toEqual([])
  })

  it('groups by day with correct growth rates', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'day')
    // Expect periods: 2023-01-01 (3), 2023-01-02 (1), 2023-01-03 (2), 2023-01-05 (1)
    expect(trends.map(t => t.period)).toEqual(['2023-01-01', '2023-01-02', '2023-01-03', '2023-01-05'])
    expect(trends.map(t => t.count)).toEqual([3, 1, 2, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -66.67, 100.0, -50.0])
  })

  it('groups by hour with correct ordering', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'hour')
    const periods = trends.map(t => t.period)
    expect(periods).toEqual([
      '2023-01-01 09:00',
      '2023-01-01 10:00',
      '2023-01-02 11:00',
      '2023-01-03 12:00',
      '2023-01-05 08:00'
    ])
    expect(trends.map(t => t.count)).toEqual([2, 1, 1, 2, 1])
    // Check first and last growth rates basic properties
    expect(trends[0].growthRate).toBe(0)
    expect(typeof trends[1].growthRate).toBe('number')
  })

  it('groups by month produces single entry when all in same month', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'month')
    expect(trends.length).toBe(1)
    expect(trends[0].period).toBe('2023-01')
    expect(trends[0].count).toBe(7)
    expect(trends[0].growthRate).toBe(0)
  })

  it('groups by week produces expected week key', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(1)
    expect(trends[0].period).toBe('2023-W01')
    expect(trends[0].count).toBe(7)
    expect(trends[0].growthRate).toBe(0)
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters inclusively within start and end dates', () => {
    const { activities, t0, t4 } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    const start = t0
    const end = t4 // inclusive: should include t4 at exactly 12:00
    const result = dash.filterByDateRange('u1', start, end)
    // Expect to include t0, t1, t2, t3, t4 (5 total), exclude t5 and t6
    expect(result.length).toBe(5)
    expect(result.every(a => a.user_id === 'u1')).toBe(true)
    const ids = result.map(r => r.id).sort()
    expect(ids).toEqual(['a0', 'a1', 'a2', 'a3', 'a4'])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('aggregates counts, percentages, and first/last occurrence, sorted by count', () => {
    const { activities, t0, t4, t1, t6, t3 } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    const groups = dash.aggregateByAction('u1')
    expect(groups.length).toBe(3)
    // Order: view(3), click(3), purchase(1) - tie resolved by first seen (view before click)
    expect(groups[0].action).toBe('view')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(42.86)
    expect(groups[0].firstOccurrence.getTime()).toBe(t0.getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(t4.getTime())

    expect(groups[1].action).toBe('click')
    expect(groups[1].count).toBe(3)
    expect(groups[1].percentage).toBe(42.86)
    expect(groups[1].firstOccurrence.getTime()).toBe(t1.getTime())
    expect(groups[1].lastOccurrence.getTime()).toBe(t6.getTime())

    expect(groups[2].action).toBe('purchase')
    expect(groups[2].count).toBe(1)
    expect(groups[2].percentage).toBe(14.29)
    expect(groups[2].firstOccurrence.getTime()).toBe(t3.getTime())
    expect(groups[2].lastOccurrence.getTime()).toBe(t3.getTime())
  })

  it('returns empty array when user has no activities', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    expect(dash.aggregateByAction('no-such-user')).toEqual([])
  })
})

describe('ActivityDashboard - getTopActions and getTopActions_old', () => {
  it('getTopActions returns top N aggregated actions', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    const top2 = dash.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('view')
    expect(top2[1].action).toBe('click')
  })

  it('getTopActions default limit returns available actions when fewer than limit', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    const top = dash.getTopActions('u1') // default 5
    expect(top.length).toBe(3)
    expect(top.map(t => t.action)).toEqual(['view', 'click', 'purchase'])
  })

  it('getTopActions returns empty list for user with no actions', () => {
    const dash = new ActivityDashboard([])
    expect(dash.getTopActions('u1', 3)).toEqual([])
  })

  it('getTopActions_old ignores limit and returns all groups', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    const all = dash.getTopActions_old('u1', 1)
    expect(all.length).toBe(3) // not sliced
    expect(all.map(a => a.action)).toEqual(['view', 'click', 'purchase'])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activities', () => {
    const dash = new ActivityDashboard([])
    expect(dash.calculateEngagementScore('ghost')).toBe(0)
  })

  it('calculates engagement score based on summary values', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    // For baseline: volume 2.1, diversity 9, frequency 14 -> total 25.1
    expect(dash.calculateEngagementScore('u1')).toBe(25.1)
  })

  it('caps engagement components at their maximums and total at 100', () => {
    // Create 120 actions on the same day across 12 unique actions for user max
    const date = new Date(2023, 0, 1, 9, 0, 0)
    const many: any[] = []
    for (let i = 0; i < 120; i++) {
      many.push({
        id: `m${i}`,
        user_id: 'max',
        action: `action${i % 12}`,
        timestamp: new Date(2023, 0, 1, 9, i % 60, 0)
      })
    }
    const dash = new ActivityDashboard(many)
    const score = dash.calculateEngagementScore('max')
    expect(score).toBe(100)
  })
})

describe('ActivityDashboard - other edge cases', () => {
  it('getActivityTrends returns [] for unknown user with existing dataset', () => {
    const { activities } = createBaselineActivities()
    const dash = new ActivityDashboard(activities)
    expect(dash.getActivityTrends('unknown', 'day')).toEqual([])
  })
})