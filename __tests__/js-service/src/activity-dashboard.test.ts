import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../../../js-service/src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function act(id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>) {
  return { id, user_id, action, timestamp: date, metadata }
}

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([
      act('1', 'u2', 'view', new Date(2024, 0, 1, 10, 0)),
    ])
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, most frequent, actions per day and average per session', () => {
    const activities = [
      act('1', 'u1', 'view', new Date(2024, 0, 1, 10, 0)),
      act('2', 'u1', 'click', new Date(2024, 0, 1, 10, 20)),
      act('3', 'u1', 'view', new Date(2024, 0, 1, 10, 25)),
      // gap > 30 minutes => new session
      act('4', 'u1', 'view', new Date(2024, 0, 1, 11, 0)),
      act('5', 'u1', 'comment', new Date(2024, 0, 1, 11, 5)),
      // unrelated other user
      act('6', 'u2', 'view', new Date(2024, 0, 1, 11, 10)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(5)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.actionsPerDay).toBe(5) // all within same day
    expect(summary!.averageActionsPerSession).toBe(2.5) // 5 actions across 2 sessions
  })

  it('does not start a new session when gap is exactly 30 minutes', () => {
    const activities = [
      act('1', 'u1', 'view', new Date(2024, 0, 1, 10, 0)),
      act('2', 'u1', 'click', new Date(2024, 0, 1, 10, 30)), // exactly 30 minutes
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(2) // one session
  })

  it('rounds actionsPerDay to two decimals based on first and last activity timestamps', () => {
    // 7 actions over a span slightly over 2 days -> ceil to 3 days -> 7/3 = 2.33
    const acts = [
      act('1', 'u1', 'view', new Date(2024, 0, 1, 8, 0)),
      act('2', 'u1', 'view', new Date(2024, 0, 1, 9, 0)),
      act('3', 'u1', 'view', new Date(2024, 0, 2, 9, 0)),
      act('4', 'u1', 'click', new Date(2024, 0, 2, 10, 0)),
      act('5', 'u1', 'comment', new Date(2024, 0, 2, 11, 0)),
      act('6', 'u1', 'view', new Date(2024, 0, 3, 9, 10)), // makes span > 2 days
      act('7', 'u1', 'view', new Date(2024, 0, 3, 9, 15)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(7)
    expect(summary!.actionsPerDay).toBe(2.33)
  })

  it('selects the earliest encountered action on ties for most frequent', () => {
    const acts = [
      act('1', 'u1', 'view', new Date(2024, 0, 1, 9, 0)), // first encountered
      act('2', 'u1', 'click', new Date(2024, 0, 1, 9, 5)),
      act('3', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
      act('4', 'u1', 'click', new Date(2024, 0, 1, 9, 15)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.mostFrequentAction).toBe('view') // tie with click, but 'view' first encountered
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('groups by day and computes growth rates', () => {
    const acts = [
      act('1', 'u1', 'view', new Date(2024, 0, 1, 9, 0)), // 2024-01-01
      act('2', 'u1', 'click', new Date(2024, 0, 2, 9, 0)), // 2024-01-02
      act('3', 'u1', 'view', new Date(2024, 0, 2, 10, 0)),
      act('4', 'u1', 'comment', new Date(2024, 0, 2, 11, 0)),
      act('5', 'u2', 'view', new Date(2024, 0, 1, 9, 0)), // other user, ignored
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends).toHaveLength(2)
    expect(trends[0].period).toBe('2024-01-01')
    expect(trends[0].count).toBe(1)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].period).toBe('2024-01-02')
    expect(trends[1].count).toBe(3)
    expect(trends[1].growthRate).toBe(200)
  })

  it('groups by hour and sorts periods chronologically with correct growth rate', () => {
    const base = new Date(2024, 0, 1)
    const acts = [
      act('1', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
      act('2', 'u1', 'click', new Date(2024, 0, 1, 9, 50)),
      act('3', 'u1', 'view', new Date(2024, 0, 1, 10, 5)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends('u1', 'hour')
    expect(trends.map(t => t.period)).toEqual(['2024-01-01 09:00', '2024-01-01 10:00'])
    expect(trends[0].count).toBe(2)
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50)
  })

  it('groups by week using custom week number and sorts periods', () => {
    const acts = [
      act('1', 'u1', 'view', new Date(2024, 0, 1, 10, 0)), // 2024-W01
      act('2', 'u1', 'click', new Date(2024, 0, 8, 12, 0)), // 2024-W02
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends.map(t => t.period)).toEqual(['2024-W01', '2024-W02'])
    expect(trends.map(t => t.count)).toEqual([1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, 0])
  })

  it('groups by month and counts per month', () => {
    const acts = [
      act('1', 'u1', 'view', new Date(2024, 0, 15, 10, 0)), // Jan
      act('2', 'u1', 'click', new Date(2024, 1, 1, 9, 0)), // Feb
      act('3', 'u1', 'comment', new Date(2024, 1, 2, 11, 0)), // Feb
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends).toHaveLength(2)
    expect(trends[0].period).toBe('2024-01')
    expect(trends[0].count).toBe(1)
    expect(trends[1].period).toBe('2024-02')
    expect(trends[1].count).toBe(2)
  })

  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([
      act('1', 'u2', 'view', new Date(2024, 0, 1, 10, 0)),
    ])
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters by inclusive date range boundaries', () => {
    const acts = [
      act('1', 'u1', 'view', new Date(2024, 0, 1, 12, 0)),
      act('2', 'u1', 'click', new Date(2024, 0, 2, 12, 0)),
      act('3', 'u1', 'comment', new Date(2024, 0, 3, 12, 0)),
      act('4', 'u2', 'view', new Date(2024, 0, 2, 12, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const start = new Date(2024, 0, 2, 0, 0, 0)
    const end = new Date(2024, 0, 3, 23, 59, 59)
    const filtered = dashboard.filterByDateRange('u1', start, end)
    expect(filtered.map(a => a.id)).toEqual(['2', '3'])
  })

  it('returns empty when start is after end', () => {
    const acts = [
      act('1', 'u1', 'view', new Date(2024, 0, 1, 12, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const filtered = dashboard.filterByDateRange('u1', new Date(2024, 0, 2), new Date(2024, 0, 1))
    expect(filtered).toEqual([])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('aggregates counts, percentages, and occurrence dates sorted by count', () => {
    const v1 = new Date(2024, 0, 1, 10, 0)
    const v2 = new Date(2024, 0, 1, 12, 0)
    const v3 = new Date(2024, 0, 1, 13, 0)
    const c1 = new Date(2024, 0, 1, 11, 0)
    const m1 = new Date(2024, 0, 1, 11, 5)

    const acts = [
      act('1', 'u1', 'view', v1),
      act('2', 'u1', 'click', c1),
      act('3', 'u1', 'view', v2),
      act('4', 'u1', 'comment', m1),
      act('5', 'u1', 'view', v3),
    ]
    const dashboard = new ActivityDashboard(acts)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups.map(g => g.action)).toEqual(['view', 'click', 'comment'])
    expect(groups[0].count).toBe(3)
    expect(groups[1].count).toBe(1)
    expect(groups[2].count).toBe(1)
    expect(groups[0].percentage).toBeCloseTo(60.0, 2)
    expect(groups[1].percentage).toBeCloseTo(20.0, 2)
    expect(groups[2].percentage).toBeCloseTo(20.0, 2)
    expect(groups[0].firstOccurrence.getTime()).toBe(v1.getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(v3.getTime())
  })

  it('calculates percentages with two-decimal rounding for uneven distributions', () => {
    const acts = [
      act('1', 'u1', 'a', new Date(2024, 0, 1, 10, 0)),
      act('2', 'u1', 'b', new Date(2024, 0, 1, 11, 0)),
      act('3', 'u1', 'b', new Date(2024, 0, 1, 12, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const groups = dashboard.aggregateByAction('u1')
    const a = groups.find(g => g.action === 'b')!
    const b = groups.find(g => g.action === 'a')!
    expect(a.percentage).toBeCloseTo(66.67, 2)
    expect(b.percentage).toBeCloseTo(33.33, 2)
  })

  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([
      act('1', 'u2', 'view', new Date(2024, 0, 1, 10, 0)),
    ])
    const groups = dashboard.aggregateByAction('u1')
    expect(groups).toEqual([])
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('returns all actions when fewer than default limit', () => {
    const acts = [
      act('1', 'u1', 'view', new Date(2024, 0, 1, 10, 0)),
      act('2', 'u1', 'click', new Date(2024, 0, 1, 11, 0)),
      act('3', 'u1', 'comment', new Date(2024, 0, 1, 12, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const top = dashboard.getTopActions('u1')
    expect(top).toHaveLength(3)
    expect(top.map(t => t.action).sort()).toEqual(['click', 'comment', 'view'].sort())
  })

  it('respects the provided limit and preserves aggregate ordering', () => {
    const acts = [
      act('1', 'u1', 'a', new Date(2024, 0, 1, 10, 0)),
      act('2', 'u1', 'b', new Date(2024, 0, 1, 11, 0)),
      act('3', 'u1', 'b', new Date(2024, 0, 1, 12, 0)),
      act('4', 'u1', 'c', new Date(2024, 0, 1, 13, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const top = dashboard.getTopActions('u1', 2)
    expect(top.map(t => t.action)).toEqual(['b', 'a']) // 'b' has 2 > 'a' has 1 > 'c' has 1 (tie broken by insertion order from aggregate)
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(0)
  })

  it('saturates all components to yield 100.00 score', () => {
    const acts = []
    // 100 actions, 10 unique action types, all in the same day
    for (let i = 0; i < 100; i++) {
      const actionType = `a${i % 10}`
      acts.push(act(String(i + 1), 'u1', actionType, new Date(2024, 0, 1, 0, i % 60, 0)))
    }
    const dashboard = new ActivityDashboard(acts)
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(100)
  })

  it('computes a fractional score with correct rounding', () => {
    const acts = []
    // totalActions = 20, uniqueActions = 4, span ~10 days for actionsPerDay = 2
    for (let i = 0; i < 20; i++) {
      const d = new Date(2024, 0, 1 + Math.floor((i * 10) / 19), 10, 0)
      const actionType = ['a', 'b', 'c', 'd'][i % 4]
      acts.push(act(String(i + 1), 'u1', actionType, d))
    }
    // Ensure first and last cover at least 10 days difference
    acts[0] = act('start', 'u1', 'a', new Date(2024, 0, 1, 9, 0))
    acts[acts.length - 1] = act('end', 'u1', 'b', new Date(2024, 0, 11, 18, 0))
    const dashboard = new ActivityDashboard(acts)
    const score = dashboard.calculateEngagementScore('u1')
    // volume = 20/100*30 = 6
    // diversity = 4/10*30 = 12
    // frequency = 2/5*40 = 16
    // total = 34
    expect(score).toBe(34)
  })
})