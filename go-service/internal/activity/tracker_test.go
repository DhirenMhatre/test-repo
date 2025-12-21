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
	assert.Equal(t, 0, len(users))

	logs := tr.GetActivityByUser("nonexistent")
	assert.NotNil(t, logs)
	assert.Equal(t, 0, len(logs))
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()

	md := map[string]interface{}{"ip": "1.2.3.4"}
	before := time.Now()
	l1 := tr.LogActivity("user1", "login", md)
	after := time.Now()

	assert.NotNil(t, l1)
	assert.Equal(t, "user1", l1.UserID)
	assert.Equal(t, "login", l1.Action)
	assert.Equal(t, md, l1.Metadata)
	assert.NotEmpty(t, l1.ID)
	assert.False(t, l1.Timestamp.Before(before))
	assert.False(t, l1.Timestamp.After(after))

	l2 := tr.LogActivity("user1", "view", nil)
	assert.NotNil(t, l2)
	assert.NotEqual(t, l1.ID, l2.ID)

	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 2)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u2", "action1", nil)
	got := tr.GetActivityByUser("u2")
	assert.Len(t, got, 1)

	// Mutate returned slice; internal storage should not be affected
	got[0].Action = "mutated"
	got2 := tr.GetActivityByUser("u2")
	assert.Equal(t, "action1", got2[0].Action)

	// Appending to returned slice should not change internal storage
	got = append(got, ActivityLog{Action: "extra"})
	got3 := tr.GetActivityByUser("u2")
	assert.Len(t, got3, 1)
}

func TestTracker_GetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("no-user")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_Populated(t *testing.T) {
	tr := NewTracker()
	u := "statsUser"

	ts0 := time.Date(2023, 12, 31, 23, 59, 0, 0, time.UTC)
	ts1 := time.Date(2024, 1, 1, 10, 0, 0, 0, time.UTC)
	ts2 := time.Date(2024, 1, 1, 12, 0, 0, 0, time.UTC)
	ts3 := time.Date(2024, 1, 2, 9, 0, 0, 0, time.UTC)
	tsLast := time.Date(2024, 1, 3, 15, 0, 0, 0, time.UTC)

	tr.activities[u] = []ActivityLog{
		{UserID: u, Action: "purchase", Timestamp: ts2},
		{UserID: u, Action: "view", Timestamp: ts3},
		{UserID: u, Action: "login", Timestamp: ts0},
		{UserID: u, Action: "view", Timestamp: ts1},
		{UserID: u, Action: "view", Timestamp: tsLast},
		{UserID: u, Action: "purchase", Timestamp: ts2.Add(time.Minute)},
	}

	stats := tr.GetActivityStats(u)
	assert.Equal(t, 6, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)

	assert.Equal(t, 3, stats.ActionCounts["view"])
	assert.Equal(t, 2, stats.ActionCounts["purchase"])
	assert.Equal(t, 1, stats.ActionCounts["login"])

	assert.Equal(t, ts0, stats.FirstActivity)
	assert.Equal(t, tsLast, stats.LastActivity)
	assert.Equal(t, "view", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange(t *testing.T) {
	tr := NewTracker()
	u := "rangeUser"
	ts1 := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	ts2 := time.Date(2024, 1, 2, 0, 0, 0, 0, time.UTC)
	ts3 := time.Date(2024, 1, 3, 0, 0, 0, 0, time.UTC)

	tr.activities[u] = []ActivityLog{
		{UserID: u, Action: "a", Timestamp: ts1},
		{UserID: u, Action: "b", Timestamp: ts2},
		{UserID: u, Action: "c", Timestamp: ts3},
	}

	// Inclusive boundaries
	got := tr.GetActivityByDateRange(u, ts2, ts3)
	assert.Len(t, got, 2)
	acts := map[string]bool{got[0].Action: true, got[1].Action: true}
	assert.True(t, acts["b"])
	assert.True(t, acts["c"])

	// Single point inclusive
	got = tr.GetActivityByDateRange(u, ts1, ts1)
	assert.Len(t, got, 1)
	assert.Equal(t, "a", got[0].Action)

	// Out of range - start after all
	got = tr.GetActivityByDateRange(u, ts3.Add(time.Hour), ts3.Add(2*time.Hour))
	assert.Len(t, got, 0)

	// Nonexistent user
	got = tr.GetActivityByDateRange("no-user", ts1, ts3)
	assert.Len(t, got, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.activities["c"] = []ActivityLog{{UserID: "c", Action: "x", Timestamp: time.Now()}}
	tr.activities["a"] = []ActivityLog{{UserID: "a", Action: "x", Timestamp: time.Now()}}
	tr.activities["b"] = []ActivityLog{{UserID: "b", Action: "x", Timestamp: time.Now()}}

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.activities["alice"] = []ActivityLog{{UserID: "alice", Action: "x", Timestamp: time.Now()}}
	tr.activities["bob"] = []ActivityLog{{UserID: "bob", Action: "y", Timestamp: time.Now()}, {UserID: "bob", Action: "z", Timestamp: time.Now()}}

	// Delete existing
	ok := tr.DeleteUserActivity("bob")
	assert.True(t, ok)
	assert.Len(t, tr.GetActivityByUser("bob"), 0)
	assert.Equal(t, []string{"alice"}, tr.GetAllUsers())

	// Delete non-existing
	ok = tr.DeleteUserActivity("charlie")
	assert.False(t, ok)
}

func TestGenerateID_Format(t *testing.T) {
	id := generateID(65) // 'A'
	assert.True(t, strings.HasSuffix(id, "-A"))
	assert.Equal(t, 16, len(id)) // "YYYYMMDDhhmmss" (14) + "-" + "A"
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"view":    5,
		"login":   2,
		"logout":  1,
		"comment": 3,
	}
	assert.Equal(t, "view", findMostFrequentAction(counts))
}
