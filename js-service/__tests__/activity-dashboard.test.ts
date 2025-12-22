import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

type Act = {
  id: string
  user_id: string
  action: string
  timestamp: Date
  metadata?: Record<string, any>
}

const act = (id: string, user: string, action: string, date: Date): Act => ({
  id,
  user_id: user,
  action,
  timestamp: date
})

const baseActivities = (): Act[] => [
  // u1 actions
  act('1', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
  act('2', 'u1', 'view', new Date(2024, 0, 1, 9, 5)),
  act('3', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
  act('4', 'u1', 'click', new Date(2024, 0, 1, 10, 0)),
  act('5', 'u1', 'logout', new Date(2024, 0, 1, 12, 0)),
  act('6', 'u1', 'login', new Date(2024, 0, 2, 9, 0)),
  act('7', 'u1', 'view', new Date(2024, 0, 2, 9, 15)),
  act('8', 'u1', 'view', new Date(2024, 0, 2, 9, 45)),
  act('9', 'u1', 'purchase', new Date(2024, 0, 3, 11, 0)),
  // other user
  act('10', 'u2', 'view', new Date(2024, 0, 1, 8, 0))
]

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard(baseActivities())
    const res = dash.getUserSummary('no-user')
    expect(res).toBeNull()
  })

  it('computes correct summary for a user with activities', () => {
    const dash = new ActivityDashboard(baseActivities())
    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    expect(res!.totalActions).toBe(9)
    expect(res!.uniqueActions).toBe(5)
    expect(res!.actionsPerDay).toBe(3) // 9 actions over 3 days (ceil delta across 3 days)
    expect(res!.mostFrequentAction).toBe('view')
    expect(res!.averageActionsPerSession).toBe(1.8) // 9 actions over 5 sessions
  })

  it('uses at least 1 day when all actions occur the same day (actionsPerDay)', () => {
    const sameDayActs: Act[] = [
      act('a1', 'u4', 'login', new Date(2024, 0, 1, 10, 0)),
      act('a2', 'u4', 'view', new Date(2024, 0, 1, 10, 5))
    ]
    const dash = new ActivityDashboard(sameDayActs)
    const res = dash.getUserSummary('u4')
    expect(res).not.toBeNull()
    expect(res!.actionsPerDay).toBe(2) // total actions over at least 1 day
  })

  it('calculates average actions per session with 30-minute threshold', () => {
    const acts: Act[] = [
      act('b1', 'u3', 'login', new Date(2024, 0, 1, 10, 0)),
      act('b2', 'u3', 'view', new Date(2024, 0, 1, 10, 20)),
      act('b3', 'u3', 'view', new Date(2024, 0, 1, 10, 50)) // 30 min gap, still same session
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.getUserSummary('u3')
    expect(res).not.toBeNull()
    expect(res!.averageActionsPerSession).toBe(3) // all within one session
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('returns empty array when no activities for user', () => {
    const dash = new ActivityDashboard(baseActivities())
    const res = dash.getActivityTrends('no-user', 'day')
    expect(res).toEqual([])
  })

  it('groups by day and computes growth rates', () => {
    const dash = new ActivityDashboard(baseActivities())
    const res = dash.getActivityTrends('u1', 'day')
    expect(res.length).toBe(3)
    expect(res[0]).toEqual({ period: '2024-01-01', count: 5, growthRate: 0 })
    expect(res[1].period).toBe('2024-01-02')
    expect(res[1].count).toBe(3)
    expect(res[1].growthRate).toBe(-40) // (3-5)/5*100 = -40
    expect(res[2].period).toBe('2024-01-03')
    expect(res[2].count).toBe(1)
    expect(res[2].growthRate).toBe(-66.67) // (1-3)/3*100 = -66.67
  })

  it('groups by hour with formatted period keys', () => {
    const dash = new ActivityDashboard(baseActivities())
    const res = dash.getActivityTrends('u1', 'hour')
    const periods = res.map(r => r.period)
    expect(periods).toEqual([
      '2024-01-01 09:00',
      '2024-01-01 10:00',
      '2024-01-01 12:00',
      '2024-01-02 09:00',
      '2024-01-03 11:00'
    ])
    const counts = res.map(r => r.count)
    expect(counts).toEqual([3, 1, 1, 3, 1])
    expect(res[0].growthRate).toBe(0)
    expect(res[1].growthRate).toBe(-66.67)
  })

  it('groups by week and sorts periods ascending', () => {
    const acts: Act[] = [
      act('w1', 'uWeek', 'login', new Date(2024, 0, 1, 9, 0)), // 2024-W01
      act('w2', 'uWeek', 'view', new Date(2024, 0, 1, 10, 0)),  // 2024-W01
      act('w3', 'uWeek', 'view', new Date(2024, 0, 8, 9, 0))    // 2024-W02
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.getActivityTrends('uWeek', 'week')
    expect(res.map(r => r.period)).toEqual(['2024-W01', '2024-W02'])
    expect(res.map(r => r.count)).toEqual([2, 1])
    expect(res[1].growthRate).toBe(-50)
  })

  it('groups by month and computes growth', () => {
    const acts: Act[] = [
      act('m1', 'uMonth', 'login', new Date(2024, 0, 1, 9, 0)), // Jan
      act('m2', 'uMonth', 'view', new Date(2024, 0, 15, 10, 0)), // Jan
      act('m3', 'uMonth', 'view', new Date(2024, 1, 1, 9, 0)), // Feb
      act('m4', 'uMonth', 'click', new Date(2024, 1, 2, 9, 0)), // Feb
      act('m5', 'uMonth', 'logout', new Date(2024, 1, 3, 9, 0)) // Feb
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.getActivityTrends('uMonth', 'month')
    expect(res.map(r => r.period)).toEqual(['2024-01', '2024-02'])
    expect(res.map(r => r.count)).toEqual([2, 3])
    expect(res[1].growthRate).toBe(50)
  })

  it('month grouping sorts keys even when activities are out of chronological order', () => {
    const acts: Act[] = [
      act('mm2', 'uMonth2', 'view', new Date(2024, 1, 10, 12, 0)), // Feb
      act('mm1', 'uMonth2', 'login', new Date(2024, 0, 20, 12, 0)) // Jan
    ]
    const dash = new ActivityDashboard(acts)
    const res = dash.getActivityTrends('uMonth2', 'month')
    expect(res.map(r => r.period)).toEqual(['2024-01', '2024-02'])
    expect(res.map(r => r.count)).toEqual([1, 1])
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('filters inclusively between startDate and endDate', () => {
    const dash = new ActivityDashboard(baseActivities())
    const start = new Date(2024, 0, 1, 10, 0) // include
    const end = new Date(2024, 0, 2, 9, 15)   // include
    const res = dash.filterByDateRange('u1', start, end)
    const ids = res.map(a => a.id)
    expect(ids.sort()).toEqual(['4', '5', '6', '7']) // 10:00, 12:00, 09:00, 09:15
  })

  it('returns empty when no activities fall within range', () => {
    const dash = new ActivityDashboard(baseActivities())
    const start = new Date(2025, 0, 1, 0, 0)
    const end = new Date(2025, 0, 2, 0, 0)
    const res = dash.filterByDateRange('u1', start, end)
    expect(res).toEqual([])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('aggregates counts, percentages, first and last occurrences, sorted by count desc', () => {
    const dash = new ActivityDashboard(baseActivities())
    const groups = dash.aggregateByAction('u1')
    expect(groups.length).toBe(5)
    expect(groups[0].action).toBe('view')
    expect(groups[0].count).toBe(4)
    expect(groups[0].percentage).toBe(44.44) // 4/9*100
    expect(groups[1].action).toBe('login')
    expect(groups[1].count).toBe(2)
    expect(groups[1].percentage).toBe(22.22)

    const viewGroup = groups.find(g => g.action === 'view')!
    expect(viewGroup.firstOccurrence.getTime()).toBe(new Date(2024, 0, 1, 9, 5).getTime())
    expect(viewGroup.lastOccurrence.getTime()).toBe(new Date(2024, 0, 2, 9, 45).getTime())
  })
})

describe('ActivityDashboard.getTopActions and getTopActions_old', () => {
  it('getTopActions returns limited number of top groups', () => {
    const dash = new ActivityDashboard(baseActivities())
    const top2 = dash.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('view')
    expect(top2[1].action).toBe('login')
  })

  it('getTopActions returns all groups when limit exceeds available', () => {
    const dash = new ActivityDashboard(baseActivities())
    const top10 = dash.getTopActions('u1', 10)
    expect(top10.length).toBe(5)
  })

  it('getTopActions_old returns all groups and ignores limit parameter', () => {
    const dash = new ActivityDashboard(baseActivities())
    const res = dash.getTopActions_old('u1', 1)
    expect(res.length).toBe(5) // distinct actions
    expect(res[0].action).toBe('view')
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 for users without activity', () => {
    const dash = new ActivityDashboard(baseActivities())
    expect(dash.calculateEngagementScore('no-user')).toBe(0)
  })

  it('computes score based on volume, diversity, and frequency', () => {
    const dash = new ActivityDashboard(baseActivities())
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(41.7) // volume 2.7 + diversity 15 + frequency 24
  })
})

describe('ActivityDashboard.getActivityTrends growth rate for first period', () => {
  it('sets growthRate to 0 for the first period', () => {
    const dash = new ActivityDashboard(baseActivities())
    const res = dash.getActivityTrends('u1', 'day')
    expect(res[0].growthRate).toBe(0)
  })
})