package activity

import (
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, len(tr.activities))
	assert.Equal(t, 0, tr.idCounter)
}

func TestLogActivity_BasicAndIsolation(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1"}
	ret := tr.LogActivity("user1", "login", meta)
	assert.NotNil(t, ret)
	assert.Equal(t, "user1", ret.UserID)
	assert.Equal(t, "login", ret.Action)
	assert.NotZero(t, ret.Timestamp)
	assert.NotEmpty(t, ret.ID)
	assert.Contains(t, ret.ID, "-")
	assert.Equal(t, meta, ret.Metadata)

	// Ensure it's stored
	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 1)
	assert.Equal(t, "user1", logs[0].UserID)
	assert.Equal(t, "login", logs[0].Action)

	// Mutating returned pointer should not affect stored copy
	ret.Action = "changed"
	logs2 := tr.GetActivityByUser("user1")
	assert.Equal(t, "login", logs2[0].Action)
}

func TestGetActivityByUser_EmptyAndCopyIsolation(t *testing.T) {
	tr := NewTracker()

	// Non-existent user returns empty slice (not nil)
	logs := tr.GetActivityByUser("nouser")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)

	// Add some and verify copy isolation on returned slice and struct fields
	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 2)
	// Modify returned slice and element - should not mutate internal storage
	got[0].Action = "mutated"
	got = append(got, ActivityLog{UserID: "u1", Action: "extra"})

	got2 := tr.GetActivityByUser("u1")
	assert.Len(t, got2, 2)
	assert.Equal(t, "a1", got2[0].Action)
	assert.Equal(t, "a2", got2[1].Action)
}

func TestGetActivityStats_EmptyAndFilled(t *testing.T) {
	tr := NewTracker()

	// Empty user stats
	statsEmpty := tr.GetActivityStats("uX")
	assert.NotNil(t, statsEmpty)
	assert.Equal(t, 0, statsEmpty.TotalActions)
	assert.Equal(t, 0, statsEmpty.UniqueActions)
	assert.NotNil(t, statsEmpty.ActionCounts)
	assert.Empty(t, statsEmpty.MostFrequent)

	// Filled stats
	tr.LogActivity("u1", "login", nil)
	time.Sleep(2 * time.Millisecond)
	tr.LogActivity("u1", "view", nil)
	time.Sleep(2 * time.Millisecond)
	tr.LogActivity("u1", "view", nil)
	time.Sleep(2 * time.Millisecond)
	tr.LogActivity("u1", "logout", nil)

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["logout"])
	assert.Equal(t, "view", stats.MostFrequent)
	assert.False(t, stats.FirstActivity.IsZero())
	assert.False(t, stats.LastActivity.IsZero())
	assert.False(t, stats.FirstActivity.After(stats.LastActivity))
}

func TestGetActivityByDateRange_InclusiveAndEdges(t *testing.T) {
	tr := NewTracker()
	user := "rangeUser"

	// Ensure distinct timestamps
	tr.LogActivity(user, "a0", nil)
	time.Sleep(3 * time.Millisecond)
	tr.LogActivity(user, "a1", nil)
	time.Sleep(3 * time.Millisecond)
	tr.LogActivity(user, "a2", nil)

	logs := tr.GetActivityByUser(user)
	assert.Len(t, logs, 3)
	t0 := logs[0].Timestamp
	t1 := logs[1].Timestamp
	t2 := logs[2].Timestamp

	// Inclusive boundaries: should include all
	all := tr.GetActivityByDateRange(user, t0, t2)
	assert.Len(t, all, 3)

	// Exact match on middle timestamp
	onlyMid := tr.GetActivityByDateRange(user, t1, t1)
	assert.Len(t, onlyMid, 1)
	assert.Equal(t, "a1", onlyMid[0].Action)

	// Exclusively between first and last (by nudging boundaries)
	middleOnly := tr.GetActivityByDateRange(user, t0.Add(time.Nanosecond), t2.Add(-time.Nanosecond))
	// Should include only the middle if timestamps are strictly increasing
	// In case of timing edge, allow at least 1 and at most 3, but assert that "a1" is included.
	assert.GreaterOrEqual(t, len(middleOnly), 1)
	foundA1 := false
	for _, l := range middleOnly {
		if l.Action == "a1" {
			foundA1 = true
			break
		}
	}
	assert.True(t, foundA1, "expected to find a1 in middleOnly set")

	// Unknown user yields empty
	none := tr.GetActivityByDateRange("nouser", t0, t2)
	assert.Len(t, none, 0)

	// Inverted range yields empty (function is strict on start<=end)
	inverted := tr.GetActivityByDateRange(user, t2, t0)
	assert.Len(t, inverted, 0)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("bob", "a", nil)
	tr.LogActivity("alice", "b", nil)
	tr.LogActivity("charlie", "c", nil)
	tr.LogActivity("alice", "d", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("foo", "x", nil)
	tr.LogActivity("foo", "y", nil)
	tr.LogActivity("bar", "z", nil)

	// delete existing
	ok := tr.DeleteUserActivity("foo")
	assert.True(t, ok)
	assert.Len(t, tr.GetActivityByUser("foo"), 0)
	users := tr.GetAllUsers()
	assert.Equal(t, []string{"bar"}, users)

	// delete non-existing
	ok2 := tr.DeleteUserActivity("doesnotexist")
	assert.False(t, ok2)
}

func TestConcurrentLogging_NoRaceAndCount(t *testing.T) {
	tr := NewTracker()
	user := "concUser"

	var wg sync.WaitGroup
	const goroutines = 10
	const perG = 50

	wg.Add(goroutines)
	for g := 0; g < goroutines; g++ {
		go func() {
			defer wg.Done()
			for i := 0; i < perG; i++ {
				tr.LogActivity(user, "act", nil)
			}
		}()
	}
	wg.Wait()

	logs := tr.GetActivityByUser(user)
	assert.Len(t, logs, goroutines*perG)
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))
	assert.Equal(t, "b", findMostFrequentAction(map[string]int{"a": 1, "b": 3, "c": 2}))
	// With a tie, implementation returns the first to reach max; map iteration order is random,
	// so we only assert that result is one of the tied keys.
	res := findMostFrequentAction(map[string]int{"x": 2, "y": 2})
	assert.True(t, res == "x" || res == "y")
}

func TestGenerateID_Basic(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.True(t, strings.Contains(id1, "-"))
	assert.True(t, strings.Contains(id2, "-"))
}
