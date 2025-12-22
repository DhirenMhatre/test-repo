import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

const d = (y: number, m: number, day: number, h = 0, min = 0, s = 0) => new Date(y, m, day, h, min, s)

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const activities = [
      { id: '1', user_id: 'other', action: 'click', timestamp: d(2023, 0, 1, 10) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const summary = dash.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, most frequent, actionsPerDay, and avg actions per session', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'click', timestamp: d(2023, 0, 1, 10, 0) },
      { id: '2', user_id: 'u1', action: 'click', timestamp: d(2023, 0, 1, 10, 10) },
      { id: '3', user_id: 'u1', action: 'view',  timestamp: d(2023, 0, 1, 10, 20) },
      { id: '4', user_id: 'u1', action: 'click', timestamp: d(2023, 0, 1, 11, 1) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const summary = dash.getUserSummary('u1')!
    expect(summary.totalActions).toBe(4)
    expect(summary.uniqueActions).toBe(2)
    expect(summary.mostFrequentAction).toBe('click')
    expect(summary.actionsPerDay).toBe(4)
    expect(summary.averageActionsPerSession).toBe(2.00)
  })

  it('calculates actionsPerDay using ceil days between first and last activity with minimum 1 day', () => {
    const activities = [
      { id: '1', user_id: 'u2', action: 'a', timestamp: d(2023, 0, 1, 10, 0) },
      { id: '2', user_id: 'u2', action: 'b', timestamp: d(2023, 0, 3, 9, 0) } // ~47 hours later => ceil(1.958) = 2 days
    ]
    const dash = new ActivityDashboard(activities as any)
    const summary = dash.getUserSummary('u2')!
    expect(summary.totalActions).toBe(2)
    expect(summary.actionsPerDay).toBe(parseFloat((2 / 2).toFixed(2)))
  })

  it('keeps first seen action as most frequent on ties', () => {
    const activities = [
      { id: '1', user_id: 'u10', action: 'a', timestamp: d(2023, 0, 1, 10) },
      { id: '2', user_id: 'u10', action: 'b', timestamp: d(2023, 0, 1, 11) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const summary = dash.getUserSummary('u10')!
    expect(summary.totalActions).toBe(2)
    expect(summary.uniqueActions).toBe(2)
    expect(summary.mostFrequentAction).toBe('a')
  })

  it('averageActionsPerSession treats exactly 30-minute gaps as same session', () => {
    const activities = [
      { id: '1', user_id: 'u11', action: 'x', timestamp: d(2023, 0, 1, 10, 0) },
      { id: '2', user_id: 'u11', action: 'y', timestamp: d(2023, 0, 1, 10, 30) }, // exactly 30 minutes later -> same session
      { id: '3', user_id: 'u11', action: 'z', timestamp: d(2023, 0, 1, 11, 1) }  // >30 minutes from previous -> new session
    ]
    const dash = new ActivityDashboard(activities as any)
    const summary = dash.getUserSummary('u11')!
    expect(summary.totalActions).toBe(3)
    expect(summary.averageActionsPerSession).toBe(1.5)
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('returns empty array when no activities for user', () => {
    const dash = new ActivityDashboard([] as any)
    const trends = dash.getActivityTrends('none', 'day')
    expect(trends).toEqual([])
  })

  it('groups by day with correct growth rates and sorted periods', () => {
    const u = 'trend-day'
    const activities = [
      // Day 1: 2 events
      { id: '1', user_id: u, action: 'a', timestamp: d(2023, 0, 1, 9) },
      { id: '2', user_id: u, action: 'b', timestamp: d(2023, 0, 1, 10) },
      // Day 2: 4 events
      { id: '3', user_id: u, action: 'a', timestamp: d(2023, 0, 2, 12) },
      { id: '4', user_id: u, action: 'b', timestamp: d(2023, 0, 2, 13) },
      { id: '5', user_id: u, action: 'c', timestamp: d(2023, 0, 2, 14) },
      { id: '6', user_id: u, action: 'd', timestamp: d(2023, 0, 2, 15) },
      // Day 3: 2 events
      { id: '7', user_id: u, action: 'a', timestamp: d(2023, 0, 3, 15) },
      { id: '8', user_id: u, action: 'b', timestamp: d(2023, 0, 3, 16) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const trends = dash.getActivityTrends(u, 'day')
    expect(trends.map(t => t.period)).toEqual(['2023-01-01', '2023-01-02', '2023-01-03'])
    expect(trends.map(t => t.count)).toEqual([2, 4, 2])
    expect(trends.map(t => t.growthRate)).toEqual([0, 100, -50])
  })

  it('groups by hour with HH:00 keys and correct growth rates', () => {
    const u = 'trend-hour'
    const activities = [
      { id: '1', user_id: u, action: 'a', timestamp: d(2023, 0, 1, 9, 5) },
      { id: '2', user_id: u, action: 'b', timestamp: d(2023, 0, 1, 9, 15) },
      { id: '3', user_id: u, action: 'c', timestamp: d(2023, 0, 1, 10, 0) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const trends = dash.getActivityTrends(u, 'hour')
    expect(trends.map(t => t.period)).toEqual(['2023-01-01 09:00', '2023-01-01 10:00'])
    expect(trends.map(t => t.count)).toEqual([2, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50])
  })

  it('groups by week using custom week number and computes growth', () => {
    const u = 'trend-week'
    const activities = [
      { id: '1', user_id: u, action: 'x', timestamp: d(2023, 0, 1, 12) },  // 2023-01-01 (week 1 with provided formula)
      { id: '2', user_id: u, action: 'x', timestamp: d(2023, 0, 8, 12) },  // week 2
      { id: '3', user_id: u, action: 'x', timestamp: d(2023, 0, 8, 14) }   // week 2
    ]
    const dash = new ActivityDashboard(activities as any)
    const trends = dash.getActivityTrends(u, 'week')
    expect(trends.map(t => t.period)).toEqual(['2023-W01', '2023-W02'])
    expect(trends.map(t => t.count)).toEqual([1, 2])
    expect(trends.map(t => t.growthRate)).toEqual([0, 100])
  })

  it('groups by month with YYYY-MM keys', () => {
    const u = 'trend-month'
    const activities = [
      { id: '1', user_id: u, action: 'x', timestamp: d(2023, 0, 15, 10) },
      { id: '2', user_id: u, action: 'y', timestamp: d(2023, 0, 16, 10) },
      { id: '3', user_id: u, action: 'z', timestamp: d(2023, 1, 5, 10) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const trends = dash.getActivityTrends(u, 'month')
    expect(trends.map(t => t.period)).toEqual(['2023-01', '2023-02'])
    expect(trends.map(t => t.count)).toEqual([2, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50])
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('filters activities inclusively by start and end date for a user', () => {
    const u = 'u7'
    const start = d(2023, 0, 1, 0, 0, 0)
    const end = d(2023, 0, 31, 23, 59, 59)
    const activities = [
      { id: '0', user_id: u, action: 'x', timestamp: d(2022, 11, 31, 23, 59, 59) }, // before
      { id: '1', user_id: u, action: 'x', timestamp: start }, // at start
      { id: '2', user_id: u, action: 'x', timestamp: d(2023, 0, 15, 12, 0, 0) }, // within
      { id: '3', user_id: u, action: 'x', timestamp: end }, // at end
      { id: '4', user_id: u, action: 'x', timestamp: d(2023, 1, 1, 0, 0, 0) }, // after
      { id: '5', user_id: 'other', action: 'x', timestamp: d(2023, 0, 15, 12, 0, 0) } // other user
    ]
    const dash = new ActivityDashboard(activities as any)
    const filtered = dash.filterByDateRange(u, start, end)
    expect(filtered.map(a => a.id)).toEqual(['1', '2', '3'])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('aggregates counts, percentages, and occurrences, sorted by count desc', () => {
    const u = 'u8'
    const activities = [
      { id: '1', user_id: u, action: 'like', timestamp: d(2023, 0, 1, 8, 0) },
      { id: '2', user_id: u, action: 'share', timestamp: d(2023, 0, 1, 9, 0) },
      { id: '3', user_id: u, action: 'like', timestamp: d(2023, 0, 1, 10, 0) },
      { id: '4', user_id: u, action: 'like', timestamp: d(2023, 0, 2, 10, 0) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const groups = dash.aggregateByAction(u)
    expect(groups.length).toBe(2)

    expect(groups[0].action).toBe('like')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(75.0)
    expect(groups[0].firstOccurrence.getTime()).toBe(d(2023, 0, 1, 8, 0).getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(d(2023, 0, 2, 10, 0).getTime())

    expect(groups[1].action).toBe('share')
    expect(groups[1].count).toBe(1)
    expect(groups[1].percentage).toBe(25.0)
    expect(groups[1].firstOccurrence.getTime()).toBe(d(2023, 0, 1, 9, 0).getTime())
    expect(groups[1].lastOccurrence.getTime()).toBe(d(2023, 0, 1, 9, 0).getTime())
  })

  it('returns empty array when user has no activities', () => {
    const activities = [
      { id: '1', user_id: 'other', action: 'x', timestamp: d(2023, 0, 1, 10) }
    ]
    const dash = new ActivityDashboard(activities as any)
    expect(dash.aggregateByAction('u-none')).toEqual([])
  })
})

describe('ActivityDashboard.getTopActions_old', () => {
  it('returns all actions sorted by count, ignoring the limit parameter', () => {
    const u = 'u9'
    const activities = [
      { id: '1', user_id: u, action: 'a', timestamp: d(2023, 0, 1, 9) },
      { id: '2', user_id: u, action: 'a', timestamp: d(2023, 0, 2, 9) },
      { id: '3', user_id: u, action: 'b', timestamp: d(2023, 0, 1, 10) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const top = dash.getTopActions_old(u, 1)
    expect(top.length).toBe(2)
    expect(top[0].action).toBe('a')
    expect(top[0].count).toBe(2)
    expect(top[0].firstOccurrence.getTime()).toBe(d(2023, 0, 1, 9).getTime())
    expect(top[0].lastOccurrence.getTime()).toBe(d(2023, 0, 2, 9).getTime())
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('returns only the top N actions and delegates to aggregateByAction', () => {
    const u = 'u8'
    const activities = [
      { id: '1', user_id: u, action: 'like', timestamp: d(2023, 0, 1, 8, 0) },
      { id: '2', user_id: u, action: 'share', timestamp: d(2023, 0, 1, 9, 0) },
      { id: '3', user_id: u, action: 'like', timestamp: d(2023, 0, 1, 10, 0) },
      { id: '4', user_id: u, action: 'like', timestamp: d(2023, 0, 2, 10, 0) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const spy = jest.spyOn(dash, 'aggregateByAction')
    const top1 = dash.getTopActions(u, 1)
    expect(spy).toHaveBeenCalledWith(u)
    expect(top1.length).toBe(1)
    expect(top1[0].action).toBe('like')
  })

  it('defaults to 5 items when limit not provided', () => {
    const u = 'limit-default'
    const actions = ['a', 'b', 'c', 'd', 'e', 'f', 'g']
    const activities = actions.map((act, idx) => ({ id: String(idx), user_id: u, action: act, timestamp: d(2023, 0, idx + 1) }))
    const dash = new ActivityDashboard(activities as any)
    const top = dash.getTopActions(u)
    expect(top.length).toBe(5)
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 when user has no activity (no summary)', () => {
    const dash = new ActivityDashboard([] as any)
    expect(dash.calculateEngagementScore('none')).toBe(0)
  })

  it('computes score from volume, diversity, and frequency capped and rounded to 2 decimals', () => {
    const u = 'u1'
    const activities = [
      { id: '1', user_id: u, action: 'click', timestamp: d(2023, 0, 1, 10, 0) },
      { id: '2', user_id: u, action: 'click', timestamp: d(2023, 0, 1, 10, 10) },
      { id: '3', user_id: u, action: 'view',  timestamp: d(2023, 0, 1, 10, 20) },
      { id: '4', user_id: u, action: 'click', timestamp: d(2023, 0, 1, 11, 1) }
    ]
    const dash = new ActivityDashboard(activities as any)
    // volume: min(4/100,1)*30 = 1.2
    // diversity: min(2/10,1)*30 = 6
    // frequency: min(4/5,1)*40 = 32
    // total = 39.2
    expect(dash.calculateEngagementScore(u)).toBe(39.2)
  })
})