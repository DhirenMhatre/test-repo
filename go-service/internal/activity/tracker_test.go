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

func TestTracker_GetActivityByUser_NoActivities(t *testing.T) {
	tr := NewTracker()

	logs := tr.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("user1", "a1", nil)
	original := tr.GetActivityByUser("user1")
	assert.Len(t, original, 1)

	// Mutate returned slice and ensure internal state is not affected
	original[0].Action = "mutated"

	again := tr.GetActivityByUser("user1")
	assert.Equal(t, "a1", again[0].Action)
}

func TestTracker_GetActivityStats_NoUserOrEmpty(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("nouser")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_BasicAggregation(t *testing.T) {
	tr := NewTracker()

	// We control timestamps by directly writing into activities to avoid time.Now() nondeterminism
	base := time.Date(2024, 1, 2, 3, 4, 5, 0, time.UTC)
	tr.activities["user1"] = []ActivityLog{
		{
			ID:        "1",
			UserID:    "user1",
			Action:    "login",
			Timestamp: base.Add(2 * time.Hour),
		},
		{
			ID:        "2",
			UserID:    "user1",
			Action:    "click",
			Timestamp: base,
		},
		{
			ID:        "3",
			UserID:    "user1",
			Action:    "login",
			Timestamp: base.Add(4 * time.Hour),
		},
	}

	stats := tr.GetActivityStats("user1")
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["click"])
	assert.True(t, stats.FirstActivity.Equal(base))
	assert.True(t, stats.LastActivity.Equal(base.Add(4*time.Hour)))
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_NoUser(t *testing.T) {
	tr := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now().Add(time.Hour)

	logs := tr.GetActivityByDateRange("nouser", start, end)
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByDateRange_InclusiveBounds(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 1, 1, 10, 0, 0, 0, time.UTC)

	tr.activities["user1"] = []ActivityLog{
		{ID: "1", UserID: "user1", Action: "before", Timestamp: base.Add(-time.Minute)},
		{ID: "2", UserID: "user1", Action: "start", Timestamp: base},
		{ID: "3", UserID: "user1", Action: "middle", Timestamp: base.Add(30 * time.Minute)},
		{ID: "4", UserID: "user1", Action: "end", Timestamp: base.Add(time.Hour)},
		{ID: "5", UserID: "user1", Action: "after", Timestamp: base.Add(time.Hour + time.Minute)},
	}

	start := base
	end := base.Add(time.Hour)

	logs := tr.GetActivityByDateRange("user1", start, end)
	assert.Len(t, logs, 3)
	var actions []string
	for _, l := range logs {
		actions = append(actions, l.Action)
	}
	assert.ElementsMatch(t, []string{"start", "middle", "end"}, actions)
}

func TestTracker_GetAllUsers_Empty(t *testing.T) {
	tr := NewTracker()
	users := tr.GetAllUsers()
	assert.NotNil(t, users)
	assert.Len(t, users, 0)
}

func TestTracker_GetAllUsers_SortedAndUnique(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("userB", "a1", nil)
	tr.LogActivity("userA", "a2", nil)
	tr.LogActivity("userB", "a3", nil)
	tr.LogActivity("userC", "a4", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"userA", "userB", "userC"}, users)
}

func TestTracker_DeleteUserActivity_UserNotExist(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("user1", "a1", nil)

	ok := tr.DeleteUserActivity("nouser")
	assert.False(t, ok)

	// Ensure existing user still present
	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 1)
}

func TestTracker_DeleteUserActivity_UserExists(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("user1", "a1", nil)
	tr.LogActivity("user2", "b1", nil)
	tr.LogActivity("user1", "a2", nil)

	ok := tr.DeleteUserActivity("user1")
	assert.True(t, ok)

	logsUser1 := tr.GetActivityByUser("user1")
	assert.Len(t, logsUser1, 0)

	logsUser2 := tr.GetActivityByUser("user2")
	assert.Len(t, logsUser2, 1)
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	// Basic format check: should contain a dash
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
		"click":  2,
		"logout": 3,
	}
	result := findMostFrequentAction(counts)
	assert.Equal(t, "login", result)
}
