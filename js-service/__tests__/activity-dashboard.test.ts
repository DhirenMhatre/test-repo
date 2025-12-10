import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

const dt = (y: number, m: number, d: number, h = 0, min = 0) => new Date(y, m - 1, d, h, min, 0, 0)
const act = (id: string, user: string, action: string, date: Date) => ({
  id,
  user_id: user,
  action,
  timestamp: date
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([
      act('1', 'u2', 'login', dt(2023, 1, 1, 10))
    ])
    const summary = dash.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, actions per day, most frequent, and average per session', () => {
    const activities = [
      act('1', 'u1', 'login', dt(2023, 1, 1, 10, 0)),
      act('2', 'u1', 'click', dt(2023, 1, 1, 10, 5)),
      act('3', 'u1', 'click', dt(2023, 1, 1, 10, 20)),
      act('4', 'u1', 'view', dt(2023, 1, 1, 11, 10)), // >30 min gap -> new session
      act('5', 'u1', 'click', dt(2023, 1, 3, 10, 0)) // >1 day -> new session
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(5)
    expect(summary!.uniqueActions).toBe(3)
    // First is Jan 1 10:00, last is Jan 3 10:00 => exactly 2 days -> ceil(2) = 2
    expect(summary!.actionsPerDay).toBe(2.5)
    expect(summary!.mostFrequentAction).toBe('click')
    // Sessions: [10:00,10:05,10:20] [11:10] [Jan3 10:00] => 3 sessions -> 5/3 = 1.67
    expect(summary!.averageActionsPerSession).toBe(1.67)
  })

  it('uses minimum daysActive of 1 when activities are within the same moment', () => {
    const activities = [
      act('1', 'u1', 'a', dt(2023, 2, 1, 9)),
      act('2', 'u1', 'b', dt(2023, 2, 1, 9)),
      act('3', 'u1', 'c', dt(2023, 2, 1, 9))
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.actionsPerDay).toBe(3)
    expect(summary!.averageActionsPerSession).toBe(3.00) // all within same session
  })
})

describe('ActivityDashboard - getActivityTrends (day)', () => {
  it('groups by day and calculates growth rates across sorted periods', () => {
    const y = 2023
    const activities = [
      act('1', 'u1', 'a', dt(y, 1, 1, 10)),
      act('2', 'u1', 'b', dt(y, 1, 1, 11)),
      act('3', 'u1', 'c', dt(y, 1, 2, 10)),
      act('4', 'u1', 'd', dt(y, 1, 4, 9)),
      act('5', 'u1', 'e', dt(y, 1, 4, 10)),
      act('6', 'u1', 'f', dt(y, 1, 4, 11))
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends.map(t => t.period)).toEqual([
      `${y}-01-01`,
      `${y}-01-02`,
      `${y}-01-04`
    ])
    expect(trends.map(t => t.count)).toEqual([2, 1, 3])
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].growthRate).toBe(-50)
    expect(trends[2].growthRate).toBe(200)
  })

  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })
})

describe('ActivityDashboard - getActivityTrends (hour)', () => {
  it('groups by hour with HH:00 format', () => {
    const d = dt(2023, 3, 10, 9)
    const activities = [
      act('1', 'u1', 'a', dt(2023, 3, 10, 9, 5)),
      act('2', 'u1', 'b', dt(2023, 3, 10, 9, 55)),
      act('3', 'u1', 'c', dt(2023, 3, 10, 11, 1))
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'hour')
    expect(trends.map(t => t.period)).toEqual([
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} 09:00`,
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} 11:00`
    ])
    expect(trends.map(t => t.count)).toEqual([2, 1])
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].growthRate).toBe(-50)
  })
})

describe('ActivityDashboard - getActivityTrends (week and month)', () => {
  it('groups by week with "YYYY-Www" keys', () => {
    const activities = [
      act('1', 'u1', 'a', dt(2023, 1, 1, 10)), // likely week 01
      act('2', 'u1', 'b', dt(2023, 1, 5, 10)), // same week 01
      act('3', 'u1', 'c', dt(2023, 1, 8, 10))  // next week (approx week 02)
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(2)
    expect(trends[0].period.startsWith('2023-W')).toBe(true)
    expect(trends[1].period.startsWith('2023-W')).toBe(true)
    expect(trends[0].count).toBe(2)
    expect(trends[1].count).toBe(1)
    // growth from 2 to 1 -> -50%
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].growthRate).toBe(-50)
  })

  it('groups by month with "YYYY-MM" keys', () => {
    const activities = [
      act('1', 'u1', 'a', dt(2023, 1, 10, 10)),
      act('2', 'u1', 'b', dt(2023, 2, 5, 10)),
      act('3', 'u1', 'c', dt(2023, 2, 6, 12))
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'month')
    expect(trends.map(t => t.period)).toEqual(['2023-01', '2023-02'])
    expect(trends.map(t => t.count)).toEqual([1, 2])
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].growthRate).toBe(100)
  })

  it('uses day grouping when an unknown period is passed at runtime', () => {
    const activities = [
      act('1', 'u1', 'a', dt(2023, 5, 1, 10)),
      act('2', 'u1', 'b', dt(2023, 5, 2, 11))
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'quarter' as any)
    expect(trends.map(t => t.period)).toEqual(['2023-05-01', '2023-05-02'])
    expect(trends.map(t => t.count)).toEqual([1, 1])
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('returns activities inclusively within the date range', () => {
    const a1 = act('1', 'u1', 'a', dt(2023, 1, 1, 9))
    const a2 = act('2', 'u1', 'b', dt(2023, 1, 2, 10))
    const a3 = act('3', 'u1', 'c', dt(2023, 1, 3, 11))
    const a4 = act('4', 'u1', 'd', dt(2023, 1, 4, 12))
    const dash = new ActivityDashboard([a1, a2, a3, a4])
    const start = dt(2023, 1, 2, 10)
    const end = dt(2023, 1, 3, 11)
    const filtered = dash.filterByDateRange('u1', start, end)
    expect(filtered).toEqual([a2, a3])
  })

  it('filters only by specified user', () => {
    const a1 = act('1', 'u1', 'a', dt(2023, 1, 1, 9))
    const a2 = act('2', 'u2', 'b', dt(2023, 1, 2, 10))
    const dash = new ActivityDashboard([a1, a2])
    const filtered = dash.filterByDateRange('u1', dt(2023, 1, 1, 0), dt(2023, 1, 3, 0))
    expect(filtered).toEqual([a1])
  })
})

describe('ActivityDashboard - aggregateByAction and getTopActions', () => {
  it('aggregates counts, percentages, occurrences, and sorts by count desc', () => {
    const c1 = act('1', 'u1', 'click', dt(2023, 1, 1, 10))
    const c2 = act('2', 'u1', 'click', dt(2023, 1, 1, 11))
    const c3 = act('3', 'u1', 'click', dt(2023, 1, 2, 9))
    const v1 = act('4', 'u1', 'view', dt(2023, 1, 2, 12))
    const v2 = act('5', 'u1', 'view', dt(2023, 1, 3, 13))
    const dash = new ActivityDashboard([c1, c2, c3, v1, v2])

    const groups = dash.aggregateByAction('u1')
    expect(groups.length).toBe(2)

    // click group
    expect(groups[0].action).toBe('click')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(60)
    expect(groups[0].firstOccurrence.getTime()).toBe(c1.timestamp.getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(c3.timestamp.getTime())

    // view group
    expect(groups[1].action).toBe('view')
    expect(groups[1].count).toBe(2)
    expect(groups[1].percentage).toBe(40)
    expect(groups[1].firstOccurrence.getTime()).toBe(v1.timestamp.getTime())
    expect(groups[1].lastOccurrence.getTime()).toBe(v2.timestamp.getTime())
  })

  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([
      act('1', 'u2', 'click', dt(2023, 1, 1, 10))
    ])
    const groups = dash.aggregateByAction('u1')
    expect(groups).toEqual([])
  })

  it('getTopActions respects provided limit', () => {
    const acts = [
      act('1', 'u1', 'a', dt(2023, 1, 1, 10)),
      act('2', 'u1', 'a', dt(2023, 1, 1, 11)),
      act('3', 'u1', 'b', dt(2023, 1, 2, 9)),
      act('4', 'u1', 'c', dt(2023, 1, 2, 10)),
      act('5', 'u1', 'c', dt(2023, 1, 3, 10)),
      act('6', 'u1', 'd', dt(2023, 1, 3, 11))
    ]
    const dash = new ActivityDashboard(acts)
    const top2 = dash.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('a')
    expect(top2[1].action).toBe('c')
  })

  it('getTopActions with default limit returns all when fewer than limit exist', () => {
    const acts = [
      act('1', 'u1', 'x', dt(2023, 2, 1, 10)),
      act('2', 'u1', 'y', dt(2023, 2, 1, 11))
    ]
    const dash = new ActivityDashboard(acts)
    const top = dash.getTopActions('u1')
    // two actions, limit default 5 -> returns both
    expect(top.length).toBe(2)
    const actions = top.map(g => g.action).sort()
    expect(actions).toEqual(['x', 'y'])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activities', () => {
    const dash = new ActivityDashboard([
      act('1', 'u2', 'a', dt(2023, 1, 1, 10))
    ])
    expect(dash.calculateEngagementScore('u1')).toBe(0)
  })

  it('calculates engagement score with partial caps', () => {
    // totalActions=50 => volumeScore = 0.5 * 30 = 15
    // uniqueActions=5 => diversityScore = 0.5 * 30 = 15
    // actionsPerDay=2 => frequencyScore = (2/5)=0.4 * 40 = 16
    // total = 46
    const acts: any[] = []
    for (let i = 0; i < 50; i++) {
      acts.push(act(String(i + 1), 'u1', i % 10 < 5 ? `type${i % 5}` : `type${i % 5}`, dt(2023, 1, (i % 2) + 1, 10, i % 60)))
    }
    const dash = new ActivityDashboard(acts)
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(46)
  })

  it('caps each component and rounds to two decimals', () => {
    // volume: min(500/100,1)*30 = 30
    // diversity: min(100/10,1)*30 = 30
    // frequency: actionsPerDay >= 5 -> min(...,1)*40 = 40
    // total = 100
    const acts: any[] = []
    // 500 actions over 1 day -> actionsPerDay = 500
    for (let i = 0; i < 500; i++) {
      acts.push(act(`x${i}`, 'u1', `a${i % 100}`, dt(2023, 1, 1, 10, i % 60)))
    }
    const dash = new ActivityDashboard(acts)
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(100)
  })
})

describe('ActivityDashboard - getActivityTrends growth negative and positive', () => {
  it('computes negative and positive growth between consecutive periods', () => {
    const y = 2023
    const activities = [
      act('1', 'u1', 'a', dt(y, 7, 1, 10)),
      act('2', 'u1', 'b', dt(y, 7, 1, 11)),
      act('3', 'u1', 'c', dt(y, 7, 1, 12)),
      act('4', 'u1', 'd', dt(y, 7, 2, 10)), // 1 action
      act('5', 'u1', 'e', dt(y, 7, 3, 9)),
      act('6', 'u1', 'f', dt(y, 7, 3, 10)),
      act('7', 'u1', 'g', dt(y, 7, 3, 11)),
      act('8', 'u1', 'h', dt(y, 7, 3, 12))
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends.map(t => t.count)).toEqual([3, 1, 4])
    expect(trends[0].growthRate).toBe(0)
    // from 3 to 1: (1-3)/3 * 100 = -66.67
    expect(trends[1].growthRate).toBeCloseTo(-66.67, 2)
    // from 1 to 4: (4-1)/1 * 100 = 300
    expect(trends[2].growthRate).toBe(300)
  })
})