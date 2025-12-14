import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

type Act = {
  id: string
  user_id: string
  action: string
  timestamp: Date
  metadata?: Record<string, any>
}

const d = (y: number, m: number, day: number, h = 0, min = 0, s = 0) => new Date(y, m, day, h, min, s)

const pad2 = (n: number) => String(n).padStart(2, '0')

const getWeekNumberLikeSource = (date: Date) => {
  const firstDayOfYear = new Date(date.getFullYear(), 0, 1)
  const pastDaysOfYear = (date.getTime() - firstDayOfYear.getTime()) / 86400000
  return Math.ceil((pastDaysOfYear + firstDayOfYear.getDay() + 1) / 7)
}

const periodKey = (date: Date, periodType: 'hour' | 'day' | 'week' | 'month') => {
  const year = date.getFullYear()
  const month = pad2(date.getMonth() + 1)
  const day = pad2(date.getDate())
  const hour = pad2(date.getHours())

  switch (periodType) {
    case 'hour':
      return `${year}-${month}-${day} ${hour}:00`
    case 'day':
      return `${year}-${month}-${day}`
    case 'week': {
      const w = getWeekNumberLikeSource(date)
      return `${year}-W${pad2(w)}`
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

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const res = dash.getUserSummary('u1')
    expect(res).toBeNull()
  })

  it('computes totals, unique actions, most frequent, actionsPerDay, and averageActionsPerSession', () => {
    const a1 = { id: '1', user_id: 'u1', action: 'click', timestamp: d(2024, 0, 1, 10, 0) }
    const a2 = { id: '2', user_id: 'u1', action: 'view', timestamp: d(2024, 0, 1, 10, 10) }
    const a3 = { id: '3', user_id: 'u1', action: 'click', timestamp: d(2024, 0, 1, 10, 20) }
    const a4 = { id: '4', user_id: 'u1', action: 'click', timestamp: d(2024, 0, 1, 11, 0) }
    const a5 = { id: '5', user_id: 'u1', action: 'view', timestamp: d(2024, 0, 2, 9, 0) }
    const other = { id: '6', user_id: 'u2', action: 'click', timestamp: d(2024, 0, 1, 10, 0) }
    const dash = new ActivityDashboard([a1, a2, a3, a4, a5, other] as Act[])

    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    expect(res!.totalActions).toBe(5)
    expect(res!.uniqueActions).toBe(2)
    expect(res!.mostFrequentAction).toBe('click')
    expect(res!.actionsPerDay).toBe(5) // all within less than 24 hours difference -> daysActive=1 -> 5/day
    expect(res!.averageActionsPerSession).toBe(1.67) // sessions split by >30min gaps: [a1,a2,a3], [a4], [a5] => 3 sessions => 5/3=1.67
  })

  it('resolves tie in most frequent action by first encountered action', () => {
    const a1 = { id: '1', user_id: 'u1', action: 'A', timestamp: d(2024, 0, 1, 10, 0) }
    const a2 = { id: '2', user_id: 'u1', action: 'B', timestamp: d(2024, 0, 1, 10, 5) }
    const dash = new ActivityDashboard([a1, a2] as Act[])
    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    expect(res!.mostFrequentAction).toBe('A')
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('returns empty array when no activities for user', () => {
    const dash = new ActivityDashboard([])
    const res = dash.getActivityTrends('u1', 'day')
    expect(res).toEqual([])
  })

  it('groups by day and calculates growth rates', () => {
    const u = 'u1'
    const d1 = d(2024, 0, 1, 10, 0)
    const d2a = d(2024, 0, 2, 9, 0)
    const d2b = d(2024, 0, 2, 12, 0)
    const d3 = d(2024, 0, 3, 8, 0)
    const acts: Act[] = [
      { id: '1', user_id: u, action: 'x', timestamp: d1 },
      { id: '2', user_id: u, action: 'y', timestamp: d2a },
      { id: '3', user_id: u, action: 'z', timestamp: d2b },
      { id: '4', user_id: u, action: 'x', timestamp: d3 }
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.getActivityTrends(u, 'day')
    expect(res.map(x => x.period)).toEqual([
      periodKey(d1, 'day'),
      periodKey(d2a, 'day'),
      periodKey(d3, 'day')
    ])
    expect(res.map(x => x.count)).toEqual([1, 2, 1])
    expect(res.map(x => x.growthRate)).toEqual([0, 100, -50])
  })

  it('groups by hour correctly with HH:00 formatting and growth', () => {
    const u = 'u1'
    const h10a = d(2024, 0, 1, 10, 5)
    const h10b = d(2024, 0, 1, 10, 55)
    const h11 = d(2024, 0, 1, 11, 0)
    const dash = new ActivityDashboard([
      { id: '1', user_id: u, action: 'a', timestamp: h10a },
      { id: '2', user_id: u, action: 'b', timestamp: h10b },
      { id: '3', user_id: u, action: 'c', timestamp: h11 }
    ] as Act[])
    const res = dash.getActivityTrends(u, 'hour')
    expect(res.map(r => r.period)).toEqual([periodKey(h10a, 'hour'), periodKey(h11, 'hour')])
    expect(res.map(r => r.count)).toEqual([2, 1])
    expect(res.map(r => r.growthRate)).toEqual([0, -50])
  })

  it('groups by week and sorts by period increasing', () => {
    const u = 'u1'
    const w1 = d(2024, 0, 1, 10, 0) // week 01
    const w2a = d(2024, 0, 10, 9, 0) // likely week 02
    const w2b = d(2024, 0, 11, 9, 0)
    const dash = new ActivityDashboard([
      { id: '1', user_id: u, action: 'a', timestamp: w1 },
      { id: '2', user_id: u, action: 'b', timestamp: w2a },
      { id: '3', user_id: u, action: 'c', timestamp: w2b }
    ] as Act[])
    const res = dash.getActivityTrends(u, 'week')
    expect(res.length).toBe(2)
    expect(res[0].period).toBe(periodKey(w1, 'week'))
    expect(res[1].period).toBe(periodKey(w2a, 'week'))
    expect(res.map(x => x.count)).toEqual([1, 2])
    expect(res.map(x => x.growthRate)).toEqual([0, 100])
  })

  it('groups by month and computes correct growth', () => {
    const u = 'u1'
    const m1a = d(2024, 0, 1, 0, 0)
    const m1b = d(2024, 0, 15, 12, 0)
    const m2 = d(2024, 1, 1, 9, 0)
    const dash = new ActivityDashboard([
      { id: '1', user_id: u, action: 'a', timestamp: m1a },
      { id: '2', user_id: u, action: 'b', timestamp: m1b },
      { id: '3', user_id: u, action: 'c', timestamp: m2 }
    ] as Act[])
    const res = dash.getActivityTrends(u, 'month')
    expect(res.map(r => r.period)).toEqual([periodKey(m1a, 'month'), periodKey(m2, 'month')])
    expect(res.map(r => r.count)).toEqual([2, 1])
    expect(res.map(r => r.growthRate)).toEqual([0, -50])
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('includes activities exactly on the start and end dates (inclusive boundaries)', () => {
    const u = 'u1'
    const a1 = { id: '1', user_id: u, action: 'a', timestamp: d(2024, 0, 1, 10, 0) }
    const a2 = { id: '2', user_id: u, action: 'b', timestamp: d(2024, 0, 2, 0, 0) }
    const a3 = { id: '3', user_id: u, action: 'c', timestamp: d(2024, 0, 2, 23, 59) }
    const a4 = { id: '4', user_id: u, action: 'd', timestamp: d(2024, 0, 3, 0, 0) }
    const dash = new ActivityDashboard([a1, a2, a3, a4] as Act[])
    const res = dash.filterByDateRange(u, d(2024, 0, 2, 0, 0), d(2024, 0, 2, 23, 59))
    expect(res.map(r => r.id)).toEqual(['2', '3'])
  })

  it('returns empty when user has no activities in range', () => {
    const dash = new ActivityDashboard([
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 0, 1) },
      { id: '2', user_id: 'u2', action: 'a', timestamp: d(2024, 0, 2) }
    ] as Act[])
    const res = dash.filterByDateRange('u3', d(2024, 0, 1), d(2024, 0, 3))
    expect(res).toEqual([])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('returns empty array for user with no activities', () => {
    const dash = new ActivityDashboard([] as Act[])
    const res = dash.aggregateByAction('u1')
    expect(res).toEqual([])
  })

  it('aggregates counts, percentages, and first/last occurrences; sorts by count desc', () => {
    const u = 'u1'
    const c1 = d(2024, 0, 1, 10, 0)
    const c2 = d(2024, 0, 1, 10, 5)
    const v1 = d(2024, 0, 1, 11, 0)
    const v2 = d(2024, 0, 1, 11, 10)
    const s1 = d(2024, 0, 1, 12, 0)
    const acts: Act[] = [
      { id: '1', user_id: u, action: 'view', timestamp: v1 },
      { id: '2', user_id: u, action: 'click', timestamp: c1 },
      { id: '3', user_id: u, action: 'share', timestamp: s1 },
      { id: '4', user_id: u, action: 'click', timestamp: c2 },
      { id: '5', user_id: u, action: 'view', timestamp: v2 }
    ]
    const dash = new ActivityDashboard(acts)
    const groups = dash.aggregateByAction(u)

    const totals = groups.reduce((sum, g) => sum + g.count, 0)
    expect(totals).toBe(5)

    const topCounts = groups.slice(0, 2).map(g => g.count)
    expect(topCounts).toEqual([2, 2])

    const actionsSet = new Set(groups.slice(0, 2).map(g => g.action))
    expect(actionsSet.has('click')).toBe(true)
    expect(actionsSet.has('view')).toBe(true)

    const clickGroup = groups.find(g => g.action === 'click')!
    expect(clickGroup.count).toBe(2)
    expect(clickGroup.percentage).toBe(40) // 2/5 * 100 = 40.00 -> 40
    expect(clickGroup.firstOccurrence.getTime()).toBe(c1.getTime())
    expect(clickGroup.lastOccurrence.getTime()).toBe(c2.getTime())

    const shareGroup = groups.find(g => g.action === 'share')!
    expect(shareGroup.count).toBe(1)
    expect(shareGroup.percentage).toBe(20) // 1/5 * 100 = 20.00 -> 20
    expect(shareGroup.firstOccurrence.getTime()).toBe(s1.getTime())
    expect(shareGroup.lastOccurrence.getTime()).toBe(s1.getTime())
  })
})

describe('ActivityDashboard.getTopActions_old', () => {
  it('returns all aggregated actions ignoring the limit parameter', () => {
    const u = 'u1'
    const acts: Act[] = [
      { id: '1', user_id: u, action: 'a', timestamp: d(2024, 0, 1, 10) },
      { id: '2', user_id: u, action: 'b', timestamp: d(2024, 0, 1, 11) },
      { id: '3', user_id: u, action: 'c', timestamp: d(2024, 0, 1, 12) },
      { id: '4', user_id: u, action: 'd', timestamp: d(2024, 0, 1, 13) },
      { id: '5', user_id: u, action: 'a', timestamp: d(2024, 0, 1, 14) },
      { id: '6', user_id: u, action: 'b', timestamp: d(2024, 0, 1, 15) }
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.getTopActions_old(u, 2)
    expect(res.length).toBe(4) // ignores limit: returns all unique actions
    const map = new Map(res.map(r => [r.action, r]))
    expect(map.get('a')!.count).toBe(2)
    expect(map.get('b')!.count).toBe(2)
    expect(map.get('c')!.count).toBe(1)
    expect(map.get('d')!.count).toBe(1)
    expect(map.get('a')!.percentage).toBe(33.33) // 2/6 * 100 -> 33.33
    expect(map.get('c')!.percentage).toBe(16.67) // 1/6 * 100 -> 16.67
    expect(map.get('a')!.firstOccurrence.getTime()).toBe(d(2024, 0, 1, 10).getTime())
    expect(map.get('a')!.lastOccurrence.getTime()).toBe(d(2024, 0, 1, 14).getTime())
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('returns a limited list of top actions', () => {
    const u = 'u1'
    const acts: Act[] = [
      { id: '1', user_id: u, action: 'a', timestamp: d(2024, 0, 1, 10) },
      { id: '2', user_id: u, action: 'b', timestamp: d(2024, 0, 1, 11) },
      { id: '3', user_id: u, action: 'c', timestamp: d(2024, 0, 1, 12) },
      { id: '4', user_id: u, action: 'd', timestamp: d(2024, 0, 1, 13) },
      { id: '5', user_id: u, action: 'a', timestamp: d(2024, 0, 1, 14) },
      { id: '6', user_id: u, action: 'b', timestamp: d(2024, 0, 1, 15) }
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.getTopActions(u, 2)
    expect(res.length).toBe(2)
    expect(new Set(res.map(r => r.action))).toEqual(new Set(['a', 'b']))
  })

  it('returns empty array when user has no actions', () => {
    const dash = new ActivityDashboard([] as Act[])
    expect(dash.getTopActions('uX', 3)).toEqual([])
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 for user with no activity', () => {
    const dash = new ActivityDashboard([])
    expect(dash.calculateEngagementScore('u1')).toBe(0)
  })

  it('caps at 100 when all components are saturated', () => {
    const u = 'u1'
    const acts: Act[] = []
    const base = d(2024, 0, 1, 10, 0)
    const actions = ['a','b','c','d','e','f','g','h','i','j']
    for (let i = 0; i < 120; i++) {
      acts.push({
        id: String(i + 1),
        user_id: u,
        action: actions[i % actions.length],
        timestamp: new Date(base.getTime() + i * 1000) // all within the same day
      })
    }
    const dash = new ActivityDashboard(acts)
    expect(dash.calculateEngagementScore(u)).toBe(100)
  })

  it('computes partial scores with two-decimal rounding', () => {
    const u = 'u1'
    const acts: Act[] = []
    const first = d(2024, 0, 1, 0, 0)
    const last = d(2024, 0, 20, 0, 0)
    const total = 50
    const actions = ['a', 'b', 'c', 'd', 'e'] // 5 unique
    for (let i = 0; i < total; i++) {
      const t = new Date(first.getTime() + Math.floor((last.getTime() - first.getTime()) * (i / (total - 1))))
      acts.push({
        id: String(i + 1),
        user_id: u,
        action: actions[i % actions.length],
        timestamp: t
      })
    }
    const dash = new ActivityDashboard(acts)
    const score = dash.calculateEngagementScore(u)
    // volume: 50/100 * 30 = 15
    // diversity: 5/10 * 30 = 15
    // daysActive: ceil((last - first)/1d) = ceil(19) = 19; actionsPerDay = 50/19 = 2.6316...
    // frequency: min(2.6316/5,1)*40 = 0.52632*40 = 21.0528 -> 21.05 after rounding
    // total = 51.05
    expect(score).toBe(51.05)
  })
})

describe('ActivityDashboard.getActivityTrends default period type', () => {
  it('defaults to day when periodType is not provided', () => {
    const u = 'u1'
    const a = d(2024, 0, 1, 10, 0)
    const b = d(2024, 0, 1, 12, 0)
    const c = d(2024, 0, 2, 9, 0)
    const dash = new ActivityDashboard([
      { id: '1', user_id: u, action: 'x', timestamp: a },
      { id: '2', user_id: u, action: 'y', timestamp: b },
      { id: '3', user_id: u, action: 'z', timestamp: c }
    ] as Act[])
    const res = dash.getActivityTrends(u)
    expect(res.map(r => r.period)).toEqual([periodKey(a, 'day'), periodKey(c, 'day')])
    expect(res.map(r => r.count)).toEqual([2, 1])
  })
})