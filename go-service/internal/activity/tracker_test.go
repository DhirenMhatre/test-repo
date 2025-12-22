package activity

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)

	users := tr.GetAllUsers()
	assert.Empty(t, users)

	byUser := tr.GetActivityByUser("nonexistent")
	assert.Empty(t, byUser)

	stats := tr.GetActivityStats("nonexistent")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestLogActivity_Basic(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"ip": "1.2.3.4"}

	log := tr.LogActivity("u1", "login", meta)
	assert.NotNil(t, log)
	assert.Equal(t, "u1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.WithinDuration(t, time.Now(), log.Timestamp, 5*time.Second)
	assert.Contains(t, log.ID, "-")

	// Stored log should be retrievable
	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 1)
	assert.Equal(t, "u1", logs[0].UserID)
	assert.Equal(t, "login", logs[0].Action)
	assert.Equal(t, meta, logs[0].Metadata)
}

func TestGetActivityByUser_CopyIsolation(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "act1", nil)

	// First retrieval and mutation
	ret1 := tr.GetActivityByUser("u1")
	assert.Len(t, ret1, 1)
	ret1[0].Action = "mutated"

	// Append to returned slice
	ret1 = append(ret1, ActivityLog{Action: "extra"})

	// Second retrieval should be unaffected
	ret2 := tr.GetActivityByUser("u1")
	assert.Len(t, ret2, 1)
	assert.Equal(t, "act1", ret2[0].Action)
}

func TestGetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("missing")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestGetActivityStats_Computed(t *testing.T) {
	tr := NewTracker()
	u := "u1"
	t1 := time.Date(2023, 10, 10, 10, 0, 0, 0, time.UTC)
	t2 := t1.Add(2 * time.Hour)
	t3 := t1.Add(1 * time.Hour)

	logs := []ActivityLog{
		{ID: "x1", UserID: u, Action: "login", Timestamp: t2},
		{ID: "x2", UserID: u, Action: "click", Timestamp: t1},
		{ID: "x3", UserID: u, Action: "login", Timestamp: t3},
	}
	tr.mu.Lock()
	tr.activities[u] = append([]ActivityLog(nil), logs...)
	tr.mu.Unlock()

	stats := tr.GetActivityStats(u)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["click"])
	assert.True(t, stats.FirstActivity.Equal(t1))
	assert.True(t, stats.LastActivity.Equal(t2))
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestGetActivityByDateRange_InclusiveBounds(t *testing.T) {
	tr := NewTracker()
	u := "u1"
	start := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	mid := start.Add(1 * time.Hour)
	end := start.Add(2 * time.Hour)

	logs := []ActivityLog{
		{ID: "s", UserID: u, Action: "start", Timestamp: start},
		{ID: "m", UserID: u, Action: "mid", Timestamp: mid},
		{ID: "e", UserID: u, Action: "end", Timestamp: end},
	}
	tr.mu.Lock()
	tr.activities[u] = append([]ActivityLog(nil), logs...)
	tr.mu.Unlock()

	// Inclusive of both start and end
	res := tr.GetActivityByDateRange(u, start, end)
	assert.Len(t, res, 3)

	// Narrow range to only mid
	res2 := tr.GetActivityByDateRange(u, mid, mid)
	assert.Len(t, res2, 1)
	assert.Equal(t, "mid", res2[0].Action)

	// Out of range
	before := start.Add(-time.Hour)
	after := end.Add(-30 * time.Minute)
	res3 := tr.GetActivityByDateRange(u, before, after)
	assert.Len(t, res3, 2) // start and mid

	// No user
	res4 := tr.GetActivityByDateRange("nouser", start, end)
	assert.Empty(t, res4)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.mu.Lock()
	tr.activities["b"] = []ActivityLog{{UserID: "b", Action: "x", Timestamp: time.Now()}}
	tr.activities["a"] = []ActivityLog{{UserID: "a", Action: "y", Timestamp: time.Now()}}
	tr.activities["c"] = []ActivityLog{{UserID: "c", Action: "z", Timestamp: time.Now()}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a", Timestamp: time.Now()},
		{ID: "2", UserID: "u1", Action: "b", Timestamp: time.Now()},
	}
	tr.activities["u2"] = []ActivityLog{
		{ID: "3", UserID: "u2", Action: "c", Timestamp: time.Now()},
	}
	tr.mu.Unlock()

	// Nonexistent user
	ok := tr.DeleteUserActivity("missing")
	assert.False(t, ok)

	// Existing user
	ok2 := tr.DeleteUserActivity("u1")
	assert.True(t, ok2)

	// Verify deletion
	rem := tr.GetActivityByUser("u1")
	assert.Empty(t, rem)

	// Other users unaffected
	rem2 := tr.GetActivityByUser("u2")
	assert.Len(t, rem2, 1)
	assert.Equal(t, "u2", rem2[0].UserID)
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login":  5,
		"click":  2,
		"logout": 3,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEqual(t, id1, id2)

	parts := strings.Split(id1, "-")
	assert.Len(t, parts, 2)
	// First part is timestamp YYYYMMDDHHMMSS (14 digits)
	assert.Len(t, parts[0], 14)
	for _, r := range parts[0] {
		assert.True(t, r >= '0' && r <= '9', "timestamp part should be digits")
	}
	// Second part exists (single rune string)
	assert.GreaterOrEqual(t, len(parts[1]), 1)
}
