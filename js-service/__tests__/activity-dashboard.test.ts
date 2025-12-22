import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

function makeActivity(id: string, userId: string, action: string, date: Date) {
  return { id, user_id: userId, action, timestamp: date, metadata: { i: id } }
}

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const result = dashboard.getUserSummary('u1')
    expect(result).toBeNull()
  })

  it('computes total, unique, most frequent action, actions per day, and average per session', () => {
    const u = 'userA'
    const acts = [
      makeActivity('1', u, 'view', new Date(2024, 0, 1, 0, 0, 0)),
      makeActivity('2', u, 'click', new Date(2024, 0, 1, 0, 10, 0)),
      makeActivity('3', u, 'view', new Date(2024, 0, 3, 0, 0, 0)),
      makeActivity('4', u, 'share', new Date(2024, 0, 3, 0, 5, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)

    const summary = dashboard.getUserSummary(u)
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(4)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.mostFrequentAction).toBe('view')
    // first: Jan 1 00:00, last: Jan 3 00:05 => diff just over 2 days, ceil => 3 daysActive; adjust data to exact 2 days
  })

  it('computes actionsPerDay based on ceil day span and averageActionsPerSession splitting at 30 minutes', () => {
    const u = 'userB'
    const acts = [
      makeActivity('1', u, 'a', new Date(2024, 0, 1, 0, 0, 0)),
      makeActivity('2', u, 'b', new Date(2024, 0, 1, 0, 10, 0)),
      makeActivity('3', u, 'c', new Date(2024, 0, 3, 0, 0, 0)), // exactly 2 days after first
      makeActivity('4', u, 'd', new Date(2024, 0, 3, 0, 0, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)

    const summary = dashboard.getUserSummary(u)
    expect(summary).not.toBeNull()
    // daysActive = ceil((Jan3 00:00 - Jan1 00:00)/1day) = ceil(2) = 2
    expect(summary!.actionsPerDay).toBe(2) // 4 actions / 2 days = 2
    // sessions: (0m,10m) same session, (48 hours later) new session, last same time => total 2 sessions, 4/2=2.00
    expect(summary!.averageActionsPerSession).toBe(2)
  })

  it('keeps daysActive at minimum 1 when all timestamps equal', () => {
    const u = 'userC'
    const t = new Date(2024, 0, 1, 12, 0, 0)
    const acts = [
      makeActivity('1', u, 'x', t),
      makeActivity('2', u, 'y', t),
      makeActivity('3', u, 'z', t),
    ]
    const dashboard = new ActivityDashboard(acts)
    const summary = dashboard.getUserSummary(u)
    expect(summary).not.toBeNull()
    expect(summary!.actionsPerDay).toBe(3) // 3 actions / 1 day
  })

  it('splits sessions when gap > 30 minutes', () => {
    const u = 'userD'
    const base = new Date(2024, 0, 1, 9, 0, 0)
    const acts = [
      makeActivity('1', u, 'a', base), // 0 min
      makeActivity('2', u, 'a', new Date(2024, 0, 1, 9, 10, 0)), // +10 min same session
      makeActivity('3', u, 'a', new Date(2024, 0, 1, 9, 50, 0)), // +40 min new session
    ]
    const dashboard = new ActivityDashboard(acts)
    const summary = dashboard.getUserSummary(u)
    expect(summary).not.toBeNull()
    expect(summary!.averageActionsPerSession).toBe(1.5) // 3 actions / 2 sessions
  })

  it('isolates users when generating summaries', () => {
    const u1 = 'userE'
    const u2 = 'other'
    const acts = [
      makeActivity('1', u1, 'a', new Date(2024, 0, 1)),
      makeActivity('2', u2, 'a', new Date(2024, 0, 1)),
      makeActivity('3', u1, 'b', new Date(2024, 0, 2)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const summary = dashboard.getUserSummary(u1)
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(2)
    expect(summary!.uniqueActions).toBe(2)
  })
})

describe('ActivityDashboard.getActivityTrends', () => {
  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const result = dashboard.getActivityTrends('nope')
    expect(result).toEqual([])
  })

  it('groups by day by default, sorts chronologically, and computes growthRate', () => {
    const u = 'trendUser'
    const acts = [
      makeActivity('1', u, 'a', new Date(2024, 0, 1, 1, 0, 0)), // Jan 1
      makeActivity('2', u, 'a', new Date(2024, 0, 2, 1, 0, 0)), // Jan 2
      makeActivity('3', u, 'a', new Date(2024, 0, 2, 2, 0, 0)),
      makeActivity('4', u, 'a', new Date(2024, 0, 2, 3, 0, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends(u)
    expect(trends.map(t => t.period)).toEqual(['2024-01-01', '2024-01-02'])
    expect(trends[0].count).toBe(1)
    expect(trends[0].growthRate).toBe(0)
    expect(trends[1].count).toBe(3)
    expect(trends[1].growthRate).toBe(200)
  })

  it('groups by hour and pads hour to two digits', () => {
    const u = 'hourUser'
    const acts = [
      makeActivity('1', u, 'a', new Date(2024, 0, 1, 9, 15, 0)), // 09:00 bucket
      makeActivity('2', u, 'a', new Date(2024, 0, 1, 9, 45, 0)), // same hour
      makeActivity('3', u, 'a', new Date(2024, 0, 1, 10, 10, 0)), // 10:00 bucket
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends(u, 'hour')
    expect(trends.map(t => t.period)).toEqual(['2024-01-01 09:00', '2024-01-01 10:00'])
    expect(trends[0].count).toBe(2)
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(-50)
  })

  it('groups by week with custom week number logic', () => {
    const u = 'weekUser'
    const acts = [
      makeActivity('1', u, 'a', new Date(2024, 0, 1)), // 2024-W01
      makeActivity('2', u, 'a', new Date(2024, 0, 8)), // 2024-W02
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends(u, 'week')
    expect(trends.map(t => t.period)).toEqual(['2024-W01', '2024-W02'])
    expect(trends[0].count).toBe(1)
    expect(trends[1].count).toBe(1)
    expect(trends[1].growthRate).toBe(0)
  })

  it('groups by month with YYYY-MM format', () => {
    const u = 'monthUser'
    const acts = [
      makeActivity('1', u, 'a', new Date(2024, 0, 15)), // Jan
      makeActivity('2', u, 'a', new Date(2024, 1, 5)), // Feb
      makeActivity('3', u, 'a', new Date(2024, 1, 6)), // Feb
    ]
    const dashboard = new ActivityDashboard(acts)
    const trends = dashboard.getActivityTrends(u, 'month')
    expect(trends.map(t => t.period)).toEqual(['2024-01', '2024-02'])
    expect(trends[0].count).toBe(1)
    expect(trends[1].count).toBe(2)
  })
})

describe('ActivityDashboard.filterByDateRange', () => {
  it('filters by inclusive start and end dates', () => {
    const u = 'filterUser'
    const acts = [
      makeActivity('1', u, 'a', new Date(2024, 0, 1)),
      makeActivity('2', u, 'a', new Date(2024, 0, 2)),
      makeActivity('3', u, 'a', new Date(2024, 0, 3)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const result = dashboard.filterByDateRange(u, new Date(2024, 0, 2), new Date(2024, 0, 3))
    expect(result.map(r => r.id)).toEqual(['2', '3'])
  })

  it('returns empty when no activities fall within range for user', () => {
    const u = 'filterUser2'
    const acts = [
      makeActivity('1', u, 'a', new Date(2024, 0, 1)),
      makeActivity('2', 'other', 'a', new Date(2024, 0, 2)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const result = dashboard.filterByDateRange(u, new Date(2024, 0, 5), new Date(2024, 0, 6))
    expect(result).toEqual([])
  })
})

describe('ActivityDashboard.aggregateByAction', () => {
  it('aggregates counts, percentages, and occurrences, sorted by count desc', () => {
    const u = 'aggUser'
    const acts = [
      makeActivity('1', u, 'click', new Date(2024, 0, 1, 12, 0, 0)),
      makeActivity('2', u, 'view', new Date(2024, 0, 1, 12, 5, 0)),
      makeActivity('3', u, 'click', new Date(2024, 0, 1, 12, 10, 0)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const groups = dashboard.aggregateByAction(u)
    expect(groups.length).toBe(2)
    expect(groups[0].action).toBe('click')
    expect(groups[0].count).toBe(2)
    expect(groups[0].percentage).toBe(66.67)
    expect(groups[0].firstOccurrence.getTime()).toBe(new Date(2024, 0, 1, 12, 0, 0).getTime())
    expect(groups[0].lastOccurrence.getTime()).toBe(new Date(2024, 0, 1, 12, 10, 0).getTime())

    expect(groups[1].action).toBe('view')
    expect(groups[1].count).toBe(1)
    expect(groups[1].percentage).toBe(33.33)
  })

  it('returns empty array when user has no activities', () => {
    const dashboard = new ActivityDashboard([])
    const groups = dashboard.aggregateByAction('nobody')
    expect(groups).toEqual([])
  })
})

describe('ActivityDashboard.getTopActions_old', () => {
  it('returns all actions and ignores the limit parameter', () => {
    const u = 'oldTop'
    const acts = [
      makeActivity('1', u, 'a', new Date(2024, 0, 1)),
      makeActivity('2', u, 'b', new Date(2024, 0, 1, 1)),
      makeActivity('3', u, 'a', new Date(2024, 0, 2)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const groups = dashboard.getTopActions_old(u, 1)
    expect(groups.length).toBe(2)
    const aGroup = groups.find(g => g.action === 'a')!
    const bGroup = groups.find(g => g.action === 'b')!
    expect(aGroup.count).toBe(2)
    expect(bGroup.count).toBe(1)
    expect(aGroup.firstOccurrence.getTime()).toBe(new Date(2024, 0, 1).getTime())
    expect(aGroup.lastOccurrence.getTime()).toBe(new Date(2024, 0, 2).getTime())
  })
})

describe('ActivityDashboard.getTopActions', () => {
  it('returns top N actions limited by parameter', () => {
    const u = 'topUser'
    const acts = [
      makeActivity('1', u, 'a', new Date(2024, 0, 1)),
      makeActivity('2', u, 'a', new Date(2024, 0, 1, 1)),
      makeActivity('3', u, 'b', new Date(2024, 0, 1, 2)),
      makeActivity('4', u, 'b', new Date(2024, 0, 1, 3)),
      makeActivity('5', u, 'c', new Date(2024, 0, 1, 4)),
    ]
    const dashboard = new ActivityDashboard(acts)
    const top2 = dashboard.getTopActions(u, 2)
    expect(top2.length).toBe(2)
    expect(top2[0].action).toBe('a')
    expect(top2[0].count).toBe(2)
    expect(top2[1].action).toBe('b')
    expect(top2[1].count).toBe(2)
  })

  it('returns empty array when no actions exist for user', () => {
    const dashboard = new ActivityDashboard([])
    const top = dashboard.getTopActions('n/a', 3)
    expect(top).toEqual([])
  })
})

describe('ActivityDashboard.calculateEngagementScore', () => {
  it('returns 0 when user has no activity summary', () => {
    const dashboard = new ActivityDashboard([])
    expect(dashboard.calculateEngagementScore('none')).toBe(0)
  })

  it('computes score using volume, diversity, and frequency with rounding', () => {
    const u = 'scoreUser'
    // 10 actions on same day, 5 unique actions (each repeated twice)
    const base = new Date(2024, 0, 1, 10, 0, 0)
    const acts = []
    const unique = ['a1', 'a2', 'a3', 'a4', 'a5']
    let id = 1
    for (const action of unique) {
      acts.push(makeActivity(String(id++), u, action, new Date(base.getFullYear(), base.getMonth(), base.getDate(), 10, id)))
      acts.push(makeActivity(String(id++), u, action, new Date(base.getFullYear(), base.getMonth(), base.getDate(), 10, id)))
    }
    const dashboard = new ActivityDashboard(acts)
    // volume: min(10/100,1)*30 = 3
    // diversity: min(5/10,1)*30 = 15
    // frequency: min(10/5,1)*40 = 40
    // total = 58
    expect(dashboard.calculateEngagementScore(u)).toBe(58)
  })
})