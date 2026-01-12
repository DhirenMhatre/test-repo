import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

describe('ActivityDashboard', () => {
  let activities: Activity[]
  let dashboard: ActivityDashboard

  beforeEach(() => {
    const baseDate = new Date('2024-01-01T00:00:00Z')

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
      {
        id: '6',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 60 * 60 * 1000 * 24 * 3), // 3 days later
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

      const expectedActionCounts = {
        login: 2,
        view: 2,
        purchase: 1,
      }
      expect(result.uniqueActions).toBe(Object.keys(expectedActionCounts).length)

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

      expect(result.mostFrequentAction === 'login' || result.mostFrequentAction === 'view').toBe(
        true
      )

      const sessionGapMinutes = 30
      const sortedForSession = [...user1Activities].sort(
        (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
      )
      let sessions = 1
      for (let i = 1; i < sortedForSession.length; i++) {
        const diffMinutes =
          (sortedForSession[i].timestamp.getTime() -
            sortedForSession[i - 1].timestamp.getTime()) /
          (1000 * 60)
        if (diffMinutes > sessionGapMinutes) {
          sessions++
        }
      }
      const expectedAvgPerSession = parseFloat(
        (user1Activities.length / sessions).toFixed(2)
      )
      expect(result.averageActionsPerSession).toBe(expectedAvgPerSession)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: 'single',
        user_id: 'singleUser',
        action: 'onlyAction',
        timestamp: new Date('2024-02-01T12:00:00Z'),
      }
      const singleDashboard = new ActivityDashboard([singleActivity])

      const result = singleDashboard.getUserSummary('singleUser')
      expect(result).not.toBeNull()
      if (!result) return

      expect(result.totalActions).toBe(1)
      expect(result.uniqueActions).toBe(1)
      expect(result.actionsPerDay).toBe(1)
      expect(result.mostFrequentAction).toBe('onlyAction')
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
      expect(result.length).toBeGreaterThanOrEqual(2)

      const periods = result.map(r => r.period)
      const sortedPeriods = [...periods].sort()
      expect(periods).toEqual(sortedPeriods)

      const first = result[0]
      expect(first.count).toBeGreaterThan(0)
      expect(first.growthRate).toBe(0)

      for (let i = 1; i < result.length; i++) {
        const prev = result[i - 1]
        const curr = result[i]
        const expectedGrowth =
          prev.count > 0
            ? parseFloat((((curr.count - prev.count) / prev.count) * 100).toFixed(2))
            : 0
        expect(curr.growthRate).toBe(expectedGrowth)
      }
    })

    it('groups activities by hour correctly', () => {
      const result = dashboard.getActivityTrends('user1', 'hour')
      expect(result.length).toBeGreaterThan(1)
      result.forEach(entry => {
        expect(entry.period).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:00$/)
      })
    })

    it('groups activities by week and month correctly', () => {
      const weekTrends = dashboard.getActivityTrends('user1', 'week')
      const monthTrends = dashboard.getActivityTrends('user1', 'month')

      weekTrends.forEach(entry => {
        expect(entry.period).toMatch(/^\d{4}-W\d{2}$/)
      })
      monthTrends.forEach(entry => {
        expect(entry.period).toMatch(/^\d{4}-\d{2}$/)
      })
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within the inclusive date range for a user', () => {
      const start = new Date('2024-01-01T00:00:00Z')
      const end = new Date('2024-01-02T00:00:00Z')

      const result = dashboard.filterByDateRange('user1', start, end)

      expect(result.length).toBeGreaterThan(0)
      result.forEach(activity => {
        expect(activity.user_id).toBe('user1')
        expect(activity.timestamp.getTime()).toBeGreaterThanOrEqual(start.getTime())
        expect(activity.timestamp.getTime()).toBeLessThanOrEqual(end.getTime())
      })
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date('2030-01-01T00:00:00Z')
      const end = new Date('2030-01-02T00:00:00Z')

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

      const totalUser1 = activities.filter(a => a.user_id === 'user1').length
      expect(result.length).toBeGreaterThan(0)

      const actionsSeen = new Set<string>()
      result.forEach(group => {
        expect(actionsSeen.has(group.action)).toBe(false)
        actionsSeen.add(group.action)

        const matching = activities.filter(
          a => a.user_id === 'user1' && a.action === group.action
        )
        expect(group.count).toBe(matching.length)

        const expectedPercentage = parseFloat(
          ((matching.length / totalUser1) * 100).toFixed(2)
        )
        expect(group.percentage).toBe(expectedPercentage)

        const sorted = [...matching].sort(
          (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
        )
        expect(group.firstOccurrence.getTime()).toBe(sorted[0].timestamp.getTime())
        expect(group.lastOccurrence.getTime()).toBe(
          sorted[sorted.length - 1].timestamp.getTime()
        )
      })

      for (let i = 1; i < result.length; i++) {
        expect(result[i - 1].count).toBeGreaterThanOrEqual(result[i].count)
      }
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count without applying limit', () => {
      const result = dashboard.getTopActions_old('user1', 1)

      const totalUser1 = activities.filter(a => a.user_id === 'user1').length
      expect(result.length).toBeGreaterThan(1)

      const counts = result.map(r => r.count)
      const sortedCounts = [...counts].sort((a, b) => b - a)
      expect(counts).toEqual(sortedCounts)

      result.forEach(group => {
        const matching = activities.filter(
          a => a.user_id === 'user1' && a.action === group.action
        )
        expect(group.count).toBe(matching.length)
        const expectedPercentage = parseFloat(
          ((matching.length / totalUser1) * 100).toFixed(2)
        )
        expect(group.percentage).toBe(expectedPercentage)
      })
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions based on count', () => {
      const limit = 2
      const result = dashboard.getTopActions('user1', limit)

      const allAggregated = dashboard.aggregateByAction('user1')
      expect(result).toEqual(allAggregated.slice(0, limit))
    })

    it('returns all actions when limit exceeds available actions', () => {
      const result = dashboard.getTopActions('user1', 100)
      const allAggregated = dashboard.aggregateByAction('user1')
      expect(result).toEqual(allAggregated)
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
      const expectedScore = parseFloat(
        (volumeScore + diversityScore + frequencyScore).toFixed(2)
      )

      const result = dashboard.calculateEngagementScore('user1')
      expect(result).toBe(expectedScore)
    })

    it('caps each component of the score at its maximum', () => {
      const manyActivities: Activity[] = []
      const baseDate = new Date('2024-01-01T00:00:00Z')
      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `a${i}`,
          user_id: 'heavyUser',
          action: `action${i % 20}`,
          timestamp: new Date(baseDate.getTime() + i * 60 * 1000),
        })
      }
      const heavyDashboard = new ActivityDashboard(manyActivities)

      const summary = heavyDashboard.getUserSummary('heavyUser')
      expect(summary).not.toBeNull()
      if (!summary) return

      const volumeScore = Math.min(summary.totalActions / 100, 1) * 30
      const diversityScore = Math.min(summary.uniqueActions / 10, 1) * 30
      const frequencyScore = Math.min(summary.actionsPerDay / 5, 1) * 40
      const expectedScore = parseFloat(
        (volumeScore + diversityScore + frequencyScore).toFixed(2)
      )

      const result = heavyDashboard.calculateEngagementScore('heavyUser')
      expect(result).toBe(expectedScore)
      expect(result).toBeLessThanOrEqual(100)
    })
  })

  describe('constructor and basic behavior', () => {
    it('initializes with empty activities when none provided', () => {
      const emptyDashboard = new ActivityDashboard()
      const summary = emptyDashboard.getUserSummary('any')
      expect(summary).toBeNull()
      const trends = emptyDashboard.getActivityTrends('any')
      expect(trends).toEqual([])
    })
  })
})