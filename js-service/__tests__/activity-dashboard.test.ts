import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function mkDate(y: number, m: number, d: number, h = 0, min = 0, s = 0) {
  return new Date(y, m, d, h, min, s)
}

function mkAct(id: string, user_id: string, action: string, timestamp: Date, metadata?: Record<string, any>) {
  return { id, user_id, action, timestamp, metadata }
}

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const result = dash.getUserSummary('u-missing')
    expect(result).toBeNull()
  })

  it('computes totals, unique actions, mostFrequent, actionsPerDay and averageActionsPerSession', () => {
    const base = mkDate(2023, 0, 1, 10, 0, 0)
    const activities = [
      mkAct('1', 'u1', 'view', new Date(base.getTime() + 0 * 60000)),
      mkAct('2', 'u1', 'login', new Date(base.getTime() + 10 * 60000)),
      mkAct('3', 'u1', 'login', new Date(base.getTime() + 20 * 60000)),
      mkAct('4', 'u1', 'view', new Date(base.getTime() + 70 * 60000)), // 50 min gap -> new session
      mkAct('5', 'u1', 'purchase', new Date(base.getTime() + 80 * 60000)),
      mkAct('6', 'u2', 'view', new Date(base.getTime() + 90 * 60000))
    ]
    const dash = new ActivityDashboard(activities)
    const result = dash.getUserSummary('u1')
    expect(result).not.toBeNull()
    expect(result!.totalActions).toBe(5)
    expect(result!.uniqueActions).toBe(3)
    // Tie between 'view' and 'login' with 2 each, but 'view' first encountered
    expect(result!.mostFrequentAction).toBe('view')
    // All within the same day => daysActive = 1 -> actionsPerDay = 5
    expect(result!.actionsPerDay).toBe(5)
    // Sessions: gaps > 30 mins => two sessions, avg = 5 / 2 = 2.5
    expect(result!.averageActionsPerSession).toBe(2.5)
  })

  it('correctly computes actionsPerDay across multiple days (ceil difference)', () => {
    const t1 = mkDate(2023, 0, 1, 8, 0, 0)
    const t2 = mkDate(2023, 0, 3, 8, 0, 0) // exactly 48 hours apart -> ceil(2) daysActive = 2
    const activities = [
      mkAct('1', 'u1', 'a', t1),
      mkAct('2', 'u1', 'b', t2)
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.actionsPerDay).toBe(1)
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('filters by inclusive start and end dates', () => {
    const d10 = mkDate(2023, 0, 1, 10)
    const d11 = mkDate(2023, 0, 1, 11)
    const d12 = mkDate(2023, 0, 1, 12)
    const activities = [
      mkAct('1', 'u1', 'a', d10),
      mkAct('2', 'u1', 'b', d11),
      mkAct('3', 'u1', 'c', d12),
      mkAct('4', 'u2', 'a', d11)
    ]
    const dash = new ActivityDashboard(activities)
    const filtered = dash.filterByDateRange('u1', d11, d12)
    const ids = filtered.map(a => a.id)
    expect(ids).toEqual(['2', '3'])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('aggregates counts, percentages and first/last occurrence, sorted by count desc', () => {
    const d950 = mkDate(2023, 0, 1, 9, 50)
    const d1000 = mkDate(2023, 0, 1, 10, 0)
    const d1100 = mkDate(2023, 0, 1, 11, 0)
    const d1200 = mkDate(2023, 0, 1, 12, 0)
    const activities = [
      mkAct('1', 'u1', 'login', d950),
      mkAct('2', 'u1', 'view', d1000),
      mkAct('3', 'u1', 'view', d1100),
      mkAct('4', 'u1', 'purchase', d1200),
      mkAct('5', 'u2', 'view', d1100)
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.aggregateByAction('u1')
    expect(groups.length).toBe(3)
    // Sorted by count DESC: view (2), login (1), purchase (1)
    expect(groups[0].action).toBe('view')
    expect(groups[0].count).toBe(2)
    expect(groups[0].percentage).toBe(50)
    expect(groups[0].firstOccurrence.getTime()).toBe(d1000.getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(d1100.getTime())

    // Others at 25% each
    const otherPercents = groups.slice(1).map(g => g.percentage)
    expect(otherPercents).toEqual([25, 25])
  })

  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const groups = dash.aggregateByAction('uX')
    expect(groups).toEqual([])
  })

  it('percentages are rounded to two decimals (e.g., 1/3 = 33.33)', () => {
    const d = mkDate(2023, 0, 1, 10)
    const activities = [
      mkAct('1', 'u1', 'A', d),
      mkAct('2', 'u1', 'B', new Date(d.getTime() + 1000)),
      mkAct('3', 'u1', 'B', new Date(d.getTime() + 2000))
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.aggregateByAction('u1')
    const aGroup = groups.find(g => g.action === 'A')!
    const bGroup = groups.find(g => g.action === 'B')!
    expect(aGroup.percentage).toBe(33.33)
    expect(bGroup.percentage).toBe(66.67)
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('returns limited number of top action groups', () => {
    const d = mkDate(2023, 0, 1, 10)
    const activities = [
      mkAct('1', 'u1', 'A', d),
      mkAct('2', 'u1', 'A', new Date(d.getTime() + 1000)),
      mkAct('3', 'u1', 'B', new Date(d.getTime() + 2000)),
      mkAct('4', 'u1', 'C', new Date(d.getTime() + 3000)),
      mkAct('5', 'u1', 'D', new Date(d.getTime() + 4000))
    ]
    const dash = new ActivityDashboard(activities)
    const top2 = dash.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('A')
  })

  it('default limit returns up to 5 groups', () => {
    const d = mkDate(2023, 0, 1, 10)
    const acts = ['A', 'B', 'C', 'D', 'E', 'F']
    const activities = acts.map((a, idx) => mkAct(String(idx + 1), 'u1', a, new Date(d.getTime() + idx * 1000)))
    const dash = new ActivityDashboard(activities)
    const top = dash.getTopActions('u1')
    expect(top.length).toBe(5)
    expect(new Set(top.map(g => g.action)).size).toBe(5)
  })
})

describe('ActivityDashboard.getActivityTrends - day', () => {
  it('groups by day and computes growth rates with rounding', () => {
    const d1 = mkDate(2023, 0, 1, 9)
    const d2 = mkDate(2023, 0, 2, 10)
    const d3 = mkDate(2023, 0, 3, 11)
    const activities = [
      mkAct('1', 'u1', 'A', d1),
      mkAct('2', 'u1', 'B', new Date(d1.getTime() + 1000)), // Day 1: 2
      mkAct('3', 'u1', 'A', d2),
      mkAct('4', 'u1', 'B', new Date(d2.getTime() + 1000)),
      mkAct('5', 'u1', 'C', new Date(d2.getTime() + 2000)), // Day 2: 3
      mkAct('6', 'u1', 'A', d3) // Day 3: 1
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends.length).toBe(3)
    // sorted ascending by period
    expect(trends[0].period).toBe('2023-01-01')
    expect(trends[0].count).toBe(2)
    expect(trends[0].growthRate).toBe(0)

    expect(trends[1].period).toBe('2023-01-02')
    expect(trends[1].count).toBe(3)
    expect(trends[1].growthRate).toBe(50)

    expect(trends[2].period).toBe('2023-01-03')
    expect(trends[2].count).toBe(1)
    expect(trends[2].growthRate).toBe(-66.67)
  })

  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const trends = dash.getActivityTrends('uX', 'day')
    expect(trends).toEqual([])
  })
})

describe('ActivityDashboard.getActivityTrends - hour', () => {
  it('groups by hour within the same day and computes growth', () => {
    const d10 = mkDate(2023, 0, 1, 10, 0)
    const d1030 = mkDate(2023, 0, 1, 10, 30)
    const d11 = mkDate(2023, 0, 1, 11, 0)
    const activities = [
      mkAct('1', 'u1', 'A', d10),
      mkAct('2', 'u1', 'B', d1030),
      mkAct('3', 'u1', 'C', d11)
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'hour')
    expect(trends.map(t => t.period)).toEqual(['2023-01-01 10:00', '2023-01-01 11:00'])
    expect(trends[0].count).toBe(2)
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50)
  })
})

describe('ActivityDashboard.getActivityTrends - week and month', () => {
  it('groups by week with expected period format', () => {
    const w1d = mkDate(2023, 0, 1, 10) // 2023-01-01, should be week W01 per implementation
    const w2d = mkDate(2023, 0, 8, 12) // Next week W02
    const activities = [
      mkAct('1', 'u1', 'A', w1d),
      mkAct('2', 'u1', 'A', w2d)
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-W01')
    expect(trends[0].count).toBe(1)
    expect(trends[1].period).toBe('2023-W02')
    expect(trends[1].count).toBe(1)
  })

  it('groups by month with format YYYY-MM', () => {
    const jan = mkDate(2023, 0, 15, 10)
    const feb = mkDate(2023, 1, 1, 9)
    const activities = [
      mkAct('1', 'u1', 'A', jan),
      mkAct('2', 'u1', 'B', feb),
      mkAct('3', 'u1', 'C', new Date(feb.getTime() + 1000))
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'month')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-01')
    expect(trends[0].count).toBe(1)
    expect(trends[1].period).toBe('2023-02')
    expect(trends[1].count).toBe(2)
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 for user with no activity', () => {
    const dash = new ActivityDashboard([])
    expect(dash.calculateEngagementScore('none')).toBe(0)
  })

  it('computes capped score at 100 with high volume/diversity/frequency', () => {
    // 100 actions, 10 unique types, within the same day => volume=30, diversity=30, frequency=40 -> 100
    const base = mkDate(2023, 0, 1, 10)
    const actions = Array.from({ length: 10 }, (_, i) => `A${i + 1}`)
    const activities = []
    let id = 1
    for (let a of actions) {
      for (let j = 0; j < 10; j++) {
        activities.push(mkAct(String(id++), 'u1', a, new Date(base.getTime() + (id * 1000))))
      }
    }
    const dash = new ActivityDashboard(activities)
    expect(dash.calculateEngagementScore('u1')).toBe(100)
  })

  it('computes fractional score with rounding to two decimals', () => {
    // total=5 (volume=1.5), unique=2 (diversity=6), actionsPerDay=5 (frequency=40)
    const base = mkDate(2023, 0, 1, 10)
    const activities = [
      mkAct('1', 'u1', 'A', new Date(base.getTime() + 0)),
      mkAct('2', 'u1', 'A', new Date(base.getTime() + 1000)),
      mkAct('3', 'u1', 'B', new Date(base.getTime() + 2000)),
      mkAct('4', 'u1', 'B', new Date(base.getTime() + 3000)),
      mkAct('5', 'u1', 'B', new Date(base.getTime() + 4000))
    ]
    const dash = new ActivityDashboard(activities)
    expect(dash.calculateEngagementScore('u1')).toBe(47.5)
  })
})