import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

const d = (y: number, m: number, day: number, h = 0, min = 0) => new Date(y, m - 1, day, h, min, 0, 0)
const pad = (n: number) => String(n).padStart(2, '0')
const getWeekNumberLikeSource = (date: Date): number => {
  const firstDayOfYear = new Date(date.getFullYear(), 0, 1)
  const pastDaysOfYear = (date.getTime() - firstDayOfYear.getTime()) / 86400000
  return Math.ceil((pastDaysOfYear + firstDayOfYear.getDay() + 1) / 7)
}
const periodKeyLikeSource = (date: Date, periodType: 'hour' | 'day' | 'week' | 'month' | string): string => {
  const year = date.getFullYear()
  const month = pad(date.getMonth() + 1)
  const day = pad(date.getDate())
  const hour = pad(date.getHours())
  switch (periodType) {
    case 'hour':
      return `${year}-${month}-${day} ${hour}:00`
    case 'day':
      return `${year}-${month}-${day}`
    case 'week': {
      const weekNumber = getWeekNumberLikeSource(date)
      return `${year}-W${pad(weekNumber)}`
    }
    case 'month':
      return `${year}-${month}`
    default:
      return `${year}-${month}-${day}`
  }
}

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when no activities for the user', () => {
    const dash = new ActivityDashboard([])
    const summary = dash.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, actions per day (rounded), most frequent and avg per session', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2024, 1, 1, 10, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 10, 10) },
      { id: '3', user_id: 'u1', action: 'login', timestamp: d(2024, 1, 1, 10, 50) }, // new session
      { id: '4', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 12, 0) }, // new session
      { id: '5', user_id: 'u1', action: 'click', timestamp: d(2024, 1, 2, 9, 0) } // new session
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')!
    expect(summary.totalActions).toBe(5)
    expect(summary.uniqueActions).toBe(3)
    expect(summary.actionsPerDay).toBe(5) // within 1 day window due to ceil and max(,1)
    expect(summary.mostFrequentAction).toBe('login') // tie broken by insertion order
    expect(summary.averageActionsPerSession).toBe(1.25) // 5 actions / 4 sessions
  })

  it('rounds actionsPerDay to 2 decimals using ceil daysActive', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u2', action: 'a', timestamp: d(2024, 1, 1, 10, 0) },
      { id: '2', user_id: 'u2', action: 'b', timestamp: d(2024, 1, 4, 10, 0) } // exactly 3 days difference
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u2')!
    expect(summary.totalActions).toBe(2)
    expect(summary.actionsPerDay).toBe(0.67) // 2 / 3 = 0.666..., rounded to 0.67
  })

  it('single activity results in actionsPerDay 1 and averageActionsPerSession 1', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'solo', action: 'like', timestamp: d(2024, 5, 5, 12, 0) }
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('solo')!
    expect(summary.totalActions).toBe(1)
    expect(summary.actionsPerDay).toBe(1)
    expect(summary.mostFrequentAction).toBe('like')
    expect(summary.averageActionsPerSession).toBe(1)
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('returns activities within inclusive date range', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 2, 12, 0) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d(2024, 1, 3, 18, 0) }
    ]
    const dash = new ActivityDashboard(activities)
    const res = dash.filterByDateRange('u1', d(2024, 1, 2, 0, 0), d(2024, 1, 2, 23, 59))
    expect(res).toHaveLength(1)
    expect(res[0].id).toBe('2')
  })

  it('returns empty array when no activities fall in the range or user mismatch', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1) }
    ]
    const dash = new ActivityDashboard(activities)
    const noneForUser = dash.filterByDateRange('u2', d(2024, 1, 1), d(2024, 1, 2))
    const noneForRange = dash.filterByDateRange('u1', d(2024, 2, 1), d(2024, 2, 2))
    expect(noneForUser).toEqual([])
    expect(noneForRange).toEqual([])
  })
})

describe('ActivityDashboard - aggregateByAction and top actions', () => {
  it('aggregates by action with counts, percentages, and first/last occurrences; sorted by count desc', () => {
    const a1 = d(2024, 1, 1, 9, 0)
    const a2 = d(2024, 1, 1, 10, 0)
    const a3 = d(2024, 1, 2, 9, 0)
    const a4 = d(2024, 1, 3, 9, 0)
    const a5 = d(2024, 1, 3, 10, 0)
    const activities: Activity[] = [
      { id: '1', user_id: 'uA', action: 'login', timestamp: a1 },
      { id: '2', user_id: 'uA', action: 'login', timestamp: a2 },
      { id: '3', user_id: 'uA', action: 'login', timestamp: a3 },
      { id: '4', user_id: 'uA', action: 'view', timestamp: a4 },
      { id: '5', user_id: 'uA', action: 'click', timestamp: a5 }
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.aggregateByAction('uA')
    expect(groups[0].action).toBe('login')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(60)
    expect(groups[0].firstOccurrence.getTime()).toBe(a1.getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(a3.getTime())

    const totalCount = groups.reduce((sum, g) => sum + g.count, 0)
    expect(totalCount).toBe(5)
  })

  it('returns empty array when aggregating a user with no activities', () => {
    const dash = new ActivityDashboard([])
    expect(dash.aggregateByAction('uX')).toEqual([])
  })

  it('getTopActions_old ignores the limit argument and returns all sorted groups', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'uA', action: 'a', timestamp: d(2024, 1, 1) },
      { id: '2', user_id: 'uA', action: 'a', timestamp: d(2024, 1, 2) },
      { id: '3', user_id: 'uA', action: 'b', timestamp: d(2024, 1, 3) },
      { id: '4', user_id: 'uA', action: 'c', timestamp: d(2024, 1, 4) }
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.getTopActions_old('uA', 1)
    expect(groups).toHaveLength(3)
    expect(groups[0].action).toBe('a')
    expect(groups[0].count).toBe(2)
  })

  it('getTopActions respects the limit and returns sorted action groups', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'uA', action: 'x', timestamp: d(2024, 1, 1) },
      { id: '2', user_id: 'uA', action: 'x', timestamp: d(2024, 1, 2) },
      { id: '3', user_id: 'uA', action: 'y', timestamp: d(2024, 1, 3) },
      { id: '4', user_id: 'uA', action: 'z', timestamp: d(2024, 1, 4) }
    ]
    const dash = new ActivityDashboard(activities)
    const top2 = dash.getTopActions('uA', 2)
    expect(top2).toHaveLength(2)
    expect(top2[0].action).toBe('x')
    expect(top2[0].count).toBe(2)
  })

  it('percentage values are rounded to two decimals', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'uA', action: 'onlyOnce', timestamp: d(2024, 1, 1) },
      { id: '2', user_id: 'uA', action: 'other', timestamp: d(2024, 1, 2) },
      { id: '3', user_id: 'uA', action: 'other', timestamp: d(2024, 1, 3) }
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.aggregateByAction('uA')
    const one = groups.find(g => g.action === 'onlyOnce')!
    expect(one.count).toBe(1)
    expect(one.percentage).toBe(33.33)
  })

  it('getTopActions returns empty list for user without activities', () => {
    const dash = new ActivityDashboard([])
    const top = dash.getTopActions('nobody', 3)
    expect(top).toEqual([])
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns [] when there are no activities for the user', () => {
    const dash = new ActivityDashboard([])
    expect(dash.getActivityTrends('u1', 'day')).toEqual([])
  })

  it('groups by day with correct growth rates', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 1, 10, 0) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d(2024, 1, 2, 9, 0) }
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'day')
    const p1 = periodKeyLikeSource(d(2024, 1, 1, 9, 0), 'day')
    const p2 = periodKeyLikeSource(d(2024, 1, 2, 9, 0), 'day')

    expect(trends).toHaveLength(2)
    expect(trends[0]).toEqual({ period: p1, count: 2, growthRate: 0 })
    expect(trends[1]).toEqual({ period: p2, count: 1, growthRate: -50 })
  })

  it('groups by hour and sorts periods', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 10, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 1, 10, 10) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d(2024, 1, 1, 11, 0) }
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'hour')
    const p10 = periodKeyLikeSource(d(2024, 1, 1, 10, 0), 'hour')
    const p11 = periodKeyLikeSource(d(2024, 1, 1, 11, 0), 'hour')

    expect(trends).toHaveLength(2)
    expect(trends[0]).toEqual({ period: p10, count: 2, growthRate: 0 })
    expect(trends[1]).toEqual({ period: p11, count: 1, growthRate: -50 })
  })

  it('groups by week with expected week keys and growth rates', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 12, 0) }, // Week 01
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 8, 12, 0) }  // Week 02
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'week')
    const p1 = periodKeyLikeSource(d(2024, 1, 1, 12, 0), 'week')
    const p2 = periodKeyLikeSource(d(2024, 1, 8, 12, 0), 'week')

    expect(trends).toHaveLength(2)
    expect(trends[0]).toEqual({ period: p1, count: 1, growthRate: 0 })
    expect(trends[1]).toEqual({ period: p2, count: 1, growthRate: 0 })
  })

  it('groups by month with growth rate calculation', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 15, 12, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 2, 1, 9, 0) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d(2024, 2, 2, 9, 0) }
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'month')
    const jan = periodKeyLikeSource(d(2024, 1, 15, 12, 0), 'month')
    const feb = periodKeyLikeSource(d(2024, 2, 2, 9, 0), 'month')

    expect(trends).toHaveLength(2)
    expect(trends[0]).toEqual({ period: jan, count: 1, growthRate: 0 })
    expect(trends[1]).toEqual({ period: feb, count: 2, growthRate: 100 })
  })

  it('defaults to day period when not specified', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 3, 3, 10, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 3, 3, 11, 0) }
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1')
    const p = periodKeyLikeSource(d(2024, 3, 3, 10, 0), 'day')
    expect(trends).toEqual([{ period: p, count: 2, growthRate: 0 }])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when no activities for user', () => {
    const dash = new ActivityDashboard([])
    expect(dash.calculateEngagementScore('n/a')).toBe(0)
  })

  it('computes engagement score using volume, diversity, and frequency components', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2024, 1, 1, 10, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 10, 10) },
      { id: '3', user_id: 'u1', action: 'login', timestamp: d(2024, 1, 1, 10, 50) },
      { id: '4', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 12, 0) },
      { id: '5', user_id: 'u1', action: 'click', timestamp: d(2024, 1, 2, 9, 0) }
    ]
    const dash = new ActivityDashboard(activities)
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(50.5) // 1.5 + 9 + 40
  })

  it('handles high volume and caps components at specified maxima', () => {
    // 150 actions across 10 unique actions and dense in 1 day to cap all components
    const acts: Activity[] = []
    for (let i = 0; i < 150; i++) {
      acts.push({
        id: String(i + 1),
        user_id: 'uX',
        action: `a${i % 10}`, // 10 unique actions
        timestamp: d(2024, 6, 1, 0, 0 + i) // all within same day in small increments
      })
    }
    const dash = new ActivityDashboard(acts)
    const score = dash.calculateEngagementScore('uX')
    // volumeScore capped at 30, diversityScore capped at 30, frequencyScore capped at 40 -> total 100
    expect(score).toBe(100)
  })
})