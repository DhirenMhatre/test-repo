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
        timestamp: new Date(baseDate.getTime() + 60 * 60 * 1000 * 24 * 7), // +7 days
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

      const userActivities = activities.filter(a => a.user_id === 'user1')
      expect(result.totalActions).toBe(userActivities.length)

      const uniqueActions = new Set(userActivities.map(a => a.action))
      expect(result.uniqueActions).toBe(uniqueActions.size)

      const sorted = [...userActivities].sort(
        (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
      )
      const first = sorted[0].timestamp
      const last = sorted[sorted.length - 1].timestamp
      const daysDiff = Math.ceil(
        (last.getTime() - first.getTime()) / (1000 * 60 * 60 * 24)
      )
      const daysActive = Math.max(daysDiff, 1)
      const expectedActionsPerDay = parseFloat(
        (userActivities.length / daysActive).toFixed(2)
      )
      expect(result.actionsPerDay).toBe(expectedActionsPerDay)

      const counts: Record<string, number> = {}
      userActivities.forEach(a => {
        counts[a.action] = (counts[a.action] || 0) + 1
      })
      const mostFrequent = Object.entries(counts).reduce(
        (acc, [action, count]) =>
          count > acc.count ? { action, count } : acc,
        { action: 'none', count: 0 }
      ).action
      expect(result.mostFrequentAction).toBe(mostFrequent)
    })

    it('calculates averageActionsPerSession based on 30-minute gaps', () => {
      const base = new Date('2024-02-01T00:00:00Z')
      const userId = 'sessionUser'
      const sessionActivities: Activity[] = [
        {
          id: 's1',
          user_id: userId,
          action: 'a',
          timestamp: new Date(base.getTime()),
        },
        {
          id: 's2',
          user_id: userId,
          action: 'b',
          timestamp: new Date(base.getTime() + 10 * 60 * 1000),
        },
        {
          id: 's3',
          user_id: userId,
          action: 'c',
          timestamp: new Date(base.getTime() + 31 * 60 * 1000),
        },
        {
          id: 's4',
          user_id: userId,
          action: 'd',
          timestamp: new Date(base.getTime() + 32 * 60 * 1000),
        },
      ]
      const localDashboard = new ActivityDashboard(sessionActivities)
      const summary = localDashboard.getUserSummary(userId)
      expect(summary).not.toBeNull()
      if (!summary) return

      const total = sessionActivities.length
      const sessions = 2
      const expectedAvg = parseFloat((total / sessions).toFixed(2))
      expect(summary.averageActionsPerSession).toBe(expectedAvg)
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.getActivityTrends('unknown', 'day')
      expect(result).toEqual([])
    })

    it('groups activities by day and calculates growthRate', () => {
      const result = dashboard.getActivityTrends('user1', 'day')
      expect(result.length).toBeGreaterThan(0)

      const periods = result.map(r => r.period)
      const sortedPeriods = [...periods].sort()
      expect(periods).toEqual(sortedPeriods)

      expect(result[0].growthRate).toBe(0)

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

    it('supports hour, day, week, and month period types', () => {
      const hourTrends = dashboard.getActivityTrends('user1', 'hour')
      const dayTrends = dashboard.getActivityTrends('user1', 'day')
      const weekTrends = dashboard.getActivityTrends('user1', 'week')
      const monthTrends = dashboard.getActivityTrends('user1', 'month')

      expect(hourTrends.length).toBeGreaterThan(0)
      expect(dayTrends.length).toBeGreaterThan(0)
      expect(weekTrends.length).toBeGreaterThan(0)
      expect(monthTrends.length).toBeGreaterThan(0)

      expect(hourTrends[0].period).toMatch(/\d{4}-\d{2}-\d{2} \d{2}:00/)
      expect(dayTrends[0].period).toMatch(/\d{4}-\d{2}-\d{2}/)
      expect(weekTrends[0].period).toMatch(/\d{4}-W\d{2}/)
      expect(monthTrends[0].period).toMatch(/\d{4}-\d{2}/)
    })

    it('uses default periodType "day" when not provided', () => {
      const withDefault = dashboard.getActivityTrends('user1')
      const explicitDay = dashboard.getActivityTrends('user1', 'day')
      expect(withDefault).toEqual(explicitDay)
    })
  })

  describe('filterByDateRange', () => {
    it('returns only activities for the given user within the date range', () => {
      const start = new Date('2024-01-01T00:00:00Z')
      const end = new Date('2024-01-02T00:00:00Z')
      const result = dashboard.filterByDateRange('user1', start, end)

      expect(result.length).toBeGreaterThan(0)
      result.forEach(a => {
        expect(a.user_id).toBe('user1')
        expect(a.timestamp.getTime()).toBeGreaterThanOrEqual(start.getTime())
        expect(a.timestamp.getTime()).toBeLessThanOrEqual(end.getTime())
      })
    })

    it('returns empty array when no activities match criteria', () => {
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

    it('aggregates actions with counts, percentages, and occurrence dates', () => {
      const result = dashboard.aggregateByAction('user1')
      const userActivities = activities.filter(a => a.user_id === 'user1')
      const total = userActivities.length

      const actions = new Set(userActivities.map(a => a.action))
      expect(result.length).toBe(actions.size)

      result.forEach(group => {
        const matching = userActivities.filter(a => a.action === group.action)
        expect(group.count).toBe(matching.length)

        const expectedPercentage = parseFloat(
          ((matching.length / total) * 100).toFixed(2)
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
      const userActivities = activities.filter(a => a.user_id === 'user1')
      const actions = new Set(userActivities.map(a => a.action))
      expect(result.length).toBe(actions.size)

      for (let i = 1; i < result.length; i++) {
        expect(result[i - 1].count).toBeGreaterThanOrEqual(result[i].count)
      }
    })

    it('calculates percentages based on total user actions', () => {
      const result = dashboard.getTopActions_old('user1')
      const userActivities = activities.filter(a => a.user_id === 'user1')
      const total = userActivities.length

      result.forEach(group => {
        const matching = userActivities.filter(a => a.action === group.action)
        const expectedPercentage = parseFloat(
          ((matching.length / total) * 100).toFixed(2)
        )
        expect(group.percentage).toBe(expectedPercentage)
      })
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions based on limit', () => {
      const limit = 2
      const result = dashboard.getTopActions('user1', limit)
      expect(result.length).toBeLessThanOrEqual(limit)

      const all = dashboard.aggregateByAction('user1')
      expect(result).toEqual(all.slice(0, limit))
    })

    it('defaults to limit 5 when not provided', () => {
      const result = dashboard.getTopActions('user1')
      expect(result.length).toBeLessThanOrEqual(5)
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

    it('calculates engagement score based on volume, diversity, and frequency', () => {
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

    it('caps each component score at its maximum', () => {
      const manyActivities: Activity[] = []
      const base = new Date('2024-03-01T00:00:00Z')
      const userId = 'heavyUser'
      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `m${i}`,
          user_id: userId,
          action: `action${i % 20}`,
          timestamp: new Date(base.getTime() + i * 60 * 1000),
        })
      }
      const localDashboard = new ActivityDashboard(manyActivities)
      const summary = localDashboard.getUserSummary(userId)
      expect(summary).not.toBeNull()
      if (!summary) return

      const volumeScore = 30
      const diversityScore = 30
      const frequencyScore = Math.min(summary.actionsPerDay / 5, 1) * 40
      const expectedScore = parseFloat(
        (volumeScore + diversityScore + frequencyScore).toFixed(2)
      )

      const result = localDashboard.calculateEngagementScore(userId)
      expect(result).toBe(expectedScore)
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

    it('handles activities with metadata without affecting calculations', () => {
      const metaActivities: Activity[] = [
        {
          id: 'm1',
          user_id: 'metaUser',
          action: 'click',
          timestamp: new Date('2024-04-01T10:00:00Z'),
          metadata: { page: 'home' },
        },
        {
          id: 'm2',
          user_id: 'metaUser',
          action: 'click',
          timestamp: new Date('2024-04-01T10:05:00Z'),
          metadata: { page: 'about' },
        },
      ]
      const localDashboard = new ActivityDashboard(metaActivities)
      const summary = localDashboard.getUserSummary('metaUser')
      expect(summary).not.toBeNull()
      if (!summary) return
      expect(summary.totalActions).toBe(2)
      expect(summary.uniqueActions).toBe(1)
      expect(summary.mostFrequentAction).toBe('click')
    })
  })
})