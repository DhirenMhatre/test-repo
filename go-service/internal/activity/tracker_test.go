package activity

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.Equal(t, 0, tr.idCounter)
	assert.Empty(t, tr.GetAllUsers())
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()

	md := map[string]interface{}{"ip": "127.0.0.1"}
	start := time.Now()
	log1 := tr.LogActivity("user1", "login", md)
	end := time.Now()

	assert.NotNil(t, log1)
	assert.Equal(t, "user1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.True(t, !log1.Timestamp.Before(start) && !log1.Timestamp.After(end))
	assert.NotEmpty(t, log1.ID)

	// Second activity should increment counter and produce a different ID
	log2 := tr.LogActivity("user2", "view", nil)
	assert.NotEqual(t, log1.ID, log2.ID)

	// Verify activities stored per user
	u1Logs := tr.GetActivityByUser("user1")
	u2Logs := tr.GetActivityByUser("user2")
	assert.Len(t, u1Logs, 1)
	assert.Len(t, u2Logs, 1)
	assert.Equal(t, "login", u1Logs[0].Action)
	assert.Equal(t, "view", u2Logs[0].Action)

	// idCounter should be 2 after two logs
	assert.Equal(t, 2, tr.idCounter)
}

func TestTracker_GetActivityByUser_CopyIndependence(t *testing.T) {
	tr := NewTracker()

	base := time.Date(2025, 1, 1, 12, 0, 0, 0, time.UTC)
	tr.activities["u"] = []ActivityLog{
		{ID: "1", UserID: "u", Action: "a1", Timestamp: base.Add(10 * time.Minute), Metadata: map[string]interface{}{"k": "v"}},
		{ID: "2", UserID: "u", Action: "a2", Timestamp: base.Add(20 * time.Minute)},
	}

	got := tr.GetActivityByUser("u")
	assert.Len(t, got, 2)
	// Modify returned slice and element fields; internal data should not change.
	got[0].Action = "mutated"
	got = append(got, ActivityLog{ID: "3", UserID: "u", Action: "a3", Timestamp: base.Add(30 * time.Minute)})

	again := tr.GetActivityByUser("u")
	assert.Len(t, again, 2)
	assert.Equal(t, "a1", again[0].Action)

	// Unknown user returns empty slice
	none := tr.GetActivityByUser("nope")
	assert.NotNil(t, none)
	assert.Len(t, none, 0)
}

func TestTracker_GetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("missing")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_Populated(t *testing.T) {
	tr := NewTracker()
	user := "u"

	base := time.Date(2025, 2, 2, 9, 0, 0, 0, time.UTC)
	// Unsorted timestamps
	tr.activities[user] = []ActivityLog{
		{ID: "1", UserID: user, Action: "login", Timestamp: base.Add(30 * time.Minute)},
		{ID: "2", UserID: user, Action: "view", Timestamp: base.Add(10 * time.Minute)},
		{ID: "3", UserID: user, Action: "view", Timestamp: base.Add(50 * time.Minute)},
	}
	// Add other user to ensure isolation
	tr.activities["other"] = []ActivityLog{
		{ID: "o1", UserID: "other", Action: "edit", Timestamp: base.Add(5 * time.Minute)},
	}

	stats := tr.GetActivityStats(user)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, "view", stats.MostFrequent)
	assert.Equal(t, base.Add(10*time.Minute), stats.FirstActivity)
	assert.Equal(t, base.Add(50*time.Minute), stats.LastActivity)
}

func TestTracker_GetActivityByDateRange_InclusiveAndUserScoped(t *testing.T) {
	tr := NewTracker()
	user := "u"
	base := time.Date(2025, 3, 3, 10, 0, 0, 0, time.UTC)

	tr.activities[user] = []ActivityLog{
		{ID: "1", UserID: user, Action: "a", Timestamp: base.Add(-1 * time.Hour)},
		{ID: "2", UserID: user, Action: "b", Timestamp: base},
		{ID: "3", UserID: user, Action: "c", Timestamp: base.Add(1 * time.Hour)},
	}
	tr.activities["v"] = []ActivityLog{
		{ID: "x", UserID: "v", Action: "x", Timestamp: base},
	}

	// Inclusive bounds: should return the middle record only
	got := tr.GetActivityByDateRange(user, base, base)
	assert.Len(t, got, 1)
	assert.Equal(t, "b", got[0].Action)

	// Range covering two records
	got = tr.GetActivityByDateRange(user, base.Add(-30*time.Minute), base.Add(2*time.Hour))
	assert.Len(t, got, 2)
	actions := []string{got[0].Action, got[1].Action}
	assert.Contains(t, actions, "b")
	assert.Contains(t, actions, "c")

	// Unknown user
	none := tr.GetActivityByDateRange("missing", base.Add(-time.Hour), base.Add(time.Hour))
	assert.Len(t, none, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	now := time.Now()
	tr.activities["c"] = []ActivityLog{{ID: "1", UserID: "c", Action: "x", Timestamp: now}}
	tr.activities["a"] = []ActivityLog{{ID: "2", UserID: "a", Action: "y", Timestamp: now}}
	tr.activities["b"] = []ActivityLog{{ID: "3", UserID: "b", Action: "z", Timestamp: now}}

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	now := time.Now()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "x", Timestamp: now},
		{ID: "2", UserID: "u1", Action: "y", Timestamp: now},
	}
	tr.activities["u2"] = []ActivityLog{
		{ID: "3", UserID: "u2", Action: "z", Timestamp: now},
	}

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Len(t, tr.GetActivityByUser("u1"), 0)
	assert.Len(t, tr.GetActivityByUser("u2"), 1)

	// Deleting non-existing user returns false
	ok = tr.DeleteUserActivity("u1")
	assert.False(t, ok)
}

func TestGenerateID_UniquenessAndFormat(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.True(t, strings.Contains(id1, "-"))
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login":  1,
		"view":   5,
		"search": 3,
	}
	assert.Equal(t, "view", findMostFrequentAction(counts))
}
