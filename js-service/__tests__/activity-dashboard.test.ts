import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function d(y: number, m: number, day: number, h = 0, min = 0, s = 0) {
  return new Date(y, m - 1, day, h, min, s)
}

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const summary = dashboard.getUserSummary('uX')
    expect(summary).toBeNull()
  })

  it('computes correct totals, unique actions, actionsPerDay, most frequent, average per session', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'click', timestamp: d(2024, 1, 1, 9, 50) },
      { id: '4', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 10, 40) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 2, 11, 0) },
      { id: '6', user_id: 'u1', action: 'logout', timestamp: d(2024, 1, 3, 12, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)

    const summary = dashboard.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(6)
    expect(summary!.uniqueActions).toBe(4)
    expect(summary!.actionsPerDay).toBe(2) // 6 actions across 3 days (ceil span) -> 2.00
    expect(summary!.mostFrequentAction).toBe('view')
    expect(summary!.averageActionsPerSession).toBe(1.2) // sessions split with >30min gaps
  })

  it('actions within same day produce daysActive=1 and correct actionsPerDay', () => {
    const activities: Activity[] = [
      { id: 'a', user_id: 'u2', action: 'x', timestamp: d(2024, 2, 1, 10, 0) },
      { id: 'b', user_id: 'u2', action: 'y', timestamp: d(2024, 2, 1, 10, 5) },
      { id: 'c', user_id: 'u2', action: 'z', timestamp: d(2024, 2, 1, 23, 59) },
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u2')
    expect(summary).not.toBeNull()
    expect(summary!.actionsPerDay).toBe(3) // ceil((last-first)/day)=0 -> max with 1 => 3/1
  })

  it('most frequent action keeps first encountered on tie', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u3', action: 'click', timestamp: d(2024, 1, 1, 10, 0) },
      { id: '2', user_id: 'u3', action: 'view', timestamp: d(2024, 1, 1, 10, 5) },
      { id: '3', user_id: 'u3', action: 'view', timestamp: d(2024, 1, 1, 10, 10) },
      { id: '4', user_id: 'u3', action: 'click', timestamp: d(2024, 1, 1, 10, 15) },
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u3')
    expect(summary).not.toBeNull()
    expect(summary!.mostFrequentAction).toBe('click') // tie 2 vs 2; 'click' first encountered
  })

  it('average actions per session uses 30-minute gap threshold (exactly 30 does not split)', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u4', action: 'a', timestamp: d(2024, 3, 1, 9, 0) },
      { id: '2', user_id: 'u4', action: 'b', timestamp: d(2024, 3, 1, 9, 30) }, // exactly 30 -> same session
      { id: '3', user_id: 'u4', action: 'c', timestamp: d(2024, 3, 1, 10, 1) }, // >30 from previous -> new session
    ]
    const dashboard = new ActivityDashboard(activities)
    const summary = dashboard.getUserSummary('u4')
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(1.5) // 3 actions / 2 sessions
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns [] when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const trends = dashboard.getActivityTrends('uX')
    expect(trends).toEqual([])
  })

  it('groups by day by default and computes growth rates', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'click', timestamp: d(2024, 1, 1, 9, 50) },
      { id: '4', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 10, 40) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 2, 11, 0) },
      { id: '6', user_id: 'u1', action: 'logout', timestamp: d(2024, 1, 3, 12, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1') // default 'day'
    expect(trends.map(t => t.period)).toEqual(['2024-01-01', '2024-01-02', '2024-01-03'])
    expect(trends.map(t => t.count)).toEqual([4, 1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -75, 0])
  })

  it('groups by hour with proper keys and growth', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'click', timestamp: d(2024, 1, 1, 9, 50) },
      { id: '4', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 10, 40) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 2, 11, 0) },
      { id: '6', user_id: 'u1', action: 'logout', timestamp: d(2024, 1, 3, 12, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'hour')
    expect(trends.map(t => t.period)).toEqual([
      '2024-01-01 09:00',
      '2024-01-01 10:00',
      '2024-01-02 11:00',
      '2024-01-03 12:00'
    ])
    expect(trends.map(t => t.count)).toEqual([3, 1, 1, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -66.67, 0, 0])
  })

  it('groups by week and formats as YYYY-Wnn', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 8, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 3, 12, 0) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d(2024, 1, 6, 12, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'week')
    expect(trends.length).toBe(1)
    expect(trends[0].period).toBe('2024-W01')
    expect(trends[0].count).toBe(3)
    expect(trends[0].growthRate).toBe(0)
  })

  it('groups by month with keys YYYY-MM', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 0, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 31, 23, 59) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d(2024, 2, 1, 0, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const trends = dashboard.getActivityTrends('u1', 'month')
    expect(trends.map(t => t.period)).toEqual(['2024-01', '2024-02'])
    expect(trends.map(t => t.count)).toEqual([2, 1])
    expect(trends.map(t => t.growthRate)).toEqual([0, -50])
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('returns activities in inclusive range for a user', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 1, 9, 50) },
      { id: '3', user_id: 'u1', action: 'c', timestamp: d(2024, 1, 1, 10, 40) },
      { id: '4', user_id: 'u1', action: 'd', timestamp: d(2024, 1, 2, 11, 0) },
      { id: '5', user_id: 'u2', action: 'e', timestamp: d(2024, 1, 2, 11, 0) },
    ]
    const dashboard = new ActivityDashboard(activities)
    const start = d(2024, 1, 1, 9, 50)
    const end = d(2024, 1, 2, 11, 0)
    const filtered = dashboard.filterByDateRange('u1', start, end)
    expect(filtered.map(a => a.id)).toEqual(['2', '3', '4'])
  })

  it('returns empty when no activities match user or range', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 1, 9, 50) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const filtered = dashboard.filterByDateRange('u2', d(2024, 1, 1, 0, 0), d(2024, 1, 2, 0, 0))
    expect(filtered).toEqual([])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const groups = dashboard.aggregateByAction('uX')
    expect(groups).toEqual([])
  })

  it('aggregates counts, percentages, and first/last occurrences, sorted by count desc', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'click', timestamp: d(2024, 1, 1, 9, 50) },
      { id: '4', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 10, 40) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 2, 11, 0) },
      { id: '6', user_id: 'u1', action: 'logout', timestamp: d(2024, 1, 3, 12, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.aggregateByAction('u1')

    const byAction: Record<string, any> = {}
    groups.forEach(g => { byAction[g.action] = g })

    expect(groups[0].action).toBe('view')
    expect(groups[0].count).toBe(3)
    expect(groups[0].percentage).toBe(50)
    expect(byAction['login'].count).toBe(1)
    expect(byAction['click'].count).toBe(1)
    expect(byAction['logout'].count).toBe(1)
    expect(byAction['view'].firstOccurrence.getTime()).toBe(d(2024, 1, 1, 9, 10).getTime())
    expect(byAction['view'].lastOccurrence.getTime()).toBe(d(2024, 1, 2, 11, 0).getTime())
  })
})

describe('ActivityDashboard - getTopActions_old', () => {
  it('returns all groups sorted by count and ignores limit parameter', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 10, 0) },
      { id: '4', user_id: 'u1', action: 'c', timestamp: d(2024, 1, 2, 11, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const groups = dashboard.getTopActions_old('u1', 1) // limit ignored
    expect(groups.length).toBe(3)
    expect(groups[0].action).toBe('a')
    expect(groups[0].count).toBe(2)
    expect(groups[0].percentage).toBe(50)
    const ids = groups.map(g => g.action).sort()
    expect(ids).toEqual(['a', 'b', 'c'].sort())
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('returns top N actions using aggregateByAction', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 10, 0) },
      { id: '4', user_id: 'u1', action: 'c', timestamp: d(2024, 1, 2, 11, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const top2 = dashboard.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('a')
    expect(top2[0].count).toBe(2)
  })

  it('default limit returns up to 5, or fewer if not enough groups', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'a', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'b', timestamp: d(2024, 1, 1, 9, 10) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const top = dashboard.getTopActions('u1')
    expect(top.length).toBe(2)
    const names = top.map(t => t.action).sort()
    expect(names).toEqual(['a', 'b'])
  })

  it('returns empty for user with no activities', () => {
    const dashboard = new ActivityDashboard([])
    const top = dashboard.getTopActions('uX', 3)
    expect(top).toEqual([])
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activity summary', () => {
    const dashboard = new ActivityDashboard([])
    const score = dashboard.calculateEngagementScore('none')
    expect(score).toBe(0)
  })

  it('calculates weighted score based on summary numbers', () => {
    const activities: Activity[] = [
      { id: '1', user_id: 'u1', action: 'login', timestamp: d(2024, 1, 1, 9, 0) },
      { id: '2', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 9, 10) },
      { id: '3', user_id: 'u1', action: 'click', timestamp: d(2024, 1, 1, 9, 50) },
      { id: '4', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 1, 10, 40) },
      { id: '5', user_id: 'u1', action: 'view', timestamp: d(2024, 1, 2, 11, 0) },
      { id: '6', user_id: 'u1', action: 'logout', timestamp: d(2024, 1, 3, 12, 0) }
    ]
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('u1')
    expect(score).toBe(29.8)
  })

  it('caps each component and overall score at 100', () => {
    const activities: Activity[] = []
    // 100 actions, 10 unique actions, all same day to max frequency score
    for (let i = 0; i < 100; i++) {
      const action = `a${i % 10}`
      activities.push({
        id: `id_${i}`,
        user_id: 'uMax',
        action,
        timestamp: d(2024, 1, 1, 0, i) // 1-minute increments
      })
    }
    const dashboard = new ActivityDashboard(activities)
    const score = dashboard.calculateEngagementScore('uMax')
    expect(score).toBe(100)
  })
})