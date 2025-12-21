import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

const d = (y: number, m: number, day: number, h: number = 0, mi: number = 0) =>
  new Date(y, m - 1, day, h, mi)

const makeActivity = (id: string, user_id: string, action: string, timestamp: Date): Activity => ({
  id,
  user_id,
  action,
  timestamp
})

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const summary = dash.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, uniqueness, actionsPerDay, mostFrequent, and averageActionsPerSession correctly', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'login', d(2023, 1, 1, 9, 0)),
      makeActivity('2', 'u1', 'click', d(2023, 1, 2, 9, 0)),
      makeActivity('3', 'u1', 'click', d(2023, 1, 2, 10, 0)),
      makeActivity('4', 'u2', 'other', d(2023, 1, 2, 10, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    expect(summary!.uniqueActions).toBe(2)
    expect(summary!.actionsPerDay).toBe(3) // last-first exactly 1 day => daysActive = 1
    expect(summary!.mostFrequentAction).toBe('click')
    expect(summary!.averageActionsPerSession).toBe(1) // three sessions due to >30m gaps, 3/3 = 1.00
  })

  it('resolves ties in mostFrequentAction based on first seen action', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'b', d(2023, 1, 1, 9, 0)),
      makeActivity('2', 'u1', 'a', d(2023, 1, 1, 9, 5)),
      makeActivity('3', 'u1', 'a', d(2023, 1, 1, 9, 10)),
      makeActivity('4', 'u1', 'b', d(2023, 1, 1, 9, 15))
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.mostFrequentAction).toBe('b')
  })

  it('calculates averageActionsPerSession with 30 minute boundary', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'x', d(2023, 1, 1, 10, 0)),
      makeActivity('2', 'u1', 'x', d(2023, 1, 1, 10, 30)), // exactly 30m => same session
      makeActivity('3', 'u1', 'x', d(2023, 1, 1, 11, 1)) // 31m later => new session
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(1.5) // 3 actions / 2 sessions
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })

  it('groups by day and computes growth rates', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 9, 0)),
      makeActivity('2', 'u1', 'b', d(2023, 1, 1, 10, 0)),
      makeActivity('3', 'u1', 'a', d(2023, 1, 2, 11, 0)),
      makeActivity('4', 'u2', 'c', d(2023, 1, 2, 11, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends.length).toBe(2)
    expect(trends[0]).toEqual({ period: '2023-01-01', count: 2, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2023-01-02', count: 1, growthRate: -50 })
  })

  it('groups by hour and sorts chronologically by period string', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 9, 0)),
      makeActivity('2', 'u1', 'a', d(2023, 1, 1, 9, 45)),
      makeActivity('3', 'u1', 'b', d(2023, 1, 1, 10, 10))
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'hour')
    expect(trends).toEqual([
      { period: '2023-01-01 09:00', count: 2, growthRate: 0 },
      { period: '2023-01-01 10:00', count: 1, growthRate: -50 }
    ])
  })

  it('groups by month and computes positive growth', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 15, 9, 0)),
      makeActivity('2', 'u1', 'a', d(2023, 2, 1, 9, 0)),
      makeActivity('3', 'u1', 'b', d(2023, 2, 2, 10, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'month')
    expect(trends).toEqual([
      { period: '2023-01', count: 1, growthRate: 0 },
      { period: '2023-02', count: 2, growthRate: 100 }
    ])
  })

  it('groups by week using the implemented week numbering', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 9, 0)),  // 2023-W01
      makeActivity('2', 'u1', 'b', d(2023, 1, 8, 10, 0)), // 2023-W02
      makeActivity('3', 'u1', 'b', d(2023, 1, 8, 11, 0))  // 2023-W02
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'week')
    expect(trends).toEqual([
      { period: '2023-W01', count: 1, growthRate: 0 },
      { period: '2023-W02', count: 2, growthRate: 100 }
    ])
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('filters activities inclusively by date range', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 9, 0)),
      makeActivity('2', 'u1', 'b', d(2023, 1, 2, 0, 0)),
      makeActivity('3', 'u1', 'c', d(2023, 1, 2, 23, 59)),
      makeActivity('4', 'u1', 'd', d(2023, 1, 3, 0, 0)),
      makeActivity('5', 'u2', 'e', d(2023, 1, 2, 12, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const filtered = dash.filterByDateRange('u1', d(2023, 1, 2, 0, 0), d(2023, 1, 2, 23, 59))
    expect(filtered.map(a => a.id)).toEqual(['2', '3'])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const result = dash.aggregateByAction('u1')
    expect(result).toEqual([])
  })

  it('aggregates counts, percentages, and first/last occurrence; sorted by count desc', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'click', d(2023, 1, 1, 9, 0)),
      makeActivity('2', 'u1', 'view', d(2023, 1, 2, 12, 0)),
      makeActivity('3', 'u1', 'view', d(2023, 1, 2, 13, 0)),
      makeActivity('4', 'u1', 'click', d(2023, 1, 2, 14, 0)),
      makeActivity('5', 'u1', 'click', d(2023, 1, 3, 10, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const groups = dash.aggregateByAction('u1')
    expect(groups.length).toBe(2)
    expect(groups[0].action).toBe('click')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(60)
    expect(groups[0].firstOccurrence.getTime()).toBe(d(2023, 1, 1, 9, 0).getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(d(2023, 1, 3, 10, 0).getTime())
    expect(groups[1].action).toBe('view')
    expect(groups[1].count).toBe(2)
    expect(groups[1].percentage).toBe(40)
  })

  it('rounds percentage to two decimals (e.g., 1/3 -> 33.33)', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 9, 0)),
      makeActivity('2', 'u1', 'b', d(2023, 1, 1, 9, 5)),
      makeActivity('3', 'u1', 'b', d(2023, 1, 1, 9, 10))
    ]
    const dash = new ActivityDashboard(acts)
    const groups = dash.aggregateByAction('u1')
    const aGroup = groups.find(g => g.action === 'a')!
    const bGroup = groups.find(g => g.action === 'b')!
    expect(aGroup.percentage).toBe(33.33)
    expect(bGroup.percentage).toBe(66.67)
  })
})

describe('ActivityDashboard.getTopActions_old', () => {
  it('returns all actions and ignores the limit parameter', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 9, 0)),
      makeActivity('2', 'u1', 'a', d(2023, 1, 1, 10, 0)),
      makeActivity('3', 'u1', 'b', d(2023, 1, 2, 9, 0)),
      makeActivity('4', 'u1', 'c', d(2023, 1, 3, 9, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const result = dash.getTopActions_old('u1', 1)
    expect(result.length).toBe(3)
    const actions = result.map(r => r.action).sort()
    expect(actions).toEqual(['a', 'b', 'c'])
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('applies limit to aggregated actions', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 9, 0)),
      makeActivity('2', 'u1', 'a', d(2023, 1, 1, 10, 0)),
      makeActivity('3', 'u1', 'b', d(2023, 1, 2, 9, 0)),
      makeActivity('4', 'u1', 'b', d(2023, 1, 2, 10, 0)),
      makeActivity('5', 'u1', 'c', d(2023, 1, 3, 9, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const top2 = dash.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('a')
    expect(top2[1].action).toBe('b')
  })

  it('defaults to returning up to 5 actions but not more than available', () => {
    const acts: Activity[] = [
      makeActivity('1', 'u1', 'a', d(2023, 1, 1, 9, 0)),
      makeActivity('2', 'u1', 'b', d(2023, 1, 1, 10, 0)),
      makeActivity('3', 'u1', 'c', d(2023, 1, 2, 9, 0))
    ]
    const dash = new ActivityDashboard(acts)
    const top = dash.getTopActions('u1')
    expect(top.length).toBe(3)
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 when user has no activity summary', () => {
    const dash = new ActivityDashboard([])
    expect(dash.calculateEngagementScore('missing')).toBe(0)
  })

  it('computes score using volume, diversity, and frequency with rounding', () => {
    const acts: Activity[] = []
    for (let i = 0; i < 10; i++) {
      const action = ['a', 'b', 'c'][i % 3]
      // spread across within the day, but ensure first at Jan 1 00:00 and last at Jan 2 00:00
      const ts = i === 0 ? d(2023, 1, 1, 0, 0) : i === 9 ? d(2023, 1, 2, 0, 0) : d(2023, 1, 1, 1, i)
      acts.push(makeActivity(String(i + 1), 'u1', action, ts))
    }
    const dash = new ActivityDashboard(acts)
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(52) // volume: 3, diversity: 9, frequency: 40
  })
})