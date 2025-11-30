package activity

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_Init(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
	assert.Empty(t, tr.GetAllUsers())
}

func TestLogActivity_Basic(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"ip": "127.0.0.1"}
	log := tr.LogActivity("user1", "login", meta)

	assert.NotNil(t, log)
	assert.NotEmpty(t, log.ID)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.Equal(t, "127.0.0.1", log.Metadata["ip"])

	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 1)
	assert.Equal(t, "login", logs[0].Action)

	log2 := tr.LogActivity("user1", "view", nil)
	assert.NotEqual(t, log.ID, log2.ID)
	logs = tr.GetActivityByUser("user1")
	assert.Len(t, logs, 2)
	assert.Equal(t, "login", logs[0].Action)
	assert.Equal(t, "view", logs[1].Action)
}

func TestGetActivityByUser_EmptyAndCopyIsolation(t *testing.T) {
	tr := NewTracker()

	// Empty case returns empty slice
	logs := tr.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)

	// Copy isolation
	tr.LogActivity("userA", "a1", nil)
	tr.LogActivity("userA", "a2", nil)

	got := tr.GetActivityByUser("userA")
	assert.Len(t, got, 2)
	// mutate returned slice and element; original should remain intact
	got = append(got, ActivityLog{Action: "new"})
	got[0].Action = "mutated"

	got2 := tr.GetActivityByUser("userA")
	assert.Len(t, got2, 2)
	assert.Equal(t, "a1", got2[0].Action)
	assert.Equal(t, "a2", got2[1].Action)
}

func TestGetActivityStats_NoLogs(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("nouser")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestGetActivityStats_WithLogs(t *testing.T) {
	tr := NewTracker()

	// Prepare controlled logs with known timestamps
	user := "user1"
	t0 := time.Date(2025, 1, 2, 10, 0, 0, 0, time.UTC)
	t1 := t0.Add(5 * time.Minute)
	t2 := t0.Add(10 * time.Minute)

	logs := []ActivityLog{
		{ID: "1", UserID: user, Action: "A", Timestamp: t0},
		{ID: "2", UserID: user, Action: "B", Timestamp: t1},
		{ID: "3", UserID: user, Action: "A", Timestamp: t2},
	}

	tr.mu.Lock()
	tr.activities[user] = logs
	tr.mu.Unlock()

	stats := tr.GetActivityStats(user)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["A"])
	assert.Equal(t, 1, stats.ActionCounts["B"])
	assert.Equal(t, t0, stats.FirstActivity)
	assert.Equal(t, t2, stats.LastActivity)
	assert.Equal(t, "A", stats.MostFrequent)
}

func TestGetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()
	user := "userX"
	t0 := time.Date(2025, 1, 2, 10, 0, 0, 0, time.UTC)
	t1 := t0.Add(5 * time.Minute)
	t2 := t0.Add(10 * time.Minute)

	tr.mu.Lock()
	tr.activities[user] = []ActivityLog{
		{ID: "1", UserID: user, Action: "a", Timestamp: t0},
		{ID: "2", UserID: user, Action: "b", Timestamp: t1},
		{ID: "3", UserID: user, Action: "c", Timestamp: t2},
	}
	tr.mu.Unlock()

	// exact boundaries inclusive: should include t1 and t2
	filtered := tr.GetActivityByDateRange(user, t1, t2)
	assert.Len(t, filtered, 2)
	assert.Equal(t, "b", filtered[0].Action)
	assert.Equal(t, "c", filtered[1].Action)

	// range that excludes all
	none := tr.GetActivityByDateRange(user, t2.Add(time.Second), t2.Add(2*time.Second))
	assert.Len(t, none, 0)

	// non-existent user
	empty := tr.GetActivityByDateRange("nope", t0, t2)
	assert.Len(t, empty, 0)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["charlie"] = []ActivityLog{{UserID: "charlie"}}
	tr.activities["alice"] = []ActivityLog{{UserID: "alice"}}
	tr.activities["bob"] = []ActivityLog{{UserID: "bob"}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{{UserID: "u1", Action: "a"}}
	tr.activities["u2"] = []ActivityLog{{UserID: "u2", Action: "b"}}
	tr.mu.Unlock()

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	// user u1 removed
	assert.Empty(t, tr.GetActivityByUser("u1"))
	// user u2 remains
	assert.Len(t, tr.GetActivityByUser("u2"), 1)

	// deleting again returns false
	assert.False(t, tr.DeleteUserActivity("u1"))
	// deleting non-existent returns false
	assert.False(t, tr.DeleteUserActivity("nope"))
}

func TestFindMostFrequentAction(t *testing.T) {
	// empty
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// non-tie
	counts := map[string]int{
		"login":  3,
		"view":   1,
		"click":  2,
		"logout": 1,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	// Should contain a dash and end with the rune of the counter
	assert.Contains(t, id1, "-")
	assert.True(t, strings.HasSuffix(id1, "-"+string(rune(1))))
	assert.True(t, strings.HasSuffix(id2, "-"+string(rune(2))))
}

func TestGetActivityByUser_AfterLogActivity_WithDateRangeIntegration(t *testing.T) {
	tr := NewTracker()
	start := time.Now().Add(-1 * time.Hour)
	end := time.Now().Add(1 * time.Hour)

	tr.LogActivity("u", "a1", nil)
	tr.LogActivity("u", "a2", nil)

	// Both should fall inside [start, end]
	filtered := tr.GetActivityByDateRange("u", start, end)
	all := tr.GetActivityByUser("u")

	assert.Len(t, all, 2)
	assert.Len(t, filtered, 2)
}
