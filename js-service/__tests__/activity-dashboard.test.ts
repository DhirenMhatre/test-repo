import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

type Activity = ConstructorParameters<typeof ActivityDashboard>[0][number]

const makeActivity = (id: string, user_id: string, action: string, date: Date): Activity => ({
  id,
  user_id,
  action,
  timestamp: date
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const res = dash.getUserSummary('u1')
    expect(res).toBeNull()
  })

  it('calculates summary metrics correctly for a multi-day user', () => {
    const u = 'user1'
    const activities: Activity[] = [
      makeActivity('1', u, 'login', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', u, 'view', new Date(2023, 0, 1, 9, 10, 0)),
      makeActivity('3', u, 'view', new Date(2023, 0, 1, 9, 25, 0)),
      makeActivity('4', u, 'logout', new Date(2023, 0, 1, 10, 0, 0)),
      makeActivity('5', u, 'login', new Date(2023, 0, 2, 8, 0, 0)),
      makeActivity('6', u, 'view', new Date(2023, 0, 2, 8, 5, 0)),
      makeActivity('7', u, 'purchase', new Date(2023, 0, 5, 12, 0, 0)),
      makeActivity('8', u, 'view', new Date(2023, 0, 5, 12, 10, 0)),
      makeActivity('9', u, 'view', new Date(2023, 0, 5, 12, 35, 0)),
      makeActivity('10', u, 'view', new Date(2023, 0, 5, 13, 10, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const res = dash.getUserSummary(u)
    expect(res).not.toBeNull()
    expect(res!.totalActions).toBe(10)
    expect(res!.uniqueActions).toBe(4)
    expect(res!.actionsPerDay).toBe(2)
    expect(res!.mostFrequentAction).toBe('view')
    expect(res!.averageActionsPerSession).toBe(2)
  })

  it('uses minimum of 1 day for actionsPerDay and session gap is strictly >30min', () => {
    const u = 'user2'
    const activities: Activity[] = [
      makeActivity('1', u, 'a', new Date(2023, 0, 1, 10, 0, 0)),
      makeActivity('2', u, 'b', new Date(2023, 0, 1, 10, 30, 0)), // exactly 30 min, same session
      makeActivity('3', u, 'c', new Date(2023, 0, 1, 11, 1, 0))  // 31 min, new session
    ]
    const dash = new ActivityDashboard(activities)

    const res = dash.getUserSummary(u)
    expect(res).not.toBeNull()
    expect(res!.actionsPerDay).toBe(3) // same day => daysActive = 1
    expect(res!.averageActionsPerSession).toBe(1.5) // 3 actions over 2 sessions
  })

  it('mostFrequentAction uses insertion order on ties', () => {
    const u = 'user3'
    const activities: Activity[] = [
      makeActivity('1', u, 'b', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', u, 'a', new Date(2023, 0, 1, 9, 10, 0)),
      makeActivity('3', u, 'b', new Date(2023, 0, 1, 9, 20, 0)),
      makeActivity('4', u, 'a', new Date(2023, 0, 1, 9, 30, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const res = dash.getUserSummary(u)
    expect(res).not.toBeNull()
    expect(res!.mostFrequentAction).toBe('b') // tie, but 'b' first encountered
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('returns empty array when no activities for user', () => {
    const dash = new ActivityDashboard([])
    expect(dash.getActivityTrends('u')).toEqual([])
  })

  it('groups by day and calculates growthRate', () => {
    const u = 'user1'
    const activities: Activity[] = [
      // Jan 1: 4 actions
      makeActivity('1', u, 'a', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', u, 'b', new Date(2023, 0, 1, 9, 10, 0)),
      makeActivity('3', u, 'b', new Date(2023, 0, 1, 9, 25, 0)),
      makeActivity('4', u, 'c', new Date(2023, 0, 1, 10, 0, 0)),
      // Jan 2: 2 actions
      makeActivity('5', u, 'a', new Date(2023, 0, 2, 8, 0, 0)),
      makeActivity('6', u, 'b', new Date(2023, 0, 2, 8, 5, 0)),
      // Jan 5: 4 actions
      makeActivity('7', u, 'd', new Date(2023, 0, 5, 12, 0, 0)),
      makeActivity('8', u, 'b', new Date(2023, 0, 5, 12, 10, 0)),
      makeActivity('9', u, 'b', new Date(2023, 0, 5, 12, 35, 0)),
      makeActivity('10', u, 'b', new Date(2023, 0, 5, 13, 10, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const trends = dash.getActivityTrends(u, 'day')
    expect(trends.length).toBe(3)
    expect(trends[0]).toEqual({ period: '2023-01-01', count: 4, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2023-01-02', count: 2, growthRate: -50 })
    expect(trends[2]).toEqual({ period: '2023-01-05', count: 4, growthRate: 100 })
  })

  it('groups by hour with correct formatting and growth', () => {
    const u = 'userH'
    const activities: Activity[] = [
      makeActivity('1', u, 'a', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', u, 'b', new Date(2023, 0, 1, 9, 10, 0)),
      makeActivity('3', u, 'b', new Date(2023, 0, 1, 9, 25, 0)),
      makeActivity('4', u, 'c', new Date(2023, 0, 1, 10, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const trends = dash.getActivityTrends(u, 'hour')
    expect(trends.length).toBe(2)
    expect(trends[0]).toEqual({ period: '2023-01-01 09:00', count: 3, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2023-01-01 10:00', count: 1, growthRate: -66.67 })
  })

  it('groups by week into single period with correct count', () => {
    const u = 'userW'
    const activities: Activity[] = [
      makeActivity('1', u, 'a', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', u, 'a', new Date(2023, 0, 2, 9, 0, 0)),
      makeActivity('3', u, 'a', new Date(2023, 0, 3, 9, 0, 0)),
      makeActivity('4', u, 'a', new Date(2023, 0, 4, 9, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const trends = dash.getActivityTrends(u, 'week')
    expect(trends.length).toBe(1)
    expect(trends[0].period).toBe('2023-W01')
    expect(trends[0].count).toBe(4)
    expect(trends[0].growthRate).toBe(0)
  })

  it('groups by month across months and sorts periods', () => {
    const u = 'userM'
    const activities: Activity[] = [
      makeActivity('1', u, 'a', new Date(2023, 0, 31, 23, 59, 0)),
      makeActivity('2', u, 'a', new Date(2023, 1, 1, 0, 1, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const trends = dash.getActivityTrends(u, 'month')
    expect(trends.length).toBe(2)
    expect(trends[0]).toEqual({ period: '2023-01', count: 1, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2023-02', count: 1, growthRate: 0 })
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('filters by date range inclusively', () => {
    const u = 'userF'
    const activities: Activity[] = [
      makeActivity('1', u, 'a', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', u, 'b', new Date(2023, 0, 1, 9, 25, 0)),
      makeActivity('3', u, 'c', new Date(2023, 0, 1, 10, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const start = new Date(2023, 0, 1, 9, 0, 0)
    const end = new Date(2023, 0, 1, 9, 25, 0)
    const res = dash.filterByDateRange(u, start, end)
    expect(res.map(r => r.id)).toEqual(['1', '2'])
  })

  it('filters only specified user activities', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', 'u2', 'b', new Date(2023, 0, 1, 9, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const res = dash.filterByDateRange('u1', new Date(2023, 0, 1, 8, 0, 0), new Date(2023, 0, 1, 10, 0, 0))
    expect(res.length).toBe(1)
    expect(res[0].user_id).toBe('u1')
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('aggregates action groups with counts, percentages, and occurrences', () => {
    const u = 'userA'
    const activities: Activity[] = [
      makeActivity('1', u, 'login', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', u, 'view', new Date(2023, 0, 1, 9, 10, 0)),
      makeActivity('3', u, 'view', new Date(2023, 0, 1, 9, 25, 0)),
      makeActivity('4', u, 'logout', new Date(2023, 0, 1, 10, 0, 0)),
      makeActivity('5', u, 'login', new Date(2023, 0, 2, 8, 0, 0)),
      makeActivity('6', u, 'view', new Date(2023, 0, 2, 8, 5, 0)),
      makeActivity('7', u, 'purchase', new Date(2023, 0, 5, 12, 0, 0)),
      makeActivity('8', u, 'view', new Date(2023, 0, 5, 12, 10, 0)),
      makeActivity('9', u, 'view', new Date(2023, 0, 5, 12, 35, 0)),
      makeActivity('10', u, 'view', new Date(2023, 0, 5, 13, 10, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const groups = dash.aggregateByAction(u)
    expect(groups.length).toBe(4)
    expect(groups[0].action).toBe('view')
    expect(groups[0].count).toBe(6)
    expect(groups[0].percentage).toBe(60)
    expect(groups[0].firstOccurrence.getTime()).toBe(new Date(2023, 0, 1, 9, 10, 0).getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(new Date(2023, 0, 5, 13, 10, 0).getTime())
  })

  it('returns empty list when user has no activities', () => {
    const dash = new ActivityDashboard([])
    expect(dash.aggregateByAction('none')).toEqual([])
  })
})

describe('ActivityDashboard.getTopActions_old', () => {
  it('returns all actions sorted by count and ignores limit parameter', () => {
    const u = 'userOld'
    const activities: Activity[] = [
      makeActivity('1', u, 'a', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', u, 'b', new Date(2023, 0, 1, 9, 5, 0)),
      makeActivity('3', u, 'b', new Date(2023, 0, 1, 9, 10, 0)),
      makeActivity('4', u, 'c', new Date(2023, 0, 1, 9, 15, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const groups = dash.getTopActions_old(u, 1)
    expect(groups.length).toBe(3)
    expect(groups[0].action).toBe('b')
    expect(groups[0].count).toBe(2)
    expect(groups[1].action).toBe('a')
    expect(groups[1].count).toBe(1)
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('returns top N actions by count', () => {
    const u = 'userTop'
    const activities: Activity[] = [
      makeActivity('1', u, 'x', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', u, 'y', new Date(2023, 0, 1, 9, 5, 0)),
      makeActivity('3', u, 'y', new Date(2023, 0, 1, 9, 10, 0)),
      makeActivity('4', u, 'z', new Date(2023, 0, 1, 9, 15, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const top2 = dash.getTopActions(u, 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('y')
    expect(top2[1].action).toBe('x')
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 when user has no activities', () => {
    const dash = new ActivityDashboard([])
    expect(dash.calculateEngagementScore('u')).toBe(0)
  })

  it('computes score based on volume, diversity, and frequency with rounding', () => {
    const u = 'userScore'
    const activities: Activity[] = [
      makeActivity('1', u, 'login', new Date(2023, 0, 1, 9, 0, 0)),
      makeActivity('2', u, 'view', new Date(2023, 0, 1, 9, 10, 0)),
      makeActivity('3', u, 'view', new Date(2023, 0, 1, 9, 25, 0)),
      makeActivity('4', u, 'logout', new Date(2023, 0, 1, 10, 0, 0)),
      makeActivity('5', u, 'login', new Date(2023, 0, 2, 8, 0, 0)),
      makeActivity('6', u, 'view', new Date(2023, 0, 2, 8, 5, 0)),
      makeActivity('7', u, 'purchase', new Date(2023, 0, 5, 12, 0, 0)),
      makeActivity('8', u, 'view', new Date(2023, 0, 5, 12, 10, 0)),
      makeActivity('9', u, 'view', new Date(2023, 0, 5, 12, 35, 0)),
      makeActivity('10', u, 'view', new Date(2023, 0, 5, 13, 10, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const score = dash.calculateEngagementScore(u)
    expect(score).toBe(31)
  })
})