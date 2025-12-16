import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

const dt = (y: number, m: number, d: number, h = 0, min = 0) => new Date(y, m - 1, d, h, min)
const act = (id: string, user_id: string, action: string, timestamp: Date, metadata?: Record<string, any>) => ({
  id,
  user_id,
  action,
  timestamp,
  metadata
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard', () => {
  describe('constructor and empty data behavior', () => {
    it('returns null summary and 0 engagement score when user has no activities', () => {
      const dash = new ActivityDashboard()
      expect(dash.getUserSummary('u0')).toBeNull()
      expect(dash.calculateEngagementScore('u0')).toBe(0)
    })

    it('getActivityTrends returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard()
      expect(dash.getActivityTrends('u-x', 'day')).toEqual([])
    })
  })

  describe('getUserSummary', () => {
    it('computes totals, unique actions, actionsPerDay, mostFrequentAction, and averageActionsPerSession correctly', () => {
      const activities = [
        act('1', 'u1', 'login', dt(2024, 1, 1, 10, 0)),
        act('2', 'u1', 'view', dt(2024, 1, 1, 10, 5)),
        act('3', 'u1', 'view', dt(2024, 1, 1, 10, 10)),
        act('4', 'u1', 'logout', dt(2024, 1, 1, 11, 0)),
        act('5', 'u1', 'view', dt(2024, 1, 2, 12, 0)),
        act('6', 'u1', 'login', dt(2024, 1, 3, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(6)
      expect(summary!.uniqueActions).toBe(3)
      expect(summary!.actionsPerDay).toBe(3) // 6 actions across ceil((Jan3 09:00 - Jan1 10:00)/1d)=2 days
      expect(summary!.mostFrequentAction).toBe('view')
      expect(summary!.averageActionsPerSession).toBe(1.5) // sessions separated by >30min
    })

    it('handles single activity: daysActive at least 1, actionsPerDay = 1, averageActionsPerSession = 1', () => {
      const activities = [act('a', 'u2', 'signup', dt(2024, 6, 10, 14, 0))]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u2')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(1)
      expect(summary!.uniqueActions).toBe(1)
      expect(summary!.actionsPerDay).toBe(1)
      expect(summary!.mostFrequentAction).toBe('signup')
      expect(summary!.averageActionsPerSession).toBe(1)
    })

    it('session gap strictly greater than 30 minutes starts a new session; gap equal to 30 does not', () => {
      const base = dt(2024, 7, 1, 8, 0)
      const t0 = base
      const t1 = dt(2024, 7, 1, 8, 30) // exactly 30 minutes later -> same session
      const t2 = dt(2024, 7, 1, 9, 1) // 31 minutes after t1 -> new session
      const activities = [
        act('1', 'u3', 'a', t0),
        act('2', 'u3', 'b', t1),
        act('3', 'u3', 'c', t2)
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u3')
      expect(summary).not.toBeNull()
      expect(summary!.averageActionsPerSession).toBe(1.5) // 3 actions / 2 sessions
    })
  })

  describe('getActivityTrends - day grouping and growth rates', () => {
    it('groups by day and calculates growthRate compared to previous period', () => {
      const activities = [
        // 2024-01-01: 2 actions
        act('1', 'u1', 'a', dt(2024, 1, 1, 9, 0)),
        act('2', 'u1', 'b', dt(2024, 1, 1, 10, 0)),
        // 2024-01-02: 4 actions
        act('3', 'u1', 'a', dt(2024, 1, 2, 9, 0)),
        act('4', 'u1', 'a', dt(2024, 1, 2, 10, 0)),
        act('5', 'u1', 'b', dt(2024, 1, 2, 11, 0)),
        act('6', 'u1', 'c', dt(2024, 1, 2, 12, 0)),
        // 2024-01-03: 2 actions
        act('7', 'u1', 'd', dt(2024, 1, 3, 9, 0)),
        act('8', 'u1', 'd', dt(2024, 1, 3, 10, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('u1', 'day')
      expect(trends).toEqual([
        { period: '2024-01-01', count: 2, growthRate: 0 },
        { period: '2024-01-02', count: 4, growthRate: 100 },
        { period: '2024-01-03', count: 2, growthRate: -50 }
      ])
    })
  })

  describe('getActivityTrends - hour grouping', () => {
    it('groups by hour with "YYYY-MM-DD HH:00" keys', () => {
      const activities = [
        act('1', 'uH', 'a', dt(2024, 3, 5, 9, 15)),
        act('2', 'uH', 'b', dt(2024, 3, 5, 9, 45)),
        act('3', 'uH', 'c', dt(2024, 3, 5, 10, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('uH', 'hour')
      expect(trends).toEqual([
        { period: '2024-03-05 09:00', count: 2, growthRate: 0 },
        { period: '2024-03-05 10:00', count: 1, growthRate: -50 }
      ])
    })
  })

  describe('getActivityTrends - week grouping', () => {
    it('groups by computed week number using getWeekNumber', () => {
      const activities = [
        act('1', 'uW', 'a', dt(2024, 1, 1, 10, 0)), // 2024-W01 by implementation
        act('2', 'uW', 'b', dt(2024, 1, 7, 10, 0)), // Sunday -> should advance to W02 by implementation
        act('3', 'uW', 'c', dt(2024, 1, 8, 10, 0))  // Monday -> W02 also
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('uW', 'week')
      // Expect W01 first, then W02 with count 2
      expect(trends[0]).toEqual({ period: '2024-W01', count: 1, growthRate: 0 })
      expect(trends[1].period).toBe('2024-W02')
      expect(trends[1].count).toBe(2)
      expect(typeof trends[1].growthRate).toBe('number')
    })
  })

  describe('getActivityTrends - month grouping', () => {
    it('groups by month "YYYY-MM"', () => {
      const activities = [
        act('1', 'uM', 'a', dt(2024, 2, 28, 10, 0)),
        act('2', 'uM', 'b', dt(2024, 3, 1, 10, 0)),
        act('3', 'uM', 'c', dt(2024, 3, 15, 10, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const trends = dash.getActivityTrends('uM', 'month')
      expect(trends).toEqual([
        { period: '2024-02', count: 1, growthRate: 0 },
        { period: '2024-03', count: 2, growthRate: 100 }
      ])
    })
  })

  describe('filterByDateRange', () => {
    it('includes activities within inclusive start and end bounds only for the specified user', () => {
      const start = dt(2024, 4, 10, 9, 0)
      const end = dt(2024, 4, 10, 11, 0)
      const activities = [
        act('1', 'uF', 'a', dt(2024, 4, 10, 8, 59)),
        act('2', 'uF', 'a', start),
        act('3', 'uF', 'b', dt(2024, 4, 10, 10, 0)),
        act('4', 'uF', 'c', end),
        act('5', 'uF', 'd', dt(2024, 4, 10, 11, 1)),
        act('x', 'other', 'a', dt(2024, 4, 10, 10, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const filtered = dash.filterByDateRange('uF', start, end)
      expect(filtered.map(a => a.id)).toEqual(['2', '3', '4'])
    })

    it('returns empty when nothing falls in the range', () => {
      const activities = [
        act('1', 'uG', 'a', dt(2024, 5, 1, 9, 0)),
        act('2', 'uG', 'b', dt(2024, 5, 2, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const filtered = dash.filterByDateRange('uG', dt(2024, 5, 3, 0, 0), dt(2024, 5, 4, 0, 0))
      expect(filtered).toEqual([])
    })
  })

  describe('aggregateByAction', () => {
    it('aggregates counts, percentages, and first/last occurrences, sorted by count desc', () => {
      const activities = [
        act('1', 'uA', 'view', dt(2024, 1, 1, 9, 0)),
        act('2', 'uA', 'click', dt(2024, 1, 1, 9, 5)),
        act('3', 'uA', 'view', dt(2024, 1, 2, 10, 0)),
        act('4', 'uA', 'view', dt(2024, 1, 3, 11, 0)),
        act('5', 'uA', 'click', dt(2024, 1, 2, 12, 0)),
        act('6', 'uA', 'purchase', dt(2024, 1, 4, 9, 0)),
        act('7', 'other', 'view', dt(2024, 1, 1, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const groups = dash.aggregateByAction('uA')
      expect(groups.length).toBe(3)
      // 'view' should be first with count 3
      expect(groups[0].action).toBe('view')
      expect(groups[0].count).toBe(3)
      expect(groups[0].percentage).toBe(parseFloat(((3 / 6) * 100).toFixed(2)))
      expect(groups[0].firstOccurrence.getTime()).toBe(dt(2024, 1, 1, 9, 0).getTime())
      expect(groups[0].lastOccurrence.getTime()).toBe(dt(2024, 1, 3, 11, 0).getTime())
      // 'click' count 2
      expect(groups[1].action).toBe('click')
      expect(groups[1].count).toBe(2)
      // 'purchase' count 1
      expect(groups[2].action).toBe('purchase')
      expect(groups[2].count).toBe(1)
    })

    it('returns empty array when no activities for user', () => {
      const dash = new ActivityDashboard([])
      expect(dash.aggregateByAction('u-none')).toEqual([])
    })
  })

  describe('getTopActions_old', () => {
    it('returns all action groups sorted by count desc, ignoring provided limit', () => {
      const activities = [
        act('1', 'uT', 'x', dt(2024, 1, 1, 9, 0)),
        act('2', 'uT', 'x', dt(2024, 1, 1, 10, 0)),
        act('3', 'uT', 'y', dt(2024, 1, 2, 11, 0)),
        act('4', 'uT', 'z', dt(2024, 1, 3, 12, 0)),
        act('5', 'uT', 'y', dt(2024, 1, 4, 13, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const res = dash.getTopActions_old('uT', 1)
      expect(res.length).toBe(3)
      expect(res[0].action).toBe('x')
      expect(res[0].count).toBe(2)
      expect(res[1].action).toBe('y')
      expect(res[1].count).toBe(2)
      expect(res[2].action).toBe('z')
      expect(res[2].count).toBe(1)
    })
  })

  describe('getTopActions', () => {
    it('returns top N action groups limited by "limit"', () => {
      const activities = [
        act('1', 'uTop', 'a', dt(2024, 1, 1, 9, 0)),
        act('2', 'uTop', 'a', dt(2024, 1, 1, 10, 0)),
        act('3', 'uTop', 'b', dt(2024, 1, 2, 9, 0)),
        act('4', 'uTop', 'b', dt(2024, 1, 2, 10, 0)),
        act('5', 'uTop', 'b', dt(2024, 1, 2, 11, 0)),
        act('6', 'uTop', 'c', dt(2024, 1, 3, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const top2 = dash.getTopActions('uTop', 2)
      expect(top2.length).toBe(2)
      expect(top2[0].action).toBe('b')
      expect(top2[0].count).toBe(3)
      expect(top2[1].action).toBe('a')
      expect(top2[1].count).toBe(2)
    })

    it('when limit exceeds available groups, returns all groups', () => {
      const activities = [
        act('1', 'uTop2', 'a', dt(2024, 1, 1, 9, 0)),
        act('2', 'uTop2', 'b', dt(2024, 1, 1, 10, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const top5 = dash.getTopActions('uTop2', 5)
      expect(top5.length).toBe(2)
      const actions = top5.map(g => g.action).sort()
      expect(actions).toEqual(['a', 'b'])
    })
  })

  describe('calculateEngagementScore', () => {
    it('computes a non-trivial score based on volume, diversity, and frequency', () => {
      const activities = [
        act('1', 'uE', 'login', dt(2024, 1, 1, 10, 0)),
        act('2', 'uE', 'view', dt(2024, 1, 1, 10, 5)),
        act('3', 'uE', 'view', dt(2024, 1, 1, 10, 10)),
        act('4', 'uE', 'logout', dt(2024, 1, 1, 11, 0)),
        act('5', 'uE', 'view', dt(2024, 1, 2, 12, 0)),
        act('6', 'uE', 'login', dt(2024, 1, 3, 9, 0))
      ]
      const dash = new ActivityDashboard(activities)
      // From earlier summary: volume=6 -> 6/100*30=1.8; diversity=3 -> 3/10*30=9; frequency=3 actions/day -> 3/5*40=24
      expect(dash.calculateEngagementScore('uE')).toBe(34.8)
    })

    it('caps each component and returns 100 when all caps reached', () => {
      const many: ReturnType<typeof act>[] = []
      const base = dt(2024, 8, 1, 0, 0)
      // Create 150 actions across the same day to ensure actionsPerDay >= 5 and total >= 100
      for (let i = 0; i < 150; i++) {
        const actionName = `a${i % 12}` // 12 unique actions -> diversity capped at 10
        const time = new Date(base.getTime() + i * 60_000) // 1 minute apart
        many.push(act(`id_${i}`, 'uCap', actionName, time))
      }
      const dash = new ActivityDashboard(many)
      expect(dash.calculateEngagementScore('uCap')).toBe(100)
    })
  })

  describe('aggregate first/last occurrence with unsorted input', () => {
    it('determines first and last occurrence correctly regardless of input order', () => {
      const activities = [
        act('1', 'uO', 'view', dt(2024, 9, 1, 12, 0)),
        act('2', 'uO', 'view', dt(2024, 9, 1, 10, 0)),
        act('3', 'uO', 'view', dt(2024, 9, 1, 11, 0))
      ]
      const dash = new ActivityDashboard(activities)
      const groups = dash.aggregateByAction('uO')
      const view = groups.find(g => g.action === 'view')!
      expect(view.firstOccurrence.getTime()).toBe(dt(2024, 9, 1, 10, 0).getTime())
      expect(view.lastOccurrence.getTime()).toBe(dt(2024, 9, 1, 12, 0).getTime())
    })
  })
})