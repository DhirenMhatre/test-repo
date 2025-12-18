import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

const makeActivity = (id, user_id, action, dateStr, metadata) => ({
  id,
  user_id,
  action,
  timestamp: new Date(dateStr),
  metadata
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const summary = dash.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes summary fields correctly for single-day activity', () => {
    const acts = [
      makeActivity('1', 'u1', 'click', '2023-01-01T10:00:00Z'),
      makeActivity('2', 'u1', 'view', '2023-01-01T11:00:00Z'),
      makeActivity('3', 'u1', 'click', '2023-01-01T12:15:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary?.totalActions).toBe(3)
    expect(summary?.uniqueActions).toBe(2)
    expect(summary?.actionsPerDay).toBe(3)
    expect(summary?.mostFrequentAction).toBe('click')
    expect(summary?.averageActionsPerSession).toBe(1) // gaps > 30 min create 3 sessions => 3/3 = 1
  })

  it('selects the first encountered action when frequencies tie', () => {
    const acts = [
      makeActivity('1', 'u1', 'a', '2023-01-01T10:00:00Z'),
      makeActivity('2', 'u1', 'b', '2023-01-01T11:00:00Z'),
      makeActivity('3', 'u1', 'b', '2023-01-01T12:00:00Z'),
      makeActivity('4', 'u1', 'a', '2023-01-01T13:00:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary?.mostFrequentAction).toBe('a') // both 'a' and 'b' have 2, but 'a' was first inserted
  })

  it('computes actions per day across multiple days and average actions per session', () => {
    const acts = [
      makeActivity('1', 'u1', 'a', '2023-01-01T10:00:00Z'),
      makeActivity('2', 'u1', 'a', '2023-01-02T13:00:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const summary = dash.getUserSummary('u1')
    expect(summary?.actionsPerDay).toBe(1) // ceil((27h)/24)=2 days active => 2/2 = 1.00
    expect(summary?.averageActionsPerSession).toBe(1) // gap > 30 => 2 sessions, 2/2 = 1.00
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const trends = dash.getActivityTrends('u1')
    expect(trends).toEqual([])
  })

  it('groups by day and calculates growth rates', () => {
    const acts = [
      makeActivity('1', 'u1', 'a', '2023-01-01T10:00:00Z'),
      makeActivity('2', 'u1', 'b', '2023-01-01T11:00:00Z'),
      makeActivity('3', 'u1', 'a', '2023-01-02T09:00:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends.map(t => t.period)).toEqual(['2023-01-01', '2023-01-02'])
    expect(trends.map(t => t.count)).toEqual([2, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50])
  })

  it('groups by hour with correct period keys and zero growth when counts are equal', () => {
    const acts = [
      makeActivity('1', 'u1', 'a', '2023-01-01T10:00:00Z'),
      makeActivity('2', 'u1', 'b', '2023-01-01T11:30:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'hour')
    expect(trends.map(t => t.period)).toEqual(['2023-01-01 10:00', '2023-01-01 11:00'])
    expect(trends.map(t => t.count)).toEqual([1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, 0])
  })

  it('groups by week using getWeekNumber', () => {
    const acts = [
      makeActivity('1', 'u1', 'a', '2023-01-02T10:00:00Z'), // likely week 1
      makeActivity('2', 'u1', 'a', '2023-01-09T10:00:00Z'), // likely week 2
      makeActivity('3', 'u1', 'a', '2023-01-10T10:00:00Z'),
      makeActivity('4', 'u1', 'a', '2023-01-11T10:00:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(2)
    expect(trends[0].period).toMatch(/^2023-W0?1$/)
    expect(trends[1].period).toMatch(/^2023-W0?2$/)
    expect(trends.map(t => t.count)).toEqual([1, 3])
    expect(trends.map(t => t.growthRate)).toEqual([0, 200])
  })

  it('groups by month and sorts lexicographically which matches chronological order', () => {
    const acts = [
      makeActivity('1', 'u1', 'a', '2023-01-15T10:00:00Z'),
      makeActivity('2', 'u1', 'b', '2023-02-01T12:00:00Z'),
      makeActivity('3', 'u1', 'c', '2023-02-15T12:00:00Z'),
      makeActivity('4', 'u1', 'c', '2023-02-20T12:00:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const trends = dash.getActivityTrends('u1', 'month')
    expect(trends.map(t => t.period)).toEqual(['2023-01', '2023-02'])
    expect(trends.map(t => t.count)).toEqual([1, 3])
    expect(trends.map(t => t.growthRate)).toEqual([0, 200])
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('filters activities within start and end date (exclusive of outside)', () => {
    const acts = [
      makeActivity('1', 'u1', 'a', '2023-01-01T10:00:00Z'),
      makeActivity('2', 'u1', 'b', '2023-01-03T10:00:00Z'),
      makeActivity('3', 'u1', 'c', '2023-01-05T10:00:00Z'),
      makeActivity('4', 'u2', 'z', '2023-01-03T10:00:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const start = new Date('2023-01-02T00:00:00Z')
    const end = new Date('2023-01-04T00:00:00Z')
    const filtered = dash.filterByDateRange('u1', start, end)
    expect(filtered.length).toBe(1)
    expect(filtered[0].id).toBe('2')
  })

  it('includes activities exactly on the start and end boundaries', () => {
    const acts = [
      makeActivity('1', 'u1', 'a', '2023-01-01T10:00:00Z'),
      makeActivity('2', 'u1', 'b', '2023-01-03T10:00:00Z'),
      makeActivity('3', 'u1', 'c', '2023-01-05T10:00:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const start = new Date('2023-01-01T10:00:00Z')
    const end = new Date('2023-01-03T10:00:00Z')
    const filtered = dash.filterByDateRange('u1', start, end)
    expect(filtered.map(a => a.id)).toEqual(['1', '2'])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('aggregates counts, percentages, and occurrence bounds correctly and sorts by count desc', () => {
    const acts = [
      makeActivity('1', 'u1', 'view', '2023-01-01T09:00:00Z'),
      makeActivity('2', 'u1', 'click', '2023-01-01T10:00:00Z'),
      makeActivity('3', 'u1', 'click', '2023-01-02T10:00:00Z'),
      makeActivity('4', 'u1', 'view', '2023-01-02T12:00:00Z'),
      makeActivity('5', 'u1', 'click', '2023-01-03T10:00:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const groups = dash.aggregateByAction('u1')
    expect(groups.length).toBe(2)
    expect(groups[0].action).toBe('click')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(60)
    expect(groups[0].firstOccurrence.getTime()).toBe(new Date('2023-01-01T10:00:00Z').getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(new Date('2023-01-03T10:00:00Z').getTime())

    expect(groups[1].action).toBe('view')
    expect(groups[1].count).toBe(2)
    expect(groups[1].percentage).toBe(40)
    expect(groups[1].firstOccurrence.getTime()).toBe(new Date('2023-01-01T09:00:00Z').getTime())
    expect(groups[1].lastOccurrence.getTime()).toBe(new Date('2023-01-02T12:00:00Z').getTime())
  })

  it('returns empty array for user with no activities', () => {
    const dash = new ActivityDashboard([
      makeActivity('1', 'u2', 'x', '2023-01-01T10:00:00Z')
    ])
    const groups = dash.aggregateByAction('u1')
    expect(groups).toEqual([])
  })
})

describe('ActivityDashboard - getTopActions_old and getTopActions', () => {
  it('getTopActions_old ignores limit and returns all aggregated actions sorted by count', () => {
    const acts = [
      makeActivity('1', 'u1', 'view', '2023-01-01T09:00:00Z'),
      makeActivity('2', 'u1', 'click', '2023-01-01T10:00:00Z'),
      makeActivity('3', 'u1', 'click', '2023-01-02T10:00:00Z'),
      makeActivity('4', 'u1', 'view', '2023-01-02T12:00:00Z'),
      makeActivity('5', 'u1', 'click', '2023-01-03T10:00:00Z'),
      makeActivity('6', 'u1', 'like', '2023-01-03T11:00:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const topOld = dash.getTopActions_old('u1', 1)
    expect(topOld.length).toBe(3)
    expect(topOld[0].action).toBe('click')
    expect(topOld[0].count).toBe(3)
  })

  it('getTopActions applies limit after aggregation', () => {
    const acts = [
      makeActivity('1', 'u1', 'view', '2023-01-01T09:00:00Z'),
      makeActivity('2', 'u1', 'click', '2023-01-01T10:00:00Z'),
      makeActivity('3', 'u1', 'click', '2023-01-02T10:00:00Z'),
      makeActivity('4', 'u1', 'view', '2023-01-02T12:00:00Z'),
      makeActivity('5', 'u1', 'click', '2023-01-03T10:00:00Z'),
      makeActivity('6', 'u1', 'like', '2023-01-03T11:00:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    const top1 = dash.getTopActions('u1', 1)
    expect(top1.length).toBe(1)
    expect(top1[0].action).toBe('click')
    const top2 = dash.getTopActions('u1', 2)
    expect(top2.map(t => t.action)).toEqual(['click', 'view'])
  })

  it('getTopActions returns empty when no activities for user', () => {
    const dash = new ActivityDashboard([])
    const top = dash.getTopActions('u1')
    expect(top).toEqual([])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 for users with no activity', () => {
    const dash = new ActivityDashboard([])
    expect(dash.calculateEngagementScore('u1')).toBe(0)
  })

  it('computes a weighted score with rounding to two decimals', () => {
    const acts = [
      makeActivity('1', 'u1', 'click', '2023-01-01T10:00:00Z'),
      makeActivity('2', 'u1', 'view', '2023-01-01T11:00:00Z'),
      makeActivity('3', 'u1', 'click', '2023-01-01T12:15:00Z')
    ]
    const dash = new ActivityDashboard(acts)
    // total=3 -> volumeScore = (3/100)*30 = 0.9
    // unique=2 -> diversityScore = (2/10)*30 = 6
    // actionsPerDay=3 -> frequencyScore = (3/5)*40 = 24
    // total = 30.9
    expect(dash.calculateEngagementScore('u1')).toBe(30.9)
  })

  it('caps each component and reaches maximum score of 100', () => {
    const base = new Date('2023-01-01T00:00:00Z')
    const acts = []
    for (let i = 0; i < 100; i++) {
      const ts = new Date(base.getTime() + i * 60000) // every minute
      const action = `a${i % 10}` // 10 unique actions
      acts.push({
        id: String(i + 1),
        user_id: 'u1',
        action,
        timestamp: ts
      })
    }
    const dash = new ActivityDashboard(acts)
    expect(dash.calculateEngagementScore('u1')).toBe(100)
  })
})