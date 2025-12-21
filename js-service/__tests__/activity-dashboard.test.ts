import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, type Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function makeActivity(id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity {
  return { id, user_id, action, timestamp: date, metadata }
}

function localPeriodKey(date: Date, periodType: 'hour' | 'day' | 'week' | 'month' | string): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  const hour = String(date.getHours()).padStart(2, '0')
  const getWeekNumber = (d: Date): number => {
    const firstDayOfYear = new Date(d.getFullYear(), 0, 1)
    const pastDaysOfYear = (d.getTime() - firstDayOfYear.getTime()) / 86400000
    return Math.ceil((pastDaysOfYear + firstDayOfYear.getDay() + 1) / 7)
  }
  switch (periodType) {
    case 'hour':
      return `${year}-${month}-${day} ${hour}:00`
    case 'day':
      return `${year}-${month}-${day}`
    case 'week': {
      const weekNumber = getWeekNumber(date)
      return `${year}-W${String(weekNumber).padStart(2, '0')}`
    }
    case 'month':
      return `${year}-${month}`
    default:
      return `${year}-${month}-${day}`
  }
}

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const acts = [
      makeActivity('1', 'u2', 'login', new Date(2024, 0, 1, 10)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const res = dashboard.getUserSummary('u1')
    expect(res).toBeNull()
  })

  it('computes totals, unique actions, most frequent action, actionsPerDay and avg per session for single day', () => {
    const user = 'u1'
    const base = new Date(2024, 0, 1, 10, 0, 0)
    const acts: Activity[] = [
      makeActivity('1', user, 'login', new Date(base)),
      makeActivity('2', user, 'click', new Date(2024, 0, 1, 10, 5, 0)),
      makeActivity('3', user, 'login', new Date(2024, 0, 1, 10, 10, 0)),
      makeActivity('4', user, 'login', new Date(2024, 0, 1, 10, 15, 0)),
      makeActivity('5', 'other', 'login', new Date(2024, 0, 2, 10, 0, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const res = dashboard.getUserSummary(user)
    expect(res).not.toBeNull()
    expect(res!.totalActions).toBe(4)
    expect(res!.uniqueActions).toBe(2)
    expect(res!.mostFrequentAction).toBe('login')
    expect(res!.actionsPerDay).toBe(4) // all within same day window
    expect(res!.averageActionsPerSession).toBe(4) // no session gap > 30 minutes
  })

  it('calculates daysActive via ceil and actionsPerDay rounding across multiple days', () => {
    const user = 'u1'
    const acts: Activity[] = [
      makeActivity('1', user, 'a', new Date(2024, 0, 1, 10, 0, 0)),
      makeActivity('2', user, 'b', new Date(2024, 0, 1, 12, 0, 0)),
      makeActivity('3', user, 'a', new Date(2024, 0, 2, 12, 0, 0)), // 26 hours after first -> daysActive=2
    ]
    const dashboard = new ActivityDashboard(acts)
    const res = dashboard.getUserSummary(user)
    expect(res).not.toBeNull()
    expect(res!.totalActions).toBe(3)
    expect(res!.uniqueActions).toBe(2)
    expect(res!.actionsPerDay).toBe(1.5) // 3 / 2
    expect(res!.mostFrequentAction).toBe('a')
  })

  it('calculates average actions per session with 30 minute session gaps', () => {
    const user = 'u1'
    const acts: Activity[] = [
      makeActivity('1', user, 'a', new Date(2024, 0, 1, 10, 0, 0)),
      makeActivity('2', user, 'a', new Date(2024, 0, 1, 10, 10, 0)),
      makeActivity('3', user, 'a', new Date(2024, 0, 1, 10, 45, 0)), // 35 minutes after previous -> new session
      makeActivity('4', user, 'a', new Date(2024, 0, 1, 10, 50, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const res = dashboard.getUserSummary(user)
    expect(res).not.toBeNull()
    // 4 actions over 2 sessions => 2.00
    expect(res!.averageActionsPerSession).toBe(2)
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('returns empty when no activities for user', () => {
    const dashboard = new ActivityDashboard([])
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })

  it('groups by day and computes growth rates between periods', () => {
    const user = 'u1'
    const acts: Activity[] = [
      makeActivity('1', user, 'a', new Date(2024, 0, 1, 10, 0, 0)),
      makeActivity('2', user, 'b', new Date(2024, 0, 1, 11, 0, 0)),
      makeActivity('3', user, 'a', new Date(2024, 0, 2, 9, 0, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends(user, 'day')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe(localPeriodKey(acts[0].timestamp, 'day'))
    expect(trends[0].count).toBe(2)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].period).toBe(localPeriodKey(acts[2].timestamp, 'day'))
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50) // (1-2)/2 * 100 = -50.00
  })

  it('groups by hour with correct formatting and sorting', () => {
    const user = 'u1'
    const a1 = makeActivity('1', user, 'a', new Date(2024, 0, 1, 10, 5, 0))
    const a2 = makeActivity('2', user, 'a', new Date(2024, 0, 1, 10, 55, 0))
    const a3 = makeActivity('3', user, 'a', new Date(2024, 0, 1, 11, 0, 0))
    const dashboard = new ActivityDashboard([a3, a1, a2]) // unsorted input
    const trends = dashboard.getActivityTrends(user, 'hour')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe(localPeriodKey(a1.timestamp, 'hour'))
    expect(trends[0].count).toBe(2)
    expect(trends[1].period).toBe(localPeriodKey(a3.timestamp, 'hour'))
    expect(trends[1].count).toBe(1)
  })

  it('groups by month and sorts keys ascending', () => {
    const user = 'u1'
    const jan = makeActivity('1', user, 'a', new Date(2024, 0, 31, 23, 0, 0))
    const feb = makeActivity('2', user, 'a', new Date(2024, 1, 1, 0, 0, 0))
    const dashboard = new ActivityDashboard([feb, jan])
    const trends = dashboard.getActivityTrends(user, 'month')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe(localPeriodKey(jan.timestamp, 'month'))
    expect(trends[1].period).toBe(localPeriodKey(feb.timestamp, 'month'))
  })

  it('groups by week using generated week keys', () => {
    const user = 'u1'
    const d1 = makeActivity('1', user, 'a', new Date(2024, 0, 1, 10, 0, 0))
    const d2 = makeActivity('2', user, 'a', new Date(2024, 0, 10, 10, 0, 0))
    const dashboard = new ActivityDashboard([d1, d2])
    const trends = dashboard.getActivityTrends(user, 'week')
    expect(trends.length).toBe(2)
    expect(trends[0].period.startsWith('2024-W')).toBe(true)
    expect(trends[1].period.startsWith('2024-W')).toBe(true)
    expect(trends[0].count).toBe(1)
    expect(trends[1].count).toBe(1)
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('includes activities on the inclusive boundaries', () => {
    const user = 'u1'
    const a1 = makeActivity('1', user, 'a', new Date(2024, 0, 1, 10, 0, 0))
    const a2 = makeActivity('2', user, 'a', new Date(2024, 0, 1, 12, 0, 0))
    const a3 = makeActivity('3', user, 'a', new Date(2024, 0, 2, 12, 0, 0))
    const dashboard = new ActivityDashboard([a1, a2, a3])
    const res = dashboard.filterByDateRange(user, new Date(2024, 0, 1, 10, 0, 0), new Date(2024, 0, 1, 12, 0, 0))
    expect(res.map(a => a.id)).toEqual(['1', '2'])
  })

  it('excludes activities outside the range and for other users', () => {
    const user = 'u1'
    const a1 = makeActivity('1', user, 'a', new Date(2024, 0, 1, 9, 59, 59))
    const a2 = makeActivity('2', user, 'a', new Date(2024, 0, 1, 10, 0, 0))
    const a3 = makeActivity('3', 'u2', 'a', new Date(2024, 0, 1, 10, 30, 0))
    const a4 = makeActivity('4', user, 'a', new Date(2024, 0, 1, 11, 0, 1))
    const dashboard = new ActivityDashboard([a1, a2, a3, a4])
    const res = dashboard.filterByDateRange(user, new Date(2024, 0, 1, 10, 0, 0), new Date(2024, 0, 1, 11, 0, 0))
    expect(res.map(a => a.id)).toEqual(['2'])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('groups actions with counts, percentages, first/last occurrences and sorts by count desc', () => {
    const user = 'u1'
    const acts: Activity[] = [
      makeActivity('1', user, 'A', new Date(2024, 0, 1, 10, 0, 0)),
      makeActivity('2', user, 'B', new Date(2024, 0, 1, 10, 5, 0)),
      makeActivity('3', user, 'A', new Date(2024, 0, 1, 10, 10, 0)),
      makeActivity('4', user, 'A', new Date(2024, 0, 1, 10, 20, 0)),
      makeActivity('5', user, 'B', new Date(2024, 0, 1, 10, 25, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const res = dashboard.aggregateByAction(user)
    expect(res.length).toBe(2)
    // Sorted by count desc => 'A' first (3 of 5 -> 60.00%)
    expect(res[0].action).toBe('A')
    expect(res[0].count).toBe(3)
    expect(res[0].percentage).toBe(60)
    expect(res[0].firstOccurrence.getTime()).toBe(new Date(2024, 0, 1, 10, 0, 0).getTime())
    expect(res[0].lastOccurrence.getTime()).toBe(new Date(2024, 0, 1, 10, 20, 0).getTime())
    // 'B' group
    expect(res[1].action).toBe('B')
    expect(res[1].count).toBe(2)
    expect(res[1].percentage).toBe(40)
    expect(res[1].firstOccurrence.getTime()).toBe(new Date(2024, 0, 1, 10, 5, 0).getTime())
    expect(res[1].lastOccurrence.getTime()).toBe(new Date(2024, 0, 1, 10, 25, 0).getTime())
  })

  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([
      makeActivity('1', 'u2', 'A', new Date(2024, 0, 1, 10, 0, 0)),
    ])
    const res = dashboard.aggregateByAction('u1')
    expect(res).toEqual([])
  })
})

describe('ActivityDashboard.getTopActions_old', () => {
  it('returns all groups sorted by count descending (does not apply limit)', () => {
    const user = 'u1'
    const acts = [
      makeActivity('1', user, 'x', new Date(2024, 0, 1, 10)),
      makeActivity('2', user, 'y', new Date(2024, 0, 1, 11)),
      makeActivity('3', user, 'x', new Date(2024, 0, 1, 12)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const res = dashboard.getTopActions_old(user, 1)
    expect(res.length).toBe(2)
    expect(res[0].action).toBe('x')
    expect(res[0].count).toBe(2)
    expect(res[1].action).toBe('y')
    expect(res[1].count).toBe(1)
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('applies limit and returns top actions by count', () => {
    const user = 'u1'
    const acts: Activity[] = [
      makeActivity('1', user, 'a', new Date(2024, 0, 1, 10)),
      makeActivity('2', user, 'b', new Date(2024, 0, 1, 11)),
      makeActivity('3', user, 'a', new Date(2024, 0, 1, 12)),
      makeActivity('4', user, 'c', new Date(2024, 0, 1, 13)),
      makeActivity('5', user, 'a', new Date(2024, 0, 1, 14)),
      makeActivity('6', user, 'b', new Date(2024, 0, 1, 15)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const res = dashboard.getTopActions(user, 2)
    expect(res.length).toBe(2)
    expect(res[0].action).toBe('a')
    expect(res[0].count).toBe(3)
    expect(res[1].action).toBe('b')
    expect(res[1].count).toBe(2)
  })

  it('returns empty array if user has no actions', () => {
    const dashboard = new ActivityDashboard([])
    const res = dashboard.getTopActions('u1', 3)
    expect(res).toEqual([])
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 when user has no summary', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('u1')).toBe(0)
  })

  it('computes expected score with rounding to two decimals for higher activity', () => {
    const user = 'u1'
    // 50 actions within the same day, 5 unique actions
    const acts: Activity[] = []
    const base = new Date(2024, 0, 1, 9, 0, 0)
    for (let i = 0; i < 50; i++) {
      const action = `a${(i % 5) + 1}`
      acts.push(makeActivity(String(i + 1), user, action, new Date(2024, 0, 1, 9, Math.floor(i / 2), 0)))
    }
    const dashboard = new ActivityDashboard(acts)
    const score = dashboard.calculateEngagementScore(user)
    // volume: min(50/100,1)*30 = 15
    // diversity: min(5/10,1)*30 = 15
    // frequency: min(50/5,1)*40 = 40
    // total = 70.00
    expect(score).toBe(70)
  })

  it('computes expected score with fractional components and toFixed rounding', () => {
    const user = 'u1'
    const acts: Activity[] = [
      makeActivity('1', user, 'a', new Date(2024, 0, 1, 10, 0, 0)),
      makeActivity('2', user, 'b', new Date(2024, 0, 2, 10, 0, 0)), // 24h apart -> daysActive=1 (ceil(1) => 1)
      makeActivity('3', user, 'a', new Date(2024, 0, 2, 10, 1, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const score = dashboard.calculateEngagementScore(user)
    // totalActions=3 => volume = (3/100)*30 = 0.9
    // unique=2 => diversity = (2/10)*30 = 6
    // actionsPerDay: first 1/1 10:00 -> last 1/2 10:01 diff slightly > 1 day => ceil(>1) = 2 daysActive, oh careful
    // adjust to ensure daysActive=2; compute expected accordingly:
    // With the given times: diff slightly > 1 day => daysActive=2, actionsPerDay=3/2=1.5
    // frequency = (1.5/5)*40 = 12
    // total = 0.9 + 6 + 12 = 18.9
    expect(score).toBe(18.9)
  })
})

describe('ActivityDashboard.getActivityTrends sorting with unsorted input', () => {
  it('sorts periods lexicographically which aligns to chronological for the given formats', () => {
    const user = 'u1'
    const d1 = new Date(2024, 0, 3, 12)
    const d2 = new Date(2024, 0, 1, 12)
    const d3 = new Date(2024, 0, 2, 12)
    const acts: Activity[] = [
      makeActivity('1', user, 'a', d1),
      makeActivity('2', user, 'a', d2),
      makeActivity('3', user, 'a', d3),
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends(user, 'day')
    const expectedOrder = [d2, d3, d1].map(d => localPeriodKey(d, 'day'))
    expect(trends.map(t => t.period)).toEqual(expectedOrder)
  })
})