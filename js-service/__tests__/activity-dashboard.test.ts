import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

type Activity = {
  id: string
  user_id: string
  action: string
  timestamp: Date
  metadata?: Record<string, any>
}

const makeAct = (id: string, user_id: string, action: string, date: Date): Activity => ({
  id,
  user_id,
  action,
  timestamp: date
})

describe('ActivityDashboard', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const dash = new ActivityDashboard([])
      const summary = dash.getUserSummary('u1')
      expect(summary).toBeNull()
    })

    it('computes total, unique, mostFrequentAction, actionsPerDay and averageActionsPerSession correctly', () => {
      const acts: Activity[] = [
        makeAct('1', 'u1', 'login', new Date(2024, 0, 1, 10, 0, 0)),
        makeAct('2', 'u1', 'click', new Date(2024, 0, 1, 10, 10, 0)),
        makeAct('3', 'u1', 'click', new Date(2024, 0, 1, 10, 40, 0)), // exactly 30 mins after - same session
        makeAct('4', 'u1', 'purchase', new Date(2024, 0, 1, 11, 50, 0)), // > 30 mins after - new session
        makeAct('5', 'u1', 'click', new Date(2024, 0, 2, 9, 0, 0)),
        makeAct('6', 'u1', 'logout', new Date(2024, 0, 3, 12, 0, 0)),
        makeAct('7', 'u2', 'login', new Date(2024, 0, 1, 12, 0, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(6)
      expect(summary!.uniqueActions).toBe(4)
      expect(summary!.mostFrequentAction).toBe('click')
      expect(summary!.actionsPerDay).toBe(2) // 6 actions over 3 daysActive
      expect(summary!.averageActionsPerSession).toBe(1.5) // 4 sessions: [1,2,1,1]
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard([])
      const trends = dash.getActivityTrends('u1', 'day')
      expect(trends).toEqual([])
    })

    it('groups by day with correct counts and growth rates', () => {
      const acts: Activity[] = [
        makeAct('1', 'u1', 'login', new Date(2024, 0, 1, 10, 0, 0)),
        makeAct('2', 'u1', 'click', new Date(2024, 0, 1, 10, 10, 0)),
        makeAct('3', 'u1', 'click', new Date(2024, 0, 1, 10, 40, 0)),
        makeAct('4', 'u1', 'purchase', new Date(2024, 0, 1, 11, 50, 0)),
        makeAct('5', 'u1', 'click', new Date(2024, 0, 2, 9, 0, 0)),
        makeAct('6', 'u1', 'logout', new Date(2024, 0, 3, 12, 0, 0)),
        makeAct('7', 'u2', 'login', new Date(2024, 0, 1, 12, 0, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'day')
      expect(trends.length).toBe(3)
      expect(trends[0].period).toMatch(/^\d{4}-\d{2}-\d{2}$/)
      expect(trends[0].count).toBe(4)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBe(-75)
      expect(trends[2].count).toBe(1)
      expect(trends[2].growthRate).toBe(0)
    })

    it('groups by hour with padded hour key and correct growth rate rounding', () => {
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', new Date(2024, 0, 1, 3, 15, 0)),
        makeAct('2', 'u1', 'a', new Date(2024, 0, 1, 3, 35, 0)),
        makeAct('3', 'u1', 'b', new Date(2024, 0, 1, 3, 59, 59)),
        makeAct('4', 'u1', 'c', new Date(2024, 0, 1, 4, 0, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'hour')
      expect(trends.length).toBe(2)
      expect(trends[0].period.endsWith('03:00')).toBe(true)
      expect(trends[0].count).toBe(3)
      expect(trends[1].period.endsWith('04:00')).toBe(true)
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBe(-66.67)
    })

    it('groups by month correctly', () => {
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', new Date(2024, 0, 31, 23, 59, 59)),
        makeAct('2', 'u1', 'b', new Date(2024, 0, 1, 0, 0, 0)),
        makeAct('3', 'u1', 'c', new Date(2024, 0, 15, 12, 0, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'month')
      expect(trends.length).toBe(1)
      expect(trends[0].period).toMatch(/^\d{4}-\d{2}$/)
      expect(trends[0].count).toBe(3)
      expect(trends[0].growthRate).toBe(0)
    })

    it('groups by week with zero-padded week number', () => {
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', new Date(2024, 0, 1, 10, 0, 0)) // Jan 1, 2024 is week 01 per implementation
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'week')
      expect(trends.length).toBe(1)
      expect(trends[0].period).toContain('-W01')
      expect(trends[0].count).toBe(1)
      expect(trends[0].growthRate).toBe(0)
    })
  })

  describe('filterByDateRange', () => {
    it('filters inclusively by start and end date for the given user', () => {
      const a1 = new Date(2024, 0, 1, 10, 0, 0)
      const a2 = new Date(2024, 0, 1, 10, 10, 0)
      const a3 = new Date(2024, 0, 1, 10, 40, 0)
      const a4 = new Date(2024, 0, 1, 11, 50, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'login', a1),
        makeAct('2', 'u1', 'click', a2),
        makeAct('3', 'u1', 'click', a3),
        makeAct('4', 'u1', 'purchase', a4),
        makeAct('5', 'u2', 'login', a3)
      ]
      const dash = new ActivityDashboard(acts)
      const result = dash.filterByDateRange('u1', a2, a4)
      const times = result.map(r => r.timestamp.getTime()).sort()
      expect(times).toEqual([a2.getTime(), a3.getTime(), a4.getTime()].sort())
    })

    it('returns empty array if no activities fall within the range or user mismatch', () => {
      const acts: Activity[] = [
        makeAct('1', 'u1', 'login', new Date(2024, 0, 1, 10, 0, 0)),
        makeAct('2', 'u2', 'login', new Date(2024, 0, 1, 10, 10, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const result1 = dash.filterByDateRange('u1', new Date(2024, 0, 1, 10, 1, 0), new Date(2024, 0, 1, 10, 2, 0))
      expect(result1).toEqual([])
      const result2 = dash.filterByDateRange('u3', new Date(2024, 0, 1, 0, 0, 0), new Date(2024, 0, 2, 0, 0, 0))
      expect(result2).toEqual([])
    })
  })

  describe('aggregateByAction', () => {
    it('aggregates correctly with counts, percentages, and first/last occurrences, sorted by count desc', () => {
      const a1 = new Date(2024, 0, 1, 10, 0, 0)
      const a2 = new Date(2024, 0, 1, 10, 10, 0)
      const a3 = new Date(2024, 0, 1, 10, 40, 0)
      const a4 = new Date(2024, 0, 1, 11, 50, 0)
      const a5 = new Date(2024, 0, 2, 9, 0, 0)
      const a6 = new Date(2024, 0, 3, 12, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'login', a1),
        makeAct('2', 'u1', 'click', a2),
        makeAct('3', 'u1', 'click', a3),
        makeAct('4', 'u1', 'purchase', a4),
        makeAct('5', 'u1', 'click', a5),
        makeAct('6', 'u1', 'logout', a6),
        makeAct('7', 'u2', 'login', a1)
      ]
      const dash = new ActivityDashboard(acts)
      const groups = dash.aggregateByAction('u1')
      expect(groups.length).toBe(4)
      expect(groups[0].action).toBe('click')
      expect(groups[0].count).toBe(3)
      expect(groups[0].percentage).toBe(50)
      expect(groups[0].firstOccurrence.getTime()).toBe(a2.getTime())
      expect(groups[0].lastOccurrence.getTime()).toBe(a5.getTime())
      const other = groups.filter(g => g.action !== 'click')
      other.forEach(g => {
        expect(g.count).toBe(1)
        expect(g.percentage).toBe(16.67)
      })
    })

    it('returns empty array when no activities for user', () => {
      const acts: Activity[] = [
        makeAct('1', 'u2', 'login', new Date(2024, 0, 1, 10, 0, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const groups = dash.aggregateByAction('u1')
      expect(groups).toEqual([])
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count (no limit applied)', () => {
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', new Date(2024, 0, 1, 10, 0, 0)),
        makeAct('2', 'u1', 'b', new Date(2024, 0, 1, 10, 5, 0)),
        makeAct('3', 'u1', 'a', new Date(2024, 0, 1, 10, 10, 0)),
        makeAct('4', 'u1', 'c', new Date(2024, 0, 1, 10, 15, 0)),
        makeAct('5', 'u1', 'a', new Date(2024, 0, 1, 10, 20, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const top = dash.getTopActions_old('u1')
      expect(top.length).toBe(3)
      expect(top[0].action).toBe('a')
      expect(top[0].count).toBe(3)
      const actions = top.map(t => t.action)
      expect(actions).toEqual(expect.arrayContaining(['b', 'c']))
    })
  })

  describe('getTopActions', () => {
    it('limits results to specified number and sorts by count desc', () => {
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', new Date(2024, 0, 1, 10, 0, 0)),
        makeAct('2', 'u1', 'b', new Date(2024, 0, 1, 10, 5, 0)),
        makeAct('3', 'u1', 'a', new Date(2024, 0, 1, 10, 10, 0)),
        makeAct('4', 'u1', 'c', new Date(2024, 0, 1, 10, 15, 0)),
        makeAct('5', 'u1', 'a', new Date(2024, 0, 1, 10, 20, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const top2 = dash.getTopActions('u1', 2)
      expect(top2.length).toBe(2)
      expect(top2[0].action).toBe('a')
      expect(top2[0].count).toBe(3)
      expect(top2[1].count).toBe(1)
    })

    it('returns fewer than limit when not enough actions', () => {
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', new Date(2024, 0, 1, 10, 0, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const top = dash.getTopActions('u1', 5)
      expect(top.length).toBe(1)
      expect(top[0].action).toBe('a')
      expect(top[0].count).toBe(1)
    })

    it('returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard([])
      const top = dash.getTopActions('u1', 3)
      expect(top).toEqual([])
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when user has no activity summary', () => {
      const dash = new ActivityDashboard([])
      const score = dash.calculateEngagementScore('u1')
      expect(score).toBe(0)
    })

    it('calculates based on volume, diversity, and frequency with rounding to 2 decimals', () => {
      const acts: Activity[] = [
        makeAct('1', 'u1', 'login', new Date(2024, 0, 1, 10, 0, 0)),
        makeAct('2', 'u1', 'click', new Date(2024, 0, 1, 10, 10, 0)),
        makeAct('3', 'u1', 'click', new Date(2024, 0, 1, 10, 40, 0)),
        makeAct('4', 'u1', 'purchase', new Date(2024, 0, 1, 11, 50, 0)),
        makeAct('5', 'u1', 'click', new Date(2024, 0, 2, 9, 0, 0)),
        makeAct('6', 'u1', 'logout', new Date(2024, 0, 3, 12, 0, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const score = dash.calculateEngagementScore('u1')
      expect(score).toBeCloseTo(29.8, 2)
    })

    it('caps each component and total at 100', () => {
      const manyActs: Activity[] = []
      const base = new Date(2024, 0, 1, 0, 0, 0)
      // 200 actions in the same day across 20 unique actions
      for (let i = 0; i < 200; i++) {
        const action = `a${i % 20}`
        const ts = new Date(2024, 0, 1, 0, 0, i) // spread within the same day
        manyActs.push(makeAct(String(i + 1), 'u3', action, ts))
      }
      const dash = new ActivityDashboard(manyActs)
      const score = dash.calculateEngagementScore('u3')
      expect(score).toBe(100)
    })
  })
})