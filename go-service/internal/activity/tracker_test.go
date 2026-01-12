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
	assert.Equal(t, *log, logs[0])
}

func TestTracker_LogActivity_IDCounterIncrements(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	log1 := tracker.LogActivity(userID, "action1", nil)
	log2 := tracker.LogActivity(userID, "action2", nil)

	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, 2, tracker.idCounter)
}

func TestTracker_GetActivityByUser_NoActivities(t *testing.T) {
	tracker := NewTracker()
	userID := "nonexistent"

	logs := tracker.GetActivityByUser(userID)
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	tracker.LogActivity(userID, "action1", nil)
	original := tracker.GetActivityByUser(userID)
	assert.Len(t, original, 1)

	// Modify returned slice and ensure internal state is not affected
	original[0].Action = "modified"

	internal := tracker.GetActivityByUser(userID)
	assert.Equal(t, "action1", internal[0].Action)
}

func TestTracker_GetActivityStats_NoUserOrEmpty(t *testing.T) {
	tracker := NewTracker()

	stats := tracker.GetActivityStats("nonexistent")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)

	// Explicitly test empty slice case
	userID := "user1"
	tracker.activities[userID] = []ActivityLog{}
	stats2 := tracker.GetActivityStats(userID)
	assert.NotNil(t, stats2)
	assert.Equal(t, 0, stats2.TotalActions)
	assert.Equal(t, 0, stats2.UniqueActions)
	assert.NotNil(t, stats2.ActionCounts)
	assert.Len(t, stats2.ActionCounts, 0)
}

func TestTracker_GetActivityStats_WithActivities(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	baseTime := time.Now().Add(-time.Hour)
	// Manually insert logs with controlled timestamps
	tracker.activities[userID] = []ActivityLog{
		{
			ID:        "1",
			UserID:    userID,
			Action:    "login",
			Timestamp: baseTime.Add(10 * time.Minute),
		},
		{
			ID:        "2",
			UserID:    userID,
			Action:    "view",
			Timestamp: baseTime.Add(20 * time.Minute),
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "login",
			Timestamp: baseTime.Add(30 * time.Minute),
		},
	}

	stats := tracker.GetActivityStats(userID)
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.Equal(t, baseTime.Add(10*time.Minute), stats.FirstActivity)
	assert.Equal(t, baseTime.Add(30*time.Minute), stats.LastActivity)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_NoUser(t *testing.T) {
	tracker := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now()

	logs := tracker.GetActivityByDateRange("nonexistent", start, end)
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByDateRange_Filtering(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"
	baseTime := time.Now().Add(-2 * time.Hour)

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
			Timestamp: baseTime.Add(30 * time.Minute),
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "a3",
			Timestamp: baseTime.Add(60 * time.Minute),
		},
	}
	tracker.activities[userID] = logs

	tests := []struct {
		name      string
		start     time.Time
		end       time.Time
		wantIDs   []string
	}{
		{
			name:    "range includes all",
			start:   baseTime,
			end:     baseTime.Add(60 * time.Minute),
			wantIDs: []string{"1", "2", "3"},
		},
		{
			name:    "range middle subset",
			start:   baseTime.Add(15 * time.Minute),
			end:     baseTime.Add(45 * time.Minute),
			wantIDs: []string{"2"},
		},
		{
			name:    "range single exact match start",
			start:   baseTime,
			end:     baseTime.Add(0),
			wantIDs: []string{"1"},
		},
		{
			name:    "range single exact match end",
			start:   baseTime.Add(60 * time.Minute),
			end:     baseTime.Add(60 * time.Minute),
			wantIDs: []string{"3"},
		},
		{
			name:    "range none",
			start:   baseTime.Add(70 * time.Minute),
			end:     baseTime.Add(80 * time.Minute),
			wantIDs: []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tracker.GetActivityByDateRange(userID, tt.start, tt.end)
			assert.Len(t, got, len(tt.wantIDs))
			for i, id := range tt.wantIDs {
				assert.Equal(t, id, got[i].ID)
			}
		})
	}
}

func TestTracker_GetAllUsers_Empty(t *testing.T) {
	tracker := NewTracker()
	users := tracker.GetAllUsers()
	assert.NotNil(t, users)
	assert.Len(t, users, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tracker := NewTracker()
	tracker.activities["userB"] = []ActivityLog{}
	tracker.activities["userA"] = []ActivityLog{}
	tracker.activities["userC"] = []ActivityLog{}

	users := tracker.GetAllUsers()
	assert.Equal(t, []string{"userA", "userB", "userC"}, users)
}

func TestTracker_DeleteUserActivity_UserExists(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"
	tracker.activities[userID] = []ActivityLog{
		{ID: "1", UserID: userID, Action: "a1", Timestamp: time.Now()},
	}

	ok := tracker.DeleteUserActivity(userID)
	assert.True(t, ok)
	_, exists := tracker.activities[userID]
	assert.False(t, exists)
}

func TestTracker_DeleteUserActivity_UserNotExists(t *testing.T) {
	tracker := NewTracker()
	ok := tracker.DeleteUserActivity("nonexistent")
	assert.False(t, ok)
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

func TestFindMostFrequentAction_Empty(t *testing.T) {
	result := findMostFrequentAction(map[string]int{})
	assert.Equal(t, "", result)
}

func TestFindMostFrequentAction_Single(t *testing.T) {
	result := findMostFrequentAction(map[string]int{"login": 3})
	assert.Equal(t, "login", result)
}

func TestFindMostFrequentAction_Multiple(t *testing.T) {
	counts := map[string]int{
		"login":  5,
		"view":   2,
		"logout": 3,
	}
	result := findMostFrequentAction(counts)
	assert.Equal(t, "login", result)
}
