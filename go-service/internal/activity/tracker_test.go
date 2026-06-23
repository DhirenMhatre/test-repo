package activity

import (
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)

	users := tr.GetAllUsers()
	assert.Equal(t, 0, len(users))

	// Non-existent user should return empty (non-nil) slice
	logs := tr.GetActivityByUser("nope")
	assert.NotNil(t, logs)
	assert.Equal(t, 0, len(logs))

	// Non-existent user stats should be zeroed with non-nil ActionCounts
	stats := tr.GetActivityStats("nope")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
}

func TestTracker_LogActivityAndGetByUser_CopySemantics(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1"}
	before := time.Now()
	log := tr.LogActivity("user1", "login", meta)
	after := time.Now()

	assert.NotNil(t, log)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotEmpty(t, log.ID)
	// Timestamp within [before, after]
	assert.False(t, log.Timestamp.Before(before))
	assert.False(t, log.Timestamp.After(after))

	// Ensure it was added
	got := tr.GetActivityByUser("user1")
	assert.Len(t, got, 1)
	assert.Equal(t, log.ID, got[0].ID)
	assert.Equal(t, "login", got[0].Action)

	// Modifying returned slice element should not mutate internal state (struct copy)
	got[0].Action = "tampered"
	got2 := tr.GetActivityByUser("user1")
	assert.Equal(t, "login", got2[0].Action)

	// Appending to returned slice should not affect internal state
	got = append(got, ActivityLog{ID: "fake"})
	got3 := tr.GetActivityByUser("user1")
	assert.Len(t, got3, 1)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("bob", "login", nil)
	tr.LogActivity("alice", "login", nil)
	tr.LogActivity("charlie", "click", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("bob", "login", nil)
	tr.LogActivity("bob", "click", nil)
	tr.LogActivity("alice", "login", nil)

	// Delete existing user's activity (all)
	ok := tr.DeleteUserActivity("bob")
	assert.True(t, ok)

	// bob should be gone
	bobLogs := tr.GetActivityByUser("bob")
	assert.NotNil(t, bobLogs)
	assert.Len(t, bobLogs, 0)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice"}, users)

	// Deleting non-existent user should return false
	ok = tr.DeleteUserActivity("bob")
	assert.False(t, ok)
}

func TestTracker_GetActivityStats_Populated(t *testing.T) {
	tr := NewTracker()

	// Log three activities for the same user with two actions
	tr.LogActivity("u1", "A", nil)
	tr.LogActivity("u1", "B", nil)
	tr.LogActivity("u1", "A", nil)

	// Overwrite timestamps deterministically
	base := time.Date(2023, 7, 1, 10, 0, 0, 0, time.UTC)
	times := []time.Time{
		base.Add(10 * time.Minute),
		base.Add(20 * time.Minute),
		base.Add(30 * time.Minute),
	}

	tr.mu.Lock()
	for i := range tr.activities["u1"] {
		tr.activities["u1"][i].Timestamp = times[i]
	}
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["A"])
	assert.Equal(t, 1, stats.ActionCounts["B"])
	assert.True(t, stats.FirstActivity.Equal(times[0]))
	assert.True(t, stats.LastActivity.Equal(times[2]))
	assert.Equal(t, "A", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_InclusiveAndUnknown(t *testing.T) {
	tr := NewTracker()

	// Create deterministic times
	base := time.Date(2024, 1, 2, 3, 4, 5, 0, time.UTC)
	t1 := base.Add(1 * time.Minute)
	t2 := base.Add(2 * time.Minute)
	t3 := base.Add(3 * time.Minute)
	t4 := base.Add(4 * time.Minute)

	// Log in insertion order that matches chronological order
	tr.LogActivity("u2", "a1", nil)
	tr.LogActivity("u2", "a2", nil)
	tr.LogActivity("u2", "a3", nil)
	tr.LogActivity("u2", "a4", nil)

	// Set timestamps
	tr.mu.Lock()
	for i, ts := range []time.Time{t1, t2, t3, t4} {
		tr.activities["u2"][i].Timestamp = ts
	}
	tr.mu.Unlock()

	// Range exactly t2..t3 should include second and third entries
	got := tr.GetActivityByDateRange("u2", t2, t3)
	assert.Len(t, got, 2)
	assert.Equal(t, "a2", got[0].Action)
	assert.Equal(t, "a3", got[1].Action)

	// Full range should include all
	got = tr.GetActivityByDateRange("u2", t1, t4)
	assert.Len(t, got, 4)

	// Unknown user
	none := tr.GetActivityByDateRange("unknown", t1, t4)
	assert.NotNil(t, none)
	assert.Len(t, none, 0)
}

func TestFindMostFrequentAction(t *testing.T) {
	// Empty map => ""
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// Clear winner
	counts := map[string]int{
		"A": 1,
		"B": 3,
		"C": 2,
	}
	assert.Equal(t, "B", findMostFrequentAction(counts))
}

func TestGenerateID_UniquenessWithDifferentCounters(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
}

func TestTracker_ConcurrentLogActivity(t *testing.T) {
	tr := NewTracker()

	const goroutines = 10
	const perG = 20

	var wg sync.WaitGroup
	wg.Add(goroutines)
	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < perG; j++ {
				tr.LogActivity("cu", "act", nil)
			}
		}()
	}
	wg.Wait()

	logs := tr.GetActivityByUser("cu")
	assert.Len(t, logs, goroutines*perG)

	stats := tr.GetActivityStats("cu")
	assert.Equal(t, goroutines*perG, stats.TotalActions)
	assert.Equal(t, 1, stats.UniqueActions)
	assert.Equal(t, goroutines*perG, stats.ActionCounts["act"])
	assert.Equal(t, "act", stats.MostFrequent)
}
