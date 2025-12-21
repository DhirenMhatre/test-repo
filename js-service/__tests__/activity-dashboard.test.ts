import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

const mkActivity = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata
})

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, actionsPerDay, mostFrequent and averageActionsPerSession (single session)', () => {
    const base = new Date(2023, 0, 1, 9, 0, 0)
    const activities: Activity[] = [
      mkActivity('1', 'u1', 'view', new Date(2023, 0, 1, 9, 0)),
      mkActivity('2', 'u1', 'click', new Date(2023, 0, 1, 9, 5)),
      mkActivity('3', 'u1', 'view', new Date(2023, 0, 1, 9, 10)),
      mkActivity('4', 'u1', 'purchase', new Date(2023, 0, 1, 9, 15)),
      mkActivity('5', 'u1', 'view', new Date(2023, 0, 1, 9, 20))
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(5)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.actionsPerDay).toBe(5) // same day => daysActive = 1
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.averageActionsPerSession).toBe(5) // all within 30 minutes => one session
  })

  it('calculates averageActionsPerSession with gaps > 30 minutes as new sessions', () => {
    const activities: Activity[] = [
      mkActivity('1', 'u1', 'view', new Date(2023, 0, 1, 9, 0)),
      mkActivity('2', 'u1', 'view', new Date(2023, 0, 1, 9, 35)), // >30 min gap => new session
      mkActivity('3', 'u1', 'view', new Date(2023, 0, 1, 9, 36))  // same session as previous
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(1.5) // 3 actions / 2 sessions
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends).toEqual([])
  })

  it('groups by day and computes growth rate between consecutive periods', () => {
    const activities: Activity[] = [
      mkActivity('1', 'u1', 'view', new Date(2023, 4, 1, 10, 0)),
      mkActivity('2', 'u1', 'click', new Date(2023, 4, 1, 12, 0)),
      mkActivity('3', 'u1', 'view', new Date(2023, 4, 2, 9, 0)),
      mkActivity('4', 'u1', 'click', new Date(2023, 4, 2, 10, 0)),
      mkActivity('5', 'u1', 'view', new Date(2023, 4, 2, 11, 0)),
      mkActivity('6', 'u1', 'view', new Date(2023, 4, 2, 12, 0))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends.length).toBe(2)
    expect(trends[0].count).toBe(2)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].count).toBe(4)
    expect(trends[1].growthRate).toBe(100) // ((4-2)/2)*100
  })

  it('groups by hour with formatted period keys', () => {
    const d = new Date(2023, 6, 10)
    const activities: Activity[] = [
      mkActivity('1', 'u1', 'a', new Date(2023, 6, 10, 10, 5)),
      mkActivity('2', 'u1', 'a', new Date(2023, 6, 10, 11, 10)),
      mkActivity('3', 'u1', 'a', new Date(2023, 6, 10, 11, 30))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'hour')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2023-07-10 10:00')
    expect(trends[0].count).toBe(1)
    expect(trends[1].period).toBe('2023-07-10 11:00')
    expect(trends[1].count).toBe(2)
    expect(trends[1].growthRate).toBe(100) // ((2-1)/1)*100
  })

  it('groups by month and sorts periods ascending', () => {
    const activities: Activity[] = [
      mkActivity('1', 'u1', 'a', new Date(2023, 0, 15)),
      mkActivity('2', 'u1', 'a', new Date(2023, 1, 1)),
      mkActivity('3', 'u1', 'a', new Date(2023, 1, 2))
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends.map(t => t.period)).toEqual(['2023-01', '2023-02'])
    expect(trends[0].count).toBe(1)
    expect(trends[1].count).toBe(2)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].growthRate).toBe(100)
  })

  it('groups by week such that same-week dates share the same period key', () => {
    const activities: Activity[] = [
      mkActivity('1', 'u1', 'a', new Date(2023, 0, 3)), // early Jan
      mkActivity('2', 'u1', 'a', new Date(2023, 0, 4)), // same week
      mkActivity('3', 'u1', 'a', new Date(2023, 0, 10)), // next week
      mkActivity('4', 'u1', 'a', new Date(2023, 0, 11))  // next week
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(2)
    expect(trends[0].count).toBe(2)
    expect(trends[1].count).toBe(2)
    expect(trends[0].period).toMatch(/^2023-W\d{2}$/)
    expect(trends[1].period).toMatch(/^2023-W\d{2}$/)
    expect(trends[1].period).not.toBe(trends[0].period)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].growthRate).toBe(0) // prevCount is 2, current is 2 => ((2-2)/2)*100 = 0
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('returns activities within inclusive date range', () => {
    const activities: Activity[] = [
      mkActivity('1', 'u1', 'a', new Date(2023, 0, 1, 8, 0)),
      mkActivity('2', 'u1', 'a', new Date(2023, 0, 1, 9, 0)),  // start
      mkActivity('3', 'u1', 'a', new Date(2023, 0, 1, 10, 0)),
      mkActivity('4', 'u1', 'a', new Date(2023, 0, 1, 11, 0)), // end
      mkActivity('5', 'u1', 'a', new Date(2023, 0, 1, 12, 0)),
      mkActivity('6', 'u2', 'a', new Date(2023, 0, 1, 10, 0))  // different user
    ]
    const dashboard = new ActivityDashboard(activities)
    const start = new Date(2023, 0, 1, 9, 0)
    const end = new Date(2023, 0, 1, 11, 0)
    const filtered = dashboard.filterByDateRange('u1', start, end)
    expect(filtered.map(a => a.id)).toEqual(['2', '3', '4'])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('returns empty array for users with no activities', () => {
    const dashboard = new ActivityDashboard([])
    const groups = dashboard.aggregateByAction('u1')
    expect(groups).toEqual([])
  })

  it('aggregates counts, percentages, first/last occurrence and sorts by count desc', () => {
    const activities: Activity[] = [
      mkActivity('1', 'u1', 'click', new Date(2023, 0, 1, 9, 0)),
      mkActivity('2', 'u1', 'click', new Date(2023, 0, 1, 10, 0)),
      mkActivity('3', 'u1', 'click', new Date(2023, 0, 1, 11, 0)),
      mkActivity('4', 'u1', 'view', new Date(2023, 0, 1, 12, 0)),
      mkActivity('5', 'u2', 'click', new Date(2023, 0, 1, 13, 0)) // different user
    ]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction('u1')
    expect(groups.length).toBe(2)
    expect(groups[0].action).toBe('click')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(75)
    expect(groups[0].firstOccurrence.getTime()).toBe(new Date(2023, 0, 1, 9, 0).getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(new Date(2023, 0, 1, 11, 0).getTime())
    expect(groups[1].action).toBe('view')
    expect(groups[1].count).toBe(1)
    expect(groups[1].percentage).toBe(25)
  })
})

describe('ActivityDashboard.getTopActions_old', () => {
  it('returns all actions sorted by count and ignores limit parameter', () => {
    const activities: Activity[] = [
      mkActivity('1', 'u1', 'a', new Date(2023, 0, 1, 9)),
      mkActivity('2', 'u1', 'b', new Date(2023, 0, 1, 9, 10)),
      mkActivity('3', 'u1', 'a', new Date(2023, 0, 1, 9, 20))
    ]
    const dashboard = new ActivityDashboard(activities)
    const res = dashboard.getTopActions_old('u1', 1)
    expect(res.length).toBe(2)
    expect(res[0].action).toBe('a')
    expect(res[0].count).toBe(2)
    expect(res[1].action).toBe('b')
    expect(res[1].count).toBe(1)
    expect(res[0].firstOccurrence.getTime()).toBe(new Date(2023, 0, 1, 9).getTime())
    expect(res[0].lastOccurrence.getTime()).toBe(new Date(2023, 0, 1, 9, 20).getTime())
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('returns limited top actions using aggregateByAction', () => {
    const activities: Activity[] = [
      mkActivity('1', 'u1', 'x', new Date(2023, 0, 1, 9)),
      mkActivity('2', 'u1', 'x', new Date(2023, 0, 1, 9, 10)),
      mkActivity('3', 'u1', 'y', new Date(2023, 0, 1, 9, 20)),
      mkActivity('4', 'u1', 'z', new Date(2023, 0, 1, 9, 30))
    ]
    const dashboard = new ActivityDashboard(activities)
    const res1 = dashboard.getTopActions('u1', 1)
    expect(res1.length).toBe(1)
    expect(res1[0].action).toBe('x')
    const res2 = dashboard.getTopActions('u1', 2)
    expect(res2.length).toBe(2)
    expect(res2[0].action).toBe('x')
  })

  it('returns empty array when user has no actions', () => {
    const dashboard = new ActivityDashboard([])
    const res = dashboard.getTopActions('uX', 3)
    expect(res).toEqual([])
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 when user has no summary (no activities)', () => {
    const dashboard = new ActivityDashboard([])
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(0)
  })

  it('computes expected score with caps applied per component', () => {
    // 10 total actions, 5 unique, same day so actionsPerDay = 10
    const acts: Activity[] = [
      mkActivity('1', 'u1', 'a1', new Date(2023, 0, 1, 9, 0)),
      mkActivity('2', 'u1', 'a2', new Date(2023, 0, 1, 9, 1)),
      mkActivity('3', 'u1', 'a3', new Date(2023, 0, 1, 9, 2)),
      mkActivity('4', 'u1', 'a4', new Date(2023, 0, 1, 9, 3)),
      mkActivity('5', 'u1', 'a5', new Date(2023, 0, 1, 9, 4)),
      mkActivity('6', 'u1', 'a1', new Date(2023, 0, 1, 9, 5)),
      mkActivity('7', 'u1', 'a2', new Date(2023, 0, 1, 9, 6)),
      mkActivity('8', 'u1', 'a3', new Date(2023, 0, 1, 9, 7)),
      mkActivity('9', 'u1', 'a4', new Date(2023, 0, 1, 9, 8)),
      mkActivity('10', 'u1', 'a5', new Date(2023, 0, 1, 9, 9))
    ]
    const dashboard = new ActivityDashboard(acts)
    const score = dashboard.calculateEngagementScore('u1')
    // volumeScore: 10/100*30 = 3
    // diversityScore: 5/10*30 = 15
    // frequencyScore: min(10/5,1)*40 = 40
    // total = 58
    expect(score).toBe(58)
  })

  it('caps the overall score at 100 when components exceed max', () => {
    // 500 actions, 15 unique, same day => actionsPerDay very high
    const acts: Activity[] = []
    for (let i = 0; i < 500; i++) {
      const action = `a${i % 15}`
      acts.push(mkActivity(String(i + 1), 'u1', action, new Date(2023, 0, 1, 0, i % 60)))
    }
    const dashboard = new ActivityDashboard(acts)
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(100)
  })
})