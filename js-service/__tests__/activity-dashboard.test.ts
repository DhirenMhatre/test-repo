import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

describe('ActivityDashboard', () => {
  let activities: Activity[]
  let dashboard: ActivityDashboard

  beforeEach(() => {
    const base = new Date('2024-01-01T00:00:00Z')

    activities = [
      // user1 - multiple actions over multiple days and sessions
      {
        id: '1',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(base.getTime() + 0 * 60 * 1000),
      },
      {
        id: '2',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(base.getTime() + 10 * 60 * 1000),
      },
      {
        id: '3',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(base.getTime() + 20 * 60 * 1000),
      },
      {
        id: '4',
        user_id: 'user1',
        action: 'purchase',
        timestamp: new Date(base.getTime() + 40 * 60 * 1000),
      },
      // gap > 30 minutes -> new session
      {
        id: '5',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(base.getTime() + 2 * 60 * 60 * 1000),
      },
      // next day
      {
        id: '6',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date('2024-01-02T01:00:00Z'),
      },
      // user2 - separate user
      {
        id: '7',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date('2024-01-01T05:00:00Z'),
      },
      {
        id: '8',
        user_id: 'user2',
        action: 'logout',
        timestamp: new Date('2024-01-01T06:00:00Z'),
      },
    ]

    dashboard = new ActivityDashboard(activities)
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const result = dashboard.getUserSummary('unknown')
      expect(result).toBeNull()
    })

    it('calculates summary metrics correctly for a user', () => {
      const result = dashboard.getUserSummary('user1')
      expect(result).not.toBeNull()
      if (!result) return

      // totalActions: all activities for user1
      expect(result.totalActions).toBe(6)

      // uniqueActions: login, view, purchase
      expect(result.uniqueActions).toBe(3)

      // daysActive: from 2024-01-01T00:00 to 2024-01-02T01:00
      // diff ~ 25 hours -> 1.04 days -> ceil = 2
      // actionsPerDay = 6 / 2 = 3.00
      expect(result.actionsPerDay).toBe(3)

      // mostFrequentAction: view (3 times)
      expect(result.mostFrequentAction).toBe('view')

      // sessions: timestamps for user1 sorted:
      // 0, 10, 20, 40, 120, next day 25h
      // gaps: 10,10,20,80,23*60
      // gaps > 30 at 80 and 23*60 -> 3 sessions
      // averageActionsPerSession = 6 / 3 = 2.00
      expect(result.averageActionsPerSession).toBe(2)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: '9',
        user_id: 'single',
        action: 'only',
        timestamp: new Date('2024-01-10T10:00:00Z'),
      }
      const singleDashboard = new ActivityDashboard([...activities, singleActivity])

      const result = singleDashboard.getUserSummary('single')
      expect(result).not.toBeNull()
      if (!result) return

      expect(result.totalActions).toBe(1)
      expect(result.uniqueActions).toBe(1)
      expect(result.actionsPerDay).toBe(1)
      expect(result.mostFrequentAction).toBe('only')
      expect(result.averageActionsPerSession).toBe(1)
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.getActivityTrends('unknown')
      expect(result).toEqual([])
    })

    it('groups activities by day and calculates growth rate', () => {
      const result = dashboard.getActivityTrends('user1', 'day')

      // user1 has activities on 2024-01-01 and 2024-01-02
      expect(result.length).toBe(2)

      const day1 = result[0]
      const day2 = result[1]

      expect(day1.period).toBe('2024-01-01')
      expect(day1.count).toBe(5)
      expect(day1.growthRate).toBe(0)

      expect(day2.period).toBe('2024-01-02')
      expect(day2.count).toBe(1)
      // previous count 5, current 1 -> ((1-5)/5)*100 = -80.00
      expect(day2.growthRate).toBe(-80)
    })

    it('groups activities by hour', () => {
      const result = dashboard.getActivityTrends('user2', 'hour')

      // user2 has two hours: 05:00 and 06:00
      expect(result.length).toBe(2)
      expect(result[0].period).toBe('2024-01-01 05:00')
      expect(result[0].count).toBe(1)
      expect(result[0].growthRate).toBe(0)

      expect(result[1].period).toBe('2024-01-01 06:00')
      expect(result[1].count).toBe(1)
      expect(result[1].growthRate).toBe(0)
    })

    it('groups activities by month and week', () => {
      const monthTrends = dashboard.getActivityTrends('user1', 'month')
      expect(monthTrends.length).toBe(1)
      expect(monthTrends[0].period).toBe('2024-01')
      expect(monthTrends[0].count).toBe(6)
      expect(monthTrends[0].growthRate).toBe(0)

      const weekTrends = dashboard.getActivityTrends('user1', 'week')
      expect(weekTrends.length).toBe(1)
      expect(weekTrends[0].period.startsWith('2024-W')).toBe(true)
      expect(weekTrends[0].count).toBe(6)
      expect(weekTrends[0].growthRate).toBe(0)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within inclusive date range for a user', () => {
      const start = new Date('2024-01-01T00:10:00Z')
      const end = new Date('2024-01-01T02:00:00Z')

      const result = dashboard.filterByDateRange('user1', start, end)

      // user1 activities in that range: ids 2,3,4,5 (10m,20m,40m,2h)
      const ids = result.map(a => a.id).sort()
      expect(ids).toEqual(['2', '3', '4', '5'])
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date('2025-01-01T00:00:00Z')
      const end = new Date('2025-01-02T00:00:00Z')

      const result = dashboard.filterByDateRange('user1', start, end)
      expect(result).toEqual([])
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.aggregateByAction('unknown')
      expect(result).toEqual([])
    })

    it('aggregates actions with counts, percentages and occurrences', () => {
      const result = dashboard.aggregateByAction('user1')

      // actions: login(2), view(3), purchase(1)
      expect(result.length).toBe(3)

      // sorted by count desc: view, login, purchase
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(3)
      expect(result[0].percentage).toBeCloseTo((3 / 6) * 100, 2)

      expect(result[1].action).toBe('login')
      expect(result[1].count).toBe(2)
      expect(result[1].percentage).toBeCloseTo((2 / 6) * 100, 2)

      expect(result[2].action).toBe('purchase')
      expect(result[2].count).toBe(1)
      expect(result[2].percentage).toBeCloseTo((1 / 6) * 100, 2)

      // first and last occurrence for "view"
      const viewGroup = result.find(g => g.action === 'view')!
      const viewActivities = activities.filter(
        a => a.user_id === 'user1' && a.action === 'view'
      )
      const sorted = [...viewActivities].sort(
        (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
      )
      expect(viewGroup.firstOccurrence.getTime()).toBe(sorted[0].timestamp.getTime())
      expect(viewGroup.lastOccurrence.getTime()).toBe(
        sorted[sorted.length - 1].timestamp.getTime()
      )
    })

    it('does not mutate original activities array order', () => {
      const originalUser1 = activities.filter(a => a.user_id === 'user1')
      const originalTimestamps = originalUser1.map(a => a.timestamp.getTime())

      dashboard.aggregateByAction('user1')

      const afterUser1 = activities.filter(a => a.user_id === 'user1')
      const afterTimestamps = afterUser1.map(a => a.timestamp.getTime())

      expect(afterTimestamps).toEqual(originalTimestamps)
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count without applying limit', () => {
      const result = dashboard.getTopActions_old('user1', 1)

      // limit is ignored in _old version
      expect(result.length).toBe(3)

      // sorted by count desc: view(3), login(2), purchase(1)
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(3)
      expect(result[1].action).toBe('login')
      expect(result[1].count).toBe(2)
      expect(result[2].action).toBe('purchase')
      expect(result[2].count).toBe(1)
    })

    it('calculates percentages based on total actions', () => {
      const result = dashboard.getTopActions_old('user2')

      // user2 has 2 actions: login, logout
      expect(result.length).toBe(2)
      const login = result.find(r => r.action === 'login')!
      const logout = result.find(r => r.action === 'logout')!

      expect(login.percentage).toBeCloseTo(50, 2)
      expect(logout.percentage).toBeCloseTo(50, 2)
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions based on aggregateByAction', () => {
      const result = dashboard.getTopActions('user1', 2)

      // should delegate to aggregateByAction and slice
      expect(result.length).toBe(2)
      expect(result[0].action).toBe('view')
      expect(result[1].action).toBe('login')
    })

    it('returns all actions when limit exceeds available', () => {
      const result = dashboard.getTopActions('user1', 10)
      expect(result.length).toBe(3)
    })

    it('returns empty array when user has no activities', () => {
      const result = dashboard.getTopActions('unknown', 3)
      expect(result).toEqual([])
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when user has no activities', () => {
      const result = dashboard.calculateEngagementScore('unknown')
      expect(result).toBe(0)
    })

    it('calculates engagement score based on summary metrics', () => {
      const summary = dashboard.getUserSummary('user1')
      expect(summary).not.toBeNull()
      if (!summary) return

      const volumeScore = Math.min(summary.totalActions / 100, 1) * 30
      const diversityScore = Math.min(summary.uniqueActions / 10, 1) * 30
      const frequencyScore = Math.min(summary.actionsPerDay / 5, 1) * 40
      const expected = parseFloat((volumeScore + diversityScore + frequencyScore).toFixed(2))

      const result = dashboard.calculateEngagementScore('user1')
      expect(result).toBe(expected)
    })

    it('caps each component score at its maximum', () => {
      const manyActivities: Activity[] = []
      const base = new Date('2024-01-01T00:00:00Z')
      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `m${i}`,
          user_id: 'heavy',
          action: `action${i % 20}`, // 20 unique actions
          timestamp: new Date(base.getTime() + i * 60 * 1000),
        })
      }
      const heavyDashboard = new ActivityDashboard(manyActivities)
      const score = heavyDashboard.calculateEngagementScore('heavy')

      // volumeScore max 30, diversityScore max 30, frequencyScore max 40 -> total 100
      expect(score).toBeLessThanOrEqual(100)
      expect(score).toBeCloseTo(100, 2)
    })
  })

  describe('private behavior via public methods', () => {
    it('calculateAverageActionsPerSession handles empty activities via getUserSummary', () => {
      const emptyDashboard = new ActivityDashboard([])
      const summary = emptyDashboard.getUserSummary('any')
      expect(summary).toBeNull()
    })

    it('getActivityTrends default periodType is day', () => {
      const dayTrends = dashboard.getActivityTrends('user1')
      const explicitDayTrends = dashboard.getActivityTrends('user1', 'day')
      expect(dayTrends).toEqual(explicitDayTrends)
    })

    it('groupByPeriod default branch behaves like day when invalid periodType is passed indirectly', () => {
      // We cannot call private groupByPeriod directly, but we can rely on getActivityTrends
      // using getPeriodKey with default branch when an invalid periodType is passed.
      // To do this, we cast to any to bypass TypeScript at runtime.
      const anyDashboard: any = dashboard
      const activitiesForUser1 = activities.filter(a => a.user_id === 'user1')
      const grouped = anyDashboard.groupByPeriod(activitiesForUser1, 'invalid')

      const keys = Object.keys(grouped)
      // Should be grouped by day (default case)
      expect(keys).toContain('2024-01-01')
      expect(keys).toContain('2024-01-02')
    })
  })
})