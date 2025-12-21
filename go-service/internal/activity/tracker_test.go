package activity

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestTracker_LogActivity_And_GetActivityByUser_CopyIsolation(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1", "agent": "test"}
	r1 := tr.LogActivity("u1", "login", meta)
	r2 := tr.LogActivity("u1", "click", nil)

	assert.NotNil(t, r1)
	assert.NotNil(t, r2)
	assert.NotEmpty(t, r1.ID)
	assert.NotEmpty(t, r2.ID)
	assert.Equal(t, "u1", r1.UserID)
	assert.Equal(t, "login", r1.Action)
	assert.Equal(t, "u1", r2.UserID)
	assert.Equal(t, "click", r2.Action)

	// Get activities and verify content
	got := tr.GetActivityByUser("u1")
	if assert.Len(t, got, 2) {
		assert.Equal(t, "login", got[0].Action)
		assert.Equal(t, "click", got[1].Action)
	}

	// Mutate the returned log pointer; internal state should not change
	r1.Action = "changed"
	got2 := tr.GetActivityByUser("u1")
	if assert.Len(t, got2, 2) {
		assert.Equal(t, "login", got2[0].Action)
		assert.Equal(t, "click", got2[1].Action)
	}

	// Mutate the returned slice's elements; internal state should remain unchanged
	got[0].Action = "mutated"
	got3 := tr.GetActivityByUser("u1")
	if assert.Len(t, got3, 2) {
		assert.Equal(t, "login", got3[0].Action)
	}

	// Append to the returned slice; the internal slice should be unaffected
	got = append(got, ActivityLog{UserID: "u1", Action: "extra"})
	got4 := tr.GetActivityByUser("u1")
	assert.Len(t, got4, 2)
}

func TestTracker_GetActivityByUser_UnknownUser(t *testing.T) {
	tr := NewTracker()
	got := tr.GetActivityByUser("nouser")
	assert.Len(t, got, 0)
}

func TestTracker_GetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("nouser")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.MostFrequent)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
}

func TestTracker_GetActivityStats_Computation(t *testing.T) {
	tr := NewTracker()

	t1 := time.Date(2025, 1, 1, 10, 0, 0, 0, time.UTC)
	t2 := time.Date(2025, 1, 1, 12, 0, 0, 0, time.UTC)
	t3 := time.Date(2025, 1, 2, 8, 0, 0, 0, time.UTC)

	logs := []ActivityLog{
		{ID: "a1", UserID: "u1", Action: "login", Timestamp: t2},
		{ID: "a2", UserID: "u1", Action: "click", Timestamp: t3},
		{ID: "a3", UserID: "u1", Action: "login", Timestamp: t1},
	}
	tr.mu.Lock()
	tr.activities["u1"] = logs
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	if assert.NotNil(t, stats) {
		assert.Equal(t, 3, stats.TotalActions)
		assert.Equal(t, 2, stats.UniqueActions)
		assert.Equal(t, 2, stats.ActionCounts["login"])
		assert.Equal(t, 1, stats.ActionCounts["click"])
		assert.Equal(t, t1, stats.FirstActivity)
		assert.Equal(t, t3, stats.LastActivity)
		assert.Equal(t, "login", stats.MostFrequent)
	}
}

func TestTracker_GetActivityByDateRange_FilterInclusivity(t *testing.T) {
	tr := NewTracker()

	t1 := time.Date(2025, 2, 1, 9, 0, 0, 0, time.UTC)
	t2 := time.Date(2025, 2, 1, 10, 0, 0, 0, time.UTC)
	t3 := time.Date(2025, 2, 1, 11, 0, 0, 0, time.UTC)

	logs := []ActivityLog{
		{ID: "a1", UserID: "u1", Action: "A", Timestamp: t1},
		{ID: "a2", UserID: "u1", Action: "B", Timestamp: t2},
		{ID: "a3", UserID: "u1", Action: "C", Timestamp: t3},
	}
	tr.mu.Lock()
	tr.activities["u1"] = logs
	tr.mu.Unlock()

	// Full inclusive range
	gotAll := tr.GetActivityByDateRange("u1", t1, t3)
	if assert.Len(t, gotAll, 3) {
		assert.ElementsMatch(t, []string{"A", "B", "C"}, []string{gotAll[0].Action, gotAll[1].Action, gotAll[2].Action})
	}

	// Middle inclusive range [t2, t3]
	gotMid := tr.GetActivityByDateRange("u1", t2, t3)
	if assert.Len(t, gotMid, 2) {
		actions := []string{gotMid[0].Action, gotMid[1].Action}
		assert.ElementsMatch(t, []string{"B", "C"}, actions)
	}

	// Single point inclusive [t2, t2]
	gotSingle := tr.GetActivityByDateRange("u1", t2, t2)
	if assert.Len(t, gotSingle, 1) {
		assert.Equal(t, "B", gotSingle[0].Action)
	}

	// Unknown user
	assert.Empty(t, tr.GetActivityByDateRange("nouser", t1, t3))
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["bob"] = []ActivityLog{{ID: "b1", UserID: "bob", Action: "X", Timestamp: time.Now()}}
	tr.activities["alice"] = []ActivityLog{{ID: "a1", UserID: "alice", Action: "Y", Timestamp: time.Now()}}
	tr.activities["charlie"] = []ActivityLog{{ID: "c1", UserID: "charlie", Action: "Z", Timestamp: time.Now()}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["alice"] = []ActivityLog{{ID: "a1", UserID: "alice", Action: "A", Timestamp: time.Now()}}
	tr.activities["bob"] = []ActivityLog{{ID: "b1", UserID: "bob", Action: "B", Timestamp: time.Now()}}
	tr.mu.Unlock()

	// Non-existent user
	assert.False(t, tr.DeleteUserActivity("charlie"))

	// Delete existing
	assert.True(t, tr.DeleteUserActivity("alice"))
	assert.Empty(t, tr.GetActivityByUser("alice"))

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"bob"}, users)

	// Second delete should return false
	assert.False(t, tr.DeleteUserActivity("alice"))
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.True(t, strings.Contains(id1, "-"))
	assert.True(t, strings.Contains(id2, "-"))
	assert.True(t, strings.HasSuffix(id1, "-"+string(rune(1))))
	assert.True(t, strings.HasSuffix(id2, "-"+string(rune(2))))
}

func TestFindMostFrequentAction(t *testing.T) {
	// Regular case
	counts := map[string]int{
		"login":  5,
		"click":  2,
		"logout": 3,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))

	// Empty map
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))
}

func TestTracker_GetActivityByDateRange_StartAfterEnd_ReturnsEmpty(t *testing.T) {
	tr := NewTracker()
	now := time.Now()
	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "x", UserID: "u1", Action: "act", Timestamp: now},
	}
	tr.mu.Unlock()

	start := now.Add(2 * time.Hour)
	end := now.Add(1 * time.Hour)
	got := tr.GetActivityByDateRange("u1", start, end)
	assert.Empty(t, got)
}

func TestTracker_ConcurrentLogActivity_Count(t *testing.T) {
	tr := NewTracker()

	const n = 50
	done := make(chan struct{})
	for i := 0; i < n; i++ {
		go func(idx int) {
			tr.LogActivity("u1", "act", map[string]interface{}{"i": idx})
			done <- struct{}{}
		}(i)
	}
	for i := 0; i < n; i++ {
		<-done
	}

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, n)
}
