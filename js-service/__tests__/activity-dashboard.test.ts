import { describe, it, expect, jest, afterEach } from '@jest/globals'
import { ActivityDashboard } from '../src/activity-dashboard'

jest.mock('date-fns', () => {
  const actual = jest.requireActual('date-fns')
  return {
    ...actual,
    // Ensure format is always a function regardless of ESM/CJS interop
    format: jest.fn((date: Date, fmt: string) => {
      try {
        return (actual as any).format ? (actual as any).format(date, fmt) : '2024-01-01'
      } catch {
        return '2024-01-01'
      }
    }),
    // Provide a safe stub for subMonths if needed by implementation
    subMonths: jest.fn((date: Date, n: number) => {
      try {
        return (actual as any).subMonths ? (actual as any).subMonths(date, n) : new Date(date)
      } catch {
        return new Date(date)
      }
    })
  }
})

// Some environments or transitive deps may import react-use; make sure it's safely mocked
jest.mock('react-use', () => ({
  ...jest.requireActual('react-use'),
  useMedia: jest.fn()
}))

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

  it('computes totals, unique actions, most frequent action, and reasonable rates', () => {
    const activities = [
      act('1', 'u1', 'login', dt(2023, 1, 1, 10, 0)),
      act('2', 'u1', 'click', dt(2023, 1, 1, 10, 5)),
      act('3', 'u1', 'click', dt(2023, 1, 1, 10, 20)),
      act('4', 'u1', 'view', dt(2023, 1, 1, 11, 10)),
      act('5', 'u1', 'click', dt(2023, 1, 3, 10, 0))
    ]
    const dash = new ActivityDashboard(activities)
    const summary = dash.getUserSummary('u1')
    expect(summary).not.toBeNull()

    // Deterministic checks
    expect(summary!.totalActions).toBe(5)
    expect(summary!.uniqueActions).toBe(3)
    expect(summary!.mostFrequentAction).toBe('click')

    // Allow implementation-dependent calculations while ensuring sane values
    expect(summary!.actionsPerDay).toBeGreaterThan(0)
    expect(summary!.averageActionsPerSession).toBeGreaterThan(0)
    expect(summary!.averageActionsPerSession).toBeLessThanOrEqual(summary!.totalActions)
  })

  it('handles multiple actions at the exact same moment', () => {
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
    expect(summary!.actionsPerDay).toBeGreaterThan(0)
    expect(summary!.averageActionsPerSession).toBeGreaterThan(0)
  })
})