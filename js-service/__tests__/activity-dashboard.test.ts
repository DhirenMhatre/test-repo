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
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, most frequent, actionsPerDay and averageActionsPerSession (with >30 min gap)', () => {
    const u = 'u1'
    const base = new Date(2023, 0, 1, 10, 0, 0)
    const activities = [
      makeActivity('a1', u, 'A', new Date(base.getTime() + 0 * 60000)),
      makeActivity('a2', u, 'B', new Date(base.getTime() + 15 * 60000)),
      makeActivity('a3', u, 'A', new Date(base.getTime() + 45 * 60000)),
      makeActivity('a4', u, 'C', new Date(base.getTime() + 80 * 60000)) // 35 minutes after previous => new session
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary(u)
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(4)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.mostFrequentAction).toBe('A')
    expect(summary!.actionsPerDay).toBe(4) // same day => daysActive = 1
    expect(summary!.averageActionsPerSession).toBe(2) // 4 actions over 2 sessions
  })

  it('calculates actionsPerDay across multiple days with ceiling and two decimals', () => {
    const u = 'u2'
    const a1 = makeActivity('b1', u, 'view', new Date(2023, 0, 1, 10, 0, 0))
    const a2 = makeActivity('b2', u, 'click', new Date(2023, 0, 2, 12, 0, 0))
    const a3 = makeActivity('b3', u, 'view', new Date(2023, 0, 3, 10, 0, 0)) // diff 48h => daysActive = 2
    const dashboard = new ActivityDashboard([a1, a2, a3])
    const summary = dashboard.getUserSummary(u)
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    expect(summary!.actionsPerDay).toBe(1.5)
  })

  it('does not start a new session when gap is exactly 30 minutes', () => {
    const u = 'u3'
    const t0 = new Date(2023, 0, 1, 9, 0, 0)
    const a1 = makeActivity('c1', u, 'x', new Date(t0.getTime()))
    const a2 = makeActivity('c2', u, 'y', new Date(t0.getTime() + 30 * 60000)) // exactly 30min
    const dashboard = new ActivityDashboard([a1, a2])
    const summary = dashboard.getUserSummary(u)
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(2) // same session
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const trends = dashboard.getActivityTrends('uX', 'day')
    expect(trends).toEqual([])
  })

  it('groups by day and computes growthRate between consecutive periods', () => {
    const u = 'u1'
    const d1 = new Date(2023, 0, 1, 10, 0, 0)
    const d2 = new Date(2023, 0, 2, 10, 0, 0)
    const d3 = new Date(2023, 0, 3, 10, 0, 0)
    const activities = [
      makeActivity('t1', u, 'A', new Date(d1.getTime())),
      makeActivity('t2', u, 'B', new Date(d1.getTime() + 60 * 60000)),
      makeActivity('t3', u, 'C', d2),
      makeActivity('t4', u, 'A', d3),
      makeActivity('t5', u, 'A', new Date(d3.getTime() + 10 * 60000)),
      makeActivity('t6', u, 'A', new Date(d3.getTime() + 20 * 60000))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends(u, 'day')
    expect(trends.map(t => t.period)).toEqual(['2023-01-01', '2023-01-02', '2023-01-03'])
    expect(trends.map(t => t.count)).toEqual([2, 1, 3])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50, 200])
  })

  it('groups by hour and merges events within the same hour', () => {
    const u = 'uH'
    const base = new Date(2023, 0, 1, 10, 0, 0)
    const activities = [
      makeActivity('h1', u, 'A', new Date(base.getTime() + 0)),
      makeActivity('h2', u, 'B', new Date(base.getTime() + 30 * 60000)), // same hour bucket
      makeActivity('h3', u, 'C', new Date(base.getTime() + 60 * 60000)) // next hour
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends(u, 'hour')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-01-01 10:00')
    expect(trends[0].count).toBe(2)
    expect(trends[1].period).toBe('2023-01-01 11:00')
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50)
  })

  it('groups by week using week key and computes growth', () => {
    const u = 'uW'
    const w1d1 = new Date(2023, 0, 2, 9, 0, 0) // 2023-01-02
    const w1d2 = new Date(2023, 0, 3, 9, 0, 0) // same week key
    const w2d1 = new Date(2023, 0, 9, 9, 0, 0) // next week
    const activities = [
      makeActivity('w1', u, 'A', w1d1),
      makeActivity('w2', u, 'B', w1d2),
      makeActivity('w3', u, 'C', w2d1)
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends(u, 'week')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-W01')
    expect(trends[0].count).toBe(2)
    expect(trends[1].period).toBe('2023-W02')
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50)
  })

  it('groups by month and sorts chronologically by period string', () => {
    const u = 'uM'
    const jan = new Date(2023, 0, 15, 10, 0, 0)
    const feb = new Date(2023, 1, 1, 10, 0, 0)
    const activities = [
      makeActivity('m1', u, 'A', jan),
      makeActivity('m2', u, 'B', feb),
      makeActivity('m3', u, 'C', feb)
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends(u, 'month')
    expect(trends.map(t => t.period)).toEqual(['2023-01', '2023-02'])
    expect(trends.map(t => t.count)).toEqual([1, 2])
    expect(trends[1].growthRate).toBe(100) // from 1 to 2 = +100%
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters by inclusive date range', () => {
    const u = 'uF'
    const t1 = new Date(2023, 0, 1, 10, 0, 0)
    const t2 = new Date(2023, 0, 1, 11, 0, 0)
    const t3 = new Date(2023, 0, 1, 12, 0, 0)
    const activities = [
      makeActivity('f1', u, 'A', t1),
      makeActivity('f2', u, 'B', t2),
      makeActivity('f3', u, 'C', t3),
      makeActivity('f4', 'other', 'D', t2)
    ]
    const dashboard = new ActivityDashboard(activities)
    const filtered = dashboard.filterByDateRange(u, t1, t2)
    expect(filtered.map(a => a.id)).toEqual(['f1', 'f2'])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array when no activities for user', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.aggregateByAction('none')).toEqual([])
  })

  it('aggregates counts, percentages and occurrence bounds per action and sorts by count desc', () => {
    const u = 'uA'
    const t0 = new Date(2023, 0, 1, 9, 0, 0)
    const activities = [
      makeActivity('ag1', u, 'click', new Date(t0.getTime() + 0)),
      makeActivity('ag2', u, 'click', new Date(t0.getTime() + 1000)),
      makeActivity('ag3', u, 'click', new Date(t0.getTime() + 2000)),
      makeActivity('ag4', u, 'view', new Date(t0.getTime() + 3000))
    ]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction(u)
    expect(groups.length).toBe(2)
    expect(groups[0].action).toBe('click')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(75)
    expect(groups[0].firstOccurrence.getTime()).toBe(activities[0].timestamp.getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(activities[2].timestamp.getTime())
    expect(groups[1].action).toBe('view')
    expect(groups[1].count).toBe(1)
    expect(groups[1].percentage).toBe(25)
  })

  it('rounds percentage to two decimals when not evenly divisible', () => {
    const u = 'uAR'
    const t0 = new Date(2023, 0, 2, 9, 0, 0)
    const activities = [
      makeActivity('r1', u, 'x', new Date(t0.getTime() + 0)),
      makeActivity('r2', u, 'x', new Date(t0.getTime() + 1000)),
      makeActivity('r3', u, 'y', new Date(t0.getTime() + 2000))
    ]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction(u)
    const x = groups.find(g => g.action === 'x')!
    const y = groups.find(g => g.action === 'y')!
    expect(x.percentage).toBe(66.67)
    expect(y.percentage).toBe(33.33)
  })
})

describe('ActivityDashboard - getTopActions_old', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const top = dashboard.getTopActions_old('nouser')
    expect(top).toEqual([])
  })

  it('aggregates action stats sorted by count', () => {
    const u = 'uOld'
    const t0 = new Date(2023, 0, 3, 9, 0, 0)
    const acts = [
      makeActivity('o1', u, 'a', new Date(t0.getTime() + 100)),
      makeActivity('o2', u, 'a', new Date(t0.getTime() + 200)),
      makeActivity('o3', u, 'b', new Date(t0.getTime() + 300)),
      makeActivity('o4', u, 'a', new Date(t0.getTime() + 400))
    ]
    const dashboard = new ActivityDashboard(acts)
    const top = dashboard.getTopActions_old(u)
    expect(top[0].action).toBe('a')
    expect(top[0].count).toBe(3)
    expect(top[0].percentage).toBe(75)
    expect(top[0].firstOccurrence.getTime()).toBe(acts[0].timestamp.getTime())
    expect(top[0].lastOccurrence.getTime()).toBe(acts[3].timestamp.getTime())
    expect(top[1].action).toBe('b')
    expect(top[1].count).toBe(1)
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('returns limited number of top actions by count', () => {
    const u = 'uTop'
    const t0 = new Date(2023, 0, 4, 9, 0, 0)
    const activities = [
      makeActivity('t1', u, 'a', new Date(t0.getTime() + 0)),
      makeActivity('t2', u, 'a', new Date(t0.getTime() + 1000)),
      makeActivity('t3', u, 'b', new Date(t0.getTime() + 2000)),
      makeActivity('t4', u, 'c', new Date(t0.getTime() + 3000)),
      makeActivity('t5', u, 'c', new Date(t0.getTime() + 4000)),
      makeActivity('t6', u, 'c', new Date(t0.getTime() + 5000))
    ]
    const dashboard = new ActivityDashboard(activities)
    const top2 = dashboard.getTopActions(u, 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('c') // 3 occurrences
    expect(top2[0].count).toBe(3)
    expect(top2[1].action).toBe('a') // 2 occurrences
    expect(top2[1].count).toBe(2)
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when no summary is available', () => {
    const dashboard = new ActivityDashboard([])
    const score = dashboard.calculateEngagementScore('uZ')
    expect(score).toBe(0)
  })

  it('computes score using weighted volume, diversity, and frequency', () => {
    const u = 'uScore'
    const base = new Date(2023, 0, 1, 10, 0, 0)
    const activities = [
      makeActivity('s1', u, 'A', new Date(base.getTime() + 0)),
      makeActivity('s2', u, 'B', new Date(base.getTime() + 15 * 60000)),
      makeActivity('s3', u, 'A', new Date(base.getTime() + 45 * 60000)),
      makeActivity('s4', u, 'C', new Date(base.getTime() + 80 * 60000))
    ]
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore(u)
    // totalActions=4 => volumeScore=1.2; unique=3 => 9; actionsPerDay=4 => 32; total=42.2
    expect(score).toBe(42.2)
  })
})