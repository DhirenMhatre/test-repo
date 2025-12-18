import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

const L = (y: number, m: number, d: number, h = 0, min = 0) => new Date(y, m - 1, d, h, min)
const makeAct = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>) => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([
      makeAct('1', 'u2', 'login', L(2024, 1, 1, 9))
    ])
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes summary metrics across multiple days with sessions and rounding', () => {
    const activities = [
      makeAct('1', 'u1', 'login', L(2024, 1, 1, 9, 0)),
      makeAct('2', 'u1', 'view', L(2024, 1, 1, 9, 10)),
      makeAct('3', 'u1', 'view', L(2024, 1, 1, 9, 45)), // 35 min gap -> new session
      makeAct('4', 'u1', 'logout', L(2024, 1, 2, 10, 0)),
      makeAct('5', 'u2', 'login', L(2024, 1, 1, 8, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(4)
    expect(summary!.uniqueActions).toBe(3)
    // From 2024-01-01 09:00 to 2024-01-02 10:00 -> ceil(25h/24h)=2 -> actionsPerDay=4/2=2
    expect(summary!.actionsPerDay).toBe(2)
    expect(summary!.mostFrequentAction).toBe('view')
    // Sessions: [9:00, 9:10], [9:45], [next day] => 3 sessions => 4/3 = 1.33
    expect(summary!.averageActionsPerSession).toBe(1.33)
  })

  it('ensures actionsPerDay minimum 1 and averageActionsPerSession for a single activity', () => {
    const activities = [
      makeAct('1', 'solo', 'login', L(2024, 2, 10, 12, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('solo')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(1)
    expect(summary!.uniqueActions).toBe(1)
    expect(summary!.actionsPerDay).toBe(1)
    expect(summary!.mostFrequentAction).toBe('login')
    expect(summary!.averageActionsPerSession).toBe(1)
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('groups by day (default) and computes growth rates', () => {
    const activities = [
      makeAct('1', 'u1', 'login', L(2024, 1, 1, 9)),
      makeAct('2', 'u1', 'view', L(2024, 1, 1, 9, 10)),
      makeAct('3', 'u1', 'view', L(2024, 1, 1, 9, 45)),
      makeAct('4', 'u1', 'logout', L(2024, 1, 2, 10))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trend = dashboard.getActivityTrends('u1')
    expect(trend.length).toBe(2)
    expect(trend[0]).toEqual({ period: '2024-01-01', count: 3, growthRate: 0 })
    expect(trend[1].period).toBe('2024-01-02')
    expect(trend[1].count).toBe(1)
    // Growth rate ((1-3)/3)*100 = -66.67
    expect(trend[1].growthRate).toBe(-66.67)
  })

  it('groups by hour with zero-padded hour and sorted periods', () => {
    const activities = [
      makeAct('1', 'u1', 'login', L(2024, 1, 1, 9, 0)),
      makeAct('2', 'u1', 'view', L(2024, 1, 1, 9, 20)),
      makeAct('3', 'u1', 'view', L(2024, 1, 1, 10, 0)),
      makeAct('4', 'u1', 'logout', L(2024, 1, 2, 9, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trend = dashboard.getActivityTrends('u1', 'hour')
    expect(trend.map(t => t.period)).toEqual([
      '2024-01-01 09:00',
      '2024-01-01 10:00',
      '2024-01-02 09:00'
    ])
    expect(trend[0].count).toBe(2)
    // Growth rate second vs first: ((1-2)/2)*100 = -50.00
    expect(trend[1].growthRate).toBe(-50)
  })

  it('groups by week with "YYYY-Wxx" keys and computes growth vs previous non-empty period', () => {
    const activities = [
      makeAct('a', 'uw', 'view', L(2024, 1, 1, 10)), // week 01
      makeAct('b', 'uw', 'click', L(2024, 1, 2, 12)), // same week 01
      makeAct('c', 'uw', 'view', L(2024, 1, 8, 9)) // next week 02
    ]
    const dashboard = new ActivityDashboard(activities)
    const trend = dashboard.getActivityTrends('uw', 'week')
    expect(trend.length).toBe(2)
    expect(trend[0].period).toBe('2024-W01')
    expect(trend[0].count).toBe(2)
    expect(trend[0].growthRate).toBe(0)
    expect(trend[1].period).toBe('2024-W02')
    expect(trend[1].count).toBe(1)
    expect(trend[1].growthRate).toBe(-50)
  })

  it('groups by month and sorts chronologically', () => {
    const activities = [
      makeAct('1', 'um', 'view', L(2024, 1, 15, 10)),
      makeAct('2', 'um', 'view', L(2024, 2, 1, 8)),
      makeAct('3', 'um', 'view', L(2024, 2, 20, 18))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trend = dashboard.getActivityTrends('um', 'month')
    expect(trend.map(t => t.period)).toEqual(['2024-01', '2024-02'])
    expect(trend[0].count).toBe(1)
    expect(trend[1].count).toBe(2)
    expect(trend[1].growthRate).toBe(100)
  })

  it('returns empty array when no activities for user', () => {
    const dashboard = new ActivityDashboard([
      makeAct('1', 'x', 'login', L(2024, 1, 1, 9))
    ])
    expect(dashboard.getActivityTrends('nope')).toEqual([])
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters by inclusive start and end dates for a specific user', () => {
    const activities = [
      makeAct('1', 'u1', 'login', L(2024, 1, 1, 9, 0)),
      makeAct('2', 'u1', 'view', L(2024, 1, 1, 9, 10)),
      makeAct('3', 'u1', 'view', L(2024, 1, 1, 9, 45)),
      makeAct('4', 'u1', 'logout', L(2024, 1, 2, 10, 0)),
      makeAct('5', 'u2', 'login', L(2024, 1, 1, 9, 10))
    ]
    const dashboard = new ActivityDashboard(activities)
    const start = L(2024, 1, 1, 9, 10)
    const end = L(2024, 1, 1, 9, 45)
    const result = dashboard.filterByDateRange('u1', start, end)
    expect(result.map(r => r.id)).toEqual(['2', '3'])
  })

  it('returns empty array if user has no activities in range', () => {
    const activities = [
      makeAct('1', 'u1', 'login', L(2024, 1, 1, 8)),
      makeAct('2', 'u1', 'view', L(2024, 1, 3, 9))
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.filterByDateRange('u1', L(2024, 1, 1, 9), L(2024, 1, 2, 9))
    expect(result).toEqual([])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.aggregateByAction('nobody')).toEqual([])
  })

  it('aggregates counts, percentages, and occurrence dates; sorted by count desc', () => {
    const a1 = L(2024, 1, 1, 9, 0)
    const a2 = L(2024, 1, 1, 9, 10)
    const a3 = L(2024, 1, 1, 9, 45)
    const a4 = L(2024, 1, 2, 10, 0)
    const activities = [
      makeAct('1', 'u1', 'login', a1),
      makeAct('2', 'u1', 'view', a2),
      makeAct('3', 'u1', 'view', a3),
      makeAct('4', 'u1', 'logout', a4)
    ]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups[0].action).toBe('view')
    expect(groups[0].count).toBe(2)
    expect(groups[0].percentage).toBe(50)
    expect(groups[0].firstOccurrence.getTime()).toBe(a2.getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(a3.getTime())
    // Remaining actions include login and logout with 25% each
    const rest = groups.slice(1)
    const actionNames = rest.map(g => g.action)
    expect(actionNames).toEqual(expect.arrayContaining(['login', 'logout']))
    const percentages = rest.map(g => g.percentage).sort()
    expect(percentages).toEqual([25, 25])
  })
})

describe('ActivityDashboard - getTopActions_old', () => {
  it('ignores the limit parameter and returns all groups sorted by count desc', () => {
    const activities = [
      makeAct('1', 'u1', 'view', L(2024, 1, 1, 9)),
      makeAct('2', 'u1', 'view', L(2024, 1, 1, 10)),
      makeAct('3', 'u1', 'click', L(2024, 1, 1, 11)),
      makeAct('4', 'u1', 'login', L(2024, 1, 1, 12))
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.getTopActions_old('u1', 1)
    expect(result.length).toBe(3)
    expect(result[0].action).toBe('view')
    expect(result[0].count).toBe(2)
    expect(result[0].percentage).toBeCloseTo((2 / 4) * 100, 2)
  })

  it('computes first/last occurrence per action correctly', () => {
    const t1 = L(2024, 3, 1, 8)
    const t2 = L(2024, 3, 1, 9)
    const activities = [
      makeAct('1', 'u1', 'open', t2),
      makeAct('2', 'u1', 'open', t1)
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.getTopActions_old('u1')
    const open = result.find(r => r.action === 'open')!
    expect(open.firstOccurrence.getTime()).toBe(t1.getTime())
    expect(open.lastOccurrence.getTime()).toBe(t2.getTime())
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('returns only the top N actions according to limit', () => {
    const activities = [
      makeAct('1', 'u1', 'view', L(2024, 1, 1, 9)),
      makeAct('2', 'u1', 'view', L(2024, 1, 1, 10)),
      makeAct('3', 'u1', 'click', L(2024, 1, 1, 11)),
      makeAct('4', 'u1', 'login', L(2024, 1, 1, 12))
    ]
    const dashboard = new ActivityDashboard(activities)
    const top1 = dashboard.getTopActions('u1', 1)
    expect(top1.length).toBe(1)
    expect(top1[0].action).toBe('view')

    const top2 = dashboard.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].count).toBe(2)
  })

  it('returns fewer than default limit when not enough action groups', () => {
    const activities = [
      makeAct('1', 'u1', 'only', L(2024, 1, 1, 9))
    ]
    const dashboard = new ActivityDashboard(activities)
    const top = dashboard.getTopActions('u1')
    expect(top.length).toBe(1)
    expect(top[0].action).toBe('only')
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activity', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('ghost')).toBe(0)
  })

  it('computes expected score with volume, diversity, and frequency', () => {
    const activities = [
      makeAct('1', 'u1', 'login', L(2024, 1, 1, 9, 0)),
      makeAct('2', 'u1', 'view', L(2024, 1, 1, 9, 10)),
      makeAct('3', 'u1', 'view', L(2024, 1, 1, 9, 45)),
      makeAct('4', 'u1', 'logout', L(2024, 1, 2, 10, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    // From earlier summary: total=4, unique=3, actionsPerDay=2
    // volume: (4/100)*30=1.2, diversity: (3/10)*30=9, frequency: (2/5)*40=16 => 26.2
    expect(dashboard.calculateEngagementScore('u1')).toBe(26.2)
  })

  it('caps each component and maxes out at 100', () => {
    const manyActs = []
    for (let i = 0; i < 120; i++) {
      // Cycle 12 unique actions
      const action = `a${(i % 12) + 1}`
      manyActs.push(makeAct(`id${i}`, 'heavy', action, L(2024, 5, 10, 12, Math.floor(i / 2))))
    }
    const dashboard = new ActivityDashboard(manyActs)
    // total >= 100 => volumeScore=30
    // unique >= 10 => diversityScore=30
    // actionsPerDay very high => frequencyScore=40
    expect(dashboard.calculateEngagementScore('heavy')).toBe(100)
  })
})