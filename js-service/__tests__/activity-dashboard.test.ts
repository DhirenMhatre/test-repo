import { describe, it, expect, jest, afterEach, beforeEach } from '@jest/globals'
import { ActivityDashboard, Activity, ActionGroup, TrendData, ActivitySummary } from '../src/activity-dashboard'

function act(id: string, user: string, action: string, date: Date, metadata?: Record<string, any>): Activity {
  return { id, user_id: user, action, timestamp: date, metadata }
}

describe('ActivityDashboard', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      const summary = dashboard.getUserSummary('user-x')
      expect(summary).toBeNull()
    })

    it('computes summary with totals, unique count, per-day, most frequent, avg per session', () => {
      const u = 'u1'
      const activities: Activity[] = [
        act('a1', u, 'login', new Date(2023, 0, 1, 10, 0)),
        act('a2', u, 'view', new Date(2023, 0, 1, 10, 10)),
        act('a3', u, 'view', new Date(2023, 0, 1, 10, 45)),
        act('a4', u, 'logout', new Date(2023, 0, 1, 11, 5)),
        act('a5', u, 'login', new Date(2023, 0, 2, 9, 0)),
        act('a6', u, 'view', new Date(2023, 0, 3, 12, 0)),
        act('b1', 'other', 'view', new Date(2023, 0, 1, 10, 0)),
      ]
      const dashboard = new ActivityDashboard(activities)
      const summary = dashboard.getUserSummary(u) as ActivitySummary

      expect(summary).not.toBeNull()
      expect(summary.totalActions).toBe(6)
      expect(summary.uniqueActions).toBe(3)
      expect(summary.actionsPerDay).toBe(2) // 6 actions over ceil(~2.08 days) => 3 days => 2.00
      expect(summary.mostFrequentAction).toBe('view')
      expect(summary.averageActionsPerSession).toBe(1.5) // sessions split by >30min gaps
    })

    it('mostFrequentAction ties resolved by first encountered action', () => {
      const u = 'uTie'
      const activities: Activity[] = [
        act('t1', u, 'b', new Date(2023, 0, 1, 9, 0)),
        act('t2', u, 'a', new Date(2023, 0, 1, 9, 5)),
        act('t3', u, 'a', new Date(2023, 0, 1, 9, 10)),
        act('t4', u, 'b', new Date(2023, 0, 1, 9, 15)),
      ]
      const dashboard = new ActivityDashboard(activities)
      const summary = dashboard.getUserSummary(u) as ActivitySummary
      expect(summary.mostFrequentAction).toBe('b')
    })

    it('actionsPerDay uses minimum of 1 day for same-day activity', () => {
      const u = 'uSingle'
      const activities: Activity[] = [
        act('s1', u, 'login', new Date(2023, 0, 1, 12, 0)),
      ]
      const dashboard = new ActivityDashboard(activities)
      const summary = dashboard.getUserSummary(u) as ActivitySummary
      expect(summary.actionsPerDay).toBe(1)
    })
  })

  describe('getActivityTrends', () => {
    let dashboard: ActivityDashboard
    const u = 'uTrends'
    beforeEach(() => {
      const activities: Activity[] = [
        act('d1', u, 'a', new Date(2023, 0, 1, 10, 0)),
        act('d2', u, 'b', new Date(2023, 0, 1, 12, 0)),
        act('d3', u, 'c', new Date(2023, 0, 1, 13, 0)),
        act('d4', u, 'd', new Date(2023, 0, 1, 14, 0)),
        act('d5', u, 'e', new Date(2023, 0, 2, 9, 0)),
        act('d6', u, 'f', new Date(2023, 0, 3, 10, 0)),
        act('o1', 'other', 'a', new Date(2023, 0, 1, 10, 0)),
      ]
      dashboard = new ActivityDashboard(activities)
    })

    it('returns empty array when user has no activities', () => {
      const empty = new ActivityDashboard([])
      const trends = empty.getActivityTrends('nobody', 'day')
      expect(trends).toEqual([])
    })

    it('groups by day with correct counts and growth rates', () => {
      const trends = dashboard.getActivityTrends(u, 'day')
      expect(trends.map(t => t.period)).toEqual(['2023-01-01', '2023-01-02', '2023-01-03'])
      const counts = trends.map(t => t.count)
      expect(counts).toEqual([4, 1, 1])
      const growthRates = trends.map(t => t.growthRate)
      expect(growthRates[0]).toBe(0)
      expect(growthRates[1]).toBe(-75)
      expect(growthRates[2]).toBe(0)
    })

    it('groups by hour with correct period keys', () => {
      const acts: Activity[] = [
        act('h1', u, 'a', new Date(2023, 0, 4, 10, 0)),
        act('h2', u, 'a', new Date(2023, 0, 4, 10, 30)),
        act('h3', u, 'a', new Date(2023, 0, 4, 11, 0)),
      ]
      const db = new ActivityDashboard(acts)
      const trends = db.getActivityTrends(u, 'hour')
      expect(trends.map(t => t.period)).toEqual(['2023-01-04 10:00', '2023-01-04 11:00'])
      expect(trends.map(t => t.count)).toEqual([2, 1])
      expect(trends[1].growthRate).toBe(-50)
    })

    it('groups by week with expected week keys', () => {
      const acts: Activity[] = [
        act('w1', u, 'a', new Date(2023, 0, 1, 10, 0)), // week 01
        act('w2', u, 'a', new Date(2023, 0, 8, 10, 0)), // week 02
        act('w3', u, 'a', new Date(2023, 0, 8, 11, 0)), // week 02
      ]
      const db = new ActivityDashboard(acts)
      const trends = db.getActivityTrends(u, 'week')
      expect(trends.map(t => t.period)).toEqual(['2023-W01', '2023-W02'])
      expect(trends.map(t => t.count)).toEqual([1, 2])
      expect(trends[1].growthRate).toBe(100)
    })

    it('groups by month with correct keys and growth 0 when equal counts', () => {
      const acts: Activity[] = [
        act('m1', u, 'a', new Date(2023, 0, 15, 10, 0)), // Jan
        act('m2', u, 'a', new Date(2023, 1, 1, 10, 0)), // Feb
      ]
      const db = new ActivityDashboard(acts)
      const trends = db.getActivityTrends(u, 'month')
      expect(trends.map(t => t.period)).toEqual(['2023-01', '2023-02'])
      expect(trends.map(t => t.count)).toEqual([1, 1])
      expect(trends[1].growthRate).toBe(0)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within inclusive date range', () => {
      const u = 'uRange'
      const activities: Activity[] = [
        act('r1', u, 'a', new Date(2023, 0, 1, 0, 0)),
        act('r2', u, 'b', new Date(2023, 0, 1, 12, 0)),
        act('r3', u, 'c', new Date(2023, 0, 1, 23, 59)),
        act('r4', u, 'd', new Date(2023, 0, 2, 0, 0)),
      ]
      const dashboard = new ActivityDashboard(activities)
      const start = new Date(2023, 0, 1, 0, 0)
      const end = new Date(2023, 0, 1, 23, 59)
      const filtered = dashboard.filterByDateRange(u, start, end)
      expect(filtered.map(a => a.id)).toEqual(['r1', 'r2', 'r3'])
    })

    it('returns empty when range does not include any activity', () => {
      const u = 'uRange2'
      const activities: Activity[] = [
        act('r1', u, 'a', new Date(2023, 0, 5, 10, 0)),
      ]
      const dashboard = new ActivityDashboard(activities)
      const filtered = dashboard.filterByDateRange(u, new Date(2023, 0, 1), new Date(2023, 0, 2))
      expect(filtered).toEqual([])
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      expect(dashboard.aggregateByAction('nobody')).toEqual([])
    })

    it('aggregates counts, percentages, and first/last occurrences; sorted by count desc', () => {
      const u = 'uAgg'
      const activities: Activity[] = [
        act('a1', u, 'login', new Date(2023, 0, 1, 10, 0)),
        act('a2', u, 'view', new Date(2023, 0, 1, 10, 10)),
        act('a3', u, 'view', new Date(2023, 0, 1, 10, 45)),
        act('a4', u, 'logout', new Date(2023, 0, 1, 11, 5)),
        act('a5', u, 'login', new Date(2023, 0, 2, 9, 0)),
        act('a6', u, 'view', new Date(2023, 0, 3, 12, 0)),
      ]
      const dashboard = new ActivityDashboard(activities)
      const groups = dashboard.aggregateByAction(u)
      const byAction = new Map(groups.map(g => [g.action, g]))

      const view = byAction.get('view') as ActionGroup
      expect(view.count).toBe(3)
      expect(view.percentage).toBe(50)
      expect(view.firstOccurrence.getTime()).toBe(new Date(2023, 0, 1, 10, 10).getTime())
      expect(view.lastOccurrence.getTime()).toBe(new Date(2023, 0, 3, 12, 0).getTime())

      const login = byAction.get('login') as ActionGroup
      expect(login.count).toBe(2)
      expect(login.percentage).toBe(33.33)
      expect(login.firstOccurrence.getTime()).toBe(new Date(2023, 0, 1, 10, 0).getTime())
      expect(login.lastOccurrence.getTime()).toBe(new Date(2023, 0, 2, 9, 0).getTime())

      const logout = byAction.get('logout') as ActionGroup
      expect(logout.count).toBe(1)
      expect(logout.percentage).toBe(16.67)

      // sorted by count desc: first should be 'view'
      expect(groups[0].action).toBe('view')
      expect(groups[0].count).toBe(3)
    })
  })

  describe('getTopActions_old', () => {
    it('returns all action groups sorted by count desc and ignores limit parameter', () => {
      const u = 'uOld'
      const activities: Activity[] = [
        act('o1', u, 'x', new Date(2023, 0, 1, 10, 0)),
        act('o2', u, 'y', new Date(2023, 0, 1, 11, 0)),
        act('o3', u, 'x', new Date(2023, 0, 1, 12, 0)),
        act('o4', u, 'z', new Date(2023, 0, 2, 9, 0)),
      ]
      const dashboard = new ActivityDashboard(activities)
      const groups = dashboard.getTopActions_old(u, 1)
      expect(groups.length).toBe(3)
      expect(groups[0].action).toBe('x')
      expect(groups[0].count).toBe(2)
      expect(groups[1].count).toBe(1)
      expect(groups[2].count).toBe(1)

      const x = groups.find(g => g.action === 'x') as ActionGroup
      expect(x.firstOccurrence.getTime()).toBe(new Date(2023, 0, 1, 10, 0).getTime())
      expect(x.lastOccurrence.getTime()).toBe(new Date(2023, 0, 1, 12, 0).getTime())
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions limited by the provided limit', () => {
      const u = 'uTop'
      const activities: Activity[] = [
        act('t1', u, 'a', new Date(2023, 0, 1, 10, 0)),
        act('t2', u, 'a', new Date(2023, 0, 1, 10, 1)),
        act('t3', u, 'b', new Date(2023, 0, 1, 10, 2)),
        act('t4', u, 'c', new Date(2023, 0, 1, 10, 3)),
        act('t5', u, 'd', new Date(2023, 0, 1, 10, 4)),
        act('t6', u, 'e', new Date(2023, 0, 1, 10, 5)),
      ]
      const dashboard = new ActivityDashboard(activities)
      const top2 = dashboard.getTopActions(u, 2)
      expect(top2.length).toBe(2)
      expect(top2[0].action).toBe('a')
      const top10 = dashboard.getTopActions(u, 10)
      expect(top10.length).toBe(5) // 5 unique actions
    })

    it('returns empty when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      expect(dashboard.getTopActions('none')).toEqual([])
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when no summary available', () => {
      const dashboard = new ActivityDashboard([])
      expect(dashboard.calculateEngagementScore('nobody')).toBe(0)
    })

    it('calculates score based on volume, diversity, and frequency', () => {
      const u = 'uScore'
      const activities: Activity[] = [
        act('s1', u, 'login', new Date(2023, 0, 1, 10, 0)),
        act('s2', u, 'view', new Date(2023, 0, 1, 10, 10)),
        act('s3', u, 'view', new Date(2023, 0, 1, 10, 45)),
        act('s4', u, 'logout', new Date(2023, 0, 1, 11, 5)),
        act('s5', u, 'login', new Date(2023, 0, 2, 9, 0)),
        act('s6', u, 'view', new Date(2023, 0, 3, 12, 0)),
      ]
      const dashboard = new ActivityDashboard(activities)
      const score = dashboard.calculateEngagementScore(u)
      expect(score).toBe(26.8) // volume 1.8 + diversity 9 + frequency 16 = 26.8
    })

    it('caps score components and returns maximum 100', () => {
      const u = 'uMax'
      const acts: Activity[] = []
      // 150 actions in one day, across 10 unique action types to cap diversity
      for (let i = 0; i < 150; i++) {
        const actionName = `act${i % 10}`
        acts.push(act(`m${i}`, u, actionName, new Date(2023, 1, 1, 10, i % 60)))
      }
      const dashboard = new ActivityDashboard(acts)
      const score = dashboard.calculateEngagementScore(u)
      expect(score).toBe(100)
    })
  })
})