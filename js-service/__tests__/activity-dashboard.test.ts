import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

const d = (y: number, m: number, day: number, h: number = 0, min: number = 0) =>
  new Date(y, m - 1, day, h, min, 0, 0)

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

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard - getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const res = dash.getUserSummary('u1')
    expect(res).toBeNull()
  })

  it('computes totals, uniqueActions, mostFrequentAction, actionsPerDay and averageActionsPerSession (same day, two sessions)', () => {
    const activities: Act[] = [
      act('1', 'u1', 'click', d(2024, 1, 1, 9, 0)),
      act('2', 'u1', 'click', d(2024, 1, 1, 9, 10)),
      act('3', 'u1', 'click', d(2024, 1, 1, 9, 20)),
      act('4', 'u1', 'view', d(2024, 1, 1, 10, 1)), // > 30 mins after 9:20 -> new session
      act('5', 'u1', 'view', d(2024, 1, 1, 10, 5))
    ]
    const dash = new ActivityDashboard(activities)

    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    expect(res!.totalActions).toBe(5)
    expect(res!.uniqueActions).toBe(2)
    expect(res!.mostFrequentAction).toBe('click')
    expect(res!.actionsPerDay).toBe(5) // all within the same day -> daysActive = 1
    expect(res!.averageActionsPerSession).toBe(2.5) // 5 actions over 2 sessions
  })

  it('computes actionsPerDay across multiple days using ceil day span', () => {
    const activities: Act[] = [
      act('1', 'u1', 'click', d(2024, 1, 1, 9, 0)),
      act('2', 'u1', 'view', d(2024, 1, 1, 12, 0)),
      act('3', 'u1', 'click', d(2024, 1, 2, 10, 0)),
      act('4', 'u1', 'view', d(2024, 1, 2, 10, 10)),
      act('5', 'u1', 'click', d(2024, 1, 2, 11, 0)) // ~26 hours from first -> daysActive = ceil(26/24) = 2
    ]
    const dash = new ActivityDashboard(activities)

    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    expect(res!.totalActions).toBe(5)
    expect(res!.actionsPerDay).toBe(2.5) // 5 actions / 2 days
  })

  it('averageActionsPerSession treats exactly 30-minute gaps as same session', () => {
    const activities: Act[] = [
      act('1', 'u1', 'click', d(2024, 1, 1, 9, 0)),
      act('2', 'u1', 'click', d(2024, 1, 1, 9, 30)), // exactly 30 min -> same session
      act('3', 'u1', 'view', d(2024, 1, 1, 10, 0)) // exactly 30 min from 9:30 -> same session
    ]
    const dash = new ActivityDashboard(activities)
    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    expect(res!.averageActionsPerSession).toBe(3) // all in one session
  })

  it('mostFrequentAction matches the only action present', () => {
    const activities: Act[] = [act('1', 'u1', 'download', d(2024, 1, 1, 9, 0))]
    const dash = new ActivityDashboard(activities)
    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    expect(res!.mostFrequentAction).toBe('download')
    expect(res!.uniqueActions).toBe(1)
    expect(res!.totalActions).toBe(1)
  })
})

describe('ActivityDashboard - getActivityTrends', () => {
  it('returns empty array for user with no activities', () => {
    const dash = new ActivityDashboard([])
    const res = dash.getActivityTrends('u1', 'day')
    expect(res).toEqual([])
  })

  it('groups by day with correct counts and growthRate', () => {
    const activities: Act[] = [
      act('1', 'u1', 'click', d(2024, 1, 1, 9, 0)),
      act('2', 'u1', 'view', d(2024, 1, 1, 10, 0)),
      act('3', 'u1', 'click', d(2024, 1, 2, 9, 0)),
      act('4', 'u1', 'view', d(2024, 1, 2, 10, 0)),
      act('5', 'u1', 'share', d(2024, 1, 2, 11, 0))
    ]
    const dash = new ActivityDashboard(activities)

    const res = dash.getActivityTrends('u1', 'day')
    expect(res.length).toBe(2)
    expect(res[0]).toEqual({ period: '2024-01-01', count: 2, growthRate: 0 })
    expect(res[1]).toEqual({ period: '2024-01-02', count: 3, growthRate: 50 })
  })

  it('growthRate rounds to two decimals (e.g., 33.33)', () => {
    const activities: Act[] = [
      act('1', 'u1', 'a', d(2024, 1, 1, 9, 0)),
      act('2', 'u1', 'a', d(2024, 1, 1, 10, 0)),
      act('3', 'u1', 'a', d(2024, 1, 1, 11, 0)),
      act('4', 'u1', 'a', d(2024, 1, 2, 9, 0)),
      act('5', 'u1', 'a', d(2024, 1, 2, 10, 0)),
      act('6', 'u1', 'a', d(2024, 1, 2, 11, 0)),
      act('7', 'u1', 'a', d(2024, 1, 2, 12, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const res = dash.getActivityTrends('u1', 'day')
    expect(res.length).toBe(2)
    expect(res[0].count).toBe(3)
    expect(res[1].count).toBe(4)
    expect(res[1].growthRate).toBe(33.33)
  })

  it('groups by hour with lexicographically sorted periods', () => {
    const activities: Act[] = [
      act('1', 'u1', 'click', d(2024, 1, 1, 9, 10)),
      act('2', 'u1', 'view', d(2024, 1, 1, 9, 20)),
      act('3', 'u1', 'click', d(2024, 1, 1, 10, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const res = dash.getActivityTrends('u1', 'hour')
    expect(res).toEqual([
      { period: '2024-01-01 09:00', count: 2, growthRate: 0 },
      { period: '2024-01-01 10:00', count: 1, growthRate: -50 }
    ])
  })

  it('groups by month with sorted periods', () => {
    const activities: Act[] = [
      act('1', 'u1', 'click', d(2024, 1, 10, 9, 0)),
      act('2', 'u1', 'view', d(2024, 1, 11, 10, 0)),
      act('3', 'u1', 'share', d(2024, 2, 5, 11, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const res = dash.getActivityTrends('u1', 'month')
    expect(res).toEqual([
      { period: '2024-01', count: 2, growthRate: 0 },
      { period: '2024-02', count: 1, growthRate: -50 }
    ])
  })

  it('groups by week; events in same week share a key; later week is different', () => {
    const activities: Act[] = [
      act('1', 'u1', 'a', d(2024, 1, 3, 9, 0)), // Week 1 by implementation
      act('2', 'u1', 'b', d(2024, 1, 4, 10, 0)), // Same week
      act('3', 'u1', 'c', d(2024, 1, 15, 11, 0)) // Different week by implementation
    ]
    const dash = new ActivityDashboard(activities)
    const res = dash.getActivityTrends('u1', 'week')
    expect(res.length).toBe(2)
    expect(res[0].count).toBe(2)
    expect(res[1].count).toBe(1)
    expect(typeof res[0].period).toBe('string')
    expect(typeof res[1].period).toBe('string')
    expect(res[0].period).not.toBe(res[1].period)
  })
})

describe('ActivityDashboard - filterByDateRange', () => {
  it('returns only activities for the user within inclusive range', () => {
    const activities: Act[] = [
      act('1', 'u1', 'a', d(2024, 1, 1, 9, 0)),
      act('2', 'u1', 'b', d(2024, 1, 1, 12, 0)),
      act('3', 'u1', 'c', d(2024, 1, 1, 15, 0)),
      act('4', 'u2', 'x', d(2024, 1, 1, 12, 0)) // different user
    ]
    const dash = new ActivityDashboard(activities)
    const res = dash.filterByDateRange('u1', d(2024, 1, 1, 12, 0), d(2024, 1, 1, 15, 0))
    expect(res.map(r => r.id)).toEqual(['2', '3'])
  })
})

describe('ActivityDashboard - aggregateByAction', () => {
  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const res = dash.aggregateByAction('u1')
    expect(res).toEqual([])
  })

  it('aggregates counts, percentages, first and last occurrence; sorted by count desc', () => {
    const activities: Act[] = [
      act('1', 'u1', 'click', d(2024, 1, 1, 9, 0)),
      act('2', 'u1', 'click', d(2024, 1, 1, 10, 0)),
      act('3', 'u1', 'click', d(2024, 1, 1, 11, 0)),
      act('4', 'u1', 'view', d(2024, 1, 1, 12, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const groups = dash.aggregateByAction('u1')
    expect(groups.length).toBe(2)

    const click = groups.find(g => g.action === 'click')!
    const view = groups.find(g => g.action === 'view')!

    expect(click.count).toBe(3)
    expect(click.percentage).toBe(75)
    expect(click.firstOccurrence.getTime()).toBe(d(2024, 1, 1, 9, 0).getTime())
    expect(click.lastOccurrence.getTime()).toBe(d(2024, 1, 1, 11, 0).getTime())

    expect(view.count).toBe(1)
    expect(view.percentage).toBe(25)
    expect(view.firstOccurrence.getTime()).toBe(d(2024, 1, 1, 12, 0).getTime())
    expect(view.lastOccurrence.getTime()).toBe(d(2024, 1, 1, 12, 0).getTime())

    expect(groups[0].count >= groups[1].count).toBe(true)
  })
})

describe('ActivityDashboard - getTopActions', () => {
  it('returns top N actions by count', () => {
    const activities: Act[] = [
      act('1', 'u1', 'click', d(2024, 1, 1, 9, 0)),
      act('2', 'u1', 'click', d(2024, 1, 1, 10, 0)),
      act('3', 'u1', 'view', d(2024, 1, 1, 11, 0)),
      act('4', 'u1', 'share', d(2024, 1, 1, 12, 0)),
      act('5', 'u1', 'view', d(2024, 1, 1, 12, 30))
    ]
    const dash = new ActivityDashboard(activities)
    const top2 = dash.getTopActions('u1', 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('click')
    expect(top2[0].count).toBe(2)
    expect(top2[1].action).toBe('view')
    expect(top2[1].count).toBe(2)
  })

  it('default limit returns at most 5 groups', () => {
    const acts: Act[] = []
    for (let i = 0; i < 6; i++) {
      acts.push(act(String(i + 1), 'u1', `a${i}`, d(2024, 1, 1, 9, i)))
    }
    const dash = new ActivityDashboard(acts)
    const top = dash.getTopActions('u1')
    expect(top.length).toBe(5)
  })

  it('returns fewer than limit when not enough groups', () => {
    const activities: Act[] = [
      act('1', 'u1', 'x', d(2024, 1, 1, 9, 0)),
      act('2', 'u1', 'y', d(2024, 1, 1, 10, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const top5 = dash.getTopActions('u1', 5)
    expect(top5.length).toBe(2)
  })
})

describe('ActivityDashboard - calculateEngagementScore', () => {
  it('returns 0 when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(0)
  })

  it('caps each component and returns 100 when all caps reached', () => {
    const acts: Act[] = []
    // 100 actions in one day; >10 unique actions; actionsPerDay >> 5
    const actions = Array.from({ length: 12 }, (_, i) => `a${i}`)
    for (let i = 0; i < 100; i++) {
      acts.push(act(String(i + 1), 'u1', actions[i % actions.length], d(2024, 1, 1, 0, i % 60)))
    }
    const dash = new ActivityDashboard(acts)
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBe(100)
  })

  it('computes score with partial caps', () => {
    // totalActions: 20 -> volumeScore = min(20/100,1)*30 = 6
    // uniqueActions: 4 -> diversityScore = min(4/10,1)*30 = 12
    // actionsPerDay: across two days 10 events each over 24h + small => daysActive=2, 20/2=10 -> frequencyScore capped at 40
    const acts: Act[] = []
    for (let i = 0; i < 10; i++) {
      acts.push(act(`d1-${i}`, 'u1', `a${i % 4}`, d(2024, 1, 1, 9, i)))
    }
    for (let i = 0; i < 10; i++) {
      acts.push(act(`d2-${i}`, 'u1', `a${i % 4}`, d(2024, 1, 2, 10, i)))
    }
    const dash = new ActivityDashboard(acts)
    const score = dash.calculateEngagementScore('u1')
    expect(score).toBeCloseTo(6 + 12 + 40, 2)
  })
})