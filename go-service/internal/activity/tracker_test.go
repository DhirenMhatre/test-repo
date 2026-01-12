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
	meta := map[string]interface{}{"ip": "127.0.0.1"}

	log := tr.LogActivity("user1", "login", meta)

	assert.NotNil(t, log)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.Equal(t, meta, log.Metadata)
	assert.NotEmpty(t, log.ID)
	assert.False(t, log.Timestamp.IsZero())

	// Ensure it is stored
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

	// Mutate returned slice and ensure internal state is not affected
	logs[0].Action = "mutated"

	internal := tr.GetActivityByUser("user1")
	assert.Equal(t, "login", internal[0].Action)
}

func TestTracker_GetActivityStats_NoUserOrEmpty(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("nouser")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_SingleUserMultipleActions(t *testing.T) {
	tr := NewTracker()

	// We want deterministic timestamps, so we bypass LogActivity and set directly
	now := time.Now()
	tr.activities["user1"] = []ActivityLog{
		{
			ID:        "1",
			UserID:    "user1",
			Action:    "login",
			Timestamp: now.Add(-10 * time.Minute),
		},
		{
			ID:        "2",
			UserID:    "user1",
			Action:    "view",
			Timestamp: now.Add(-5 * time.Minute),
		},
		{
			ID:        "3",
			UserID:    "user1",
			Action:    "login",
			Timestamp: now,
		},
	}

	stats := tr.GetActivityStats("user1")
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.Equal(t, "login", stats.MostFrequent)

	assert.Equal(t, now.Add(-10*time.Minute), stats.FirstActivity)
	assert.Equal(t, now, stats.LastActivity)
}

func TestTracker_GetActivityStats_DifferentUsersIsolation(t *testing.T) {
	tr := NewTracker()
	now := time.Now()

	tr.activities["user1"] = []ActivityLog{
		{ID: "1", UserID: "user1", Action: "a1", Timestamp: now},
	}
	tr.activities["user2"] = []ActivityLog{
		{ID: "2", UserID: "user2", Action: "a2", Timestamp: now},
		{ID: "3", UserID: "user2", Action: "a2", Timestamp: now},
	}

	stats1 := tr.GetActivityStats("user1")
	stats2 := tr.GetActivityStats("user2")

	assert.Equal(t, 1, stats1.TotalActions)
	assert.Equal(t, 2, stats2.TotalActions)
	assert.Equal(t, "a1", stats1.MostFrequent)
	assert.Equal(t, "a2", stats2.MostFrequent)
}

func TestTracker_GetActivityByDateRange_NoUser(t *testing.T) {
	tr := NewTracker()

	start := time.Now().Add(-time.Hour)
	end := time.Now().Add(time.Hour)

	logs := tr.GetActivityByDateRange("nouser", start, end)
	assert.NotNil(t, logs)
	assert.Empty(t, logs)
}

func TestTracker_GetActivityByDateRange_InclusiveBounds(t *testing.T) {
	tr := NewTracker()
	userID := "user1"
	now := time.Now()

	logs := []ActivityLog{
		{
			ID:        "1",
			UserID:    userID,
			Action:    "before",
			Timestamp: now.Add(-2 * time.Hour),
		},
		{
			ID:        "2",
			UserID:    userID,
			Action:    "start",
			Timestamp: now.Add(-1 * time.Hour),
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "middle",
			Timestamp: now,
		},
		{
			ID:        "4",
			UserID:    userID,
			Action:    "end",
			Timestamp: now.Add(1 * time.Hour),
		},
		{
			ID:        "5",
			UserID:    userID,
			Action:    "after",
			Timestamp: now.Add(2 * time.Hour),
		},
	}
	tr.activities[userID] = logs

	start := now.Add(-1 * time.Hour)
	end := now.Add(1 * time.Hour)

	filtered := tr.GetActivityByDateRange(userID, start, end)
	assert.Len(t, filtered, 3)

	var actions []string
	for _, l := range filtered {
		actions = append(actions, l.Action)
	}
	assert.Contains(t, actions, "start")
	assert.Contains(t, actions, "middle")
	assert.Contains(t, actions, "end")
}

func TestTracker_GetAllUsers_Empty(t *testing.T) {
	tr := NewTracker()

	users := tr.GetAllUsers()
	assert.NotNil(t, users)
	assert.Empty(t, users)
}

func TestTracker_GetAllUsers_SortedUnique(t *testing.T) {
	tr := NewTracker()

	tr.activities["b-user"] = []ActivityLog{{UserID: "b-user"}}
	tr.activities["a-user"] = []ActivityLog{{UserID: "a-user"}}
	tr.activities["c-user"] = []ActivityLog{{UserID: "c-user"}}

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a-user", "b-user", "c-user"}, users)
}

func TestTracker_DeleteUserActivity_UserExists(t *testing.T) {
	tr := NewTracker()

	tr.activities["user1"] = []ActivityLog{
		{ID: "1", UserID: "user1"},
		{ID: "2", UserID: "user1"},
	}
	tr.activities["user2"] = []ActivityLog{
		{ID: "3", UserID: "user2"},
	}

	ok := tr.DeleteUserActivity("user1")
	assert.True(t, ok)

	_, exists := tr.activities["user1"]
	assert.False(t, exists)

	// Ensure other users unaffected
	_, exists2 := tr.activities["user2"]
	assert.True(t, exists2)
}

func TestTracker_DeleteUserActivity_UserNotExists(t *testing.T) {
	tr := NewTracker()

	tr.activities["user1"] = []ActivityLog{{ID: "1", UserID: "user1"}}

	ok := tr.DeleteUserActivity("nouser")
	assert.False(t, ok)

	_, exists := tr.activities["user1"]
	assert.True(t, exists)
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	// Check that there is a dash separator and suffix matches rune of counter
	assert.Contains(t, id1, "-")
}

func TestFindMostFrequentAction_Empty(t *testing.T) {
	res := findMostFrequentAction(map[string]int{})
	assert.Equal(t, "", res)
}

func TestFindMostFrequentAction_Single(t *testing.T) {
	res := findMostFrequentAction(map[string]int{
		"login": 1,
	})
	assert.Equal(t, "login", res)
}

func TestFindMostFrequentAction_Multiple(t *testing.T) {
	res := findMostFrequentAction(map[string]int{
		"login":  3,
		"view":   5,
		"logout": 2,
	})
	assert.Equal(t, "view", res)
}
