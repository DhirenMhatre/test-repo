import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

const makeAct = (
  id: string,
  user_id: string,
  action: string,
  y: number,
  m: number,
  d: number,
  h = 0,
  mi = 0,
  s = 0
) => ({
  id,
  user_id,
  action,
  timestamp: new Date(y, m - 1, d, h, mi, s)
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const activities = [
      makeAct('1', 'u2', 'click', 2023, 1, 1, 10, 0),
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, actionsPerDay, mostFrequentAction, and averageActionsPerSession for single-day activities', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 1, 10, 0),
      makeAct('2', 'u1', 'click', 2023, 1, 1, 10, 10),
      makeAct('3', 'u1', 'view', 2023, 1, 1, 11, 0), // 50 min gap from previous => new session
      makeAct('4', 'u2', 'click', 2023, 1, 1, 12, 0) // other user
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    expect(summary!.uniqueActions).toBe(2)
    expect(summary!.actionsPerDay).toBe(3) // same day => daysActive = 1
    expect(summary!.mostFrequentAction).toBe('click')
    expect(summary!.averageActionsPerSession).toBe(1.5) // 2 sessions, 3 actions
  })

  it('computes actionsPerDay across multiple days with correct rounding', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 1, 0, 0),
      makeAct('2', 'u1', 'view', 2023, 1, 2, 12, 0),
      makeAct('3', 'u1', 'login', 2023, 1, 3, 0, 0),
      makeAct('4', 'u1', 'view', 2023, 1, 2, 13, 0),
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(4)
    // first: 2023-01-01 00:00, last: 2023-01-03 00:00 => (2 days) => ceil(2) => 2 daysActive
    expect(summary!.actionsPerDay).toBe(2) // 4/2 = 2.00
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.uniqueActions).toBe(3)
  })

  it('session boundary at exactly 30 minutes does not start a new session', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 1, 10, 0),
      makeAct('2', 'u1', 'click', 2023, 1, 1, 10, 30), // exactly 30 mins later => same session
      makeAct('3', 'u1', 'click', 2023, 1, 1, 11, 1), // 31 mins later => new session
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(1.5) // 3 actions / 2 sessions = 1.50
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })

  it('groups by day with correct counts and growth rates', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 1, 10, 0),
      makeAct('2', 'u1', 'view', 2023, 1, 1, 12, 0),
      makeAct('3', 'u1', 'click', 2023, 1, 2, 9, 0),
      makeAct('4', 'u1', 'click', 2023, 1, 4, 10, 0),
      makeAct('5', 'u1', 'click', 2023, 1, 4, 18, 0),
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends).toHaveLength(3)
    expect(trends[0]).toEqual({ period: '2023-01-01', count: 2, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2023-01-02', count: 1, growthRate: -50 })
    expect(trends[2]).toEqual({ period: '2023-01-04', count: 2, growthRate: 100 })
  })

  it('default period type is day', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 1, 10, 0),
      makeAct('2', 'u1', 'view', 2023, 1, 1, 12, 0),
      makeAct('3', 'u1', 'click', 2023, 1, 2, 9, 0),
    ]
    const dash = new ActivityDashboard(activities)
    const trends1 = dash.getActivityTrends('u1')
    const trends2 = dash.getActivityTrends('u1', 'day')
    expect(trends1).toEqual(trends2)
  })

  it('groups by hour with zero-padded hour and correct growth rates', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 1, 9, 10),
      makeAct('2', 'u1', 'view', 2023, 1, 1, 9, 45),
      makeAct('3', 'u1', 'click', 2023, 1, 1, 11, 5),
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'hour')
    expect(trends).toHaveLength(2)
    expect(trends[0]).toEqual({ period: '2023-01-01 09:00', count: 2, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2023-01-01 11:00', count: 1, growthRate: -50 })
  })

  it('groups by week using its custom week number calculation', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 1, 10, 0),  // 2023-W01
      makeAct('2', 'u1', 'click', 2023, 1, 8, 10, 0),  // 2023-W02
      makeAct('3', 'u1', 'view', 2023, 1, 8, 11, 0),   // 2023-W02
      makeAct('4', 'u1', 'login', 2023, 1, 15, 9, 0),  // 2023-W03
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'week')
    expect(trends).toHaveLength(3)
    expect(trends[0]).toEqual({ period: '2023-W01', count: 1, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2023-W02', count: 2, growthRate: 100 })
    expect(trends[2]).toEqual({ period: '2023-W03', count: 1, growthRate: -50 })
  })

  it('groups by month with correct counts and growth rates', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 5, 10, 0),  // Jan
      makeAct('2', 'u1', 'view', 2023, 1, 6, 12, 0),   // Jan
      makeAct('3', 'u1', 'click', 2023, 2, 1, 9, 0),   // Feb
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'month')
    expect(trends).toHaveLength(2)
    expect(trends[0]).toEqual({ period: '2023-01', count: 2, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2023-02', count: 1, growthRate: -50 })
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('includes activities on the boundary dates (inclusive)', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 1, 9, 0),
      makeAct('2', 'u1', 'click', 2023, 1, 1, 10, 0), // start boundary
      makeAct('3', 'u1', 'view', 2023, 1, 2, 0, 0),   // within range
      makeAct('4', 'u1', 'login', 2023, 1, 2, 10, 0), // end boundary
      makeAct('5', 'u1', 'logout', 2023, 1, 3, 9, 59),
      makeAct('6', 'u2', 'click', 2023, 1, 1, 10, 0),
    ]
    const dash = new ActivityDashboard(activities)
    const start = new Date(2023, 0, 1, 10, 0)
    const end = new Date(2023, 0, 2, 10, 0)
    const result = dash.filterByDateRange('u1', start, end)
    const ids = result.map(a => a.id)
    expect(ids.sort()).toEqual(['2', '3', '4'])
  })

  it('returns empty when no items fall in the range or user mismatch', () => {
    const activities = [
      makeAct('1', 'u2', 'click', 2023, 1, 1, 10, 0),
      makeAct('2', 'u2', 'click', 2023, 1, 2, 10, 0),
    ]
    const dash = new ActivityDashboard(activities)
    const start = new Date(2023, 0, 1, 0, 0)
    const end = new Date(2023, 0, 1, 23, 59)
    const result = dash.filterByDateRange('u1', start, end)
    expect(result).toEqual([])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array when no activities for user', () => {
    const dash = new ActivityDashboard([])
    const groups = dash.aggregateByAction('u1')
    expect(groups).toEqual([])
  })

  it('aggregates counts, percentages, and first/last occurrence; sorted by count desc', () => {
    const y = 2023, m = 1, d = 1
    const activities = [
      makeAct('1', 'u1', 'click', y, m, d, 9, 0),     // click first at 09:00
      makeAct('2', 'u1', 'view', y, m, d, 8, 0),      // view first at 08:00
      makeAct('3', 'u1', 'click', y, m, d, 12, 0),    // click last at 12:00
      makeAct('4', 'u1', 'download', y, m, d, 7, 30), // download only
      makeAct('5', 'u1', 'view', y, m, d, 11, 0),     // view last at 11:00
      makeAct('6', 'u1', 'click', y, m, d, 10, 0),    // middle click
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.aggregateByAction('u1')
    expect(groups).toHaveLength(3)

    const click = groups.find(g => g.action === 'click')!
    const view = groups.find(g => g.action === 'view')!
    const download = groups.find(g => g.action === 'download')!

    expect(click.count).toBe(3)
    expect(view.count).toBe(2)
    expect(download.count).toBe(1)

    expect(click.percentage).toBeCloseTo(50.00, 2)
    expect(view.percentage).toBeCloseTo(33.33, 2)
    expect(download.percentage).toBeCloseTo(16.67, 2)

    expect(click.firstOccurrence.getTime()).toBe(new Date(y, m - 1, d, 9, 0).getTime())
    expect(click.lastOccurrence.getTime()).toBe(new Date(y, m - 1, d, 12, 0).getTime())
    expect(view.firstOccurrence.getTime()).toBe(new Date(y, m - 1, d, 8, 0).getTime())
    expect(view.lastOccurrence.getTime()).toBe(new Date(y, m - 1, d, 11, 0).getTime())
    expect(download.firstOccurrence.getTime()).toBe(new Date(y, m - 1, d, 7, 30).getTime())
    expect(download.lastOccurrence.getTime()).toBe(new Date(y, m - 1, d, 7, 30).getTime())

    // Ensure sorted by count desc: click first, then view, then download
    expect(groups[0].action).toBe('click')
    expect(groups[1].action).toBe('view')
    expect(groups[2].action).toBe('download')
  })

  it('handles ties in counts without crashing and includes all actions', () => {
    const activities = [
      makeAct('1', 'u1', 'a', 2023, 1, 1, 10, 0),
      makeAct('2', 'u1', 'b', 2023, 1, 1, 11, 0),
      makeAct('3', 'u1', 'a', 2023, 1, 1, 12, 0),
      makeAct('4', 'u1', 'b', 2023, 1, 1, 13, 0),
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.aggregateByAction('u1')
    const map = new Map(groups.map(g => [g.action, g.count]))
    expect(map.get('a')).toBe(2)
    expect(map.get('b')).toBe(2)
  })
})

describe('ActivityDashboard - getTopActions and getTopActions_old', () => {
  it('getTopActions respects the limit', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 1, 9, 0),
      makeAct('2', 'u1', 'click', 2023, 1, 1, 10, 0),
      makeAct('3', 'u1', 'view', 2023, 1, 1, 11, 0),
      makeAct('4', 'u1', 'view', 2023, 1, 1, 12, 0),
      makeAct('5', 'u1', 'download', 2023, 1, 1, 13, 0),
    ]
    const dash = new ActivityDashboard(activities)
    const top2 = dash.getTopActions('u1', 2)
    expect(top2).toHaveLength(2)
    const actions = top2.map(g => g.action)
    expect(actions).toEqual(['click', 'view'])
  })

  it('getTopActions returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const result = dash.getTopActions('u1', 3)
    expect(result).toEqual([])
  })

  it('getTopActions_old returns all groups (does not apply limit)', () => {
    const activities = [
      makeAct('1', 'u1', 'click', 2023, 1, 1, 9, 0),
      makeAct('2', 'u1', 'click', 2023, 1, 1, 10, 0),
      makeAct('3', 'u1', 'view', 2023, 1, 1, 11, 0),
      makeAct('4', 'u1', 'download', 2023, 1, 1, 12, 0),
    ]
    const dash = new ActivityDashboard(activities)
    const top1Old = dash.getTopActions_old('u1', 1)
    expect(top1Old).toHaveLength(3) // should ignore limit and include all actions
    const actions = top1Old.map(g => g.action).sort()
    expect(actions).toEqual(['click', 'download', 'view'])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activity summary', () => {
    const dash = new ActivityDashboard([])
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(0)
  })

  it('computes engagement score with proper capping and rounding', () => {
    // 10 actions in one day, 5 unique actions => volume=3, diversity=15, frequency=40 => total=58.00
    const actions = ['a1', 'a2', 'a3', 'a4', 'a5']
    const activities = []
    let id = 1
    for (let i = 0; i < 10; i++) {
      const action = actions[i % actions.length]
      activities.push(makeAct(String(id++), 'u1', action, 2023, 1, 1, 10, i)) // all within same day window
    }
    const dash = new ActivityDashboard(activities)
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(58)
  })
})