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
	assert.Empty(t, users)

	stats := tr.GetActivityStats("nonexistent")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)

	logs := tr.GetActivityByUser("nonexistent")
	assert.Empty(t, logs)
}

func TestTracker_LogActivityAndGetByUser_CopiesAndIDs(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1"}
	l1 := tr.LogActivity("u1", "login", meta)
	assert.NotNil(t, l1)
	assert.Equal(t, "u1", l1.UserID)
	assert.Equal(t, "login", l1.Action)
	assert.NotZero(t, l1.Timestamp)
	assert.NotEmpty(t, l1.ID)
	assert.Equal(t, 14, strings.Index(l1.ID, "-"))

	l2 := tr.LogActivity("u1", "click", nil)
	assert.NotNil(t, l2)
	assert.NotEqual(t, l1.ID, l2.ID)

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 2)
	assert.Equal(t, "127.0.0.1", logs[0].Metadata["ip"])

	// Mutating the returned slice should not affect stored data (slice elements are copied).
	originalAction := logs[0].Action
	logs[0].Action = "changed"
	logsAgain := tr.GetActivityByUser("u1")
	assert.Equal(t, originalAction, logsAgain[0].Action)
}

func TestTracker_GetActivityByDateRange(t *testing.T) {
	tr := NewTracker()

	time.Sleep(2 * time.Millisecond)
	b1 := time.Now()
	tr.LogActivity("u1", "a1", nil)
	a1 := time.Now()

	time.Sleep(2 * time.Millisecond)
	b2 := time.Now()
	tr.LogActivity("u1", "a2", nil)
	a2 := time.Now()

	time.Sleep(2 * time.Millisecond)
	b3 := time.Now()
	tr.LogActivity("u1", "a3", nil)
	a3 := time.Now()

	// Add another user's activity to ensure filtering by userID.
	time.Sleep(2 * time.Millisecond)
	tr.LogActivity("u2", "x1", nil)

	// Inclusive: only second log
	filtered := tr.GetActivityByDateRange("u1", b2, a2)
	if assert.Len(t, filtered, 1) {
		assert.Equal(t, "a2", filtered[0].Action)
	}

	// Full range for all three
	filtered = tr.GetActivityByDateRange("u1", b1, a3)
	assert.Len(t, filtered, 3)

	// Inverted range should return empty (implementation does not swap)
	filtered = tr.GetActivityByDateRange("u1", a3, b1)
	assert.Empty(t, filtered)

	// Non-existent user
	filtered = tr.GetActivityByDateRange("no_user", b1, a3)
	assert.Empty(t, filtered)

	// Boundary checks: start before first and end after last should include all
	start := b1.Add(-time.Second)
	end := a3.Add(time.Second)
	filtered = tr.GetActivityByDateRange("u1", start, end)
	assert.Len(t, filtered, 3)
}

func TestTracker_GetAllUsers(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u2", "a", nil)
	tr.LogActivity("u1", "b", nil)
	tr.LogActivity("u3", "c", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u1", "u2", "u3"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u2", "b", nil)

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Empty(t, tr.GetActivityByUser("u1"))

	// Other user unaffected
	assert.NotEmpty(t, tr.GetActivityByUser("u2"))

	// Deleting again should return false
	ok = tr.DeleteUserActivity("u1")
	assert.False(t, ok)
}

func TestTracker_GetActivityStats(t *testing.T) {
	tr := NewTracker()

	// User u1 activities
	tr.LogActivity("u1", "a", nil)
	time.Sleep(2 * time.Millisecond)
	tr.LogActivity("u1", "b", nil)
	time.Sleep(2 * time.Millisecond)
	tr.LogActivity("u1", "a", nil)

	// Another user to ensure stats are per user
	tr.LogActivity("u2", "a", nil)

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["a"])
	assert.Equal(t, 1, stats.ActionCounts["b"])
	assert.Equal(t, "a", stats.MostFrequent)
	assert.True(t, stats.FirstActivity.Before(stats.LastActivity) || stats.FirstActivity.Equal(stats.LastActivity))

	// No activity user
	emptyStats := tr.GetActivityStats("no_user")
	assert.Equal(t, 0, emptyStats.TotalActions)
	assert.Equal(t, 0, emptyStats.UniqueActions)
	assert.NotNil(t, emptyStats.ActionCounts)
}

func Test_findMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))
	assert.Equal(t, "a", findMostFrequentAction(map[string]int{"a": 3, "b": 1}))
}

func Test_generateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.Equal(t, 14, strings.Index(id1, "-"))
	assert.True(t, strings.HasSuffix(id1, string(rune(1))))
	assert.True(t, strings.HasSuffix(id2, string(rune(2))))
	assert.NotEqual(t, id1, id2)
}
