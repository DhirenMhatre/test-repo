import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../../../js-service/src/activity-dashboard'
import type { Activity } from '../../../js-service/src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

let idCounter = 0
function mk(user_id: string, action: string, y: number, m: number, d: number, h: number, min: number): Activity {
  return {
    id: `${user_id}-${action}-${y}-${m + 1}-${d}-${h}-${min}-${idCounter++}`,
    user_id,
    action,
    timestamp: new Date(y, m, d, h, min)
  }
}

describe('ActivityDashboard', () => {
  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.getUserSummary('unknown')).toBeNull()
    })

    it('computes correct summary including sessions and rounding', () => {
      const activities: Activity[] = [
        mk('userS', 'view', 2023, 0, 1, 10, 0),
        mk('userS', 'click', 2023, 0, 1, 10, 20),
        mk('userS', 'view', 2023, 0, 1, 10, 51), // >30 min gap -> new session
        mk('userS', 'click', 2023, 0, 1, 11, 20),
        mk('userS', 'view', 2023, 0, 2, 11, 20) // next day -> new session
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('userS')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(5)
      expect(summary!.uniqueActions).toBe(2)
      expect(summary!.mostFrequentAction).toBe('view')
      expect(summary!.actionsPerDay).toBeCloseTo(2.5, 5) // 5 actions over 2 days (ceil)
      expect(summary!.averageActionsPerSession).toBeCloseTo(1.67, 2) // 5 actions / 3 sessions
    })

    it('actionsPerDay equals total when activities occur on the same day', () => {
      const activities: Activity[] = [
        mk('uSameDay', 'a', 2023, 0, 1, 10, 0),
        mk('uSameDay', 'a', 2023, 0, 1, 10, 10),
        mk('uSameDay', 'b', 2023, 0, 1, 10, 20)
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('uSameDay')
      expect(summary).not.toBeNull()
      expect(summary!.actionsPerDay).toBeCloseTo(3, 5)
    })
  })

  describe('getActivityTrends (day/hour/week/month)', () => {
    const activitiesU1: Activity[] = [
      mk('u1', 'A', 2023, 0, 1, 10, 0),
      mk('u1', 'B', 2023, 0, 1, 10, 5),
      mk('u1', 'A', 2023, 0, 1, 10, 20),
      mk('u1', 'C', 2023, 0, 1, 11, 0),
      mk('u1', 'A', 2023, 0, 1, 12, 0),
      mk('u1', 'B', 2023, 0, 2, 9, 0),
      mk('u1', 'B', 2023, 0, 2, 13, 45),
      mk('u1', 'D', 2023, 0, 3, 10, 15),
      mk('u1', 'E', 2023, 0, 10, 10, 0),
      mk('u1', 'A', 2023, 1, 1, 10, 0),
      mk('u2', 'Z', 2023, 0, 1, 10, 0) // other user noise
    ]
    const dash = new ActivityDashboard(activitiesU1)

    it('groups by day with correct counts and growth rates', () => {
      const trends = dash.getActivityTrends('u1', 'day')
      expect(trends.length).toBe(5)
      expect(trends[0]).toEqual({ period: '2023-01-01', count: 5, growthRate: 0 })
      expect(trends[1].period).toBe('2023-01-02')
      expect(trends[1].count).toBe(2)
      expect(trends[1].growthRate).toBeCloseTo(-60.0, 2)
      expect(trends[2].period).toBe('2023-01-03')
      expect(trends[2].count).toBe(1)
      expect(trends[2].growthRate).toBeCloseTo(-50.0, 2)
      expect(trends[3]).toEqual({ period: '2023-01-10', count: 1, growthRate: 0 })
      expect(trends[4]).toEqual({ period: '2023-02-01', count: 1, growthRate: 0 })
    })

    it('groups by hour with correct format and growth rates', () => {
      const trends = dash.getActivityTrends('u1', 'hour')
      // First three hours on 2023-01-01
      expect(trends[0]).toEqual({ period: '2023-01-01 10:00', count: 3, growthRate: 0 })
      expect(trends[1].period).toBe('2023-01-01 11:00')
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBeCloseTo(-66.67, 2)
      expect(trends[2].period).toBe('2023-01-01 12:00')
      expect(trends[2].count).toBe(1)
      expect(trends[2].growthRate).toBeCloseTo(0, 5)
    })

    it('groups by week with correct counts and growth', () => {
      const trends = dash.getActivityTrends('u1', 'week')
      expect(trends.map(t => t.period)).toEqual(['2023-W01', '2023-W02', '2023-W05'])
      expect(trends[0].count).toBe(8) // Jan1,2,3
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].count).toBe(1) // Jan10
      expect(trends[1].growthRate).toBeCloseTo(-87.5, 2)
      expect(trends[2].count).toBe(1) // Feb1
      expect(trends[2].growthRate).toBeCloseTo(0, 5)
    })

    it('groups by month with correct counts and growth', () => {
      const trends = dash.getActivityTrends('u1', 'month')
      expect(trends.map(t => t.period)).toEqual(['2023-01', '2023-02'])
      expect(trends[0].count).toBe(9)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBeCloseTo(-88.89, 2)
    })

    it('returns empty trends when user has no activities', () => {
      const trends = dash.getActivityTrends('nope', 'day')
      expect(trends).toEqual([])
    })
  })

  describe('filterByDateRange', () => {
    it('includes activities on boundaries (inclusive)', () => {
      const activities: Activity[] = [
        mk('u1', 'A', 2023, 0, 1, 10, 0),
        mk('u1', 'B', 2023, 0, 1, 10, 5),
        mk('u1', 'A', 2023, 0, 1, 12, 0),
        mk('u1', 'B', 2023, 0, 2, 9, 0),
        mk('u1', 'B', 2023, 0, 2, 13, 45)
      ]
      const dash = new ActivityDashboard(activities)
      const start = new Date(2023, 0, 1, 10, 0)
      const end = new Date(2023, 0, 2, 9, 0)
      const filtered = dash.filterByDateRange('u1', start, end)
      expect(filtered.length).toBe(4)
      expect(filtered.find(a => a.timestamp.getTime() === start.getTime())).toBeDefined()
      expect(filtered.find(a => a.timestamp.getTime() === end.getTime())).toBeDefined()
    })

    it('returns empty array when nothing in the range or user mismatch', () => {
      const activities: Activity[] = [
        mk('u1', 'A', 2023, 0, 1, 10, 0),
        mk('u1', 'A', 2023, 0, 3, 10, 0)
      ]
      const dash = new ActivityDashboard(activities)
      const filtered = dash.filterByDateRange('u2', new Date(2023, 0, 1), new Date(2023, 0, 10))
      expect(filtered).toEqual([])

      const filtered2 = dash.filterByDateRange('u1', new Date(2023, 1, 1), new Date(2023, 1, 2))
      expect(filtered2).toEqual([])
    })
  })

  describe('aggregateByAction', () => {
    const activitiesU1: Activity[] = [
      mk('u1', 'A', 2023, 0, 1, 10, 0),
      mk('u1', 'B', 2023, 0, 1, 10, 5),
      mk('u1', 'A', 2023, 0, 1, 10, 20),
      mk('u1', 'C', 2023, 0, 1, 11, 0),
      mk('u1', 'A', 2023, 0, 1, 12, 0),
      mk('u1', 'B', 2023, 0, 2, 9, 0),
      mk('u1', 'B', 2023, 0, 2, 13, 45),
      mk('u1', 'D', 2023, 0, 3, 10, 15),
      mk('u1', 'E', 2023, 0, 10, 10, 0),
      mk('u1', 'A', 2023, 1, 1, 10, 0)
    ]

    it('returns empty when user has no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.aggregateByAction('nobody')).toEqual([])
    })

    it('aggregates counts, percentages, and first/last occurrence correctly and sorts by count', () => {
      const dash = new ActivityDashboard(activitiesU1)
      const groups = dash.aggregateByAction('u1')
      expect(groups.length).toBe(5)
      const top = groups[0]
      expect(top.action).toBe('A')
      expect(top.count).toBe(4)
      expect(top.percentage).toBeCloseTo(40.0, 2)
      expect(top.firstOccurrence.getTime()).toBe(new Date(2023, 0, 1, 10, 0).getTime())
      expect(top.lastOccurrence.getTime()).toBe(new Date(2023, 1, 1, 10, 0).getTime())

      const second = groups[1]
      expect(second.action).toBe('B')
      expect(second.count).toBe(3)
      expect(second.percentage).toBeCloseTo(30.0, 2)
      expect(second.firstOccurrence.getTime()).toBe(new Date(2023, 0, 1, 10, 5).getTime())
      expect(second.lastOccurrence.getTime()).toBe(new Date(2023, 0, 2, 13, 45).getTime())
    })

    it('includes actions with single occurrence with correct percentage and dates', () => {
      const dash = new ActivityDashboard(activitiesU1)
      const groups = dash.aggregateByAction('u1')
      const groupC = groups.find(g => g.action === 'C')!
      expect(groupC).toBeDefined()
      expect(groupC.count).toBe(1)
      expect(groupC.percentage).toBeCloseTo(10.0, 2)
      expect(groupC.firstOccurrence.getTime()).toBe(new Date(2023, 0, 1, 11, 0).getTime())
      expect(groupC.lastOccurrence.getTime()).toBe(new Date(2023, 0, 1, 11, 0).getTime())
    })
  })

  describe('getTopActions', () => {
    const activitiesU1: Activity[] = [
      mk('u1', 'A', 2023, 0, 1, 10, 0),
      mk('u1', 'B', 2023, 0, 1, 10, 5),
      mk('u1', 'A', 2023, 0, 1, 10, 20),
      mk('u1', 'C', 2023, 0, 1, 11, 0),
      mk('u1', 'A', 2023, 0, 1, 12, 0),
      mk('u1', 'B', 2023, 0, 2, 9, 0),
      mk('u1', 'B', 2023, 0, 2, 13, 45),
      mk('u1', 'D', 2023, 0, 3, 10, 15),
      mk('u1', 'E', 2023, 0, 10, 10, 0),
      mk('u1', 'A', 2023, 1, 1, 10, 0)
    ]

    it('returns default top 5 actions', () => {
      const dash = new ActivityDashboard(activitiesU1)
      const top = dash.getTopActions('u1')
      expect(top.length).toBe(5)
      expect(top[0].action).toBe('A')
    })

    it('respects custom limit and ordering by count', () => {
      const dash = new ActivityDashboard(activitiesU1)
      const top2 = dash.getTopActions('u1', 2)
      expect(top2.length).toBe(2)
      expect(top2[0].action).toBe('A')
      expect(top2[1].action).toBe('B')
    })

    it('returns empty array when limit is 0', () => {
      const dash = new ActivityDashboard(activitiesU1)
      const top0 = dash.getTopActions('u1', 0)
      expect(top0).toEqual([])
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when user has no activity', () => {
      const dash = new ActivityDashboard([])
      expect(dash.calculateEngagementScore('nobody')).toBe(0)
    })

    it('caps scores at 100 with high volume, diversity, and frequency', () => {
      const base = new Date(2023, 0, 1, 10, 0)
      const activities: Activity[] = []
      for (let i = 0; i < 120; i++) {
        activities.push({
          id: `cap-${i}`,
          user_id: 'cap',
          action: `a${i % 12}`, // 12 unique actions
          timestamp: new Date(base.getFullYear(), base.getMonth(), base.getDate(), base.getHours(), base.getMinutes() + i)
        })
      }
      const dash = new ActivityDashboard(activities)
      const score = dash.calculateEngagementScore('cap')
      expect(score).toBeCloseTo(100.0, 2)
    })

    it('uses rounded actionsPerDay in frequency score computation', () => {
      const activities: Activity[] = [
        // Day 1: 3 actions
        mk('round', 'a', 2023, 0, 1, 10, 0),
        mk('round', 'b', 2023, 0, 1, 10, 1),
        mk('round', 'a', 2023, 0, 1, 10, 2),
        // Day 2: 2 actions
        mk('round', 'a', 2023, 0, 2, 10, 0),
        mk('round', 'b', 2023, 0, 2, 10, 1),
        // Day 3: 2 actions slightly over 2-day window to force daysActive=3
        mk('round', 'a', 2023, 0, 3, 10, 1),
        mk('round', 'a', 2023, 0, 3, 10, 2)
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('round')
      expect(summary).not.toBeNull()
      expect(summary!.actionsPerDay).toBeCloseTo(2.33, 2) // 7/3 rounded to 2 decimals
      const score = dash.calculateEngagementScore('round')
      // volume: 7/100*30=2.1, diversity: 2/10*30=6, frequency: 2.33/5*40=18.64 => total 26.74
      expect(score).toBeCloseTo(26.74, 2)
    })
  })
})