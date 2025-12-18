import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

function mkActivity(id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity {
  return { id, user_id, action, timestamp: date, metadata }
}

describe('ActivityDashboard', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const dash = new ActivityDashboard([])
      const res = dash.getUserSummary('u1')
      expect(res).toBeNull()
    })

    it('computes totals, unique actions, mostFrequentAction, actionsPerDay, averageActionsPerSession', () => {
      const base = new Date(2024, 0, 1, 10, 0, 0)
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'click', new Date(2024, 0, 1, 10, 0, 0)),
        mkActivity('2', 'u1', 'view', new Date(2024, 0, 1, 10, 20, 0)),
        mkActivity('3', 'u1', 'click', new Date(2024, 0, 1, 11, 0, 0)),
        mkActivity('4', 'u1', 'purchase', new Date(2024, 0, 2, 22, 0, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const res = dash.getUserSummary('u1')
      expect(res).not.toBeNull()
      expect(res!.totalActions).toBe(4)
      expect(res!.uniqueActions).toBe(3)
      expect(res!.mostFrequentAction).toBe('click')
      // last - first = 36h => ceil(1.5) = 2 daysActive -> 4/2 = 2.00
      expect(res!.actionsPerDay).toBe(2.0)
      // sessions: [10:00,10:20] same; 11:00 new; next day 22:00 new -> 3 sessions => 4/3 = 1.33
      expect(res!.averageActionsPerSession).toBe(1.33)
    })

    it('uses at least 1 day for actionsPerDay when timestamps are same day', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9)),
        mkActivity('2', 'u1', 'b', new Date(2024, 0, 1, 10)),
        mkActivity('3', 'u1', 'a', new Date(2024, 0, 1, 11))
      ]
      const dash = new ActivityDashboard(acts)
      const res = dash.getUserSummary('u1')
      expect(res).not.toBeNull()
      // last-first < 1 day => ceil(less than 1) => 1 dayActive
      expect(res!.actionsPerDay).toBe(3.0)
    })
  })

  describe('filterByDateRange', () => {
    it('filters by inclusive date range for a specific user', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
        mkActivity('2', 'u1', 'b', new Date(2024, 0, 1, 10, 0)),
        mkActivity('3', 'u1', 'c', new Date(2024, 0, 1, 12, 0)),
        mkActivity('4', 'u2', 'a', new Date(2024, 0, 1, 10, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const start = new Date(2024, 0, 1, 10, 0)
      const end = new Date(2024, 0, 1, 12, 0)
      const filtered = dash.filterByDateRange('u1', start, end)
      expect(filtered.map(a => a.id)).toEqual(['2', '3'])
    })

    it('returns empty if no activities within range or user mismatch', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
        mkActivity('2', 'u1', 'b', new Date(2024, 0, 1, 10, 0)),
        mkActivity('3', 'u2', 'c', new Date(2024, 0, 1, 12, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const filtered = dash.filterByDateRange('u1', new Date(2024, 0, 2, 0, 0), new Date(2024, 0, 3, 0, 0))
      expect(filtered).toHaveLength(0)
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard([])
      const agg = dash.aggregateByAction('u1')
      expect(agg).toEqual([])
    })

    it('groups by action with counts, percentage, first and last occurrences, sorted by count desc', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'view', new Date(2024, 0, 1, 10, 0)),
        mkActivity('2', 'u1', 'view', new Date(2024, 0, 1, 10, 30)),
        mkActivity('3', 'u1', 'click', new Date(2024, 0, 1, 11, 0)),
        mkActivity('4', 'u1', 'purchase', new Date(2024, 0, 1, 12, 0)),
        mkActivity('5', 'u1', 'purchase', new Date(2024, 0, 1, 12, 30)),
        mkActivity('6', 'u1', 'view', new Date(2024, 0, 1, 12, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const agg = dash.aggregateByAction('u1')
      expect(agg.map(g => g.action)).toEqual(['view', 'purchase', 'click'])
      const view = agg[0]
      expect(view.count).toBe(3)
      expect(view.percentage).toBe(50.0)
      expect(view.firstOccurrence.getTime()).toBe(new Date(2024, 0, 1, 10, 0).getTime())
      expect(view.lastOccurrence.getTime()).toBe(new Date(2024, 0, 1, 12, 0).getTime())
      const purchase = agg[1]
      expect(purchase.count).toBe(2)
      expect(purchase.percentage).toBe(33.33)
      const click = agg[2]
      expect(click.count).toBe(1)
      expect(click.percentage).toBe(16.67)
    })
  })

  describe('getTopActions_old', () => {
    it('returns sorted action groups without applying limit', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9)),
        mkActivity('2', 'u1', 'a', new Date(2024, 0, 1, 10)),
        mkActivity('3', 'u1', 'b', new Date(2024, 0, 1, 11)),
        mkActivity('4', 'u1', 'c', new Date(2024, 0, 1, 12)),
        mkActivity('5', 'u1', 'c', new Date(2024, 0, 1, 13)),
        mkActivity('6', 'u1', 'c', new Date(2024, 0, 1, 14))
      ]
      const dash = new ActivityDashboard(acts)
      const top = dash.getTopActions_old('u1', 1)
      expect(top.map(t => t.action)).toEqual(['c', 'a', 'b'])
      expect(top[0].count).toBe(3)
      expect(top[1].count).toBe(2)
      expect(top[2].count).toBe(1)
    })
  })

  describe('getTopActions', () => {
    it('returns top N action groups based on counts', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'x', new Date(2024, 0, 1, 9)),
        mkActivity('2', 'u1', 'x', new Date(2024, 0, 1, 10)),
        mkActivity('3', 'u1', 'y', new Date(2024, 0, 1, 11)),
        mkActivity('4', 'u1', 'z', new Date(2024, 0, 1, 12)),
        mkActivity('5', 'u1', 'z', new Date(2024, 0, 1, 13)),
        mkActivity('6', 'u1', 'z', new Date(2024, 0, 1, 14))
      ]
      const dash = new ActivityDashboard(acts)
      const top2 = dash.getTopActions('u1', 2)
      expect(top2.map(t => t.action)).toEqual(['z', 'x'])
      const top10 = dash.getTopActions('u1', 10)
      expect(top10.map(t => t.action)).toEqual(['z', 'x', 'y'])
    })

    it('returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard([])
      const top = dash.getTopActions('u1', 3)
      expect(top).toEqual([])
    })

    it('returns empty when limit is 0', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9))
      ]
      const dash = new ActivityDashboard(acts)
      const top0 = dash.getTopActions('u1', 0)
      expect(top0).toEqual([])
    })
  })

  describe('getActivityTrends (day)', () => {
    it('groups activities by day, sorts periods, and computes growth rates', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9)),
        mkActivity('2', 'u1', 'a', new Date(2024, 0, 2, 10)),
        mkActivity('3', 'u1', 'b', new Date(2024, 0, 2, 11)),
        mkActivity('4', 'u1', 'c', new Date(2024, 0, 3, 12))
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'day')
      expect(trends).toHaveLength(3)
      const periods = trends.map(t => t.period)
      expect(periods).toEqual(['2024-01-01', '2024-01-02', '2024-01-03'])
      const counts = trends.map(t => t.count)
      expect(counts).toEqual([1, 2, 1])
      const growth = trends.map(t => t.growthRate)
      // first is 0, second: ((2-1)/1)*100=100, third: ((1-2)/2)*100=-50
      expect(growth).toEqual([0, 100, -50])
    })

    it('returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.getActivityTrends('uX', 'day')).toEqual([])
    })
  })

  describe('getActivityTrends (hour)', () => {
    it('groups by hour with correct period keys and growth', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 15)),
        mkActivity('2', 'u1', 'a', new Date(2024, 0, 1, 9, 45)),
        mkActivity('3', 'u1', 'b', new Date(2024, 0, 1, 10, 5))
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'hour')
      expect(trends).toHaveLength(2)
      expect(trends[0].period).toBe('2024-01-01 09:00')
      expect(trends[0].count).toBe(2)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].period).toBe('2024-01-01 10:00')
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBe(-50)
    })
  })

  describe('getActivityTrends (week)', () => {
    it('groups into weeks with counts and computes growth rates', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 1, 10)), // likely week 1
        mkActivity('2', 'u1', 'b', new Date(2024, 0, 2, 11)), // week 1
        mkActivity('3', 'u1', 'c', new Date(2024, 0, 8, 12)), // week 2
        mkActivity('4', 'u1', 'c', new Date(2024, 0, 9, 9))   // week 2
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'week')
      expect(trends.length).toBe(2)
      // bucket label pattern YYYY-Wxx
      expect(/^\d{4}-W\d{2}$/.test(trends[0].period)).toBe(true)
      expect(/^\d{4}-W\d{2}$/.test(trends[1].period)).toBe(true)
      expect(trends[0].count).toBe(2)
      expect(trends[1].count).toBe(2)
      // growth where prevCount=2, current=2 => ((2-2)/2)*100=0
      expect(trends[1].growthRate).toBe(0)
    })
  })

  describe('getActivityTrends (month)', () => {
    it('groups into months and computes growth', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 15, 10)),
        mkActivity('2', 'u1', 'b', new Date(2024, 1, 2, 11)),
        mkActivity('3', 'u1', 'b', new Date(2024, 1, 9, 9)),
        mkActivity('4', 'u1', 'b', new Date(2024, 1, 10, 9))
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'month')
      expect(trends.map(t => t.period)).toEqual(['2024-01', '2024-02'])
      expect(trends.map(t => t.count)).toEqual([1, 3])
      // ((3-1)/1)*100=200
      expect(trends[1].growthRate).toBe(200)
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 for users with no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.calculateEngagementScore('u1')).toBe(0)
    })

    it('computes weighted score with caps and two-decimal rounding', () => {
      const actions = ['a0', 'a1', 'a2', 'a3', 'a4']
      const acts: Activity[] = []
      // create 49 actions in early part
      for (let i = 0; i < 49; i++) {
        const day = 1 + Math.floor(i / 3) // spread across days
        acts.push(mkActivity(`${i}`, 'uE', actions[i % actions.length], new Date(2024, 0, day, 12, 0)))
      }
      // Ensure last activity is at Jan 21 to get 20 daysActive (ceil)
      acts.push(mkActivity('last', 'uE', 'a0', new Date(2024, 0, 21, 12, 0)))
      const dash = new ActivityDashboard(acts)
      const score = dash.calculateEngagementScore('uE')
      // total=50 -> 0.5*30=15
      // unique=5 -> 0.5*30=15
      // actionsPerDay=50/20=2.5 -> (2.5/5)*40=20
      expect(score).toBe(50)
    })
  })

  describe('user filtering across methods', () => {
    it('getActivityTrends isolates per user', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9)),
        mkActivity('2', 'u2', 'a', new Date(2024, 0, 1, 9)),
        mkActivity('3', 'u1', 'b', new Date(2024, 0, 2, 9))
      ]
      const dash = new ActivityDashboard(acts)
      const trendsU1 = dash.getActivityTrends('u1', 'day')
      expect(trendsU1).toHaveLength(2)
      const trendsU2 = dash.getActivityTrends('u2', 'day')
      expect(trendsU2).toHaveLength(1)
      expect(trendsU2[0].count).toBe(1)
    })

    it('aggregateByAction isolates per user', () => {
      const acts: Activity[] = [
        mkActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9)),
        mkActivity('2', 'u2', 'a', new Date(2024, 0, 1, 9)),
        mkActivity('3', 'u1', 'b', new Date(2024, 0, 2, 9))
      ]
      const dash = new ActivityDashboard(acts)
      const aggU1 = dash.aggregateByAction('u1')
      const aggU2 = dash.aggregateByAction('u2')
      expect(aggU1.reduce((sum, g) => sum + g.count, 0)).toBe(2)
      expect(aggU2.reduce((sum, g) => sum + g.count, 0)).toBe(1)
    })
  })
})