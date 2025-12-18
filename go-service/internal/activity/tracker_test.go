package activity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	require.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
}

func TestLogActivity_Basic(t *testing.T) {
	tr := NewTracker()
	md := map[string]interface{}{"ip": "1.2.3.4", "n": 5}

	log := tr.LogActivity("u1", "login", md)
	require.NotNil(t, log)
	assert.Equal(t, "u1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotEmpty(t, log.ID)
	assert.False(t, log.Timestamp.IsZero())
	assert.Equal(t, md, log.Metadata)

	// verify it was stored
	fetched := tr.GetActivityByUser("u1")
	require.Len(t, fetched, 1)
	assert.Equal(t, "u1", fetched[0].UserID)
	assert.Equal(t, "login", fetched[0].Action)
	assert.Equal(t, md, fetched[0].Metadata)
}

func TestGetActivityByUser_CopyIsolation(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u", "a", nil)
	tr.LogActivity("u", "b", nil)

	logs1 := tr.GetActivityByUser("u")
	require.Len(t, logs1, 2)

	// Modify returned slice and element; internal state should not change
	logs1[0].Action = "CHANGED"
	logs1 = append(logs1, ActivityLog{Action: "extra"})

	logs2 := tr.GetActivityByUser("u")
	require.Len(t, logs2, 2)
	assert.NotEqual(t, "CHANGED", logs2[0].Action)
}

func TestGetActivityByUser_NotExists_ReturnsEmptyNonNil(t *testing.T) {
	tr := NewTracker()
	got := tr.GetActivityByUser("nouser")
	require.NotNil(t, got)
	assert.Len(t, got, 0)
}

func TestGetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("nouser")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	require.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Empty(t, stats.MostFrequent)
}

func TestGetActivityStats_WithData(t *testing.T) {
	tr := NewTracker()

	base := time.Date(2024, 7, 10, 12, 0, 0, 0, time.UTC)
	logs := []ActivityLog{
		{ID: "1", UserID: "u1", Action: "A", Timestamp: base},                      // earliest
		{ID: "2", UserID: "u1", Action: "B", Timestamp: base.Add(2 * time.Minute)}, // latest
		{ID: "3", UserID: "u1", Action: "A", Timestamp: base.Add(1 * time.Minute)},
		{ID: "4", UserID: "u1", Action: "C", Timestamp: base.Add(30 * time.Second)},
		{ID: "5", UserID: "u1", Action: "A", Timestamp: base.Add(90 * time.Second)},
	}

	tr.mu.Lock()
	tr.activities["u1"] = logs
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 5, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 3, stats.ActionCounts["A"])
	assert.Equal(t, 1, stats.ActionCounts["B"])
	assert.Equal(t, 1, stats.ActionCounts["C"])
	assert.Equal(t, base, stats.FirstActivity)
	assert.Equal(t, base.Add(2*time.Minute), stats.LastActivity)
	assert.Equal(t, "A", stats.MostFrequent)
}

func TestGetActivityByDateRange_BoundsInclusive(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 7, 10, 13, 0, 0, 0, time.UTC)

	logs := []ActivityLog{
		{ID: "x1", UserID: "u", Action: "pre", Timestamp: base.Add(-1 * time.Second)},
		{ID: "x2", UserID: "u", Action: "start", Timestamp: base},                       // included
		{ID: "x3", UserID: "u", Action: "middle", Timestamp: base.Add(1 * time.Second)}, // included
		{ID: "x4", UserID: "u", Action: "post", Timestamp: base.Add(2 * time.Second)},
	}
	tr.mu.Lock()
	tr.activities["u"] = logs
	tr.mu.Unlock()

	start := base
	end := base.Add(1 * time.Second)

	got := tr.GetActivityByDateRange("u", start, end)
	require.Len(t, got, 2)
	assert.Equal(t, "start", got[0].Action)
	assert.Equal(t, "middle", got[1].Action)
}

func TestGetActivityByDateRange_UserNotFound(t *testing.T) {
	tr := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now().Add(time.Hour)

	got := tr.GetActivityByDateRange("missing", start, end)
	require.NotNil(t, got)
	assert.Len(t, got, 0)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.mu.Lock()
	tr.activities["beta"] = []ActivityLog{{UserID: "beta"}}
	tr.activities["alpha"] = []ActivityLog{{UserID: "alpha"}}
	tr.activities["charlie"] = []ActivityLog{{UserID: "charlie"}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	require.Len(t, users, 3)
	assert.Equal(t, []string{"alpha", "beta", "charlie"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "A", Timestamp: time.Now()},
		{ID: "2", UserID: "u1", Action: "B", Timestamp: time.Now()},
	}
	tr.mu.Unlock()

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	// Ensure activities are removed
	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 0)

	// Deleting again returns false
	ok2 := tr.DeleteUserActivity("u1")
	assert.False(t, ok2)
}

func TestGenerateID_UniquenessAndFormat(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	require.NotEmpty(t, id1)
	require.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.Contains(t, id1, "-")
}

func TestFindMostFrequentAction(t *testing.T) {
	// Empty map
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// Non-empty
	counts := map[string]int{
		"login":  3,
		"logout": 1,
		"click":  2,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}
