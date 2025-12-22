package activity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)

	users := tr.GetAllUsers()
	assert.Len(t, users, 0)

	logs := tr.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)

	stats := tr.GetActivityStats("unknown")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
}

func TestTracker_LogActivity_UniqueIDsAndStored(t *testing.T) {
	tr := NewTracker()

	md := map[string]interface{}{"k": "v"}
	log1 := tr.LogActivity("u1", "a1", md)
	assert.NotNil(t, log1)
	assert.Equal(t, "u1", log1.UserID)
	assert.Equal(t, "a1", log1.Action)
	assert.NotEmpty(t, log1.ID)
	assert.Equal(t, "v", log1.Metadata["k"])

	log2 := tr.LogActivity("u1", "a2", nil)
	assert.NotNil(t, log2)
	assert.NotEqual(t, log1.ID, log2.ID)

	userLogs := tr.GetActivityByUser("u1")
	assert.Len(t, userLogs, 2)
	assert.Equal(t, "a1", userLogs[0].Action)
	assert.Equal(t, "a2", userLogs[1].Action)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()

	t1 := time.Date(2025, 1, 2, 3, 4, 5, 0, time.UTC)
	t2 := t1.Add(time.Minute)

	tr.mu.Lock()
	tr.activities["u"] = []ActivityLog{
		{ID: "1", UserID: "u", Action: "a1", Timestamp: t1},
		{ID: "2", UserID: "u", Action: "a2", Timestamp: t2},
	}
	tr.mu.Unlock()

	got := tr.GetActivityByUser("u")
	assert.Len(t, got, 2)

	// Modify returned slice and element; ensure original is unaffected.
	got[0].Action = "changed"
	got = got[:0]

	got2 := tr.GetActivityByUser("u")
	assert.Len(t, got2, 2)
	assert.Equal(t, "a1", got2[0].Action)
	assert.Equal(t, "a2", got2[1].Action)
}

func TestTracker_GetActivityByUser_NonExistentUser(t *testing.T) {
	tr := NewTracker()
	out := tr.GetActivityByUser("nope")
	assert.NotNil(t, out)
	assert.Len(t, out, 0)
}

func TestTracker_GetActivityStats_WithLogs(t *testing.T) {
	tr := NewTracker()

	u := "user1"
	t1 := time.Date(2024, 10, 1, 10, 0, 0, 0, time.UTC)
	t2 := t1.Add(10 * time.Minute)
	t3 := t1.Add(20 * time.Minute)

	tr.mu.Lock()
	tr.activities[u] = []ActivityLog{
		{ID: "1", UserID: u, Action: "login", Timestamp: t1},
		{ID: "2", UserID: u, Action: "click", Timestamp: t2},
		{ID: "3", UserID: u, Action: "login", Timestamp: t3},
	}
	tr.mu.Unlock()

	stats := tr.GetActivityStats(u)
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["click"])
	assert.Equal(t, t1, stats.FirstActivity)
	assert.Equal(t, t3, stats.LastActivity)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("missing")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()

	user := "u"
	base := time.Date(2025, 1, 1, 10, 0, 0, 0, time.UTC)
	start := base
	end := base.Add(2 * time.Hour)

	// Insert in chronological order to match return order
	tr.mu.Lock()
	tr.activities[user] = []ActivityLog{
		{ID: "1", UserID: user, Action: "before", Timestamp: base.Add(-time.Hour)},
		{ID: "2", UserID: user, Action: "start", Timestamp: start},
		{ID: "3", UserID: user, Action: "middle", Timestamp: base.Add(time.Hour)},
		{ID: "4", UserID: user, Action: "end", Timestamp: end},
		{ID: "5", UserID: user, Action: "after", Timestamp: end.Add(time.Minute)},
	}
	tr.mu.Unlock()

	got := tr.GetActivityByDateRange(user, start, end)
	assert.Len(t, got, 3)
	assert.Equal(t, []string{"start", "middle", "end"}, []string{got[0].Action, got[1].Action, got[2].Action})
}

func TestTracker_GetActivityByDateRange_UnknownUser(t *testing.T) {
	tr := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now().Add(time.Hour)
	got := tr.GetActivityByDateRange("unknown", start, end)
	assert.NotNil(t, got)
	assert.Len(t, got, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["bob"] = []ActivityLog{{ID: "1", UserID: "bob", Action: "x", Timestamp: time.Now()}}
	tr.activities["alice"] = []ActivityLog{{ID: "2", UserID: "alice", Action: "y", Timestamp: time.Now()}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a", Timestamp: time.Now()},
		{ID: "2", UserID: "u1", Action: "b", Timestamp: time.Now()},
	}
	tr.mu.Unlock()

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	// Ensure removed
	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 0)

	// Second delete should return false
	ok2 := tr.DeleteUserActivity("u1")
	assert.False(t, ok2)
}

func TestGenerateID_Basic(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.Contains(t, id1, "-")
	assert.Contains(t, id2, "-")
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login":  5,
		"click":  3,
		"logout": 1,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}
