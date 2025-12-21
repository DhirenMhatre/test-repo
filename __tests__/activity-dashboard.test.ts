import { describe, it, expect, jest, afterEach } from '@jest/globals'

jest.mock('date-fns', () => {
  const actual = jest.requireActual('date-fns')
  return {
    ...actual,
    // Ensure these are functions to prevent "format is not a function" errors
    format: jest.fn((date: Date, fmt: string) => '2024-01-01'),
    subMonths: jest.fn((date: Date, n: number) => new Date('2024-01-01')),
  }
})

jest.mock('react-use', () => {
  const actual = jest.requireActual('react-use')
  return {
    ...actual,
    // Only override what we need; keep rest via requireActual
    useMedia: jest.fn(() => false),
  }
})

import * as ActivityModule from '@/app/activity-dashboard'

// Prefer named export, fall back to default
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const ActivityDashboardExport: any =
  (ActivityModule as any).ActivityDashboard ?? (ActivityModule as any).default

// Be resilient whether it's a class (new-able) or factory function
const makeDashboard = (activities: any[]) => {
  if (typeof ActivityDashboardExport === 'function') {
    try {
      // Try class-style constructor
      return new ActivityDashboardExport(activities)
    } catch {
      // Fallback to factory/function
      return ActivityDashboardExport(activities)
    }
  }
  // If module exports an object with a builder
  if (ActivityDashboardExport && typeof ActivityDashboardExport.create === 'function') {
    return ActivityDashboardExport.create(activities)
  }
  throw new Error('ActivityDashboard export is not constructible')
}

const makeActivity = (
  id: string,
  userId: string,
  action: string,
  date: Date,
  metadata?: Record<string, any>
) => ({
  id,
  userId,
  user_id: userId,
  action,
  timestamp: date,
  date,
  metadata,
  meta: metadata,
})

describe('ActivityDashboard', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('getUserSummary', () => {
    it('returns null/undefined when no activities for user', () => {
      const dash = makeDashboard([])
      // Ensure method exists before calling
      expect(typeof (dash as any).getUserSummary).toBe('function')
      const summary = (dash as any).getUserSummary('uX')
      expect(summary == null).toBe(true)
    })

    it('computes totals, uniques, actionsPerDay (finite), and most frequent action', () => {
      const activities = [
        makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
        makeActivity('3', 'u1', 'click', new Date(2024, 0, 1, 9, 20)),
        makeActivity('4', 'u1', 'view', new Date(2024, 0, 1, 10, 0)),
        makeActivity('5', 'u1', 'view', new Date(2024, 0, 2, 9, 0)),
        makeActivity('6', 'u1', 'logout', new Date(2024, 0, 3, 9, 0)),
      ]
      const dash = makeDashboard(activities)

      const userActs = activities.filter(a => a.userId === 'u1' || a.user_id === 'u1')
      const totalExpected = userActs.length
      const uniqueExpected = new Set(userActs.map(a => a.action)).size
      const freqMap = userActs.reduce<Record<string, number>>((acc, a) => {
        acc[a.action] = (acc[a.action] || 0) + 1
        return acc
      }, {})
      const mostFreqExpected = Object.entries(freqMap).sort((a, b) => b[1] - a[1])[0]?.[0]

      const summary = (dash as any).getUserSummary('u1')
      expect(summary).toBeTruthy()
      expect(typeof summary.totalActions).toBe('number')
      expect(summary.totalActions).toBe(totalExpected)
      expect(summary.uniqueActions).toBe(uniqueExpected)
      expect(summary.mostFrequentAction).toBe(mostFreqExpected)
      expect(typeof summary.actionsPerDay).toBe('number')
      expect(Number.isFinite(summary.actionsPerDay)).toBe(true)
      expect(summary.actionsPerDay).toBeGreaterThan(0)
    })

    it('isolates summaries per user (ignores other user activities)', () => {
      const activities = [
        makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u2', 'view', new Date(2024, 0, 1, 9, 10)),
        makeActivity('3', 'u1', 'click', new Date(2024, 0, 1, 9, 20)),
        makeActivity('4', 'u2', 'like', new Date(2024, 0, 1, 10, 0)),
        makeActivity('5', 'u1', 'view', new Date(2024, 0, 2, 9, 0)),
        makeActivity('6', 'u3', 'logout', new Date(2024, 0, 3, 9, 0)),
      ]
      const dash = makeDashboard(activities)

      const u1Acts = activities.filter(a => a.userId === 'u1' || a.user_id === 'u1')
      const summaryU1 = (dash as any).getUserSummary('u1')
      expect(summaryU1).toBeTruthy()
      expect(summaryU1.totalActions).toBe(u1Acts.length)
      const uniqueU1 = new Set(u1Acts.map(a => a.action)).size
      expect(summaryU1.uniqueActions).toBe(uniqueU1)

      const u2Acts = activities.filter(a => a.userId === 'u2' || a.user_id === 'u2')
      const summaryU2 = (dash as any).getUserSummary('u2')
      expect(summaryU2).toBeTruthy()
      expect(summaryU2.totalActions).toBe(u2Acts.length)
      const uniqueU2 = new Set(u2Acts.map(a => a.action)).size
      expect(summaryU2.uniqueActions).toBe(uniqueU2)
    })

    it('handles varied activity shapes (timestamp vs date, metadata vs meta)', () => {
      const activities = [
        // Only timestamp
        {
          id: '1',
          userId: 'u1',
          action: 'view',
          timestamp: new Date(2024, 0, 1, 8, 0),
          metadata: { page: 'home' },
        },
        // Only date
        {
          id: '2',
          user_id: 'u1',
          action: 'view',
          date: new Date(2024, 0, 2, 8, 0),
          meta: { page: 'profile' },
        },
        // Both
        makeActivity('3', 'u1', 'like', new Date(2024, 0, 2, 9, 0), { item: 'post' }),
      ] as any[]
      const dash = makeDashboard(activities)
      const summary = (dash as any).getUserSummary('u1')
      expect(summary).toBeTruthy()
      expect(summary.totalActions).toBe(3)
      expect(Number.isFinite(summary.actionsPerDay)).toBe(true)
      expect(summary.actionsPerDay).toBeGreaterThan(0)
      // Most frequent should be 'view' in this set
      expect(summary.mostFrequentAction).toBe('view')
    })
  })
})