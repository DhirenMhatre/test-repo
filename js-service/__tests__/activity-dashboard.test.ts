import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

describe('ActivityDashboard', () => {
  let baseDate: Date
  let activities: Activity[]
  let dashboard: ActivityDashboard

  beforeEach(() => {
    baseDate = new Date('2024-01-01T00:00:00Z')

    activities = [
      {
        id: '1',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 0 * 60 * 1000),
      },
      {
        id: '2',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(baseDate.getTime() + 10 * 60 * 1000),
      },
      {
        id: '3',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(baseDate.getTime() + 20 * 60 * 1000),
      },
      {
        id: '4',
        user_id: 'user1',
        action: 'purchase',
        timestamp: new Date(baseDate.getTime() + 24 * 60 * 60 * 1000), // next day
      },
      {
        id: '5',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 5 * 60 * 1000),
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

      // totalActions: 4 activities for user1
      expect(result.totalActions).toBe(4)

      // uniqueActions: login, view, purchase
      expect(result.uniqueActions).toBe(3)

      // daysActive: from baseDate to baseDate + 1 day => diff = 1 day, ceil(1) = 1, max(1,1)=1
      // actionsPerDay = 4 / 1 = 4.00
      expect(result.actionsPerDay).toBe(4)

      // mostFrequentAction: 'view' (2 times)
      expect(result.mostFrequentAction).toBe('view')

      // averageActionsPerSession: all within 30 minutes except last one next day
      // sessions: first 3 in one session, last in second session => 2 sessions
      // 4 / 2 = 2.00
      expect(result.averageActionsPerSession).toBe(2)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: '10',
        user_id: 'single',
        action: 'login',
        timestamp: baseDate,
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
      const result = dashboard.getActivityTrends('unknown')
      expect(result).toEqual([])
    })

    it('groups activities by day and calculates growth rate', () => {
      const result = dashboard.getActivityTrends('user1', 'day')

      // user1 has 3 activities on day 1 and 1 on day 2
      expect(result.length).toBe(2)

      const day1 = result[0]
      const day2 = result[1]

      expect(day1.count).toBe(3)
      expect(day1.growthRate).toBe(0)

      expect(day2.count).toBe(1)
      // growthRate = ((1 - 3) / 3) * 100 = -66.666..., rounded to -66.67
      expect(day2.growthRate).toBe(-66.67)
    })

    it('groups activities by hour', () => {
      const result = dashboard.getActivityTrends('user1', 'hour')

      // 3 activities in first hour (00:00, 00:10, 00:20), 1 in next day same hour
      expect(result.length).toBe(2)
      expect(result[0].period.endsWith('00:00')).toBe(true)
      expect(result[0].count).toBe(3)
      expect(result[1].count).toBe(1)
    })

    it('groups activities by month and week', () => {
      const monthTrends = dashboard.getActivityTrends('user1', 'month')
      expect(monthTrends.length).toBe(1)
      expect(monthTrends[0].count).toBe(4)

      const weekTrends = dashboard.getActivityTrends('user1', 'week')
      expect(weekTrends.length).toBe(1)
      expect(weekTrends[0].count).toBe(4)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within the inclusive date range for a user', () => {
      const start = new Date(baseDate.getTime() + 5 * 60 * 1000)
      const end = new Date(baseDate.getTime() + 25 * 60 * 1000)

      const result = dashboard.filterByDateRange('user1', start, end)

      // user1 activities at 10 and 20 minutes are within range
      expect(result.map(a => a.id)).toEqual(['2', '3'])
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date(baseDate.getTime() + 2 * 24 * 60 * 60 * 1000)
      const end = new Date(baseDate.getTime() + 3 * 24 * 60 * 60 * 1000)

      const result = dashboard.filterByDateRange('user1', start, end)
      expect(result).toEqual([])
    })

    it('filters by user id as well as date', () => {
      const start = new Date(baseDate.getTime() - 60 * 60 * 1000)
      const end = new Date(baseDate.getTime() + 60 * 60 * 1000)

      const resultUser1 = dashboard.filterByDateRange('user1', start, end)
      const resultUser2 = dashboard.filterByDateRange('user2', start, end)

      expect(resultUser1.map(a => a.user_id)).toEqual(['user1', 'user1', 'user1'])
      expect(resultUser2.map(a => a.user_id)).toEqual(['user2'])
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.aggregateByAction('unknown')
      expect(result).toEqual([])
    })

    it('aggregates actions with counts, percentages and occurrences', () => {
      const result = dashboard.aggregateByAction('user1')

      // user1: login(1), view(2), purchase(1)
      expect(result.length).toBe(3)

      // sorted by count desc: view (2), login (1), purchase (1)
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(2)
      expect(result[0].percentage).toBe(50) // 2/4 * 100

      const loginGroup = result.find(g => g.action === 'login')
      expect(loginGroup).toBeDefined()
      if (!loginGroup) return
      expect(loginGroup.count).toBe(1)
      expect(loginGroup.percentage).toBe(25)

      const purchaseGroup = result.find(g => g.action === 'purchase')
      expect(purchaseGroup).toBeDefined()
      if (!purchaseGroup) return
      expect(purchaseGroup.count).toBe(1)
      expect(purchaseGroup.percentage).toBe(25)

      // first and last occurrence for 'view'
      const viewGroup = result[0]
      const viewActivities = activities.filter(
        a => a.user_id === 'user1' && a.action === 'view'
      )
      const sortedViews = [...viewActivities].sort(
        (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
      )
      expect(viewGroup.firstOccurrence.getTime()).toBe(sortedViews[0].timestamp.getTime())
      expect(viewGroup.lastOccurrence.getTime()).toBe(sortedViews[1].timestamp.getTime())
    })

    it('does not mutate original activities array order', () => {
      const original = [...activities]
      dashboard.aggregateByAction('user1')
      expect(activities).toEqual(original)
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count without applying limit', () => {
      const result = dashboard.getTopActions_old('user1', 1)

      // limit is ignored in _old version
      expect(result.length).toBe(3)
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(2)
    })

    it('calculates percentages based on total actions', () => {
      const result = dashboard.getTopActions_old('user1')

      const view = result.find(r => r.action === 'view')
      const login = result.find(r => r.action === 'login')
      const purchase = result.find(r => r.action === 'purchase')

      expect(view?.percentage).toBe(50)
      expect(login?.percentage).toBe(25)
      expect(purchase?.percentage).toBe(25)
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions based on count', () => {
      const result = dashboard.getTopActions('user1', 1)

      expect(result.length).toBe(1)
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(2)
    })

    it('returns all actions when limit exceeds available actions', () => {
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
      const result = dashboard.calculateEngagementScore('user1')

      const summary = dashboard.getUserSummary('user1')
      if (!summary) return

      const volumeScore = Math.min(summary.totalActions / 100, 1) * 30
      const diversityScore = Math.min(summary.uniqueActions / 10, 1) * 30
      const frequencyScore = Math.min(summary.actionsPerDay / 5, 1) * 40
      const expected = parseFloat((volumeScore + diversityScore + frequencyScore).toFixed(2))

      expect(result).toBe(expected)
    })

    it('caps each component of the score at its maximum', () => {
      const manyActivities: Activity[] = []
      const userId = 'heavy'

      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `h-${i}`,
          user_id: userId,
          action: `action-${i % 15}`, // 15 different actions
          timestamp: new Date(baseDate.getTime() + i * 60 * 1000),
        })
      }

      const heavyDashboard = new ActivityDashboard(manyActivities)
      const score = heavyDashboard.calculateEngagementScore(userId)

      // All components should be capped, so max score = 30 + 30 + 40 = 100
      expect(score).toBeLessThanOrEqual(100)
      expect(score).toBe(100)
    })
  })

  describe('private behavior via public methods', () => {
    it('calculateAverageActionsPerSession behavior via getUserSummary', () => {
      const spacedActivities: Activity[] = [
        {
          id: 's1',
          user_id: 'spaced',
          action: 'a',
          timestamp: new Date(baseDate.getTime()),
        },
        {
          id: 's2',
          user_id: 'spaced',
          action: 'b',
          timestamp: new Date(baseDate.getTime() + 10 * 60 * 1000), // 10 min later
        },
        {
          id: 's3',
          user_id: 'spaced',
          action: 'c',
          timestamp: new Date(baseDate.getTime() + 31 * 60 * 1000), // 31 min later -> new session
        },
      ]
      const spacedDashboard = new ActivityDashboard(spacedActivities)

      const summary = spacedDashboard.getUserSummary('spaced')
      expect(summary).not.toBeNull()
      if (!summary) return

      // sessions: first two in one session, third in second session => 2 sessions
      // average = 3 / 2 = 1.5
      expect(summary.averageActionsPerSession).toBe(1.5)
    })

    it('groupByPeriod default behavior via getActivityTrends', () => {
      const resultDefault = dashboard.getActivityTrends('user1')
      const resultDay = dashboard.getActivityTrends('user1', 'day')

      // default periodType should behave like 'day'
      expect(resultDefault).toEqual(resultDay)
    })
  })
})