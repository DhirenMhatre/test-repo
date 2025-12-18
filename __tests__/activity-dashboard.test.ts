import { describe, it, expect, jest, afterEach } from '@jest/globals'

jest.mock('date-fns', () => ({
  ...jest.requireActual('date-fns'),
  format: jest.fn(() => '2024-01-01'),
  subMonths: jest.fn(() => new Date('2024-01-01')),
}))

jest.mock('react-use', () => ({
  ...jest.requireActual('react-use'),
  useMedia: jest.fn(),
}))

import { ActivityDashboard } from '@/app/activity-dashboard'

const makeActivity = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>) => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata,
})

describe('ActivityDashboard', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('getUserSummary', () => {
    it('returns null when no activities for user', () => {
      const dash = new ActivityDashboard([])
      const summary = dash.getUserSummary('uX')
      expect(summary).toBeNull()
    })

    it('computes totals, uniques, actionsPerDay, most frequent, and average per session', () => {
      const activities = [
        makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
        makeActivity('3', 'u1', 'click', new Date(2024, 0, 1, 9, 20)),
        makeActivity('4', 'u1', 'view', new Date(2024, 0, 1, 10, 0)),
        makeActivity('5', 'u1', 'view', new Date(2024, 0, 2, 9, 0)),
        makeActivity('6', 'u1', 'logout', new Date(2024, 0, 3, 9, 0)),
      ]
      const dash = new ActivityDashboard(activities)

      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(6)
      expect(summary!.uniqueActions).toBe(4)
      expect(summary!.mostFrequentAction).toBe('view')
      expect(summary!.actionsPerDay).toBeCloseTo(2, 5)
      expect(summary!.averageActionsPerSession).toBeCloseTo(1.5, 5)
    })
  })
})