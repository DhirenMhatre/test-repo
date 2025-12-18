import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

type Act = ConstructorParameters<typeof ActivityDashboard>[0][number]

const makeActivity = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Act => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata
})

describe('ActivityDashboard', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('getUserSummary', () => {
    it('returns null when no activities for user', () => {
      const dash = new ActivityDashboard([])
      const summary = dash.getUserSummary('uX')
      expect(summary).toBeNull()
    })

    it('computes totals, uniques, actionsPerDay, most frequent, and average per session', () => {
      const activities: Act[] = [
        makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
        makeActivity('3', 'u1', 'click', new Date(2024, 0, 1, 9, 20)),
        makeActivity('4', 'u1', 'view', new Date(2024, 0, 1, 10, 0)), // 40 min gap -> new session
        makeActivity('5', 'u1', 'view', new Date(2024, 0, 2, 9, 0)), // next day -> new session
        makeActivity('6', 'u1', 'logout', new Date(2024, 0, 3, 9, 0)) // next day -> new session
      ]
      const dash = new ActivityDashboard(activities)

      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(6)
      expect(summary!.uniqueActions).toBe(4)
      expect(summary!.actionsPerDay).toBe(3) // 6 actions over 2 days active
      expect(summary!.mostFrequentAction).toBe('view')
      // sessions: [9:00,9:10,9:20], [10:00], [next day 9:00], [next day 9:00] => 4 sessions
      expect(summary!.averageActionsPerSession).toBe(1.5)
    })

    it('does not start a new session for exactly 30 minutes gap', () => {
      const activities: Act[] = [
        makeActivity('1', 'u3', 'a', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u3', 'b', new Date(2024, 0, 1, 9, 30)) // exactly 30 min
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u3')
      expect(summary).not.toBeNull()
      expect(summary!.averageActionsPerSession).toBe(2) // same session
      expect(summary!.actionsPerDay).toBe(2) // same day => 2 per day
    })
  })

  describe('getActivityTrends - day', () => {
    it('groups by day and computes growth rates across periods', () => {
      const activities: Act[] = [
        makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
        makeActivity('3', 'u1', 'click', new Date(2024, 0, 1, 9, 20)),
        makeActivity('4', 'u1', 'view', new Date(2024, 0, 1, 10, 0)),
        makeActivity('5', 'u1', 'view', new Date(2024, 0, 2, 9, 0)),
        makeActivity('6', 'u1', 'logout', new Date(2024, 0, 3, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('u1', 'day')

      expect(trends.length).toBe(3)
      expect(trends[0]).toEqual({ period: '2024-01-01', count: 4, growthRate: 0 })
      expect(trends[1].period).toBe('2024-01-02')
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBe(-75) // (1-4)/4*100
      expect(trends[2]).toEqual({ period: '2024-01-03', count: 1, growthRate: 0 })
    })

    it('returns empty array if user has no activities', () => {
      const dash = new ActivityDashboard([])
      const trends = dash.getActivityTrends('uX', 'day')
      expect(trends).toEqual([])
    })
  })

  describe('getActivityTrends - hour', () => {
    it('groups by hour and sorts periods', () => {
      const activities: Act[] = [
        makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 9, 10)),
        makeActivity('3', 'u1', 'a', new Date(2024, 0, 1, 9, 20)),
        makeActivity('4', 'u1', 'b', new Date(2024, 0, 1, 10, 0)),
        makeActivity('5', 'u1', 'b', new Date(2024, 0, 2, 9, 0)),
        makeActivity('6', 'u1', 'c', new Date(2024, 0, 3, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('u1', 'hour')
      expect(trends.map(t => t.period)).toEqual([
        '2024-01-01 09:00',
        '2024-01-01 10:00',
        '2024-01-02 09:00',
        '2024-01-03 09:00'
      ])
      expect(trends[0].count).toBe(3)
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBeCloseTo(-66.67, 2)
    })
  })

  describe('getActivityTrends - week', () => {
    it('groups by week using internal week number implementation', () => {
      const activities: Act[] = [
        // Week 1
        makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'a', new Date(2024, 0, 2, 9, 0)),
        makeActivity('3', 'u1', 'a', new Date(2024, 0, 3, 9, 0)),
        // Week 2
        makeActivity('4', 'u1', 'b', new Date(2024, 0, 8, 9, 0)),
        makeActivity('5', 'u1', 'b', new Date(2024, 0, 8, 12, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('u1', 'week')

      expect(trends.length).toBe(2)
      expect(trends[0].period).toBe('2024-W01')
      expect(trends[0].count).toBe(3)
      expect(trends[1].period).toBe('2024-W02')
      expect(trends[1].count).toBe(2)
      expect(trends[1].growthRate).toBeCloseTo(-33.33, 2)
    })
  })

  describe('getActivityTrends - month', () => {
    it('groups by month and sorts correctly', () => {
      const activities: Act[] = [
        makeActivity('1', 'u1', 'a', new Date(2024, 0, 31, 23, 59)),
        makeActivity('2', 'u1', 'b', new Date(2024, 1, 1, 0, 1))
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('u1', 'month')
      expect(trends).toEqual([
        { period: '2024-01', count: 1, growthRate: 0 },
        { period: '2024-02', count: 1, growthRate: 0 }
      ])
    })
  })

  describe('getActivityTrends - fallback for unknown period', () => {
    it('falls back to day when an unknown periodType is provided at runtime', () => {
      const activities: Act[] = [
        makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'b', new Date(2024, 0, 1, 12, 0)),
        makeActivity('3', 'u1', 'c', new Date(2024, 0, 2, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const trends = (dash as any).getActivityTrends('u1', 'unknown')
      expect(trends.map((t: any) => t.period)).toEqual(['2024-01-01', '2024-01-02'])
      expect(trends[0].count).toBe(2)
      expect(trends[1].count).toBe(1)
    })
  })

  describe('filterByDateRange', () => {
    it('returns only activities within inclusive range for a specific user', () => {
      const a1 = makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0))
      const a2 = makeActivity('2', 'u1', 'b', new Date(2024, 0, 1, 10, 0))
      const a3 = makeActivity('3', 'u1', 'c', new Date(2024, 0, 1, 11, 0))
      const a4 = makeActivity('4', 'u2', 'd', new Date(2024, 0, 1, 10, 0))
      const dash = new ActivityDashboard([a1, a2, a3, a4])

      const result = dash.filterByDateRange('u1', new Date(2024, 0, 1, 10, 0), new Date(2024, 0, 1, 11, 0))
      const ids = result.map(r => r.id)
      expect(ids).toEqual(['2', '3'])
    })

    it('returns empty if no activities fall within bounds', () => {
      const dash = new ActivityDashboard([
        makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 8, 0)),
        makeActivity('2', 'u1', 'b', new Date(2024, 0, 1, 9, 0))
      ])
      const result = dash.filterByDateRange('u1', new Date(2024, 0, 1, 10, 0), new Date(2024, 0, 1, 12, 0))
      expect(result).toEqual([])
    })
  })

  describe('aggregateByAction', () => {
    it('aggregates counts, percentages (rounded), and first/last occurrence, sorted by count desc', () => {
      const a1 = makeActivity('1', 'u1', 'view', new Date(2024, 0, 1, 9, 10))
      const a2 = makeActivity('2', 'u1', 'view', new Date(2024, 0, 1, 10, 0))
      const a3 = makeActivity('3', 'u1', 'view', new Date(2024, 0, 2, 9, 0))
      const a4 = makeActivity('4', 'u1', 'login', new Date(2024, 0, 1, 9, 0))
      const a5 = makeActivity('5', 'u1', 'click', new Date(2024, 0, 1, 9, 20))
      const a6 = makeActivity('6', 'u1', 'logout', new Date(2024, 0, 3, 9, 0))
      const dash = new ActivityDashboard([a1, a2, a3, a4, a5, a6])

      const groups = dash.aggregateByAction('u1')
      expect(groups.length).toBe(4)
      // First should be "view" with 3/6 = 50%
      expect(groups[0].action).toBe('view')
      expect(groups[0].count).toBe(3)
      expect(groups[0].percentage).toBe(50)
      expect(groups[0].firstOccurrence.getTime()).toBe(a1.timestamp.getTime())
      expect(groups[0].lastOccurrence.getTime()).toBe(a3.timestamp.getTime())
      // Others should be 1/6 = 16.67%
      const rest = groups.slice(1)
      rest.forEach(g => {
        expect(g.count).toBe(1)
        expect(g.percentage).toBeCloseTo(16.67, 2)
      })
    })

    it('returns empty array for users with no activities', () => {
      const dash = new ActivityDashboard([
        makeActivity('1', 'u2', 'a', new Date(2024, 0, 1, 9, 0))
      ])
      const groups = dash.aggregateByAction('u1')
      expect(groups).toEqual([])
    })
  })

  describe('getTopActions_old', () => {
    it('returns action groups sorted by count and does not apply limit', () => {
      const activities: Act[] = [
        makeActivity('1', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
        makeActivity('2', 'u1', 'view', new Date(2024, 0, 1, 10, 0)),
        makeActivity('3', 'u1', 'view', new Date(2024, 0, 2, 9, 0)),
        makeActivity('4', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
        makeActivity('5', 'u1', 'click', new Date(2024, 0, 1, 9, 20)),
        makeActivity('6', 'u1', 'logout', new Date(2024, 0, 3, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const groups = dash.getTopActions_old('u1', 2) // limit ignored in _old
      expect(groups.length).toBe(4)
      expect(groups[0].action).toBe('view')
      expect(groups[0].count).toBe(3)
      // First and last occurrences for "view"
      expect(groups[0].firstOccurrence.getTime()).toBe(activities[0].timestamp.getTime())
      expect(groups[0].lastOccurrence.getTime()).toBe(activities[2].timestamp.getTime())
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions by count using limit', () => {
      const acts: Act[] = [
        makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'b', new Date(2024, 0, 1, 9, 5)),
        makeActivity('3', 'u1', 'c', new Date(2024, 0, 1, 9, 10)),
        makeActivity('4', 'u1', 'd', new Date(2024, 0, 1, 9, 15)),
        makeActivity('5', 'u1', 'e', new Date(2024, 0, 1, 9, 20)),
        makeActivity('6', 'u1', 'f', new Date(2024, 0, 1, 9, 25)),
        makeActivity('7', 'u1', 'a', new Date(2024, 0, 1, 9, 30)) // make 'a' top with count 2
      ]
      const dash = new ActivityDashboard(acts)
      const top2 = dash.getTopActions('u1', 2)
      expect(top2.length).toBe(2)
      expect(top2[0].action).toBe('a')
      expect(top2[0].count).toBe(2)

      const topDefault = dash.getTopActions('u1') // default 5
      expect(topDefault.length).toBe(5)
    })

    it('returns fewer than limit if not enough actions', () => {
      const acts: Act[] = [
        makeActivity('1', 'u1', 'x', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'y', new Date(2024, 0, 1, 10, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const top5 = dash.getTopActions('u1', 5)
      expect(top5.length).toBe(2)
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 for users with no activity', () => {
      const dash = new ActivityDashboard([])
      expect(dash.calculateEngagementScore('nope')).toBe(0)
    })

    it('computes score with proper caps and rounding', () => {
      // From earlier test: total=6, unique=4, actionsPerDay=3 => 37.8
      const activities: Act[] = [
        makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
        makeActivity('3', 'u1', 'click', new Date(2024, 0, 1, 9, 20)),
        makeActivity('4', 'u1', 'view', new Date(2024, 0, 1, 10, 0)),
        makeActivity('5', 'u1', 'view', new Date(2024, 0, 2, 9, 0)),
        makeActivity('6', 'u1', 'logout', new Date(2024, 0, 3, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      expect(dash.calculateEngagementScore('u1')).toBe(37.8)
    })

    it('caps each component and returns 100 when all capped', () => {
      const acts: Act[] = []
      // 100 actions, 10 unique, all on same day => actionsPerDay >= 5
      const start = new Date(2024, 0, 1, 9, 0)
      const actions = Array.from({ length: 10 }).map((_, i) => String.fromCharCode(97 + i)) // a..j
      for (let i = 0; i < 100; i++) {
        const action = actions[i % actions.length]
        acts.push(makeActivity(String(i + 1), 'uMax', action, new Date(2024, 0, 1, 9, i % 60)))
      }
      const dash = new ActivityDashboard(acts)
      const score = dash.calculateEngagementScore('uMax')
      expect(score).toBe(100)
    })
  })

  describe('integration of multiple methods', () => {
    it('trends day counts align with aggregation counts per day', () => {
      const activities: Act[] = [
        makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 10, 0)),
        makeActivity('3', 'u1', 'b', new Date(2024, 0, 2, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('u1', 'day')
      expect(trends).toEqual([
        { period: '2024-01-01', count: 2, growthRate: 0 },
        { period: '2024-01-02', count: 1, growthRate: -50 }
      ])

      const aggs = dash.aggregateByAction('u1')
      const counts = aggs.reduce((sum, g) => sum + g.count, 0)
      expect(counts).toBe(3)
    })
  })
})