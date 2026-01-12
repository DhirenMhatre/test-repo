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
        timestamp: new Date(baseDate.getTime() + 2 * 24 * 60 * 60 * 1000) // +2 days
      },
      {
        id: '6',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 3 * 24 * 60 * 60 * 1000) // +3 days
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

      // user1 has 5 activities
      expect(result.totalActions).toBe(5)

      // actions: login, view, logout => 3 unique
      expect(result.uniqueActions).toBe(3)

      // first at day 0, last at day 2 => diff = 2 days, ceil(2) = 2
      // actionsPerDay = 5 / 2 = 2.5 -> toFixed(2) => 2.50 -> 2.5
      expect(result.actionsPerDay).toBe(2.5)

      // most frequent action is 'view' (2 times)
      expect(result.mostFrequentAction).toBe('view')

      // sessions: gap > 30 minutes splits sessions
      // timestamps: 0, 10, 20, 40 minutes, then +2 days
      // gaps: 10, 10, 20, then large gap > 30 => 2 sessions
      // averageActionsPerSession = 5 / 2 = 2.5 -> 2.50
      expect(result.averageActionsPerSession).toBe(2.5)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: 'single',
        user_id: 'singleUser',
        action: 'only',
        timestamp: new Date('2024-01-10T12:00:00Z')
      }
      const singleDashboard = new ActivityDashboard([singleActivity])

      const result = singleDashboard.getUserSummary('singleUser')
      expect(result).not.toBeNull()
      if (!result) return

      expect(result.totalActions).toBe(1)
      expect(result.uniqueActions).toBe(1)
      // daysActive: diff 0 => ceil(0) => 0, but Math.max(...,1) => 1
      expect(result.actionsPerDay).toBe(1)
      expect(result.mostFrequentAction).toBe('only')
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

      // user1 has activities on day 0 and day 2
      expect(result.length).toBe(2)

      const periods = result.map(r => r.period)
      expect(periods[0]).toBe('2024-01-01')
      expect(periods[1]).toBe('2024-01-03')

      const first = result[0]
      const second = result[1]

      expect(first.count).toBe(4) // 4 activities on day 1
      expect(first.growthRate).toBe(0) // first period has 0 growth

      expect(second.count).toBe(1) // 1 activity on day 3
      // growthRate = ((1 - 4) / 4) * 100 = -75 => -75.00
      expect(second.growthRate).toBe(-75)
    })

    it('groups activities by hour', () => {
      const result = dashboard.getActivityTrends('user1', 'hour')

      // All first 4 activities are within same hour (00:00Z), last is 2 days later same hour
      const periods = result.map(r => r.period)
      expect(periods).toContain('2024-01-01 00:00')
      expect(periods).toContain('2024-01-03 00:00')

      const firstHour = result.find(r => r.period === '2024-01-01 00:00')
      const secondHour = result.find(r => r.period === '2024-01-03 00:00')

      expect(firstHour?.count).toBe(4)
      expect(firstHour?.growthRate).toBe(0)
      expect(secondHour?.count).toBe(1)
      expect(secondHour?.growthRate).toBe(-75)
    })

    it('groups activities by week and month', () => {
      const weekTrends = dashboard.getActivityTrends('user1', 'week')
      const monthTrends = dashboard.getActivityTrends('user1', 'month')

      expect(weekTrends.length).toBeGreaterThanOrEqual(1)
      expect(monthTrends.length).toBe(1)

      expect(monthTrends[0].period).toBe('2024-01')
      expect(monthTrends[0].count).toBe(5)
      expect(monthTrends[0].growthRate).toBe(0)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within inclusive date range for user', () => {
      const start = new Date('2024-01-01T00:10:00Z')
      const end = new Date('2024-01-01T00:40:00Z')

      const result = dashboard.filterByDateRange('user1', start, end)

      // Should include ids 2,3,4 (10,20,40 minutes)
      const ids = result.map(a => a.id).sort()
      expect(ids).toEqual(['2', '3', '4'])
    })

    it('excludes activities outside date range and for other users', () => {
      const start = new Date('2024-01-02T00:00:00Z')
      const end = new Date('2024-01-04T00:00:00Z')

      const resultUser1 = dashboard.filterByDateRange('user1', start, end)
      const resultUser2 = dashboard.filterByDateRange('user2', start, end)

      // user1 has one activity at +2 days
      expect(resultUser1.length).toBe(1)
      expect(resultUser1[0].id).toBe('5')

      // user2 has one activity at +3 days
      expect(resultUser2.length).toBe(1)
      expect(resultUser2[0].id).toBe('6')
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.aggregateByAction('unknown')
      expect(result).toEqual([])
    })

    it('aggregates actions with counts, percentages and occurrences', () => {
      const result = dashboard.aggregateByAction('user1')

      // actions: login(2), view(2), logout(1)
      expect(result.length).toBe(3)

      // sorted by count desc: login and view (2), then logout (1)
      expect(result[0].count).toBeGreaterThanOrEqual(result[1].count)
      expect(result[2].count).toBe(1)

      const loginGroup = result.find(g => g.action === 'login')
      const viewGroup = result.find(g => g.action === 'view')
      const logoutGroup = result.find(g => g.action === 'logout')

      expect(loginGroup?.count).toBe(2)
      expect(viewGroup?.count).toBe(2)
      expect(logoutGroup?.count).toBe(1)

      // total = 5
      expect(loginGroup?.percentage).toBe(40)
      expect(viewGroup?.percentage).toBe(40)
      expect(logoutGroup?.percentage).toBe(20)

      // first and last occurrence timestamps
      expect(loginGroup?.firstOccurrence.getTime()).toBe(activities[0].timestamp.getTime())
      expect(loginGroup?.lastOccurrence.getTime()).toBe(activities[4].timestamp.getTime())
    })

    it('sorts groups by count descending', () => {
      const customActivities: Activity[] = [
        {
          id: '1',
          user_id: 'u',
          action: 'a',
          timestamp: new Date('2024-01-01T00:00:00Z')
        },
        {
          id: '2',
          user_id: 'u',
          action: 'b',
          timestamp: new Date('2024-01-01T01:00:00Z')
        },
        {
          id: '3',
          user_id: 'u',
          action: 'b',
          timestamp: new Date('2024-01-01T02:00:00Z')
        }
      ]
      const d = new ActivityDashboard(customActivities)
      const result = d.aggregateByAction('u')

      expect(result.map(g => g.action)).toEqual(['b', 'a'])
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count without applying limit', () => {
      const result = dashboard.getTopActions_old('user1', 1)

      // Should ignore limit and return all 3 actions
      expect(result.length).toBe(3)

      const actions = result.map(r => r.action)
      expect(actions).toContain('login')
      expect(actions).toContain('view')
      expect(actions).toContain('logout')

      const login = result.find(r => r.action === 'login')
      const view = result.find(r => r.action === 'view')
      const logout = result.find(r => r.action === 'logout')

      expect(login?.count).toBe(2)
      expect(view?.count).toBe(2)
      expect(logout?.count).toBe(1)
    })

    it('calculates percentages and occurrences same as aggregateByAction', () => {
      const result = dashboard.getTopActions_old('user1')

      const login = result.find(r => r.action === 'login')
      expect(login?.percentage).toBe(40)
      expect(login?.firstOccurrence.getTime()).toBe(activities[0].timestamp.getTime())
      expect(login?.lastOccurrence.getTime()).toBe(activities[4].timestamp.getTime())
    })
  })

  describe('getTopActions', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.getTopActions('unknown')
      expect(result).toEqual([])
    })

    it('returns top N actions based on aggregateByAction', () => {
      const result = dashboard.getTopActions('user1', 2)

      // aggregateByAction sorted by count desc; login and view both 2, logout 1
      expect(result.length).toBe(2)
      const actions = result.map(r => r.action)
      expect(actions).toContain('login')
      expect(actions).toContain('view')
      expect(actions).not.toContain('logout')
    })

    it('defaults limit to 5 when not provided', () => {
      const result = dashboard.getTopActions('user1')
      // only 3 actions exist, so should return 3
      expect(result.length).toBe(3)
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
      // totalActions = 5 => volumeScore = min(5/100,1)*30 = 1.5
      // uniqueActions = 3 => diversityScore = min(3/10,1)*30 = 9
      // actionsPerDay = 2.5 => frequencyScore = min(2.5/5,1)*40 = 20
      // total = 1.5 + 9 + 20 = 30.5 => toFixed(2) => 30.50 => 30.5
      expect(result).toBe(30.5)
    })

    it('caps each component at its maximum', () => {
      const manyActivities: Activity[] = []
      const base = new Date('2024-01-01T00:00:00Z').getTime()
      // 200 actions over 1 day, 20 unique actions
      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `a${i}`,
          user_id: 'heavy',
          action: `action${i % 20}`,
          timestamp: new Date(base + i * 60 * 1000)
        })
      }
      const d = new ActivityDashboard(manyActivities)
      const score = d.calculateEngagementScore('heavy')

      // volumeScore capped at 30, diversityScore at 30, frequencyScore at 40 => 100
      expect(score).toBe(100)
    })
  })

  describe('private behavior via public methods', () => {
    it('calculateAverageActionsPerSession splits sessions when gap > 30 minutes', () => {
      const base = new Date('2024-02-01T00:00:00Z').getTime()
      const acts: Activity[] = [
        {
          id: '1',
          user_id: 's',
          action: 'a',
          timestamp: new Date(base)
        },
        {
          id: '2',
          user_id: 's',
          action: 'a',
          timestamp: new Date(base + 10 * 60 * 1000) // +10 min
        },
        {
          id: '3',
          user_id: 's',
          action: 'a',
          timestamp: new Date(base + 31 * 60 * 1000) // +31 min -> new session
        }
      ]
      const d = new ActivityDashboard(acts)
      const summary = d.getUserSummary('s')
      expect(summary).not.toBeNull()
      if (!summary) return

      // 3 actions, 2 sessions => 1.5
      expect(summary.averageActionsPerSession).toBe(1.5)
    })

    it('getActivityTrends uses default periodType "day" when not provided', () => {
      const withDefault = dashboard.getActivityTrends('user1')
      const explicit = dashboard.getActivityTrends('user1', 'day')

      expect(withDefault).toEqual(explicit)
    })

    it('getActivityTrends falls back to day grouping for unknown periodType via default in groupByPeriod', () => {
      const anyDashboard = dashboard as any
      const activitiesForUser1 = activities.filter(a => a.user_id === 'user1')
      const grouped = anyDashboard.groupByPeriod(activitiesForUser1, 'unknown')

      const keys = Object.keys(grouped)
      // Should behave like 'day' case
      expect(keys).toContain('2024-01-01')
      expect(keys).toContain('2024-01-03')
    })
  })
})