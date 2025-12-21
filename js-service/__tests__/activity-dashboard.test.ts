import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

describe('ActivityDashboard', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('getUserSummary returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('unknown')
    expect(summary).toBeNull()
  })

  it('getUserSummary computes totals, unique, most frequent, actionsPerDay, averageActionsPerSession', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: new Date(2024, 0, 1, 10, 0, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: new Date(2024, 0, 1, 10, 10, 0) },
      { id: '3', user_id: 'u1', action: 'view', timestamp: new Date(2024, 0, 1, 10, 50, 0) }, // >30 mins gap from 10:10 => new session
      { id: '4', user_id: 'u1', action: 'purchase', timestamp: new Date(2024, 0, 2, 11, 0, 0) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: new Date(2024, 0, 3, 9, 0, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(5)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.actionsPerDay).toBe(2.5) // 5 actions over ceil((~47 hours)/24)=2 days
    expect(summary!.averageActionsPerSession).toBe(1.25) // sessions detected: 4 (gaps > 30 minutes)
  })

  it('calculateEngagementScore returns computed weighted score based on summary', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: new Date(2024, 0, 1, 10, 0, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: new Date(2024, 0, 1, 10, 10, 0) },
      { id: '3', user_id: 'u1', action: 'view', timestamp: new Date(2024, 0, 1, 10, 50, 0) },
      { id: '4', user_id: 'u1', action: 'purchase', timestamp: new Date(2024, 0, 2, 11, 0, 0) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: new Date(2024, 0, 3, 9, 0, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('u1')
    // total=5 => 1.5, unique=3 => 9, actionsPerDay=2.5 => 20 => total 30.5
    expect(score).toBe(30.5)
  })

  it('calculateEngagementScore returns 0 when no summary available', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('none')).toBe(0)
  })

  it('getActivityTrends (day) groups by day and computes growthRate', () => {
    const activities = [
      // 3 actions on 2024-01-01
      { id: '1', user_id: 'u1', action: 'a', timestamp: new Date(2024, 0, 1, 9, 0, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: new Date(2024, 0, 1, 13, 0, 0) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: new Date(2024, 0, 1, 18, 0, 0) },
      // 1 action on 2024-01-02
      { id: '4', user_id: 'u1', action: 'a', timestamp: new Date(2024, 0, 2, 11, 0, 0) },
      // 1 action on 2024-01-03
      { id: '5', user_id: 'u1', action: 'a', timestamp: new Date(2024, 0, 3, 9, 0, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'day')
    expect(trends.map(t => t.period)).toEqual(['2024-01-01', '2024-01-02', '2024-01-03'])
    expect(trends.map(t => t.count)).toEqual([3, 1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -66.67, 0])
  })

  it('getActivityTrends (hour) groups by hour with proper hour key and growthRate', () => {
    const activities = [
      { id: '1', user_id: 'u2', action: 'a', timestamp: new Date(2024, 5, 1, 9, 15, 0) },
      { id: '2', user_id: 'u2', action: 'b', timestamp: new Date(2024, 5, 1, 9, 45, 0) },
      { id: '3', user_id: 'u2', action: 'a', timestamp: new Date(2024, 5, 1, 10, 0, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u2', 'hour')
    const expectedPeriods = [
      `${new Date(2024, 5, 1).getFullYear()}-06-01 09:00`,
      `${new Date(2024, 5, 1).getFullYear()}-06-01 10:00`
    ]
    expect(trends.map(t => t.period)).toEqual(expectedPeriods)
    expect(trends.map(t => t.count)).toEqual([2, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50])
  })

  it('getActivityTrends (week) groups by week number and computes growth', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: new Date(2024, 0, 1, 12, 0, 0) }, // likely W01
      { id: '2', user_id: 'u1', action: 'b', timestamp: new Date(2024, 0, 5, 9, 0, 0) },  // W01
      { id: '3', user_id: 'u1', action: 'c', timestamp: new Date(2024, 0, 8, 10, 0, 0) }  // W02
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toBe('2024-W01')
    expect(trends[0].count).toBe(2)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].period).toBe('2024-W02')
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50)
  })

  it('getActivityTrends (month) groups by month and computes growth across months', () => {
    const activities = [
      { id: '1', user_id: 'm1', action: 'a', timestamp: new Date(2024, 0, 10, 8, 0, 0) }, // Jan
      { id: '2', user_id: 'm1', action: 'b', timestamp: new Date(2024, 0, 15, 12, 0, 0) }, // Jan
      { id: '3', user_id: 'm1', action: 'c', timestamp: new Date(2024, 1, 29, 9, 0, 0) },  // Feb (leap)
      { id: '4', user_id: 'm1', action: 'd', timestamp: new Date(2024, 2, 1, 10, 0, 0) }   // Mar
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('m1', 'month')
    expect(trends.map(t => t.period)).toEqual(['2024-01', '2024-02', '2024-03'])
    expect(trends.map(t => t.count)).toEqual([2, 1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50, 0])
  })

  it('getActivityTrends returns empty array when user has no activities', () => {
    const activities = [
      { id: '1', user_id: 'x', action: 'a', timestamp: new Date(2024, 0, 1) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('nope', 'day')
    expect(trends).toEqual([])
  })

  it('filterByDateRange returns only activities in inclusive date range for a specific user', () => {
    const a1 = { id: '1', user_id: 'u3', action: 'a', timestamp: new Date(2024, 0, 1, 0, 0, 0) }
    const a2 = { id: '2', user_id: 'u3', action: 'b', timestamp: new Date(2024, 0, 2, 12, 0, 0) }
    const a3 = { id: '3', user_id: 'u3', action: 'c', timestamp: new Date(2024, 0, 3, 23, 59, 59) }
    const a4 = { id: '4', user_id: 'other', action: 'd', timestamp: new Date(2024, 0, 2, 12, 0, 0) }
    const dashboard = new ActivityDashboard([a1, a2, a3, a4])
    const start = new Date(2024, 0, 2, 12, 0, 0)
    const end = new Date(2024, 0, 3, 23, 59, 59)
    const filtered = dashboard.filterByDateRange('u3', start, end)
    expect(filtered.length).toBe(2)
    expect(filtered.find(x => x.id === '2')).toBeTruthy()
    expect(filtered.find(x => x.id === '3')).toBeTruthy()
  })

  it('aggregateByAction returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const result = dashboard.aggregateByAction('none')
    expect(result).toEqual([])
  })

  it('aggregateByAction aggregates counts, percentages, first and last occurrence, sorted by count desc', () => {
    const a1 = { id: '1', user_id: 'ag', action: 'view', timestamp: new Date(2024, 0, 1, 9, 0, 0) }
    const a2 = { id: '2', user_id: 'ag', action: 'view', timestamp: new Date(2024, 0, 2, 12, 0, 0) }
    const a3 = { id: '3', user_id: 'ag', action: 'view', timestamp: new Date(2024, 0, 3, 14, 0, 0) }
    const a4 = { id: '4', user_id: 'ag', action: 'purchase', timestamp: new Date(2024, 0, 2, 13, 0, 0) }
    const a5 = { id: '5', user_id: 'ag', action: 'purchase', timestamp: new Date(2024, 0, 5, 10, 0, 0) }
    const a6 = { id: '6', user_id: 'ag', action: 'login', timestamp: new Date(2023, 11, 31, 23, 0, 0) }
    const dashboard = new ActivityDashboard([a1, a2, a3, a4, a5, a6])
    const groups = dashboard.aggregateByAction('ag')
    expect(groups.length).toBe(3)
    // Sorted by count desc: view (3), purchase (2), login (1)
    expect(groups[0].action).toBe('view')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(50)
    expect(groups[0].firstOccurrence.getTime()).toBe(a1.timestamp.getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(a3.timestamp.getTime())

    expect(groups[1].action).toBe('purchase')
    expect(groups[1].count).toBe(2)
    expect(groups[1].percentage).toBe(33.33)
    expect(groups[1].firstOccurrence.getTime()).toBe(a4.timestamp.getTime())
    expect(groups[1].lastOccurrence.getTime()).toBe(a5.timestamp.getTime())

    expect(groups[2].action).toBe('login')
    expect(groups[2].count).toBe(1)
    expect(groups[2].percentage).toBe(16.67)
    expect(groups[2].firstOccurrence.getTime()).toBe(a6.timestamp.getTime())
    expect(groups[2].lastOccurrence.getTime()).toBe(a6.timestamp.getTime())
  })

  it('getTopActions_old returns all action groups sorted by count (ignores limit parameter)', () => {
    const a1 = { id: '1', user_id: 'ag', action: 'view', timestamp: new Date(2024, 0, 1, 9, 0, 0) }
    const a2 = { id: '2', user_id: 'ag', action: 'view', timestamp: new Date(2024, 0, 2, 12, 0, 0) }
    const a3 = { id: '3', user_id: 'ag', action: 'purchase', timestamp: new Date(2024, 0, 3, 14, 0, 0) }
    const a4 = { id: '4', user_id: 'ag', action: 'login', timestamp: new Date(2024, 0, 2, 13, 0, 0) }
    const dashboard = new ActivityDashboard([a1, a2, a3, a4])
    const groups = dashboard.getTopActions_old('ag', 1)
    expect(groups.length).toBe(3)
    expect(groups[0].action).toBe('view')
    expect(groups[0].count).toBe(2)
    expect(groups[1].count).toBe(1)
    expect(groups[2].count).toBe(1)
  })

  it('getTopActions returns top N action groups using aggregateByAction results', () => {
    const a1 = { id: '1', user_id: 'ag', action: 'view', timestamp: new Date(2024, 0, 1, 9, 0, 0) }
    const a2 = { id: '2', user_id: 'ag', action: 'view', timestamp: new Date(2024, 0, 2, 12, 0, 0) }
    const a3 = { id: '3', user_id: 'ag', action: 'purchase', timestamp: new Date(2024, 0, 3, 14, 0, 0) }
    const a4 = { id: '4', user_id: 'ag', action: 'login', timestamp: new Date(2024, 0, 2, 13, 0, 0) }
    const a5 = { id: '5', user_id: 'ag', action: 'comment', timestamp: new Date(2024, 0, 4, 13, 0, 0) }
    const dashboard = new ActivityDashboard([a1, a2, a3, a4, a5])
    const top2 = dashboard.getTopActions('ag', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('view')
    expect(top2[0].count).toBe(2)
    const defaultTop = dashboard.getTopActions('ag')
    expect(defaultTop.length).toBe(4) // 4 distinct actions, default limit 5
  })

  it('getTopActions limits results even when many distinct actions exist', () => {
    const userId = 'many'
    const actions = ['a', 'b', 'c', 'd', 'e', 'f']
    const activities = actions.map((act, i) => ({
      id: String(i + 1),
      user_id: userId,
      action: act,
      timestamp: new Date(2024, 0, 1, 10, i, 0)
    }))
    const dashboard = new ActivityDashboard(activities)
    const top5 = dashboard.getTopActions(userId, 5)
    expect(top5.length).toBe(5)
    // Each count is 1; order is by sort on count (ties), still ensure none undefined
    expect(top5.every(g => g.count === 1)).toBe(true)
  })

  it('getUserSummary treats exactly 30-minute gaps as same session (session gap is strictly > 30)', () => {
    const activities = [
      { id: '1', user_id: 'u4', action: 'x', timestamp: new Date(2024, 0, 1, 10, 0, 0) },
      { id: '2', user_id: 'u4', action: 'y', timestamp: new Date(2024, 0, 1, 10, 30, 0) }, // exactly 30 mins -> same session
      { id: '3', user_id: 'u4', action: 'z', timestamp: new Date(2024, 0, 1, 11, 1, 0) }   // 31 mins gap -> new session
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u4')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    expect(summary!.averageActionsPerSession).toBe(1.5) // 2 sessions -> 3/2
    expect(summary!.actionsPerDay).toBe(3) // same day => daysActive=1
  })

  it('getActivityTrends respects userId filtering', () => {
    const activities = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: new Date(2024, 0, 1, 9, 0, 0) },
      { id: '2', user_id: 'u2', action: 'b', timestamp: new Date(2024, 0, 1, 10, 0, 0) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: new Date(2024, 0, 2, 11, 0, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const u1Trends = dashboard.getActivityTrends('u1', 'day')
    expect(u1Trends.map(t => t.count)).toEqual([1, 1])
    const u2Trends = dashboard.getActivityTrends('u2', 'day')
    expect(u2Trends.map(t => t.count)).toEqual([1])
  })

  it('filterByDateRange excludes activities outside range and for other users', () => {
    const activities = [
      { id: '1', user_id: 'u5', action: 'a', timestamp: new Date(2024, 0, 5, 10, 0, 0) },
      { id: '2', user_id: 'u5', action: 'b', timestamp: new Date(2024, 0, 6, 12, 0, 0) },
      { id: '3', user_id: 'u5', action: 'c', timestamp: new Date(2024, 0, 7, 14, 0, 0) },
      { id: '4', user_id: 'other', action: 'd', timestamp: new Date(2024, 0, 6, 12, 0, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const start = new Date(2024, 0, 6, 0, 0, 0)
    const end = new Date(2024, 0, 7, 0, 0, 0)
    const filtered = dashboard.filterByDateRange('u5', start, end)
    expect(filtered.length).toBe(1)
    expect(filtered[0].id).toBe('2')
  })
})