import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

const makeActivity = (overrides: Partial<Activity> = {}): Activity => {
  return {
    id: overrides.id ?? 'id',
    user_id: overrides.user_id ?? 'user1',
    action: overrides.action ?? 'click',
    timestamp: overrides.timestamp ?? new Date('2024-01-01T10:00:00Z'),
    metadata: overrides.metadata,
  }
}

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const result = dashboard.getUserSummary('user1')
    expect(result).toBeNull()
  })

  it('calculates summary for single activity in one day', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', action: 'view', timestamp: new Date('2024-01-01T10:00:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.getUserSummary('user1')

    expect(result).not.toBeNull()
    expect(result!.totalActions).toBe(1)
    expect(result!.uniqueActions).toBe(1)
    expect(result!.actionsPerDay).toBe(1) // daysActive = 1
    expect(result!.mostFrequentAction).toBe('view')
    expect(result!.averageActionsPerSession).toBe(1)
  })

  it('calculates actionsPerDay using ceil days difference and rounding to 2 decimals', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', timestamp: new Date('2024-01-01T00:00:00Z') }),
      makeActivity({ id: '2', user_id: 'user1', timestamp: new Date('2024-01-03T00:00:00Z') }),
      makeActivity({ id: '3', user_id: 'user1', timestamp: new Date('2024-01-03T12:00:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.getUserSummary('user1')

    // first=Jan1, last=Jan3 => diff=2 days => ceil(2)=2 daysActive
    // totalActions=3 => 3/2=1.5
    expect(result!.actionsPerDay).toBe(1.5)
  })

  it('uses most frequent action based on counts', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', action: 'view' }),
      makeActivity({ id: '2', user_id: 'user1', action: 'click' }),
      makeActivity({ id: '3', user_id: 'user1', action: 'click' }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.getUserSummary('user1')

    expect(result!.mostFrequentAction).toBe('click')
    expect(result!.uniqueActions).toBe(2)
  })

  it('calculates averageActionsPerSession based on 30 minute gaps', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', timestamp: new Date('2024-01-01T10:00:00Z') }),
      makeActivity({ id: '2', user_id: 'user1', timestamp: new Date('2024-01-01T10:10:00Z') }),
      makeActivity({ id: '3', user_id: 'user1', timestamp: new Date('2024-01-01T11:00:01Z') }), // >30 min gap from 10:10
      makeActivity({ id: '4', user_id: 'user1', timestamp: new Date('2024-01-01T11:10:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.getUserSummary('user1')

    // sessions: [10:00,10:10], [11:00:01,11:10] => 2 sessions, 4 actions => 2.00
    expect(result!.averageActionsPerSession).toBe(2)
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  const baseActivities: Activity[] = [
    makeActivity({ id: '1', user_id: 'user1', timestamp: new Date('2024-01-01T10:00:00Z') }),
    makeActivity({ id: '2', user_id: 'user1', timestamp: new Date('2024-01-01T11:00:00Z') }),
    makeActivity({ id: '3', user_id: 'user1', timestamp: new Date('2024-01-02T10:00:00Z') }),
    makeActivity({ id: '4', user_id: 'user1', timestamp: new Date('2024-01-03T10:00:00Z') }),
  ]

  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard(baseActivities)
    const result = dashboard.getActivityTrends('otherUser', 'day')
    expect(result).toEqual([])
  })

  it('groups by day and calculates growthRate', () => {
    const dashboard = new ActivityDashboard(baseActivities)

    const result = dashboard.getActivityTrends('user1', 'day')

    // periods: 2024-01-01 (2), 2024-01-02 (1), 2024-01-03 (1)
    expect(result).toHaveLength(3)
    expect(result[0]).toEqual({ period: '2024-01-01', count: 2, growthRate: 0 })
    // growthRate = ((1-2)/2)*100 = -50 => -50.00
    expect(result[1].period).toBe('2024-01-02')
    expect(result[1].count).toBe(1)
    expect(result[1].growthRate).toBe(-50)
    // growthRate = ((1-1)/1)*100 = 0
    expect(result[2].period).toBe('2024-01-03')
    expect(result[2].count).toBe(1)
    expect(result[2].growthRate).toBe(0)
  })

  it('groups by hour with correct period keys', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', timestamp: new Date('2024-01-01T10:15:00Z') }),
      makeActivity({ id: '2', user_id: 'user1', timestamp: new Date('2024-01-01T10:45:00Z') }),
      makeActivity({ id: '3', user_id: 'user1', timestamp: new Date('2024-01-01T11:00:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.getActivityTrends('user1', 'hour')

    expect(result).toHaveLength(2)
    expect(result[0].period).toBe('2024-01-01 10:00')
    expect(result[0].count).toBe(2)
    expect(result[1].period).toBe('2024-01-01 11:00')
    expect(result[1].count).toBe(1)
  })

  it('groups by month and sorts periods lexicographically', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', timestamp: new Date('2024-02-01T00:00:00Z') }),
      makeActivity({ id: '2', user_id: 'user1', timestamp: new Date('2024-01-15T00:00:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.getActivityTrends('user1', 'month')

    expect(result.map(r => r.period)).toEqual(['2024-01', '2024-02'])
    expect(result[0].count).toBe(1)
    expect(result[1].count).toBe(1)
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters by user and inclusive date range', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', timestamp: new Date('2024-01-01T00:00:00Z') }),
      makeActivity({ id: '2', user_id: 'user1', timestamp: new Date('2024-01-02T00:00:00Z') }),
      makeActivity({ id: '3', user_id: 'user1', timestamp: new Date('2024-01-03T00:00:00Z') }),
      makeActivity({ id: '4', user_id: 'user2', timestamp: new Date('2024-01-02T00:00:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.filterByDateRange(
      'user1',
      new Date('2024-01-02T00:00:00Z'),
      new Date('2024-01-03T00:00:00Z')
    )

    expect(result.map(a => a.id)).toEqual(['2', '3'])
  })

  it('returns empty array when no activities in range', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', timestamp: new Date('2024-01-01T00:00:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.filterByDateRange(
      'user1',
      new Date('2024-01-02T00:00:00Z'),
      new Date('2024-01-03T00:00:00Z')
    )

    expect(result).toEqual([])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const result = dashboard.aggregateByAction('user1')
    expect(result).toEqual([])
  })

  it('aggregates counts, percentages and occurrence dates per action', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', action: 'view', timestamp: new Date('2024-01-01T10:00:00Z') }),
      makeActivity({ id: '2', user_id: 'user1', action: 'view', timestamp: new Date('2024-01-01T11:00:00Z') }),
      makeActivity({ id: '3', user_id: 'user1', action: 'click', timestamp: new Date('2024-01-01T12:00:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.aggregateByAction('user1')

    // total=3 => view: 2/3=66.67, click:1/3=33.33
    expect(result).toHaveLength(2)
    expect(result[0].action).toBe('view')
    expect(result[0].count).toBe(2)
    expect(result[0].percentage).toBe(66.67)
    expect(result[0].firstOccurrence).toEqual(new Date('2024-01-01T10:00:00Z'))
    expect(result[0].lastOccurrence).toEqual(new Date('2024-01-01T11:00:00Z'))

    expect(result[1].action).toBe('click')
    expect(result[1].count).toBe(1)
    expect(result[1].percentage).toBe(33.33)
    expect(result[1].firstOccurrence).toEqual(new Date('2024-01-01T12:00:00Z'))
    expect(result[1].lastOccurrence).toEqual(new Date('2024-01-01T12:00:00Z'))
  })

  it('sorts action groups by count descending', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', action: 'a' }),
      makeActivity({ id: '2', user_id: 'user1', action: 'b' }),
      makeActivity({ id: '3', user_id: 'user1', action: 'b' }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.aggregateByAction('user1')

    expect(result.map(g => g.action)).toEqual(['b', 'a'])
  })
})

describe('ActivityDashboard - getTopActions_old', () => {
  it('returns all actions sorted by count when limit not applied', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', action: 'a', timestamp: new Date('2024-01-01T10:00:00Z') }),
      makeActivity({ id: '2', user_id: 'user1', action: 'b', timestamp: new Date('2024-01-01T11:00:00Z') }),
      makeActivity({ id: '3', user_id: 'user1', action: 'b', timestamp: new Date('2024-01-01T12:00:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.getTopActions_old('user1')

    expect(result).toHaveLength(2)
    expect(result[0].action).toBe('b')
    expect(result[0].count).toBe(2)
    expect(result[1].action).toBe('a')
    expect(result[1].count).toBe(1)
  })

  it('calculates percentage and occurrence dates correctly', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', action: 'x', timestamp: new Date('2024-01-01T09:00:00Z') }),
      makeActivity({ id: '2', user_id: 'user1', action: 'x', timestamp: new Date('2024-01-01T10:00:00Z') }),
      makeActivity({ id: '3', user_id: 'user1', action: 'y', timestamp: new Date('2024-01-01T11:00:00Z') }),
      makeActivity({ id: '4', user_id: 'user1', action: 'y', timestamp: new Date('2024-01-01T12:00:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const result = dashboard.getTopActions_old('user1')

    // total=4 => each 2/4=50.00
    const xGroup = result.find(g => g.action === 'x')!
    expect(xGroup.percentage).toBe(50)
    expect(xGroup.firstOccurrence).toEqual(new Date('2024-01-01T09:00:00Z'))
    expect(xGroup.lastOccurrence).toEqual(new Date('2024-01-01T10:00:00Z'))
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('returns top N actions using aggregateByAction', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', action: 'a' }),
      makeActivity({ id: '2', user_id: 'user1', action: 'b' }),
      makeActivity({ id: '3', user_id: 'user1', action: 'b' }),
      makeActivity({ id: '4', user_id: 'user1', action: 'c' }),
      makeActivity({ id: '5', user_id: 'user1', action: 'c' }),
      makeActivity({ id: '6', user_id: 'user1', action: 'c' }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const top2 = dashboard.getTopActions('user1', 2)

    expect(top2).toHaveLength(2)
    expect(top2[0].action).toBe('c')
    expect(top2[0].count).toBe(3)
    expect(top2[1].action).toBe('b')
    expect(top2[1].count).toBe(2)
  })

  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const result = dashboard.getTopActions('user1', 3)
    expect(result).toEqual([])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no summary', () => {
    const dashboard = new ActivityDashboard([])
    const score = dashboard.calculateEngagementScore('user1')
    expect(score).toBe(0)
  })

  it('calculates score with caps and rounding', () => {
    const activities: Activity[] = []
    // create 100 actions, 10 unique actions, all on same day so actionsPerDay=100
    for (let i = 0; i < 100; i++) {
      activities.push(
        makeActivity({
          id: String(i),
          user_id: 'user1',
          action: `action${i % 10}`,
          timestamp: new Date('2024-01-01T10:00:00Z'),
        })
      )
    }
    const dashboard = new ActivityDashboard(activities)

    const score = dashboard.calculateEngagementScore('user1')

    // volumeScore: min(100/100,1)*30 = 30
    // diversityScore: min(10/10,1)*30 = 30
    // frequencyScore: min(100/5,1)*40 = 40
    // total = 100
    expect(score).toBe(100)
  })

  it('calculates partial scores when below caps', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', user_id: 'user1', action: 'a', timestamp: new Date('2024-01-01T00:00:00Z') }),
      makeActivity({ id: '2', user_id: 'user1', action: 'b', timestamp: new Date('2024-01-02T00:00:00Z') }),
      makeActivity({ id: '3', user_id: 'user1', action: 'b', timestamp: new Date('2024-01-03T00:00:00Z') }),
    ]
    const dashboard = new ActivityDashboard(activities)

    const score = dashboard.calculateEngagementScore('user1')

    // totalActions=3 => volumeScore = (3/100)*30 = 0.9
    // uniqueActions=2 => diversityScore = (2/10)*30 = 6
    // actionsPerDay: first=Jan1, last=Jan3 => diff=2 days => daysActive=2 => 3/2=1.5
    // frequencyScore = (1.5/5)*40 = 12
    // total = 0.9 + 6 + 12 = 18.9 => 18.90
    expect(score).toBe(18.9)
  })
})

describe('ActivityDashboard - constructor and data isolation', () => {
  it('does not mutate original activities array when sorting internally', () => {
    const activities: Activity[] = [
      makeActivity({ id: '1', timestamp: new Date('2024-01-02T00:00:00Z') }),
      makeActivity({ id: '2', timestamp: new Date('2024-01-01T00:00:00Z') }),
    ]
    const originalOrderIds = activities.map(a => a.id)
    const dashboard = new ActivityDashboard(activities)

    dashboard.getUserSummary('user1')
    dashboard.getActivityTrends('user1', 'day')

    expect(activities.map(a => a.id)).toEqual(originalOrderIds)
  })
})