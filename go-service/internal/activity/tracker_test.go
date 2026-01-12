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

func TestTracker_GetActivityByUser_NoActivities(t *testing.T) {
	tracker := NewTracker()
	logs := tracker.GetActivityByUser("nonexistent")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"
	tracker.LogActivity(userID, "action1", nil)
	tracker.LogActivity(userID, "action2", nil)

	logs := tracker.GetActivityByUser(userID)
	assert.Len(t, logs, 2)

	// Modify returned slice and ensure internal state is not affected
	logs[0].Action = "modified"

	internalLogs := tracker.GetActivityByUser(userID)
	assert.Equal(t, "action1", internalLogs[0].Action)
}

func TestTracker_GetActivityStats_NoUserOrNoLogs(t *testing.T) {
	tracker := NewTracker()

	stats := tracker.GetActivityStats("nonexistent")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)

	// User exists but no logs
	userID := "user1"
	tracker.activities[userID] = []ActivityLog{}
	stats2 := tracker.GetActivityStats(userID)
	assert.NotNil(t, stats2)
	assert.Equal(t, 0, stats2.TotalActions)
	assert.Equal(t, 0, stats2.UniqueActions)
	assert.NotNil(t, stats2.ActionCounts)
	assert.Equal(t, 0, len(stats2.ActionCounts))
	assert.True(t, stats2.FirstActivity.IsZero())
	assert.True(t, stats2.LastActivity.IsZero())
	assert.Equal(t, "", stats2.MostFrequent)
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
			Timestamp: base,
		},
		{
			ID:        "2",
			UserID:    userID,
			Action:    "view",
			Timestamp: base.Add(10 * time.Minute),
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "login",
			Timestamp: base.Add(20 * time.Minute),
		},
	}
	tracker.activities[userID] = logs

	stats := tracker.GetActivityStats(userID)
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.Equal(t, base, stats.FirstActivity)
	assert.Equal(t, base.Add(20*time.Minute), stats.LastActivity)
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
	base := time.Date(2024, 1, 1, 10, 0, 0, 0, time.UTC)

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
	tracker.activities[userID] = logs

	start := base
	end := base.Add(20 * time.Minute)

	filtered := tracker.GetActivityByDateRange(userID, start, end)
	assert.Len(t, filtered, 3)
	assert.Equal(t, "2", filtered[0].ID)
	assert.Equal(t, "3", filtered[1].ID)
	assert.Equal(t, "4", filtered[2].ID)
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
	actionCounts := map[string]int{
		"login":  5,
		"view":   2,
		"logout": 3,
	}
	result := findMostFrequentAction(actionCounts)
	assert.Equal(t, "login", result)
}

func TestTracker_Concurrency_LogAndRead(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	done := make(chan struct{})
	go func() {
		for i := 0; i < 50; i++ {
			tracker.LogActivity(userID, "action", nil)
		}
		close(done)
	}()

	for i := 0; i < 50; i++ {
		_ = tracker.GetActivityByUser(userID)
		_ = tracker.GetActivityStats(userID)
	}

	<-done
	logs := tracker.GetActivityByUser(userID)
	assert.True(t, len(logs) >= 50)
}
