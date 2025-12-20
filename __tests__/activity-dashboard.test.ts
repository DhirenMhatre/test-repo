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

import { ActivityDashboard } from '@/app/activity-dashboard'

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

    it('computes totals, uniques, actionsPerDay, and most frequent action', () => {
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
        makeActivity('1', 'u1', 'view', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u2', 'view', new Date(2024, 0, 1, 9, 10)),
        makeActivity('3', 'u1', 'click', new Date(2024, 0, 2, 9, 0)),
        makeActivity('4', 'u2', 'login', new Date(2024, 0, 3, 9, 0)),
      ]
      const dash = new ActivityDashboard(activities)

      const s1 = dash.getUserSummary('u1')
      const s2 = dash.getUserSummary('u2')
      expect(s1).toBeTruthy()
      expect(s2).toBeTruthy()

      const u1Acts = activities.filter(a => a.userId === 'u1' || a.user_id === 'u1')
      const u2Acts = activities.filter(a => a.userId === 'u2' || a.user_id === 'u2')

      const u1Total = u1Acts.length
      const u2Total = u2Acts.length
      const u1Unique = new Set(u1Acts.map(a => a.action)).size
      const u2Unique = new Set(u2Acts.map(a => a.action)).size

      const u1FreqMap = u1Acts.reduce<Record<string, number>>((acc, a) => {
        acc[a.action] = (acc[a.action] || 0) + 1
        return acc
      }, {})
      const u2FreqMap = u2Acts.reduce<Record<string, number>>((acc, a) => {
        acc[a.action] = (acc[a.action] || 0) + 1
        return acc
      }, {})

      const u1Most = Object.entries(u1FreqMap).sort((a, b) => b[1] - a[1])[0]?.[0]
      const u2Most = Object.entries(u2FreqMap).sort((a, b) => b[1] - a[1])[0]?.[0]

      expect(s1!.totalActions).toBe(u1Total)
      expect(s2!.totalActions).toBe(u2Total)
      expect(s1!.uniqueActions).toBe(u1Unique)
      expect(s2!.uniqueActions).toBe(u2Unique)
      expect(s1!.mostFrequentAction).toBe(u1Most)
      expect(s2!.mostFrequentAction).toBe(u2Most)
      expect(Number.isFinite(s1!.actionsPerDay)).toBe(true)
      expect(Number.isFinite(s2!.actionsPerDay)).toBe(true)
    })

    it('handles mixed field aliases and still returns a valid summary', () => {
      const activities = [
        // mixed aliases are already included by makeActivity
        makeActivity('1', 'u3', 'download', new Date(2024, 0, 5, 12, 0), { size: 10 }),
        makeActivity('2', 'u3', 'download', new Date(2024, 0, 6, 12, 0), { size: 20 }),
        makeActivity('3', 'u3', 'share', new Date(2024, 0, 7, 12, 0), { target: 'x' }),
      ]
      const dash = new ActivityDashboard(activities)
      const summary = dash.getUserSummary('u3')
      expect(summary).toBeTruthy()
      expect(summary!.totalActions).toBe(3)
      expect(summary!.uniqueActions).toBe(2)
      expect(typeof summary!.mostFrequentAction).toBe('string')
      expect(Number.isFinite(summary!.actionsPerDay)).toBe(true)
    })
  })
})