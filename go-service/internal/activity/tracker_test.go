package activity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tracker := NewTracker()
	assert.NotNil(t, tracker)
	assert.NotNil(t, tracker.activities)
	assert.Equal(t, 0, tracker.idCounter)
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"
	action := "login"
	metadata := map[string]interface{}{"ip": "127.0.0.1"}

	log := tracker.LogActivity(userID, action, metadata)

	assert.NotNil(t, log)
	assert.Equal(t, userID, log.UserID)
	assert.Equal(t, action, log.Action)
	assert.Equal(t, metadata, log.Metadata)
	assert.NotEmpty(t, log.ID)
	assert.WithinDuration(t, time.Now(), log.Timestamp, time.Second)

	// Ensure it is stored
	logs := tracker.GetActivityByUser(userID)
	assert.Len(t, logs, 1)
	assert.Equal(t, log.ID, logs[0].ID)
}

func TestTracker_LogActivity_IDCounterIncrements(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	log1 := tracker.LogActivity(userID, "action1", nil)
	log2 := tracker.LogActivity(userID, "action2", nil)

	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, 2, tracker.idCounter)
}

func TestTracker_GetActivityByUser_EmptyAndNonExisting(t *testing.T) {
	tracker := NewTracker()

	// Non-existing user
	logs := tracker.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)

	// Existing user with activities
	tracker.LogActivity("user1", "a1", nil)
	tracker.LogActivity("user1", "a2", nil)

	logs = tracker.GetActivityByUser("user1")
	assert.Len(t, logs, 2)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"
	tracker.LogActivity(userID, "a1", nil)

	logs := tracker.GetActivityByUser(userID)
	assert.Len(t, logs, 1)

	// Modify returned slice and ensure internal state is not affected
	logs[0].Action = "modified"

	internalLogs := tracker.GetActivityByUser(userID)
	assert.Equal(t, "a1", internalLogs[0].Action)
}

func TestTracker_GetActivityStats_NoUserOrNoLogs(t *testing.T) {
	tracker := NewTracker()

	// Non-existing user
	stats := tracker.GetActivityStats("unknown")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))

	// Existing user but no logs (should not happen with current code, but test anyway)
	tracker.activities["user1"] = []ActivityLog{}
	stats = tracker.GetActivityStats("user1")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))
}

func TestTracker_GetActivityStats_WithLogs(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	// Create deterministic timestamps
	base := time.Now().Add(-time.Hour)
	logs := []ActivityLog{
		{
			ID:        "1",
			UserID:    userID,
			Action:    "login",
			Timestamp: base.Add(1 * time.Minute),
		},
		{
			ID:        "2",
			UserID:    userID,
			Action:    "view",
			Timestamp: base.Add(2 * time.Minute),
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "login",
			Timestamp: base.Add(3 * time.Minute),
		},
	}

	tracker.mu.Lock()
	tracker.activities[userID] = logs
	tracker.mu.Unlock()

	stats := tracker.GetActivityStats(userID)
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.Equal(t, logs[0].Timestamp, stats.FirstActivity)
	assert.Equal(t, logs[2].Timestamp, stats.LastActivity)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_NoUser(t *testing.T) {
	tracker := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now()

	logs := tracker.GetActivityByDateRange("unknown", start, end)
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByDateRange_Filtering(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"
	base := time.Now().Add(-time.Hour)

	logs := []ActivityLog{
		{
			ID:        "1",
			UserID:    userID,
			Action:    "a1",
			Timestamp: base.Add(-10 * time.Minute), // before range
		},
		{
			ID:        "2",
			UserID:    userID,
			Action:    "a2",
			Timestamp: base, // start boundary
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "a3",
			Timestamp: base.Add(10 * time.Minute), // inside
		},
		{
			ID:        "4",
			UserID:    userID,
			Action:    "a4",
			Timestamp: base.Add(20 * time.Minute), // end boundary
		},
		{
			ID:        "5",
			UserID:    userID,
			Action:    "a5",
			Timestamp: base.Add(30 * time.Minute), // after range
		},
	}

	tracker.mu.Lock()
	tracker.activities[userID] = logs
	tracker.mu.Unlock()

	start := base
	end := base.Add(20 * time.Minute)

	filtered := tracker.GetActivityByDateRange(userID, start, end)
	assert.Len(t, filtered, 3)
	assert.Equal(t, "2", filtered[0].ID)
	assert.Equal(t, "3", filtered[1].ID)
	assert.Equal(t, "4", filtered[2].ID)
}

func TestTracker_GetAllUsers_EmptyAndSorted(t *testing.T) {
	tracker := NewTracker()

	// Empty
	users := tracker.GetAllUsers()
	assert.NotNil(t, users)
	assert.Len(t, users, 0)

	// Add users in unsorted order
	tracker.LogActivity("userB", "a1", nil)
	tracker.LogActivity("userA", "a1", nil)
	tracker.LogActivity("userC", "a1", nil)

	users = tracker.GetAllUsers()
	assert.Equal(t, []string{"userA", "userB", "userC"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	// Delete non-existing
	ok := tracker.DeleteUserActivity(userID)
	assert.False(t, ok)

	// Add and delete existing
	tracker.LogActivity(userID, "a1", nil)
	ok = tracker.DeleteUserActivity(userID)
	assert.True(t, ok)

	// Ensure removed
	logs := tracker.GetActivityByUser(userID)
	assert.Len(t, logs, 0)
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	// Check that there is a dash and something after it
	assert.Contains(t, id1, "-")
}

func TestFindMostFrequentAction(t *testing.T) {
	tests := []struct {
		name         string
		actionCounts map[string]int
		expected     string
	}{
		{
			name:         "empty map",
			actionCounts: map[string]int{},
			expected:     "",
		},
		{
			name: "single action",
			actionCounts: map[string]int{
				"login": 3,
			},
			expected: "login",
		},
		{
			name: "multiple actions",
			actionCounts: map[string]int{
				"login":  3,
				"view":   5,
				"logout": 2,
			},
			expected: "view",
		},
		{
			name: "tie chooses first encountered with max (map iteration is random, so just ensure result is one of max)",
			actionCounts: map[string]int{
				"a": 2,
				"b": 2,
			},
			expected: "", // we'll check membership instead of equality
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := findMostFrequentAction(tt.actionCounts)
			if tt.expected != "" {
				assert.Equal(t, tt.expected, result)
			} else {
				// For tie case, ensure result is one of the keys with max count or empty if map empty
				if len(tt.actionCounts) == 0 {
					assert.Equal(t, "", result)
				} else {
					max := 0
					for _, c := range tt.actionCounts {
						if c > max {
							max = c
						}
					}
					if result != "" {
						assert.Equal(t, max, tt.actionCounts[result])
					}
				}
			}
		})
	}
}
