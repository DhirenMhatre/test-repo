import { describe, it, expect, jest, afterEach } from '@jest/globals'

jest.mock('date-fns', () => {
  const actual = jest.requireActual('date-fns')
  return {
    ...actual,
    format: jest.fn(() => '2024-01-01'),
    subMonths: jest.fn(() => new Date('2024-01-01')),
  }
})

jest.mock('react-use', () => {
  const actual = jest.requireActual('react-use')
  return {
    ...actual,
    useMedia: jest.fn(() => false),
  }
})

import * as ActivityModule from '@/app/activity-dashboard'
const ActivityDashboard =
  // Prefer named export, fall back to default
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  ((ActivityModule as any).ActivityDashboard ?? (ActivityModule as any).default)

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
      const dash = new ActivityDashboard([])
      const summary = dash.getUserSummary('uX')
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
      const dash = new ActivityDashboard(activities)

      const userActs = activities.filter(a => a.userId === 'u1' || a.user_id === 'u1')
      const totalExpected = userActs.length
      const uniqueExpected = new Set(userActs.map(a => a.action)).size
      const freqMap = userActs.reduce<Record<string, number>>((acc, a) => {
        acc[a.action] = (acc[a.action] || 0) + 1
        return acc
      }, {})
      const mostFreqExpected = Object.entries(freqMap).sort((a, b) => b[1] - a[1])[0]?.[0]

      const summary = dash.getUserSummary('u1')
      expect(summary).toBeTruthy()
      expect(typeof summary!.totalActions).toBe('number')
      expect(summary!.totalActions).toBe(totalExpected)
      expect(summary!.uniqueActions).toBe(uniqueExpected)
      expect(summary!.mostFrequentAction).toBe(mostFreqExpected)
      expect(typeof summary!.actionsPerDay).toBe('number')
      expect(Number.isFinite(summary!.actionsPerDay)).toBe(true)
      expect(summary!.actionsPerDay).toBeGreaterThan(0)
    })

    it('isolates summaries per user (ignores other user activities)', () => {
      const activities = [
        makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u2', 'view', new Date(2024, 0, 1, 9, 10)),
        makeActivity('3', 'u1', 'view', new Date(2024, 0, 1, 10, 0)),
        makeActivity('4', 'u2', 'click', new Date(2024, 0, 2, 8, 0)),
        makeActivity('5', 'u1', 'logout', new Date(2024, 0, 3, 9, 0)),
        makeActivity('6', 'u2', 'view', new Date(2024, 0, 3, 10, 0)),
      ]
      const dash = new ActivityDashboard(activities)

      const u1Acts = activities.filter(a => a.userId === 'u1' || a.user_id === 'u1')
      const u2Acts = activities.filter(a => a.userId === 'u2' || a.user_id === 'u2')

      const u1Summary = dash.getUserSummary('u1')
      const u2Summary = dash.getUserSummary('u2')

      expect(u1Summary).toBeTruthy()
      expect(u2Summary).toBeTruthy()

      expect(u1Summary!.totalActions).toBe(u1Acts.length)
      expect(u2Summary!.totalActions).toBe(u2Acts.length)

      const u1Unique = new Set(u1Acts.map(a => a.action)).size
      const u2Unique = new Set(u2Acts.map(a => a.action)).size
      expect(u1Summary!.uniqueActions).toBe(u1Unique)
      expect(u2Summary!.uniqueActions).toBe(u2Unique)

      const freq = (acts: typeof activities) =>
        Object.entries(
          acts.reduce<Record<string, number>>((acc, a) => {
            acc[a.action] = (acc[a.action] || 0) + 1
            return acc
          }, {})
        ).sort((a, b) => b[1] - a[1])[0]?.[0]

      expect(u1Summary!.mostFrequentAction).toBe(freq(u1Acts))
      expect(u2Summary!.mostFrequentAction).toBe(freq(u2Acts))
    })
  })
})