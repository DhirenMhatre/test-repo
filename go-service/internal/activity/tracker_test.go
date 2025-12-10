package activity

import (
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

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()

	md := map[string]interface{}{"ip": "127.0.0.1", "device": "mobile"}
	log1 := tr.LogActivity("user1", "login", md)
	assert.NotNil(t, log1)
	assert.Equal(t, "user1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.NotEmpty(t, log1.ID)
	assert.False(t, log1.Timestamp.IsZero())
	assert.Equal(t, md, log1.Metadata)

	assert.Equal(t, 1, tr.idCounter)
	assert.Len(t, tr.activities["user1"], 1)

	log2 := tr.LogActivity("user1", "click", nil)
	assert.NotNil(t, log2)
	assert.NotEmpty(t, log2.ID)
	assert.NotEqual(t, log1.ID, log2.ID, "IDs should be unique per activity")
	assert.Equal(t, 2, tr.idCounter)
	assert.Len(t, tr.activities["user1"], 2)
}

func TestTracker_GetActivityByUser_CopyIsolation(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a1", nil)

	// Returned slice is a copy; mutating it must not affect stored activities.
	out := tr.GetActivityByUser("u1")
	assert.Len(t, out, 1)
	origAction := out[0].Action

	out[0].Action = "mutated"
	out2 := tr.GetActivityByUser("u1")
	assert.Len(t, out2, 1)
	assert.Equal(t, origAction, out2[0].Action)
}

func TestTracker_GetActivityByUser_Unknown(t *testing.T) {
	tr := NewTracker()
	out := tr.GetActivityByUser("unknown")
	assert.NotNil(t, out)
	assert.Len(t, out, 0)
}

func TestTracker_GetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("no-user")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_Computed(t *testing.T) {
	tr := NewTracker()

	u := "u1"
	// Prepare deterministic activity logs with out-of-order timestamps
	logs := []ActivityLog{
		{ID: "1", UserID: u, Action: "view", Timestamp: fixed(50)},
		{ID: "2", UserID: u, Action: "login", Timestamp: fixed(10)},
		{ID: "3", UserID: u, Action: "login", Timestamp: fixed(70)},
		{ID: "4", UserID: u, Action: "click", Timestamp: fixed(60)},
	}
	tr.mu.Lock()
	tr.activities[u] = append([]ActivityLog{}, logs...)
	tr.mu.Unlock()

	stats := tr.GetActivityStats(u)
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["click"])
	assert.Equal(t, 1, stats.ActionCounts["view"])

	assert.Equal(t, fixed(10), stats.FirstActivity)
	assert.Equal(t, fixed(70), stats.LastActivity)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()
	u := "u1"
	logs := []ActivityLog{
		{ID: "1", UserID: u, Action: "a10", Timestamp: fixed(10)},
		{ID: "2", UserID: u, Action: "a20", Timestamp: fixed(20)},
		{ID: "3", UserID: u, Action: "a30", Timestamp: fixed(30)},
	}
	tr.mu.Lock()
	tr.activities[u] = append([]ActivityLog{}, logs...)
	tr.mu.Unlock()

	// Range includes boundaries
	out := tr.GetActivityByDateRange(u, fixed(20), fixed(30))
	assert.Len(t, out, 2)
	assert.Equal(t, "a20", out[0].Action)
	assert.Equal(t, "a30", out[1].Action)

	// Exact point range
	out2 := tr.GetActivityByDateRange(u, fixed(20), fixed(20))
	assert.Len(t, out2, 1)
	assert.Equal(t, "a20", out2[0].Action)

	// No matches
	out3 := tr.GetActivityByDateRange(u, fixed(31), fixed(40))
	assert.Empty(t, out3)

	// Unknown user
	out4 := tr.GetActivityByDateRange("unknown", fixed(0), fixed(100))
	assert.Empty(t, out4)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.mu.Lock()
	tr.activities["charlie"] = []ActivityLog{{ID: "1", UserID: "charlie", Action: "a", Timestamp: fixed(1)}}
	tr.activities["alice"] = []ActivityLog{{ID: "2", UserID: "alice", Action: "b", Timestamp: fixed(2)}}
	tr.activities["bob"] = []ActivityLog{
		{ID: "3", UserID: "bob", Action: "c", Timestamp: fixed(3)},
		{ID: "4", UserID: "bob", Action: "d", Timestamp: fixed(4)},
	}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a", Timestamp: fixed(1)},
		{ID: "2", UserID: "u1", Action: "b", Timestamp: fixed(2)},
	}
	tr.activities["u2"] = []ActivityLog{
		{ID: "3", UserID: "u2", Action: "c", Timestamp: fixed(3)},
	}
	tr.mu.Unlock()

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Empty(t, tr.GetActivityByUser("u1"))
	assert.Len(t, tr.GetActivityByUser("u2"), 1)

	ok2 := tr.DeleteUserActivity("unknown")
	assert.False(t, ok2)
}

func Test_findMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login":  5,
		"click":  2,
		"view":   3,
		"logout": 1,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}

func Test_generateID(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.Contains(t, id1, "-")
	assert.Contains(t, id2, "-")
}

func fixed(sec int) time.Time {
	return time.Date(2025, 1, 1, 0, 0, sec, 0, time.UTC)
}
