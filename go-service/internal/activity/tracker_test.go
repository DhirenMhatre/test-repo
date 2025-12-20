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
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
	assert.Empty(t, tr.GetAllUsers())
}

func TestTracker_LogActivity_StoresAndReturns(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"ip": "127.0.0.1"}

	log1 := tr.LogActivity("u1", "login", meta)
	assert.NotNil(t, log1)
	assert.Equal(t, "u1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.NotEmpty(t, log1.ID)
	assert.False(t, log1.Timestamp.IsZero())
	assert.Equal(t, meta, log1.Metadata)

	log2 := tr.LogActivity("u1", "view", map[string]interface{}{"page": "home"})
	assert.NotNil(t, log2)
	assert.NotEqual(t, log1.ID, log2.ID)

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 2)
	assert.Equal(t, "login", logs[0].Action)
	assert.Equal(t, meta, logs[0].Metadata)
}

func TestTracker_GetActivityByUser_EmptyAndCopyIsolation(t *testing.T) {
	tr := NewTracker()

	empty := tr.GetActivityByUser("missing")
	assert.NotNil(t, empty)
	assert.Len(t, empty, 0)

	// Add two logs
	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)

	// Get and mutate returned slice; internal state should not change
	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 2)
	orig := got[0].Action
	got[0].Action = "changed"

	got2 := tr.GetActivityByUser("u1")
	assert.Equal(t, orig, got2[0].Action)
}

func TestTracker_GetActivityStats_EmptyAndNonEmpty(t *testing.T) {
	tr := NewTracker()

	// Empty user
	statsEmpty := tr.GetActivityStats("nouser")
	assert.NotNil(t, statsEmpty)
	assert.Equal(t, 0, statsEmpty.TotalActions)
	assert.Equal(t, 0, statsEmpty.UniqueActions)
	assert.NotNil(t, statsEmpty.ActionCounts)
	assert.Empty(t, statsEmpty.MostFrequent)

	// Populate activities
	u := "alice"
	tr.LogActivity(u, "view", nil)
	tr.LogActivity(u, "login", nil)
	tr.LogActivity(u, "view", nil)
	tr.LogActivity(u, "logout", nil)

	// Override timestamps deterministically
	t0 := time.Date(2024, 1, 1, 10, 0, 0, 0, time.UTC)
	t1 := t0.Add(1 * time.Minute)
	t2 := t0.Add(2 * time.Minute)
	t3 := t0.Add(3 * time.Minute)

	tr.mu.Lock()
	tr.activities[u][0].Timestamp = t0
	tr.activities[u][1].Timestamp = t1
	tr.activities[u][2].Timestamp = t2
	tr.activities[u][3].Timestamp = t3
	tr.mu.Unlock()

	stats := tr.GetActivityStats(u)
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["logout"])
	assert.Equal(t, t0, stats.FirstActivity)
	assert.Equal(t, t3, stats.LastActivity)
	assert.Equal(t, "view", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_InclusiveAndFiltering(t *testing.T) {
	tr := NewTracker()
	u := "u"

	// Log three activities
	tr.LogActivity(u, "a", nil)
	tr.LogActivity(u, "b", nil)
	tr.LogActivity(u, "c", nil)

	// Set deterministic times
	tA := time.Date(2023, 1, 1, 10, 0, 0, 0, time.UTC)
	tB := tA.Add(1 * time.Minute)
	tC := tA.Add(2 * time.Minute)

	tr.mu.Lock()
	tr.activities[u][0].Timestamp = tA
	tr.activities[u][1].Timestamp = tB
	tr.activities[u][2].Timestamp = tC
	tr.mu.Unlock()

	// Full range
	all := tr.GetActivityByDateRange(u, tA, tC)
	assert.Len(t, all, 3)

	// Single point inclusive
	onlyB := tr.GetActivityByDateRange(u, tB, tB)
	assert.Len(t, onlyB, 1)
	assert.Equal(t, tB, onlyB[0].Timestamp)
	assert.Equal(t, "b", onlyB[0].Action)

	// No results range
	none := tr.GetActivityByDateRange(u, tA.Add(-time.Hour), tA.Add(-time.Minute))
	assert.Len(t, none, 0)

	// Missing user
	missing := tr.GetActivityByDateRange("missing", tA, tC)
	assert.Len(t, missing, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("bob", "x", nil)
	tr.LogActivity("alice", "y", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	assert.False(t, tr.DeleteUserActivity("nouser"))

	tr.LogActivity("u1", "a", nil)
	assert.True(t, tr.DeleteUserActivity("u1"))
	assert.Len(t, tr.GetActivityByUser("u1"), 0)

	assert.False(t, tr.DeleteUserActivity("u1"))
}

func Test_findMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"a": 2,
		"b": 5,
		"c": 1,
	}
	assert.Equal(t, "b", findMostFrequentAction(counts))
}

func Test_generateID_UniquenessAndFormat(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.Contains(t, id1, "-")
	assert.Contains(t, id2, "-")
}

func TestTracker_ConcurrentLogActivitySafety(t *testing.T) {
	tr := NewTracker()

	var wg sync.WaitGroup
	total := 100
	wg.Add(total)

	for i := 0; i < total; i++ {
		go func(i int) {
			defer wg.Done()
			tr.LogActivity("u", "act", map[string]interface{}{"i": i})
		}(i)
	}
	wg.Wait()

	logs := tr.GetActivityByUser("u")
	assert.Len(t, logs, total)

	// Ensure IDs are non-empty and appear unique
	seen := make(map[string]struct{})
	for _, l := range logs {
		assert.NotEmpty(t, l.ID)
		seen[l.ID] = struct{}{}
	}
	assert.Equal(t, total, len(seen))
}
