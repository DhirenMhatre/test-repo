import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

const makeActivity = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard', () => {
  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.getUserSummary('u1')).toBeNull()
    })

    it('computes totals, unique actions, most frequent, actionsPerDay and averageActionsPerSession (same day)', () => {
      const d1 = new Date(2024, 0, 1, 10, 0, 0)
      const d2 = new Date(2024, 0, 1, 10, 15, 0)
      const d3 = new Date(2024, 0, 1, 11, 0, 0) // 45 min after previous -> new session
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'login', d1),
        makeActivity('2', 'u1', 'click', d2),
        makeActivity('3', 'u1', 'click', d3)
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(3)
      expect(summary!.uniqueActions).toBe(2)
      expect(summary!.mostFrequentAction).toBe('click')
      // same day -> daysActive = 1; actionsPerDay = 3/1 = 3.00
      expect(summary!.actionsPerDay).toBe(3)
      // Sessions: [10:00, 10:15] in same session; 11:00 starts new session => 2 sessions; avg = 1.5
      expect(summary!.averageActionsPerSession).toBe(1.5)
    })

    it('computes actionsPerDay across multiple days using ceil of day span', () => {
      // First activity Jan 1 10:00, last activity Jan 3 09:00
      const a1 = new Date(2024, 0, 1, 10, 0, 0)
      const a2 = new Date(2024, 0, 2, 12, 0, 0)
      const a3 = new Date(2024, 0, 3, 9, 0, 0)
      const a4 = new Date(2024, 0, 2, 13, 0, 0)
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'view', a1),
        makeActivity('2', 'u1', 'click', a2),
        makeActivity('3', 'u1', 'view', a3),
        makeActivity('4', 'u1', 'share', a4)
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      // Span is less than 48 hours but more than 24 -> ceil to 2 days
      expect(summary!.totalActions).toBe(4)
      expect(summary!.actionsPerDay).toBe(2) // 4 / 2 days
    })

    it('averageActionsPerSession treats exactly 30 minutes as same session', () => {
      const t1 = new Date(2024, 5, 10, 10, 0, 0)
      const t2 = new Date(2024, 5, 10, 10, 30, 0) // exactly 30 min, not a new session
      const t3 = new Date(2024, 5, 10, 11, 0, 0)  // another 30 min, still not a new session
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'a', t1),
        makeActivity('2', 'u1', 'b', t2),
        makeActivity('3', 'u1', 'c', t3)
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.averageActionsPerSession).toBe(3) // 3 actions, 1 session
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.getActivityTrends('uX')).toEqual([])
    })

    it('groups by day by default and computes growth rate between periods', () => {
      const d1 = new Date(2024, 0, 1, 9, 0, 0)  // 2024-01-01
      const d2 = new Date(2024, 0, 2, 10, 0, 0) // 2024-01-02
      const d3 = new Date(2024, 0, 2, 11, 0, 0) // 2024-01-02
      const d4 = new Date(2024, 0, 2, 12, 0, 0) // 2024-01-02
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'a', d1),
        makeActivity('2', 'u1', 'a', d2),
        makeActivity('3', 'u1', 'b', d3),
        makeActivity('4', 'u1', 'b', d4)
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('u1') // default 'day'
      expect(trends.length).toBe(2)
      expect(trends[0].period).toBe('2024-01-01')
      expect(trends[0].count).toBe(1)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].period).toBe('2024-01-02')
      expect(trends[1].count).toBe(3)
      // growth from 1 to 3 => 200%
      expect(trends[1].growthRate).toBe(200)
    })

    it('groups by hour correctly', () => {
      const h1a = new Date(2024, 2, 10, 14, 5, 0)  // 2024-03-10 14:00
      const h1b = new Date(2024, 2, 10, 14, 30, 0) // same hour
      const h2 = new Date(2024, 2, 10, 15, 0, 0)   // next hour
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'x', h1a),
        makeActivity('2', 'u1', 'y', h1b),
        makeActivity('3', 'u1', 'z', h2)
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('u1', 'hour')
      expect(trends.length).toBe(2)
      expect(trends[0].period).toBe('2024-03-10 14:00')
      expect(trends[0].count).toBe(2)
      expect(trends[1].period).toBe('2024-03-10 15:00')
      expect(trends[1].count).toBe(1)
      // growth from 2 to 1 => ((1-2)/2)*100 = -50
      expect(trends[1].growthRate).toBe(-50)
    })

    it('groups by week using its internal week number calculation', () => {
      // Jan 1, 2024 (Mon) -> week 01; Jan 8, 2024 (Mon) -> week 02 (based on implementation)
      const w1 = new Date(2024, 0, 1, 10, 0, 0)
      const w2 = new Date(2024, 0, 8, 10, 0, 0)
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'a', w1),
        makeActivity('2', 'u1', 'a', w2),
        makeActivity('3', 'u1', 'b', w2)
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('u1', 'week')
      expect(trends.length).toBe(2)
      expect(trends[0].period).toBe('2024-W01')
      expect(trends[0].count).toBe(1)
      expect(trends[1].period).toBe('2024-W02')
      expect(trends[1].count).toBe(2)
      expect(trends[1].growthRate).toBe(100) // from 1 to 2
    })

    it('groups by month correctly', () => {
      const m1 = new Date(2024, 0, 15, 9, 0, 0)  // Jan
      const m2 = new Date(2024, 1, 10, 9, 0, 0)  // Feb
      const m3 = new Date(2024, 1, 12, 9, 0, 0)  // Feb
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'a', m1),
        makeActivity('2', 'u1', 'a', m2),
        makeActivity('3', 'u1', 'a', m3)
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('u1', 'month')
      expect(trends).toEqual([
        { period: '2024-01', count: 1, growthRate: 0 },
        { period: '2024-02', count: 2, growthRate: 100 }
      ])
    })
  })

  describe('filterByDateRange', () => {
    it('includes activities on the start and end boundaries (inclusive)', () => {
      const start = new Date(2024, 4, 1, 0, 0, 0)
      const end = new Date(2024, 4, 2, 0, 0, 0)
      const before = new Date(2024, 3, 30, 23, 59, 59)
      const after = new Date(2024, 4, 2, 0, 0, 1)
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'x', before),
        makeActivity('2', 'u1', 'x', start),  // included
        makeActivity('3', 'u1', 'x', end),    // included
        makeActivity('4', 'u1', 'x', after),
        makeActivity('5', 'u2', 'x', start)
      ]
      const dash = new ActivityDashboard(activities)
      const filtered = dash.filterByDateRange('u1', start, end)
      expect(filtered.map(a => a.id)).toEqual(['2', '3'])
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array for user with no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.aggregateByAction('u1')).toEqual([])
    })

    it('aggregates counts, percentage, first/last occurrence and sorts by count desc', () => {
      const t1 = new Date(2024, 6, 1, 9, 0, 0)
      const t2 = new Date(2024, 6, 1, 10, 0, 0)
      const t3 = new Date(2024, 6, 2, 9, 0, 0)
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'click', t1),
        makeActivity('2', 'u1', 'click', t3),
        makeActivity('3', 'u1', 'view', t2)
      ]
      const dash = new ActivityDashboard(activities)
      const groups = dash.aggregateByAction('u1')
      expect(groups.length).toBe(2)
      // click has 2/3 = 66.67%
      expect(groups[0].action).toBe('click')
      expect(groups[0].count).toBe(2)
      expect(groups[0].percentage).toBe(66.67)
      expect(groups[0].firstOccurrence.getTime()).toBe(t1.getTime())
      expect(groups[0].lastOccurrence.getTime()).toBe(t3.getTime())
      // view has 1/3 = 33.33%
      expect(groups[1].action).toBe('view')
      expect(groups[1].count).toBe(1)
      expect(groups[1].percentage).toBe(33.33)
      expect(groups[1].firstOccurrence.getTime()).toBe(t2.getTime())
      expect(groups[1].lastOccurrence.getTime()).toBe(t2.getTime())
    })
  })

  describe('getTopActions_old', () => {
    it('returns all groups sorted by count and ignores the limit parameter', () => {
      const t1 = new Date(2024, 1, 1, 10, 0, 0)
      const t2 = new Date(2024, 1, 1, 11, 0, 0)
      const t3 = new Date(2024, 1, 2, 12, 0, 0)
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'a', t1),
        makeActivity('2', 'u1', 'a', t2),
        makeActivity('3', 'u1', 'b', t3),
        makeActivity('4', 'u2', 'a', t1)
      ]
      const dash = new ActivityDashboard(activities)
      const groups = dash.getTopActions_old('u1', 1)
      expect(groups.length).toBe(2) // returns all unique actions for user u1
      expect(groups[0].action).toBe('a')
      expect(groups[0].count).toBe(2)
      expect(groups[0].firstOccurrence.getTime()).toBe(t1.getTime())
      expect(groups[0].lastOccurrence.getTime()).toBe(t2.getTime())
      expect(groups[1].action).toBe('b')
      expect(groups[1].count).toBe(1)
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions by count', () => {
      const t = new Date(2024, 3, 1, 10, 0, 0)
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'a', t),
        makeActivity('2', 'u1', 'a', t),
        makeActivity('3', 'u1', 'b', t),
        makeActivity('4', 'u1', 'c', t),
        makeActivity('5', 'u1', 'c', t),
        makeActivity('6', 'u1', 'c', t)
      ]
      const dash = new ActivityDashboard(activities)
      const top2 = dash.getTopActions('u1', 2)
      expect(top2.length).toBe(2)
      expect(top2[0].action).toBe('c')
      expect(top2[0].count).toBe(3)
      expect(top2[1].action).toBe('a')
      expect(top2[1].count).toBe(2)
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when user has no activity', () => {
      const dash = new ActivityDashboard([])
      expect(dash.calculateEngagementScore('u1')).toBe(0)
    })

    it('computes score based on volume, diversity, and frequency', () => {
      // 3 actions across same day => actionsPerDay = 3
      const d1 = new Date(2024, 0, 1, 10, 0, 0)
      const d2 = new Date(2024, 0, 1, 11, 0, 0)
      const d3 = new Date(2024, 0, 1, 12, 0, 0)
      const activities: Activity[] = [
        makeActivity('1', 'u1', 'x', d1),
        makeActivity('2', 'u1', 'y', d2),
        makeActivity('3', 'u1', 'y', d3)
      ]
      const dash = new ActivityDashboard(activities)
      const score = dash.calculateEngagementScore('u1')
      // volumeScore = min(3/100,1)*30 = 0.9
      // diversityScore = min(2/10,1)*30 = 6
      // frequencyScore = min(3/5,1)*40 = 24
      // total = 30.9
      expect(score).toBe(30.9)
    })
  })
})