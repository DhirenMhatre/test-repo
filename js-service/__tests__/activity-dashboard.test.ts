import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

const act = (id: string, userId: string, action: string, iso: string, metadata?: Record<string, any>): Activity => ({
  id,
  user_id: userId,
  action,
  timestamp: new Date(iso),
  metadata
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when no activities for the user', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, most frequent action, actionsPerDay and average per session', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'click', '2024-01-01T00:00:00.000Z'),
      act('2', 'u1', 'view', '2024-01-01T00:10:00.000Z'),
      act('3', 'u1', 'click', '2024-01-01T00:25:00.000Z'),
      act('4', 'u1', 'click', '2024-01-01T01:05:00.000Z'), // 40 minutes gap -> new session
      act('5', 'u1', 'view', '2024-01-01T01:06:00.000Z')
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(5)
    expect(summary!.uniqueActions).toBe(2)
    expect(summary!.mostFrequentAction).toBe('click')
    expect(summary!.actionsPerDay).toBe(5) // same day -> daysActive=1
    expect(summary!.averageActionsPerSession).toBe(2.5) // 5 actions over 2 sessions
  })

  it('single activity yields actionsPerDay = 1 and averageActionsPerSession = 1', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'view', '2024-01-01T12:00:00.000Z')
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(1)
    expect(summary!.uniqueActions).toBe(1)
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.actionsPerDay).toBe(1)
    expect(summary!.averageActionsPerSession).toBe(1)
  })

  it('computes actionsPerDay across multiple days using ceil and min 1 day safeguard', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'click', '2024-01-01T00:00:00.000Z'),
      act('2', 'u1', 'click', '2024-01-03T00:00:00.000Z') // exactly 2 days apart => daysActive=2
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(2)
    expect(summary!.actionsPerDay).toBe(1)
  })

  it('averageActionsPerSession splits sessions when gap > 30 minutes and rounds to 2 decimals', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'a', '2024-01-01T00:00:00.000Z'),
      act('2', 'u1', 'a', '2024-01-01T00:20:00.000Z'), // same session
      act('3', 'u1', 'a', '2024-01-01T01:00:00.000Z'), // new session (40m gap)
      act('4', 'u1', 'a', '2024-01-01T01:31:00.000Z')  // new session (31m gap)
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(1.33) // 4 actions / 3 sessions = 1.333...
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array when no activities for user', () => {
    const dashboard = new ActivityDashboard([])
    const trends = dashboard.getActivityTrends('u1')
    expect(trends).toEqual([])
  })

  it('groups by day with correct counts and growth rate', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'click', '2024-01-01T05:00:00.000Z'),
      act('2', 'u1', 'click', '2024-01-02T08:00:00.000Z'),
      act('3', 'u1', 'view',  '2024-01-02T12:00:00.000Z')
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends.length).toBe(2)
    expect(trends[0]).toEqual({ period: '2024-01-01', count: 1, growthRate: 0 })
    expect(trends[1].period).toBe('2024-01-02')
    expect(trends[1].count).toBe(2)
    expect(trends[1].growthRate).toBe(100) // (2-1)/1 * 100
  })

  it('groups by hour with zero-padded hour and sorted periods', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'click', '2024-01-01T10:05:00.000Z'),
      act('2', 'u1', 'view',  '2024-01-01T10:59:00.000Z'),
      act('3', 'u1', 'click', '2024-01-01T11:00:00.000Z')
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'hour')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2024-01-01 10:00')
    expect(trends[0].count).toBe(2)
    expect(trends[1].period).toBe('2024-01-01 11:00')
    expect(trends[1].count).toBe(1)
  })

  it('groups by month correctly', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'a', '2024-01-15T00:00:00.000Z'),
      act('2', 'u1', 'a', '2024-01-20T00:00:00.000Z'),
      act('3', 'u1', 'a', '2024-02-01T00:00:00.000Z')
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends.map(t => t.period)).toEqual(['2024-01', '2024-02'])
    expect(trends[0].count).toBe(2)
    expect(trends[1].count).toBe(1)
  })

  it('groups by week using implemented week calculation', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'a', '2024-01-01T00:00:00.000Z'), // 2024-W01 (Monday)
      act('2', 'u1', 'a', '2024-01-07T00:00:00.000Z')  // 2024-W02 (Sunday)
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2024-W01')
    expect(trends[0].count).toBe(1)
    expect(trends[1].period).toBe('2024-W02')
    expect(trends[1].count).toBe(1)
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters activities by inclusive date range for specific user', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'a', '2024-01-01T00:00:00.000Z'),
      act('2', 'u1', 'b', '2024-01-02T00:00:00.000Z'),
      act('3', 'u1', 'c', '2024-01-03T00:00:00.000Z'),
      act('4', 'u2', 'a', '2024-01-02T00:00:00.000Z')
    ]
    const dashboard = new ActivityDashboard(activities)
    const start = new Date('2024-01-02T00:00:00.000Z')
    const end = new Date('2024-01-03T00:00:00.000Z')
    const filtered = dashboard.filterByDateRange('u1', start, end)
    expect(filtered.length).toBe(2)
    expect(filtered.map(a => a.id)).toEqual(['2', '3'])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const groups = dashboard.aggregateByAction('u1')
    expect(groups).toEqual([])
  })

  it('aggregates and sorts by count descending with correct percentages and occurrence times', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'click', '2024-01-01T00:00:00.000Z'),
      act('2', 'u1', 'view',  '2024-01-01T12:00:00.000Z'),
      act('3', 'u1', 'click', '2024-01-02T00:00:00.000Z'),
      act('4', 'u1', 'click', '2024-01-03T00:00:00.000Z')
    ]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups.length).toBe(2)
    expect(groups[0].action).toBe('click')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(75)
    expect(groups[0].firstOccurrence.toISOString()).toBe('2024-01-01T00:00:00.000Z')
    expect(groups[0].lastOccurrence.toISOString()).toBe('2024-01-03T00:00:00.000Z')
    expect(groups[1].action).toBe('view')
    expect(groups[1].count).toBe(1)
    expect(groups[1].percentage).toBe(25)
    expect(groups[1].firstOccurrence.toISOString()).toBe('2024-01-01T12:00:00.000Z')
    expect(groups[1].lastOccurrence.toISOString()).toBe('2024-01-01T12:00:00.000Z')
  })
})

describe('ActivityDashboard - getTopActions_old and getTopActions', () => {
  it('getTopActions_old returns all groups without limiting by provided limit', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'click', '2024-01-01T00:00:00.000Z'),
      act('2', 'u1', 'view',  '2024-01-01T01:00:00.000Z'),
      act('3', 'u1', 'click', '2024-01-01T02:00:00.000Z'),
      act('4', 'u1', 'play',  '2024-01-01T03:00:00.000Z')
    ]
    const dashboard = new ActivityDashboard(activities)
    const topOld = dashboard.getTopActions_old('u1', 1)
    expect(topOld.length).toBe(3) // not limited
    expect(topOld[0].action).toBe('click')
    expect(topOld[0].count).toBe(2)
  })

  it('getTopActions respects the limit and returns sorted top actions', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'click', '2024-01-01T00:00:00.000Z'),
      act('2', 'u1', 'view',  '2024-01-01T01:00:00.000Z'),
      act('3', 'u1', 'click', '2024-01-01T02:00:00.000Z'),
      act('4', 'u1', 'play',  '2024-01-01T03:00:00.000Z')
    ]
    const dashboard = new ActivityDashboard(activities)
    const top = dashboard.getTopActions('u1', 1)
    expect(top.length).toBe(1)
    expect(top[0].action).toBe('click')
    expect(top[0].count).toBe(2)
  })

  it('returns empty arrays for users with no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.getTopActions_old('uX')).toEqual([])
    expect(dashboard.getTopActions('uX')).toEqual([])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('u1')).toBe(0)
  })

  it('computes engagement score with rounding to 2 decimals', () => {
    const activities: Activity[] = []
    // 10 actions within same day, 2 unique actions
    for (let i = 0; i < 10; i++) {
      activities.push(
        act(String(i + 1), 'u1', i % 2 === 0 ? 'click' : 'view', `2024-01-01T00:${String(i).padStart(2, '0')}:00.000Z`)
      )
    }
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('u1')
    // volume: (10/100)*30 = 3
    // diversity: (2/10)*30 = 6
    // frequency: min(10/5,1)*40 = 40
    // total = 49
    expect(score).toBe(49)
  })

  it('computes engagement score for small activity volume producing fractional result', () => {
    const activities: Activity[] = [
      act('1', 'u1', 'a', '2024-01-01T00:00:00.000Z'),
      act('2', 'u1', 'b', '2024-01-01T01:00:00.000Z')
    ]
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('u1')
    // volume: (2/100)*30 = 0.6
    // diversity: (2/10)*30 = 6
    // frequency: (2/5)*40 = 16
    // total = 22.6
    expect(score).toBe(22.6)
  })
})