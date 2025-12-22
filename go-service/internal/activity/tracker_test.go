package activity

import (
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)

	users := tr.GetAllUsers()
	assert.NotNil(t, users)
	assert.Len(t, users, 0)

	logs := tr.GetActivityByUser("nonexistent")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_LogActivity_And_GetActivityByUser_Basic(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1", "count": 1}
	log1 := tr.LogActivity("u1", "login", meta)
	assert.NotNil(t, log1)
	assert.Equal(t, "u1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.NotEmpty(t, log1.ID)

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 1)
	assert.Equal(t, "u1", logs[0].UserID)
	assert.Equal(t, "login", logs[0].Action)
	assert.Equal(t, "127.0.0.1", logs[0].Metadata["ip"])

	// Metadata aliasing: modifying the original map should reflect in stored logs
	meta["new"] = "val"
	logs2 := tr.GetActivityByUser("u1")
	assert.Equal(t, "val", logs2[0].Metadata["new"])

	// IDs should be unique for subsequent activities
	log2 := tr.LogActivity("u1", "click", nil)
	assert.NotNil(t, log2)
	assert.NotEqual(t, log1.ID, log2.ID)
}

func TestTracker_GetActivityByUser_CopyAndMetadataAlias(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"k": "v"}
	_ = tr.LogActivity("u1", "act", meta)

	// Verify struct copy (modifying returned struct shouldn't affect stored one)
	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 1)
	origAction := logs[0].Action

	// Change the returned copy's Action
	logs[0].Action = "changed"

	// Fetched logs again should still have original action
	logsAgain := tr.GetActivityByUser("u1")
	assert.Equal(t, origAction, logsAgain[0].Action)

	// But Metadata is a map (reference type): aliasing should occur
	logs[0].Metadata["alias"] = "yes"
	logsThird := tr.GetActivityByUser("u1")
	assert.Equal(t, "yes", logsThird[0].Metadata["alias"])
}

func TestTracker_GetActivityStats_EmptyAndFilled(t *testing.T) {
	tr := NewTracker()

	// Empty user stats
	statsEmpty := tr.GetActivityStats("nouser")
	assert.NotNil(t, statsEmpty)
	assert.Equal(t, 0, statsEmpty.TotalActions)
	assert.Equal(t, 0, statsEmpty.UniqueActions)
	assert.NotNil(t, statsEmpty.ActionCounts)
	assert.Len(t, statsEmpty.ActionCounts, 0)
	assert.Empty(t, statsEmpty.MostFrequent)
	assert.True(t, statsEmpty.FirstActivity.IsZero())
	assert.True(t, statsEmpty.LastActivity.IsZero())

	// Add activities for a user
	_ = tr.LogActivity("u1", "login", nil)
	_ = tr.LogActivity("u1", "view", nil)
	_ = tr.LogActivity("u1", "view", nil)

	// Set deterministic timestamps out of order: [t1, t0, t2]
	t0 := time.Date(2020, 1, 1, 10, 0, 0, 0, time.UTC)
	t1 := time.Date(2020, 1, 1, 11, 0, 0, 0, time.UTC)
	t2 := time.Date(2020, 1, 1, 12, 0, 0, 0, time.UTC)
	setUserLogTimes(tr, "u1", []time.Time{t1, t0, t2})

	stats := tr.GetActivityStats("u1")
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, "view", stats.MostFrequent)
	assert.True(t, stats.FirstActivity.Equal(t0))
	assert.True(t, stats.LastActivity.Equal(t2))
}

func TestTracker_GetActivityByDateRange_InclusiveAndInvalid(t *testing.T) {
	tr := NewTracker()

	_ = tr.LogActivity("u1", "a0", nil)
	_ = tr.LogActivity("u1", "a1", nil)
	_ = tr.LogActivity("u1", "a2", nil)

	// Assign deterministic timestamps: [t0, t1, t2]
	t0 := time.Date(2021, 2, 3, 10, 0, 0, 0, time.UTC)
	t1 := time.Date(2021, 2, 3, 11, 0, 0, 0, time.UTC)
	t2 := time.Date(2021, 2, 3, 12, 0, 0, 0, time.UTC)
	setUserLogTimes(tr, "u1", []time.Time{t0, t1, t2})

	// Inclusive range [t1, t2] should include timestamps at t1 and t2
	got := tr.GetActivityByDateRange("u1", t1, t2)
	assert.Len(t, got, 2)
	for _, l := range got {
		assert.True(t, !l.Timestamp.Before(t1) && !l.Timestamp.After(t2))
	}

	// Exact timestamp [t0, t0] should return 1
	gotExact := tr.GetActivityByDateRange("u1", t0, t0)
	assert.Len(t, gotExact, 1)
	assert.True(t, gotExact[0].Timestamp.Equal(t0))

	// Invalid range start > end should return empty
	gotInvalid := tr.GetActivityByDateRange("u1", t2, t1)
	assert.Len(t, gotInvalid, 0)

	// Non-existent user
	gotNone := tr.GetActivityByDateRange("nouser", t0, t2)
	assert.Len(t, gotNone, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	_ = tr.LogActivity("b", "x", nil)
	_ = tr.LogActivity("a", "x", nil)
	_ = tr.LogActivity("c", "x", nil)
	_ = tr.LogActivity("b", "y", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	// Non-existent user
	assert.False(t, tr.DeleteUserActivity("nouser"))

	// Add user activities and delete
	_ = tr.LogActivity("u1", "x", nil)
	_ = tr.LogActivity("u1", "y", nil)
	assert.True(t, tr.DeleteUserActivity("u1"))

	// Verify deletion
	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 0)
	users := tr.GetAllUsers()
	assert.NotContains(t, users, "u1")

	// Deleting again should return false
	assert.False(t, tr.DeleteUserActivity("u1"))
}

func TestTracker_LogActivity_Concurrent(t *testing.T) {
	tr := NewTracker()

	var wg sync.WaitGroup
	users := []string{"u1", "u2", "u3"}
	perUser := 50

	for _, u := range users {
		u := u
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < perUser; i++ {
				tr.LogActivity(u, "act", nil)
			}
		}()
	}
	wg.Wait()

	for _, u := range users {
		logs := tr.GetActivityByUser(u)
		assert.Len(t, logs, perUser)
	}
}

// helper to set deterministic timestamps for a user's logs
func setUserLogTimes(tr *Tracker, userID string, times []time.Time) {
	tr.mu.Lock()
	defer tr.mu.Unlock()
	logs := tr.activities[userID]
	for i := range logs {
		if i < len(times) {
			tr.activities[userID][i].Timestamp = times[i]
		}
	}
}
