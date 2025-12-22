import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

type Activity = {
  id: string
  user_id: string
  action: string
  timestamp: Date
  metadata?: Record<string, any>
}

const act = (overrides: Partial<Activity> & Pick<Activity, 'id' | 'user_id' | 'action' | 'timestamp'>): Activity => ({
  metadata: {},
  ...overrides
})

describe('ActivityDashboard', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('constructor / basic behavior', () => {
    it('defaults to no activities; getUserSummary returns null; trends/aggregations return empty; engagement is 0', () => {
      const dash = new ActivityDashboard()

      expect(dash.getUserSummary('u1')).toBeNull()
      expect(dash.getActivityTrends('u1')).toEqual([])
      expect(dash.aggregateByAction('u1')).toEqual([])
      expect(dash.getTopActions('u1')).toEqual([])
      expect(dash.calculateEngagementScore('u1')).toBe(0)
    })
  })

  describe('getUserSummary', () => {
    it('returns null when user has no activities (even if other users do)', () => {
      const dash = new ActivityDashboard([
        act({ id: 'a1', user_id: 'other', action: 'login', timestamp: new Date('2024-01-01T00:00:00Z') })
      ])

      expect(dash.getUserSummary('u1')).toBeNull()
    })

    it('computes totals, unique actions, most frequent action; daysActive is at least 1', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'click', timestamp: new Date('2024-01-01T10:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'click', timestamp: new Date('2024-01-01T12:00:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'view', timestamp: new Date('2024-01-01T13:00:00Z') }),
        act({ id: '4', user_id: 'u2', action: 'click', timestamp: new Date('2024-01-01T14:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(3)
      expect(summary!.uniqueActions).toBe(2)
      expect(summary!.mostFrequentAction).toBe('click')
      expect(summary!.actionsPerDay).toBe(3) // daysActive=1
    })

    it('actionsPerDay uses ceil day span and is rounded to 2 decimals', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T00:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'b', timestamp: new Date('2024-01-02T00:00:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'c', timestamp: new Date('2024-01-03T00:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u1')!

      // span: Jan1 -> Jan3 = 2 days exactly; ceil(2)=2; 3/2=1.5
      expect(summary.actionsPerDay).toBe(1.5)
    })

    it('averageActionsPerSession counts new session only when gap is strictly greater than 30 minutes', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T10:00:00Z') }),
        // exactly 30 minutes later => still same session
        act({ id: '2', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T10:30:00Z') }),
        // 31 minutes later => new session
        act({ id: '3', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T11:01:00Z') })
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u1')!

      // sessions: [10:00,10:30] and [11:01] => 2 sessions => 3/2=1.5
      expect(summary.averageActionsPerSession).toBe(1.5)
    })

    it('averageActionsPerSession is independent of input order (sorts by timestamp)', () => {
      const activities: Activity[] = [
        act({ id: '3', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T12:00:00Z') }),
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T10:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T10:20:00Z') })
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u1')!

      // all within 30 mins of prior after sorting => 1 session => avg=3
      expect(summary.averageActionsPerSession).toBe(3)
    })

    it('mostFrequentAction uses strict greater-than; ties keep earliest max encountered by insertion order of keys', () => {
      const activities: Activity[] = [
        // actions encountered in counts in this order: b, a
        act({ id: '1', user_id: 'u1', action: 'b', timestamp: new Date('2024-01-01T10:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T10:01:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T10:02:00Z') }),
        act({ id: '4', user_id: 'u1', action: 'b', timestamp: new Date('2024-01-01T10:03:00Z') })
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u1')!

      // counts: b=2, a=2 => since only ">" updates, first to reach max=2 stays.
      // iteration order is insertion order of keys: b then a, so b stays.
      expect(summary.mostFrequentAction).toBe('b')
    })
  })

  describe('filterByDateRange', () => {
    it('includes boundaries (>= startDate and <= endDate) and filters by user', () => {
      const start = new Date('2024-01-01T00:00:00Z')
      const end = new Date('2024-01-02T00:00:00Z')
      const activities: Activity[] = [
        act({ id: 's', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T00:00:00Z') }),
        act({ id: 'm', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T12:00:00Z') }),
        act({ id: 'e', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-02T00:00:00Z') }),
        act({ id: 'o', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-02T00:00:00.001Z') }),
        act({ id: 'x', user_id: 'u2', action: 'a', timestamp: new Date('2024-01-01T12:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const result = dash.filterByDateRange('u1', start, end)
      expect(result.map(r => r.id).sort()).toEqual(['e', 'm', 's'])
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard([
        act({ id: '1', user_id: 'u2', action: 'a', timestamp: new Date('2024-01-01T00:00:00Z') })
      ])
      expect(dash.aggregateByAction('u1')).toEqual([])
    })

    it('aggregates count, percentage (2 decimals), first/last occurrence; sorts by count desc', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'view', timestamp: new Date('2024-01-03T10:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'click', timestamp: new Date('2024-01-01T10:00:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'click', timestamp: new Date('2024-01-02T10:00:00Z') }),
        act({ id: '4', user_id: 'u1', action: 'view', timestamp: new Date('2024-01-01T09:00:00Z') }),
        act({ id: '5', user_id: 'u1', action: 'click', timestamp: new Date('2024-01-01T08:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const groups = dash.aggregateByAction('u1')
      expect(groups).toHaveLength(2)
      expect(groups[0].action).toBe('click')
      expect(groups[0].count).toBe(3)
      expect(groups[0].percentage).toBe(60)
      expect(groups[0].firstOccurrence.toISOString()).toBe(new Date('2024-01-01T08:00:00Z').toISOString())
      expect(groups[0].lastOccurrence.toISOString()).toBe(new Date('2024-01-02T10:00:00Z').toISOString())

      expect(groups[1].action).toBe('view')
      expect(groups[1].count).toBe(2)
      expect(groups[1].percentage).toBe(40)
      expect(groups[1].firstOccurrence.toISOString()).toBe(new Date('2024-01-01T09:00:00Z').toISOString())
      expect(groups[1].lastOccurrence.toISOString()).toBe(new Date('2024-01-03T10:00:00Z').toISOString())
    })

    it('percentage is rounded to 2 decimals using toFixed, e.g., 1 of 3 => 33.33', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T00:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'b', timestamp: new Date('2024-01-01T00:01:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'b', timestamp: new Date('2024-01-01T00:02:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const groups = dash.aggregateByAction('u1')
      const a = groups.find(g => g.action === 'a')!
      const b = groups.find(g => g.action === 'b')!

      expect(a.count).toBe(1)
      expect(a.percentage).toBe(33.33)
      expect(b.count).toBe(2)
      expect(b.percentage).toBe(66.67)
    })
  })

  describe('getTopActions and getTopActions_old', () => {
    it('getTopActions slices results from aggregateByAction according to limit', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T00:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'b', timestamp: new Date('2024-01-01T00:01:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'b', timestamp: new Date('2024-01-01T00:02:00Z') }),
        act({ id: '4', user_id: 'u1', action: 'c', timestamp: new Date('2024-01-01T00:03:00Z') }),
        act({ id: '5', user_id: 'u1', action: 'c', timestamp: new Date('2024-01-01T00:04:00Z') }),
        act({ id: '6', user_id: 'u1', action: 'c', timestamp: new Date('2024-01-01T00:05:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const top1 = dash.getTopActions('u1', 1)
      expect(top1).toHaveLength(1)
      expect(top1[0].action).toBe('c')
      expect(top1[0].count).toBe(3)

      const top2 = dash.getTopActions('u1', 2)
      expect(top2).toHaveLength(2)
      expect(top2.map(t => t.action)).toEqual(['c', 'b'])
    })

    it('getTopActions_old ignores limit parameter in implementation (returns all action groups)', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T00:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'b', timestamp: new Date('2024-01-01T00:01:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'c', timestamp: new Date('2024-01-01T00:02:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const result = dash.getTopActions_old('u1', 1)
      expect(result).toHaveLength(3)
      expect(result.map(r => r.action).sort()).toEqual(['a', 'b', 'c'])
    })

    it('getTopActions_old computes first/last occurrence per action and percentage', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T10:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T09:00:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'b', timestamp: new Date('2024-01-01T11:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const groups = dash.getTopActions_old('u1')
      const a = groups.find(g => g.action === 'a')!
      const b = groups.find(g => g.action === 'b')!

      expect(a.count).toBe(2)
      expect(a.percentage).toBe(66.67)
      expect(a.firstOccurrence.toISOString()).toBe(new Date('2024-01-01T09:00:00Z').toISOString())
      expect(a.lastOccurrence.toISOString()).toBe(new Date('2024-01-01T10:00:00Z').toISOString())

      expect(b.count).toBe(1)
      expect(b.percentage).toBe(33.33)
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const dash = new ActivityDashboard([
        act({ id: '1', user_id: 'u2', action: 'a', timestamp: new Date('2024-01-01T00:00:00Z') })
      ])
      expect(dash.getActivityTrends('u1', 'day')).toEqual([])
    })

    it('groups by day (default) and sorts periods lexicographically; growthRate is 0 for first period', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-02T10:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T10:00:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-02T12:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const trends = dash.getActivityTrends('u1')
      expect(trends.map(t => t.period)).toEqual(['2024-01-01', '2024-01-02'])
      expect(trends[0]).toEqual({ period: '2024-01-01', count: 1, growthRate: 0 })
      expect(trends[1]).toEqual({ period: '2024-01-02', count: 2, growthRate: 100 })
    })

    it('groups by hour and formats as YYYY-MM-DD HH:00 (zero-padded)', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T09:15:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'b', timestamp: new Date('2024-01-01T09:59:59Z') }),
        act({ id: '3', user_id: 'u1', action: 'c', timestamp: new Date('2024-01-01T10:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const trends = dash.getActivityTrends('u1', 'hour')
      expect(trends.map(t => t.period)).toEqual(['2024-01-01 09:00', '2024-01-01 10:00'])
      expect(trends[0].count).toBe(2)
      expect(trends[0].growthRate).toBe(0)
      expect(trends[1].count).toBe(1)
      expect(trends[1].growthRate).toBe(-50)
    })

    it('groups by month and uses YYYY-MM key', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-15T00:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'a', timestamp: new Date('2024-02-01T00:00:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'a', timestamp: new Date('2024-02-20T00:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const trends = dash.getActivityTrends('u1', 'month')
      expect(trends.map(t => t.period)).toEqual(['2024-01', '2024-02'])
      expect(trends[0].count).toBe(1)
      expect(trends[1].count).toBe(2)
      expect(trends[1].growthRate).toBe(100)
    })

    it('week grouping uses getWeekNumber algorithm and yields keys like YYYY-W##', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T00:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-02T00:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const trends = dash.getActivityTrends('u1', 'week')
      expect(trends).toHaveLength(1)
      expect(trends[0].period).toMatch(/^2024-W\d{2}$/)
      expect(trends[0].count).toBe(2)
      expect(trends[0].growthRate).toBe(0)
    })

    it('growthRate is rounded to 2 decimals', () => {
      const activities: Activity[] = [
        // period 1: 3
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T00:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T01:00:00Z') }),
        act({ id: '3', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T02:00:00Z') }),
        // period 2: 2 => (2-3)/3*100 = -33.333... => -33.33
        act({ id: '4', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-02T00:00:00Z') }),
        act({ id: '5', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-02T01:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const trends = dash.getActivityTrends('u1', 'day')
      expect(trends.map(t => t.period)).toEqual(['2024-01-01', '2024-01-02'])
      expect(trends[1].growthRate).toBe(-33.33)
    })

    it('unknown periodType defaults to day formatting (via default branch)', () => {
      const activities: Activity[] = [
        act({ id: '1', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T10:00:00Z') }),
        act({ id: '2', user_id: 'u1', action: 'a', timestamp: new Date('2024-01-01T11:00:00Z') })
      ]
      const dash = new ActivityDashboard(activities)

      const trends = dash.getActivityTrends('u1', 'day')
      expect(trends).toHaveLength(1)
      expect(trends[0].period).toBe('2024-01-01')

      const trendsUnknown = dash.getActivityTrends('u1', 'quarter' as any)
      expect(trendsUnknown).toHaveLength(1)
      expect(trendsUnknown[0].period).toBe('2024-01-01')
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when getUserSummary is null', () => {
      const dash = new ActivityDashboard([])
      expect(dash.calculateEngagementScore('u1')).toBe(0)
    })

    it('calculates weighted score and rounds to 2 decimals', () => {
      // totalActions=50 => volumeScore=min(0.5,1)*30=15
      // uniqueActions=5 => diversityScore=min(0.5,1)*30=15
      // actionsPerDay=1.67 => frequencyScore=min(0.334,1)*40=13.36
      // total = 43.36
      const activities: Activity[] = []
      const start = new Date('2024-01-01T00:00:00Z')
      for (let i = 0; i < 50; i++) {
        const action = i < 10 ? `action${i % 5}` : `action${i % 5}` // 5 unique
        const ts = new Date(start.getTime() + (i % 3) * 24 * 60 * 60 * 1000) // across 3 calendar days
        activities.push(act({ id: String(i), user_id: 'u1', action, timestamp: ts }))
      }
      const dash = new ActivityDashboard(activities)

      const summary = dash.getUserSummary('u1')!
      expect(summary.totalActions).toBe(50)
      expect(summary.uniqueActions).toBe(5)
      expect(summary.actionsPerDay).toBe(16.67) // daysActive: ceil(2)=2; 50/3days spread? Actually ts uses i%3 => last-first=2 days => 25.00
      // Adjust expectation to actual computed behavior:
      // first=day0, last=day2 => ceil(2)=2 daysActive; 50/2=25.00
      expect(summary.actionsPerDay).toBe(25)

      // frequencyScore caps at 1 when actionsPerDay/5 > 1
      // volumeScore=15, diversityScore=15, frequencyScore=40 => 70
      expect(dash.calculateEngagementScore('u1')).toBe(70)
    })

    it('caps each component at its max (totalActions>=100, uniqueActions>=10, actionsPerDay>=5)', () => {
      const activities: Activity[] = []
      const base = new Date('2024-01-01T00:00:00Z')
      for (let i = 0; i < 120; i++) {
        activities.push(
          act({
            id: `id-${i}`,
            user_id: 'u1',
            action: `a${i % 12}`, // 12 unique
            timestamp: new Date(base.getTime() + i * 60 * 1000) // all same day => high actionsPerDay
          })
        )
      }
      const dash = new ActivityDashboard(activities)

      // volume max 30 + diversity max 30 + frequency max 40 = 100
      expect(dash.calculateEngagementScore('u1')).toBe(100)
    })
  })
})