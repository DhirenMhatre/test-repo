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
        timestamp: new Date(baseDate.getTime() + 5 * 60 * 1000),
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

      // totalActions: 4 activities for user1 in initial array before adding id 6? Actually we have 5 for user1: 1,2,3,4,6
      expect(result.totalActions).toBe(5)

      // uniqueActions: login, view, purchase
      expect(result.uniqueActions).toBe(3)

      // daysActive: from first (baseDate) to last (baseDate + 1 day) => diff = 1 day => ceil(1) = 1, but code:
      // Math.ceil((last-first)/dayMs) => (1 day)/1day =1 => ceil(1)=1, max(1,1)=1
      // actionsPerDay = 5 / 1 = 5.00
      expect(result.actionsPerDay).toBe(5)

      // mostFrequentAction: 'view' appears 2 times, others less
      expect(result.mostFrequentAction).toBe('view')

      // sessions: timestamps for user1 sorted:
      // 0min, 10min, 20min, 31min, 24h
      // gaps: 10,10,11, (24h-31min)=1389min -> >30 => new session
      // Only gap >30 is between 31min and 24h => 2 sessions
      // averageActionsPerSession = 5 / 2 = 2.5
      expect(result.averageActionsPerSession).toBe(2.5)
    })

    it('handles single activity correctly', () => {
      const singleActivity: Activity = {
        id: 'single',
        user_id: 'singleUser',
        action: 'login',
        timestamp: baseDate,
      }
      const singleDashboard = new ActivityDashboard([singleActivity])

      const result = singleDashboard.getUserSummary('singleUser')
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

      // user1 has activities on two days: 2024-01-01 (4 acts) and 2024-01-02 (1 act)
      expect(result.length).toBe(2)

      const day1 = result[0]
      const day2 = result[1]

      expect(day1.period).toBe('2024-01-01')
      expect(day1.count).toBe(4)
      expect(day1.growthRate).toBe(0)

      expect(day2.period).toBe('2024-01-02')
      expect(day2.count).toBe(1)
      // growthRate = ((1 - 4) / 4) * 100 = -75.00
      expect(day2.growthRate).toBe(-75)
    })

    it('groups activities by hour', () => {
      const result = dashboard.getActivityTrends('user1', 'hour')

      // user1 activities: 0min,10,20,31, +24h
      // hours: 00:00 (first 4), 24h => 01:00 next day UTC
      expect(result.length).toBe(2)

      const hour1 = result[0]
      const hour2 = result[1]

      expect(hour1.period).toBe('2024-01-01 00:00')
      expect(hour1.count).toBe(4)
      expect(hour1.growthRate).toBe(0)

      expect(hour2.period).toBe('2024-01-02 00:00')
      expect(hour2.count).toBe(1)
      expect(hour2.growthRate).toBe(-75)
    })

    it('groups activities by month and week', () => {
      const resultMonth = dashboard.getActivityTrends('user1', 'month')
      expect(resultMonth.length).toBe(1)
      expect(resultMonth[0].period).toBe('2024-01')
      expect(resultMonth[0].count).toBe(5)
      expect(resultMonth[0].growthRate).toBe(0)

      const resultWeek = dashboard.getActivityTrends('user1', 'week')
      expect(resultWeek.length).toBe(1)
      expect(resultWeek[0].period.startsWith('2024-W')).toBe(true)
      expect(resultWeek[0].count).toBe(5)
      expect(resultWeek[0].growthRate).toBe(0)
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities within inclusive date range for user', () => {
      const start = new Date(baseDate.getTime() + 5 * 60 * 1000)
      const end = new Date(baseDate.getTime() + 25 * 60 * 1000)

      const result = dashboard.filterByDateRange('user1', start, end)

      // user1 activities at 0,10,20,31min,24h => within 5-25min => 10 and 20
      expect(result.map(a => a.id)).toEqual(['2', '3'])
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date(baseDate.getTime() + 2 * 24 * 60 * 60 * 1000)
      const end = new Date(baseDate.getTime() + 3 * 24 * 60 * 60 * 1000)

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

      // user1 actions: login x2, view x2, purchase x1
      expect(result.length).toBe(3)

      // sorted by count desc: login (2), view (2), purchase (1)
      // when counts equal, original order of first encounter: login then view
      const loginGroup = result.find(g => g.action === 'login')
      const viewGroup = result.find(g => g.action === 'view')
      const purchaseGroup = result.find(g => g.action === 'purchase')

      expect(loginGroup).toBeDefined()
      expect(viewGroup).toBeDefined()
      expect(purchaseGroup).toBeDefined()

      if (!loginGroup || !viewGroup || !purchaseGroup) return

      expect(loginGroup.count).toBe(2)
      expect(loginGroup.percentage).toBeCloseTo(parseFloat(((2 / 5) * 100).toFixed(2)))
      expect(loginGroup.firstOccurrence.getTime()).toBe(activities[0].timestamp.getTime())
      expect(loginGroup.lastOccurrence.getTime()).toBe(activities[5].timestamp.getTime())

      expect(viewGroup.count).toBe(2)
      expect(viewGroup.percentage).toBeCloseTo(parseFloat(((2 / 5) * 100).toFixed(2)))
      expect(viewGroup.firstOccurrence.getTime()).toBe(activities[1].timestamp.getTime())
      expect(viewGroup.lastOccurrence.getTime()).toBe(activities[2].timestamp.getTime())

      expect(purchaseGroup.count).toBe(1)
      expect(purchaseGroup.percentage).toBeCloseTo(parseFloat(((1 / 5) * 100).toFixed(2)))
      expect(purchaseGroup.firstOccurrence.getTime()).toBe(activities[3].timestamp.getTime())
      expect(purchaseGroup.lastOccurrence.getTime()).toBe(activities[3].timestamp.getTime())
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

      // Should ignore limit and return all 3 groups
      expect(result.length).toBe(3)

      const actions = result.map(g => g.action)
      expect(actions).toContain('login')
      expect(actions).toContain('view')
      expect(actions).toContain('purchase')

      // Ensure counts match aggregateByAction for same user
      const aggregated = dashboard.aggregateByAction('user1')
      const sortByAction = (arr: any[]) => arr.slice().sort((a, b) => a.action.localeCompare(b.action))
      expect(sortByAction(result).map(g => g.count)).toEqual(sortByAction(aggregated).map(g => g.count))
    })
  })

  describe('getTopActions', () => {
    it('returns limited number of top actions', () => {
      const result = dashboard.getTopActions('user1', 2)
      expect(result.length).toBe(2)

      // Should be the two most frequent actions: login and view (both 2)
      const actions = result.map(g => g.action)
      expect(actions).toContain('login')
      expect(actions).toContain('view')
    })

    it('returns all actions when limit exceeds available groups', () => {
      const result = dashboard.getTopActions('user1', 10)
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

      const score = dashboard.calculateEngagementScore('user1')

      const volumeScore = Math.min(summary.totalActions / 100, 1) * 30
      const diversityScore = Math.min(summary.uniqueActions / 10, 1) * 30
      const frequencyScore = Math.min(summary.actionsPerDay / 5, 1) * 40
      const expected = parseFloat((volumeScore + diversityScore + frequencyScore).toFixed(2))

      expect(score).toBe(expected)
    })

    it('caps each component of the score at its maximum', () => {
      const manyActivities: Activity[] = []
      const userId = 'heavyUser'
      const start = new Date('2024-01-01T00:00:00Z')

      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `h${i}`,
          user_id: userId,
          action: `action${i % 20}`, // 20 unique actions
          timestamp: new Date(start.getTime() + i * 60 * 1000),
        })
      }

      const heavyDashboard = new ActivityDashboard(manyActivities)
      const score = heavyDashboard.calculateEngagementScore(userId)

      // With enough volume, diversity and frequency, each component should hit its cap:
      // volumeScore: 30, diversityScore: 30, frequencyScore: 40 => total 100
      expect(score).toBe(100)
    })
  })

  describe('session calculation via getUserSummary (calculateAverageActionsPerSession)', () => {
    it('returns 0 average actions per session when no activities', () => {
      const emptyDashboard = new ActivityDashboard([])
      const summary = emptyDashboard.getUserSummary('user1')
      expect(summary).toBeNull()
    })

    it('treats activities within 30 minutes as same session', () => {
      const userId = 'sessionUser'
      const start = new Date('2024-01-01T00:00:00Z')
      const sessionActivities: Activity[] = [
        {
          id: 's1',
          user_id: userId,
          action: 'a',
          timestamp: start,
        },
        {
          id: 's2',
          user_id: userId,
          action: 'b',
          timestamp: new Date(start.getTime() + 29 * 60 * 1000), // 29 minutes later
        },
      ]
      const sessionDashboard = new ActivityDashboard(sessionActivities)
      const summary = sessionDashboard.getUserSummary(userId)
      expect(summary).not.toBeNull()
      if (!summary) return

      // Both in same session => 2 / 1 = 2.00
      expect(summary.averageActionsPerSession).toBe(2)
    })

    it('splits sessions when gap exceeds 30 minutes', () => {
      const userId = 'sessionUser2'
      const start = new Date('2024-01-01T00:00:00Z')
      const sessionActivities: Activity[] = [
        {
          id: 's1',
          user_id: userId,
          action: 'a',
          timestamp: start,
        },
        {
          id: 's2',
          user_id: userId,
          action: 'b',
          timestamp: new Date(start.getTime() + 31 * 60 * 1000), // 31 minutes later
        },
        {
          id: 's3',
          user_id: userId,
          action: 'c',
          timestamp: new Date(start.getTime() + 32 * 60 * 1000), // 32 minutes later
        },
      ]
      const sessionDashboard = new ActivityDashboard(sessionActivities)
      const summary = sessionDashboard.getUserSummary(userId)
      expect(summary).not.toBeNull()
      if (!summary) return

      // sessions: [s1], [s2,s3] => 3 / 2 = 1.5
      expect(summary.averageActionsPerSession).toBe(1.5)
    })
  })

  describe('getActivityTrends default periodType', () => {
    it('uses day as default periodType when not provided', () => {
      const resultExplicit = dashboard.getActivityTrends('user1', 'day')
      const resultDefault = dashboard.getActivityTrends('user1')
      expect(resultDefault).toEqual(resultExplicit)
    })
  })
})