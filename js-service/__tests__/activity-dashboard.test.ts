import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

const d = (y: number, m: number, day: number, h = 0, min = 0) => new Date(y, m - 1, day, h, min, 0, 0)

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard', () => {
  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      const summary = dashboard.getUserSummary('uX')
      expect(summary).toBeNull()
    })

    it('computes correct summary for a user with multiple activities across days and sessions', () => {
      const activities = [
        { id: 'a1', user_id: 'u1', action: 'login', timestamp: d(2023, 1, 1, 9, 0) },
        { id: 'a2', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 9, 10) },
        { id: 'a3', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 9, 20) },
        { id: 'a4', user_id: 'u1', action: 'click', timestamp: d(2023, 1, 1, 10, 0) },
        { id: 'a5', user_id: 'u1', action: 'logout', timestamp: d(2023, 1, 1, 10, 15) },
        { id: 'a6', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 2, 10, 0) },
        { id: 'a7', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 2, 10, 31) }
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const summary = dashboard.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(7)
      expect(summary!.uniqueActions).toBe(4)
      expect(summary!.mostFrequentAction).toBe('view')
      expect(summary!.actionsPerDay).toBeCloseTo(3.5, 5)
      expect(summary!.averageActionsPerSession).toBeCloseTo(1.75, 5)
    })

    it('treats exactly 30 minutes gap as same session', () => {
      const activities = [
        { id: 'b1', user_id: 'u2', action: 'view', timestamp: d(2023, 3, 10, 12, 0) },
        { id: 'b2', user_id: 'u2', action: 'view', timestamp: d(2023, 3, 10, 12, 30) } // exactly 30 min
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const summary = dashboard.getUserSummary('u2')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(2)
      expect(summary!.uniqueActions).toBe(1)
      // same day => daysActive = 1
      expect(summary!.actionsPerDay).toBeCloseTo(2, 5)
      // one session => average 2
      expect(summary!.averageActionsPerSession).toBeCloseTo(2, 5)
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      const trends = dashboard.getActivityTrends('uX')
      expect(trends).toEqual([])
    })

    it('groups by day and calculates growth rate correctly', () => {
      const activities = [
        { id: 'c1', user_id: 'u1', action: 'a', timestamp: d(2023, 4, 1, 9, 0) },  // day1: 1
        { id: 'c2', user_id: 'u1', action: 'b', timestamp: d(2023, 4, 2, 8, 0) },  // day2: 2
        { id: 'c3', user_id: 'u1', action: 'b', timestamp: d(2023, 4, 2, 9, 0) },
        { id: 'c4', user_id: 'u1', action: 'c', timestamp: d(2023, 4, 3, 10, 0) }  // day3: 1
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const trends = dashboard.getActivityTrends('u1', 'day')
      expect(trends).toHaveLength(3)
      expect(trends[0]).toEqual({ period: '2023-04-01', count: 1, growthRate: 0 })
      expect(trends[1]).toEqual({ period: '2023-04-02', count: 2, growthRate: 100 })
      expect(trends[2]).toEqual({ period: '2023-04-03', count: 1, growthRate: -50 })
    })

    it('groups by hour and sorts periods correctly with proper labels', () => {
      const activities = [
        { id: 'd1', user_id: 'u1', action: 'a', timestamp: d(2023, 5, 5, 9, 5) },
        { id: 'd2', user_id: 'u1', action: 'b', timestamp: d(2023, 5, 5, 9, 40) },
        { id: 'd3', user_id: 'u1', action: 'c', timestamp: d(2023, 5, 5, 10, 0) },
        { id: 'd4', user_id: 'u1', action: 'd', timestamp: d(2023, 5, 6, 10, 30) }
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const trends = dashboard.getActivityTrends('u1', 'hour')
      expect(trends.map(t => t.period)).toEqual(['2023-05-05 09:00', '2023-05-05 10:00', '2023-05-06 10:00'])
      expect(trends.map(t => t.count)).toEqual([2, 1, 1])
      expect(trends[1].growthRate).toBeCloseTo(-50, 2)
      expect(trends[2].growthRate).toBe(0)
    })

    it('groups by month', () => {
      const activities = [
        { id: 'e1', user_id: 'u1', action: 'a', timestamp: d(2023, 1, 31, 23, 59) },
        { id: 'e2', user_id: 'u1', action: 'b', timestamp: d(2023, 2, 1, 0, 1) },
        { id: 'e3', user_id: 'u1', action: 'b', timestamp: d(2023, 2, 10, 12, 0) }
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const trends = dashboard.getActivityTrends('u1', 'month')
      expect(trends).toEqual([
        { period: '2023-01', count: 1, growthRate: 0 },
        { period: '2023-02', count: 2, growthRate: 100 }
      ])
    })

    it('groups by week with expected week format and correct counts', () => {
      const activities = [
        { id: 'f1', user_id: 'u1', action: 'a', timestamp: d(2023, 1, 1, 9, 0) }, // Jan 1, 2023
        { id: 'f2', user_id: 'u1', action: 'b', timestamp: d(2023, 1, 2, 9, 0) }  // Jan 2, 2023
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const trends = dashboard.getActivityTrends('u1', 'week')
      // Both should be in W01 per the implementation
      expect(trends).toHaveLength(1)
      expect(trends[0].period).toBe('2023-W01')
      expect(trends[0].count).toBe(2)
      expect(trends[0].growthRate).toBe(0)
    })
  })

  describe('filterByDateRange', () => {
    it('returns only activities within range, inclusive of boundaries', () => {
      const activities = [
        { id: 'g1', user_id: 'u1', action: 'x', timestamp: d(2023, 6, 1, 9, 0) },
        { id: 'g2', user_id: 'u1', action: 'y', timestamp: d(2023, 6, 1, 9, 10) },
        { id: 'g3', user_id: 'u1', action: 'z', timestamp: d(2023, 6, 1, 9, 20) },
        { id: 'g4', user_id: 'u1', action: 'w', timestamp: d(2023, 6, 1, 10, 0) },
        { id: 'g5', user_id: 'u1', action: 'v', timestamp: d(2023, 6, 1, 10, 15) }
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const result = dashboard.filterByDateRange('u1', d(2023, 6, 1, 9, 10), d(2023, 6, 1, 10, 0))
      expect(result.map(r => r.id)).toEqual(['g2', 'g3', 'g4'])
    })

    it('returns empty if no activities match', () => {
      const activities = [
        { id: 'h1', user_id: 'u1', action: 'a', timestamp: d(2023, 7, 1, 9, 0) }
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const result = dashboard.filterByDateRange('u1', d(2023, 7, 2, 0, 0), d(2023, 7, 2, 23, 59))
      expect(result).toEqual([])
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      expect(dashboard.aggregateByAction('uX')).toEqual([])
    })

    it('aggregates counts, percentages, first/last occurrence, and sorts by count desc', () => {
      const activities = [
        { id: 'i1', user_id: 'u1', action: 'login', timestamp: d(2023, 1, 1, 9, 0) },
        { id: 'i2', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 9, 10) },
        { id: 'i3', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 9, 20) },
        { id: 'i4', user_id: 'u1', action: 'click', timestamp: d(2023, 1, 1, 10, 0) },
        { id: 'i5', user_id: 'u1', action: 'logout', timestamp: d(2023, 1, 1, 10, 15) },
        { id: 'i6', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 2, 10, 0) },
        { id: 'i7', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 2, 10, 31) }
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const groups = dashboard.aggregateByAction('u1')
      expect(groups).toHaveLength(4)
      // top group is 'view'
      expect(groups[0].action).toBe('view')
      expect(groups[0].count).toBe(4)
      expect(groups[0].percentage).toBeCloseTo(57.14, 2)
      expect(groups[0].firstOccurrence.getTime()).toBe(d(2023, 1, 1, 9, 10).getTime())
      expect(groups[0].lastOccurrence.getTime()).toBe(d(2023, 1, 2, 10, 31).getTime())
      // check one of the single-count actions
      const loginGroup = groups.find(g => g.action === 'login')!
      expect(loginGroup.count).toBe(1)
      expect(loginGroup.percentage).toBeCloseTo(14.29, 2)
      expect(loginGroup.firstOccurrence.getTime()).toBe(d(2023, 1, 1, 9, 0).getTime())
      expect(loginGroup.lastOccurrence.getTime()).toBe(d(2023, 1, 1, 9, 0).getTime())
    })
  })

  describe('getTopActions_old', () => {
    it('returns all grouped actions sorted by count and ignores the limit parameter', () => {
      const activities = [
        { id: 'j1', user_id: 'u1', action: 'a', timestamp: d(2023, 8, 1, 9, 0) },
        { id: 'j2', user_id: 'u1', action: 'b', timestamp: d(2023, 8, 1, 9, 10) },
        { id: 'j3', user_id: 'u1', action: 'b', timestamp: d(2023, 8, 1, 9, 20) },
        { id: 'j4', user_id: 'u1', action: 'c', timestamp: d(2023, 8, 1, 10, 0) },
        { id: 'j5', user_id: 'u1', action: 'd', timestamp: d(2023, 8, 1, 10, 15) }
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const result = dashboard.getTopActions_old('u1', 2)
      expect(result).toHaveLength(4)
      expect(result[0].action).toBe('b')
      expect(result[0].count).toBe(2)
      const map = Object.fromEntries(result.map(r => [r.action, r.count]))
      expect(map).toEqual({ b: 2, a: 1, c: 1, d: 1 })
    })
  })

  describe('getTopActions', () => {
    it('returns only the top N actions by count', () => {
      const activities = [
        { id: 'k1', user_id: 'u1', action: 'x', timestamp: d(2023, 9, 1, 9, 0) },
        { id: 'k2', user_id: 'u1', action: 'y', timestamp: d(2023, 9, 1, 9, 10) },
        { id: 'k3', user_id: 'u1', action: 'y', timestamp: d(2023, 9, 1, 9, 20) },
        { id: 'k4', user_id: 'u1', action: 'z', timestamp: d(2023, 9, 1, 10, 0) },
        { id: 'k5', user_id: 'u1', action: 'w', timestamp: d(2023, 9, 1, 10, 15) }
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const top2 = dashboard.getTopActions('u1', 2)
      expect(top2).toHaveLength(2)
      expect(top2[0].action).toBe('y')
      // For ties, the next one will be the first encountered among singletons
      expect(['x', 'z', 'w']).toContain(top2[1].action)
    })

    it('defaults to limit 5 but returns less if fewer unique actions exist', () => {
      const activities = [
        { id: 'l1', user_id: 'u1', action: 'a', timestamp: d(2023, 10, 1, 9, 0) },
        { id: 'l2', user_id: 'u1', action: 'a', timestamp: d(2023, 10, 1, 9, 10) },
        { id: 'l3', user_id: 'u1', action: 'b', timestamp: d(2023, 10, 1, 9, 20) }
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const top = dashboard.getTopActions('u1')
      expect(top).toHaveLength(2)
      expect(top[0].action).toBe('a')
      expect(top[1].action).toBe('b')
    })

    it('returns empty array when user has no activities', () => {
      const dashboard = new ActivityDashboard([])
      expect(dashboard.getTopActions('uX')).toEqual([])
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 for users with no activities', () => {
      const dashboard = new ActivityDashboard([])
      expect(dashboard.calculateEngagementScore('none')).toBe(0)
    })

    it('calculates expected score based on volume, diversity, and frequency', () => {
      const activities = [
        { id: 'm1', user_id: 'u1', action: 'login', timestamp: d(2023, 1, 1, 9, 0) },
        { id: 'm2', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 9, 10) },
        { id: 'm3', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 1, 9, 20) },
        { id: 'm4', user_id: 'u1', action: 'click', timestamp: d(2023, 1, 1, 10, 0) },
        { id: 'm5', user_id: 'u1', action: 'logout', timestamp: d(2023, 1, 1, 10, 15) },
        { id: 'm6', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 2, 10, 0) },
        { id: 'm7', user_id: 'u1', action: 'view', timestamp: d(2023, 1, 2, 10, 31) }
      ]
      const dashboard = new ActivityDashboard(activities as any)
      const score = dashboard.calculateEngagementScore('u1')
      // volume: 7/100*30 = 2.1
      // diversity: 4/10*30 = 12
      // frequency: (3.5/5)*40 = 28
      // total = 42.1 -> toFixed(2)
      expect(score).toBeCloseTo(42.1, 5)
    })
  })
})