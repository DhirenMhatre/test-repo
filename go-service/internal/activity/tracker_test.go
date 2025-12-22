package activity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
	assert.Empty(t, tr.activities)
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()
	metadata := map[string]interface{}{"ip": "127.0.0.1"}

	log := tr.LogActivity("user1", "login", metadata)

	assert.NotNil(t, log)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.Equal(t, metadata, log.Metadata)
	assert.NotEmpty(t, log.ID)
	assert.False(t, log.Timestamp.IsZero())

	// Ensure it was stored
	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 1)
	assert.Equal(t, log.ID, logs[0].ID)
}

func TestTracker_LogActivity_IDCounterIncrements(t *testing.T) {
	tr := NewTracker()

	log1 := tr.LogActivity("user1", "a1", nil)
	log2 := tr.LogActivity("user1", "a2", nil)

	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, 2, tr.idCounter)
}

func TestTracker_GetActivityByUser_NoUser(t *testing.T) {
	tr := NewTracker()

	logs := tr.GetActivityByUser("nonexistent")
	assert.NotNil(t, logs)
	assert.Empty(t, logs)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("user1", "login", nil)

	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 1)

	// Mutate returned slice and element; internal state should not change
	logs[0].Action = "changed"
	logs = append(logs, ActivityLog{UserID: "user1", Action: "extra"})

	internal := tr.GetActivityByUser("user1")
	assert.Len(t, internal, 1)
	assert.Equal(t, "login", internal[0].Action)
}

func TestTracker_GetActivityStats_NoUserOrEmpty(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("nonexistent")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)

	// Explicitly test user with empty slice
	tr.activities["empty"] = []ActivityLog{}
	stats2 := tr.GetActivityStats("empty")
	assert.NotNil(t, stats2)
	assert.Equal(t, 0, stats2.TotalActions)
	assert.Equal(t, 0, stats2.UniqueActions)
	assert.NotNil(t, stats2.ActionCounts)
	assert.Empty(t, stats2.ActionCounts)
}

func TestTracker_GetActivityStats_ComputesCorrectly(t *testing.T) {
	tr := NewTracker()
	base := time.Now().Add(-time.Hour)

	// Manually control timestamps
	logs := []ActivityLog{
		{
			ID:        "1",
			UserID:    "u1",
			Action:    "login",
			Timestamp: base.Add(10 * time.Minute),
		},
		{
			ID:        "2",
			UserID:    "u1",
			Action:    "view",
			Timestamp: base.Add(20 * time.Minute),
		},
		{
			ID:        "3",
			UserID:    "u1",
			Action:    "login",
			Timestamp: base.Add(30 * time.Minute),
		},
	}
	tr.activities["u1"] = logs

	stats := tr.GetActivityStats("u1")
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
	tr := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now()

	logs := tr.GetActivityByDateRange("nonexistent", start, end)
	assert.NotNil(t, logs)
	assert.Empty(t, logs)
}

func TestTracker_GetActivityByDateRange_FiltersInclusive(t *testing.T) {
	tr := NewTracker()
	base := time.Now().Add(-time.Hour)

	logs := []ActivityLog{
		{
			ID:        "1",
			UserID:    "u1",
			Action:    "a1",
			Timestamp: base.Add(-10 * time.Minute), // before range
		},
		{
			ID:        "2",
			UserID:    "u1",
			Action:    "a2",
			Timestamp: base, // start boundary
		},
		{
			ID:        "3",
			UserID:    "u1",
			Action:    "a3",
			Timestamp: base.Add(10 * time.Minute), // inside
		},
		{
			ID:        "4",
			UserID:    "u1",
			Action:    "a4",
			Timestamp: base.Add(20 * time.Minute), // end boundary
		},
		{
			ID:        "5",
			UserID:    "u1",
			Action:    "a5",
			Timestamp: base.Add(30 * time.Minute), // after range
		},
	}
	tr.activities["u1"] = logs

	start := base
	end := base.Add(20 * time.Minute)

	filtered := tr.GetActivityByDateRange("u1", start, end)
	assert.Len(t, filtered, 3)
	assert.Equal(t, "2", filtered[0].ID)
	assert.Equal(t, "3", filtered[1].ID)
	assert.Equal(t, "4", filtered[2].ID)
}

func TestTracker_GetAllUsers_Empty(t *testing.T) {
	tr := NewTracker()
	users := tr.GetAllUsers()
	assert.NotNil(t, users)
	assert.Empty(t, users)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.activities["charlie"] = []ActivityLog{}
	tr.activities["alice"] = []ActivityLog{}
	tr.activities["bob"] = []ActivityLog{}

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity_UserExists(t *testing.T) {
	tr := NewTracker()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a1"},
	}

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	_, exists := tr.activities["u1"]
	assert.False(t, exists)
}

func TestTracker_DeleteUserActivity_UserNotExists(t *testing.T) {
	tr := NewTracker()

	ok := tr.DeleteUserActivity("missing")
	assert.False(t, ok)
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	// Ensure it contains a dash and suffix corresponds to rune(counter)
	assert.Contains(t, id1, "-")
}

func TestFindMostFrequentAction_Empty(t *testing.T) {
	result := findMostFrequentAction(map[string]int{})
	assert.Equal(t, "", result)
}

func TestFindMostFrequentAction_SingleAndMultiple(t *testing.T) {
	counts := map[string]int{
		"login":  5,
		"view":   3,
		"logout": 1,
	}
	result := findMostFrequentAction(counts)
	assert.Equal(t, "login", result)

	// Tie case: ensure it returns one of the max entries (implementation-defined)
	countsTie := map[string]int{
		"a": 2,
		"b": 2,
	}
	resultTie := findMostFrequentAction(countsTie)
	assert.Contains(t, []string{"a", "b"}, resultTie)
}
