package activity

import (
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)

	assert.Empty(t, tr.GetAllUsers())
	assert.Empty(t, tr.GetActivityByUser("unknown"))
}

func TestLogActivity_BasicAndIDFormat(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"ip": "127.0.0.1"}
	al := tr.LogActivity("u1", "login", meta)
	assert.NotNil(t, al)
	assert.Equal(t, "u1", al.UserID)
	assert.Equal(t, "login", al.Action)
	assert.WithinDuration(t, time.Now(), al.Timestamp, 2*time.Second)

	// ID format: "<YYYYMMDDhhmmss>-<rune(counter)>"
	id := al.ID
	parts := strings.SplitN(id, "-", 2)
	assert.Len(t, parts, 2)
	_, err := time.Parse("20060102150405", parts[0])
	assert.NoError(t, err)
	assert.True(t, strings.HasSuffix(id, "-"+string(rune(1))), "expected suffix -\\x01 for first ID, got %q", id)
}

func TestGetActivityByUser_OrderAndCopyIsolation(t *testing.T) {
	tr := NewTracker()
	a1 := tr.LogActivity("u1", "a", nil)
	time.Sleep(10 * time.Millisecond)
	a2 := tr.LogActivity("u1", "b", nil)
	tr.LogActivity("u2", "c", nil)

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 2)
	assert.Equal(t, a1.ID, got[0].ID)
	assert.Equal(t, a2.ID, got[1].ID)

	// Mutate returned copy and ensure internal state is not affected
	got[0].Action = "changed"
	gotBack := tr.GetActivityByUser("u1")
	assert.Equal(t, "a", gotBack[0].Action)
}

func TestGetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("missing")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestGetActivityStats_CountsTimesMostFrequent(t *testing.T) {
	tr := NewTracker()
	// Ensure one action is strictly most frequent
	tr.LogActivity("u1", "login", nil)
	time.Sleep(5 * time.Millisecond)
	tr.LogActivity("u1", "login", nil)
	time.Sleep(5 * time.Millisecond)
	tr.LogActivity("u1", "click", nil)
	time.Sleep(5 * time.Millisecond)
	tr.LogActivity("u1", "login", nil)

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 3, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["click"])
	assert.Equal(t, "login", stats.MostFrequent)
	assert.False(t, stats.FirstActivity.IsZero())
	assert.False(t, stats.LastActivity.IsZero())
	assert.True(t, stats.LastActivity.After(stats.FirstActivity) || stats.LastActivity.Equal(stats.FirstActivity))
}

func TestGetActivityByDateRange_InclusiveEdges(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a", nil)
	time.Sleep(5 * time.Millisecond)
	tr.LogActivity("u1", "b", nil)
	time.Sleep(5 * time.Millisecond)
	tr.LogActivity("u1", "c", nil)

	// Fetch timestamps to build exact ranges
	all := tr.GetActivityByUser("u1")
	assert.Len(t, all, 3)
	t1 := all[0].Timestamp
	t2 := all[1].Timestamp
	t3 := all[2].Timestamp

	// Start == End == middle timestamp should include that log (inclusive)
	f1 := tr.GetActivityByDateRange("u1", t2, t2)
	assert.Len(t, f1, 1)
	assert.Equal(t, all[1].ID, f1[0].ID)

	// Full range inclusive should include all
	f2 := tr.GetActivityByDateRange("u1", t1, t3)
	assert.Len(t, f2, 3)

	// Out-of-range should return empty
	f3 := tr.GetActivityByDateRange("u1", t3.Add(1*time.Second), t3.Add(2*time.Second))
	assert.Empty(t, f3)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("b", "x", nil)
	tr.LogActivity("a", "y", nil)
	tr.LogActivity("c", "z", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u1", "b", nil)
	tr.LogActivity("u2", "c", nil)

	// Delete non-existent
	ok := tr.DeleteUserActivity("nope")
	assert.False(t, ok)

	ok = tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Empty(t, tr.GetActivityByUser("u1"))

	remaining := tr.GetActivityByUser("u2")
	assert.Len(t, remaining, 1)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)
}

func TestFindMostFrequentAction(t *testing.T) {
	// Empty
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// Single
	assert.Equal(t, "login", findMostFrequentAction(map[string]int{"login": 1}))

	// Multiple with clear winner
	m := map[string]int{
		"click": 2,
		"login": 5,
		"view":  3,
	}
	assert.Equal(t, "login", findMostFrequentAction(m))
}

func TestGenerateID_Format(t *testing.T) {
	id := generateID(1)
	parts := strings.SplitN(id, "-", 2)
	assert.Len(t, parts, 2)
	_, err := time.Parse("20060102150405", parts[0])
	assert.NoError(t, err)
	assert.Equal(t, string(rune(1)), parts[1])

	id2 := generateID(2)
	parts2 := strings.SplitN(id2, "-", 2)
	assert.Len(t, parts2, 2)
	_, err2 := time.Parse("20060102150405", parts2[0])
	assert.NoError(t, err2)
	assert.Equal(t, string(rune(2)), parts2[1])
}

func TestConcurrentLoggingSafety(t *testing.T) {
	tr := NewTracker()
	var wg sync.WaitGroup
	n := 200
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func() {
			defer wg.Done()
			tr.LogActivity("u", "t", nil)
		}()
	}
	wg.Wait()

	logs := tr.GetActivityByUser("u")
	assert.Len(t, logs, n)

	stats := tr.GetActivityStats("u")
	assert.Equal(t, n, stats.TotalActions)
	assert.Equal(t, 1, stats.UniqueActions)
	assert.Equal(t, n, stats.ActionCounts["t"])
}
