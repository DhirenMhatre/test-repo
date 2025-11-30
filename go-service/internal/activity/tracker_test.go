package activity

import (
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)

	users := tr.GetAllUsers()
	assert.NotNil(t, users)
	assert.Len(t, users, 0)
}

func TestTracker_LogActivityAndGetByUser(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "1.2.3.4"}
	log := tr.LogActivity("u1", "login", meta)
	assert.NotNil(t, log)
	assert.Equal(t, "u1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotZero(t, log.Timestamp)
	assert.NotEmpty(t, log.ID)
	assert.Equal(t, meta, log.Metadata)

	// Fetch by user
	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 1)
	assert.Equal(t, "login", got[0].Action)

	// Ensure returned slice is a copy and struct elements are independent copies
	got[0].Action = "changed"
	got2 := tr.GetActivityByUser("u1")
	assert.Equal(t, "login", got2[0].Action)

	// Missing user returns empty slice (not nil)
	none := tr.GetActivityByUser("missing")
	assert.NotNil(t, none)
	assert.Len(t, none, 0)
}

func TestTracker_GetActivityStats_EmptyAndCounts(t *testing.T) {
	tr := NewTracker()

	// Empty stats for unknown user
	statsEmpty := tr.GetActivityStats("nope")
	assert.Equal(t, 0, statsEmpty.TotalActions)
	assert.Equal(t, 0, statsEmpty.UniqueActions)
	assert.NotNil(t, statsEmpty.ActionCounts)
	assert.Len(t, statsEmpty.ActionCounts, 0)
	assert.True(t, statsEmpty.FirstActivity.IsZero())
	assert.True(t, statsEmpty.LastActivity.IsZero())
	assert.Equal(t, "", statsEmpty.MostFrequent)

	// Add 3 activities for u1: a, b, a with controlled timestamps
	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u1", "b", nil)
	tr.LogActivity("u1", "a", nil)

	t1 := time.Date(2024, 1, 1, 10, 0, 0, 0, time.UTC)
	t2 := time.Date(2024, 1, 1, 10, 1, 0, 0, time.UTC)
	t3 := time.Date(2024, 1, 1, 10, 2, 0, 0, time.UTC)

	tr.mu.Lock()
	tr.activities["u1"][0].Timestamp = t1
	tr.activities["u1"][1].Timestamp = t2
	tr.activities["u1"][2].Timestamp = t3
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["a"])
	assert.Equal(t, 1, stats.ActionCounts["b"])
	assert.Equal(t, t1, stats.FirstActivity)
	assert.Equal(t, t3, stats.LastActivity)
	assert.Equal(t, "a", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u1", "b", nil)
	tr.LogActivity("u1", "c", nil)

	t1 := time.Date(2024, 2, 1, 0, 0, 0, 0, time.UTC)
	t2 := time.Date(2024, 2, 1, 1, 0, 0, 0, time.UTC)
	t3 := time.Date(2024, 2, 1, 2, 0, 0, 0, time.UTC)

	tr.mu.Lock()
	tr.activities["u1"][0].Timestamp = t1
	tr.activities["u1"][1].Timestamp = t2
	tr.activities["u1"][2].Timestamp = t3
	tr.mu.Unlock()

	// Full inclusive range
	all := tr.GetActivityByDateRange("u1", t1, t3)
	assert.Len(t, all, 3)

	// Single point inclusive range
	midOnly := tr.GetActivityByDateRange("u1", t2, t2)
	assert.Len(t, midOnly, 1)
	assert.Equal(t, "b", midOnly[0].Action)

	// Range excluding the first and last
	inBetween := tr.GetActivityByDateRange("u1", t1.Add(time.Nanosecond), t3.Add(-time.Nanosecond))
	assert.Len(t, inBetween, 1)
	assert.Equal(t, "b", inBetween[0].Action)

	// Unknown user
	none := tr.GetActivityByDateRange("unknown", t1, t3)
	assert.NotNil(t, none)
	assert.Len(t, none, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u2", "x", nil)
	tr.LogActivity("u1", "y", nil)
	tr.LogActivity("u3", "z", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u1", "u2", "u3"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u1", "b", nil)
	tr.LogActivity("u2", "a", nil)

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Len(t, tr.GetActivityByUser("u1"), 0)

	// Deleting again returns false
	ok2 := tr.DeleteUserActivity("u1")
	assert.False(t, ok2)

	// Only u2 remains
	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)
}

func Test_generateID_SuffixAndUniqueness(t *testing.T) {
	id1 := generateID(49) // '1'
	id2 := generateID(50) // '2'
	assert.True(t, strings.HasSuffix(id1, "-1"), "expected suffix -1, got %q", id1)
	assert.True(t, strings.HasSuffix(id2, "-2"), "expected suffix -2, got %q", id2)
	assert.NotEqual(t, id1, id2)
}

func Test_findMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login":  3,
		"click":  2,
		"logout": 1,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}

func TestTracker_ConcurrentLogActivity(t *testing.T) {
	tr := NewTracker()
	const n = 100

	var wg sync.WaitGroup
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func() {
			defer wg.Done()
			tr.LogActivity("u1", "act", nil)
		}()
	}
	wg.Wait()

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, n)
	assert.Equal(t, n, tr.idCounter)
}

func TestGetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u1", "b", nil)

	got1 := tr.GetActivityByUser("u1")
	assert.Len(t, got1, 2)

	// Append to returned slice; should not affect internal storage
	got1 = append(got1, ActivityLog{UserID: "u1", Action: "c"})
	got2 := tr.GetActivityByUser("u1")
	assert.Len(t, got2, 2)
}
