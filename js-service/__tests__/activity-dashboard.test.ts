import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

describe('ActivityDashboard', () => {
  let baseDate: Date
  let activities: Activity[]
  let dashboard: ActivityDashboard

  beforeEach(() => {
    baseDate = new Date('2024-01-01T00:00:00Z')

    activities = [
      // user1 - multiple actions over several days and sessions
      {
        id: '1',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date('2024-01-01T09:00:00Z')
      },
      {
        id: '2',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date('2024-01-01T09:10:00Z')
      },
      {
        id: '3',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date('2024-01-01T09:20:00Z')
      },
      {
        id: '4',
        user_id: 'user1',
        action: 'purchase',
        timestamp: new Date('2024-01-02T10:00:00Z')
      },
      {
        id: '5',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date('2024-01-03T12:00:00Z')
      },
      // gap > 30 minutes to create new session
      {
        id: '6',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date('2024-01-03T13:00:00Z')
      },
      // user2 - fewer actions
      {
        id: '7',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date('2024-01-01T08:00:00Z')
      },
      {
        id: '8',
        user_id: 'user2',
        action: 'view',
        timestamp: new Date('2024-01-01T08:05:00Z')
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

      // totalActions: all activities for user1
      expect(result.totalActions).toBe(6)

      // uniqueActions: login, view, purchase
      expect(result.uniqueActions).toBe(3)

      // daysActive: from 2024-01-01 09:00 to 2024-01-03 13:00
      // diff ~ 2.1667 days -> ceil = 3
      // actionsPerDay = 6 / 3 = 2.00
      expect(result.actionsPerDay).toBe(2)

      // mostFrequentAction: 'view' (3 times)
      expect(result.mostFrequentAction).toBe('view')

      // averageActionsPerSession:
      // sessions determined by 30-minute gaps
      // user1 timestamps:
      // 01 09:00, 09:10, 09:20 (session1)
      // 02 10:00 (gap > 30m from previous day -> session2)
      // 03 12:00 (gap > 30m from previous day -> session3)
      // 03 13:00 (gap 60m from 12:00 -> session4)
      // sessions = 4, actions = 6 -> 6/4 = 1.5 -> 1.50
      expect(result.averageActionsPerSession).toBe(1.5)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: '9',
        user_id: 'single',
        action: 'login',
        timestamp: new Date('2024-01-05T10:00:00Z')
      }
      const singleDashboard = new ActivityDashboard([singleActivity])

      const result = singleDashboard.getUserSummary('single')
      expect(result).not.toBeNull()
      if (!result) return

      expect(result.totalActions).toBe(1)
      expect(result.uniqueActions).toBe(1)
      // daysActive: diff 0 -> max(ceil(0),1) = 1
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

      // user1 days:
      // 2024-01-01: 3 actions
      // 2024-01-02: 1 action
      // 2024-01-03: 2 actions
      expect(result.length).toBe(3)

      const day1 = result[0]
      const day2 = result[1]
      const day3 = result[2]

      expect(day1.period).toBe('2024-01-01')
      expect(day1.count).toBe(3)
      expect(day1.growthRate).toBe(0)

      expect(day2.period).toBe('2024-01-02')
      expect(day2.count).toBe(1)
      // growth from 3 to 1: ((1-3)/3)*100 = -66.67 -> -66.67
      expect(day2.growthRate).toBe(-66.67)

      expect(day3.period).toBe('2024-01-03')
      expect(day3.count).toBe(2)
      // growth from 1 to 2: ((2-1)/1)*100 = 100.00
      expect(day3.growthRate).toBe(100)
    })

    it('groups activities by hour correctly', () => {
      const result = dashboard.getActivityTrends('user2', 'hour')

      // user2:
      // 2024-01-01T08:00 and 08:05 -> same hour
      expect(result.length).toBe(1)
      expect(result[0].period).toBe('2024-01-01 08:00')
      expect(result[0].count).toBe(2)
      expect(result[0].growthRate).toBe(0)
    })

    it('groups activities by month and week', () => {
      const monthTrends = dashboard.getActivityTrends('user1', 'month')
      expect(monthTrends.length).toBe(1)
      expect(monthTrends[0].period).toBe('2024-01')
      expect(monthTrends[0].count).toBe(6)

      const weekTrends = dashboard.getActivityTrends('user1', 'week')
      expect(weekTrends.length).toBe(1)
      expect(weekTrends[0].count).toBe(6)
      expect(weekTrends[0].growthRate).toBe(0)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within inclusive date range for user', () => {
      const start = new Date('2024-01-01T09:05:00Z')
      const end = new Date('2024-01-02T23:59:59Z')

      const result = dashboard.filterByDateRange('user1', start, end)

      // user1 activities in this range: ids 2,3,4
      const ids = result.map(a => a.id).sort()
      expect(ids).toEqual(['2', '3', '4'])
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date('2025-01-01T00:00:00Z')
      const end = new Date('2025-01-02T00:00:00Z')

      const result = dashboard.filterByDateRange('user1', start, end)
      expect(result).toEqual([])
    })

    it('respects userId filter', () => {
      const start = new Date('2024-01-01T00:00:00Z')
      const end = new Date('2024-01-02T00:00:00Z')

      const result = dashboard.filterByDateRange('user2', start, end)
      const userIds = Array.from(new Set(result.map(a => a.user_id)))
      expect(userIds).toEqual(['user2'])
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.aggregateByAction('unknown')
      expect(result).toEqual([])
    })

    it('aggregates actions with counts, percentages and occurrences', () => {
      const result = dashboard.aggregateByAction('user1')

      // user1 actions:
      // login: 2, view: 3, purchase: 1
      expect(result.length).toBe(3)

      // sorted by count desc: view (3), login (2), purchase (1)
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(3)
      expect(result[0].percentage).toBeCloseTo((3 / 6) * 100, 2)
      expect(result[0].firstOccurrence).toEqual(new Date('2024-01-01T09:10:00Z'))
      expect(result[0].lastOccurrence).toEqual(new Date('2024-01-03T12:00:00Z'))

      expect(result[1].action).toBe('login')
      expect(result[1].count).toBe(2)
      expect(result[1].percentage).toBeCloseTo((2 / 6) * 100, 2)

      expect(result[2].action).toBe('purchase')
      expect(result[2].count).toBe(1)
      expect(result[2].percentage).toBeCloseTo((1 / 6) * 100, 2)
    })

    it('handles single action type correctly', () => {
      const acts: Activity[] = [
        {
          id: 'a1',
          user_id: 'u',
          action: 'only',
          timestamp: new Date('2024-01-01T00:00:00Z')
        },
        {
          id: 'a2',
          user_id: 'u',
          action: 'only',
          timestamp: new Date('2024-01-01T01:00:00Z')
        }
      ]
      const d = new ActivityDashboard(acts)
      const result = d.aggregateByAction('u')

      expect(result.length).toBe(1)
      expect(result[0].action).toBe('only')
      expect(result[0].count).toBe(2)
      expect(result[0].percentage).toBe(100)
      expect(result[0].firstOccurrence).toEqual(acts[0].timestamp)
      expect(result[0].lastOccurrence).toEqual(acts[1].timestamp)
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count desc without limiting', () => {
      const result = dashboard.getTopActions_old('user1')

      expect(result.length).toBe(3)
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(3)
      expect(result[1].action).toBe('login')
      expect(result[1].count).toBe(2)
      expect(result[2].action).toBe('purchase')
      expect(result[2].count).toBe(1)
    })

    it('calculates percentages based on total actions', () => {
      const result = dashboard.getTopActions_old('user2')

      // user2: 2 actions, 1 login, 1 view
      const login = result.find(r => r.action === 'login')
      const view = result.find(r => r.action === 'view')

      expect(login?.percentage).toBe(50)
      expect(view?.percentage).toBe(50)
    })
  })

  describe('getTopActions', () => {
    it('returns limited number of top actions using aggregateByAction', () => {
      const spy = jest.spyOn(dashboard as any, 'aggregateByAction')
      const result = dashboard.getTopActions('user1', 2)

      expect(spy).toHaveBeenCalledWith('user1')
      expect(result.length).toBe(2)
      expect(result[0].count).toBeGreaterThanOrEqual(result[1].count)
    })

    it('defaults limit to 5 when not provided', () => {
      const result = dashboard.getTopActions('user1')
      // only 3 actions exist, so should return 3
      expect(result.length).toBe(3)
    })

    it('returns empty array when user has no actions', () => {
      const result = dashboard.getTopActions('unknown', 3)
      expect(result).toEqual([])
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when user has no summary', () => {
      const result = dashboard.calculateEngagementScore('unknown')
      expect(result).toBe(0)
    })

    it('calculates engagement score based on summary metrics', () => {
      const result = dashboard.calculateEngagementScore('user1')

      // For user1:
      // totalActions = 6 -> volumeScore = min(6/100,1)*30 = 1.8
      // uniqueActions = 3 -> diversityScore = min(3/10,1)*30 = 9
      // actionsPerDay = 2 -> frequencyScore = min(2/5,1)*40 = 16
      // total = 1.8 + 9 + 16 = 26.8 -> 26.80
      expect(result).toBe(26.8)
    })

    it('caps each component at its maximum', () => {
      const manyActivities: Activity[] = []
      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `m${i}`,
          user_id: 'heavy',
          action: `action${i % 20}`, // 20 unique actions
          timestamp: new Date(2024, 0, 1, 0, i)
        })
      }
      const d = new ActivityDashboard(manyActivities)
      const score = d.calculateEngagementScore('heavy')

      // totalActions/100 >= 1 -> 30
      // uniqueActions/10 >= 1 -> 30
      // actionsPerDay/5 likely >= 1 -> 40
      // total capped at 100
      expect(score).toBe(100)
    })
  })
})