import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function makeActivity(id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity {
  return { id, user_id, action, timestamp: date, metadata }
}

describe('ActivityDashboard', () => {
  it('getUserSummary returns null when user has no activities', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u2', 'login', new Date(2024, 0, 1, 10, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('getUserSummary computes totals, unique actions, most frequent, actionsPerDay and avg per session for same-day activities', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'u1', 'login', new Date(2024, 0, 1, 10, 10)),
      makeActivity('3', 'u1', 'view', new Date(2024, 0, 1, 10, 20)),
      makeActivity('4', 'u1', 'click', new Date(2024, 0, 1, 10, 30)),
      makeActivity('5', 'u2', 'login', new Date(2024, 0, 1, 9, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(4)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.mostFrequentAction).toBe('login')
    expect(summary!.actionsPerDay).toBe(4) // all within same day window -> daysActive = 1
    expect(summary!.averageActionsPerSession).toBe(4) // all within 30 mins -> 1 session
  })

  it('getUserSummary computes actionsPerDay across multiple days using ceil diff and rounds to two decimals', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 10, 0)),  // Jan 1
      makeActivity('2', 'u1', 'b', new Date(2024, 0, 2, 9, 0)),   // Jan 2
      makeActivity('3', 'u1', 'a', new Date(2024, 0, 3, 9, 0))    // Jan 3 -> diff ~47h => ceil 2 days
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    expect(summary!.uniqueActions).toBe(2)
    expect(summary!.actionsPerDay).toBe(1.5) // 3 actions / 2 daysActive
  })

  it('calculateAverageActionsPerSession uses 30-minute gap threshold (> 30 starts new session)', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 10, 0)),   // Session 1 start
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 10, 30)),  // exactly 30 min -> same session
      makeActivity('3', 'u1', 'a', new Date(2024, 0, 1, 11, 1)),   // 31 min after previous -> new session
      makeActivity('4', 'u1', 'a', new Date(2024, 0, 1, 11, 15))   // within 30 -> same session as previous
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(2) // 4 actions / 2 sessions
  })

  it('getActivityTrends (day) groups by local day and computes growth rates', () => {
    const acts: Activity[] = [
      // Jan 1: 1 action
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)),
      // Jan 2: 2 actions
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 2, 10, 0)),
      makeActivity('3', 'u1', 'b', new Date(2024, 0, 2, 15, 0)),
      // Jan 4: 4 actions (note: Jan 3 is a gap and should not appear)
      makeActivity('4', 'u1', 'c', new Date(2024, 0, 4, 8, 0)),
      makeActivity('5', 'u1', 'c', new Date(2024, 0, 4, 9, 0)),
      makeActivity('6', 'u1', 'c', new Date(2024, 0, 4, 10, 0)),
      makeActivity('7', 'u1', 'c', new Date(2024, 0, 4, 11, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends.map(t => t.period)).toEqual([
      '2024-01-01',
      '2024-01-02',
      '2024-01-04'
    ])
    expect(trends.map(t => t.count)).toEqual([1, 2, 4])
    expect(trends.map(t => t.growthRate)).toEqual([0, 100, 100])
  })

  it('getActivityTrends (hour) groups correctly with negative growth rate possible', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 10, 5)),
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 1, 10, 20)),
      makeActivity('3', 'u1', 'b', new Date(2024, 0, 1, 11, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'hour')
    expect(trends.map(t => t.period)).toEqual([
      '2024-01-01 10:00',
      '2024-01-01 11:00'
    ])
    expect(trends.map(t => t.count)).toEqual([2, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50])
  })

  it('getActivityTrends (week) groups into weeks', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 9, 0)), // 2024-01-01 -> W01
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 8, 12, 0)) // 2024-01-08 -> W02
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'week')
    expect(trends.map(t => t.period)).toEqual(['2024-W01', '2024-W02'])
    expect(trends.map(t => t.count)).toEqual([1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, 0])
  })

  it('getActivityTrends (month) groups into months', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 15, 9, 0)), // Jan
      makeActivity('2', 'u1', 'b', new Date(2024, 1, 2, 10, 0))  // Feb
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'month')
    expect(trends.map(t => t.period)).toEqual(['2024-01', '2024-02'])
    expect(trends.map(t => t.count)).toEqual([1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, 0])
  })

  it('getActivityTrends returns empty array when no user activities', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u2', 'a', new Date(2024, 0, 1, 9, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })

  it('filterByDateRange returns activities for user within inclusive date range', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2024, 0, 1, 0, 0)),
      makeActivity('2', 'u1', 'a', new Date(2024, 0, 2, 0, 0)),
      makeActivity('3', 'u1', 'a', new Date(2024, 0, 3, 0, 0)),
      makeActivity('4', 'u2', 'a', new Date(2024, 0, 2, 0, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.filterByDateRange('u1', new Date(2024, 0, 1, 0, 0), new Date(2024, 0, 2, 0, 0))
    expect(res.map(a => a.id)).toEqual(['1', '2'])
  })

  it('aggregateByAction returns groups sorted by count with percentages and first/last timestamps', () => {
    const a1 = new Date(2024, 0, 1, 10, 0)
    const a2 = new Date(2024, 0, 1, 12, 0)
    const v1 = new Date(2024, 0, 1, 11, 0)
    const c1 = new Date(2024, 0, 1, 13, 0)

    const acts: Activity[] = [
      makeActivity('1', 'u1', 'login', a1),
      makeActivity('2', 'u1', 'view', v1),
      makeActivity('3', 'u1', 'login', a2),
      makeActivity('4', 'u1', 'click', c1)
    ]
    const dash = new ActivityDashboard(acts)
    const groups = dash.aggregateByAction('u1')
    expect(groups.length).toBe(3)

    const top = groups[0]
    expect(top.action).toBe('login')
    expect(top.count).toBe(2)
    expect(top.percentage).toBe(50)
    expect(top.firstOccurrence.getTime()).toBe(a1.getTime())
    expect(top.lastOccurrence.getTime()).toBe(a2.getTime())

    const actions = groups.map(g => g.action)
    expect(actions).toEqual(expect.arrayContaining(['view', 'click', 'login']))
  })

  it('aggregateByAction returns empty array when user has no activities', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u2', 'login', new Date(2024, 0, 1, 10, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.aggregateByAction('u1')
    expect(res).toEqual([])
  })

  it('getTopActions respects limit and returns top N actions', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'A', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'u1', 'B', new Date(2024, 0, 1, 11, 0)),
      makeActivity('3', 'u1', 'A', new Date(2024, 0, 1, 12, 0)),
      makeActivity('4', 'u1', 'C', new Date(2024, 0, 1, 13, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const top2 = dash.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('A')
    expect(top2[0].count).toBe(2)
  })

  it('getTopActions default limit is 5', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'A', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'u1', 'B', new Date(2024, 0, 1, 11, 0)),
      makeActivity('3', 'u1', 'C', new Date(2024, 0, 1, 12, 0)),
      makeActivity('4', 'u1', 'D', new Date(2024, 0, 1, 13, 0)),
      makeActivity('5', 'u1', 'E', new Date(2024, 0, 1, 14, 0)),
      makeActivity('6', 'u1', 'F', new Date(2024, 0, 1, 15, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const top = dash.getTopActions('u1')
    expect(top.length).toBe(5)
  })

  it('getTopActions_old returns all actions and ignores limit parameter', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'A', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'u1', 'B', new Date(2024, 0, 1, 11, 0)),
      makeActivity('3', 'u1', 'C', new Date(2024, 0, 1, 12, 0)),
      makeActivity('4', 'u1', 'D', new Date(2024, 0, 1, 13, 0)),
      makeActivity('5', 'u1', 'E', new Date(2024, 0, 1, 14, 0)),
      makeActivity('6', 'u1', 'F', new Date(2024, 0, 1, 15, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.getTopActions_old('u1', 2)
    expect(res.length).toBe(6)
    const names = res.map(r => r.action)
    expect(names).toEqual(expect.arrayContaining(['A', 'B', 'C', 'D', 'E,', 'F'].map(s => s.replace(',', ''))))
  })

  it('calculateEngagementScore returns 0 for users with no activity', () => {
    const dash = new ActivityDashboard([])
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(0)
  })

  it('calculateEngagementScore computes score based on volume, diversity, and frequency with rounding', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'A', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'u1', 'A', new Date(2024, 0, 1, 10, 10)),
      makeActivity('3', 'u1', 'A', new Date(2024, 0, 1, 10, 20)),
      makeActivity('4', 'u1', 'A', new Date(2024, 0, 1, 10, 30)),
      makeActivity('5', 'u1', 'A', new Date(2024, 0, 1, 10, 40)),
      makeActivity('6', 'u1', 'B', new Date(2024, 0, 1, 10, 50)),
      makeActivity('7', 'u1', 'B', new Date(2024, 0, 1, 11, 0)),
      makeActivity('8', 'u1', 'B', new Date(2024, 0, 1, 11, 10)),
      makeActivity('9', 'u1', 'B', new Date(2024, 0, 1, 11, 20)),
      makeActivity('10', 'u1', 'B', new Date(2024, 0, 1, 11, 30))
    ]
    const dash = new ActivityDashboard(acts)
    const score = dash.calculateEngagementScore('u1')
    // total=10 -> volume 3, unique=2 -> diversity 6, actionsPerDay 10 -> frequency 40 => total 49
    expect(score).toBe(49)
  })

  it('calculateEngagementScore caps at 100 when all components saturate', () => {
    const acts: Activity[] = []
    for (let i = 0; i < 200; i++) {
      acts.push(makeActivity(String(i + 1), 'u1', `A${i % 20}`, new Date(2024, 0, 1, 0, i % 60)))
    }
    const dash = new ActivityDashboard(acts)
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(100)
  })

  it('getActivityTrends filters by userId', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'A', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'u2', 'A', new Date(2024, 0, 1, 11, 0)),
      makeActivity('3', 'u1', 'B', new Date(2024, 0, 2, 10, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends.map(t => t.period)).toEqual(['2024-01-01', '2024-01-02'])
    expect(trends.map(t => t.count)).toEqual([1, 1])
  })

  it('filterByDateRange excludes activities from other users even if in range', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'A', new Date(2024, 0, 1, 0, 0)),
      makeActivity('2', 'u2', 'A', new Date(2024, 0, 1, 12, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.filterByDateRange('u1', new Date(2024, 0, 1, 0, 0), new Date(2024, 0, 2, 0, 0))
    expect(res.length).toBe(1)
    expect(res[0].user_id).toBe('u1')
  })

  it('getTopActions only uses specified user activities', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'A', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'u2', 'A', new Date(2024, 0, 1, 10, 5)),
      makeActivity('3', 'u1', 'B', new Date(2024, 0, 1, 10, 10)),
      makeActivity('4', 'u2', 'B', new Date(2024, 0, 1, 10, 15)),
      makeActivity('5', 'u1', 'A', new Date(2024, 0, 1, 10, 20))
    ]
    const dash = new ActivityDashboard(acts)
    const top = dash.getTopActions('u1', 5)
    expect(top.length).toBe(2)
    const actions = top.map(t => t.action)
    expect(actions).toEqual(expect.arrayContaining(['A', 'B']))
    const topA = top.find(t => t.action === 'A')!
    expect(topA.count).toBe(2)
  })
})