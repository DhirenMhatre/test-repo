package activity

import (
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	users := tr.GetAllUsers()
	assert.Empty(t, users)
}

func TestLogActivity_StoresAndReturns(t *testing.T) {
	tr := NewTracker()
	before := time.Now()

	meta := map[string]interface{}{"ip": "127.0.0.1"}
	log1 := tr.LogActivity("u1", "login", meta)
	after := time.Now()

	assert.NotNil(t, log1)
	assert.Equal(t, "u1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.NotEmpty(t, log1.ID)
	assert.NotNil(t, log1.Metadata)
	assert.Equal(t, "127.0.0.1", log1.Metadata["ip"])
	assert.True(t, (log1.Timestamp.Equal(before) || log1.Timestamp.After(before)) && (log1.Timestamp.Equal(after) || log1.Timestamp.Before(after)))

	log2 := tr.LogActivity("u1", "click", nil)
	assert.NotNil(t, log2)
	assert.NotEmpty(t, log2.ID)
	assert.NotEqual(t, log1.ID, log2.ID)

	// Verify retrieval and copy isolation
	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 2)
	assert.Equal(t, "login", got[0].Action)
	// mutate returned slice; must not affect internal state
	got[0].Action = "mutated"
	gotAgain := tr.GetActivityByUser("u1")
	assert.Equal(t, "login", gotAgain[0].Action)
}

func TestGetActivityByUser_Nonexistent(t *testing.T) {
	tr := NewTracker()
	got := tr.GetActivityByUser("unknown")
	assert.Empty(t, got)
}

func TestGetActivityStats_EmptyAndPopulated(t *testing.T) {
	tr := NewTracker()

	// Nonexistent user
	stats := tr.GetActivityStats("nobody")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)

	// Populate with controlled timestamps by writing directly (package internal test)
	t0 := time.Now().Add(-3 * time.Minute)
	t1 := t0.Add(1 * time.Minute)
	t2 := t0.Add(2 * time.Minute)

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "a1", UserID: "u1", Action: "login", Timestamp: t0},
		{ID: "a2", UserID: "u1", Action: "click", Timestamp: t1},
		{ID: "a3", UserID: "u1", Action: "login", Timestamp: t2},
	}
	tr.mu.Unlock()

	stats = tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["click"])
	assert.Equal(t, t0, stats.FirstActivity)
	assert.Equal(t, t2, stats.LastActivity)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestGetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()

	// Prepare known times and data
	t0 := time.Now().Add(-10 * time.Minute)
	t1 := t0.Add(1 * time.Minute)
	t2 := t0.Add(2 * time.Minute)
	t3 := t0.Add(3 * time.Minute)

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "a1", UserID: "u1", Action: "A", Timestamp: t1},
		{ID: "a2", UserID: "u1", Action: "B", Timestamp: t2},
		{ID: "a3", UserID: "u1", Action: "C", Timestamp: t3},
	}
	tr.mu.Unlock()

	// Inclusive range [t1, t3]
	got := tr.GetActivityByDateRange("u1", t1, t3)
	assert.Len(t, got, 3)
	assert.Equal(t, "A", got[0].Action)
	assert.Equal(t, "C", got[2].Action)

	// Exact instant [t2, t2]
	got = tr.GetActivityByDateRange("u1", t2, t2)
	assert.Len(t, got, 1)
	assert.Equal(t, "B", got[0].Action)

	// Start after end should yield none (no swapping in implementation)
	got = tr.GetActivityByDateRange("u1", t3, t1)
	assert.Len(t, got, 0)

	// Unknown user
	got = tr.GetActivityByDateRange("unknown", t1, t3)
	assert.Empty(t, got)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("charlie", "x", nil)
	tr.LogActivity("alice", "y", nil)
	tr.LogActivity("bob", "z", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u2", "b", nil)

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	got := tr.GetActivityByUser("u1")
	assert.Empty(t, got)

	// Deleting again should return false
	ok = tr.DeleteUserActivity("u1")
	assert.False(t, ok)

	// Other user remains intact
	got = tr.GetActivityByUser("u2")
	assert.Len(t, got, 1)
	assert.Equal(t, "u2", got[0].UserID)
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))
	assert.Equal(t, "a", findMostFrequentAction(map[string]int{"a": 3, "b": 1, "c": 2}))
}

func TestGenerateID_UniqueOnCounter(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
}

func TestConcurrentAccess(t *testing.T) {
	tr := NewTracker()
	var wg sync.WaitGroup
	n := 200

	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			tr.LogActivity("u", "act", map[string]interface{}{"i": i})
		}(i)
	}
	wg.Wait()

	got := tr.GetActivityByUser("u")
	assert.Len(t, got, n)
	// Ensure copy semantics under concurrency
	if len(got) > 0 {
		got[0].Action = "mutated"
		gotAgain := tr.GetActivityByUser("u")
		assert.Equal(t, "act", gotAgain[0].Action)
	}
}
