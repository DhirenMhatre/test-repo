import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

const act = (id: string, user: string, action: string, date: Date, metadata?: Record<string, any>) => ({
  id,
  user_id: user,
  action,
  timestamp: date,
  metadata
})

describe('ActivityDashboard', () => {
  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      const summary = dashboard.getUserSummary('uX')
      expect(summary).toBeNull()
    })

    it('calculates correct summary metrics for a user', () => {
      const activities = [
        act('1', 'u1', 'view', new Date(2024, 0, 1, 9, 0)),
        act('2', 'u1', 'click', new Date(2024, 0, 1, 9, 10)),
        act('3', 'u1', 'view', new Date(2024, 0, 1, 9, 15)),
        act('4', 'u1', 'purchase', new Date(2024, 0, 1, 10, 0)),
        act('5', 'u1', 'view', new Date(2024, 0, 2, 11, 0)),
        act('6', 'u1', 'click', new Date(2024, 0, 8, 12, 0))
      ]
      const dashboard = new ActivityDashboard(activities)
      const summary = dashboard.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(6)
      expect(summary!.uniqueActions).toBe(3)
      expect(summary!.actionsPerDay).toBe(0.75)
      expect(summary!.mostFrequentAction).toBe('view')
      expect(summary!.averageActionsPerSession).toBe(1.5)
    })

    it('picks the first encountered action when there is a tie for most frequent', () => {
      const activities = [
        act('a', 'u2', 'click', new Date(2024, 0, 1, 8, 0)),
        act('b', 'u2', 'view', new Date(2024, 0, 1, 9, 0)),
        act('c', 'u2', 'click', new Date(2024, 0, 2, 8, 0)),
        act('d', 'u2', 'view', new Date(2024, 0, 3, 9, 0))
      ]
      const dashboard = new ActivityDashboard(activities)
      const summary = dashboard.getUserSummary('u2')
      expect(summary).not.toBeNull()
      expect(summary!.mostFrequentAction).toBe('click')
    })

    it('does not start a new session for exactly 30 minutes gap (averageActionsPerSession)', () => {
      const activities = [
        act('x1', 'u3', 'view', new Date(2024, 0, 1, 9, 0)),
        act('x2', 'u3', 'view', new Date(2024, 0, 1, 9, 30))
      ]
      const dashboard = new ActivityDashboard(activities)
      const summary = dashboard.getUserSummary('u3')
      expect(summary).not.toBeNull()
      // Both in the same session => 2 actions / 1 session = 2.00
      expect(summary!.averageActionsPerSession).toBe(2.0)
    })

    it('rounds actionsPerDay to two decimals', () => {
      // 2 actions across 3 days window -> 2/3 = 0.6667 -> 0.67
      const activities = [
        act('y1', 'u4', 'view', new Date(2024, 0, 1, 0, 0)),
        act('y2', 'u4', 'view', new Date(2024, 0, 4, 0, 0))
      ]
      const dashboard = new ActivityDashboard(activities)
      const summary = dashboard.getUserSummary('u4')
      expect(summary).not.toBeNull()
      expect(summary!.actionsPerDay).toBe(0.67)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within inclusive date range for a user', () => {
      const activities = [
        act('1', 'u1', 'view', new Date(2024, 0, 1, 9, 0)),
        act('2', 'u1', 'click', new Date(2024, 0, 1, 9, 10)),
        act('3', 'u1', 'view', new Date(2024, 0, 1, 9, 15)),
        act('4', 'u1', 'purchase', new Date(2024, 0, 1, 10, 0)),
        act('5', 'u1', 'view', new Date(2024, 0, 2, 11, 0)),
        act('6', 'u1', 'click', new Date(2024, 0, 8, 12, 0)),
        act('7', 'u2', 'view', new Date(2024, 0, 2, 12, 0)) // other user
      ]
      const dashboard = new ActivityDashboard(activities)
      const start = new Date(2024, 0, 1, 9, 10)
      const end = new Date(2024, 0, 2, 11, 0)
      const filtered = dashboard.filterByDateRange('u1', start, end)
      const ids = filtered.map(a => a.id)
      expect(ids).toEqual(['2', '3', '4', '5'])
    })

    it('returns empty if no activities match user or date range', () => {
      const activities = [
        act('1', 'u1', 'view', new Date(2024, 0, 1, 9, 0))
      ]
      const dashboard = new ActivityDashboard(activities)
      const filtered = dashboard.filterByDateRange('u2', new Date(2024, 0, 1), new Date(2024, 0, 2))
      expect(filtered).toEqual([])
    })
  })

  describe('aggregateByAction', () => {
    it('aggregates actions with counts, percentages, and first/last occurrences and sorts by count desc', () => {
      const activities = [
        act('1', 'u1', 'view', new Date(2024, 0, 1, 9, 0)),
        act('2', 'u1', 'click', new Date(2024, 0, 1, 9, 10)),
        act('3', 'u1', 'view', new Date(2024, 0, 1, 9, 15)),
        act('4', 'u1', 'purchase', new Date(2024, 0, 1, 10, 0)),
        act('5', 'u1', 'view', new Date(2024, 0, 2, 11, 0)),
        act('6', 'u1', 'click', new Date(2024, 0, 8, 12, 0))
      ]
      const dashboard = new ActivityDashboard(activities)
      const groups = dashboard.aggregateByAction('u1')
      expect(groups.length).toBe(3)
      expect(groups[0].action).toBe('view')
      expect(groups[0].count).toBe(3)
      expect(groups[0].percentage).toBe(50)
      expect(groups[0].firstOccurrence.getTime()).toBe(new Date(2024, 0, 1, 9, 0).getTime())
      expect(groups[0].lastOccurrence.getTime()).toBe(new Date(2024, 0, 2, 11, 0).getTime())

      expect(groups[1].action).toBe('click')
      expect(groups[1].count).toBe(2)
      expect(groups[1].percentage).toBe(33.33)

      expect(groups[2].action).toBe('purchase')
      expect(groups[2].count).toBe(1)
      expect(groups[2].percentage).toBe(16.67)
    })

    it('returns empty array when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      const groups = dashboard.aggregateByAction('uX')
      expect(groups).toEqual([])
    })
  })

  describe('getTopActions and getTopActions_old', () => {
    it('getTopActions returns limited number of top actions', () => {
      const activities = [
        act('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
        act('2', 'u1', 'b', new Date(2024, 0, 1, 9, 10)),
        act('3', 'u1', 'a', new Date(2024, 0, 1, 9, 15)),
        act('4', 'u1', 'c', new Date(2024, 0, 1, 10, 0)),
        act('5', 'u1', 'a', new Date(2024, 0, 2, 11, 0)),
        act('6', 'u1', 'b', new Date(2024, 0, 8, 12, 0))
      ]
      const dashboard = new ActivityDashboard(activities)
      const top2 = dashboard.getTopActions('u1', 2)
      expect(top2.length).toBe(2)
      expect(top2[0].action).toBe('a')
      expect(top2[1].action).toBe('b')
    })

    it('getTopActions returns empty array when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      const top = dashboard.getTopActions('uX', 3)
      expect(top).toEqual([])
    })

    it('getTopActions_old ignores the limit parameter and returns all groups', () => {
      const activities = [
        act('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
        act('2', 'u1', 'b', new Date(2024, 0, 1, 9, 10)),
        act('3', 'u1', 'a', new Date(2024, 0, 1, 9, 15)),
        act('4', 'u1', 'c', new Date(2024, 0, 1, 10, 0))
      ]
      const dashboard = new ActivityDashboard(activities)
      const all = dashboard.getTopActions_old('u1', 1)
      const actions = all.map(g => g.action)
      expect(actions).toEqual(['a', 'b', 'c'])
      expect(all.length).toBe(3)
    })
  })

  describe('getActivityTrends', () => {
    it('groups by day and computes growth rate across periods', () => {
      const activities = [
        act('d1', 'u5', 'x', new Date(2024, 0, 1, 9, 0)),
        act('d2', 'u5', 'x', new Date(2024, 0, 1, 10, 0)),
        act('d3', 'u5', 'x', new Date(2024, 0, 1, 11, 0)),
        act('d4', 'u5', 'x', new Date(2024, 0, 2, 9, 0))
      ]
      const dashboard = new ActivityDashboard(activities)
      const trends = dashboard.getActivityTrends('u5', 'day')
      expect(trends.length).toBe(2)
      expect(trends[0].period).toBe('2024-01-01')
      expect(trends[0].count).toBe(3)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].period).toBe('2024-01-02')
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBe(-66.67)
    })

    it('groups by hour with proper keys and counts', () => {
      const activities = [
        act('h1', 'u6', 'x', new Date(2024, 0, 1, 9, 15)),
        act('h2', 'u6', 'x', new Date(2024, 0, 1, 9, 50)),
        act('h3', 'u6', 'y', new Date(2024, 0, 1, 10, 10))
      ]
      const dashboard = new ActivityDashboard(activities)
      const trends = dashboard.getActivityTrends('u6', 'hour')
      expect(trends.length).toBe(2)
      expect(trends[0].period).toBe('2024-01-01 09:00')
      expect(trends[0].count).toBe(2)
      expect(trends[1].period).toBe('2024-01-01 10:00')
      expect(trends[1].count).toBe(1)
    })

    it('groups by month with chronological period keys', () => {
      const activities = [
        act('m1', 'u7', 'x', new Date(2024, 0, 15, 9, 0)),
        act('m2', 'u7', 'x', new Date(2024, 1, 1, 12, 0))
      ]
      const dashboard = new ActivityDashboard(activities)
      const trends = dashboard.getActivityTrends('u7', 'month')
      expect(trends.map(t => t.period)).toEqual(['2024-01', '2024-02'])
      expect(trends.map(t => t.count)).toEqual([1, 1])
    })

    it('groups by week and keeps same week entries together', () => {
      const activities = [
        act('w1', 'u8', 'x', new Date(2024, 0, 3, 10, 0)), // same week
        act('w2', 'u8', 'x', new Date(2024, 0, 5, 12, 0)), // same week
        act('w3', 'u8', 'x', new Date(2024, 0, 10, 9, 0))  // next week
      ]
      const dashboard = new ActivityDashboard(activities)
      const trends = dashboard.getActivityTrends('u8', 'week')
      expect(trends.length).toBe(2)
      // First two should be in the same week bucket
      expect(trends[0].count).toBe(2)
      expect(trends[1].count).toBe(1)
      // Ensure period keys are different between weeks
      expect(trends[0].period).not.toBe(trends[1].period)
    })

    it('returns empty array when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      const trends = dashboard.getActivityTrends('nope', 'day')
      expect(trends).toEqual([])
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when user has no activity summary', () => {
      const dashboard = new ActivityDashboard([])
      expect(dashboard.calculateEngagementScore('none')).toBe(0)
    })

    it('calculates engagement score with expected rounding', () => {
      const activities = [
        act('1', 'u1', 'view', new Date(2024, 0, 1, 9, 0)),
        act('2', 'u1', 'click', new Date(2024, 0, 1, 9, 10)),
        act('3', 'u1', 'view', new Date(2024, 0, 1, 9, 15)),
        act('4', 'u1', 'purchase', new Date(2024, 0, 1, 10, 0)),
        act('5', 'u1', 'view', new Date(2024, 0, 2, 11, 0)),
        act('6', 'u1', 'click', new Date(2024, 0, 8, 12, 0))
      ]
      const dashboard = new ActivityDashboard(activities)
      // volume: (6/100)*30 = 1.8
      // diversity: (3/10)*30 = 9
      // frequency: (0.75/5)*40 = 6
      // total = 16.8 -> rounded to 16.8
      expect(dashboard.calculateEngagementScore('u1')).toBe(16.8)
    })

    it('caps engagement score components to a maximum of 100 total', () => {
      const manyActs: any[] = []
      for (let i = 0; i < 200; i++) {
        const action = `a${i % 15}` // 15 unique actions -> diversity capped
        manyActs.push(act(`id-${i}`, 'u9', action, new Date(2024, 0, 1, 0, 0, i)))
      }
      const dashboard = new ActivityDashboard(manyActs)
      const score = dashboard.calculateEngagementScore('u9')
      expect(score).toBe(100)
    })
  })
})