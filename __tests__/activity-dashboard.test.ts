import { describe, it, expect, jest, afterEach } from '@jest/globals'

jest.mock('date-fns', () => ({
  ...jest.requireActual('date-fns'),
  format: jest.fn(() => '2024-01-01'),
  subMonths: jest.fn(() => new Date('2024-01-01')),
}))

jest.mock('react-use', () => ({
  ...jest.requireActual('react-use'),
  useMedia: jest.fn(() => false),
}))

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

      const u1Acts = activities.filter(a => (a.userId === 'u1' || a.user_id === 'u1'))
      const u2Acts = activities.filter(a => (a.userId === 'u2' || a.user_id === 'u2'))

      expect(s1).toBeTruthy()
      expect(s2).toBeTruthy()
      expect(s1!.totalActions).toBe(u1Acts.length)
      expect(s2!.totalActions).toBe(u2Acts.length)

      expect(s1!.uniqueActions).toBe(new Set(u1Acts.map(a => a.action)).size)
      expect(s2!.uniqueActions).toBe(new Set(u2Acts.map(a => a.action)).size)
    })
  })
})