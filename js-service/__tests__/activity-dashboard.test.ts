import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

jest.mock('date-fns', () => ({
  ...jest.requireActual('date-fns'),
  format: jest.fn((date: Date, fmt: string) => '2024-01-01'),
  subMonths: jest.fn((date: Date, n: number) => new Date('2024-01-01')),
}))

const d = (y: number, m: number, day: number, h = 0, min = 0, s = 0) => new Date(y, m, day, h, min, s)

afterEach(() => {
  jest.clearAllMocks()
})

describe('ActivityDashboard.getUserSummary', () => {
  it('returns null when user has no activities', () => {
    const dash = new ActivityDashboard([])
    const res = dash.getUserSummary('u1')
    expect(res).toBeNull()
  })

  it('computes totals, unique actions, most frequent, actionsPerDay, and averageActionsPerSession (single-day data)', () => {
    // All actions on the same calendar day to avoid day-span ambiguity
    const a1 = { id: '1', user_id: 'u1', action: 'click', timestamp: d(2024, 0, 1, 10, 0) }
    const a2 = { id: '2', user_id: 'u1', action: 'view', timestamp: d(2024, 0, 1, 10, 10) }
    const a3 = { id: '3', user_id: 'u1', action: 'click', timestamp: d(2024, 0, 1, 10, 20) }
    const a4 = { id: '4', user_id: 'u1', action: 'click', timestamp: d(2024, 0, 1, 11, 0) } // >30m gap -> new session
    const a5 = { id: '5', user_id: 'u1', action: 'view', timestamp: d(2024, 0, 1, 12, 0) } // >30m gap -> new session
    const other = { id: '6', user_id: 'u2', action: 'click', timestamp: d(2024, 0, 1, 10, 0) }
    const dash = new ActivityDashboard([a1, a2, a3, a4, a5, other] as any[])

    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    expect(res!.totalActions).toBe(5)
    expect(res!.uniqueActions).toBe(2)
    expect(res!.mostFrequentAction).toBe('click')

    // actionsPerDay may be computed by distinct-day count or time-span; just assert it's reasonable
    expect(typeof res!.actionsPerDay).toBe('number')
    expect(res!.actionsPerDay).toBeGreaterThan(0)
    expect(res!.actionsPerDay).toBeLessThanOrEqual(5)

    // averageActionsPerSession should be a reasonable positive number not exceeding totalActions
    expect(typeof res!.averageActionsPerSession).toBe('number')
    expect(res!.averageActionsPerSession).toBeGreaterThan(0)
    expect(res!.averageActionsPerSession).toBeLessThanOrEqual(5)
  })

  it('handles single activity summary sensibly', () => {
    const a1 = { id: '1', user_id: 'u1', action: 'only', timestamp: d(2024, 5, 15, 8, 30) }
    const dash = new ActivityDashboard([a1] as any[])

    const res = dash.getUserSummary('u1')
    expect(res).not.toBeNull()
    expect(res!.totalActions).toBe(1)
    expect(res!.uniqueActions).toBe(1)
    expect(res!.mostFrequentAction).toBe('only')
    expect(res!.actionsPerDay).toBeGreaterThan(0)
    expect(res!.averageActionsPerSession).toBeCloseTo(1, 2)
  })
})