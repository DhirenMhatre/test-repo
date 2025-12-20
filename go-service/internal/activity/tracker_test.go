package activity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.Equal(t, 0, tr.idCounter)
	assert.Equal(t, 0, len(tr.activities))
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"ip": "1.2.3.4", "attempts": 3}

	l1 := tr.LogActivity("u1", "login", meta)
	assert.NotNil(t, l1)
	assert.Equal(t, "u1", l1.UserID)
	assert.Equal(t, "login", l1.Action)
	assert.NotEmpty(t, l1.ID)
	assert.False(t, l1.Timestamp.IsZero())
	assert.Equal(t, meta, l1.Metadata)
	assert.Equal(t, 1, tr.idCounter)

	l2 := tr.LogActivity("u1", "view", nil)
	assert.NotNil(t, l2)
	assert.NotEqual(t, l1.ID, l2.ID)

	tr.mu.RLock()
	defer tr.mu.RUnlock()
	assert.Len(t, tr.activities["u1"], 2)
}

func TestTracker_GetActivityByUser_CopyAndNonExistent(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("u1", "a1", nil)
	_ = tr.LogActivity("u1", "a2", nil)

	out1 := tr.GetActivityByUser("u1")
	assert.Len(t, out1, 2)

	// Mutate returned slice and ensure internal state is unchanged (slice copied)
	out1[0].Action = "mutated"
	out2 := tr.GetActivityByUser("u1")
	assert.Equal(t, "a1", out2[0].Action)
	assert.Equal(t, "a2", out2[1].Action)

	// Non-existent user
	none := tr.GetActivityByUser("nope")
	assert.NotNil(t, none)
	assert.Len(t, none, 0)
}

func TestTracker_GetActivityStats_EmptyUser(t *testing.T) {
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

func TestTracker_GetActivityStats_Populated(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2025, 3, 1, 12, 0, 0, 0, time.UTC)

	_ = tr.LogActivity("u1", "login", nil)  // idx 0
	_ = tr.LogActivity("u1", "view", nil)   // idx 1
	_ = tr.LogActivity("u1", "login", nil)  // idx 2
	_ = tr.LogActivity("u1", "logout", nil) // idx 3

	// Set deterministic timestamps
	tr.mu.Lock()
	tr.activities["u1"][0].Timestamp = base.Add(0 * time.Minute)
	tr.activities["u1"][1].Timestamp = base.Add(10 * time.Minute)
	tr.activities["u1"][2].Timestamp = base.Add(20 * time.Minute)
	tr.activities["u1"][3].Timestamp = base.Add(30 * time.Minute)
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["logout"])
	assert.True(t, stats.FirstActivity.Equal(base))
	assert.True(t, stats.LastActivity.Equal(base.Add(30*time.Minute)))
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2025, 4, 1, 0, 0, 0, 0, time.UTC)

	l1 := tr.LogActivity("u1", "a", nil) // t=+1h
	l2 := tr.LogActivity("u1", "b", nil) // t=+2h
	l3 := tr.LogActivity("u1", "c", nil) // t=+3h
	_ = tr.LogActivity("u2", "z", nil)   // t=+2h (other user)

	tr.mu.Lock()
	tr.activities["u1"][0].Timestamp = base.Add(1 * time.Hour)
	tr.activities["u1"][1].Timestamp = base.Add(2 * time.Hour)
	tr.activities["u1"][2].Timestamp = base.Add(3 * time.Hour)
	tr.activities["u2"][0].Timestamp = base.Add(2 * time.Hour)
	tr.mu.Unlock()

	// Inclusive range: should include l2 and l3
	out := tr.GetActivityByDateRange("u1", base.Add(2*time.Hour), base.Add(3*time.Hour))
	assert.Len(t, out, 2)
	assert.Equal(t, l2.ID, out[0].ID)
	assert.Equal(t, l3.ID, out[1].ID)

	// Non-existent user
	none := tr.GetActivityByDateRange("nouser", base, base.Add(10*time.Hour))
	assert.NotNil(t, none)
	assert.Len(t, none, 0)

	// Inclusive boundary for single match
	out2 := tr.GetActivityByDateRange("u1", base.Add(1*time.Hour), base.Add(1*time.Hour))
	assert.Len(t, out2, 1)
	assert.Equal(t, l1.ID, out2[0].ID)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("bob", "a", nil)
	_ = tr.LogActivity("alice", "b", nil)
	_ = tr.LogActivity("charlie", "c", nil)
	_ = tr.LogActivity("alice", "d", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("u1", "a", nil)
	_ = tr.LogActivity("u1", "b", nil)
	_ = tr.LogActivity("u2", "c", nil)

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	u1 := tr.GetActivityByUser("u1")
	assert.Len(t, u1, 0)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 0, stats.TotalActions)

	// Deleting again should return false
	ok2 := tr.DeleteUserActivity("u1")
	assert.False(t, ok2)
}

func TestGenerateID_UniqueAcrossCounters(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login": 2,
		"view":  1,
		"share": 1,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}
