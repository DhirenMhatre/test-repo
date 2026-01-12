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

func TestTracker_GetActivityByUser_EmptyAndCopy(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	// No activities yet
	logs := tracker.GetActivityByUser(userID)
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)

	// Add activities
	tracker.LogActivity(userID, "a1", nil)
	tracker.LogActivity(userID, "a2", nil)

	logs = tracker.GetActivityByUser(userID)
	assert.Len(t, logs, 2)

	// Ensure copy is returned (modifying result does not affect internal slice)
	originalFirstID := logs[0].ID
	logs[0].ID = "modified"
	internalLogs := tracker.activities[userID]
	assert.Equal(t, originalFirstID, internalLogs[0].ID)
}

func TestTracker_GetActivityStats_NoUserOrEmpty(t *testing.T) {
	tracker := NewTracker()

	stats := tracker.GetActivityStats("unknown")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)

	// Explicit empty user slice
	tracker.activities["user1"] = []ActivityLog{}
	stats = tracker.GetActivityStats("user1")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
}

func TestTracker_GetActivityStats_WithData(t *testing.T) {
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
			Action:    "a",
			Timestamp: base.Add(-10 * time.Minute),
		},
		{
			ID:        "2",
			UserID:    userID,
			Action:    "b",
			Timestamp: base,
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "c",
			Timestamp: base.Add(10 * time.Minute),
		},
	}
	tracker.activities[userID] = logs

	tests := []struct {
		name    string
		start   time.Time
		end     time.Time
		wantIDs []string
		userID  string
	}{
		{
			name:    "no user",
			start:   base.Add(-1 * time.Hour),
			end:     base.Add(1 * time.Hour),
			wantIDs: []string{},
			userID:  "unknown",
		},
		{
			name:    "full range includes all",
			start:   base.Add(-1 * time.Hour),
			end:     base.Add(1 * time.Hour),
			wantIDs: []string{"1", "2", "3"},
			userID:  userID,
		},
		{
			name:    "exact match single",
			start:   base,
			end:     base,
			wantIDs: []string{"2"},
			userID:  userID,
		},
		{
			name:    "between start and end",
			start:   base.Add(-5 * time.Minute),
			end:     base.Add(5 * time.Minute),
			wantIDs: []string{"2"},
			userID:  userID,
		},
		{
			name:    "upper bound inclusive",
			start:   base,
			end:     base.Add(10 * time.Minute),
			wantIDs: []string{"2", "3"},
			userID:  userID,
		},
		{
			name:    "lower bound inclusive",
			start:   base.Add(-10 * time.Minute),
			end:     base,
			wantIDs: []string{"1", "2"},
			userID:  userID,
		},
		{
			name:    "no matches",
			start:   base.Add(20 * time.Minute),
			end:     base.Add(30 * time.Minute),
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

	// Add users in unsorted order
	tracker.activities["userB"] = []ActivityLog{}
	tracker.activities["userA"] = []ActivityLog{}
	tracker.activities["userC"] = []ActivityLog{}

	users = tracker.GetAllUsers()
	assert.Equal(t, []string{"userA", "userB", "userC"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tracker := NewTracker()
	tracker.activities["user1"] = []ActivityLog{{ID: "1", UserID: "user1"}}

	// Delete existing
	ok := tracker.DeleteUserActivity("user1")
	assert.True(t, ok)
	_, exists := tracker.activities["user1"]
	assert.False(t, exists)

	// Delete non-existing
	ok = tracker.DeleteUserActivity("user2")
	assert.False(t, ok)
}

func TestGenerateID(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	// Basic format check: should contain a dash
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
			name: "tie chooses first max encountered",
			actionCounts: map[string]int{
				"a": 2,
				"b": 2,
			},
			// Implementation returns the first with max count encountered in map iteration.
			// Map iteration order is not guaranteed, so we only assert that result is one of them.
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := findMostFrequentAction(tt.actionCounts)
			if tt.expected == "" && len(tt.actionCounts) > 0 {
				// tie case: ensure result is one of the keys with max count
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
