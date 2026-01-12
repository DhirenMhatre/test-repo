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

func TestTracker_GetActivityByUser_EmptyAndCopy(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	// No activities yet
	logs := tracker.GetActivityByUser(userID)
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)

	// Add one activity
	tracker.LogActivity(userID, "login", nil)
	logs = tracker.GetActivityByUser(userID)
	assert.Len(t, logs, 1)

	// Ensure returned slice is a copy (modifying it does not affect internal state)
	logs[0].Action = "modified"
	internalLogs := tracker.GetActivityByUser(userID)
	assert.Equal(t, "login", internalLogs[0].Action)
}

func TestTracker_GetActivityStats_NoUserOrEmpty(t *testing.T) {
	tracker := NewTracker()

	stats := tracker.GetActivityStats("nonexistent")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))

	// User with no logs (should behave same as nonexistent)
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

	baseTime := time.Now().Add(-time.Hour)
	logs := []ActivityLog{
		{
			ID:        "1",
			UserID:    userID,
			Action:    "login",
			Timestamp: baseTime.Add(1 * time.Minute),
		},
		{
			ID:        "2",
			UserID:    userID,
			Action:    "view",
			Timestamp: baseTime.Add(2 * time.Minute),
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "login",
			Timestamp: baseTime.Add(3 * time.Minute),
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

	baseTime := time.Now().Add(-time.Hour)
	logs := []ActivityLog{
		{
			ID:        "1",
			UserID:    userID,
			Action:    "a1",
			Timestamp: baseTime.Add(0 * time.Minute),
		},
		{
			ID:        "2",
			UserID:    userID,
			Action:    "a2",
			Timestamp: baseTime.Add(10 * time.Minute),
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "a3",
			Timestamp: baseTime.Add(20 * time.Minute),
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
			start:   baseTime,
			end:     baseTime.Add(30 * time.Minute),
			wantIDs: []string{},
			userID:  "unknown",
		},
		{
			name:    "full range includes all",
			start:   baseTime,
			end:     baseTime.Add(20 * time.Minute),
			wantIDs: []string{"1", "2", "3"},
			userID:  userID,
		},
		{
			name:    "middle range",
			start:   baseTime.Add(5 * time.Minute),
			end:     baseTime.Add(15 * time.Minute),
			wantIDs: []string{"2"},
			userID:  userID,
		},
		{
			name:    "exact boundaries",
			start:   logs[0].Timestamp,
			end:     logs[2].Timestamp,
			wantIDs: []string{"1", "2", "3"},
			userID:  userID,
		},
		{
			name:    "no matches",
			start:   baseTime.Add(30 * time.Minute),
			end:     baseTime.Add(40 * time.Minute),
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
				"login": 3,
				"view":  5,
				"edit":  2,
			},
			expected: "view",
		},
		{
			name: "tie chooses first max encountered",
			actionCounts: map[string]int{
				"login": 5,
				"view":  5,
			},
			// Implementation returns the first with max count encountered in map iteration.
			// Since map iteration order is random, we can only assert that result is one of them.
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := findMostFrequentAction(tt.actionCounts)
			if tt.expected != "" {
				assert.Equal(t, tt.expected, result)
			} else if len(tt.actionCounts) == 0 {
				assert.Equal(t, "", result)
			} else {
				// tie case: result must be one of the keys with max count
				max := 0
				for _, c := range tt.actionCounts {
					if c > max {
						max = c
					}
				}
				assert.NotEmpty(t, result)
				assert.Equal(t, max, tt.actionCounts[result])
			}
		})
	}
}
