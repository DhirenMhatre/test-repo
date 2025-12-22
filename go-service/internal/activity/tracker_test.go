package activity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func mustTime(t *testing.T, s string) time.Time {
	t.Helper()
	ts, err := time.Parse(time.RFC3339, s)
	if err != nil {
		t.Fatalf("invalid time %q: %v", s, err)
	}
	return ts
}

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
	assert.Equal(t, 0, len(tr.activities))
}

func TestTracker_LogActivity(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"ip": "1.2.3.4", "ok": true}

	before := time.Now()
	log := tr.LogActivity("u1", "login", meta)
	after := time.Now()

	assert.NotNil(t, log)
	assert.Equal(t, "u1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotEmpty(t, log.ID)
	assert.WithinDuration(t, before, log.Timestamp, after.Sub(before)+2*time.Second)
	assert.Equal(t, meta, log.Metadata)

	// ensure stored
	stored := tr.GetActivityByUser("u1")
	assert.Len(t, stored, 1)
	assert.Equal(t, log.ID, stored[0].ID)

	// ID uniqueness on subsequent call
	log2 := tr.LogActivity("u1", "click", nil)
	assert.NotEqual(t, log.ID, log2.ID)
}

func TestTracker_GetActivityByUser_CopyIsolation(t *testing.T) {
	tr := NewTracker()
	l := tr.LogActivity("u1", "view", nil)

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 1)
	assert.Equal(t, l.Action, got[0].Action)

	// mutate returned slice element; internal store should be unchanged
	got[0].Action = "mutated"
	got2 := tr.GetActivityByUser("u1")
	assert.Equal(t, l.Action, got2[0].Action)
}

func TestTracker_GetActivityByUser_Nonexistent(t *testing.T) {
	tr := NewTracker()
	got := tr.GetActivityByUser("nope")
	assert.NotNil(t, got)
	assert.Len(t, got, 0)
}

func TestTracker_GetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("no_user")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_Populated(t *testing.T) {
	tr := NewTracker()

	t1 := mustTime(t, "2025-01-01T10:00:00Z")
	t2 := mustTime(t, "2025-01-01T11:00:00Z")
	t3 := mustTime(t, "2025-01-01T12:00:00Z")

	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "login", Timestamp: t1},
		{ID: "2", UserID: "u1", Action: "play", Timestamp: t2},
		{ID: "3", UserID: "u1", Action: "play", Timestamp: t3},
	}

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["play"])
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, t1, stats.FirstActivity)
	assert.Equal(t, t3, stats.LastActivity)
	assert.Equal(t, "play", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_InclusiveAndExclusive(t *testing.T) {
	tr := NewTracker()

	// inject deterministic logs
	u := "u1"
	ts0 := mustTime(t, "2025-01-01T00:00:00Z")
	ts1 := mustTime(t, "2025-01-01T12:00:00Z")
	ts2 := mustTime(t, "2025-01-01T23:59:59Z")
	before := mustTime(t, "2024-12-31T23:00:00Z")
	after := mustTime(t, "2025-01-02T00:00:00Z")

	tr.activities[u] = []ActivityLog{
		{ID: "a", UserID: u, Action: "x", Timestamp: before}, // out of range
		{ID: "b", UserID: u, Action: "x", Timestamp: ts0},
		{ID: "c", UserID: u, Action: "x", Timestamp: ts1},
		{ID: "d", UserID: u, Action: "x", Timestamp: ts2},
		{ID: "e", UserID: u, Action: "x", Timestamp: after}, // out of range
	}

	// full inclusive range
	got := tr.GetActivityByDateRange(u, ts0, ts2)
	assert.Len(t, got, 3)

	// single instant inclusive
	got2 := tr.GetActivityByDateRange(u, ts0, ts0)
	assert.Len(t, got2, 1)
	assert.Equal(t, "b", got2[0].ID)

	// user not found
	got3 := tr.GetActivityByDateRange("nope", ts0, ts2)
	assert.NotNil(t, got3)
	assert.Len(t, got3, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("b", "act", nil)
	tr.LogActivity("a", "act", nil)
	tr.LogActivity("b", "act2", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b"}, users)

	// empty tracker
	empty := NewTracker().GetAllUsers()
	assert.NotNil(t, empty)
	assert.Len(t, empty, 0)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "x", nil)
	tr.LogActivity("u1", "y", nil)
	tr.LogActivity("u2", "z", nil)

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)
	assert.Len(t, tr.GetActivityByUser("u1"), 0)

	// deleting again should return false
	assert.False(t, tr.DeleteUserActivity("u1"))
}

func TestFindMostFrequentAction(t *testing.T) {
	// empty
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// simple
	ac := map[string]int{"a": 1, "b": 3, "c": 2}
	assert.Equal(t, "b", findMostFrequentAction(ac))
}

func TestGenerateID(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
}
