import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

type Act = {
  id: string
  user_id: string
  action: string
  timestamp: Date
  metadata?: Record<string, any>
}

const mkAct = (id: string, user_id: string, action: string, y: number, m0: number, d: number, hh: number, mm: number): Act => ({
  id,
  user_id,
  action,
  timestamp: new Date(y, m0, d, hh, mm, 0, 0)
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const summary = dash.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes correct summary metrics across multiple days and sessions', () => {
    const activities: Act[] = [
      mkAct('1', 'u1', 'view', 2023, 0, 1, 10, 0),
      mkAct('2', 'u1', 'click', 2023, 0, 1, 10, 10),
      mkAct('3', 'u1', 'view', 2023, 0, 1, 10, 20),
      mkAct('4', 'u1', 'purchase', 2023, 0, 1, 10, 50), // +30 minutes (not a new session)
      mkAct('5', 'u1', 'view', 2023, 0, 1, 11, 0),
      mkAct('6', 'u1', 'share', 2023, 0, 1, 12, 0), // +60 minutes (new session)
      mkAct('7', 'u1', 'view', 2023, 0, 3, 9, 0),   // new session
      mkAct('8', 'u1', 'click', 2023, 0, 5, 9, 0),  // new session
      // other user's activities should be ignored
      mkAct('9', 'u2', 'view', 2023, 0, 1, 10, 0)
    ]
    const dash = new ActivityDashboard(activities)

    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(8)
    expect(summary!.uniqueActions).toBe(4)
    expect(summary!.actionsPerDay).toBe(2) // 8 actions / 4 days = 2.00
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.averageActionsPerSession).toBe(2) // 8 actions across 4 sessions = 2.00
  })

  it('treats multiple actions in same day as 1 day of activity', () => {
    const acts: Act[] = [
      mkAct('1', 'u1', 'view', 2023, 0, 2, 9, 0),
      mkAct('2', 'u1', 'view', 2023, 0, 2, 10, 0),
      mkAct('3', 'u1', 'click', 2023, 0, 2, 11, 0)
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    expect(summary!.actionsPerDay).toBe(3) // same day -> daysActive = 1
  })

  it('does not split session when gap is exactly 30 minutes', () => {
    const acts: Act[] = [
      mkAct('1', 'u1', 'view', 2023, 0, 2, 10, 0),
      mkAct('2', 'u1', 'view', 2023, 0, 2, 10, 30) // exactly 30 minutes later
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(2) // both in same session
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('filters by user and inclusive date range', () => {
    const acts: Act[] = [
      mkAct('1', 'u1', 'view', 2023, 0, 1, 9, 0),
      mkAct('2', 'u1', 'click', 2023, 0, 3, 9, 0),
      mkAct('3', 'u1', 'view', 2023, 0, 5, 9, 0),
      mkAct('4', 'u2', 'view', 2023, 0, 3, 9, 0)
    ]
    const dash = new ActivityDashboard(acts)
    const start = new Date(2023, 0, 3, 0, 0, 0, 0)
    const end = new Date(2023, 0, 5, 9, 0, 0, 0)
    const filtered = dash.filterByDateRange('u1', start, end)
    const ids = filtered.map(a => a.id).sort()
    expect(ids).toEqual(['2', '3'])
  })

  it('returns empty when nothing matches', () => {
    const dash = new ActivityDashboard([
      mkAct('1', 'u1', 'view', 2023, 0, 1, 0, 0)
    ])
    const res = dash.filterByDateRange('u1', new Date(2023, 1, 1), new Date(2023, 1, 2))
    expect(res).toEqual([])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('aggregates actions with counts, percentages and occurrence bounds', () => {
    const v1 = mkAct('1', 'u1', 'view', 2023, 0, 1, 10, 0)
    const c1 = mkAct('2', 'u1', 'click', 2023, 0, 1, 10, 10)
    const v2 = mkAct('3', 'u1', 'view', 2023, 0, 1, 10, 20)
    const p1 = mkAct('4', 'u1', 'purchase', 2023, 0, 1, 10, 50)
    const v3 = mkAct('5', 'u1', 'view', 2023, 0, 1, 11, 0)
    const s1 = mkAct('6', 'u1', 'share', 2023, 0, 1, 12, 0)
    const v4 = mkAct('7', 'u1', 'view', 2023, 0, 3, 9, 0)
    const c2 = mkAct('8', 'u1', 'click', 2023, 0, 5, 9, 0)
    const acts: Act[] = [v1, c1, v2, p1, v3, s1, v4, c2]
    const dash = new ActivityDashboard(acts)
    const groups = dash.aggregateByAction('u1')

    // Should be sorted by count desc: view (4), click (2), purchase (1), share (1)
    expect(groups.map(g => [g.action, g.count])).toEqual([
      ['view', 4], ['click', 2], ['purchase', 1], ['share', 1]
    ])

    const total = acts.length
    const viewGroup = groups.find(g => g.action === 'view')!
    expect(viewGroup.percentage).toBeCloseTo(parseFloat(((4 / total) * 100).toFixed(2)))
    expect(viewGroup.firstOccurrence.getTime()).toBe(v1.timestamp.getTime())
    expect(viewGroup.lastOccurrence.getTime()).toBe(v4.timestamp.getTime())

    const clickGroup = groups.find(g => g.action === 'click')!
    expect(clickGroup.count).toBe(2)
    expect(clickGroup.firstOccurrence.getTime()).toBe(c1.timestamp.getTime())
    expect(clickGroup.lastOccurrence.getTime()).toBe(c2.timestamp.getTime())
  })

  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([
      mkAct('1', 'u2', 'view', 2023, 0, 1, 10, 0)
    ])
    const groups = dash.aggregateByAction('u1')
    expect(groups).toEqual([])
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('returns top N actions by count', () => {
    const acts: Act[] = [
      mkAct('1', 'u1', 'a', 2023, 0, 1, 9, 0),
      mkAct('2', 'u1', 'b', 2023, 0, 1, 9, 1),
      mkAct('3', 'u1', 'a', 2023, 0, 1, 9, 2),
      mkAct('4', 'u1', 'c', 2023, 0, 1, 9, 3),
      mkAct('5', 'u1', 'd', 2023, 0, 1, 9, 4),
      mkAct('6', 'u1', 'e', 2023, 0, 1, 9, 5),
      mkAct('7', 'u1', 'f', 2023, 0, 1, 9, 6)
    ]
    const dash = new ActivityDashboard(acts)
    const top2 = dash.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('a') // most frequent
    expect(top2[0].count).toBe(2)
  })

  it('returns all when limit exceeds available groups', () => {
    const acts: Act[] = [
      mkAct('1', 'u1', 'x', 2023, 0, 1, 0, 0),
      mkAct('2', 'u1', 'y', 2023, 0, 1, 0, 1)
    ]
    const dash = new ActivityDashboard(acts)
    const top = dash.getTopActions('u1', 10)
    expect(top.map(t => t.action).sort()).toEqual(['x', 'y'])
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 when no activity summary exists', () => {
    const dash = new ActivityDashboard([])
    expect(dash.calculateEngagementScore('u1')).toBe(0)
  })

  it('computes weighted engagement score with rounding', () => {
    const acts: Act[] = [
      mkAct('1', 'u1', 'view', 2023, 0, 1, 10, 0),
      mkAct('2', 'u1', 'click', 2023, 0, 1, 10, 10),
      mkAct('3', 'u1', 'view', 2023, 0, 1, 10, 20),
      mkAct('4', 'u1', 'purchase', 2023, 0, 1, 10, 50),
      mkAct('5', 'u1', 'view', 2023, 0, 1, 11, 0),
      mkAct('6', 'u1', 'share', 2023, 0, 1, 12, 0),
      mkAct('7', 'u1', 'view', 2023, 0, 3, 9, 0),
      mkAct('8', 'u1', 'click', 2023, 0, 5, 9, 0)
    ]
    const dash = new ActivityDashboard(acts)
    // volume: (8/100)*30 = 2.4, diversity: (4/10)*30 = 12, frequency: (2/5)*40 = 16 => total 30.4
    expect(dash.calculateEngagementScore('u1')).toBe(30.4)
  })
})

describe('ActivityDashboard.getActivityTrends - day', () => {
  it('groups by day with sorted periods and growth rates', () => {
    const acts: Act[] = [
      // Day 1: 1 action
      mkAct('1', 'u1', 'view', 2023, 0, 1, 10, 0),
      // Day 2: 3 actions
      mkAct('2', 'u1', 'view', 2023, 0, 2, 9, 0),
      mkAct('3', 'u1', 'click', 2023, 0, 2, 10, 0),
      mkAct('4', 'u1', 'view', 2023, 0, 2, 11, 0),
      // Day 3: 4 actions
      mkAct('5', 'u1', 'view', 2023, 0, 3, 9, 0),
      mkAct('6', 'u1', 'click', 2023, 0, 3, 10, 0),
      mkAct('7', 'u1', 'view', 2023, 0, 3, 11, 0),
      mkAct('8', 'u1', 'share', 2023, 0, 3, 12, 0),
      // another user on day 2
      mkAct('9', 'u2', 'view', 2023, 0, 2, 9, 0)
    ]
    const dash = new ActivityDashboard(acts)
    const trend = dash.getActivityTrends('u1', 'day')
    expect(trend.map(t => t.period)).toEqual(['2023-01-01', '2023-01-02', '2023-01-03'])
    expect(trend.map(t => t.count)).toEqual([1, 3, 4])
    // growth: first 0, second ((3-1)/1)*100=200, third ((4-3)/3)*100=33.33
    expect(trend.map(t => t.growthRate)).toEqual([0, 200, 33.33])
  })

  it('returns empty array for user with no activities', () => {
    const dash = new ActivityDashboard([
      mkAct('1', 'u2', 'x', 2023, 0, 1, 0, 0)
    ])
    expect(dash.getActivityTrends('u1', 'day')).toEqual([])
  })
})

describe('ActivityDashboard.getActivityTrends - hour', () => {
  it('groups by hour and computes negative growth correctly', () => {
    const acts: Act[] = [
      mkAct('1', 'u1', 'view', 2023, 0, 1, 10, 0),
      mkAct('2', 'u1', 'click', 2023, 0, 1, 10, 15),
      mkAct('3', 'u1', 'view', 2023, 0, 1, 11, 0)
    ]
    const dash = new ActivityDashboard(acts)
    const trend = dash.getActivityTrends('u1', 'hour')
    expect(trend.map(t => t.period)).toEqual(['2023-01-01 10:00', '2023-01-01 11:00'])
    expect(trend.map(t => t.count)).toEqual([2, 1])
    expect(trend.map(t => t.growthRate)).toEqual([0, -50]) // ((1-2)/2)*100 = -50.00
  })
})

describe('ActivityDashboard.getActivityTrends - week', () => {
  it('groups by week using class-defined week number', () => {
    const acts: Act[] = [
      mkAct('1', 'u1', 'view', 2023, 0, 1, 10, 0), // Week 1 (per implementation)
      mkAct('2', 'u1', 'view', 2023, 0, 8, 10, 0)  // Week 2
    ]
    const dash = new ActivityDashboard(acts)
    const trend = dash.getActivityTrends('u1', 'week')
    expect(trend.map(t => t.period)).toEqual(['2023-W01', '2023-W02'])
    expect(trend.map(t => t.count)).toEqual([1, 1])
    expect(trend.map(t => t.growthRate)).toEqual([0, 0]) // prevCount=1 => (1-1)/1=0
  })
})

describe('ActivityDashboard.getActivityTrends - month', () => {
  it('groups by month and sorts lexicographically by period key', () => {
    const acts: Act[] = [
      mkAct('1', 'u1', 'view', 2023, 0, 15, 9, 0), // Jan
      mkAct('2', 'u1', 'click', 2023, 0, 20, 9, 0), // Jan
      mkAct('3', 'u1', 'view', 2023, 1, 1, 9, 0)    // Feb
    ]
    const dash = new ActivityDashboard(acts)
    const trend = dash.getActivityTrends('u1', 'month')
    expect(trend.map(t => t.period)).toEqual(['2023-01', '2023-02'])
    expect(trend.map(t => t.count)).toEqual([2, 1])
    expect(trend.map(t => t.growthRate)).toEqual([0, -50]) // ((1-2)/2)*100 = -50.00
  })
})

describe('ActivityDashboard.getActivityTrends - default period type', () => {
  it('defaults to day when periodType is omitted', () => {
    const acts: Act[] = [
      mkAct('1', 'u1', 'a', 2023, 4, 10, 9, 0),
      mkAct('2', 'u1', 'a', 2023, 4, 10, 10, 0),
      mkAct('3', 'u1', 'a', 2023, 4, 11, 9, 0)
    ]
    const dash = new ActivityDashboard(acts)
    const trend = dash.getActivityTrends('u1')
    expect(trend.map(t => t.period)).toEqual(['2023-05-10', '2023-05-11'])
    expect(trend.map(t => t.count)).toEqual([2, 1])
  })
})