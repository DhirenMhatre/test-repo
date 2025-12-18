import { describe, it, expect, jest, afterEach } from '@jest/globals'

jest.mock('date-fns', () => ({
  ...jest.requireActual('date-fns'),
  const actual = jest.requireActual('date-fns')
  return {
    ...actual,
    format: jest.fn(() => '2024-01-01'),
    subMonths: jest.fn(() => new Date('2024-01-01')),
  }
})

import { ActivityDashboard } from '@/app/activity-dashboard'

type Act = ConstructorParameters<typeof ActivityDashboard>[0][number]

const makeActivity = (id: string, user_id: string, action: string, date: Date, metadata?: Record<string, any>): Act => ({
  id,
  user_id,
  action,
  timestamp: date,
  metadata
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
      const activities: Act[] = [
        makeActivity('1', 'u1', 'login', new Date(2024, 0, 1, 9, 0)),
        makeActivity('2', 'u1', 'view', new Date(2024, 0, 1, 9, 10)),
        makeActivity('3', 'u1', 'click', new Date(2024, 0, 1, 9, 20)),
        makeActivity('4', 'u1', 'view', new Date(2024, 0, 1, 10, 0)), // 40 min gap -> new session
        makeActivity('5', 'u1', 'view', new Date(2024, 0, 2, 9, 0)), // next day -> new session
        makeActivity('6', 'u1', 'logout', new Date(2024, 0, 3, 9, 0)) // next day -> new session
      ]
      const dash = new ActivityDashboard(activities)

      const summary = dash.getUserSummary('u1')
      expect(summary).not.toBeNull()
      expect(summary!.totalActions).toBe(6)
      expect(summary!.uniqueActions).toBe(4)
      expect(summary!.mostFrequentAction).toBe('view')
      // actions on 3 distinct days -> 6 / 3 = 2 per day
      expect(summary!.actionsPerDay).toBeCloseTo(2, 5)
      // sessions: [9:00,9:10,9:20], [10:00], [next day 9:00], [next day 9:00] => 4 sessions
      expect(summary!.averageActionsPerSession).toBeCloseTo(1.5, 5)
    })
  })
})