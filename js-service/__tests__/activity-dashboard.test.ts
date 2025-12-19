import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

const makeActivity = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('user-x')
    expect(summary).toBeNull()
  })

  it('calculates totals, unique actions, most frequent, actionsPerDay, and averageActionsPerSession on same day', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'u1', 'view', new Date(2024, 0, 1, 10, 15)),
      makeActivity('3', 'u1', 'view', new Date(2024, 0, 1, 11, 0)), // gap 45 min -> new session
      makeActivity('4', 'u1', 'logout', new Date(2024, 0, 1, 11, 5)),
      // other user should be ignored
      makeActivity('5', 'u2', 'login', new Date(2024, 0, 1, 9, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(4)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.actionsPerDay).toBe(4) // all same day
    expect(summary!.averageActionsPerSession).toBe(2) // 4 actions / 2 sessions
  })

  it('calculates actionsPerDay across multiple days using ceil days difference', () => {
    const activities: Activity[] = [
      makeActivity('1', 'u3', 'a', new Date(2024, 0, 1, 0, 0)),
      makeActivity('2', 'u3', 'b', new Date(2024, 0, 2, 12, 0)),
      makeActivity('3', 'u3', 'c', new Date(2024, 0, 3, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u3')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    // last - first = exactly 2 days -> daysActive = 2 -> 3/2 = 1.5
    expect(summary!.actionsPerDay).toBe(1.5)
  })

  it('selects the first encountered action when there is a tie for most frequent', () => {
    const activities: Activity[] = [
      makeActivity('1', 'uTie', 'A', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'uTie', 'B', new Date(2024, 0, 1, 10, 5)),
      makeActivity('3', 'uTie', 'B', new Date(2024, 0, 1, 10, 10)),
      makeActivity('4', 'uTie', 'A', new Date(2024, 0, 1, 10, 15))
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('uTie')
    expect(summary).not.toBeNull()
    expect(summary!.mostFrequentAction).toBe('A') // tie resolved to first encountered
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array for user with no activities', () => {
    const dashboard = new ActivityDashboard([])
    const trends = dashboard.getActivityTrends('unknown', 'day')
    expect(trends).toEqual([])
  })

  it('groups by day and computes growth rate', () => {
    const activities: Activity[] = [
      makeActivity('1', 'uT1', 'x', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'uT1', 'y', new Date(2024, 0, 2, 9, 0)),
      makeActivity('3', 'uT1', 'y', new Date(2024, 0, 2, 10, 0)),
      makeActivity('4', 'uT1', 'y', new Date(2024, 0, 2, 11, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('uT1', 'day')
    expect(trends.length).toBe(2)
    expect(trends[0]).toEqual({ period: '2024-01-01', count: 1, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2024-01-02', count: 3, growthRate: 200 })
  })

  it('groups by hour and sorts periods, computing negative growth correctly', () => {
    const activities: Activity[] = [
      makeActivity('1', 'uT2', 'x', new Date(2024, 0, 1, 10, 10)),
      makeActivity('2', 'uT2', 'x', new Date(2024, 0, 1, 10, 20)),
      makeActivity('3', 'uT2', 'x', new Date(2024, 0, 1, 11, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('uT2', 'hour')
    expect(trends.length).toBe(2)
    expect(trends[0]).toEqual({ period: '2024-01-01 10:00', count: 2, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2024-01-01 11:00', count: 1, growthRate: -50 })
  })

  it('groups by week and merges activities into same week period', () => {
    const activities: Activity[] = [
      makeActivity('1', 'uTWeek', 'x', new Date(2024, 0, 1, 10, 0)), // Jan 1, 2024 (Mon)
      makeActivity('2', 'uTWeek', 'x', new Date(2024, 0, 3, 12, 0))  // Jan 3, 2024 (Wed)
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('uTWeek', 'week')
    expect(trends.length).toBe(1)
    expect(trends[0].count).toBe(2)
    expect(trends[0].period).toMatch(/^\d{4}-W\d{2}$/)
  })

  it('groups by month and computes growth across months', () => {
    const activities: Activity[] = [
      makeActivity('1', 'uTMonth', 'x', new Date(2024, 0, 15, 10, 0)), // Jan
      makeActivity('2', 'uTMonth', 'x', new Date(2024, 1, 1, 10, 0)),  // Feb
      makeActivity('3', 'uTMonth', 'x', new Date(2024, 1, 2, 10, 0))   // Feb
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('uTMonth', 'month')
    expect(trends.length).toBe(2)
    expect(trends[0]).toEqual({ period: '2024-01', count: 1, growthRate: 0 })
    expect(trends[1]).toEqual({ period: '2024-02', count: 2, growthRate: 100 })
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('returns activities within inclusive date range', () => {
    const activities: Activity[] = [
      makeActivity('1', 'uF', 'a', new Date(2024, 0, 1, 0, 0)),
      makeActivity('2', 'uF', 'b', new Date(2024, 0, 2, 0, 0)),
      makeActivity('3', 'uF', 'c', new Date(2024, 0, 3, 0, 0)),
      makeActivity('4', 'other', 'z', new Date(2024, 0, 2, 0, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const result = dashboard.filterByDateRange('uF', new Date(2024, 0, 2, 0, 0), new Date(2024, 0, 3, 0, 0))
    expect(result.map(r => r.id)).toEqual(['2', '3'])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array when no activities for user', () => {
    const dashboard = new ActivityDashboard([])
    const agg = dashboard.aggregateByAction('nope')
    expect(agg).toEqual([])
  })

  it('groups actions with counts, percentages, and occurrence dates; sorted by count desc', () => {
    const v1 = new Date(2024, 0, 1, 10, 0)
    const v2 = new Date(2024, 0, 1, 11, 0)
    const v3 = new Date(2024, 0, 1, 12, 0)
    const c1 = new Date(2024, 0, 1, 13, 0)
    const activities: Activity[] = [
      makeActivity('1', 'uAgg', 'view', v1),
      makeActivity('2', 'uAgg', 'view', v2),
      makeActivity('3', 'uAgg', 'view', v3),
      makeActivity('4', 'uAgg', 'click', c1)
    ]
    const dashboard = new ActivityDashboard(activities)
    const agg = dashboard.aggregateByAction('uAgg')
    expect(agg.length).toBe(2)
    expect(agg[0].action).toBe('view')
    expect(agg[0].count).toBe(3)
    expect(agg[0].percentage).toBe(75)
    expect(agg[0].firstOccurrence).toEqual(v1)
    expect(agg[0].lastOccurrence).toEqual(v3)
    expect(agg[1].action).toBe('click')
    expect(agg[1].count).toBe(1)
    expect(agg[1].percentage).toBe(25)
  })
})

describe('ActivityDashboard - getTopActions and getTopActions_old', () => {
  it('getTopActions applies limit to aggregated actions', () => {
    const activities: Activity[] = [
      makeActivity('1', 'uTop', 'A', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'uTop', 'A', new Date(2024, 0, 1, 11, 0)),
      makeActivity('3', 'uTop', 'B', new Date(2024, 0, 1, 12, 0)),
      makeActivity('4', 'uTop', 'C', new Date(2024, 0, 1, 13, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const top1 = dashboard.getTopActions('uTop', 1)
    expect(top1.length).toBe(1)
    expect(top1[0].action).toBe('A')
  })

  it('getTopActions with limit larger than available returns all groups', () => {
    const activities: Activity[] = [
      makeActivity('1', 'uTop2', 'A', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'uTop2', 'B', new Date(2024, 0, 1, 11, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const top = dashboard.getTopActions('uTop2', 10)
    expect(top.length).toBe(2)
    expect(top.map(t => t.action).sort()).toEqual(['A', 'B'])
  })

  it('getTopActions with limit 0 returns empty array', () => {
    const activities: Activity[] = [
      makeActivity('1', 'uTop3', 'A', new Date(2024, 0, 1, 10, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const top = dashboard.getTopActions('uTop3', 0)
    expect(top).toEqual([])
  })

  it('getTopActions_old returns all groups and ignores the limit parameter', () => {
    const activities: Activity[] = [
      makeActivity('1', 'uOld', 'A', new Date(2024, 0, 1, 10, 0)),
      makeActivity('2', 'uOld', 'A', new Date(2024, 0, 1, 11, 0)),
      makeActivity('3', 'uOld', 'B', new Date(2024, 0, 1, 12, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const topOld = dashboard.getTopActions_old('uOld', 1)
    expect(topOld.length).toBe(2)
    expect(topOld[0].action).toBe('A')
    expect(topOld[1].action).toBe('B')
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 for user with no activities', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('none')).toBe(0)
  })

  it('computes engagement score using volume, diversity, and frequency', () => {
    const userId = 'uScore'
    // 10 actions, 3 unique actions, across exactly 2 days -> actionsPerDay = 5
    const start = new Date(2024, 0, 1, 0, 0)
    const end = new Date(2024, 0, 3, 0, 0)
    const actions = ['a', 'b', 'c']
    const activities: Activity[] = []
    for (let i = 0; i < 5; i++) {
      activities.push(makeActivity(`s${i}`, userId, actions[i % 3], new Date(2024, 0, 1, 0, i)))
    }
    for (let i = 0; i < 5; i++) {
      activities.push(makeActivity(`e${i}`, userId, actions[i % 3], new Date(2024, 0, 3, 0, i)))
    }
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary(userId)
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(10)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.actionsPerDay).toBe(5)

    // volume: min(10/100,1)*30 = 3
    // diversity: min(3/10,1)*30 = 9
    // frequency: min(5/5,1)*40 = 40
    // total = 52
    const score = dashboard.calculateEngagementScore(userId)
    expect(score).toBe(52)
  })
})