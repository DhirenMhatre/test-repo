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
	assert.Equal(t, 0, len(tr.GetAllUsers()))
}

func TestLogActivity_StoresAndIDUnique(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1"}
	l1 := tr.LogActivity("user1", "login", meta)
	l2 := tr.LogActivity("user1", "view", meta)

	assert.NotNil(t, l1)
	assert.NotNil(t, l2)
	assert.NotEqual(t, l1.ID, l2.ID)
	assert.Equal(t, "user1", l1.UserID)
	assert.Equal(t, "login", l1.Action)
	assert.False(t, l1.Timestamp.IsZero())
	assert.Equal(t, meta, l1.Metadata)

	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 2)
}

func TestGetActivityByUser_EmptyAndIsolation(t *testing.T) {
	tr := NewTracker()

	// Non-existent user returns empty slice
	logs := tr.GetActivityByUser("nouser")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)

	// Isolation: returned slice is a copy
	tr.LogActivity("u", "a1", nil)
	got1 := tr.GetActivityByUser("u")
	assert.Len(t, got1, 1)
	origAction := got1[0].Action
	got1[0].Action = "changed"

	got2 := tr.GetActivityByUser("u")
	assert.Equal(t, origAction, got2[0].Action)
}

func TestGetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("nouser")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, "", stats.MostFrequent)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
}

func TestGetActivityStats_WithLogs(t *testing.T) {
	tr := NewTracker()
	// Prepare controlled timestamps
	t1 := time.Date(2023, 1, 2, 12, 0, 0, 0, time.UTC)
	t2 := time.Date(2023, 1, 2, 13, 0, 0, 0, time.UTC)
	t3 := time.Date(2023, 1, 2, 14, 0, 0, 0, time.UTC)

	tr.mu.Lock()
	tr.activities["alice"] = []ActivityLog{
		{ID: "1", UserID: "alice", Action: "login", Timestamp: t2},
		{ID: "2", UserID: "alice", Action: "view", Timestamp: t3},
		{ID: "3", UserID: "alice", Action: "login", Timestamp: t1},
	}
	tr.mu.Unlock()

	stats := tr.GetActivityStats("alice")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.Equal(t, t1, stats.FirstActivity)
	assert.Equal(t, t3, stats.LastActivity)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestGetActivityByDateRange_InclusiveAndEmpty(t *testing.T) {
	tr := NewTracker()
	// Fixed timestamps
	t1 := time.Date(2024, 2, 1, 10, 0, 0, 0, time.UTC)
	t2 := time.Date(2024, 2, 1, 11, 0, 0, 0, time.UTC)
	t3 := time.Date(2024, 2, 1, 12, 0, 0, 0, time.UTC)

	tr.mu.Lock()
	tr.activities["bob"] = []ActivityLog{
		{ID: "1", UserID: "bob", Action: "a", Timestamp: t1},
		{ID: "2", UserID: "bob", Action: "b", Timestamp: t2},
		{ID: "3", UserID: "bob", Action: "c", Timestamp: t3},
	}
	tr.mu.Unlock()

	// Inclusive range that selects middle only
	midOnly := tr.GetActivityByDateRange("bob", t2, t2)
	assert.Len(t, midOnly, 1)
	assert.Equal(t, "b", midOnly[0].Action)

	// Inclusive range selecting all
	all := tr.GetActivityByDateRange("bob", t1, t3)
	assert.Len(t, all, 3)

	// Range outside returns empty
	empty := tr.GetActivityByDateRange("bob", t3.Add(time.Second), t3.Add(2*time.Second))
	assert.Len(t, empty, 0)

	// Non-existent user
	none := tr.GetActivityByDateRange("nouser", t1, t3)
	assert.Len(t, none, 0)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["zeta"] = []ActivityLog{{UserID: "zeta", Action: "x", Timestamp: time.Now()}}
	tr.activities["alpha"] = []ActivityLog{{UserID: "alpha", Action: "y", Timestamp: time.Now()}}
	tr.activities["beta"] = []ActivityLog{{UserID: "beta", Action: "z", Timestamp: time.Now()}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alpha", "beta", "zeta"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	// Deleting non-existent user returns false
	ok := tr.DeleteUserActivity("nouser")
	assert.False(t, ok)

	// Add activities and delete
	tr.LogActivity("carol", "login", nil)
	tr.LogActivity("carol", "view", nil)

	gotBefore := tr.GetActivityByUser("carol")
	assert.Len(t, gotBefore, 2)

	ok = tr.DeleteUserActivity("carol")
	assert.True(t, ok)

	gotAfter := tr.GetActivityByUser("carol")
	assert.Len(t, gotAfter, 0)

	// Subsequent delete returns false
	ok = tr.DeleteUserActivity("carol")
	assert.False(t, ok)
}

func TestGenerateID_SuffixAndLength(t *testing.T) {
	// Use a printable rune to make assertions deterministic
	id := generateID(65) // 'A'
	assert.True(t, strings.HasSuffix(id, "-A"))
	assert.GreaterOrEqual(t, len(id), 16)
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login":  3,
		"view":   2,
		"logout": 1,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}

func TestConcurrentAccess_LogAndGet(t *testing.T) {
	tr := NewTracker()
	var wg sync.WaitGroup
	user := "u"

	n := 100
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			tr.LogActivity(user, "act", nil)
		}(i)
	}
	wg.Wait()

	// Concurrent reads
	var readWg sync.WaitGroup
	readers := 10
	readWg.Add(readers)
	for i := 0; i < readers; i++ {
		go func() {
			defer readWg.Done()
			_ = tr.GetActivityByUser(user)
			_ = tr.GetActivityStats(user)
			_ = tr.GetActivityByDateRange(user, time.Now().Add(-time.Hour), time.Now().Add(time.Hour))
			_ = tr.GetAllUsers()
		}()
	}
	readWg.Wait()

	logs := tr.GetActivityByUser(user)
	assert.Len(t, logs, n)
}
