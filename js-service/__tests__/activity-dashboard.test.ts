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
        timestamp: new Date(baseDate.getTime())
      },
      {
        id: '2',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(baseDate.getTime() + 10 * 60 * 1000) // +10 min
      },
      {
        id: '3',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(baseDate.getTime() + 20 * 60 * 1000) // +20 min
      },
      {
        id: '4',
        user_id: 'user1',
        action: 'logout',
        timestamp: new Date(baseDate.getTime() + 40 * 60 * 1000) // +40 min
      },
      {
        id: '5',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 26 * 60 * 60 * 1000) // +26 hours (next day +2h)
      },
      {
        id: '6',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 5 * 60 * 1000)
      }
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
      expect(result.mostFrequentAction).toBe('view')

      const first = activities.filter(a => a.user_id === 'user1').sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime())[0].timestamp
      const last = activities.filter(a => a.user_id === 'user1').sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime()).slice(-1)[0].timestamp
      const daysDiff = Math.ceil((last.getTime() - first.getTime()) / (1000 * 60 * 60 * 24))
      const daysActive = Math.max(daysDiff, 1)
      const expectedActionsPerDay = parseFloat((5 / daysActive).toFixed(2))

      expect(result.actionsPerDay).toBe(expectedActionsPerDay)
    })

    it('uses at least 1 day when all activities are on same day', () => {
      const sameDayActivities: Activity[] = [
        {
          id: '1',
          user_id: 'u',
          action: 'a',
          timestamp: new Date('2024-01-01T10:00:00Z')
        },
        {
          id: '2',
          user_id: 'u',
          action: 'b',
          timestamp: new Date('2024-01-01T11:00:00Z')
        }
      ]
      const dash = new ActivityDashboard(sameDayActivities)
      const result = dash.getUserSummary('u')
      expect(result).not.toBeNull()
      if (!result) return
      expect(result.actionsPerDay).toBe(parseFloat((2 / 1).toFixed(2)))
    })

    it('calculates averageActionsPerSession based on 30 minute gaps', () => {
      const result = dashboard.getUserSummary('user1')
      expect(result).not.toBeNull()
      if (!result) return

      // user1 has 5 activities; timestamps:
      // 0, +10m, +20m, +40m, +26h
      // gaps: 10m, 10m, 20m, 1500m -> only last gap > 30m => 2 sessions
      const expectedAvg = parseFloat((5 / 2).toFixed(2))
      expect(result.averageActionsPerSession).toBe(expectedAvg)
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.getActivityTrends('unknown')
      expect(result).toEqual([])
    })

    it('groups activities by day and calculates growthRate', () => {
      const result = dashboard.getActivityTrends('user1', 'day')
      expect(result.length).toBeGreaterThanOrEqual(1)

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

    it('groups activities by hour', () => {
      const result = dashboard.getActivityTrends('user1', 'hour')
      expect(result.length).toBeGreaterThan(1)
      result.forEach(entry => {
        expect(entry.period).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:00$/)
      })
    })

    it('groups activities by week and month', () => {
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
    it('returns activities within inclusive date range for user', () => {
      const start = new Date('2024-01-01T00:05:00Z')
      const end = new Date('2024-01-01T00:30:00Z')

      const result = dashboard.filterByDateRange('user1', start, end)

      expect(result.every(a => a.user_id === 'user1')).toBe(true)
      expect(result.length).toBe(2)
      const ids = result.map(a => a.id).sort()
      expect(ids).toEqual(['2', '3'])
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date('2025-01-01T00:00:00Z')
      const end = new Date('2025-01-02T00:00:00Z')

      const result = dashboard.filterByDateRange('user1', start, end)
      expect(result).toEqual([])
    })

    it('includes activities exactly on start and end boundaries', () => {
      const userActs = activities.filter(a => a.user_id === 'user1')
      const start = userActs[0].timestamp
      const end = userActs[userActs.length - 1].timestamp

      const result = dashboard.filterByDateRange('user1', start, end)
      expect(result.length).toBe(userActs.length)
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.aggregateByAction('unknown')
      expect(result).toEqual([])
    })

    it('aggregates actions with counts, percentages and occurrences', () => {
      const result = dashboard.aggregateByAction('user1')

      const total = activities.filter(a => a.user_id === 'user1').length
      const loginGroup = result.find(g => g.action === 'login')
      const viewGroup = result.find(g => g.action === 'view')
      const logoutGroup = result.find(g => g.action === 'logout')

      expect(loginGroup).toBeDefined()
      expect(viewGroup).toBeDefined()
      expect(logoutGroup).toBeDefined()

      if (!loginGroup || !viewGroup || !logoutGroup) return

      expect(loginGroup.count).toBe(2)
      expect(viewGroup.count).toBe(2)
      expect(logoutGroup.count).toBe(1)

      expect(loginGroup.percentage).toBe(parseFloat(((2 / total) * 100).toFixed(2)))
      expect(viewGroup.percentage).toBe(parseFloat(((2 / total) * 100).toFixed(2)))
      expect(logoutGroup.percentage).toBe(parseFloat(((1 / total) * 100).toFixed(2)))

      const loginActs = activities.filter(a => a.user_id === 'user1' && a.action === 'login').sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime())
      expect(loginGroup.firstOccurrence.getTime()).toBe(loginActs[0].timestamp.getTime())
      expect(loginGroup.lastOccurrence.getTime()).toBe(loginActs[loginActs.length - 1].timestamp.getTime())
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
      const counts = result.map(r => r.count)
      const sortedCounts = [...counts].sort((a, b) => b - a)
      expect(counts).toEqual(sortedCounts)
      expect(result.length).toBe(3)
    })

    it('calculates percentages based on total actions', () => {
      const result = dashboard.getTopActions_old('user1')
      const total = activities.filter(a => a.user_id === 'user1').length

      result.forEach(group => {
        const acts = activities.filter(a => a.user_id === 'user1' && a.action === group.action)
        const expectedPercentage = parseFloat(((acts.length / total) * 100).toFixed(2))
        expect(group.percentage).toBe(expectedPercentage)
      })
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions based on limit', () => {
      const result = dashboard.getTopActions('user1', 2)
      expect(result.length).toBe(2)

      const full = dashboard.aggregateByAction('user1')
      expect(result[0].action).toBe(full[0].action)
      expect(result[1].action).toBe(full[1].action)
    })

    it('returns all actions when limit exceeds available', () => {
      const result = dashboard.getTopActions('user1', 10)
      const full = dashboard.aggregateByAction('user1')
      expect(result.length).toBe(full.length)
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

    it('caps each component of engagement score at its maximum', () => {
      const manyActivities: Activity[] = []
      const base = new Date('2024-01-01T00:00:00Z').getTime()
      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `a${i}`,
          user_id: 'heavy',
          action: `action${i % 20}`,
          timestamp: new Date(base + i * 60 * 60 * 1000)
        })
      }
      const dash = new ActivityDashboard(manyActivities)
      const score = dash.calculateEngagementScore('heavy')
      expect(score).toBeLessThanOrEqual(100)
    })
  })

  describe('period grouping edge cases', () => {
    it('uses default day period when invalid periodType is passed', () => {
      const anyDashboard: any = dashboard
      const userActs = activities.filter(a => a.user_id === 'user1')
      const grouped = anyDashboard.groupByPeriod(userActs, 'invalid')
      const keys = Object.keys(grouped)
      keys.forEach(k => {
        expect(k).toMatch(/^\d{4}-\d{2}-\d{2}$/)
      })
    })

    it('getWeekNumber produces increasing or equal week numbers over time', () => {
      const anyDashboard: any = dashboard
      const dates = [
        new Date('2024-01-01T00:00:00Z'),
        new Date('2024-01-08T00:00:00Z'),
        new Date('2024-02-01T00:00:00Z')
      ]
      const weeks = dates.map(d => anyDashboard.getWeekNumber(d))
      expect(weeks[1]).toBeGreaterThanOrEqual(weeks[0])
      expect(weeks[2]).toBeGreaterThanOrEqual(weeks[1])
    })
  })
})