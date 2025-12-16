import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function createActivity(id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity {
  return { id, user_id, action, timestamp: date, metadata }
}

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const summary = dash.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes summary correctly including totals, unique actions, most frequent, actionsPerDay and average per session', () => {
    const base = new Date(2023, 0, 1, 9, 0, 0)
    const activities: Activity[] = [
      createActivity('1', 'u1', 'view', new Date(2023, 0, 1, 9, 0, 0)),
      createActivity('2', 'u1', 'click', new Date(2023, 0, 1, 9, 10, 0)),
      createActivity('3', 'u1', 'view', new Date(2023, 0, 1, 9, 20, 0)),
      // gap > 30 minutes starts new session
      createActivity('4', 'u1', 'purchase', new Date(2023, 0, 1, 10, 5, 0)),
      createActivity('5', 'u1', 'view', new Date(2023, 0, 1, 10, 15, 0)),
      // activities for other user should be ignored
      createActivity('6', 'u2', 'view', new Date(2023, 0, 1, 11, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(5)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.mostFrequentAction).toBe('view')
    // all within same day -> daysActive = 1
    expect(summary!.actionsPerDay).toBe(5)
    // 5 actions across 2 sessions => 2.5
    expect(summary!.averageActionsPerSession).toBe(2.5)
  })

  it('calculates actionsPerDay across multiple days with rounding', () => {
    const activities: Activity[] = [
      // First activity at Jan 1 00:00
      createActivity('1', 'u1', 'a', new Date(2023, 0, 1, 0, 0, 0)),
      createActivity('2', 'u1', 'b', new Date(2023, 0, 1, 1, 0, 0)),
      createActivity('3', 'u1', 'c', new Date(2023, 0, 2, 2, 0, 0)),
      createActivity('4', 'u1', 'a', new Date(2023, 0, 2, 3, 0, 0)),
      createActivity('5', 'u1', 'b', new Date(2023, 0, 3, 4, 0, 0)),
      createActivity('6', 'u1', 'c', new Date(2023, 0, 3, 5, 0, 0)),
      createActivity('7', 'u1', 'a', new Date(2023, 0, 3, 6, 0, 0)),
      // Last activity just over 3 days after first -> ceil to 4 days active
      createActivity('8', 'u1', 'd', new Date(2023, 0, 4, 0, 1, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    // daysActive = ceil((Jan4 00:01 - Jan1 00:00)/1d) = 4
    // totalActions = 8 => 8 / 4 = 2.00
    expect(summary!.actionsPerDay).toBe(2)
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })

  it('groups by day, sorts periods and computes growthRate', () => {
    const activities: Activity[] = [
      // Day 1 -> 2 actions
      createActivity('1', 'u1', 'x', new Date(2023, 1, 1, 9, 0, 0)),
      createActivity('2', 'u1', 'y', new Date(2023, 1, 1, 10, 0, 0)),
      // Day 2 -> 4 actions
      createActivity('3', 'u1', 'x', new Date(2023, 1, 2, 9, 0, 0)),
      createActivity('4', 'u1', 'y', new Date(2023, 1, 2, 10, 0, 0)),
      createActivity('5', 'u1', 'z', new Date(2023, 1, 2, 11, 0, 0)),
      createActivity('6', 'u1', 'x', new Date(2023, 1, 2, 12, 0, 0)),
      // Day 3 -> 1 action
      createActivity('7', 'u1', 'x', new Date(2023, 1, 3, 13, 0, 0)),
      // Other user ignored
      createActivity('8', 'u2', 'x', new Date(2023, 1, 2, 9, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends.length).toBe(3)
    expect(trends[0]).toMatchObject({ period: '2023-02-01', count: 2, growthRate: 0 })
    expect(trends[1]).toMatchObject({ period: '2023-02-02', count: 4, growthRate: 100 })
    expect(trends[2]).toMatchObject({ period: '2023-02-03', count: 1, growthRate: -75 })
  })

  it('groups by hour and formats "YYYY-MM-DD HH:00"', () => {
    const activities: Activity[] = [
      createActivity('1', 'u1', 'x', new Date(2023, 4, 15, 14, 15, 0)),
      createActivity('2', 'u1', 'y', new Date(2023, 4, 15, 15, 5, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'hour')
    expect(trends.length).toBe(2)
    expect(trends[0]).toMatchObject({ period: '2023-05-15 14:00', count: 1, growthRate: 0 })
    expect(trends[1]).toMatchObject({ period: '2023-05-15 15:00', count: 1, growthRate: 0 })
  })

  it('groups by week using getWeekNumber and key "YYYY-WNN"', () => {
    const activities: Activity[] = [
      // 2023-01-01 -> week 1
      createActivity('1', 'u1', 'x', new Date(2023, 0, 1, 10, 0, 0)),
      // 2023-01-08 -> week 2
      createActivity('2', 'u1', 'y', new Date(2023, 0, 8, 10, 0, 0)),
      createActivity('3', 'u1', 'z', new Date(2023, 0, 8, 11, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(2)
    expect(trends[0]).toMatchObject({ period: '2023-W01', count: 1, growthRate: 0 })
    expect(trends[1]).toMatchObject({ period: '2023-W02', count: 2, growthRate: 100 })
  })

  it('groups by month and formats "YYYY-MM"', () => {
    const activities: Activity[] = [
      createActivity('1', 'u1', 'x', new Date(2023, 0, 10, 0, 0, 0)), // Jan
      createActivity('2', 'u1', 'y', new Date(2023, 0, 15, 0, 0, 0)), // Jan
      createActivity('3', 'u1', 'z', new Date(2023, 1, 1, 0, 0, 0))   // Feb
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'month')
    expect(trends.length).toBe(2)
    expect(trends[0]).toMatchObject({ period: '2023-01', count: 2, growthRate: 0 })
    expect(trends[1]).toMatchObject({ period: '2023-02', count: 1, growthRate: -50 })
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('returns only activities in inclusive range for the user', () => {
    const start = new Date(2023, 2, 1, 10, 0, 0)
    const mid = new Date(2023, 2, 1, 12, 0, 0)
    const end = new Date(2023, 2, 1, 14, 0, 0)
    const outside = new Date(2023, 2, 1, 15, 0, 0)
    const activities: Activity[] = [
      createActivity('1', 'u1', 'a', start),
      createActivity('2', 'u1', 'b', mid),
      createActivity('3', 'u1', 'c', end),
      createActivity('4', 'u1', 'd', outside),
      createActivity('5', 'u2', 'e', mid)
    ]
    const dash = new ActivityDashboard(activities)
    const filtered = dash.filterByDateRange('u1', start, end)
    expect(filtered.map(a => a.id)).toEqual(['1', '2', '3'])
  })

  it('excludes activities of other users even within range', () => {
    const start = new Date(2023, 3, 1, 9, 0, 0)
    const end = new Date(2023, 3, 1, 11, 0, 0)
    const activities: Activity[] = [
      createActivity('1', 'u2', 'a', new Date(2023, 3, 1, 10, 0, 0)),
      createActivity('2', 'u1', 'b', new Date(2023, 3, 1, 10, 30, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const filtered = dash.filterByDateRange('u1', start, end)
    expect(filtered.length).toBe(1)
    expect(filtered[0].id).toBe('2')
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('aggregates counts, percentages, and occurrences sorted by count', () => {
    const activities: Activity[] = [
      // A: 3
      createActivity('1', 'u1', 'A', new Date(2023, 5, 1, 9, 0, 0)),
      createActivity('2', 'u1', 'A', new Date(2023, 5, 1, 10, 0, 0)),
      createActivity('3', 'u1', 'A', new Date(2023, 5, 1, 11, 0, 0)),
      // B: 2
      createActivity('4', 'u1', 'B', new Date(2023, 5, 2, 9, 0, 0)),
      createActivity('5', 'u1', 'B', new Date(2023, 5, 2, 12, 0, 0)),
      // C: 1
      createActivity('6', 'u1', 'C', new Date(2023, 5, 3, 9, 0, 0)),
      // Other user ignored
      createActivity('7', 'u2', 'A', new Date(2023, 5, 1, 9, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.aggregateByAction('u1')
    expect(groups.length).toBe(3)
    // Sorted by count desc: A, B, C
    expect(groups[0].action).toBe('A')
    expect(groups[0].count).toBe(3)
    expect(groups[1].action).toBe('B')
    expect(groups[1].count).toBe(2)
    expect(groups[2].action).toBe('C')
    expect(groups[2].count).toBe(1)
    // Percentages: 3/6=50.00, 2/6=33.33, 1/6=16.67
    expect(groups[0].percentage).toBeCloseTo(50.0, 2)
    expect(groups[1].percentage).toBeCloseTo(33.33, 2)
    expect(groups[2].percentage).toBeCloseTo(16.67, 2)
    // First/last occurrence for A
    expect(groups[0].firstOccurrence.getTime()).toBe(new Date(2023, 5, 1, 9, 0, 0).getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(new Date(2023, 5, 1, 11, 0, 0).getTime())
  })

  it('returns empty array when no activities for user', () => {
    const activities: Activity[] = [
      createActivity('1', 'u2', 'X', new Date(2023, 0, 1))
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.aggregateByAction('u1')
    expect(groups).toEqual([])
  })
})

describe('ActivityDashboard - getTopActions_old', () => {
  it('returns all action groups and ignores the limit parameter', () => {
    const activities: Activity[] = [
      // X:3, Y:2, Z:1, W:1
      createActivity('1', 'u1', 'X', new Date(2023, 7, 1, 9, 0, 0)),
      createActivity('2', 'u1', 'X', new Date(2023, 7, 1, 10, 0, 0)),
      createActivity('3', 'u1', 'X', new Date(2023, 7, 1, 11, 0, 0)),
      createActivity('4', 'u1', 'Y', new Date(2023, 7, 2, 9, 0, 0)),
      createActivity('5', 'u1', 'Y', new Date(2023, 7, 2, 10, 0, 0)),
      createActivity('6', 'u1', 'Z', new Date(2023, 7, 3, 9, 0, 0)),
      createActivity('7', 'u1', 'W', new Date(2023, 7, 4, 9, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.getTopActions_old('u1', 2)
    expect(groups.length).toBe(4)
  })

  it('sorts by count desc and calculates percentages', () => {
    const activities: Activity[] = [
      createActivity('1', 'u1', 'X', new Date(2023, 8, 1, 9, 0, 0)),
      createActivity('2', 'u1', 'X', new Date(2023, 8, 1, 10, 0, 0)),
      createActivity('3', 'u1', 'Y', new Date(2023, 8, 2, 9, 0, 0)),
      createActivity('4', 'u1', 'Z', new Date(2023, 8, 3, 9, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.getTopActions_old('u1')
    expect(groups[0].action).toBe('X')
    expect(groups[0].count).toBe(2)
    expect(groups[0].percentage).toBeCloseTo(50, 2) // 2/4
    // Check first/last occurrence for X
    expect(groups[0].firstOccurrence.getTime()).toBe(new Date(2023, 8, 1, 9, 0, 0).getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(new Date(2023, 8, 1, 10, 0, 0).getTime())
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('applies limit and returns top actions from aggregateByAction', () => {
    const activities: Activity[] = [
      // A:3, B:2, C:1, D:1
      createActivity('1', 'u1', 'A', new Date(2023, 9, 1, 9, 0, 0)),
      createActivity('2', 'u1', 'A', new Date(2023, 9, 1, 9, 5, 0)),
      createActivity('3', 'u1', 'A', new Date(2023, 9, 1, 9, 10, 0)),
      createActivity('4', 'u1', 'B', new Date(2023, 9, 1, 10, 0, 0)),
      createActivity('5', 'u1', 'B', new Date(2023, 9, 1, 10, 10, 0)),
      createActivity('6', 'u1', 'C', new Date(2023, 9, 1, 11, 0, 0)),
      createActivity('7', 'u1', 'D', new Date(2023, 9, 1, 12, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const top2 = dash.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('A')
    expect(top2[1].action).toBe('B')
  })

  it('uses default limit 5 and returns all when fewer are available', () => {
    const activities: Activity[] = [
      createActivity('1', 'u1', 'A', new Date(2023, 10, 1, 9, 0, 0)),
      createActivity('2', 'u1', 'B', new Date(2023, 10, 1, 10, 0, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const top = dash.getTopActions('u1')
    expect(top.length).toBe(2)
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activities', () => {
    const dash = new ActivityDashboard([])
    expect(dash.calculateEngagementScore('u1')).toBe(0)
  })

  it('calculates combined score with rounding to 2 decimals', () => {
    // 10 actions, 5 unique, span 4 days -> actionsPerDay = 2.5
    // volumeScore = min(10/100,1)*30 = 3
    // diversityScore = min(5/10,1)*30 = 15
    // frequencyScore = min(2.5/5,1)*40 = 20
    // total = 38.00
    const dates: Date[] = [
      new Date(2023, 0, 1, 0, 0, 0),
      new Date(2023, 0, 1, 1, 0, 0),
      new Date(2023, 0, 1, 2, 0, 0),
      new Date(2023, 0, 2, 9, 0, 0),
      new Date(2023, 0, 2, 10, 0, 0),
      new Date(2023, 0, 2, 11, 0, 0),
      new Date(2023, 0, 3, 12, 0, 0),
      new Date(2023, 0, 3, 13, 0, 0),
      new Date(2023, 0, 3, 14, 0, 0),
      // last slightly over 3 days from first => daysActive = 4
      new Date(2023, 0, 4, 0, 1, 0)
    ]
    const actions = ['a1', 'a2', 'a3', 'a4', 'a5']
    const activities: Activity[] = dates.map((d, i) =>
      createActivity(String(i + 1), 'u1', actions[i % actions.length], d)
    )
    const dash = new ActivityDashboard(activities)
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(38)
  })
})