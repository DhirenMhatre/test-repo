import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

afterEach(() => {
  jest.clearAllMocks()
})

const makeAct = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Activity => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata
})

describe('ActivityDashboard', () => {
  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const dash = new ActivityDashboard([])
      const summary = dash.getUserSummary('u1')
      expect(summary).toBeNull()
    })

    it('calculates totals, uniqueActions, actionsPerDay, mostFrequentAction (tie-breaking), and averageActionsPerSession', () => {
      const base = new Date(2024, 0, 1, 9, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'login', new Date(base.getTime())),
        makeAct('2', 'u1', 'view', new Date(base.getTime() + 10 * 60 * 1000)),
        makeAct('3', 'u1', 'view', new Date(base.getTime() + 25 * 60 * 1000)),
        makeAct('4', 'u1', 'click', new Date(base.getTime() + 3 * 60 * 60 * 1000)),
        makeAct('5', 'u1', 'click', new Date(base.getTime() + 3 * 60 * 60 * 1000 + 5 * 60 * 1000)),
        makeAct('x', 'u2', 'other', new Date(base.getTime())) // different user
      ]
      const dash = new ActivityDashboard(acts)
      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(5)
      expect(summary!.uniqueActions).toBe(3)
      // actions within same day -> 5 per day
      expect(summary!.actionsPerDay).toBe(5)
      // tie between 'view' and 'click' (2 each). The first encountered is 'view'
      expect(summary!.mostFrequentAction).toBe('view')
      // sessions: first three within 30 minutes (1), then > 30 min gap to next two (2) => 2 sessions => avg 2.5
      expect(summary!.averageActionsPerSession).toBe(2.5)
    })

    it('computes daysActive across multiple days and rounds actionsPerDay to 2 decimals', () => {
      const d1 = new Date(2024, 0, 1, 10, 0, 0)
      const d2 = new Date(2024, 0, 2, 11, 0, 0)
      const d3 = new Date(2024, 0, 3, 9, 0, 0) // ~47 hours after d1 => ceil(1.958..) => 2 daysActive
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', d1),
        makeAct('2', 'u1', 'b', d2),
        makeAct('3', 'u1', 'c', d3)
      ]
      const dash = new ActivityDashboard(acts)
      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(3)
      expect(summary!.uniqueActions).toBe(3)
      expect(summary!.actionsPerDay).toBe(1.5)
      expect(summary!.averageActionsPerSession).toBe(1) // every event separated by > 30 minutes => 3 sessions => 3/3=1
    })
  })

  describe('filterByDateRange', () => {
    it('returns activities in inclusive date range boundaries', () => {
      const d1 = new Date(2024, 0, 1, 12, 0, 0)
      const d2 = new Date(2024, 0, 1, 13, 0, 0)
      const d3 = new Date(2024, 0, 1, 14, 0, 0)
      const acts: Activity[] = [
        makeAct('a', 'u1', 'x', d1),
        makeAct('b', 'u1', 'y', d2),
        makeAct('c', 'u1', 'z', d3),
        makeAct('d', 'u2', 'z', d2)
      ]
      const dash = new ActivityDashboard(acts)
      const res = dash.filterByDateRange('u1', d2, d3)
      expect(res.map(r => r.id)).toEqual(['b', 'c'])
    })
  })

  describe('aggregateByAction', () => {
    it('groups by action with counts, percentages, and first/last occurrence, sorted by count desc', () => {
      const base = new Date(2024, 0, 1, 9, 0, 0)
      const a1 = makeAct('1', 'u1', 'login', new Date(base.getTime()))
      const a2 = makeAct('2', 'u1', 'view', new Date(base.getTime() + 10 * 60 * 1000))
      const a3 = makeAct('3', 'u1', 'view', new Date(base.getTime() + 25 * 60 * 1000))
      const a4 = makeAct('4', 'u1', 'click', new Date(base.getTime() + 3 * 60 * 60 * 1000))
      const a5 = makeAct('5', 'u1', 'click', new Date(base.getTime() + 3 * 60 * 60 * 1000 + 5 * 60 * 1000))
      const dash = new ActivityDashboard([a1, a2, a3, a4, a5])
      const groups = dash.aggregateByAction('u1')

      expect(groups.length).toBe(3)
      const byAction: Record<string, typeof groups[number]> = Object.fromEntries(groups.map(g => [g.action, g]))

      expect(byAction['view'].count).toBe(2)
      expect(byAction['view'].percentage).toBe(40)
      expect(byAction['view'].firstOccurrence.getTime()).toBe(a2.timestamp.getTime())
      expect(byAction['view'].lastOccurrence.getTime()).toBe(a3.timestamp.getTime())

      expect(byAction['click'].count).toBe(2)
      expect(byAction['click'].percentage).toBe(40)
      expect(byAction['click'].firstOccurrence.getTime()).toBe(a4.timestamp.getTime())
      expect(byAction['click'].lastOccurrence.getTime()).toBe(a5.timestamp.getTime())

      expect(byAction['login'].count).toBe(1)
      expect(byAction['login'].percentage).toBe(20)

      // sorted by count desc; top groups should have count 2
      expect(groups[0].count).toBeGreaterThanOrEqual(groups[1].count)
      expect(groups[0].count).toBe(2)
      expect(groups[1].count).toBe(2)
    })

    it('returns empty array for user with no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.aggregateByAction('none')).toEqual([])
    })
  })

  describe('getTopActions_old', () => {
    it('returns all action groups sorted by count without limiting', () => {
      const base = new Date(2024, 0, 1, 10, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'x', new Date(base.getTime())),
        makeAct('2', 'u1', 'x', new Date(base.getTime() + 60 * 1000)),
        makeAct('3', 'u1', 'y', new Date(base.getTime() + 2 * 60 * 1000)),
        makeAct('4', 'u1', 'z', new Date(base.getTime() + 3 * 60 * 1000)),
        makeAct('5', 'u1', 'y', new Date(base.getTime() + 4 * 60 * 1000))
      ]
      const dash = new ActivityDashboard(acts)
      const groups = dash.getTopActions_old('u1')
      expect(groups.length).toBe(3)
      const top = groups[0]
      expect(top.action).toBe('x')
      expect(top.count).toBe(2)
      expect(top.percentage).toBe(40)
      expect(top.firstOccurrence.getTime()).toBe(acts[0].timestamp.getTime())
      expect(top.lastOccurrence.getTime()).toBe(acts[1].timestamp.getTime())
    })
  })

  describe('getTopActions', () => {
    it('returns top limited actions sorted by count', () => {
      const base = new Date(2024, 0, 1, 10, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'x', new Date(base.getTime())),
        makeAct('2', 'u1', 'x', new Date(base.getTime() + 60 * 1000)),
        makeAct('3', 'u1', 'y', new Date(base.getTime() + 2 * 60 * 1000)),
        makeAct('4', 'u1', 'y', new Date(base.getTime() + 3 * 60 * 1000)),
        makeAct('5', 'u1', 'y', new Date(base.getTime() + 4 * 60 * 1000)),
        makeAct('6', 'u1', 'z', new Date(base.getTime() + 5 * 60 * 1000))
      ]
      const dash = new ActivityDashboard(acts)
      const top1 = dash.getTopActions('u1', 1)
      expect(top1.length).toBe(1)
      expect(top1[0].action).toBe('y')
      expect(top1[0].count).toBe(3)

      const top2 = dash.getTopActions('u1', 2)
      expect(top2.length).toBe(2)
      expect(top2[0].action).toBe('y')
      expect(top2[1].action).toBe('x')
    })

    it('returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.getTopActions('uX', 5)).toEqual([])
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard([])
      expect(dash.getActivityTrends('u1')).toEqual([])
    })

    it('groups by day by default with growth rates', () => {
      const d1 = new Date(2024, 0, 1, 10, 0, 0)
      const d2a = new Date(2024, 0, 2, 11, 0, 0)
      const d2b = new Date(2024, 0, 2, 12, 0, 0)
      const d3 = new Date(2024, 0, 3, 9, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', d1),
        makeAct('2', 'u1', 'b', d2a),
        makeAct('3', 'u1', 'c', d2b),
        makeAct('4', 'u1', 'd', d3)
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1') // default 'day'
      expect(trends.length).toBe(3)
      // Sorted ascending by period string
      expect(trends[0].count).toBe(1)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].count).toBe(2)
      expect(trends[1].growthRate).toBe(100)
      expect(trends[2].count).toBe(1)
      expect(trends[2].growthRate).toBe(-50)
      expect(trends[0].period).toMatch(/^\d{4}-\d{2}-\d{2}$/)
      expect(trends[1].period).toMatch(/^\d{4}-\d{2}-\d{2}$/)
      expect(trends[2].period).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    })

    it('groups by hour with zero-padded hour and correct growth rates', () => {
      const day = new Date(2024, 0, 5, 9, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', new Date(2024, 0, 5, 9, 15, 0)),
        makeAct('2', 'u1', 'b', new Date(2024, 0, 5, 9, 45, 0)),
        makeAct('3', 'u1', 'c', new Date(2024, 0, 5, 10, 5, 0))
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'hour')
      expect(trends.length).toBe(2)
      expect(trends[0].period).toMatch(/^\d{4}-\d{2}-\d{2} 09:00$/)
      expect(trends[0].count).toBe(2)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].period).toMatch(/^\d{4}-\d{2}-\d{2} 10:00$/)
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBe(-50)
      expect(day.getTime()).toBeLessThan(new Date(2024, 0, 5, 10, 0, 0).getTime())
    })

    it('groups by week with formatted keys and correct sorting', () => {
      const w1a = new Date(2024, 0, 3, 10, 0, 0) // Week 1-ish
      const w2a = new Date(2024, 0, 10, 12, 0, 0) // Following week
      const w2b = new Date(2024, 0, 11, 13, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'x', w1a),
        makeAct('2', 'u1', 'y', w2a),
        makeAct('3', 'u1', 'z', w2b)
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'week')
      expect(trends.length).toBe(2)
      expect(trends[0].period).toMatch(/^2024-W\d{2}$/)
      expect(trends[1].period).toMatch(/^2024-W\d{2}$/)
      // growthRate for second week vs first: (2 - 1) / 1 = 100%
      expect(trends[0].count).toBe(1)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].count).toBe(2)
      expect(trends[1].growthRate).toBe(100)
      // Ensure lexicographic order matches chronological
      expect(trends[0].period < trends[1].period).toBe(true)
    })

    it('groups by month with zero-padded month and growth rates', () => {
      const jan = new Date(2024, 0, 20, 10, 0, 0)
      const mar1 = new Date(2024, 2, 1, 10, 0, 0)
      const mar2 = new Date(2024, 2, 15, 10, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', jan),
        makeAct('2', 'u1', 'b', mar1),
        makeAct('3', 'u1', 'c', mar2)
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'month')
      expect(trends.length).toBe(2)
      expect(trends[0].period).toBe('2024-01')
      expect(trends[1].period).toBe('2024-03')
      expect(trends[0].count).toBe(1)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].count).toBe(2)
      expect(trends[1].growthRate).toBe(100)
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when user has no activity summary', () => {
      const dash = new ActivityDashboard([])
      expect(dash.calculateEngagementScore('u1')).toBe(0)
    })

    it('caps at 100 when volume, diversity, and frequency reach maximums', () => {
      const base = new Date(2024, 0, 1, 9, 0, 0)
      const acts: Activity[] = []
      // 120 actions on same day, 12 unique actions => caps on all components
      const actions = Array.from({ length: 12 }, (_, i) => `a${i + 1}`)
      for (let i = 0; i < 120; i++) {
        acts.push(makeAct(`id-${i}`, 'u1', actions[i % actions.length], new Date(base.getTime() + i * 60 * 1000)))
      }
      const dash = new ActivityDashboard(acts)
      const score = dash.calculateEngagementScore('u1')
      expect(score).toBe(100)
    })

    it('computes score using formula with toFixed rounding', () => {
      const base = new Date(2024, 0, 1, 9, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'a', new Date(base.getTime())),
        makeAct('2', 'u1', 'a', new Date(base.getTime() + 60 * 1000)),
        makeAct('3', 'u1', 'a', new Date(base.getTime() + 2 * 60 * 1000)),
        makeAct('4', 'u1', 'a', new Date(base.getTime() + 3 * 60 * 1000)),
        makeAct('5', 'u1', 'a', new Date(base.getTime() + 4 * 60 * 1000)),
        makeAct('6', 'u1', 'a', new Date(base.getTime() + 5 * 60 * 1000)),
        makeAct('7', 'u1', 'a', new Date(base.getTime() + 6 * 60 * 1000)),
        makeAct('8', 'u1', 'b', new Date(base.getTime() + 7 * 60 * 1000)),
        makeAct('9', 'u1', 'b', new Date(base.getTime() + 8 * 60 * 1000)),
        makeAct('10', 'u1', 'b', new Date(base.getTime() + 9 * 60 * 1000))
      ]
      // totalActions = 10 -> volumeScore = (10/100)*30 = 3
      // uniqueActions = 2 -> diversityScore = (2/10)*30 = 6
      // actionsPerDay = 10 (same day) -> frequencyScore = min(10/5,1)*40 = 40
      // total 3 + 6 + 40 = 49
      const dash = new ActivityDashboard(acts)
      const score = dash.calculateEngagementScore('u1')
      expect(score).toBe(49)
    })
  })

  describe('miscellaneous behaviors', () => {
    it('mostFrequentAction prefers earlier encountered action on ties', () => {
      const base = new Date(2024, 0, 1, 9, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'B', new Date(base.getTime())),
        makeAct('2', 'u1', 'A', new Date(base.getTime() + 60 * 1000)),
        makeAct('3', 'u1', 'B', new Date(base.getTime() + 2 * 60 * 1000)),
        makeAct('4', 'u1', 'A', new Date(base.getTime() + 3 * 60 * 1000))
      ]
      const dash = new ActivityDashboard(acts)
      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      // B appears first and ties with A => B selected
      expect(summary!.mostFrequentAction).toBe('B')
    })

    it('getActivityTrends ignores periods with zero prior counts by setting growthRate to 0 when prevCount=0', () => {
      const d1 = new Date(2024, 0, 1, 10, 0, 0)
      const d2 = new Date(2024, 0, 3, 11, 0, 0)
      const acts: Activity[] = [
        makeAct('1', 'u1', 'x', d1),
        makeAct('2', 'u1', 'y', d2),
        makeAct('3', 'u1', 'z', d2)
      ]
      const dash = new ActivityDashboard(acts)
      const trends = dash.getActivityTrends('u1', 'day')
      expect(trends.length).toBe(2)
      // Previous count on first period is undefined -> 0 growth rate
      expect(trends[0].growthRate).toBe(0)
      // Second period prevCount=1, count=2 => 100
      expect(trends[1].growthRate).toBe(100)
    })

    it('getTopActions default limit is 5 and respects it when there are more actions', () => {
      const base = new Date(2024, 0, 1, 9, 0, 0)
      const acts: Activity[] = []
      const actions = ['a', 'b', 'c', 'd', 'e', 'f', 'g']
      // create varying counts: a:7, b:6, c:5, d:4, e:3, f:2, g:1
      actions.forEach((act, idx) => {
        const count = actions.length - idx
        for (let i = 0; i < count; i++) {
          acts.push(makeAct(`${act}-${i}`, 'u1', act, new Date(base.getTime() + (i + idx) * 60 * 1000)))
        }
      })
      const dash = new ActivityDashboard(acts)
      const top = dash.getTopActions('u1') // default limit 5
      expect(top.length).toBe(5)
      expect(top.map(t => t.action)).toEqual(['a', 'b', 'c', 'd', 'e'])
      expect(top.map(t => t.count)).toEqual([7, 6, 5, 4, 3])
    })
  })
})