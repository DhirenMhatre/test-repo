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
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "1.2.3.4"}
	log := tr.LogActivity("u1", "login", meta)
	assert.NotNil(t, log)
	assert.Equal(t, "u1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotEmpty(t, log.ID)
	assert.WithinDuration(t, time.Now(), log.Timestamp, 5*time.Second)
	assert.Equal(t, meta, log.Metadata)

	// Stored
	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 1)
	assert.Equal(t, "login", got[0].Action)

	// ID uniqueness across subsequent logs
	log2 := tr.LogActivity("u1", "click", nil)
	assert.NotNil(t, log2)
	assert.NotEqual(t, log.ID, log2.ID)
}

func TestTracker_GetActivityByUser_EmptyAndCopy(t *testing.T) {
	tr := NewTracker()

	// Non-existent user -> empty slice (non-nil)
	got := tr.GetActivityByUser("nope")
	assert.NotNil(t, got)
	assert.Len(t, got, 0)

	// Add two logs
	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)

	// Returned slice must be a copy (modifying result should not change internal state)
	before := tr.GetActivityByUser("u1")
	assert.Len(t, before, 2)
	before[0].Action = "mutated"

	after := tr.GetActivityByUser("u1")
	assert.Equal(t, "a1", after[0].Action)
}

func TestTracker_GetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("u-missing")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, "", stats.MostFrequent)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
}

func TestTracker_GetActivityStats_WithData(t *testing.T) {
	tr := NewTracker()

	// Create three logs
	tr.LogActivity("u1", "click", nil) // will adjust timestamp
	tr.LogActivity("u1", "login", nil)
	tr.LogActivity("u2", "login", nil)

	// Adjust their timestamps deterministically (and out of order)
	now := time.Now()
	t1 := now.Add(-3 * time.Minute)
	t2 := now.Add(-2 * time.Minute)
	t3 := now.Add(-1 * time.Minute)

	tr.mu.Lock()
	// activities stored per user
	u1Logs := tr.activities["u1"]
	u2Logs := tr.activities["u2"]
	// Ensure there are expected logs
	assert.Len(t, u1Logs, 2)
	assert.Len(t, u2Logs, 1)

	// Set times: u1[0]=t2 (click), u1[1]=t1 (login) so out-of-order for u1
	u1Logs[0].Timestamp = t2
	u1Logs[1].Timestamp = t1
	tr.activities["u1"] = u1Logs

	// u2[0]=t3 (login)
	u2Logs[0].Timestamp = t3
	tr.activities["u2"] = u2Logs
	tr.mu.Unlock()

	statsU1 := tr.GetActivityStats("u1")
	assert.Equal(t, 2, statsU1.TotalActions)
	assert.Equal(t, 2, statsU1.UniqueActions)
	assert.Equal(t, 1, statsU1.ActionCounts["click"])
	assert.Equal(t, 1, statsU1.ActionCounts["login"])
	assert.True(t, statsU1.FirstActivity.Equal(t1))
	assert.True(t, statsU1.LastActivity.Equal(t2))
	// Tie between click and login (both 1). Implementation picks first max encountered.
	// Instead of asserting specific MostFrequent, assert it's one of them.
	assert.Contains(t, []string{"click", "login"}, statsU1.MostFrequent)

	statsAll := tr.GetActivityStats("u2")
	assert.Equal(t, 1, statsAll.TotalActions)
	assert.Equal(t, 1, statsAll.UniqueActions)
	assert.Equal(t, 1, statsAll.ActionCounts["login"])
	assert.True(t, statsAll.FirstActivity.Equal(t3))
	assert.True(t, statsAll.LastActivity.Equal(t3))
	assert.Equal(t, "login", statsAll.MostFrequent)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()

	// Three logs for user u1
	tr.LogActivity("u1", "a0", nil)
	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)

	// Set deterministic timestamps
	now := time.Now()
	t0 := now.Add(-3 * time.Minute)
	t1 := now.Add(-2 * time.Minute)
	t2 := now.Add(-1 * time.Minute)

	tr.mu.Lock()
	u1Logs := tr.activities["u1"]
	assert.Len(t, u1Logs, 3)
	u1Logs[0].Timestamp = t0
	u1Logs[1].Timestamp = t1
	u1Logs[2].Timestamp = t2
	tr.activities["u1"] = u1Logs
	tr.mu.Unlock()

	// Inclusive range: [t1, t2]
	in := tr.GetActivityByDateRange("u1", t1, t2)
	assert.Len(t, in, 2)
	var actions []string
	for _, l := range in {
		actions = append(actions, l.Action)
		assert.True(t, (l.Timestamp.Equal(t1) || l.Timestamp.After(t1)) && (l.Timestamp.Equal(t2) || l.Timestamp.Before(t2)))
	}
	assert.ElementsMatch(t, []string{"a1", "a2"}, actions)

	// Non-existent user
	empty := tr.GetActivityByDateRange("nope", t1, t2)
	assert.NotNil(t, empty)
	assert.Len(t, empty, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	// Populate with users out of order
	tr.LogActivity("charlie", "a", nil)
	tr.LogActivity("alice", "b", nil)
	tr.LogActivity("bob", "c", nil)
	tr.LogActivity("alice", "d", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u2", "b", nil)
	tr.LogActivity("u1", "c", nil)

	// Deleting non-existent user
	ok := tr.DeleteUserActivity("u3")
	assert.False(t, ok)

	// Delete existing
	ok = tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	// Verify removal
	gotU1 := tr.GetActivityByUser("u1")
	assert.Len(t, gotU1, 0)

	// Other user remains
	gotU2 := tr.GetActivityByUser("u2")
	assert.Len(t, gotU2, 1)

	// Users listing reflects deletion
	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)
}

func Test_generateID_Basic(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.True(t, strings.Contains(id1, "-"))
}

func Test_findMostFrequentAction(t *testing.T) {
	// Empty
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// Single
	assert.Equal(t, "a", findMostFrequentAction(map[string]int{"a": 1}))

	// Multiple with clear winner
	counts := map[string]int{"a": 2, "b": 5, "c": 3}
	assert.Equal(t, "b", findMostFrequentAction(counts))
}
