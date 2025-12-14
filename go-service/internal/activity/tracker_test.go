package activity

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func setUserTimestamps(t *testing.T, tr *Tracker, userID string, times []time.Time) {
	t.Helper()
	tr.mu.Lock()
	defer tr.mu.Unlock()
	logs := tr.activities[userID]
	for i := range logs {
		if i < len(times) {
			logs[i].Timestamp = times[i]
		}
	}
	tr.activities[userID] = logs
}

func TestNewTracker_Initialization(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)

	// No users at start
	users := tr.GetAllUsers()
	assert.Empty(t, users)

	// Stats for nonexistent user
	stats := tr.GetActivityStats("nonexistent")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_LogActivity_AssignsAndStores(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "1.2.3.4", "attempt": 1}
	log1 := tr.LogActivity("user1", "login", meta)
	assert.NotNil(t, log1)
	assert.Equal(t, "user1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.NotEmpty(t, log1.ID)
	assert.False(t, log1.Timestamp.IsZero())
	assert.Equal(t, meta, log1.Metadata)

	log2 := tr.LogActivity("user1", "click", nil)
	assert.NotNil(t, log2)
	assert.NotEmpty(t, log2.ID)
	assert.NotEqual(t, log1.ID, log2.ID)

	byUser := tr.GetActivityByUser("user1")
	assert.Len(t, byUser, 2)
	// Ensure metadata is present in the stored copy for the first log
	assert.Equal(t, meta, byUser[0].Metadata)
}

func TestTracker_GetActivityByUser_EmptyAndCopyIsolation(t *testing.T) {
	tr := NewTracker()

	// Nonexistent user
	empty := tr.GetActivityByUser("none")
	assert.NotNil(t, empty)
	assert.Empty(t, empty)

	// Add some activities
	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 2)

	// Modify returned slice and ensure internal data is unaffected
	got[0].Action = "modified"
	gotAgain := tr.GetActivityByUser("u1")
	assert.Equal(t, "a1", gotAgain[0].Action)
}

func TestTracker_GetActivityStats_EmptyAndCounts(t *testing.T) {
	tr := NewTracker()

	// Empty stats for user
	s0 := tr.GetActivityStats("u1")
	assert.Equal(t, 0, s0.TotalActions)
	assert.Equal(t, 0, s0.UniqueActions)
	assert.Equal(t, "", s0.MostFrequent)
	assert.NotNil(t, s0.ActionCounts)
	assert.Len(t, s0.ActionCounts, 0)

	// Add activities for u1
	tr.LogActivity("u1", "view", nil)
	tr.LogActivity("u1", "click", nil)
	tr.LogActivity("u1", "view", nil)
	tr.LogActivity("u1", "view", nil)

	// Set deterministic times
	base := time.Date(2025, 1, 2, 3, 0, 0, 0, time.UTC)
	times := []time.Time{
		base.Add(1 * time.Minute),
		base.Add(2 * time.Minute),
		base.Add(3 * time.Minute),
		base.Add(4 * time.Minute),
	}
	setUserTimestamps(t, tr, "u1", times)

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 3, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["click"])
	assert.Equal(t, base.Add(1*time.Minute), stats.FirstActivity)
	assert.Equal(t, base.Add(4*time.Minute), stats.LastActivity)
	assert.Equal(t, "view", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()

	// Create three activities with controlled timestamps
	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u1", "b", nil)
	tr.LogActivity("u1", "c", nil)

	base := time.Date(2025, 2, 3, 10, 0, 0, 0, time.UTC)
	t1 := base.Add(0 * time.Minute)
	t2 := base.Add(5 * time.Minute)
	t3 := base.Add(10 * time.Minute)
	setUserTimestamps(t, tr, "u1", []time.Time{t1, t2, t3})

	// [t1, t3] inclusive should include all
	all := tr.GetActivityByDateRange("u1", t1, t3)
	assert.Len(t, all, 3)

	// [t2, t3] inclusive should include 2: b and c
	midToEnd := tr.GetActivityByDateRange("u1", t2, t3)
	assert.Len(t, midToEnd, 2)
	assert.Equal(t, "b", midToEnd[0].Action)
	assert.Equal(t, "c", midToEnd[1].Action)

	// [t1, t2] inclusive should include 2: a and b
	startToMid := tr.GetActivityByDateRange("u1", t1, t2)
	assert.Len(t, startToMid, 2)
	assert.Equal(t, "a", startToMid[0].Action)
	assert.Equal(t, "b", startToMid[1].Action)

	// Range outside of any timestamps returns empty
	outside := tr.GetActivityByDateRange("u1", t3.Add(time.Second), t3.Add(2*time.Second))
	assert.Empty(t, outside)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("bob", "login", nil)
	tr.LogActivity("alice", "click", nil)
	tr.LogActivity("charlie", "view", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity_Behavior(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u1", "b", nil)
	tr.LogActivity("u2", "x", nil)

	// Nonexistent user
	ok := tr.DeleteUserActivity("none")
	assert.False(t, ok)

	// Delete existing user's activities
	ok = tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Empty(t, tr.GetActivityByUser("u1"))

	// Other user unaffected
	u2 := tr.GetActivityByUser("u2")
	assert.Len(t, u2, 1)
	assert.Equal(t, "x", u2[0].Action)

	// Deleting again returns false
	ok = tr.DeleteUserActivity("u1")
	assert.False(t, ok)
}

func TestGenerateID_FormatAndSuffix(t *testing.T) {
	id := generateID(1)
	parts := strings.SplitN(id, "-", 2)
	assert.Len(t, parts, 2)
	// datetime part expected length 14 with layout 20060102150405
	assert.Len(t, parts[0], 14)
	// suffix should be string(rune(counter))
	assert.Equal(t, string(rune(1)), parts[1])

	id2 := generateID(2)
	parts2 := strings.SplitN(id2, "-", 2)
	assert.Len(t, parts2, 2)
	assert.Equal(t, string(rune(2)), parts2[1])

	// IDs should differ for different counters and/or time
	assert.NotEqual(t, id, id2)
}

func TestFindMostFrequentAction_BasicAndEmpty(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login":  2,
		"click":  5,
		"logout": 1,
	}
	assert.Equal(t, "click", findMostFrequentAction(counts))
}
