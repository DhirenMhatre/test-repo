import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

jest.mock('date-fns', () => {
  const actual = jest.requireActual('date-fns')
  return {
    ...actual,
    format: jest.fn((date: Date, fmt: string) => (actual as any).format(date, fmt))
  }
})

const dt = (y: number, m: number, d: number, h = 0, min = 0) => new Date(y, m - 1, d, h, min, 0, 0)
const act = (id: string, user: string, action: string, date: Date) => ({
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
    const dash = new ActivityDashboard([
      act('1', 'u2', 'login', dt(2023, 1, 1, 10))
    ])
    const summary = dash.getUserSummary('u1')
    expect(summary).toBeNull()
  })

  it('computes totals, unique actions, actions per day, most frequent, and average per session', () => {
    const activities = [
      act('1', 'u1', 'login', dt(2023, 1, 1, 10, 0)),
      act('2', 'u1', 'click', dt(2023, 1, 1, 10, 5)),
      act('3', 'u1', 'click', dt(2023, 1, 1, 10, 20)),
      act('4', 'u1', 'view', dt(2023, 1, 1, 11, 10)), // >30 min gap -> new session
      act('5', 'u1', 'click', dt(2023, 1, 3, 10, 0)) // >1 day -> new session
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(5)
    expect(summary!.uniqueActions).toBe(3)
    // First is Jan 1 10:00, last is Jan 3 10:00 => exactly 2 days -> ceil(2) = 2
    expect(summary!.actionsPerDay).toBeCloseTo(2.5, 2)
    expect(summary!.mostFrequentAction).toBe('click')
    // Sessions: [10:00,10:05,10:20] [11:10] [Jan3 10:00] => 3 sessions -> 5/3 = 1.67
    expect(summary!.averageActionsPerSession).toBeCloseTo(1.67, 2)
  })

  it('uses minimum daysActive of 1 when activities are within the same moment', () => {
    const activities = [
      act('1', 'u1', 'a', dt(2023, 2, 1, 9)),
      act('2', 'u1', 'b', dt(2023, 2, 1, 9)),
      act('3', 'u1', 'c', dt(2023, 2, 1, 9))
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()
    expect(summary!.totalActions).toBe(3)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.actionsPerDay).toBeCloseTo(3, 2)
    expect(summary!.averageActionsPerSession).toBeCloseTo(3, 2) // all within same session
  })
})

describe('ActivityDashboard - getActivityTrends (day)', () => {
  it('groups by day and sorts periods ascending', () => {
    const y = 2023
    const activities = [
      act('1', 'u1', 'a', dt(y, 1, 1, 10)),
      act('2', 'u1', 'b', dt(y, 1, 1, 11)),
      act('3', 'u1', 'c', dt(y, 1, 2, 10)),
      act('4', 'u1', 'd', dt(y, 1, 4, 9)),
      act('5', 'u1', 'e', dt(y, 1, 4, 10)),
      act('6', 'u1', 'f', dt(y, 1, 4, 11)),
      act('7', 'u2', 'x', dt(y, 1, 1, 9)) // other user should be ignored
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'day')
    expect(trends.map((t: any) => t.period)).toEqual([
      `${y}-01-01`,
      `${y}-01-02`,
      `${y}-01-04`
    ])
    expect(trends.map((t: any) => t.count)).toEqual([2, 1, 3])
  })

  it('returns empty array when user has no activities', () => {
    const dash = new ActivityDashboard([
      act('1', 'u2', 'a', dt(2023, 5, 1))
    ])
    const trends = dash.getActivityTrends('u1', 'day')
    expect(Array.isArray(trends)).toBe(true)
    expect(trends.length).toBe(0)
  })
})

describe('ActivityDashboard - getActivityTrends (month)', () => {
  it('groups by month and sorts periods ascending', () => {
    const y = 2023
    const activities = [
      act('1', 'u1', 'a', dt(y, 1, 1, 10)),
      act('2', 'u1', 'b', dt(y, 1, 10, 11)),
      act('3', 'u1', 'c', dt(y, 3, 2, 10)),
      act('4', 'u1', 'd', dt(y, 3, 4, 9)),
      act('5', 'u2', 'e', dt(y, 2, 10, 12)) // other user ignored
    ]
    const dash = new ActivityDashboard(activities)
    const trends = dash.getActivityTrends('u1', 'month')
    expect(trends.map((t: any) => t.period)).toEqual([
      `${y}-01`,
      `${y}-03`
    ])
    expect(trends.map((t: any) => t.count)).toEqual([2, 2])
  })
})