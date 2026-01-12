package activity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()
	userID := "user1"
	action := "login"
	metadata := map[string]interface{}{"ip": "127.0.0.1"}

	log := tr.LogActivity(userID, action, metadata)

	assert.NotNil(t, log)
	assert.Equal(t, userID, log.UserID)
	assert.Equal(t, action, log.Action)
	assert.Equal(t, metadata, log.Metadata)
	assert.NotEmpty(t, log.ID)
	assert.WithinDuration(t, time.Now(), log.Timestamp, time.Second)

	// Ensure it was stored
	logs := tr.GetActivityByUser(userID)
	assert.Len(t, logs, 1)
	assert.Equal(t, *log, logs[0])
}

func TestTracker_LogActivity_IDCounterIncrements(t *testing.T) {
	tr := NewTracker()

	log1 := tr.LogActivity("user1", "a1", nil)
	log2 := tr.LogActivity("user1", "a2", nil)

	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, 2, tr.idCounter)
}

func TestTracker_GetActivityByUser_EmptyAndNonExisting(t *testing.T) {
	tr := NewTracker()

	// No activities at all
	logs := tr.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)

	// Add for another user
	tr.LogActivity("user1", "a1", nil)
	logs = tr.GetActivityByUser("user2")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	userID := "user1"

	tr.LogActivity(userID, "a1", nil)
	original := tr.GetActivityByUser(userID)
	assert.Len(t, original, 1)

	// Mutate returned slice and element; internal storage should not change
	original[0].Action = "modified"
	original = append(original, ActivityLog{UserID: userID, Action: "new"})

	internal := tr.GetActivityByUser(userID)
	assert.Len(t, internal, 1)
	assert.Equal(t, "a1", internal[0].Action)
}

func TestTracker_GetActivityStats_NoUserOrNoLogs(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("unknown")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)

	// User exists but no logs (should not happen with current code, but test anyway)
	tr.activities["user1"] = []ActivityLog{}
	stats = tr.GetActivityStats("user1")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_WithLogs(t *testing.T) {
	tr := NewTracker()
	userID := "user1"

	base := time.Now().Add(-time.Hour)
	// Manually control timestamps by inserting directly into activities
	tr.activities[userID] = []ActivityLog{
		{ID: "1", UserID: userID, Action: "login", Timestamp: base.Add(10 * time.Minute)},
		{ID: "2", UserID: userID, Action: "view", Timestamp: base.Add(20 * time.Minute)},
		{ID: "3", UserID: userID, Action: "login", Timestamp: base.Add(30 * time.Minute)},
		{ID: "4", UserID: userID, Action: "purchase", Timestamp: base.Add(40 * time.Minute)},
		{ID: "5", UserID: userID, Action: "login", Timestamp: base.Add(50 * time.Minute)},
	}

	stats := tr.GetActivityStats(userID)
	assert.NotNil(t, stats)
	assert.Equal(t, 5, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 3, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["purchase"])
	assert.Equal(t, "login", stats.MostFrequent)
	assert.Equal(t, tr.activities[userID][0].Timestamp, stats.FirstActivity)
	assert.Equal(t, tr.activities[userID][4].Timestamp, stats.LastActivity)
}

func TestTracker_GetActivityByDateRange_NoUser(t *testing.T) {
	tr := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now().Add(time.Hour)

	logs := tr.GetActivityByDateRange("unknown", start, end)
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByDateRange_InclusiveBounds(t *testing.T) {
	tr := NewTracker()
	userID := "user1"
	base := time.Date(2025, 1, 1, 10, 0, 0, 0, time.UTC)

	tr.activities[userID] = []ActivityLog{
		{ID: "1", UserID: userID, Action: "before", Timestamp: base.Add(-time.Minute)},
		{ID: "2", UserID: userID, Action: "start", Timestamp: base},
		{ID: "3", UserID: userID, Action: "middle", Timestamp: base.Add(30 * time.Minute)},
		{ID: "4", UserID: userID, Action: "end", Timestamp: base.Add(time.Hour)},
		{ID: "5", UserID: userID, Action: "after", Timestamp: base.Add(time.Hour + time.Minute)},
	}

	start := base
	end := base.Add(time.Hour)

	logs := tr.GetActivityByDateRange(userID, start, end)
	assert.Len(t, logs, 3)
	var actions []string
	for _, l := range logs {
		actions = append(actions, l.Action)
	}
	assert.ElementsMatch(t, []string{"start", "middle", "end"}, actions)
}

func TestTracker_GetActivityByDateRange_EmptyRange(t *testing.T) {
	tr := NewTracker()
	userID := "user1"
	now := time.Now()

	tr.activities[userID] = []ActivityLog{
		{ID: "1", UserID: userID, Action: "a1", Timestamp: now},
	}

	// start after end -> no results
	start := now.Add(time.Hour)
	end := now.Add(-time.Hour)

	logs := tr.GetActivityByDateRange(userID, start, end)
	assert.Len(t, logs, 0)
}

func TestTracker_GetAllUsers_EmptyAndSorted(t *testing.T) {
	tr := NewTracker()

	users := tr.GetAllUsers()
	assert.NotNil(t, users)
	assert.Len(t, users, 0)

	// Add users in unsorted order
	tr.activities["charlie"] = []ActivityLog{}
	tr.activities["alice"] = []ActivityLog{}
	tr.activities["bob"] = []ActivityLog{}

	users = tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.activities["user1"] = []ActivityLog{{UserID: "user1", Action: "a1"}}
	tr.activities["user2"] = []ActivityLog{{UserID: "user2", Action: "a2"}}

	ok := tr.DeleteUserActivity("user1")
	assert.True(t, ok)
	_, exists := tr.activities["user1"]
	assert.False(t, exists)
	_, exists = tr.activities["user2"]
	assert.True(t, exists)

	// Deleting non-existing user
	ok = tr.DeleteUserActivity("unknown")
	assert.False(t, ok)
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.Contains(t, id1, "-")
	assert.Contains(t, id2, "-")
}

func TestFindMostFrequentAction_Empty(t *testing.T) {
	result := findMostFrequentAction(map[string]int{})
	assert.Equal(t, "", result)
}

func TestFindMostFrequentAction_SingleAndMultiple(t *testing.T) {
	counts := map[string]int{
		"login":    3,
		"view":     1,
		"purchase": 2,
	}
	result := findMostFrequentAction(counts)
	assert.Equal(t, "login", result)

	// Tie case: ensure it returns one of the max-count keys (map iteration order is undefined)
	counts = map[string]int{
		"a": 2,
		"b": 2,
	}
	result = findMostFrequentAction(counts)
	assert.True(t, result == "a" || result == "b")
}
