import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

describe('ActivityDashboard', () => {
  let baseDate: Date
  let activities: Activity[]
  let dashboard: ActivityDashboard

  beforeEach(() => {
    baseDate = new Date('2024-01-01T00:00:00.000Z')

    activities = [
      {
        id: '1',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(baseDate.getTime()),
      },
      {
        id: '2',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(baseDate.getTime() + 10 * 60 * 1000), // +10 min
      },
      {
        id: '3',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(baseDate.getTime() + 20 * 60 * 1000), // +20 min
      },
      {
        id: '4',
        user_id: 'user1',
        action: 'purchase',
        timestamp: new Date(baseDate.getTime() + 40 * 60 * 1000), // +40 min
      },
      {
        id: '5',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 26 * 60 * 60 * 1000), // +26 hours (next day +2h)
      },
      {
        id: '6',
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

      // totalActions: all activities for user1
      expect(result.totalActions).toBe(5)

      // uniqueActions: login, view, purchase
      expect(result.uniqueActions).toBe(3)

      // daysActive: from first to last timestamp
      const first = activities.filter(a => a.user_id === 'user1').sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime())[0].timestamp
      const last = activities.filter(a => a.user_id === 'user1').sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime()).slice(-1)[0].timestamp
      const daysDiff = Math.ceil((last.getTime() - first.getTime()) / (1000 * 60 * 60 * 24))
      const daysActive = Math.max(daysDiff, 1)
      const expectedActionsPerDay = parseFloat((5 / daysActive).toFixed(2))
      expect(result.actionsPerDay).toBe(expectedActionsPerDay)

      // mostFrequentAction: 'view' appears twice, others once
      expect(result.mostFrequentAction).toBe('view')

      // averageActionsPerSession: sessions split by >30 minutes gap
      // user1 timestamps: 0, 10, 20, 40 minutes, 26h
      // gaps: 10,10,20, 26h-40m (~25h20m) -> last gap >30 => 2 sessions
      const expectedAvgPerSession = parseFloat((5 / 2).toFixed(2))
      expect(result.averageActionsPerSession).toBe(expectedAvgPerSession)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: 'single',
        user_id: 'singleUser',
        action: 'login',
        timestamp: new Date('2024-02-01T12:00:00.000Z'),
      }
      const singleDashboard = new ActivityDashboard([singleActivity])

      const result = singleDashboard.getUserSummary('singleUser')
      expect(result).not.toBeNull()
      if (!result) return

      expect(result.totalActions).toBe(1)
      expect(result.uniqueActions).toBe(1)
      expect(result.actionsPerDay).toBe(1) // daysActive = 1
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

      // user1 has 4 activities on day 1 and 1 on day 2
      expect(result.length).toBe(2)

      const day1 = result[0]
      const day2 = result[1]

      expect(day1.count).toBe(4)
      expect(day1.growthRate).toBe(0)

      expect(day2.count).toBe(1)
      const expectedGrowth = parseFloat((((1 - 4) / 4) * 100).toFixed(2))
      expect(day2.growthRate).toBe(expectedGrowth)
    })

    it('groups activities by hour', () => {
      const result = dashboard.getActivityTrends('user1', 'hour')

      // First four activities are within first hour window (0-40min)
      // Last activity is at +26h -> different hour and day
      const periods = result.map(r => r.period)
      expect(periods.length).toBe(2)

      const firstPeriod = result.find(r => r.count === 4)
      const secondPeriod = result.find(r => r.count === 1)

      expect(firstPeriod).toBeDefined()
      expect(secondPeriod).toBeDefined()
      if (!firstPeriod || !secondPeriod) return

      expect(firstPeriod.growthRate).toBe(0)
      const expectedGrowth = parseFloat((((1 - 4) / 4) * 100).toFixed(2))
      expect(secondPeriod.growthRate).toBe(expectedGrowth)
    })

    it('groups activities by month and week using default sorting', () => {
      const resultMonth = dashboard.getActivityTrends('user1', 'month')
      expect(resultMonth.length).toBe(1)
      expect(resultMonth[0].count).toBe(5)
      expect(resultMonth[0].growthRate).toBe(0)

      const resultWeek = dashboard.getActivityTrends('user1', 'week')
      expect(resultWeek.length).toBe(1)
      expect(resultWeek[0].count).toBe(5)
      expect(resultWeek[0].growthRate).toBe(0)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within inclusive date range for user', () => {
      const start = new Date(baseDate.getTime() + 5 * 60 * 1000) // between first and second
      const end = new Date(baseDate.getTime() + 30 * 60 * 1000) // between third and fourth

      const result = dashboard.filterByDateRange('user1', start, end)

      // Should include activities at 10 and 20 minutes only
      expect(result.map(a => a.id)).toEqual(['2', '3'])
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date(baseDate.getTime() - 2 * 60 * 60 * 1000)
      const end = new Date(baseDate.getTime() - 1 * 60 * 60 * 1000)

      const result = dashboard.filterByDateRange('user1', start, end)
      expect(result).toEqual([])
    })

    it('filters by user id as well as date', () => {
      const start = new Date(baseDate.getTime())
      const end = new Date(baseDate.getTime() + 60 * 60 * 1000)

      const resultUser1 = dashboard.filterByDateRange('user1', start, end)
      const resultUser2 = dashboard.filterByDateRange('user2', start, end)

      expect(resultUser1.some(a => a.user_id !== 'user1')).toBe(false)
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

      // user1 actions: login x2, view x2, purchase x1
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

      const user1Activities = activities.filter(a => a.user_id === 'user1')
      const loginActs = user1Activities.filter(a => a.action === 'login').sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime())
      expect(loginGroup.firstOccurrence.getTime()).toBe(loginActs[0].timestamp.getTime())
      expect(loginGroup.lastOccurrence.getTime()).toBe(loginActs[loginActs.length - 1].timestamp.getTime())
    })

    it('sorts groups by count descending', () => {
      const result = dashboard.aggregateByAction('user1')
      const counts = result.map(g => g.count)
      const sortedCounts = [...counts].sort((a, b) => b - a)
      expect(counts).toEqual(sortedCounts)
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count without applying limit', () => {
      const result = dashboard.getTopActions_old('user1', 1)

      // Should still return all 3 groups
      expect(result.length).toBe(3)

      const counts = result.map(g => g.count)
      const sortedCounts = [...counts].sort((a, b) => b - a)
      expect(counts).toEqual(sortedCounts)
    })

    it('calculates percentages and occurrences same as aggregateByAction', () => {
      const oldResult = dashboard.getTopActions_old('user1')
      const newResult = dashboard.aggregateByAction('user1')

      // Compare by action
      oldResult.forEach(oldGroup => {
        const match = newResult.find(g => g.action === oldGroup.action)
        expect(match).toBeDefined()
        if (!match) return
        expect(oldGroup.count).toBe(match.count)
        expect(oldGroup.percentage).toBe(match.percentage)
        expect(oldGroup.firstOccurrence.getTime()).toBe(match.firstOccurrence.getTime())
        expect(oldGroup.lastOccurrence.getTime()).toBe(match.lastOccurrence.getTime())
      })
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions based on limit', () => {
      const result = dashboard.getTopActions('user1', 2)
      expect(result.length).toBe(2)

      const counts = result.map(g => g.count)
      const sortedCounts = [...counts].sort((a, b) => b - a)
      expect(counts).toEqual(sortedCounts)
    })

    it('returns all actions when limit exceeds available groups', () => {
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
      const expectedScore = parseFloat((volumeScore + diversityScore + frequencyScore).toFixed(2))

      const result = dashboard.calculateEngagementScore('user1')
      expect(result).toBe(expectedScore)
    })

    it('caps each component score at its maximum', () => {
      const manyActivities: Activity[] = []
      const userId = 'heavyUser'
      const start = new Date('2024-01-01T00:00:00.000Z').getTime()

      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `a-${i}`,
          user_id: userId,
          action: `action-${i % 20}`, // 20 unique actions
          timestamp: new Date(start + i * 60 * 1000),
        })
      }

      const heavyDashboard = new ActivityDashboard(manyActivities)
      const score = heavyDashboard.calculateEngagementScore(userId)

      // All components should be capped at their max: 30 + 30 + 40 = 100
      expect(score).toBe(100)
    })
  })
})