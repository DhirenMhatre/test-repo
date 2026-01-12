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
	assert.False(t, log.Timestamp.IsZero())

	// Ensure it is stored
	logs := tracker.GetActivityByUser(userID)
	assert.Len(t, logs, 1)
	assert.Equal(t, log.ID, logs[0].ID)
}

func TestTracker_LogActivity_IDCounterIncrements(t *testing.T) {
	tracker := NewTracker()

	log1 := tracker.LogActivity("user1", "action1", nil)
	log2 := tracker.LogActivity("user1", "action2", nil)

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
	tracker.LogActivity("user1", "login", nil)
	tracker.LogActivity("user1", "logout", nil)

	logs = tracker.GetActivityByUser("user1")
	assert.Len(t, logs, 2)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"
	tracker.LogActivity(userID, "login", nil)

	logs := tracker.GetActivityByUser(userID)
	assert.Len(t, logs, 1)

	// Modify returned slice and ensure internal state is not affected
	logs[0].Action = "modified"

	internalLogs := tracker.GetActivityByUser(userID)
	assert.Equal(t, "login", internalLogs[0].Action)
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
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)

	// Existing user but no logs (should not happen with current code, but test defensively)
	tracker.activities["emptyUser"] = []ActivityLog{}
	stats = tracker.GetActivityStats("emptyUser")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_WithLogs(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	// Fixed timestamps for deterministic tests
	base := time.Date(2024, 1, 1, 10, 0, 0, 0, time.UTC)
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

	tracker.activities[userID] = logs

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

func TestTracker_GetActivityByDateRange(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	base := time.Date(2024, 1, 1, 10, 0, 0, 0, time.UTC)
	logs := []ActivityLog{
		{
			ID:        "1",
			UserID:    userID,
			Action:    "a1",
			Timestamp: base.Add(-2 * time.Hour),
		},
		{
			ID:        "2",
			UserID:    userID,
			Action:    "a2",
			Timestamp: base.Add(-1 * time.Hour),
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "a3",
			Timestamp: base,
		},
		{
			ID:        "4",
			UserID:    userID,
			Action:    "a4",
			Timestamp: base.Add(1 * time.Hour),
		},
	}
	tracker.activities[userID] = logs

	tests := []struct {
		name      string
		start     time.Time
		end       time.Time
		wantIDs   []string
		userID    string
		setupUser bool
	}{
		{
			name:    "no user",
			start:   base.Add(-3 * time.Hour),
			end:     base.Add(3 * time.Hour),
			wantIDs: []string{},
			userID:  "unknown",
		},
		{
			name:    "full range includes all",
			start:   base.Add(-3 * time.Hour),
			end:     base.Add(3 * time.Hour),
			wantIDs: []string{"1", "2", "3", "4"},
			userID:  userID,
		},
		{
			name:    "middle range",
			start:   base.Add(-90 * time.Minute),
			end:     base.Add(30 * time.Minute),
			wantIDs: []string{"2", "3"},
			userID:  userID,
		},
		{
			name:    "exact boundaries inclusive",
			start:   logs[1].Timestamp,
			end:     logs[2].Timestamp,
			wantIDs: []string{"2", "3"},
			userID:  userID,
		},
		{
			name:    "no matches",
			start:   base.Add(2 * time.Hour),
			end:     base.Add(3 * time.Hour),
			wantIDs: []string{},
			userID:  userID,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tracker.GetActivityByDateRange(tt.userID, tt.start, tt.end)
			assert.Len(t, result, len(tt.wantIDs))
			for i, id := range tt.wantIDs {
				assert.Equal(t, id, result[i].ID)
			}
		})
	}
}

func TestTracker_GetAllUsers(t *testing.T) {
	tracker := NewTracker()

	// No users
	users := tracker.GetAllUsers()
	assert.NotNil(t, users)
	assert.Len(t, users, 0)

	// Add users
	tracker.LogActivity("userB", "action", nil)
	tracker.LogActivity("userA", "action", nil)
	tracker.LogActivity("userC", "action", nil)

	users = tracker.GetAllUsers()
	assert.Equal(t, []string{"userA", "userB", "userC"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tracker := NewTracker()

	// Non-existing user
	ok := tracker.DeleteUserActivity("unknown")
	assert.False(t, ok)

	// Existing user
	tracker.LogActivity("user1", "action", nil)
	assert.Len(t, tracker.activities["user1"], 1)

	ok = tracker.DeleteUserActivity("user1")
	assert.True(t, ok)
	_, exists := tracker.activities["user1"]
	assert.False(t, exists)

	// Deleting again should return false
	ok = tracker.DeleteUserActivity("user1")
	assert.False(t, ok)
}

func TestGenerateID(t *testing.T) {
	id1 := generateID(1)
	time.Sleep(10 * time.Millisecond)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
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
			name: "tie chooses first max encountered",
			actionCounts: map[string]int{
				"login": 3,
				"view":  3,
			},
			// Implementation returns the first with max count encountered in map iteration.
			// Map iteration order is not guaranteed, so we only assert that result is one of them.
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := findMostFrequentAction(tt.actionCounts)
			if tt.expected == "" && len(tt.actionCounts) > 1 {
				// tie case: result should be one of the keys with max count
				max := 0
				for _, c := range tt.actionCounts {
					if c > max {
						max = c
					}
				}
				assert.NotEmpty(t, result)
				assert.Equal(t, max, tt.actionCounts[result])
			} else {
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}
