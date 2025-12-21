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
	assert.Equal(t, 0, tr.idCounter)

	users := tr.GetAllUsers()
	assert.NotNil(t, users)
	assert.Len(t, users, 0)
}

func TestTracker_LogActivity_StoresAndIDs(t *testing.T) {
	tr := NewTracker()
	md := map[string]interface{}{"ip": "1.2.3.4"}

	log1 := tr.LogActivity("user1", "login", md)
	assert.NotNil(t, log1)
	assert.Equal(t, "user1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.Equal(t, "1.2.3.4", log1.Metadata["ip"])
	assert.NotEmpty(t, log1.ID)
	assert.Equal(t, 1, tr.idCounter)

	log2 := tr.LogActivity("user1", "click", nil)
	assert.NotNil(t, log2)
	assert.Equal(t, "click", log2.Action)
	assert.NotEmpty(t, log2.ID)
	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, 2, tr.idCounter)

	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 2)
	assert.Equal(t, log1.ID, logs[0].ID)
	assert.Equal(t, log2.ID, logs[1].ID)
}

func TestTracker_GetActivityByUser_CopyAndAlias(t *testing.T) {
	tr := NewTracker()
	md := map[string]interface{}{"k": "v"}
	tr.LogActivity("u", "a", md)

	got1 := tr.GetActivityByUser("u")
	assert.Len(t, got1, 1)
	// Mutate returned struct's Action; internal should not change because slice is copied and structs are copied by value.
	got1[0].Action = "mutated"

	got2 := tr.GetActivityByUser("u")
	assert.Equal(t, "a", got2[0].Action, "internal activity should not change when returned slice element is modified")

	// Mutate returned Metadata map; since map is referenced, internal will reflect the change.
	got1[0].Metadata["k"] = "changed"
	got3 := tr.GetActivityByUser("u")
	assert.Equal(t, "changed", got3[0].Metadata["k"], "metadata map is shared and mutations are reflected internally")
}

func TestTracker_GetActivityByUser_NonExisting(t *testing.T) {
	tr := NewTracker()
	got := tr.GetActivityByUser("nope")
	assert.NotNil(t, got)
	assert.Len(t, got, 0)

	// Appending to returned slice should not affect internal state
	got = append(got, ActivityLog{ID: "x"})
	got2 := tr.GetActivityByUser("nope")
	assert.Len(t, got2, 0)
}

func TestTracker_GetActivityStats_EmptyAndNonExisting(t *testing.T) {
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

func TestTracker_GetActivityStats_WithLogs(t *testing.T) {
	tr := NewTracker()

	// Manually seed activities with deterministic timestamps
	t0 := time.Date(2023, 1, 2, 15, 4, 5, 0, time.UTC)
	logs := []ActivityLog{
		{ID: "1", UserID: "u", Action: "click", Timestamp: t0.Add(2 * time.Second)},
		{ID: "2", UserID: "u", Action: "login", Timestamp: t0},
		{ID: "3", UserID: "u", Action: "click", Timestamp: t0.Add(4 * time.Second)},
	}
	tr.mu.Lock()
	tr.activities["u"] = logs
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["click"])
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, t0, stats.FirstActivity)
	assert.Equal(t, t0.Add(4*time.Second), stats.LastActivity)
	assert.Equal(t, "click", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_InclusiveAndInvalid(t *testing.T) {
	tr := NewTracker()

	userID := "u1"
	t0 := time.Date(2024, 3, 10, 10, 0, 0, 0, time.UTC)
	logs := []ActivityLog{
		{ID: "A", UserID: userID, Action: "a", Timestamp: t0.Add(-2 * time.Hour)},
		{ID: "B", UserID: userID, Action: "b", Timestamp: t0},
		{ID: "C", UserID: userID, Action: "c", Timestamp: t0.Add(2 * time.Hour)},
	}
	tr.mu.Lock()
	tr.activities[userID] = logs
	tr.mu.Unlock()

	// Inclusive bounds: include A and C when equal to start/end
	resAll := tr.GetActivityByDateRange(userID, t0.Add(-2*time.Hour), t0.Add(2*time.Hour))
	assert.Len(t, resAll, 3)
	assert.Equal(t, []string{"A", "B", "C"}, []string{resAll[0].ID, resAll[1].ID, resAll[2].ID})

	// Middle window: only B
	resMid := tr.GetActivityByDateRange(userID, t0.Add(-90*time.Minute), t0.Add(90*time.Minute))
	assert.Len(t, resMid, 1)
	assert.Equal(t, "B", resMid[0].ID)

	// Invalid range (start after end) should yield empty
	resInvalid := tr.GetActivityByDateRange(userID, t0.Add(time.Minute), t0.Add(-time.Minute))
	assert.Len(t, resInvalid, 0)
}

func TestTracker_GetActivityByDateRange_NoUser(t *testing.T) {
	tr := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now().Add(time.Hour)
	res := tr.GetActivityByDateRange("missing", start, end)
	assert.NotNil(t, res)
	assert.Len(t, res, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("charlie", "x", nil)
	tr.LogActivity("alice", "x", nil)
	tr.LogActivity("bob", "x", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	// Non-existing user
	ok := tr.DeleteUserActivity("nouser")
	assert.False(t, ok)

	// Existing user
	tr.LogActivity("uDel", "a", nil)
	tr.LogActivity("uDel", "b", nil)

	gotBefore := tr.GetActivityByUser("uDel")
	assert.Len(t, gotBefore, 2)

	ok = tr.DeleteUserActivity("uDel")
	assert.True(t, ok)

	gotAfter := tr.GetActivityByUser("uDel")
	assert.Len(t, gotAfter, 0)

	users := tr.GetAllUsers()
	for _, u := range users {
		assert.NotEqual(t, "uDel", u)
	}
}

func TestGenerateID_UniquePerCounter(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.True(t, strings.Contains(id1, "-"))
	assert.True(t, strings.Contains(id2, "-"))
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	m := map[string]int{
		"a": 2,
		"b": 5,
		"c": 1,
	}
	assert.Equal(t, "b", findMostFrequentAction(m))
}
