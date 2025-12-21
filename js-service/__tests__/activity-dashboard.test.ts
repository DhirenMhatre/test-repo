import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

const act = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>) => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when no activities for the user', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.getUserSummary('u1')).toBeNull()
  })

  it('calculates totals, unique actions, actionsPerDay, mostFrequentAction, averageActionsPerSession', () => {
    const activities = [
      act('1', 'u1', 'click', new Date(2024, 0, 1, 9, 0, 0)),
      act('2', 'u1', 'scroll', new Date(2024, 0, 1, 9, 10, 0)),
      act('3', 'u1', 'click', new Date(2024, 0, 1, 9, 20, 0)),
      act('4', 'u1', 'hover', new Date(2024, 0, 2, 10, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')!
    expect(summary.totalActions).toBe(4)
    expect(summary.uniqueActions).toBe(3)
    expect(summary.actionsPerDay).toBe(2.00)
    expect(summary.mostFrequentAction).toBe('click')
    expect(summary.averageActionsPerSession).toBe(2.00)
  })

  it('mostFrequentAction respects insertion order on ties', () => {
    // First seen action is "B", then "A", each 2 times
    const activities = [
      act('1', 'u2', 'B', new Date(2024, 0, 1, 9, 0, 0)),
      act('2', 'u2', 'A', new Date(2024, 0, 1, 9, 5, 0)),
      act('3', 'u2', 'B', new Date(2024, 0, 1, 9, 10, 0)),
      act('4', 'u2', 'A', new Date(2024, 0, 1, 9, 15, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u2')!
    expect(summary.mostFrequentAction).toBe('B')
  })

  it('averageActionsPerSession uses 30 minute gap strictly greater than 30 to start new session', () => {
    const activities = [
      act('1', 'u3', 'x', new Date(2024, 0, 1, 9, 0, 0)),
      act('2', 'u3', 'x', new Date(2024, 0, 1, 9, 30, 0)), // exactly 30 min -> same session
      act('3', 'u3', 'x', new Date(2024, 0, 1, 10, 1, 0)) // 31 min -> new session
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u3')!
    expect(summary.averageActionsPerSession).toBe(1.5)
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters by inclusive date range and user', () => {
    const start = new Date(2024, 0, 1, 9, 0, 0)
    const middle = new Date(2024, 0, 1, 12, 0, 0)
    const end = new Date(2024, 0, 2, 9, 0, 0)
    const activities = [
      act('1', 'u1', 'a', start),
      act('2', 'u1', 'b', middle),
      act('3', 'u1', 'c', end),
      act('4', 'u2', 'a', middle) // different user
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.filterByDateRange('u1', start, end)
    expect(result.map(r => r.id)).toEqual(['1', '2', '3'])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.aggregateByAction('u1')).toEqual([])
  })

  it('aggregates counts, percentages, first and last occurrences, sorted by count desc', () => {
    const activities = [
      act('1', 'u1', 'click', new Date(2024, 0, 1, 8, 0, 0)),
      act('2', 'u1', 'click', new Date(2024, 0, 1, 9, 0, 0)),
      act('3', 'u1', 'click', new Date(2024, 0, 1, 10, 0, 0)),
      act('4', 'u1', 'scroll', new Date(2024, 0, 1, 11, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups.length).toBe(2)
    expect(groups[0].action).toBe('click')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(75.00)
    expect(groups[0].firstOccurrence.getTime()).toBe(new Date(2024, 0, 1, 8, 0, 0).getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(new Date(2024, 0, 1, 10, 0, 0).getTime())
    expect(groups[1].action).toBe('scroll')
    expect(groups[1].count).toBe(1)
    expect(groups[1].percentage).toBe(25.00)
  })
})

describe('ActivityDashboard - getTopActions_old', () => {
  it('returns all groups sorted by count, ignoring the limit parameter', () => {
    const activities = [
      act('1', 'u1', 'click', new Date(2024, 0, 1, 8, 0, 0)),
      act('2', 'u1', 'scroll', new Date(2024, 0, 1, 9, 0, 0)),
      act('3', 'u1', 'click', new Date(2024, 0, 1, 10, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const top = dashboard.getTopActions_old('u1', 1)
    expect(top.length).toBe(2)
    expect(top[0].action).toBe('click')
    expect(top[0].count).toBe(2)
    expect(top[1].action).toBe('scroll')
    expect(top[1].count).toBe(1)
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('returns limited top actions using aggregateByAction', () => {
    const activities = [
      act('1', 'u1', 'click', new Date(2024, 0, 1, 8, 0, 0)),
      act('2', 'u1', 'scroll', new Date(2024, 0, 1, 9, 0, 0)),
      act('3', 'u1', 'click', new Date(2024, 0, 1, 10, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const top1 = dashboard.getTopActions('u1', 1)
    expect(top1.length).toBe(1)
    expect(top1[0].action).toBe('click')
    const top2 = dashboard.getTopActions('u1', 2)
    expect(top2.map(t => t.action)).toEqual(['click', 'scroll'])
  })

  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.getTopActions('uX', 3)).toEqual([])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no summary', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('u1')).toBe(0)
  })

  it('caps scores at their maximums and rounds to 2 decimals', () => {
    // 100 actions in one day, 10 unique actions -> scores should max out: 30 + 30 + 40 = 100
    const acts: any[] = []
    for (let i = 0; i < 100; i++) {
      const action = `a${i % 10}`
      acts.push(act(String(i + 1), 'u1', action, new Date(2024, 0, 1, 0, i, 0)))
    }
    const dashboard = new ActivityDashboard(acts)
    expect(dashboard.calculateEngagementScore('u1')).toBe(100)
  })
})

describe('ActivityDashboard - getActivityTrends (day)', () => {
  it('returns empty array when no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.getActivityTrends('u1', 'day')).toEqual([])
  })

  it('groups by day with correct growth rates', () => {
    // Counts: 2024-01-01 -> 2, 2024-01-02 -> 4, 2024-01-03 -> 1
    const activities = [
      act('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0, 0)),
      act('2', 'u1', 'a', new Date(2024, 0, 1, 10, 0, 0)),
      act('3', 'u1', 'a', new Date(2024, 0, 2, 9, 0, 0)),
      act('4', 'u1', 'a', new Date(2024, 0, 2, 10, 0, 0)),
      act('5', 'u1', 'a', new Date(2024, 0, 2, 11, 0, 0)),
      act('6', 'u1', 'a', new Date(2024, 0, 2, 12, 0, 0)),
      act('7', 'u1', 'a', new Date(2024, 0, 3, 9, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends.length).toBe(3)
    expect(trends[0]).toEqual({ period: '2024-01-01', count: 2, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2024-01-02', count: 4, growthRate: 100 })
    expect(trends[2]).toEqual({ period: '2024-01-03', count: 1, growthRate: -75 })
  })
})

describe('ActivityDashboard - getActivityTrends (hour)', () => {
  it('groups by hour with lexicographic sorting producing chronological order', () => {
    const activities = [
      act('1', 'u1', 'a', new Date(2024, 0, 1, 23, 0, 0)),
      act('2', 'u1', 'a', new Date(2024, 0, 2, 0, 0, 0)),
      act('3', 'u1', 'a', new Date(2024, 0, 2, 0, 30, 0)),
      act('4', 'u1', 'a', new Date(2024, 0, 2, 1, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'hour')
    expect(trends.map(t => t.period)).toEqual([
      '2024-01-01 23:00',
      '2024-01-02 00:00',
      '2024-01-02 01:00'
    ])
    expect(trends.map(t => t.count)).toEqual([1, 2, 1])
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].growthRate).toBe(100)
    expect(trends[2].growthRate).toBe(-50)
  })
})

describe('ActivityDashboard - getActivityTrends (week)', () => {
  it('groups into week keys like YYYY-WNN using internal getWeekNumber', () => {
    const activities = [
      act('1', 'u1', 'a', new Date(2024, 0, 3, 9, 0, 0)), // 2024-W01
      act('2', 'u1', 'a', new Date(2024, 0, 5, 12, 0, 0))  // same week
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(1)
    expect(trends[0].period).toBe('2024-W01')
    expect(trends[0].count).toBe(2)
    expect(trends[0].growthRate).toBe(0)
  })
})

describe('ActivityDashboard - getActivityTrends (month)', () => {
  it('groups by month and calculates non-integer growth rates rounded to 2 decimals', () => {
    // Jan: 3 actions, Feb: 4 actions => growth 33.33%
    const activities = [
      act('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0, 0)),
      act('2', 'u1', 'a', new Date(2024, 0, 10, 10, 0, 0)),
      act('3', 'u1', 'a', new Date(2024, 0, 20, 11, 0, 0)),
      act('4', 'u1', 'a', new Date(2024, 1, 1, 9, 0, 0)),
      act('5', 'u1', 'a', new Date(2024, 1, 10, 10, 0, 0)),
      act('6', 'u1', 'a', new Date(2024, 1, 20, 11, 0, 0)),
      act('7', 'u1', 'a', new Date(2024, 1, 25, 12, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends.length).toBe(2)
    expect(trends[0]).toEqual({ period: '2024-01', count: 3, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2024-02', count: 4, growthRate: 33.33 })
  })
})