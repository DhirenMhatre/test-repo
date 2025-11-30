import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

const makeActivity = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, actionsPerDay, mostFrequentAction, and average per session', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
      makeActivity('2', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
      makeActivity('3', 'u1', 'click', new Date(2024, 0, 1, 9, 40)),
      makeActivity('4', 'u1', 'view', new Date(2024, 0, 1, 10, 11)),
      makeActivity('5', 'u1', 'login', new Date(2024, 0, 2, 8, 0)),
      makeActivity('6', 'u1', 'view', new Date(2024, 0, 4, 12, 0)),
      makeActivity('7', 'u1', 'view', new Date(2024, 0, 4, 12, 5)),
      makeActivity('8', 'u1', 'click', new Date(2024, 0, 4, 12, 10)),
      makeActivity('9', 'u1', 'purchase', new Date(2024, 0, 4, 13, 0)),
      // another user should be ignored
      makeActivity('10', 'u2', 'spam', new Date(2024, 0, 1, 0, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')!

    expect(summary.totalActions).toBe(9)
    expect(summary.uniqueActions).toBe(4)
    expect(summary.mostFrequentAction).toBe('view')
    expect(summary.actionsPerDay).toBe(2.25) // 9 actions across ceil(3.166..) = 4 days
    expect(summary.averageActionsPerSession).toBe(1.8) // sessions = 5
  })

  it('uses daysActive minimum of 1 even when all activities in less than a day', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
      makeActivity('2', 'u1', 'b', new Date(2024, 0, 1, 9, 5)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')!
    expect(summary.actionsPerDay).toBe(2)
  })

  it('breaks sessions when gap > 30 minutes but not when exactly 30 minutes', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 9, 30)), // exactly 30 min, same session
      makeActivity('3', 'u1', 'a', new Date(2024, 0, 1, 10, 1)), // 31 min from previous, new session
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')!
    // total 3 actions, sessions 2, average = 1.5
    expect(summary.averageActionsPerSession).toBe(1.5)
  })

  it('resolves mostFrequentAction by first insertion order in tie cases', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'b', new Date(2024, 0, 1, 9, 0)),
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 9, 1)),
      // both have one count each, tie -> first encountered is 'b'
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')!
    expect(summary.mostFrequentAction).toBe('b')
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const trends = dashboard.getActivityTrends('u1')
    expect(trends).toEqual([])
  })

  it('groups by day with correct counts and growth rate', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 10, 0)),
      makeActivity('3', 'u1', 'b', new Date(2024, 0, 2, 9, 0)),
      makeActivity('4', 'u1', 'c', new Date(2024, 0, 4, 9, 0)),
      makeActivity('5', 'u1', 'c', new Date(2024, 0, 4, 10, 0)),
      makeActivity('6', 'u1', 'c', new Date(2024, 0, 4, 11, 0)),
      makeActivity('7', 'u1', 'c', new Date(2024, 0, 4, 12, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends.map(t => t.period)).toEqual(['2024-01-01', '2024-01-02', '2024-01-04'])
    expect(trends.map(t => t.count)).toEqual([2, 1, 4])
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].growthRate).toBe(-50)
    expect(trends[2].growthRate).toBe(300)
  })

  it('groups by hour with "YYYY-MM-DD HH:00" keys', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 9, 30)),
      makeActivity('3', 'u1', 'b', new Date(2024, 0, 1, 10, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'hour')
    expect(trends.map(t => t.period)).toEqual(['2024-01-01 09:00', '2024-01-01 10:00'])
    expect(trends.map(t => t.count)).toEqual([2, 1])
  })

  it('groups by week with "YYYY-Www" keys and sorts lexicographically', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),   // likely W01
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 2, 9, 0)),   // W01
      makeActivity('3', 'u1', 'b', new Date(2024, 0, 10, 9, 0)),  // likely W02
      makeActivity('4', 'u1', 'c', new Date(2024, 0, 15, 9, 0)),  // later week
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'week')
    // Ensure keys are in ascending lex order and counts aggregated
    expect(trends[0].period <= trends[1].period).toBe(true)
    expect(trends[1].period <= trends[2].period).toBe(true)
    expect(trends.reduce((sum, t) => sum + t.count, 0)).toBe(4)
  })

  it('groups by month with "YYYY-MM" keys', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 31, 23, 59)), // Jan
      makeActivity('2', 'u1', 'b', new Date(2024, 1, 1, 0, 1)),    // Feb
      makeActivity('3', 'u1', 'b', new Date(2024, 1, 15, 12, 0)),  // Feb
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends.map(t => t.period)).toEqual(['2024-01', '2024-02'])
    expect(trends.map(t => t.count)).toEqual([1, 2])
  })

  it('falls back to day grouping when given an invalid periodType', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 10, 0)),
      makeActivity('3', 'u1', 'b', new Date(2024, 0, 2, 9, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'invalid' as any)
    expect(trends.map(t => t.period)).toEqual(['2024-01-01', '2024-01-02'])
    expect(trends.map(t => t.count)).toEqual([2, 1])
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters inclusively between start and end dates', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 0, 0)),
      makeActivity('2', 'u1', 'b', new Date(2024, 0, 2, 0, 0)),
      makeActivity('3', 'u1', 'c', new Date(2024, 0, 3, 0, 0)),
      makeActivity('4', 'u2', 'x', new Date(2024, 0, 2, 0, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.filterByDateRange('u1', new Date(2024, 0, 2, 0, 0), new Date(2024, 0, 3, 0, 0))
    expect(result.map(a => a.id)).toEqual(['2', '3'])
  })

  it('returns empty array when no matches in range', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 0, 0)),
      makeActivity('2', 'u1', 'b', new Date(2024, 0, 2, 0, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.filterByDateRange('u1', new Date(2024, 0, 3, 0, 0), new Date(2024, 0, 4, 0, 0))
    expect(result).toEqual([])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const result = dashboard.aggregateByAction('u1')
    expect(result).toEqual([])
  })

  it('aggregates with counts, percentages, and first/last occurrences, sorted by count desc', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 10, 0)),
      makeActivity('3', 'u1', 'b', new Date(2024, 0, 1, 11, 0)),
      makeActivity('4', 'u1', 'b', new Date(2024, 0, 2, 11, 0)),
      makeActivity('5', 'u1', 'b', new Date(2024, 0, 3, 11, 0)),
      makeActivity('6', 'u1', 'c', new Date(2024, 0, 4, 12, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.aggregateByAction('u1')
    expect(result.map(r => r.action)).toEqual(['b', 'a', 'c'])
    expect(result.find(r => r.action === 'b')!.count).toBe(3)
    expect(result.find(r => r.action === 'a')!.count).toBe(2)
    expect(result.find(r => r.action === 'c')!.count).toBe(1)

    // Percentages for 6 total: b=50, a=33.33, c=16.67
    expect(result.find(r => r.action === 'b')!.percentage).toBe(50)
    expect(result.find(r => r.action === 'a')!.percentage).toBe(33.33)
    expect(result.find(r => r.action === 'c')!.percentage).toBe(16.67)

    // First/last occurrence check for 'b'
    const groupB = result.find(r => r.action === 'b')!
    expect(groupB.firstOccurrence.getTime()).toBe(new Date(2024, 0, 1, 11, 0).getTime())
    expect(groupB.lastOccurrence.getTime()).toBe(new Date(2024, 0, 3, 11, 0).getTime())
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('returns top N actions by count', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 0, 0)),
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 1, 0)),
      makeActivity('3', 'u1', 'b', new Date(2024, 0, 1, 2, 0)),
      makeActivity('4', 'u1', 'c', new Date(2024, 0, 1, 3, 0)),
      makeActivity('5', 'u1', 'c', new Date(2024, 0, 1, 4, 0)),
      makeActivity('6', 'u1', 'd', new Date(2024, 0, 1, 5, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const top2 = dashboard.getTopActions('u1', 2)
    expect(top2.map(t => t.action)).toEqual(['a', 'c'])
    expect(top2.map(t => t.count)).toEqual([2, 2])
  })

  it('uses default limit of 5 and returns fewer if not enough actions', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 0, 0)),
      makeActivity('2', 'u1', 'b', new Date(2024, 0, 1, 1, 0)),
      makeActivity('3', 'u1', 'c', new Date(2024, 0, 1, 2, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const top = dashboard.getTopActions('u1')
    expect(top.length).toBe(3)
  })

  it('returns empty array when there are no actions', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.getTopActions('u1')).toEqual([])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activity', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('u1')).toBe(0)
  })

  it('calculates score with capping and rounding to two decimals', () => {
    const activities: Activity[] = [
      // 20 actions over 2 days: actionsPerDay=10 -> capped at 5 for frequency score
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
      makeActivity('2', 'u1', 'b', new Date(2024, 0, 1, 9, 1)),
      makeActivity('3', 'u1', 'c', new Date(2024, 0, 1, 9, 2)),
      makeActivity('4', 'u1', 'd', new Date(2024, 0, 1, 9, 3)),
      makeActivity('5', 'u1', 'e', new Date(2024, 0, 1, 9, 4)),
      makeActivity('6', 'u1', 'f', new Date(2024, 0, 1, 9, 5)),
      makeActivity('7', 'u1', 'g', new Date(2024, 0, 1, 9, 6)),
      makeActivity('8', 'u1', 'h', new Date(2024, 0, 1, 9, 7)),
      makeActivity('9', 'u1', 'i', new Date(2024, 0, 1, 9, 8)),
      makeActivity('10', 'u1', 'j', new Date(2024, 0, 1, 9, 9)),
      makeActivity('11', 'u1', 'a', new Date(2024, 0, 2, 9, 0)),
      makeActivity('12', 'u1', 'b', new Date(2024, 0, 2, 9, 1)),
      makeActivity('13', 'u1', 'c', new Date(2024, 0, 2, 9, 2)),
      makeActivity('14', 'u1', 'd', new Date(2024, 0, 2, 9, 3)),
      makeActivity('15', 'u1', 'e', new Date(2024, 0, 2, 9, 4)),
      makeActivity('16', 'u1', 'f', new Date(2024, 0, 2, 9, 5)),
      makeActivity('17', 'u1', 'g', new Date(2024, 0, 2, 9, 6)),
      makeActivity('18', 'u1', 'h', new Date(2024, 0, 2, 9, 7)),
      makeActivity('19', 'u1', 'i', new Date(2024, 0, 2, 9, 8)),
      makeActivity('20', 'u1', 'j', new Date(2024, 0, 2, 9, 9)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('u1')
    // volume: min(20/100,1)*30 = 6
    // diversity: unique actions = 10 -> min(10/10,1)*30 = 30
    // frequency: actionsPerDay = 10 -> min(10/5,1)*40 = 40
    // total = 76
    expect(score).toBe(76)
  })

  it('calculates fractional scores with rounding', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 0, 0)),
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 2, 0, 0)),
      makeActivity('3', 'u1', 'b', new Date(2024, 0, 3, 0, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('u1')
    // total=3 => volume= (3/100)*30 = 0.9
    // unique=2 => diversity=(2/10)*30 = 6
    // daysActive: first=Jan1 00:00, last=Jan3 00:00 -> diff=2 days -> daysActive=2
    // actionsPerDay=1.5 => frequency=min(1.5/5,1)*40 = 12
    // total = 18.9 -> rounded to 18.9
    expect(score).toBe(18.9)
  })
})