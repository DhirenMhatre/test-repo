import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

describe('ActivityDashboard', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  const d = (y: number, m: number, day: number, h = 0, mi = 0, s = 0) =>
    new Date(y, m - 1, day, h, mi, s)

  const makeActivity = (id: string, userId: string, action: string, date: Date, metadata: Record<string, any> = {}) => ({
    id,
    user_id: userId,
    action,
    timestamp: date,
    metadata
  } as Activity)

  it('getUserSummary returns null when user has no activities', () => {
    const activities: Activity[] = [
      makeActivity('1', 'other', 'login', d(2023, 1, 1, 10)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('getUserSummary computes correct summary including rounding and most frequent', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'login', d(2023, 1, 1, 10, 0)),
      makeActivity('2', 'u1', 'view', d(2023, 1, 1, 10, 10)),
      makeActivity('3', 'u1', 'view', d(2023, 1, 1, 12, 0)),
      makeActivity('4', 'u1', 'logout', d(2023, 1, 2, 11, 0)),
      makeActivity('5', 'other', 'login', d(2023, 1, 1, 10, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(4)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.actionsPerDay).toBe(2) // 4 actions across ceil(1 day + 1 hour) = 2 days => 2.00
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.averageActionsPerSession).toBe(1.33) // sessions: [10:00,10:10], [12:00], [next day 11:00]
  })

  it('getUserSummary uses min daysActive of 1 yielding actionsPerDay equal to total actions when same timestamp', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'click', d(2023, 1, 1, 10, 0)),
      makeActivity('2', 'u1', 'click', d(2023, 1, 1, 10, 0)),
      makeActivity('3', 'u1', 'view', d(2023, 1, 1, 10, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.actionsPerDay).toBe(3)
    expect(summary!.averageActionsPerSession).toBe(3) // no gap > 30min
  })

  it('getUserSummary rounds actionsPerDay to 2 decimals', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 10, 0)),
      makeActivity('2', 'u1', 'b', d(2023, 1, 1, 11, 0)),
      makeActivity('3', 'u1', 'c', d(2023, 1, 2, 12, 0)),
      makeActivity('4', 'u1', 'd', d(2023, 1, 3, 9, 0)),
      makeActivity('5', 'u1', 'e', d(2023, 1, 3, 10, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    // first: Jan 1 10:00, last: Jan 3 10:00 -> 2 days exactly -> ceil(2) = 2? Difference is 48 hours? Jan 1 10 to Jan 3 10 = 48 hours -> 2 days -> ceil(2) = 2
    // To ensure non-integer daysActive, adjust last to Jan 3 9:00 -> 47 hours -> ceil(1.958..) = 2. With 5 actions: 5/2 = 2.5 -> 2.50
    expect(summary!.actionsPerDay).toBe(2.5)
  })

  it('getActivityTrends groups by day with correct counts and growthRate', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 10, 0)),
      makeActivity('2', 'u1', 'b', d(2023, 1, 1, 11, 0)),
      makeActivity('3', 'u1', 'c', d(2023, 1, 2, 9, 0)),
      makeActivity('4', 'u1', 'd', d(2023, 1, 3, 8, 0)),
      makeActivity('5', 'u1', 'e', d(2023, 1, 3, 9, 0)),
      makeActivity('6', 'u1', 'f', d(2023, 1, 3, 10, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends.map(t => t.period)).toEqual(['2023-01-01', '2023-01-02', '2023-01-03'])
    expect(trends.map(t => t.count)).toEqual([2, 1, 3])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50, 200])
  })

  it('getActivityTrends groups by hour with correct formatting and growthRate', () => {
    const baseDate = d(2023, 1, 1, 10, 0)
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 10, 5)),
      makeActivity('2', 'u1', 'b', d(2023, 1, 1, 10, 45)),
      makeActivity('3', 'u1', 'c', d(2023, 1, 1, 11, 0)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'hour')
    expect(trends.map(t => t.period)).toEqual(['2023-01-01 10:00', '2023-01-01 11:00'])
    expect(trends.map(t => t.count)).toEqual([2, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50])
    expect(baseDate.getHours()).toBe(10)
  })

  it('getActivityTrends groups by week using getWeekNumber', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 10)),   // Week 01
      makeActivity('2', 'u1', 'b', d(2023, 1, 15, 9)),  // Likely Week 03
      makeActivity('3', 'u1', 'c', d(2023, 1, 15, 10)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends[0].period).toMatch(/^2023-W0?1$/)
    expect(trends[0].count).toBe(1)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].period).toMatch(/^2023-W0?3$/)
    expect(trends[1].count).toBe(2)
    expect(trends[1].growthRate).toBe(100)
  })

  it('getActivityTrends groups by month', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 3, 10, 10)),
      makeActivity('2', 'u1', 'b', d(2023, 3, 11, 12)),
      makeActivity('3', 'u1', 'c', d(2023, 4, 1, 9)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends.map(t => t.period)).toEqual(['2023-03', '2023-04'])
    expect(trends.map(t => t.count)).toEqual([2, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50])
  })

  it('getActivityTrends returns empty array when no activities for user', () => {
    const activities: Activity[] = [
      makeActivity('1', 'other', 'a', d(2023, 1, 1, 10)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })

  it('filterByDateRange returns only activities within inclusive range and correct user', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 10)),
      makeActivity('2', 'u1', 'b', d(2023, 1, 2, 10)),
      makeActivity('3', 'u1', 'c', d(2023, 1, 3, 10)),
      makeActivity('4', 'other', 'c', d(2023, 1, 2, 10)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.filterByDateRange('u1', d(2023, 1, 2, 10), d(2023, 1, 3, 10))
    expect(result.map(a => a.id)).toEqual(['2', '3'])
  })

  it('aggregateByAction groups, calculates percentages and first/lastOccurrence, sorted by count desc', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'click', d(2023, 1, 1, 10)),
      makeActivity('2', 'u1', 'click', d(2023, 1, 1, 11)),
      makeActivity('3', 'u1', 'click', d(2023, 1, 2, 9)),
      makeActivity('4', 'u1', 'login', d(2023, 1, 1, 9)),
      makeActivity('5', 'u1', 'login', d(2023, 1, 3, 12)),
      makeActivity('6', 'u1', 'view', d(2023, 1, 2, 12)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups.map(g => g.action)).toEqual(['click', 'login', 'view'])
    expect(groups.map(g => g.count)).toEqual([3, 2, 1])
    expect(groups[0].percentage).toBe(50)      // 3/6 * 100 = 50.00
    expect(groups[1].percentage).toBe(33.33)   // 2/6 * 100 = 33.33
    expect(groups[2].percentage).toBe(16.67)   // 1/6 * 100 = 16.67
    expect(groups[0].firstOccurrence.getTime()).toBe(d(2023, 1, 1, 10).getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(d(2023, 1, 2, 9).getTime())
    expect(groups[1].firstOccurrence.getTime()).toBe(d(2023, 1, 1, 9).getTime())
    expect(groups[1].lastOccurrence.getTime()).toBe(d(2023, 1, 3, 12).getTime())
  })

  it('aggregateByAction returns empty array when user has no activities', () => {
    const activities: Activity[] = [makeActivity('1', 'other', 'a', d(2023, 1, 1, 10))]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups).toEqual([])
  })

  it('getTopActions respects limit', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 10)),
      makeActivity('2', 'u1', 'a', d(2023, 1, 1, 11)),
      makeActivity('3', 'u1', 'b', d(2023, 1, 1, 12)),
      makeActivity('4', 'u1', 'b', d(2023, 1, 2, 9)),
      makeActivity('5', 'u1', 'c', d(2023, 1, 2, 10)),
      makeActivity('6', 'u1', 'd', d(2023, 1, 2, 11)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const top2 = dashboard.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2.map(g => g.action)).toEqual(['a', 'b']) // 'a' and 'b' each count 2; their relative order based on initial grouping order: aggregateByAction sorts by count desc; among same count, insertion order from map may determine - here 'a' then 'b'
  })

  it('getTopActions default limit of 5 returns all if fewer groups exist', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'x', d(2023, 1, 1, 10)),
      makeActivity('2', 'u1', 'y', d(2023, 1, 1, 11)),
      makeActivity('3', 'u1', 'x', d(2023, 1, 1, 12)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const top = dashboard.getTopActions('u1')
    expect(top.length).toBe(2)
    expect(top.map(g => g.action)).toEqual(['x', 'y'])
  })

  it('calculateEngagementScore returns 0 when user has no activities', () => {
    const activities: Activity[] = []
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(0)
  })

  it('calculateEngagementScore calculates with caps and rounding', () => {
    // 10 actions, 3 unique, over 2 days -> volume 0.1*30=3, diversity 0.3*30=9, frequency min(5/5,1)*40=40 => 52.00
    const acts: Activity[] = []
    for (let i = 0; i < 9; i++) {
      const action = i % 3 === 0 ? 'a' : i % 3 === 1 ? 'b' : 'c'
      acts.push(makeActivity(`${i + 1}`, 'u1', action, d(2023, 1, 1, 10, i)))
    }
    acts.push(makeActivity('10', 'u1', 'a', d(2023, 1, 2, 0, 10)))
    const dashboard = new ActivityDashboard(acts)
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(52)
  })

  it('calculateEngagementScore caps each component at maximum leading to 100', () => {
    const acts: Activity[] = []
    // 110 actions on the same day to cap volume and frequency; include more than 10 unique actions
    const uniqueActions = Array.from({ length: 12 }).map((_, i) => `act${i}`)
    for (let i = 0; i < 110; i++) {
      acts.push(makeActivity(`${i + 1}`, 'u1', uniqueActions[i % uniqueActions.length], d(2023, 1, 1, 0, i)))
    }
    const dashboard = new ActivityDashboard(acts)
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(100)
  })

  it('filterByDateRange returns empty array for user with no activities in range', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 10)),
      makeActivity('2', 'u1', 'b', d(2023, 1, 3, 10)),
      makeActivity('3', 'u2', 'c', d(2023, 1, 2, 10)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.filterByDateRange('u1', d(2023, 1, 1, 11), d(2023, 1, 2, 9))
    expect(result).toEqual([])
  })

  it('getActivityTrends defaults to day when periodType not provided', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 5, 1, 10)),
      makeActivity('2', 'u1', 'b', d(2023, 5, 1, 11)),
      makeActivity('3', 'u1', 'c', d(2023, 5, 2, 9)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1')
    expect(trends.map(t => t.period)).toEqual(['2023-05-01', '2023-05-02'])
    expect(trends.map(t => t.count)).toEqual([2, 1])
  })

  it('getUserSummary handles single action correctly', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'only', d(2023, 6, 1, 12)),
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(1)
    expect(summary!.uniqueActions).toBe(1)
    expect(summary!.actionsPerDay).toBe(1)
    expect(summary!.mostFrequentAction).toBe('only')
    expect(summary!.averageActionsPerSession).toBe(1)
  })
})