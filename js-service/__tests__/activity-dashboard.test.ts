import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

describe('ActivityDashboard', () => {
  let activities: Activity[]
  let dashboard: ActivityDashboard

  beforeEach(() => {
    const base = new Date('2024-01-01T00:00:00Z')

    activities = [
      {
        id: '1',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(base.getTime())
      },
      {
        id: '2',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(base.getTime() + 60 * 60 * 1000) // +1h
      },
      {
        id: '3',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(base.getTime() + 2 * 60 * 60 * 1000) // +2h
      },
      {
        id: '4',
        user_id: 'user1',
        action: 'purchase',
        timestamp: new Date(base.getTime() + 26 * 60 * 60 * 1000) // +26h (next day +2h)
      },
      {
        id: '5',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date(base.getTime() + 3 * 60 * 60 * 1000)
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

      // user1 has 4 activities
      expect(result.totalActions).toBe(4)

      // actions: login, view, purchase => 3 unique
      expect(result.uniqueActions).toBe(3)

      // first at t0, last at t0 + 26h => diff 26h => 1.0833 days => ceil = 2 days
      // actionsPerDay = 4 / 2 = 2.00
      expect(result.actionsPerDay).toBe(2)

      // most frequent action is 'view' (2 times)
      expect(result.mostFrequentAction).toBe('view')

      // sessions: gap > 30min starts new session
      // t0, +1h, +2h are within 30min gaps? t0->1h = 60min (>30) => new session
      // 1h->2h = 60min (>30) => new session
      // 2h->26h = 24h (>30) => new session
      // so 4 sessions, 4 actions => 1.00
      expect(result.averageActionsPerSession).toBe(1)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: '10',
        user_id: 'single',
        action: 'login',
        timestamp: new Date('2024-01-10T10:00:00Z')
      }
      const singleDashboard = new ActivityDashboard([singleActivity])

      const result = singleDashboard.getUserSummary('single')
      expect(result).not.toBeNull()
      if (!result) return

      expect(result.totalActions).toBe(1)
      expect(result.uniqueActions).toBe(1)
      // daysActive should be at least 1, so 1/1 = 1
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

      // user1 has activities on 2024-01-01 (3) and 2024-01-02 (1)
      expect(result.length).toBe(2)

      const day1 = result[0]
      const day2 = result[1]

      expect(day1.period).toBe('2024-01-01')
      expect(day1.count).toBe(3)
      // first period has growthRate 0
      expect(day1.growthRate).toBe(0)

      expect(day2.period).toBe('2024-01-02')
      expect(day2.count).toBe(1)
      // growthRate = ((1 - 3) / 3) * 100 = -66.67
      expect(day2.growthRate).toBe(-66.67)
    })

    it('groups activities by hour', () => {
      const result = dashboard.getActivityTrends('user1', 'hour')

      // user1 has 4 activities in 4 different hours
      expect(result.length).toBe(4)
      expect(result[0].period).toMatch(/2024-01-01 0[0-9]:00|2024-01-01 00:00/)
      expect(result[0].count).toBe(1)
      // growthRate for first is 0
      expect(result[0].growthRate).toBe(0)
    })

    it('groups activities by month', () => {
      const result = dashboard.getActivityTrends('user1', 'month')
      expect(result.length).toBe(1)
      expect(result[0].period).toBe('2024-01')
      expect(result[0].count).toBe(4)
      expect(result[0].growthRate).toBe(0)
    })

    it('groups activities by week', () => {
      const result = dashboard.getActivityTrends('user1', 'week')
      // All activities are in the same week of 2024-01-01
      expect(result.length).toBe(1)
      expect(result[0].count).toBe(4)
      expect(result[0].growthRate).toBe(0)
      expect(result[0].period.startsWith('2024-W')).toBe(true)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within the inclusive date range for a user', () => {
      const start = new Date('2024-01-01T00:00:00Z')
      const end = new Date('2024-01-01T23:59:59Z')

      const result = dashboard.filterByDateRange('user1', start, end)

      // user1 has 3 activities on 2024-01-01
      expect(result.length).toBe(3)
      expect(result.every(a => a.user_id === 'user1')).toBe(true)
      expect(result.every(a => a.timestamp >= start && a.timestamp <= end)).toBe(true)
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date('2025-01-01T00:00:00Z')
      const end = new Date('2025-01-02T00:00:00Z')

      const result = dashboard.filterByDateRange('user1', start, end)
      expect(result).toEqual([])
    })

    it('includes activities exactly on the boundary dates', () => {
      const first = activities.find(a => a.id === '1')!.timestamp
      const last = activities.find(a => a.id === '4')!.timestamp

      const result = dashboard.filterByDateRange('user1', first, last)
      expect(result.length).toBe(4)
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.aggregateByAction('unknown')
      expect(result).toEqual([])
    })

    it('aggregates actions with counts, percentages and occurrences', () => {
      const result = dashboard.aggregateByAction('user1')

      // actions: login(1), view(2), purchase(1)
      expect(result.length).toBe(3)

      // sorted by count desc, so 'view' first
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(2)
      expect(result[0].percentage).toBe(50) // 2/4 * 100

      const viewGroup = result.find(g => g.action === 'view')!
      const viewActivities = activities.filter(
        a => a.user_id === 'user1' && a.action === 'view'
      )
      const sortedView = [...viewActivities].sort(
        (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
      )

      expect(viewGroup.firstOccurrence.getTime()).toBe(sortedView[0].timestamp.getTime())
      expect(viewGroup.lastOccurrence.getTime()).toBe(
        sortedView[sortedView.length - 1].timestamp.getTime()
      )
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
      expect(result[0].action).toBe('view')
      expect(result[0].count).toBe(2)
      expect(result[1].count).toBe(1)
      expect(result[2].count).toBe(1)
    })

    it('calculates percentages based on total actions', () => {
      const result = dashboard.getTopActions_old('user1')
      const total = 4

      result.forEach(group => {
        const expected = parseFloat(((group.count / total) * 100).toFixed(2))
        expect(group.percentage).toBe(expected)
      })
    })
  })

  describe('getTopActions', () => {
    it('returns limited number of top actions', () => {
      const result = dashboard.getTopActions('user1', 2)
      expect(result.length).toBe(2)
      expect(result[0].count).toBeGreaterThanOrEqual(result[1].count)
    })

    it('defaults to limit 5 when not provided', () => {
      const result = dashboard.getTopActions('user1')
      // only 3 actions exist, so should return 3
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
      // total = 1.2 + 9 + 16 = 26.2 => toFixed(2) => 26.20 => parseFloat => 26.2
      expect(result).toBe(26.2)
    })

    it('caps each component at its maximum', () => {
      const manyActivities: Activity[] = []
      const base = new Date('2024-01-01T00:00:00Z')

      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `a${i}`,
          user_id: 'heavy',
          action: `action${i % 20}`, // 20 unique actions
          timestamp: new Date(base.getTime() + i * 60 * 60 * 1000)
        })
      }

      const heavyDashboard = new ActivityDashboard(manyActivities)
      const score = heavyDashboard.calculateEngagementScore('heavy')

      // All components should be capped:
      // volumeScore = 30, diversityScore = 30, frequencyScore = 40 => 100
      expect(score).toBe(100)
    })
  })

  describe('session calculation behavior via getUserSummary', () => {
    it('treats actions within 30 minutes as same session', () => {
      const base = new Date('2024-02-01T10:00:00Z')
      const sessionActivities: Activity[] = [
        {
          id: 's1',
          user_id: 'sessionUser',
          action: 'a',
          timestamp: new Date(base.getTime())
        },
        {
          id: 's2',
          user_id: 'sessionUser',
          action: 'b',
          timestamp: new Date(base.getTime() + 10 * 60 * 1000) // +10min
        },
        {
          id: 's3',
          user_id: 'sessionUser',
          action: 'c',
          timestamp: new Date(base.getTime() + 25 * 60 * 1000) // +25min
        }
      ]

      const sessionDashboard = new ActivityDashboard(sessionActivities)
      const summary = sessionDashboard.getUserSummary('sessionUser')
      expect(summary).not.toBeNull()
      if (!summary) return

      // All within 30 minutes => 1 session => avg = 3/1 = 3.00
      expect(summary.averageActionsPerSession).toBe(3)
    })

    it('starts new session when gap exceeds 30 minutes', () => {
      const base = new Date('2024-02-01T10:00:00Z')
      const sessionActivities: Activity[] = [
        {
          id: 's1',
          user_id: 'sessionUser2',
          action: 'a',
          timestamp: new Date(base.getTime())
        },
        {
          id: 's2',
          user_id: 'sessionUser2',
          action: 'b',
          timestamp: new Date(base.getTime() + 31 * 60 * 1000) // +31min
        }
      ]

      const sessionDashboard = new ActivityDashboard(sessionActivities)
      const summary = sessionDashboard.getUserSummary('sessionUser2')
      expect(summary).not.toBeNull()
      if (!summary) return

      // 2 sessions, 2 actions => 1.00
      expect(summary.averageActionsPerSession).toBe(1)
    })
  })
})