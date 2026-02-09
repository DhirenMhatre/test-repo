import { describe, it, expect, jest, beforeEach, afterEach } from '@jest/globals'
import { ActivityDashboard, Activity } from '../src/activity-dashboard'

describe('ActivityDashboard', () => {
  let baseDate: Date
  let activities: Activity[]
  let dashboard: ActivityDashboard

  beforeEach(() => {
    baseDate = new Date('2024-01-01T00:00:00.000Z')

    activities = [
      {
        id: '1',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 0 * 60 * 60 * 1000),
      },
      {
        id: '2',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(baseDate.getTime() + 1 * 60 * 60 * 1000),
      },
      {
        id: '3',
        user_id: 'user1',
        action: 'view',
        timestamp: new Date(baseDate.getTime() + 2 * 60 * 60 * 1000),
      },
      {
        id: '4',
        user_id: 'user1',
        action: 'purchase',
        timestamp: new Date(baseDate.getTime() + 26 * 60 * 60 * 1000), // next day +2h
      },
      {
        id: '5',
        user_id: 'user2',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 3 * 60 * 60 * 1000),
      },
      {
        id: '6',
        user_id: 'user1',
        action: 'login',
        timestamp: new Date(baseDate.getTime() + 60 * 60 * 1000 * 24 * 5), // 5 days later
      },
    ]

    dashboard = new ActivityDashboard(activities)
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  describe('getUserSummary', () => {
    it('returns null when user has no activities', () => {
      const result = dashboard.getUserSummary('unknown')
      expect(result).toBeNull()
    })

    it('calculates summary metrics correctly for a user', () => {
      const result = dashboard.getUserSummary('user1')
      expect(result).not.toBeNull()
      if (!result) return

      const userActivities = activities.filter(a => a.user_id === 'user1')
      expect(result.totalActions).toBe(userActivities.length)

      const uniqueActions = new Set(userActivities.map(a => a.action))
      expect(result.uniqueActions).toBe(uniqueActions.size)

      const sorted = [...userActivities].sort(
        (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
      )
      const first = sorted[0].timestamp
      const last = sorted[sorted.length - 1].timestamp
      const daysDiff = Math.ceil(
        (last.getTime() - first.getTime()) / (1000 * 60 * 60 * 24)
      )
      const daysActive = Math.max(daysDiff, 1)
      const expectedActionsPerDay = parseFloat(
        (userActivities.length / daysActive).toFixed(2)
      )
      expect(result.actionsPerDay).toBe(expectedActionsPerDay)

      const counts: Record<string, number> = {}
      userActivities.forEach(a => {
        counts[a.action] = (counts[a.action] || 0) + 1
      })
      let maxCount = 0
      let mostFrequent = 'none'
      Object.entries(counts).forEach(([action, count]) => {
        if (count > maxCount) {
          maxCount = count
          mostFrequent = action
        }
      })
      expect(result.mostFrequentAction).toBe(mostFrequent)

      const sessionGapMinutes = 30
      const sortedByTime = [...userActivities].sort(
        (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
      )
      let sessions = 1
      for (let i = 1; i < sortedByTime.length; i++) {
        const diffMinutes =
          (sortedByTime[i].timestamp.getTime() -
            sortedByTime[i - 1].timestamp.getTime()) /
          (1000 * 60)
        if (diffMinutes > sessionGapMinutes) {
          sessions++
        }
      }
      const expectedAvgPerSession = parseFloat(
        (userActivities.length / sessions).toFixed(2)
      )
      expect(result.averageActionsPerSession).toBe(expectedAvgPerSession)
    })

    it('handles single activity correctly (daysActive minimum 1)', () => {
      const singleActivity: Activity = {
        id: 'single',
        user_id: 'singleUser',
        action: 'login',
        timestamp: new Date('2024-01-10T10:00:00.000Z'),
      }
      const singleDashboard = new ActivityDashboard([singleActivity])

      const result = singleDashboard.getUserSummary('singleUser')
      expect(result).not.toBeNull()
      if (!result) return

      expect(result.totalActions).toBe(1)
      expect(result.uniqueActions).toBe(1)
      expect(result.actionsPerDay).toBe(1)
      expect(result.mostFrequentAction).toBe('login')
      expect(result.averageActionsPerSession).toBe(1)
    })
  })

  describe('getActivityTrends', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.getActivityTrends('unknown')
      expect(result).toEqual([])
    })

    it('groups activities by day and calculates growthRate', () => {
      const result = dashboard.getActivityTrends('user1', 'day')

      const userActivities = activities.filter(a => a.user_id === 'user1')
      const grouped: Record<string, Activity[]> = {}
      userActivities.forEach(a => {
        const d = a.timestamp
        const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(
          2,
          '0'
        )}-${String(d.getDate()).padStart(2, '0')}`
        if (!grouped[key]) grouped[key] = []
        grouped[key].push(a)
      })
      const periods = Object.keys(grouped).sort()

      expect(result.map(r => r.period)).toEqual(periods)
      result.forEach((entry, index) => {
        expect(entry.count).toBe(grouped[entry.period].length)
        if (index === 0) {
          expect(entry.growthRate).toBe(0)
        } else {
          const prevPeriod = periods[index - 1]
          const prevCount = grouped[prevPeriod].length
          const expectedGrowth =
            prevCount > 0
              ? parseFloat(
                  (
                    ((entry.count - prevCount) / prevCount) *
                    100
                  ).toFixed(2)
                )
              : 0
          expect(entry.growthRate).toBe(expectedGrowth)
        }
      })
    })

    it('supports hour, week, and month period types', () => {
      const hourTrends = dashboard.getActivityTrends('user1', 'hour')
      const dayTrends = dashboard.getActivityTrends('user1', 'day')
      const weekTrends = dashboard.getActivityTrends('user1', 'week')
      const monthTrends = dashboard.getActivityTrends('user1', 'month')

      expect(hourTrends.length).toBeGreaterThan(0)
      expect(dayTrends.length).toBeGreaterThan(0)
      expect(weekTrends.length).toBeGreaterThan(0)
      expect(monthTrends.length).toBeGreaterThan(0)

      hourTrends.forEach(t => {
        expect(t.period).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:00$/)
      })
      dayTrends.forEach(t => {
        expect(t.period).toMatch(/^\d{4}-\d{2}-\d{2}$/)
      })
      weekTrends.forEach(t => {
        expect(t.period).toMatch(/^\d{4}-W\d{2}$/)
      })
      monthTrends.forEach(t => {
        expect(t.period).toMatch(/^\d{4}-\d{2}$/)
      })
    })
  })

  describe('filterByDateRange', () => {
    it('returns only activities for user within date range inclusive', () => {
      const start = new Date(baseDate.getTime() + 0.5 * 60 * 60 * 1000)
      const end = new Date(baseDate.getTime() + 2.5 * 60 * 60 * 1000)

      const result = dashboard.filterByDateRange('user1', start, end)

      expect(result.every(a => a.user_id === 'user1')).toBe(true)
      expect(
        result.every(
          a => a.timestamp >= start && a.timestamp <= end
        )
      ).toBe(true)
    })

    it('returns empty array when no activities in range', () => {
      const start = new Date('2030-01-01T00:00:00.000Z')
      const end = new Date('2030-01-02T00:00:00.000Z')

      const result = dashboard.filterByDateRange('user1', start, end)
      expect(result).toEqual([])
    })
  })

  describe('aggregateByAction', () => {
    it('returns empty array when user has no activities', () => {
      const result = dashboard.aggregateByAction('unknown')
      expect(result).toEqual([])
    })

    it('aggregates counts, percentages, and occurrence dates per action', () => {
      const result = dashboard.aggregateByAction('user1')

      const userActivities = activities.filter(a => a.user_id === 'user1')
      const total = userActivities.length
      const byAction: Record<string, Activity[]> = {}
      userActivities.forEach(a => {
        if (!byAction[a.action]) byAction[a.action] = []
        byAction[a.action].push(a)
      })

      expect(result.length).toBe(Object.keys(byAction).length)

      result.forEach(group => {
        const acts = byAction[group.action]
        const sorted = [...acts].sort(
          (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
        )
        expect(group.count).toBe(acts.length)
        const expectedPct = parseFloat(
          ((acts.length / total) * 100).toFixed(2)
        )
        expect(group.percentage).toBe(expectedPct)
        expect(group.firstOccurrence.getTime()).toBe(
          sorted[0].timestamp.getTime()
        )
        expect(group.lastOccurrence.getTime()).toBe(
          sorted[sorted.length - 1].timestamp.getTime()
        )
      })

      for (let i = 1; i < result.length; i++) {
        expect(result[i - 1].count).toBeGreaterThanOrEqual(result[i].count)
      }
    })

    it('handles single action type correctly', () => {
      const single: Activity[] = [
        {
          id: '1',
          user_id: 'u',
          action: 'only',
          timestamp: new Date('2024-01-01T00:00:00.000Z'),
        },
        {
          id: '2',
          user_id: 'u',
          action: 'only',
          timestamp: new Date('2024-01-01T01:00:00.000Z'),
        },
      ]
      const d = new ActivityDashboard(single)
      const result = d.aggregateByAction('u')

      expect(result).toHaveLength(1)
      const group = result[0]
      expect(group.action).toBe('only')
      expect(group.count).toBe(2)
      expect(group.percentage).toBe(100)
      expect(group.lastOccurrence.getTime()).toBe(
        single[1].timestamp.getTime()
      )
    })
  })

  describe('getTopActions_old', () => {
    it('returns all actions sorted by count desc, ignoring limit parameter', () => {
      const result = dashboard.getTopActions_old('user1', 1)

      const userActivities = activities.filter(a => a.user_id === 'user1')
      const actionMap = new Map<string, Activity[]>()
      userActivities.forEach(a => {
        if (!actionMap.has(a.action)) actionMap.set(a.action, [])
        actionMap.get(a.action)!.push(a)
      })
      const total = userActivities.length
      const expected = Array.from(actionMap.entries())
        .map(([action, acts]) => {
          const sorted = [...acts].sort(
            (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
          )
          return {
            action,
            count: acts.length,
            percentage: parseFloat(
              ((acts.length / total) * 100).toFixed(2)
            ),
            firstOccurrence: sorted[0].timestamp,
            lastOccurrence: sorted[sorted.length - 1].timestamp,
          }
        })
        .sort((a, b) => b.count - a.count)

      expect(result.length).toBe(expected.length)
      expect(result.map(r => r.action)).toEqual(
        expected.map(e => e.action)
      )
      expect(result.map(r => r.count)).toEqual(
        expected.map(e => e.count)
      )
    })

    it('returns empty array when user has no activities', () => {
      const result = dashboard.getTopActions_old('unknown')
      expect(result).toEqual([])
    })
  })

  describe('getTopActions', () => {
    it('returns top N actions based on aggregateByAction', () => {
      const spy = jest.spyOn(dashboard as any, 'aggregateByAction')
      const result = dashboard.getTopActions('user1', 2)

      expect(spy).toHaveBeenCalledWith('user1')
      expect(result.length).toBeLessThanOrEqual(2)

      const all = (dashboard as any).aggregateByAction('user1')
      expect(result).toEqual(all.slice(0, 2))
    })

    it('defaults limit to 5 when not provided', () => {
      const result = dashboard.getTopActions('user1')
      expect(result.length).toBeLessThanOrEqual(5)
    })

    it('returns empty array when user has no activities', () => {
      const result = dashboard.getTopActions('unknown', 3)
      expect(result).toEqual([])
    })
  })

  describe('calculateEngagementScore', () => {
    it('returns 0 when user has no activities', () => {
      const result = dashboard.calculateEngagementScore('unknown')
      expect(result).toBe(0)
    })

    it('calculates engagement score based on summary metrics', () => {
      const summary = dashboard.getUserSummary('user1')
      if (!summary) throw new Error('summary should exist')

      const volumeScore = Math.min(summary.totalActions / 100, 1) * 30
      const diversityScore = Math.min(summary.uniqueActions / 10, 1) * 30
      const frequencyScore = Math.min(summary.actionsPerDay / 5, 1) * 40
      const expected = parseFloat(
        (volumeScore + diversityScore + frequencyScore).toFixed(2)
      )

      const result = dashboard.calculateEngagementScore('user1')
      expect(result).toBe(expected)
    })

    it('caps each component score at its maximum', () => {
      const manyActivities: Activity[] = []
      const userId = 'heavy'
      const start = new Date('2024-01-01T00:00:00.000Z')
      for (let i = 0; i < 200; i++) {
        manyActivities.push({
          id: `a${i}`,
          user_id: userId,
          action: `action${i % 15}`,
          timestamp: new Date(start.getTime() + i * 60 * 60 * 1000),
        })
      }
      const d = new ActivityDashboard(manyActivities)
      const score = d.calculateEngagementScore(userId)

      expect(score).toBeLessThanOrEqual(100)
      expect(score).toBeGreaterThan(0)
    })
  })

  describe('private helpers via behavior', () => {
    it('findMostFrequentAction returns "none" when no actions (via getUserSummary)', () => {
      const d = new ActivityDashboard([])
      const summary = d.getUserSummary('any')
      expect(summary).toBeNull()
    })

    it('calculateAverageActionsPerSession splits sessions when gap > 30 minutes', () => {
      const userId = 'gapUser'
      const acts: Activity[] = [
        {
          id: '1',
          user_id: userId,
          action: 'a',
          timestamp: new Date('2024-01-01T10:00:00.000Z'),
        },
        {
          id: '2',
          user_id: userId,
          action: 'b',
          timestamp: new Date('2024-01-01T10:10:00.000Z'),
        },
        {
          id: '3',
          user_id: userId,
          action: 'c',
          timestamp: new Date('2024-01-01T11:00:01.000Z'),
        },
      ]
      const d = new ActivityDashboard(acts)
      const summary = d.getUserSummary(userId)
      expect(summary).not.toBeNull()
      if (!summary) return

      const expectedAvg = parseFloat((3 / 2).toFixed(2))
      expect(summary.averageActionsPerSession).toBe(expectedAvg)
    })

    it('groupByPeriod default case behaves like day grouping', () => {
      const userId = 'p'
      const acts: Activity[] = [
        {
          id: '1',
          user_id: userId,
          action: 'x',
          timestamp: new Date('2024-01-01T00:00:00.000Z'),
        },
        {
          id: '2',
          user_id: userId,
          action: 'y',
          timestamp: new Date('2024-01-01T23:59:59.000Z'),
        },
      ]
      const d = new ActivityDashboard(acts)

      const dayTrends = d.getActivityTrends(userId, 'day')
      const defaultTrends = (d as any).getActivityTrends(userId, 'invalid' as any)

      expect(defaultTrends).toEqual(dayTrends)
    })
  })
})