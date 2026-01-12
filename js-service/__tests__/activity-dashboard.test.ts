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
        timestamp: new Date(baseDate.getTime() + 60 * 60 * 1000) // +1h
      },
      {
        id: '3',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(baseDate.getTime() + 2 * 60 * 60 * 1000) // +2h
      },
      {
        id: '4',
        user_id: 'user1',
        action: 'purchase',
        timestamp: new Date(baseDate.getTime() + 26 * 60 * 60 * 1000) // +26h (next day, new session)
      },
      {
        id: '5',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 3 * 60 * 60 * 1000)
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

      // totalActions: 4 activities for user1
      expect(result.totalActions).toBe(4)

      // uniqueActions: login, view, purchase
      expect(result.uniqueActions).toBe(3)

      // daysActive: from 0h to 26h => diff = 26h => 1.0833 days => ceil = 2
      // actionsPerDay = 4 / 2 = 2.00
      expect(result.actionsPerDay).toBe(2)

      // mostFrequentAction: 'view' appears twice
      expect(result.mostFrequentAction).toBe('view')

      // averageActionsPerSession:
      // timestamps: 0h, 1h, 2h, 26h
      // gaps: 1h, 1h, 24h -> last gap > 30min => 2 sessions
      // 4 actions / 2 sessions = 2.00
      expect(result.averageActionsPerSession).toBe(2)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: '10',
        user_id: 'single',
        action: 'login',
        timestamp: new Date('2024-02-01T10:00:00Z')
      }
      const singleDashboard = new ActivityDashboard([singleActivity])

      const result = singleDashboard.getUserSummary('single')
      expect(result).not.toBeNull()
      if (!result) return

      expect(result.totalActions).toBe(1)
      expect(result.uniqueActions).toBe(1)
      // daysActive: diff 0 => ceil(0) => 0, but Math.max(...,1) => 1
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

    it('groups activities by day and calculates growthRate', () => {
      const result = dashboard.getActivityTrends('user1', 'day')
      // user1 has 3 activities on 2024-01-01 and 1 on 2024-01-02
      expect(result.length).toBe(2)

      const first = result[0]
      const second = result[1]

      expect(first.period).toBe('2024-01-01')
      expect(first.count).toBe(3)
      expect(first.growthRate).toBe(0)

      expect(second.period).toBe('2024-01-02')
      expect(second.count).toBe(1)
      // growthRate = ((1 - 3) / 3) * 100 = -66.666... => -66.67
      expect(second.growthRate).toBe(-66.67)
    })

    it('groups activities by hour', () => {
      const result = dashboard.getActivityTrends('user1', 'hour')
      // user1 has activities at 0h,1h,2h,26h => 4 distinct hours
      expect(result.length).toBe(4)
      expect(result[0].period).toBe('2024-01-01 00:00')
      expect(result[0].count).toBe(1)
      expect(result[1].period).toBe('2024-01-01 01:00')
      expect(result[1].count).toBe(1)
      expect(result[2].period).toBe('2024-01-01 02:00')
      expect(result[2].count).toBe(1)
      expect(result[3].period).toBe('2024-01-02 02:00')
      expect(result[3].count).toBe(1)
    })

    it('groups activities by month and week using default behavior', () => {
      const resultMonth = dashboard.getActivityTrends('user1', 'month')
      expect(resultMonth.length).toBe(1)
      expect(resultMonth[0].period).toBe('2024-01')
      expect(resultMonth[0].count).toBe(4)

      const resultWeek = dashboard.getActivityTrends('user1', 'week')
      expect(resultWeek.length).toBe(1)
      expect(resultWeek[0].period.startsWith('2024-W')).toBe(true)
      expect(resultWeek[0].count).toBe(4)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within the inclusive date range for a user', () => {
      const start = new Date('2024-01-01T00:30:00Z')
      const end = new Date('2024-01-01T02:00:00Z')

      const result = dashboard.filterByDateRange('user1', start, end)

      // Should include activities at 1h and 2h, but not at 0h or 26h
      expect(result.map(a => a.id).sort()).toEqual(['2', '3'])
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date('2025-01-01T00:00:00Z')
      const end = new Date('2025-01-02T00:00:00Z')

      const result = dashboard.filterByDateRange('user1', start, end)
      expect(result).toEqual([])
    })

    it('filters by user id as well as date', () => {
      const start = new Date('2024-01-01T00:00:00Z')
      const end = new Date('2024-01-02T23:59:59Z')

      const resultUser1 = dashboard.filterByDateRange('user1', start, end)
      const resultUser2 = dashboard.filterByDateRange('user2', start, end)

      expect(resultUser1.length).toBe(4)
      expect(resultUser2.length).toBe(1)
      expect(resultUser2[0].user_id).toBe('user2')
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

      // Sorted by count descending: view(2), login(1), purchase(1)
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

      // Check first/last occurrence for 'view'
      const viewActivities = activities.filter(
        a => a.user_id === 'user1' && a.action === 'view'
      )
      const sortedViews = [...viewActivities].sort(
        (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
      )
      expect(result[0].firstOccurrence.getTime()).toBe(sortedViews[0].timestamp.getTime())
      expect(result[0].lastOccurrence.getTime()).toBe(sortedViews[1].timestamp.getTime())
    })

    it('does not mutate original activities array order', () => {
      const originalTimestamps = activities.map(a => a.timestamp.getTime())
      dashboard.aggregateByAction('user1')
      const afterTimestamps = activities.map(a => a.timestamp.getTime())
      expect(afterTimestamps).toEqual(originalTimestamps)
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count without applying limit', () => {
      const result = dashboard.getTopActions_old('user1', 1)

      // Should ignore limit and return all groups
      expect(result.length).toBe(3)
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(2)
    })

    it('calculates percentages based on total actions', () => {
      const result = dashboard.getTopActions_old('user1')

      const viewGroup = result.find(g => g.action === 'view')
      const loginGroup = result.find(g => g.action === 'login')
      const purchaseGroup = result.find(g => g.action === 'purchase')

      expect(viewGroup?.percentage).toBe(50)
      expect(loginGroup?.percentage).toBe(25)
      expect(purchaseGroup?.percentage).toBe(25)
    })
  })

  describe('getTopActions', () => {
    it('returns limited number of top actions', () => {
      const result = dashboard.getTopActions('user1', 2)
      expect(result.length).toBe(2)
      expect(result[0].action).toBe('view')
    })

    it('defaults to limit 5 when not provided', () => {
      const result = dashboard.getTopActions('user1')
      // Only 3 actions exist, so should return 3
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
      const result = dashboard.calculateEngagementScore('user1')
      // For user1:
      // totalActions = 4 => volumeScore = min(4/100,1)*30 = 1.2
      // uniqueActions = 3 => diversityScore = min(3/10,1)*30 = 9
      // actionsPerDay = 2 => frequencyScore = min(2/5,1)*40 = 16
      // total = 1.2 + 9 + 16 = 26.2 => toFixed(2) => 26.20
      expect(result).toBe(26.2)
    })

    it('caps each component at its maximum weight', () => {
      const manyActivities: Activity[] = []
      const base = new Date('2024-03-01T00:00:00Z').getTime()

      // 200 actions over 5 days, 20 unique actions
      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `m${i}`,
          user_id: 'power',
          action: `action${i % 20}`,
          timestamp: new Date(base + (i % 5) * 24 * 60 * 60 * 1000)
        })
      }

      const powerDashboard = new ActivityDashboard(manyActivities)
      const score = powerDashboard.calculateEngagementScore('power')

      // volumeScore: min(200/100,1)*30 = 30
      // diversityScore: min(20/10,1)*30 = 30
      // actionsPerDay: total 200 / daysActive 5 = 40 => min(40/5,1)*40 = 40
      // total = 100
      expect(score).toBe(100)
    })
  })

  describe('private behavior via public methods', () => {
    it('uses default periodType "day" when not provided in getActivityTrends', () => {
      const resultExplicit = dashboard.getActivityTrends('user1', 'day')
      const resultDefault = dashboard.getActivityTrends('user1')
      expect(resultDefault).toEqual(resultExplicit)
    })

    it('handles unknown periodType by falling back to day in getPeriodKey', () => {
      // Accessing private via casting to any to trigger default case
      const anyDashboard: any = dashboard
      const date = new Date('2024-01-01T12:34:56Z')
      const key = anyDashboard.getPeriodKey(date, 'unknown')
      expect(key).toBe('2024-01-01')
    })

    it('computes week number consistently for known dates', () => {
      const anyDashboard: any = dashboard
      const date = new Date('2024-01-01T00:00:00Z')
      const weekNumber = anyDashboard.getWeekNumber(date)
      expect(typeof weekNumber).toBe('number')
      expect(weekNumber).toBeGreaterThanOrEqual(1)
      expect(weekNumber).toBeLessThanOrEqual(53)
    })
  })
})