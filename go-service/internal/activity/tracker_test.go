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
	assert.Equal(t, 0, len(tr.activities))
	assert.Equal(t, 0, tr.idCounter)

	users := tr.GetAllUsers()
	assert.Equal(t, 0, len(users))
}

func TestTracker_LogActivity_StoresAndIncrementsCounter(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1"}
	log := tr.LogActivity("user1", "login", meta)

	assert.NotNil(t, log)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotEmpty(t, log.ID)
	assert.False(t, log.Timestamp.IsZero())
	assert.Equal(t, meta, log.Metadata)
	assert.Equal(t, 1, tr.idCounter)

	// Ensure it was stored
	tr.mu.RLock()
	acts := tr.activities["user1"]
	tr.mu.RUnlock()
	assert.Equal(t, 1, len(acts))
	assert.Equal(t, "user1", acts[0].UserID)
	assert.Equal(t, "login", acts[0].Action)

	// Log another one and ensure counter increments and appends
	tr.LogActivity("user1", "logout", nil)
	assert.Equal(t, 2, tr.idCounter)

	tr.mu.RLock()
	acts = tr.activities["user1"]
	tr.mu.RUnlock()
	assert.Equal(t, 2, len(acts))
	assert.Equal(t, "logout", acts[1].Action)
}

func TestTracker_GetActivityByUser_CopyIsolation(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 1, 2, 3, 4, 5, 0, time.UTC)

	// Set up deterministic data directly
	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "a1", UserID: "u1", Action: "read", Timestamp: base},
		{ID: "a2", UserID: "u1", Action: "write", Timestamp: base.Add(time.Minute)},
	}
	tr.mu.Unlock()

	got := tr.GetActivityByUser("u1")
	assert.Equal(t, 2, len(got))
	assert.Equal(t, "a1", got[0].ID)
	assert.Equal(t, "a2", got[1].ID)

	// Mutate returned slice and ensure internal state is not changed
	got[0].Action = "mutated"
	gotAgain := tr.GetActivityByUser("u1")
	assert.Equal(t, "read", gotAgain[0].Action)
}

func TestTracker_GetActivityByUser_NonExistent(t *testing.T) {
	tr := NewTracker()
	got := tr.GetActivityByUser("unknown")
	assert.NotNil(t, got)
	assert.Equal(t, 0, len(got))
}

func TestTracker_GetActivityStats_ComputesCorrectly(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 5, 10, 12, 0, 0, 0, time.UTC)

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "a1", UserID: "u1", Action: "login", Timestamp: base.Add(1 * time.Minute)},
		{ID: "a2", UserID: "u1", Action: "play", Timestamp: base.Add(2 * time.Minute)},
		{ID: "a3", UserID: "u1", Action: "play", Timestamp: base.Add(3 * time.Minute)},
		{ID: "a4", UserID: "u1", Action: "logout", Timestamp: base.Add(5 * time.Minute)},
	}
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.NotNil(t, stats)
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, 2, stats.ActionCounts["play"])
	assert.Equal(t, 1, stats.ActionCounts["logout"])
	assert.Equal(t, base.Add(1*time.Minute), stats.FirstActivity)
	assert.Equal(t, base.Add(5*time.Minute), stats.LastActivity)
	assert.Equal(t, "play", stats.MostFrequent)
}

func TestTracker_GetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("nope")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 7, 1, 10, 0, 0, 0, time.UTC)

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "a1", UserID: "u1", Action: "A", Timestamp: base},                       // start
		{ID: "a2", UserID: "u1", Action: "B", Timestamp: base.Add(30 * time.Minute)}, // mid
		{ID: "a3", UserID: "u1", Action: "C", Timestamp: base.Add(1 * time.Hour)},    // end
		{ID: "a4", UserID: "u1", Action: "D", Timestamp: base.Add(2 * time.Hour)},    // outside
	}
	tr.mu.Unlock()

	// Range includes start and end
	got := tr.GetActivityByDateRange("u1", base, base.Add(1*time.Hour))
	assert.Equal(t, 3, len(got))
	assert.Equal(t, "a1", got[0].ID)
	assert.Equal(t, "a2", got[1].ID)
	assert.Equal(t, "a3", got[2].ID)

	// Tight range only mid
	got2 := tr.GetActivityByDateRange("u1", base.Add(20*time.Minute), base.Add(40*time.Minute))
	assert.Equal(t, 1, len(got2))
	assert.Equal(t, "a2", got2[0].ID)
}

func TestTracker_GetActivityByDateRange_NoUser(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 7, 1, 10, 0, 0, 0, time.UTC)

	got := tr.GetActivityByDateRange("unknown", base, base.Add(time.Hour))
	assert.NotNil(t, got)
	assert.Equal(t, 0, len(got))
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["userC"] = []ActivityLog{{ID: "c", UserID: "userC"}}
	tr.activities["userA"] = []ActivityLog{{ID: "a", UserID: "userA"}}
	tr.activities["userB"] = []ActivityLog{{ID: "b", UserID: "userB"}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"userA", "userB", "userC"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "a1", UserID: "u1", Action: "A"},
		{ID: "a2", UserID: "u1", Action: "B"},
	}
	tr.mu.Unlock()

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok, "expected delete to succeed")

	// Verify user removed
	users := tr.GetAllUsers()
	assert.NotContains(t, users, "u1")

	// Deleting again should return false
	ok2 := tr.DeleteUserActivity("u1")
	assert.False(t, ok2, "expected delete to fail for non-existent user")
}

func Test_findMostFrequentAction(t *testing.T) {
	// Empty map
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// Single most frequent
	counts := map[string]int{
		"login":   1,
		"play":    5,
		"logout":  2,
		"comment": 3,
	}
	assert.Equal(t, "play", findMostFrequentAction(counts))
}
