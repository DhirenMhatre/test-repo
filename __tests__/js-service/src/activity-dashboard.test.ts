import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../../../js-service/src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function makeDate(y: number, m: number, d: number, h = 0, min = 0, s = 0) {
  return new Date(y, m - 1, d, h, min, s)
}

function getWeekNumber(date: Date): number {
  const firstDayOfYear = new Date(date.getFullYear(), 0, 1)
  const pastDaysOfYear = (date.getTime() - firstDayOfYear.getTime()) / 86400000
  return Math.ceil((pastDaysOfYear + firstDayOfYear.getDay() + 1) / 7)
}

function getPeriodKey(date: Date, periodType: string): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  const hour = String(date.getHours()).padStart(2, '0')

  switch (periodType) {
    case 'hour':
      return `${year}-${month}-${day} ${hour}:00`
    case 'day':
      return `${year}-${month}-${day}`
    case 'week':
      const weekNumber = getWeekNumber(date)
      return `${year}-W${String(weekNumber).padStart(2, '0')}`
    case 'month':
      return `${year}-${month}`
    default:
      return `${year}-${month}-${day}`
  }
}

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const res = dash.getUserSummary('u1')
    expect(res).toBeNull()
  })

  it('computes totals, unique actions, actionsPerDay, mostFrequentAction, and averageActionsPerSession for same-day activities', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'view', timestamp: makeDate(2023, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'click', timestamp: makeDate(2023, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'view', timestamp: makeDate(2023, 1, 1, 9, 45) },
      { id: '4', user_id: 'u1', action: 'purchase', timestamp: makeDate(2023, 1, 1, 10, 30) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: makeDate(2023, 1, 1, 11, 5) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    expect(res!.totalActions).toBe(5)
    expect(res!.uniqueActions).toBe(3)
    expect(res!.actionsPerDay).toBe(5)
    expect(res!.mostFrequentAction).toBe('view')
    expect(res!.averageActionsPerSession).toBe(1.25)
  })

  it('computes actionsPerDay across multiple days using ceil days difference and rounds to 2 decimals', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: makeDate(2023, 1, 1, 0, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: makeDate(2023, 1, 2, 0, 0) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: makeDate(2023, 1, 2, 12, 0) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    // first: Jan 1 00:00, last: Jan 2 12:00 => diff 1.5 days => ceil -> 2 days, 3 actions -> 1.5 per day
    expect(res!.actionsPerDay).toBe(1.5)
  })

  it('calculates averageActionsPerSession with 30-minute threshold (gap > 30 starts new session)', () => {
    const base = makeDate(2023, 1, 1, 9, 0, 0)
    const t1 = base
    const t2 = makeDate(2023, 1, 1, 9, 30, 0) // exactly 30 min -> same session
    const t3 = makeDate(2023, 1, 1, 10, 31, 0) // >30 min after previous -> new session
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: t1 },
      { id: '2', user_id: 'u1', action: 'a', timestamp: t2 },
      { id: '3', user_id: 'u1', action: 'a', timestamp: t3 }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    // sessions: [t1,t2], [t3] => 2 sessions, avg 3/2 = 1.5
    expect(res!.averageActionsPerSession).toBe(1.5)
  })

  it('when actions tie in frequency, mostFrequentAction is the one first seen (in insertion order)', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'view', timestamp: makeDate(2023, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'click', timestamp: makeDate(2023, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'view', timestamp: makeDate(2023, 1, 1, 9, 20) },
      { id: '4', user_id: 'u1', action: 'click', timestamp: makeDate(2023, 1, 1, 9, 30) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    // Both 'view' and 'click' have count 2; 'view' appeared first so it should remain most frequent
    expect(res!.mostFrequentAction).toBe('view')
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const res = dash.getActivityTrends('none', 'day')
    expect(Array.isArray(res)).toBe(true)
    expect(res.length).toBe(0)
  })

  it('groups by day and computes growth rate correctly', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: makeDate(2023, 1, 1, 9, 0) }, // day 1: 1
      { id: '2', user_id: 'u1', action: 'b', timestamp: makeDate(2023, 1, 2, 9, 0) }, // day 2: 2
      { id: '3', user_id: 'u1', action: 'c', timestamp: makeDate(2023, 1, 2, 10, 0) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.getActivityTrends('u1', 'day')
    expect(res.length).toBe(2)
    expect(res[0].period).toBe(getPeriodKey(makeDate(2023, 1, 1, 9, 0), 'day'))
    expect(res[0].count).toBe(1)
    expect(res[0].growthRate).toBe(0)
    expect(res[1].period).toBe(getPeriodKey(makeDate(2023, 1, 2, 9, 0), 'day'))
    expect(res[1].count).toBe(2)
    expect(res[1].growthRate).toBe(100)
  })

  it('groups by hour with correct period keys and counts', () => {
    const d1 = makeDate(2023, 1, 1, 9, 10)
    const d2 = makeDate(2023, 1, 1, 10, 5)
    const d3 = makeDate(2023, 1, 1, 9, 20)
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d1 },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d2 },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d3 }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.getActivityTrends('u1', 'hour')
    expect(res.length).toBe(2)
    const p9 = getPeriodKey(d1, 'hour')
    const p10 = getPeriodKey(d2, 'hour')
    expect(res[0].period).toBe(p9)
    expect(res[0].count).toBe(2)
    expect(res[1].period).toBe(p10)
    expect(res[1].count).toBe(1)
  })

  it('groups by week using getWeekNumber and sorts by period lexicographically', () => {
    const a1 = makeDate(2023, 1, 1, 9, 0)  // likely W01
    const a2 = makeDate(2023, 1, 8, 9, 0)  // likely W02 with given algorithm
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: a1 },
      { id: '2', user_id: 'u1', action: 'b', timestamp: a2 }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.getActivityTrends('u1', 'week')
    expect(res.length).toBe(2)
    expect(res[0].period).toBe(getPeriodKey(a1, 'week'))
    expect(res[0].count).toBe(1)
    expect(res[1].period).toBe(getPeriodKey(a2, 'week'))
    expect(res[1].count).toBe(1)
    expect(res[1].growthRate).toBe(0)
  })

  it('groups by month and computes growth', () => {
    const a1 = makeDate(2023, 1, 10, 8, 0)
    const a2 = makeDate(2023, 2, 5, 10, 0)
    const a3 = makeDate(2023, 2, 6, 10, 0)
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: a1 }, // Jan: 1
      { id: '2', user_id: 'u1', action: 'b', timestamp: a2 }, // Feb: 2
      { id: '3', user_id: 'u1', action: 'c', timestamp: a3 }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.getActivityTrends('u1', 'month')
    expect(res.length).toBe(2)
    expect(res[0].period).toBe(getPeriodKey(a1, 'month'))
    expect(res[0].count).toBe(1)
    expect(res[1].period).toBe(getPeriodKey(a2, 'month'))
    expect(res[1].count).toBe(2)
    expect(res[1].growthRate).toBe(100)
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('filters by inclusive date range and correct user', () => {
    const a1 = { id: '1', user_id: 'u1', action: 'a', timestamp: makeDate(2023, 1, 1, 9, 0) }
    const a2 = { id: '2', user_id: 'u1', action: 'b', timestamp: makeDate(2023, 1, 1, 9, 45) }
    const a3 = { id: '3', user_id: 'u1', action: 'c', timestamp: makeDate(2023, 1, 1, 10, 30) }
    const a4 = { id: '4', user_id: 'u2', action: 'x', timestamp: makeDate(2023, 1, 1, 9, 30) }
    const dash = new ActivityDashboard([a1, a2, a3, a4] as any)
    const res = dash.filterByDateRange('u1', makeDate(2023, 1, 1, 9, 45), makeDate(2023, 1, 1, 10, 30))
    expect(res.map(r => r.id)).toEqual(['2', '3'])
  })

  it('returns empty array when no activities in range', () => {
    const a1 = { id: '1', user_id: 'u1', action: 'a', timestamp: makeDate(2023, 1, 1, 9, 0) }
    const dash = new ActivityDashboard([a1] as any)
    const res = dash.filterByDateRange('u1', makeDate(2023, 1, 2, 0, 0), makeDate(2023, 1, 2, 23, 59))
    expect(res.length).toBe(0)
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const res = dash.aggregateByAction('u1')
    expect(res).toEqual([])
  })

  it('aggregates counts, percentages, first and last occurrence, sorted by count desc', () => {
    const v1 = makeDate(2023, 1, 1, 9, 0)
    const v2 = makeDate(2023, 1, 1, 9, 45)
    const v3 = makeDate(2023, 1, 1, 11, 5)
    const activities = [
      { id: '1', user_id: 'u1', action: 'view', timestamp: v1 },
      { id: '2', user_id: 'u1', action: 'click', timestamp: makeDate(2023, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'view', timestamp: v2 },
      { id: '4', user_id: 'u1', action: 'purchase', timestamp: makeDate(2023, 1, 1, 10, 30) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: v3 }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.aggregateByAction('u1')
    expect(res.length).toBe(3)
    expect(res[0].action).toBe('view')
    expect(res[0].count).toBe(3)
    expect(res[0].percentage).toBe(60)
    expect(res[0].firstOccurrence.getTime()).toBe(v1.getTime())
    expect(res[0].lastOccurrence.getTime()).toBe(v3.getTime())
    const names = res.map(r => r.action)
    expect(new Set(names)).toEqual(new Set(['view', 'click', 'purchase']))
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('returns top N actions by count with default limit 5', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: makeDate(2023, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: makeDate(2023, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'b', timestamp: makeDate(2023, 1, 1, 9, 11) },
      { id: '4', user_id: 'u1', action: 'c', timestamp: makeDate(2023, 1, 1, 9, 12) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.getTopActions('u1')
    // Only 3 groups exist, default limit 5 should return all 3
    expect(res.length).toBe(3)
    expect(res[0].action).toBe('b') // highest count
  })

  it('respects limit parameter', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: makeDate(2023, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'a', timestamp: makeDate(2023, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'b', timestamp: makeDate(2023, 1, 1, 9, 11) },
      { id: '4', user_id: 'u1', action: 'c', timestamp: makeDate(2023, 1, 1, 9, 12) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const res = dash.getTopActions('u1', 1)
    expect(res.length).toBe(1)
    expect(res[0].action).toBe('a')
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(0)
  })

  it('computes engagement score with volume, diversity, and frequency components rounded to 2 decimals', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'view', timestamp: makeDate(2023, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'click', timestamp: makeDate(2023, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'view', timestamp: makeDate(2023, 1, 1, 9, 45) },
      { id: '4', user_id: 'u1', action: 'purchase', timestamp: makeDate(2023, 1, 1, 10, 30) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: makeDate(2023, 1, 1, 11, 5) }
    ]
    const dash = new ActivityDashboard(activities as any)
    const score = dash.calculateEngagementScore('u1')
    // total=5 => volume min(5/100,1)*30=1.5
    // unique=3 => diversity min(3/10,1)*30=9
    // actionsPerDay=5 => freq min(5/5,1)*40=40
    // total = 50.5
    expect(score).toBe(50.5)
  })
})