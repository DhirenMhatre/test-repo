import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function makeActivity(id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity {
  return { id, user_id, action, timestamp: date, metadata }
}

function pad(n: number): string {
  return String(n).padStart(2, '0')
}

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, mostFrequentAction, actionsPerDay and averageActionsPerSession for same-day activities', () => {
    const d1 = new Date(2023, 0, 1, 9, 0, 0)
    const d2 = new Date(2023, 0, 1, 9, 10, 0)
    const d3 = new Date(2023, 0, 1, 9, 20, 0)
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'login', d1),
      makeActivity('2', 'u1', 'view', d2),
      makeActivity('3', 'u1', 'view', d3),
      makeActivity('4', 'u2', 'logout', d1) // different user
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    expect(summary!.uniqueActions).toBe(2)
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.actionsPerDay).toBe(3) // same day => daysActive = 1
    expect(summary!.averageActionsPerSession).toBe(3) // within 30min => 1 session, 3/1 = 3.00
  })

  it('uses ceil window for daysActive across multiple days (actionsPerDay rounded to 2 decimals)', () => {
    const d1 = new Date(2023, 0, 1, 0, 0, 0)      // Jan 1 00:00
    const d2 = new Date(2023, 0, 2, 12, 0, 0)     // Jan 2 12:00 -> 36 hours => ceil(1.5) => 2 daysActive
    const activities: Activity[] = [
      makeActivity('a1', 'u1', 'a', d1),
      makeActivity('a2', 'u1', 'b', new Date(2023, 0, 1, 1, 0, 0)),
      makeActivity('a3', 'u1', 'a', new Date(2023, 0, 2, 11, 59, 0)),
      makeActivity('a4', 'u1', 'b', d2)
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(4)
    expect(summary!.actionsPerDay).toBe(2) // 4 / 2 = 2.00
  })

  it('calculates averageActionsPerSession using 30-minute gaps', () => {
    const base = new Date(2023, 0, 1, 10, 0, 0)
    const within = (mins: number) => new Date(base.getFullYear(), base.getMonth(), base.getDate(), base.getHours(), base.getMinutes() + mins, 0)
    // Activities at 10:00, 10:20 (same session), 11:00 (new session), 11:20 (same session), 12:00 (new session)
    const activities: Activity[] = [
      makeActivity('a1', 'u1', 'x', within(0)),
      makeActivity('a2', 'u1', 'x', within(20)),
      makeActivity('a3', 'u1', 'y', within(60)),
      makeActivity('a4', 'u1', 'y', within(80)),
      makeActivity('a5', 'u1', 'z', within(120))
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    // Sessions = 3, total = 5 => 1.67
    expect(summary!.averageActionsPerSession).toBe(1.67)
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array if user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })

  it('groups by day with correct ordering and growthRate', () => {
    const d1a = new Date(2023, 0, 1, 9, 0, 0)
    const d1b = new Date(2023, 0, 1, 10, 0, 0)
    const d2 = new Date(2023, 0, 2, 9, 0, 0)
    const d3a = new Date(2023, 0, 3, 8, 0, 0)
    const d3b = new Date(2023, 0, 3, 9, 0, 0)
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d1a),
      makeActivity('2', 'u1', 'b', d1b),
      makeActivity('3', 'u1', 'c', d2),
      makeActivity('4', 'u1', 'd', d3a),
      makeActivity('5', 'u1', 'e', d3b)
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends).toHaveLength(3)
    const dayKey = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    expect(trends[0].period).toBe(dayKey(d1a))
    expect(trends[0].count).toBe(2)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].period).toBe(dayKey(d2))
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50)
    expect(trends[2].period).toBe(dayKey(d3a))
    expect(trends[2].count).toBe(2)
    expect(trends[2].growthRate).toBe(100)
  })

  it('groups by hour with correctly formatted period keys', () => {
    const d1 = new Date(2023, 0, 1, 9, 15, 0)
    const d2 = new Date(2023, 0, 1, 10, 45, 0)
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d1),
      makeActivity('2', 'u1', 'b', d2)
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'hour')
    const key1 = `${d1.getFullYear()}-${pad(d1.getMonth() + 1)}-${pad(d1.getDate())} ${pad(d1.getHours())}:00`
    const key2 = `${d2.getFullYear()}-${pad(d2.getMonth() + 1)}-${pad(d2.getDate())} ${pad(d2.getHours())}:00`
    expect(trends.map(t => t.period)).toEqual([key1, key2])
    expect(trends.map(t => t.count)).toEqual([1, 1])
    expect(trends[1].growthRate).toBe(0)
  })

  it('groups by week using getWeekNumber into YYYY-Www', () => {
    const d1 = new Date(2023, 0, 1, 12, 0, 0) // Sunday, week 1 per implementation
    const d2 = new Date(2023, 0, 8, 12, 0, 0) // Next Sunday, week 2
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d1),
      makeActivity('2', 'u1', 'b', d2)
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends).toHaveLength(2)
    expect(trends[0].period).toBe(`${d1.getFullYear()}-W01`)
    expect(trends[1].period).toBe(`${d2.getFullYear()}-W02`)
    expect(trends[0].count).toBe(1)
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(0)
  })

  it('groups by month into YYYY-MM format', () => {
    const d1 = new Date(2023, 0, 15, 12, 0, 0) // Jan
    const d2 = new Date(2023, 1, 10, 12, 0, 0) // Feb
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d1),
      makeActivity('2', 'u1', 'b', d2),
      makeActivity('3', 'u1', 'c', d2)
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends).toHaveLength(2)
    const m1 = `${d1.getFullYear()}-${pad(d1.getMonth() + 1)}`
    const m2 = `${d2.getFullYear()}-${pad(d2.getMonth() + 1)}`
    expect(trends[0].period).toBe(m1)
    expect(trends[0].count).toBe(1)
    expect(trends[1].period).toBe(m2)
    expect(trends[1].count).toBe(2)
    expect(trends[1].growthRate).toBe(100)
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters activities inclusively by date range', () => {
    const d1 = new Date(2023, 0, 1, 10, 0, 0)
    const d2 = new Date(2023, 0, 1, 12, 0, 0)
    const d3 = new Date(2023, 0, 1, 14, 0, 0)
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', d1),
      makeActivity('2', 'u1', 'b', d2),
      makeActivity('3', 'u1', 'c', d3),
      makeActivity('4', 'u2', 'a', d2)
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.filterByDateRange('u1', d2, d3)
    expect(result.map(r => r.id)).toEqual(['2', '3'])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('aggregates counts, percentages, and first/last occurrence per action sorted by count desc', () => {
    const t1 = new Date(2023, 0, 1, 9, 0, 0)
    const t2 = new Date(2023, 0, 1, 10, 0, 0)
    const t3 = new Date(2023, 0, 1, 11, 0, 0)
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', t1),
      makeActivity('2', 'u1', 'a', t3),
      makeActivity('3', 'u1', 'b', t2),
      makeActivity('4', 'u2', 'a', t2)
    ]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups).toHaveLength(2)

    // Sorted by count desc: 'a' (2) then 'b' (1)
    expect(groups[0].action).toBe('a')
    expect(groups[0].count).toBe(2)
    expect(groups[0].percentage).toBe(66.67)
    expect(groups[0].firstOccurrence.getTime()).toBe(t1.getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(t3.getTime())

    expect(groups[1].action).toBe('b')
    expect(groups[1].count).toBe(1)
    expect(groups[1].percentage).toBe(33.33)
    expect(groups[1].firstOccurrence.getTime()).toBe(t2.getTime())
    expect(groups[1].lastOccurrence.getTime()).toBe(t2.getTime())
  })

  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const groups = dashboard.aggregateByAction('uX')
    expect(groups).toEqual([])
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('returns top N actions by count', () => {
    const base = new Date(2023, 0, 1, 0, 0, 0)
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', base),
      makeActivity('2', 'u1', 'a', new Date(2023, 0, 1, 1, 0, 0)),
      makeActivity('3', 'u1', 'b', new Date(2023, 0, 1, 2, 0, 0)),
      makeActivity('4', 'u1', 'c', new Date(2023, 0, 1, 3, 0, 0)),
      makeActivity('5', 'u1', 'd', new Date(2023, 0, 1, 4, 0, 0)),
      makeActivity('6', 'u1', 'e', new Date(2023, 0, 1, 5, 0, 0)),
      makeActivity('7', 'u1', 'f', new Date(2023, 0, 1, 6, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const top2 = dashboard.getTopActions('u1', 2)
    expect(top2.map(t => t.action)).toEqual(['a', 'b'])
    expect(top2[0].count).toBe(2)
    expect(top2[1].count).toBe(1)
  })

  it('returns up to default limit of 5 when fewer groups exist', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'a', new Date(2023, 0, 1)),
      makeActivity('2', 'u1', 'b', new Date(2023, 0, 1)),
      makeActivity('3', 'u1', 'c', new Date(2023, 0, 1))
    ]
    const dashboard = new ActivityDashboard(activities)
    const top = dashboard.getTopActions('u1')
    expect(top).toHaveLength(3)
    expect(top.map(t => t.action).sort()).toEqual(['a', 'b', 'c'])
  })

  it('returns empty array when no actions exist for user', () => {
    const dashboard = new ActivityDashboard([])
    const top = dashboard.getTopActions('u1')
    expect(top).toEqual([])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no summary', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('missing')).toBe(0)
  })

  it('caps each component at maximum and returns 100 when all at cap', () => {
    const start = new Date(2023, 0, 1, 10, 0, 0)
    const activities: Activity[] = []
    const actions = Array.from({ length: 10 }).map((_, i) => `a${i}`)
    let id = 1
    // 100 actions, 10 unique action types, all within < 24h to keep daysActive = 1
    for (let i = 0; i < 10; i++) {
      for (let j = 0; j < 10; j++) {
        const t = new Date(2023, 0, 1, 10, i, j) // minutes/seconds vary but gaps <= 1 minute
        activities.push(makeActivity(String(id++), 'u1', actions[i], t))
      }
    }
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(100)
  })

  it('computes weighted score with rounding to 2 decimals', () => {
    // 5 actions over ~3.5 days => daysActive = 4 => actionsPerDay = 1.25
    const d1 = new Date(2023, 0, 1, 0, 0, 0)
    const d2 = new Date(2023, 0, 2, 0, 0, 0)
    const d3 = new Date(2023, 0, 3, 0, 0, 0)
    const d4 = new Date(2023, 0, 4, 12, 0, 0) // ensures ceil to 4 days
    const d5 = new Date(2023, 0, 4, 12, 10, 0)
    const activities: Activity[] = [
      makeActivity('1', 'u2', 'a', d1),
      makeActivity('2', 'u2', 'b', d2),
      makeActivity('3', 'u2', 'c', d3),
      makeActivity('4', 'u2', 'a', d4),
      makeActivity('5', 'u2', 'a', d5)
    ]
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('u2')
    // totalActions=5 -> volume=1.5; uniqueActions=3 -> diversity=9; actionsPerDay=1.25 -> frequency=10 => total=20.5
    expect(score).toBe(20.5)
  })
})

describe('ActivityDashboard - additional behaviors', () => {
  it('getUserSummary mostFrequentAction when all actions identical', () => {
    const t = new Date(2024, 5, 1, 12, 0, 0)
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'only', t),
      makeActivity('2', 'u1', 'only', new Date(2024, 5, 1, 13, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.mostFrequentAction).toBe('only')
    expect(summary!.uniqueActions).toBe(1)
  })
})