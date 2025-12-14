import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

const makeActivity = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>) => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when no activities exist for the user', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, most frequent, per-day, and avg actions per session', () => {
    const base = new Date(2023, 0, 1, 9, 0, 0)
    const activities = [
      makeActivity('1', 'u1', 'view', new Date(base.getTime() + 0 * 60_000)),
      makeActivity('2', 'u1', 'click', new Date(base.getTime() + 10 * 60_000)),
      makeActivity('3', 'u1', 'view', new Date(base.getTime() + 20 * 60_000)),
      makeActivity('4', 'u1', 'view', new Date(base.getTime() + 25 * 60_000)),
      // gap > 30 minutes -> new session
      makeActivity('5', 'u1', 'click', new Date(base.getTime() + 56 * 60_000)),
      makeActivity('6', 'u2', 'other', new Date(base.getTime() + 60 * 60_000))
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(5)
    expect(summary!.uniqueActions).toBe(2)
    expect(summary!.mostFrequentAction).toBe('view')
    // same day -> daysActive = 1 -> actionsPerDay = 5
    expect(summary!.actionsPerDay).toBe(5)
    // two sessions -> avg = 5/2 = 2.5
    expect(summary!.averageActionsPerSession).toBe(2.5)
  })

  it('mostFrequentAction preserves first-seen action on ties', () => {
    const base = new Date(2023, 0, 2, 12, 0, 0)
    const activities = [
      makeActivity('1', 'u1', 'B', new Date(base.getTime())),
      makeActivity('2', 'u1', 'A', new Date(base.getTime() + 1 * 60_000)),
      makeActivity('3', 'u1', 'B', new Date(base.getTime() + 2 * 60_000)),
      makeActivity('4', 'u1', 'A', new Date(base.getTime() + 3 * 60_000))
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    // Tie at 2-2, but B was encountered first, so remains most frequent
    expect(summary!.mostFrequentAction).toBe('B')
  })

  it('averageActionsPerSession does not split session at exactly 30 minutes gap', () => {
    const base = new Date(2023, 0, 3, 10, 0, 0)
    const activities = [
      makeActivity('1', 'u1', 'x', new Date(base.getTime() + 0 * 60_000)),
      makeActivity('2', 'u1', 'x', new Date(base.getTime() + 30 * 60_000)), // exactly 30 minutes -> same session
      makeActivity('3', 'u1', 'x', new Date(base.getTime() + 61 * 60_000))  // 31 minutes gap -> new session
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    // sessions: [0..30] = 1, then [61] = 1 more => 2 sessions; avg = 3/2 = 1.5
    expect(summary!.averageActionsPerSession).toBe(1.5)
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('groups by day with correct counts and growth rates', () => {
    const day1 = new Date(2023, 0, 1, 8, 0, 0)
    const day2 = new Date(2023, 0, 2, 9, 0, 0)
    const day3 = new Date(2023, 0, 3, 10, 0, 0)
    const acts = [
      makeActivity('1', 'uT', 'a', new Date(day1.getTime())),
      makeActivity('2', 'uT', 'b', new Date(day1.getTime() + 1 * 60_000)),
      makeActivity('3', 'uT', 'c', new Date(day2.getTime())),
      makeActivity('4', 'uT', 'a', new Date(day3.getTime())),
      makeActivity('5', 'uT', 'a', new Date(day3.getTime() + 1 * 60_000)),
      makeActivity('6', 'uT', 'a', new Date(day3.getTime() + 2 * 60_000)),
      makeActivity('7', 'other', 'x', new Date(day1.getTime()))
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('uT', 'day')
    expect(trends.length).toBe(3)
    expect(trends[0].period).toBe('2023-01-01')
    expect(trends[0].count).toBe(2)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].period).toBe('2023-01-02')
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50)
    expect(trends[2].period).toBe('2023-01-03')
    expect(trends[2].count).toBe(3)
    expect(trends[2].growthRate).toBe(200)
  })

  it('defaults to day grouping when periodType is omitted', () => {
    const d = new Date(2023, 0, 10, 12, 0, 0)
    const acts = [
      makeActivity('1', 'uT', 'a', d),
      makeActivity('2', 'uT', 'a', new Date(d.getTime() + 1 * 60_000))
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('uT')
    expect(trends.length).toBe(1)
    expect(trends[0].period).toBe('2023-01-10')
    expect(trends[0].count).toBe(2)
  })

  it('groups by hour with zero-padded hour keys', () => {
    const base = new Date(2023, 0, 1, 9, 0, 0)
    const acts = [
      makeActivity('1', 'uH', 'a', new Date(base.getTime())),
      makeActivity('2', 'uH', 'a', new Date(base.getTime() + 5 * 60_000)),
      makeActivity('3', 'uH', 'a', new Date(base.getTime() + 60 * 60_000)) // next hour
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('uH', 'hour')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-01-01 09:00')
    expect(trends[0].count).toBe(2)
    expect(trends[1].period).toBe('2023-01-01 10:00')
    expect(trends[1].count).toBe(1)
  })

  it('groups by week using Wxx format per implementation', () => {
    const d1 = new Date(2023, 0, 1, 12, 0, 0) // Jan 1, 2023
    const d2 = new Date(2023, 0, 8, 12, 0, 0) // Jan 8, 2023
    const acts = [
      makeActivity('1', 'uW', 'a', d1),
      makeActivity('2', 'uW', 'a', d2)
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('uW', 'week')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-W01')
    expect(trends[0].count).toBe(1)
    expect(trends[1].period).toBe('2023-W02')
    expect(trends[1].count).toBe(1)
  })

  it('groups by month with zero-padded month keys', () => {
    const jan = new Date(2023, 0, 15, 12, 0, 0)
    const feb = new Date(2023, 1, 1, 12, 0, 0)
    const acts = [
      makeActivity('1', 'uM', 'a', jan),
      makeActivity('2', 'uM', 'b', feb)
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('uM', 'month')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-01')
    expect(trends[0].count).toBe(1)
    expect(trends[1].period).toBe('2023-02')
    expect(trends[1].count).toBe(1)
  })

  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const trends = dash.getActivityTrends('unknown', 'day')
    expect(trends).toEqual([])
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('includes activities within inclusive date range', () => {
    const base = new Date(2023, 0, 5, 10, 0, 0)
    const acts = [
      makeActivity('1', 'uF', 'a', new Date(base.getTime() - 60 * 60_000)),
      makeActivity('2', 'uF', 'a', base),
      makeActivity('3', 'uF', 'a', new Date(base.getTime() + 60 * 60_000)),
      makeActivity('4', 'uF', 'a', new Date(base.getTime() + 2 * 60 * 60_000)),
      makeActivity('5', 'other', 'a', base)
    ]
    const dash = new ActivityDashboard(acts)
    const start = base
    const end = new Date(base.getTime() + 60 * 60_000)
    const filtered = dash.filterByDateRange('uF', start, end)
    expect(filtered.map(a => a.id)).toEqual(['2', '3'])
  })

  it('returns empty when no activities fall in the range', () => {
    const base = new Date(2023, 0, 5, 10, 0, 0)
    const acts = [
      makeActivity('1', 'uF', 'a', new Date(base.getTime() - 2 * 60 * 60_000)),
      makeActivity('2', 'uF', 'a', new Date(base.getTime() - 60 * 60_000))
    ]
    const dash = new ActivityDashboard(acts)
    const filtered = dash.filterByDateRange('uF', base, new Date(base.getTime() + 60 * 60_000))
    expect(filtered).toEqual([])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('aggregates counts, percentages and first/last occurrence, sorted by count desc', () => {
    const d1 = new Date(2023, 0, 1, 9, 0, 0)
    const d2 = new Date(2023, 0, 1, 9, 10, 0)
    const d3 = new Date(2023, 0, 2, 9, 0, 0)
    const d4 = new Date(2023, 0, 3, 9, 0, 0)
    const acts = [
      makeActivity('1', 'uA', 'a1', d1),
      makeActivity('2', 'uA', 'a1', d2),
      makeActivity('3', 'uA', 'a1', d3),
      makeActivity('4', 'uA', 'a2', d4),
      makeActivity('5', 'other', 'a1', d1)
    ]
    const dash = new ActivityDashboard(acts)
    const groups = dash.aggregateByAction('uA')
    expect(groups.length).toBe(2)
    // sorted by count desc: a1 first, a2 second
    const g1 = groups[0]
    const g2 = groups[1]
    expect(g1.action).toBe('a1')
    expect(g1.count).toBe(3)
    expect(g1.percentage).toBe(75)
    expect(g1.firstOccurrence.getTime()).toBe(d1.getTime())
    expect(g1.lastOccurrence.getTime()).toBe(d3.getTime())
    expect(g2.action).toBe('a2')
    expect(g2.count).toBe(1)
    expect(g2.percentage).toBe(25)
    expect(g2.firstOccurrence.getTime()).toBe(d4.getTime())
    expect(g2.lastOccurrence.getTime()).toBe(d4.getTime())
  })

  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    expect(dash.aggregateByAction('none')).toEqual([])
  })
})

describe('ActivityDashboard - getTopActions_old', () => {
  it('returns all groups and ignores limit parameter', () => {
    const d = new Date(2023, 0, 1, 12, 0, 0)
    const acts = [
      makeActivity('1', 'uO', 'x', d),
      makeActivity('2', 'uO', 'x', new Date(d.getTime() + 1 * 60_000)),
      makeActivity('3', 'uO', 'y', new Date(d.getTime() + 2 * 60_000))
    ]
    const dash = new ActivityDashboard(acts)
    const groups = dash.getTopActions_old('uO', 1)
    expect(groups.length).toBe(2) // not sliced
    expect(groups[0].action).toBe('x')
    expect(groups[0].count).toBe(2)
    expect(groups[1].action).toBe('y')
    expect(groups[1].count).toBe(1)
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('returns top N actions by count', () => {
    const d = new Date(2023, 0, 4, 10, 0, 0)
    const acts = [
      makeActivity('1', 'uT', 'X', d),
      makeActivity('2', 'uT', 'X', new Date(d.getTime() + 1 * 60_000)),
      makeActivity('3', 'uT', 'X', new Date(d.getTime() + 2 * 60_000)),
      makeActivity('4', 'uT', 'Y', new Date(d.getTime() + 3 * 60_000)),
      makeActivity('5', 'uT', 'Y', new Date(d.getTime() + 4 * 60_000)),
      makeActivity('6', 'uT', 'Z', new Date(d.getTime() + 5 * 60_000))
    ]
    const dash = new ActivityDashboard(acts)
    const top2 = dash.getTopActions('uT', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('X')
    expect(top2[0].count).toBe(3)
    expect(top2[1].action).toBe('Y')
    expect(top2[1].count).toBe(2)

    const top10 = dash.getTopActions('uT', 10)
    expect(top10.length).toBe(3)
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activity', () => {
    const dash = new ActivityDashboard([])
    const score = dash.calculateEngagementScore('none')
    expect(score).toBe(0)
  })

  it('computes score using volume, diversity, and frequency caps', () => {
    const base = new Date(2023, 0, 6, 9, 0, 0)
    const acts: any[] = []
    // 50 actions, 5 unique types, all on the same day to maximize actionsPerDay
    const actions = ['A', 'B', 'C', 'D', 'E']
    for (let i = 0; i < 50; i++) {
      const act = actions[i % actions.length]
      acts.push(makeActivity(`id-${i}`, 'uS', act, new Date(base.getTime() + i * 60_000)))
    }
    const dash = new ActivityDashboard(acts)
    const score = dash.calculateEngagementScore('uS')
    // volume: min(50/100,1)*30 = 15
    // diversity: min(5/10,1)*30 = 15
    // frequency: actionsPerDay=50 -> min(50/5,1)*40 = 40
    // total = 70.00
    expect(score).toBe(70)
  })
})

describe('ActivityDashboard - immutability and internal state', () => {
  it('does not mutate original activities array order when performing aggregations', () => {
    const base = new Date(2023, 0, 7, 8, 0, 0)
    const original = [
      makeActivity('1', 'uI', 'a', new Date(base.getTime() + 0 * 60_000)),
      makeActivity('2', 'uI', 'b', new Date(base.getTime() + 1 * 60_000)),
      makeActivity('3', 'uI', 'a', new Date(base.getTime() + 2 * 60_000))
    ]
    const dashboard = new ActivityDashboard(original)
    const beforeOrder = original.map(a => a.id)
    // Call multiple methods that may sort copies internally
    dashboard.getUserSummary('uI')
    dashboard.aggregateByAction('uI')
    dashboard.getActivityTrends('uI', 'day')
    const afterOrder = original.map(a => a.id)
    expect(afterOrder).toEqual(beforeOrder)
  })
})