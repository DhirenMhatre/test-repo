import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function makeActivity(id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity {
  return { id, user_id, action, timestamp: date, metadata }
}

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('calculates totals, uniqueActions, actionsPerDay (exact 24h difference counts as 1 day), mostFrequent and average per session', () => {
    const base = new Date(2023, 0, 1, 0, 0, 0, 0)
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'view', new Date(base.getTime())),
      makeActivity('2', 'u1', 'view', new Date(base.getTime() + 60 * 60 * 1000)),
      makeActivity('3', 'u1', 'login', new Date(base.getTime() + 24 * 60 * 60 * 1000)) // exactly +24h
    ]
    const dashboard = new ActivityDashboard(acts)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    expect(summary!.uniqueActions).toBe(2)
    // last-first = 24h => ceil(1) => 1 day => actionsPerDay = 3 / 1 = 3
    expect(summary!.actionsPerDay).toBe(3)
    expect(summary!.mostFrequentAction).toBe('view')
    // Sessions: gaps are 1h and 23h => one gap > 30min -> 2 sessions; avg = 3/2 = 1.5
    expect(summary!.averageActionsPerSession).toBe(1.5)
  })

  it('averageActionsPerSession splits sessions when gap > 30 minutes', () => {
    const base = new Date(2023, 0, 1, 0, 0, 0, 0)
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(base.getTime() + 0 * 60 * 1000)),
      makeActivity('2', 'u1', 'a', new Date(base.getTime() + 10 * 60 * 1000)),
      makeActivity('3', 'u1', 'a', new Date(base.getTime() + 31 * 60 * 1000)), // > 30 min gap -> new session
      makeActivity('4', 'u1', 'a', new Date(base.getTime() + 40 * 60 * 1000))
    ]
    const dashboard = new ActivityDashboard(acts)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(2)
  })

  it('averageActionsPerSession does not split on exactly 30 minutes gap', () => {
    const base = new Date(2023, 0, 1, 0, 0, 0, 0)
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(base.getTime() + 0 * 60 * 1000)),
      makeActivity('2', 'u1', 'a', new Date(base.getTime() + 30 * 60 * 1000)), // exactly 30 -> same session
      makeActivity('3', 'u1', 'a', new Date(base.getTime() + 60 * 60 * 1000)) // 30 min gap again -> same session
    ]
    const dashboard = new ActivityDashboard(acts)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(3)
  })

  it('handles unsorted input: computes correct daysActive, actionsPerDay, and mostFrequentAction', () => {
    const base = new Date(2023, 0, 1, 0, 0, 0, 0)
    const acts: Activity[] = [
      makeActivity('3', 'u1', 'click', new Date(base.getTime() + 48 * 60 * 60 * 1000)), // Jan 3
      makeActivity('1', 'u1', 'click', new Date(base.getTime() + 0 * 60 * 60 * 1000)),  // Jan 1
      makeActivity('2', 'u1', 'view', new Date(base.getTime() + 24 * 60 * 60 * 1000))   // Jan 2
    ]
    const dashboard = new ActivityDashboard(acts)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    // last-first = 48h => ceil(2) => 2 days; actionsPerDay = 3/2 = 1.5
    expect(summary!.actionsPerDay).toBe(1.5)
    expect(summary!.mostFrequentAction).toBe('click')
    expect(summary!.totalActions).toBe(3)
    expect(summary!.uniqueActions).toBe(2)
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('groups by day and calculates growth rates', () => {
    const base = new Date(2023, 0, 1, 0, 0, 0, 0)
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(base.getTime() + 1 * 60 * 60 * 1000)),  // Jan 1
      makeActivity('2', 'u1', 'a', new Date(base.getTime() + 25 * 60 * 60 * 1000)), // Jan 2
      makeActivity('3', 'u1', 'b', new Date(base.getTime() + 26 * 60 * 60 * 1000)), // Jan 2
      makeActivity('4', 'u1', 'c', new Date(base.getTime() + 27 * 60 * 60 * 1000))  // Jan 2
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-01-01')
    expect(trends[0].count).toBe(1)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].period).toBe('2023-01-02')
    expect(trends[1].count).toBe(3)
    expect(trends[1].growthRate).toBe(200)
  })

  it('groups by hour and formats as "YYYY-MM-DD HH:00"', () => {
    const d1 = new Date(2023, 0, 1, 3, 10, 0, 0) // local time 03:10
    const d2 = new Date(2023, 0, 1, 3, 50, 0, 0) // local time 03:50
    const d3 = new Date(2023, 0, 1, 4, 5, 0, 0)  // local time 04:05
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', d1),
      makeActivity('2', 'u1', 'a', d2),
      makeActivity('3', 'u1', 'b', d3)
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends('u1', 'hour')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-01-01 03:00')
    expect(trends[0].count).toBe(2)
    expect(trends[1].period).toBe('2023-01-01 04:00')
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50)
  })

  it('groups by month and computes negative growth', () => {
    const jan1 = new Date(2023, 0, 10, 10, 0, 0, 0)
    const jan2 = new Date(2023, 0, 20, 10, 0, 0, 0)
    const jan3 = new Date(2023, 0, 25, 10, 0, 0, 0)
    const feb1 = new Date(2023, 1, 5, 9, 0, 0, 0)
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', jan1),
      makeActivity('2', 'u1', 'b', jan2),
      makeActivity('3', 'u1', 'c', jan3),
      makeActivity('4', 'u1', 'a', feb1)
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-01')
    expect(trends[0].count).toBe(3)
    expect(trends[1].period).toBe('2023-02')
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-66.67)
  })

  it('groups by week using "YYYY-W##" and sorts periods', () => {
    const w1 = new Date(2023, 0, 1, 12, 0, 0, 0) // Sunday, should be W01 with this implementation
    const w2 = new Date(2023, 0, 8, 12, 0, 0, 0) // Next Sunday, W02
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', w1),
      makeActivity('2', 'u1', 'b', w2)
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-W01')
    expect(trends[0].count).toBe(1)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].period).toBe('2023-W02')
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(0)
  })

  it('returns empty array when no activities for user', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u2', 'a', new Date(2023, 0, 1, 1, 0, 0, 0))
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('includes activities on the boundaries (inclusive)', () => {
    const start = new Date(2023, 0, 1, 0, 0, 0, 0)
    const middle = new Date(2023, 0, 1, 12, 0, 0, 0)
    const end = new Date(2023, 0, 1, 23, 59, 0, 0)
    const outside = new Date(2023, 0, 2, 0, 0, 0, 0)
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', start),
      makeActivity('2', 'u1', 'b', middle),
      makeActivity('3', 'u1', 'c', end),
      makeActivity('4', 'u1', 'd', outside)
    ]
    const dashboard = new ActivityDashboard(acts)
    const filtered = dashboard.filterByDateRange('u1', start, end)
    expect(filtered.map(a => a.id)).toEqual(['1', '2', '3'])
  })

  it('excludes activities from other users', () => {
    const start = new Date(2023, 0, 1, 0, 0, 0, 0)
    const end = new Date(2023, 0, 2, 0, 0, 0, 0)
    const acts: Activity[] = [
      makeActivity('1', 'u2', 'a', new Date(2023, 0, 1, 1, 0, 0, 0)),
      makeActivity('2', 'u1', 'b', new Date(2023, 0, 1, 2, 0, 0, 0))
    ]
    const dashboard = new ActivityDashboard(acts)
    const filtered = dashboard.filterByDateRange('u1', start, end)
    expect(filtered.length).toBe(1)
    expect(filtered[0].user_id).toBe('u1')
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('aggregates actions with counts, percentages and occurrence dates; sorted by count desc', () => {
    const base = new Date(2023, 0, 1, 0, 0, 0, 0)
    const a1 = new Date(base.getTime() + 0)
    const a2 = new Date(base.getTime() + 1 * 60 * 1000)
    const b1 = new Date(base.getTime() + 2 * 60 * 1000)
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'A', a1),
      makeActivity('2', 'u1', 'A', a2),
      makeActivity('3', 'u1', 'B', b1)
    ]
    const dashboard = new ActivityDashboard(acts)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups.length).toBe(2)
    expect(groups[0].action).toBe('A')
    expect(groups[0].count).toBe(2)
    expect(groups[0].percentage).toBe(66.67)
    expect(groups[0].firstOccurrence.getTime()).toBe(a1.getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(a2.getTime())
    expect(groups[1].action).toBe('B')
    expect(groups[1].count).toBe(1)
    expect(groups[1].percentage).toBe(33.33)
    expect(groups[1].firstOccurrence.getTime()).toBe(b1.getTime())
    expect(groups[1].lastOccurrence.getTime()).toBe(b1.getTime())
  })

  it('returns empty array when no activities for user', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u2', 'A', new Date(2023, 0, 1, 0, 0, 0, 0))
    ]
    const dashboard = new ActivityDashboard(acts)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups).toEqual([])
  })
})

describe('ActivityDashboard - getTopActions_old', () => {
  it('returns all groups and ignores the limit parameter', () => {
    const base = new Date(2023, 0, 1, 0, 0, 0, 0)
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'A', new Date(base.getTime())),
      makeActivity('2', 'u1', 'A', new Date(base.getTime() + 1000)),
      makeActivity('3', 'u1', 'B', new Date(base.getTime() + 2000))
    ]
    const dashboard = new ActivityDashboard(acts)
    const groups = dashboard.getTopActions_old('u1', 1)
    expect(groups.length).toBe(2)
    expect(groups[0].action).toBe('A')
    expect(groups[0].count).toBe(2)
    expect(groups[1].action).toBe('B')
    expect(groups[1].count).toBe(1)
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('respects the limit and returns top actions sorted by count', () => {
    const base = new Date(2023, 0, 1, 0, 0, 0, 0)
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'X', new Date(base.getTime())),
      makeActivity('2', 'u1', 'X', new Date(base.getTime() + 1000)),
      makeActivity('3', 'u1', 'X', new Date(base.getTime() + 2000)),
      makeActivity('4', 'u1', 'Y', new Date(base.getTime() + 3000)),
      makeActivity('5', 'u1', 'Y', new Date(base.getTime() + 4000)),
      makeActivity('6', 'u1', 'Z', new Date(base.getTime() + 5000))
    ]
    const dashboard = new ActivityDashboard(acts)
    const top2 = dashboard.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('X')
    expect(top2[0].count).toBe(3)
    expect(top2[1].action).toBe('Y')
    expect(top2[1].count).toBe(2)
  })

  it('returns empty array when no activities for user', () => {
    const dashboard = new ActivityDashboard([])
    const top = dashboard.getTopActions('u1', 3)
    expect(top).toEqual([])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activity summary', () => {
    const dashboard = new ActivityDashboard([])
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(0)
  })

  it('calculates score with correct weighting and rounding', () => {
    const base = new Date(2023, 0, 1, 0, 0, 0, 0)
    // 5 actions across 26 hours -> daysActive = ceil(26/24)=2 -> actionsPerDay = 2.5
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'A', new Date(base.getTime() + 0 * 60 * 60 * 1000)),  // A
      makeActivity('2', 'u1', 'A', new Date(base.getTime() + 1 * 60 * 60 * 1000)),  // A
      makeActivity('3', 'u1', 'B', new Date(base.getTime() + 2 * 60 * 60 * 1000)),  // B
      makeActivity('4', 'u1', 'B', new Date(base.getTime() + 25 * 60 * 60 * 1000)), // B
      makeActivity('5', 'u1', 'C', new Date(base.getTime() + 26 * 60 * 60 * 1000))  // C
    ]
    const dashboard = new ActivityDashboard(acts)
    const score = dashboard.calculateEngagementScore('u1')
    // volume: (5/100)*30 = 1.5
    // diversity: (3/10)*30 = 9
    // frequency: (2.5/5)*40 = 20
    // total = 30.5
    expect(score).toBe(30.5)
  })
})