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
        timestamp: new Date(baseDate.getTime() + 31 * 60 * 1000), // new session
      },
      {
        id: '5',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 40 * 60 * 1000),
      },
      {
        id: '6',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 24 * 60 * 60 * 1000), // next day
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

      expect(result.totalActions).toBe(5)

      expect(result.uniqueActions).toBe(3)

      const first = activities[0].timestamp.getTime()
      const last = activities[5].timestamp.getTime()
      const diffDays = Math.ceil((last - first) / (1000 * 60 * 60 * 24))
      const daysActive = Math.max(diffDays, 1)
      const expectedActionsPerDay = parseFloat((5 / daysActive).toFixed(2))
      expect(result.actionsPerDay).toBe(expectedActionsPerDay)

      expect(result.mostFrequentAction).toBe('view')

      const sessionGapMinutes = 30
      const sorted = activities.filter(a => a.user_id === 'user1').sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime())
      let sessions = 1
      for (let i = 1; i < sorted.length; i++) {
        const diffMinutes = (sorted[i].timestamp.getTime() - sorted[i - 1].timestamp.getTime()) / (1000 * 60)
        if (diffMinutes > sessionGapMinutes) {
          sessions++
        }
      }
      const expectedAvgPerSession = parseFloat((5 / sessions).toFixed(2))
      expect(result.averageActionsPerSession).toBe(expectedAvgPerSession)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: '10',
        user_id: 'single',
        action: 'login',
        timestamp: new Date('2024-01-05T12:00:00Z'),
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

      expect(result.length).toBe(2)

      const firstDay = result[0]
      const secondDay = result[1]

      expect(firstDay.count).toBe(4)
      expect(firstDay.growthRate).toBe(0)

      expect(secondDay.count).toBe(1)
      const expectedGrowth = parseFloat((((1 - 4) / 4) * 100).toFixed(2))
      expect(secondDay.growthRate).toBe(expectedGrowth)
    })

    it('groups activities by hour', () => {
      const result = dashboard.getActivityTrends('user1', 'hour')

      const periods = result.map(r => r.period)
      expect(periods.length).toBeGreaterThanOrEqual(2)
      expect(periods[0]).toMatch(/2024-01-01 0\d:00/)
    })

    it('groups activities by month', () => {
      const result = dashboard.getActivityTrends('user1', 'month')
      expect(result.length).toBe(1)
      expect(result[0].period).toBe('2024-01')
      expect(result[0].count).toBe(5)
      expect(result[0].growthRate).toBe(0)
    })

    it('groups activities by week', () => {
      const result = dashboard.getActivityTrends('user1', 'week')
      expect(result.length).toBe(1)
      expect(result[0].period).toMatch(/2024-W\d{2}/)
      expect(result[0].count).toBe(5)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within the inclusive date range for a user', () => {
      const start = new Date(baseDate.getTime() + 5 * 60 * 1000)
      const end = new Date(baseDate.getTime() + 35 * 60 * 1000)

      const result = dashboard.filterByDateRange('user1', start, end)

      const expectedIds = ['2', '3', '4']
      expect(result.map(a => a.id).sort()).toEqual(expectedIds.sort())
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date(baseDate.getTime() - 60 * 60 * 1000)
      const end = new Date(baseDate.getTime() - 30 * 60 * 1000)

      const result = dashboard.filterByDateRange('user1', start, end)
      expect(result).toEqual([])
    })

    it('filters only by specified user', () => {
      const start = new Date(baseDate.getTime())
      const end = new Date(baseDate.getTime() + 60 * 60 * 1000)

      const resultUser1 = dashboard.filterByDateRange('user1', start, end)
      const resultUser2 = dashboard.filterByDateRange('user2', start, end)

      expect(resultUser1.every(a => a.user_id === 'user1')).toBe(true)
      expect(resultUser2.every(a => a.user_id === 'user2')).toBe(true)
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.aggregateByAction('unknown')
      expect(result).toEqual([])
    })

    it('aggregates actions with counts, percentages and occurrences', () => {
      const result = dashboard.aggregateByAction('user1')

      expect(result.length).toBe(3)

      const total = 5
      const viewGroup = result.find(g => g.action === 'view')
      const loginGroup = result.find(g => g.action === 'login')
      const purchaseGroup = result.find(g => g.action === 'purchase')

      expect(viewGroup).toBeDefined()
      expect(viewGroup!.count).toBe(2)
      expect(viewGroup!.percentage).toBe(parseFloat(((2 / total) * 100).toFixed(2)))

      expect(loginGroup).toBeDefined()
      expect(loginGroup!.count).toBe(2)
      expect(loginGroup!.percentage).toBe(parseFloat(((2 / total) * 100).toFixed(2)))

      expect(purchaseGroup).toBeDefined()
      expect(purchaseGroup!.count).toBe(1)
      expect(purchaseGroup!.percentage).toBe(parseFloat(((1 / total) * 100).toFixed(2)))

      expect(viewGroup!.firstOccurrence <= viewGroup!.lastOccurrence).toBe(true)
      expect(loginGroup!.firstOccurrence <= loginGroup!.lastOccurrence).toBe(true)
      expect(purchaseGroup!.firstOccurrence <= purchaseGroup!.lastOccurrence).toBe(true)
    })

    it('sorts groups by count descending', () => {
      const result = dashboard.aggregateByAction('user1')
      const counts = result.map(g => g.count)
      const sortedCounts = [...counts].sort((a, b) => b - a)
      expect(counts).toEqual(sortedCounts)
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count when limit not applied', () => {
      const result = dashboard.getTopActions_old('user1')

      expect(result.length).toBe(3)
      expect(result[0].count >= result[1].count).toBe(true)
      expect(result[1].count >= result[2].count).toBe(true)
    })

    it('calculates percentages based on total actions', () => {
      const result = dashboard.getTopActions_old('user1')
      const total = 5

      const viewGroup = result.find(g => g.action === 'view')
      const loginGroup = result.find(g => g.action === 'login')
      const purchaseGroup = result.find(g => g.action === 'purchase')

      expect(viewGroup!.percentage).toBe(parseFloat(((2 / total) * 100).toFixed(2)))
      expect(loginGroup!.percentage).toBe(parseFloat(((2 / total) * 100).toFixed(2)))
      expect(purchaseGroup!.percentage).toBe(parseFloat(((1 / total) * 100).toFixed(2)))
    })

    it('uses first and last timestamps correctly', () => {
      const result = dashboard.getTopActions_old('user1')
      const loginGroup = result.find(g => g.action === 'login')
      expect(loginGroup).toBeDefined()
      if (!loginGroup) return

      const loginActivities = activities.filter(a => a.user_id === 'user1' && a.action === 'login').sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime())
      expect(loginGroup.firstOccurrence.getTime()).toBe(loginActivities[0].timestamp.getTime())
      expect(loginGroup.lastOccurrence.getTime()).toBe(loginActivities[loginActivities.length - 1].timestamp.getTime())
    })
  })

  describe('getTopActions', () => {
    it('returns limited number of top actions', () => {
      const result = dashboard.getTopActions('user1', 2)
      expect(result.length).toBe(2)
    })

    it('defaults to limit 5 when not provided', () => {
      const result = dashboard.getTopActions('user1')
      expect(result.length).toBeLessThanOrEqual(5)
      expect(result.length).toBe(3)
    })

    it('returns empty array when user has no activities', () => {
      const result = dashboard.getTopActions('unknown')
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
      const expectedScore = parseFloat((volumeScore + diversityScore + frequencyScore).toFixed(2))

      const result = dashboard.calculateEngagementScore('user1')
      expect(result).toBe(expectedScore)
    })

    it('caps each component of the score at its maximum', () => {
      const manyActivities: Activity[] = []
      const userId = 'heavy'
      const start = new Date('2024-01-01T00:00:00Z')
      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `h-${i}`,
          user_id: userId,
          action: `action-${i % 15}`,
          timestamp: new Date(start.getTime() + i * 60 * 1000),
        })
      }
      const heavyDashboard = new ActivityDashboard(manyActivities)
      const score = heavyDashboard.calculateEngagementScore(userId)

      expect(score).toBeLessThanOrEqual(100)
      expect(score).toBe(100)
    })
  })

  describe('private behavior via public methods', () => {
    it('getActivityTrends default periodType is day', () => {
      const byDay = dashboard.getActivityTrends('user1', 'day')
      const defaultResult = dashboard.getActivityTrends('user1')
      expect(defaultResult).toEqual(byDay)
    })

    it('getActivityTrends falls back to day for unknown periodType', () => {
      const anyDashboard = dashboard as any
      const activitiesForUser = activities.filter(a => a.user_id === 'user1')
      const groupedDefault = anyDashboard.groupByPeriod(activitiesForUser, 'unknown')
      const groupedDay = anyDashboard.groupByPeriod(activitiesForUser, 'day')
      expect(groupedDefault).toEqual(groupedDay)
    })
  })
})