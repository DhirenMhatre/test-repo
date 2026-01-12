import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

describe('ActivityDashboard', () => {
  let activities: Activity[]
  let dashboard: ActivityDashboard

  beforeEach(() => {
    const base = new Date('2024-01-01T00:00:00Z')

    activities = [
      {
        id: '1',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(base.getTime()),
      },
      {
        id: '2',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(base.getTime() + 60 * 60 * 1000), // +1h
      },
      {
        id: '3',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(base.getTime() + 2 * 60 * 60 * 1000), // +2h
      },
      {
        id: '4',
        user_id: 'user1',
        action: 'purchase',
        timestamp: new Date(base.getTime() + 26 * 60 * 60 * 1000), // +26h (next day, new session)
      },
      {
        id: '5',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date(base.getTime() + 3 * 60 * 60 * 1000),
      },
      {
        id: '6',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(base.getTime() + 27 * 60 * 60 * 1000), // next day
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

      // totalActions: 4 activities for user1 in setup
      expect(result.totalActions).toBe(4)

      // uniqueActions: login, view, purchase
      expect(result.uniqueActions).toBe(3)

      // first and last timestamps for user1
      const user1Activities = activities.filter(a => a.user_id === 'user1')
      const sorted = [...user1Activities].sort(
        (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
      )
      const first = sorted[0].timestamp
      const last = sorted[sorted.length - 1].timestamp
      const daysDiff = Math.ceil(
        (last.getTime() - first.getTime()) / (1000 * 60 * 60 * 24)
      )
      const daysActive = Math.max(daysDiff, 1)
      const expectedActionsPerDay = parseFloat(
        (user1Activities.length / daysActive).toFixed(2)
      )
      expect(result.actionsPerDay).toBe(expectedActionsPerDay)

      // mostFrequentAction: 'view' appears twice
      expect(result.mostFrequentAction).toBe('view')

      // averageActionsPerSession:
      // user1 timestamps: 0h,1h,2h (session1), 26h,27h (session2)
      // sessions = 2, actions = 4 => 4/2 = 2.00
      expect(result.averageActionsPerSession).toBe(2.0)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: '10',
        user_id: 'single',
        action: 'login',
        timestamp: new Date('2024-02-01T10:00:00Z'),
      }
      const singleDashboard = new ActivityDashboard([singleActivity])

      const result = singleDashboard.getUserSummary('single')
      expect(result).not.toBeNull()
      if (!result) return

      expect(result.totalActions).toBe(1)
      expect(result.uniqueActions).toBe(1)
      expect(result.actionsPerDay).toBe(1)
      expect(result.mostFrequentAction).toBe('login')
      expect(result.averageActionsPerSession).toBe(1)
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.getActivityTrends('unknown', 'day')
      expect(result).toEqual([])
    })

    it('groups activities by day and calculates growth rate', () => {
      const result = dashboard.getActivityTrends('user1', 'day')

      // user1 has 3 activities on day 1 and 1 on day 2
      expect(result.length).toBe(2)

      const periods = result.map(r => r.period)
      expect(periods[0] <= periods[1]).toBe(true)

      const firstDay = result[0]
      const secondDay = result[1]

      expect(firstDay.count).toBe(3)
      expect(firstDay.growthRate).toBe(0)

      // growthRate = ((1 - 3) / 3) * 100 = -66.67
      expect(secondDay.count).toBe(1)
      expect(secondDay.growthRate).toBe(-66.67)
    })

    it('groups activities by hour', () => {
      const result = dashboard.getActivityTrends('user1', 'hour')

      // user1 has activities at 0h,1h,2h,26h,27h => 5 distinct hours
      expect(result.length).toBe(5)
      const counts = result.map(r => r.count)
      counts.forEach(c => expect(c).toBe(1))
    })

    it('groups activities by week and month', () => {
      const weekTrends = dashboard.getActivityTrends('user1', 'week')
      const monthTrends = dashboard.getActivityTrends('user1', 'month')

      expect(weekTrends.length).toBeGreaterThanOrEqual(1)
      expect(monthTrends.length).toBe(1)

      const totalWeekCount = weekTrends.reduce((sum, t) => sum + t.count, 0)
      const totalMonthCount = monthTrends.reduce((sum, t) => sum + t.count, 0)

      expect(totalWeekCount).toBe(4)
      expect(totalMonthCount).toBe(4)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within the inclusive date range for a user', () => {
      const start = new Date('2024-01-01T00:00:00Z')
      const end = new Date('2024-01-01T23:59:59Z')

      const result = dashboard.filterByDateRange('user1', start, end)

      // user1 has 3 activities on first day
      expect(result.length).toBe(3)
      result.forEach(a => {
        expect(a.user_id).toBe('user1')
        expect(a.timestamp.getTime()).toBeGreaterThanOrEqual(start.getTime())
        expect(a.timestamp.getTime()).toBeLessThanOrEqual(end.getTime())
      })
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

      // user1 actions: login x2, view x2, purchase x1 (but only 4 user1 in setup: login, view, view, purchase, login => actually 4? check)
      // In beforeEach: user1 ids:1(login),2(view),3(view),4(purchase),6(login) => 5 actions
      // login:2, view:2, purchase:1
      expect(result.length).toBe(3)

      const loginGroup = result.find(g => g.action === 'login')
      const viewGroup = result.find(g => g.action === 'view')
      const purchaseGroup = result.find(g => g.action === 'purchase')

      expect(loginGroup).toBeDefined()
      expect(viewGroup).toBeDefined()
      expect(purchaseGroup).toBeDefined()

      if (!loginGroup || !viewGroup || !purchaseGroup) return

      expect(loginGroup.count).toBe(2)
      expect(viewGroup.count).toBe(2)
      expect(purchaseGroup.count).toBe(1)

      const total = 5
      expect(loginGroup.percentage).toBe(parseFloat(((2 / total) * 100).toFixed(2)))
      expect(viewGroup.percentage).toBe(parseFloat(((2 / total) * 100).toFixed(2)))
      expect(purchaseGroup.percentage).toBe(parseFloat(((1 / total) * 100).toFixed(2)))

      // first and last occurrence for login
      const user1Activities = activities.filter(a => a.user_id === 'user1' && a.action === 'login')
      const sortedLogin = [...user1Activities].sort(
        (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
      )
      expect(loginGroup.firstOccurrence.getTime()).toBe(sortedLogin[0].timestamp.getTime())
      expect(loginGroup.lastOccurrence.getTime()).toBe(sortedLogin[sortedLogin.length - 1].timestamp.getTime())
    })

    it('sorts groups by count descending', () => {
      const result = dashboard.aggregateByAction('user1')
      for (let i = 1; i < result.length; i++) {
        expect(result[i - 1].count).toBeGreaterThanOrEqual(result[i].count)
      }
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count when limit not applied', () => {
      const result = dashboard.getTopActions_old('user1')

      expect(result.length).toBe(3)
      expect(result[0].count).toBeGreaterThanOrEqual(result[1].count)
      expect(result[1].count).toBeGreaterThanOrEqual(result[2].count)
    })

    it('calculates percentages based on total actions', () => {
      const result = dashboard.getTopActions_old('user1')
      const total = 5
      const login = result.find(r => r.action === 'login')
      const purchase = result.find(r => r.action === 'purchase')

      expect(login).toBeDefined()
      expect(purchase).toBeDefined()
      if (!login || !purchase) return

      expect(login.percentage).toBe(parseFloat(((2 / total) * 100).toFixed(2)))
      expect(purchase.percentage).toBe(parseFloat(((1 / total) * 100).toFixed(2)))
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions based on limit', () => {
      const result = dashboard.getTopActions('user1', 2)
      expect(result.length).toBe(2)

      const counts = result.map(r => r.count)
      expect(counts[0]).toBeGreaterThanOrEqual(counts[1])
    })

    it('defaults to limit 5 when not provided', () => {
      const result = dashboard.getTopActions('user1')
      // only 3 groups exist, so should return 3
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
          id: `m-${i}`,
          user_id: 'heavy',
          action: `action${i % 20}`, // 20 unique actions
          timestamp: new Date(base.getTime() + i * 60 * 1000),
        })
      }
      const heavyDashboard = new ActivityDashboard(manyActivities)
      const score = heavyDashboard.calculateEngagementScore('heavy')

      // Max possible score is 30 + 30 + 40 = 100
      expect(score).toBeLessThanOrEqual(100)
      expect(score).toBe(100)
    })
  })

  describe('getActivityTrends default periodType', () => {
    it('uses day as default periodType when not provided', () => {
      const withExplicit = dashboard.getActivityTrends('user1', 'day')
      const withDefault = dashboard.getActivityTrends('user1')

      expect(withDefault).toEqual(withExplicit)
    })
  })
})