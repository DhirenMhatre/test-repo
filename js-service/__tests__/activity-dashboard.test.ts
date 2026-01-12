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
        timestamp: new Date(baseDate.getTime() + 31 * 60 * 1000), // new session (>30min gap)
      },
      {
        id: '5',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 40 * 60 * 1000),
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

      expect(result.totalActions).toBe(4)
      expect(result.uniqueActions).toBe(3)
      expect(result.mostFrequentAction).toBe('view')

      // daysActive: last - first = 31min -> <1 day -> ceil(0.xxx) = 1
      // actionsPerDay = 4 / 1 = 4.00
      expect(result.actionsPerDay).toBe(4)

      // sessions: first 3 within 30min -> 1 session, last is 31min after previous -> 2 sessions
      // avg per session = 4 / 2 = 2.00
      expect(result.averageActionsPerSession).toBe(2)
    })

    it('handles activities spanning multiple days for actionsPerDay', () => {
      const longSpanActivities: Activity[] = [
        {
          id: '1',
          user_id: 'user3',
          action: 'a',
          timestamp: new Date('2024-01-01T00:00:00Z'),
        },
        {
          id: '2',
          user_id: 'user3',
          action: 'b',
          timestamp: new Date('2024-01-03T00:00:00Z'),
        },
      ]
      const dash = new ActivityDashboard(longSpanActivities)
      const result = dash.getUserSummary('user3')
      expect(result).not.toBeNull()
      if (!result) return

      // diff = 2 days -> ceil(2) = 2, totalActions=2 -> 1.00
      expect(result.actionsPerDay).toBe(1)
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.getActivityTrends('unknown')
      expect(result).toEqual([])
    })

    it('groups activities by day and calculates growthRate', () => {
      const multiDayActivities: Activity[] = [
        {
          id: '1',
          user_id: 'user4',
          action: 'a',
          timestamp: new Date('2024-01-01T10:00:00Z'),
        },
        {
          id: '2',
          user_id: 'user4',
          action: 'b',
          timestamp: new Date('2024-01-01T11:00:00Z'),
        },
        {
          id: '3',
          user_id: 'user4',
          action: 'c',
          timestamp: new Date('2024-01-02T10:00:00Z'),
        },
        {
          id: '4',
          user_id: 'user4',
          action: 'd',
          timestamp: new Date('2024-01-03T10:00:00Z'),
        },
        {
          id: '5',
          user_id: 'user4',
          action: 'e',
          timestamp: new Date('2024-01-03T11:00:00Z'),
        },
      ]
      const dash = new ActivityDashboard(multiDayActivities)
      const result = dash.getActivityTrends('user4', 'day')

      expect(result).toHaveLength(3)
      expect(result[0]).toEqual({
        period: '2024-01-01',
        count: 2,
        growthRate: 0,
      })
      // day2: 1 vs prev 2 -> ((1-2)/2)*100 = -50.00
      expect(result[1]).toEqual({
        period: '2024-01-02',
        count: 1,
        growthRate: -50,
      })
      // day3: 2 vs prev 1 -> ((2-1)/1)*100 = 100.00
      expect(result[2]).toEqual({
        period: '2024-01-03',
        count: 2,
        growthRate: 100,
      })
    })

    it('groups activities by hour', () => {
      const hourlyActivities: Activity[] = [
        {
          id: '1',
          user_id: 'user5',
          action: 'a',
          timestamp: new Date('2024-01-01T10:15:00Z'),
        },
        {
          id: '2',
          user_id: 'user5',
          action: 'b',
          timestamp: new Date('2024-01-01T10:45:00Z'),
        },
        {
          id: '3',
          user_id: 'user5',
          action: 'c',
          timestamp: new Date('2024-01-01T11:00:00Z'),
        },
      ]
      const dash = new ActivityDashboard(hourlyActivities)
      const result = dash.getActivityTrends('user5', 'hour')

      expect(result.map(r => r.period)).toEqual([
        '2024-01-01 10:00',
        '2024-01-01 11:00',
      ])
      expect(result[0].count).toBe(2)
      expect(result[1].count).toBe(1)
    })

    it('groups activities by week and month', () => {
      const weeklyActivities: Activity[] = [
        {
          id: '1',
          user_id: 'user6',
          action: 'a',
          timestamp: new Date('2024-01-01T00:00:00Z'),
        },
        {
          id: '2',
          user_id: 'user6',
          action: 'b',
          timestamp: new Date('2024-01-10T00:00:00Z'),
        },
        {
          id: '3',
          user_id: 'user6',
          action: 'c',
          timestamp: new Date('2024-02-01T00:00:00Z'),
        },
      ]
      const dash = new ActivityDashboard(weeklyActivities)

      const weekTrends = dash.getActivityTrends('user6', 'week')
      expect(weekTrends.length).toBeGreaterThanOrEqual(2)
      expect(weekTrends[0].period.startsWith('2024-W')).toBe(true)

      const monthTrends = dash.getActivityTrends('user6', 'month')
      expect(monthTrends.map(t => t.period)).toEqual(['2024-01', '2024-02'])
      expect(monthTrends[0].count).toBe(2)
      expect(monthTrends[1].count).toBe(1)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within inclusive date range for a user', () => {
      const start = new Date(baseDate.getTime() + 10 * 60 * 1000)
      const end = new Date(baseDate.getTime() + 31 * 60 * 1000)

      const result = dashboard.filterByDateRange('user1', start, end)

      // should include ids 2,3,4 (timestamps 10,20,31 minutes)
      const ids = result.map(a => a.id).sort()
      expect(ids).toEqual(['2', '3', '4'])
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date(baseDate.getTime() + 1000 * 60 * 60)
      const end = new Date(baseDate.getTime() + 2000 * 60 * 60)

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

      expect(result).toHaveLength(3)
      // sorted by count desc: view(2), login(1), purchase(1)
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(2)
      expect(result[0].percentage).toBeCloseTo(50)

      const loginGroup = result.find(g => g.action === 'login')
      expect(loginGroup).toBeDefined()
      if (!loginGroup) return
      expect(loginGroup.count).toBe(1)
      expect(loginGroup.percentage).toBeCloseTo(25)

      const purchaseGroup = result.find(g => g.action === 'purchase')
      expect(purchaseGroup).toBeDefined()
      if (!purchaseGroup) return
      expect(purchaseGroup.count).toBe(1)
      expect(purchaseGroup.percentage).toBeCloseTo(25)

      // first and last occurrence for 'view'
      const viewActivities = activities.filter(
        a => a.user_id === 'user1' && a.action === 'view'
      )
      const viewGroup = result.find(g => g.action === 'view')
      expect(viewGroup?.firstOccurrence.getTime()).toBe(
        Math.min(...viewActivities.map(a => a.timestamp.getTime()))
      )
      expect(viewGroup?.lastOccurrence.getTime()).toBe(
        Math.max(...viewActivities.map(a => a.timestamp.getTime()))
      )
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count without applying limit', () => {
      const result = dashboard.getTopActions_old('user1', 1)

      // limit is ignored in old version
      expect(result).toHaveLength(3)
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(2)
    })

    it('calculates percentages based on total actions', () => {
      const result = dashboard.getTopActions_old('user1')

      const total = 4
      const view = result.find(r => r.action === 'view')
      const login = result.find(r => r.action === 'login')

      expect(view?.percentage).toBeCloseTo((2 / total) * 100)
      expect(login?.percentage).toBeCloseTo((1 / total) * 100)
    })
  })

  describe('getTopActions', () => {
    it('returns limited number of top actions', () => {
      const result = dashboard.getTopActions('user1', 2)
      expect(result).toHaveLength(2)
      expect(result[0].count).toBeGreaterThanOrEqual(result[1].count)
    })

    it('defaults limit to 5 when not provided', () => {
      const result = dashboard.getTopActions('user1')
      // only 3 actions exist, so should return 3
      expect(result).toHaveLength(3)
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
      const userId = 'heavyUser'
      const start = new Date('2024-01-01T00:00:00Z')

      // 200 actions over 1 day, 20 unique actions
      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `a-${i}`,
          user_id: userId,
          action: `action-${i % 20}`,
          timestamp: new Date(start.getTime() + i * 60 * 1000),
        })
      }

      const dash = new ActivityDashboard(manyActivities)
      const score = dash.calculateEngagementScore(userId)

      // volumeScore capped at 30, diversityScore at 30, frequencyScore at 40 -> total 100
      expect(score).toBe(100)
    })
  })

  describe('session calculation via getUserSummary', () => {
    it('treats gaps greater than 30 minutes as new sessions', () => {
      const userId = 'sessionUser'
      const sessionActivities: Activity[] = [
        {
          id: '1',
          user_id: userId,
          action: 'a',
          timestamp: new Date('2024-01-01T00:00:00Z'),
        },
        {
          id: '2',
          user_id: userId,
          action: 'b',
          timestamp: new Date('2024-01-01T00:20:00Z'),
        },
        {
          id: '3',
          user_id: userId,
          action: 'c',
          timestamp: new Date('2024-01-01T01:00:01Z'), // 40m+ gap
        },
      ]
      const dash = new ActivityDashboard(sessionActivities)
      const summary = dash.getUserSummary(userId)
      expect(summary).not.toBeNull()
      if (!summary) return

      // 3 actions, 2 sessions -> 1.50
      expect(summary.averageActionsPerSession).toBe(1.5)
    })

    it('returns 0 averageActionsPerSession when user has no activities', () => {
      const dash = new ActivityDashboard([])
      const summary = dash.getUserSummary('nobody')
      expect(summary).toBeNull()
    })
  })
})