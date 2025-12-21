import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity, ActionGroup, TrendData, ActivitySummary } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

function makeActivity(id: string, user_id: string, action: string, y: number, m: number, d: number, h = 0, min = 0): Activity {
  return {
    id,
    user_id,
    action,
    timestamp: new Date(y, m - 1, d, h, min)
  }
}

describe('ActivityDashboard', () => {
  describe('constructor and empty state', () => {
    it('initializes with empty activities and returns null/0/[] as appropriate', () => {
      const dash = new ActivityDashboard()
      expect(dash.getUserSummary('u1')).toBeNull()
      expect(dash.calculateEngagementScore('u1')).toBe(0)
      expect(dash.getActivityTrends('u1')).toEqual([])
    })
  })

  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u2', 'view', 2024, 1, 1, 10, 0)
      ]
      const dash = new ActivityDashboard(acts)
      expect(dash.getUserSummary('u1')).toBeNull()
    })

    it('computes same-day metrics with ties resolved by first encountered action', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'view', 2024, 1, 1, 10, 0),
        makeActivity('2', 'u1', 'click', 2024, 1, 1, 10, 5)
      ]
      const dash = new ActivityDashboard(acts)
      const summary = dash.getUserSummary('u1') as ActivitySummary
      expect(summary.totalActions).toBe(2)
      expect(summary.uniqueActions).toBe(2)
      expect(summary.actionsPerDay).toBe(2)
      expect(summary.mostFrequentAction).toBe('view')
      expect(summary.averageActionsPerSession).toBe(2)
    })

    it('computes actionsPerDay over multiple days and averageActionsPerSession with 30-minute gap threshold', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'view', 2024, 1, 1, 10, 0),   // session 1
        makeActivity('2', 'u1', 'view', 2024, 1, 1, 10, 20),  // session 1 (20 min gap)
        makeActivity('3', 'u1', 'view', 2024, 1, 1, 10, 51),  // session 2 (31 min gap)
        makeActivity('4', 'u1', 'view', 2024, 1, 1, 11, 21),  // session 2 (30 min gap => still same session)
        makeActivity('5', 'u1', 'click', 2024, 1, 3, 9, 0)    // session 3 (new day)
      ]
      const dash = new ActivityDashboard(acts)
      const summary = dash.getUserSummary('u1') as ActivitySummary
      expect(summary.totalActions).toBe(5)
      // first: Jan 1 10:00, last: Jan 3 09:00 => just under 2 days -> ceil to 2 days
      expect(summary.actionsPerDay).toBe(2.5)
      // sessions: [10:00,10:20], [10:51,11:21], [Jan 3 09:00] => 3 sessions => 5/3 => 1.67
      expect(summary.averageActionsPerSession).toBe(1.67)
      expect(summary.mostFrequentAction).toBe('view')
    })
  })

  describe('filterByDateRange', () => {
    it('includes activities on the start and end boundaries (inclusive)', () => {
      const a1 = makeActivity('1', 'u2', 'view', 2024, 5, 1, 0, 0)
      const a2 = makeActivity('2', 'u2', 'view', 2024, 5, 2, 0, 0)
      const a3 = makeActivity('3', 'u2', 'view', 2024, 5, 3, 0, 0)
      const dash = new ActivityDashboard([a1, a2, a3])
      const filtered = dash.filterByDateRange('u2', new Date(2024, 4, 2, 0, 0), new Date(2024, 4, 3, 0, 0))
      const times = filtered.map(f => f.timestamp.getTime()).sort()
      expect(times).toEqual([a2.timestamp.getTime(), a3.timestamp.getTime()])
    })

    it('filters by userId and ignores other users', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'view', 2024, 1, 1, 8, 0),
        makeActivity('2', 'u2', 'view', 2024, 1, 1, 9, 0),
        makeActivity('3', 'u1', 'view', 2024, 1, 1, 10, 0)
      ]
      const dash = new ActivityDashboard(acts)
      const filtered = dash.filterByDateRange('u1', new Date(2024, 0, 1, 0, 0), new Date(2024, 0, 1, 23, 59))
      expect(filtered.every(f => f.user_id === 'u1')).toBe(true)
      expect(filtered).toHaveLength(2)
    })
  })

  describe('aggregateByAction', () => {
    it('returns aggregated groups with counts, percentages, and first/last occurrence', () => {
      const t1 = new Date(2024, 0, 1, 10, 0)
      const t2 = new Date(2024, 0, 1, 10, 10)
      const t3 = new Date(2024, 0, 1, 11, 0)
      const acts: Activity[] = [
        { id: '1', user_id: 'u1', action: 'view', timestamp: t1 },
        { id: '2', user_id: 'u1', action: 'click', timestamp: t2 },
        { id: '3', user_id: 'u1', action: 'view', timestamp: t3 }
      ]
      const dash = new ActivityDashboard(acts)
      const groups = dash.aggregateByAction('u1')
      expect(groups).toHaveLength(2)
      // Sorted by count desc, so 'view' first with 2 occurrences
      const view = groups.find(g => g.action === 'view') as ActionGroup
      expect(view.count).toBe(2)
      expect(view.percentage).toBe(66.67)
      expect(view.firstOccurrence.getTime()).toBe(t1.getTime())
      expect(view.lastOccurrence.getTime()).toBe(t3.getTime())
      const click = groups.find(g => g.action === 'click') as ActionGroup
      expect(click.count).toBe(1)
      expect(click.percentage).toBe(33.33)
      expect(groups[0].action).toBe('view')
      expect(groups[1].action).toBe('click')
    })

    it('returns empty array when no activities for user', () => {
      const dash = new ActivityDashboard([
        makeActivity('1', 'u2', 'view', 2024, 1, 1, 10, 0)
      ])
      expect(dash.aggregateByAction('u1')).toEqual([])
    })

    it('groups only the specified user activities', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'view', 2024, 1, 1, 10, 0),
        makeActivity('2', 'u2', 'view', 2024, 1, 1, 10, 5),
        makeActivity('3', 'u1', 'view', 2024, 1, 1, 10, 10)
      ]
      const dash = new ActivityDashboard(acts)
      const groups = dash.aggregateByAction('u1')
      expect(groups).toHaveLength(1)
      expect(groups[0].action).toBe('view')
      expect(groups[0].count).toBe(2)
    })
  })

  describe('getTopActions_old', () => {
    it('ignores limit and returns all action groups sorted by count', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'a', 2024, 1, 1, 10, 0),
        makeActivity('2', 'u1', 'b', 2024, 1, 1, 10, 5),
        makeActivity('3', 'u1', 'a', 2024, 1, 1, 10, 10),
        makeActivity('4', 'u1', 'c', 2024, 1, 1, 10, 15)
      ]
      const dash = new ActivityDashboard(acts)
      const groups = dash.getTopActions_old('u1', 1)
      // Should return 3 groups (a,b,c), not limited to 1
      expect(groups.map(g => g.action)).toEqual(['a', 'b', 'c'].sort((x, y) => {
        const counts: Record<string, number> = { a: 2, b: 1, c: 1 }
        return counts[y] - counts[x]
      }))
      expect(groups.find(g => g.action === 'a')?.count).toBe(2)
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions using aggregateByAction', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'x', 2024, 1, 1, 10, 0),
        makeActivity('2', 'u1', 'y', 2024, 1, 1, 10, 5),
        makeActivity('3', 'u1', 'x', 2024, 1, 1, 10, 10),
        makeActivity('4', 'u1', 'z', 2024, 1, 1, 10, 15),
        makeActivity('5', 'u1', 'x', 2024, 1, 1, 10, 20)
      ]
      const dash = new ActivityDashboard(acts)
      const top1 = dash.getTopActions('u1', 1)
      expect(top1).toHaveLength(1)
      expect(top1[0].action).toBe('x')
      expect(top1[0].count).toBe(3)

      const top2 = dash.getTopActions('u1', 2)
      expect(top2).toHaveLength(2)
      expect(top2[0].action).toBe('x')
      expect(new Set(top2.map(g => g.action)).has('y') || new Set(top2.map(g => g.action)).has('z')).toBe(true)
    })

    it('returns empty array when limit is 0', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'x', 2024, 1, 1, 10, 0)
      ]
      const dash = new ActivityDashboard(acts)
      const res = dash.getTopActions('u1', 0)
      expect(res).toEqual([])
    })
  })

  describe('getActivityTrends', () => {
    it('groups by day and computes growth rates', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'view', 2024, 1, 1, 10, 0),
        makeActivity('2', 'u1', 'view', 2024, 1, 1, 11, 0),
        makeActivity('3', 'u1', 'view', 2024, 1, 2, 12, 0)
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'day') as TrendData[]
      expect(trends).toHaveLength(2)
      expect(trends[0].period).toBe('2024-01-01')
      expect(trends[0].count).toBe(2)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].period).toBe('2024-01-02')
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBe(-50)
    })

    it('groups by hour with expected formatting', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'view', 2024, 2, 10, 9, 30),
        makeActivity('2', 'u1', 'view', 2024, 2, 10, 10, 15),
        makeActivity('3', 'u1', 'view', 2024, 2, 10, 10, 45)
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'hour')
      expect(trends.map(t => t.period)).toEqual(['2024-02-10 09:00', '2024-02-10 10:00'])
      expect(trends.map(t => t.count)).toEqual([1, 2])
    })

    it('groups by month with expected formatting', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'v', 2024, 3, 1, 0, 0),
        makeActivity('2', 'u1', 'v', 2024, 3, 2, 0, 0),
        makeActivity('3', 'u1', 'v', 2024, 4, 1, 0, 0)
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'month')
      expect(trends.map(t => t.period)).toEqual(['2024-03', '2024-04'])
      expect(trends.map(t => t.count)).toEqual([2, 1])
    })

    it('groups by week with expected formatting', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u1', 'v', 2024, 1, 1, 12, 0), // 2024-01-01 => week 01 by getWeekNumber
        makeActivity('2', 'u1', 'v', 2024, 1, 7, 12, 0)  // 2024-01-07 => likely week 02 by getWeekNumber
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'week')
      expect(trends.map(t => t.period)).toEqual(['2024-W01', '2024-W02'])
      expect(trends.map(t => t.count)).toEqual([1, 1])
      expect(trends[1].growthRate).toBe(0)
    })

    it('returns empty array when no activities for user', () => {
      const acts: Activity[] = [
        makeActivity('1', 'u2', 'v', 2024, 1, 1, 10, 0)
      ]
      const dash = new ActivityDashboard(acts)
      expect(dash.getActivityTrends('u1')).toEqual([])
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when user has no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.calculateEngagementScore('missing')).toBe(0)
    })

    it('caps component scores and sums to 100 with sufficient activity', () => {
      const actions = Array.from({ length: 100 }, (_, i) => {
        const idx = i + 1
        const actionName = `a${idx % 10}` // 10 unique actions
        return makeActivity(`${idx}`, 'u1', actionName, 2024, 5, 1, 10, Math.floor(idx / 2))
      })
      const dash = new ActivityDashboard(actions)
      const score = dash.calculateEngagementScore('u1')
      expect(score).toBe(100)
    })

    it('computes weighted score with rounding', () => {
      // 10 actions in same day, 2 unique actions -> volume 3, diversity 6, frequency 40 => total 49
      const acts: Activity[] = []
      for (let i = 0; i < 10; i++) {
        const action = i % 2 === 0 ? 'alpha' : 'beta'
        acts.push(makeActivity(`id${i}`, 'u2', action, 2024, 6, 1, 10, i))
      }
      const dash = new ActivityDashboard(acts)
      const score = dash.calculateEngagementScore('u2')
      expect(score).toBe(49)
    })
  })
})