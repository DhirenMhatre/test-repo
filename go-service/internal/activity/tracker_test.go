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
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
}

func TestTracker_LogActivity_StoresAndReturns(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"ip": "127.0.0.1", "agent": "test"}
	log := tr.LogActivity("user1", "login", meta)
	assert.NotNil(t, log)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotEmpty(t, log.ID)
	assert.False(t, log.Timestamp.IsZero())
	assert.Equal(t, meta, log.Metadata)

	// Ensure it's stored and retrievable
	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 1)
	assert.Equal(t, "login", logs[0].Action)
	assert.Equal(t, "127.0.0.1", logs[0].Metadata["ip"])

	// Multiple logs should have distinct IDs
	_ = tr.LogActivity("user1", "view", nil)
	logs = tr.GetActivityByUser("user1")
	assert.Len(t, logs, 2)
	assert.NotEqual(t, logs[0].ID, logs[1].ID)
}

func TestTracker_LogActivity_MetadataAliasingFromInput(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"k": "v"}
	_ = tr.LogActivity("u", "a", meta)

	// Mutate original metadata map; since tracker stores it directly, change should reflect
	meta["k"] = "changed"
	logs := tr.GetActivityByUser("u")
	assert.Equal(t, "changed", logs[0].Metadata["k"])
}

func TestTracker_GetActivityByUser_CopyAndMetadataBehavior(t *testing.T) {
	tr := NewTracker()

	// Prepare deterministic activities by direct injection
	base := time.Date(2025, 1, 1, 10, 0, 0, 0, time.UTC)
	act := ActivityLog{
		ID:        "1",
		UserID:    "u",
		Action:    "action1",
		Timestamp: base,
		Metadata:  map[string]interface{}{"k": "v"},
	}
	tr.mu.Lock()
	tr.activities["u"] = []ActivityLog{act}
	tr.mu.Unlock()

	// Returned slice and struct elements should be copies (struct fields), not pointers
	got := tr.GetActivityByUser("u")
	assert.Len(t, got, 1)
	got[0].Action = "mutated"
	got2 := tr.GetActivityByUser("u")
	assert.Equal(t, "action1", got2[0].Action, "mutating returned struct should not affect internal state")

	// But Metadata map is shared (no deep copy)
	got[0].Metadata["k"] = "mutated-map"
	got3 := tr.GetActivityByUser("u")
	assert.Equal(t, "mutated-map", got3[0].Metadata["k"], "metadata map was not deep-copied")
}

func TestTracker_GetActivityStats_EmptyAndNonEmpty(t *testing.T) {
	tr := NewTracker()

	// Empty user
	stats := tr.GetActivityStats("none")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.Len(t, stats.ActionCounts, 0)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)

	// Inject deterministic activities
	base := time.Date(2025, 2, 2, 12, 0, 0, 0, time.UTC)
	acts := []ActivityLog{
		{ID: "1", UserID: "u", Action: "login", Timestamp: base.Add(5 * time.Minute)},
		{ID: "2", UserID: "u", Action: "view", Timestamp: base.Add(10 * time.Minute)},
		{ID: "3", UserID: "u", Action: "view", Timestamp: base.Add(20 * time.Minute)},
		{ID: "4", UserID: "u", Action: "logout", Timestamp: base.Add(30 * time.Minute)},
	}
	tr.mu.Lock()
	tr.activities["u"] = acts
	tr.mu.Unlock()

	stats = tr.GetActivityStats("u")
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["logout"])
	assert.Equal(t, acts[0].Timestamp, stats.FirstActivity)
	assert.Equal(t, acts[3].Timestamp, stats.LastActivity)
	assert.Equal(t, "view", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_InclusiveAndEmpty(t *testing.T) {
	tr := NewTracker()
	u := "u"
	base := time.Date(2025, 3, 3, 9, 0, 0, 0, time.UTC)
	a1 := ActivityLog{ID: "1", UserID: u, Action: "A", Timestamp: base}
	a2 := ActivityLog{ID: "2", UserID: u, Action: "B", Timestamp: base.Add(1 * time.Hour)}
	a3 := ActivityLog{ID: "3", UserID: u, Action: "C", Timestamp: base.Add(2 * time.Hour)}
	tr.mu.Lock()
	tr.activities[u] = []ActivityLog{a1, a2, a3}
	tr.mu.Unlock()

	// Entire range inclusive start and end
	found := tr.GetActivityByDateRange(u, base, base.Add(2*time.Hour))
	assert.Len(t, found, 3)

	// Narrow range inclusive at boundaries
	found = tr.GetActivityByDateRange(u, base.Add(1*time.Hour), base.Add(2*time.Hour))
	assert.Len(t, found, 2)
	ids := map[string]bool{found[0].ID: true, found[1].ID: true}
	assert.True(t, ids["2"])
	assert.True(t, ids["3"])

	// Single moment range (exact match)
	found = tr.GetActivityByDateRange(u, base.Add(1*time.Hour), base.Add(1*time.Hour))
	assert.Len(t, found, 1)
	assert.Equal(t, "2", found[0].ID)

	// Start after end -> none (condition cannot be satisfied)
	found = tr.GetActivityByDateRange(u, base.Add(3*time.Hour), base.Add(1*time.Hour))
	assert.Len(t, found, 0)

	// Unknown user
	found = tr.GetActivityByDateRange("unknown", base, base.Add(time.Hour))
	assert.Len(t, found, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	// Inject users in unsorted order
	tr.mu.Lock()
	tr.activities["charlie"] = []ActivityLog{{UserID: "charlie", Action: "x", Timestamp: time.Now()}}
	tr.activities["alice"] = []ActivityLog{{UserID: "alice", Action: "y", Timestamp: time.Now()}}
	tr.activities["bob"] = []ActivityLog{{UserID: "bob", Action: "z", Timestamp: time.Now()}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("bob", "act", nil)

	ok := tr.DeleteUserActivity("bob")
	assert.True(t, ok)

	// Deleting again should return false
	ok = tr.DeleteUserActivity("bob")
	assert.False(t, ok)

	// Ensure removed from users
	users := tr.GetAllUsers()
	for _, u := range users {
		assert.NotEqual(t, "bob", u)
	}

	// Ensure activities are gone
	logs := tr.GetActivityByUser("bob")
	assert.Len(t, logs, 0)
}

func TestGenerateID_VariesByCounter(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
}

func TestFindMostFrequentAction(t *testing.T) {
	// Empty
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// Simple
	counts := map[string]int{"a": 3, "b": 2, "c": 1}
	assert.Equal(t, "a", findMostFrequentAction(counts))
}

func TestTracker_ConcurrentLogActivity(t *testing.T) {
	tr := NewTracker()
	var wg sync.WaitGroup
	const n = 200

	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			tr.LogActivity("u", "act", map[string]interface{}{"i": i})
		}(i)
	}
	wg.Wait()

	logs := tr.GetActivityByUser("u")
	assert.Len(t, logs, n)

	// IDs should be unique due to incremental counter
	seen := make(map[string]struct{}, n)
	for _, l := range logs {
		_, exists := seen[l.ID]
		assert.False(t, exists, "duplicate ID detected")
		seen[l.ID] = struct{}{}
	}
}

func TestTracker_GetActivityByUser_UnknownUser(t *testing.T) {
	tr := NewTracker()
	logs := tr.GetActivityByUser("nope")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}
