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
	assert.Equal(t, 0, tr.idCounter)

	users := tr.GetAllUsers()
	assert.NotNil(t, users)
	assert.Len(t, users, 0)

	acts := tr.GetActivityByUser("nope")
	assert.NotNil(t, acts)
	assert.Len(t, acts, 0)
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()

	md := map[string]interface{}{"ip": "127.0.0.1", "device": "mobile"}
	al := tr.LogActivity("user1", "login", md)
	assert.NotNil(t, al)
	assert.NotEmpty(t, al.ID)
	assert.Equal(t, "user1", al.UserID)
	assert.Equal(t, "login", al.Action)
	assert.False(t, al.Timestamp.IsZero())
	assert.Equal(t, md, al.Metadata)

	// Ensure activity stored
	got := tr.GetActivityByUser("user1")
	assert.Len(t, got, 1)
	assert.Equal(t, al.ID, got[0].ID)
	assert.Equal(t, "login", got[0].Action)

	// Log another, idCounter must increment and IDs should be different
	al2 := tr.LogActivity("user1", "click", nil)
	assert.NotNil(t, al2)
	assert.NotEqual(t, al.ID, al2.ID)
	assert.Equal(t, 2, tr.idCounter)
}

func TestTracker_GetActivityByUser_EmptyAndCopyBehavior(t *testing.T) {
	tr := NewTracker()

	empty := tr.GetActivityByUser("unknown")
	assert.NotNil(t, empty)
	assert.Len(t, empty, 0)

	// Add an activity
	first := tr.LogActivity("u1", "view", nil)
	assert.NotNil(t, first)

	ret := tr.GetActivityByUser("u1")
	assert.Len(t, ret, 1)
	assert.Equal(t, "view", ret[0].Action)

	// Mutate returned slice and ensure internal state isn't affected (copy semantics)
	ret[0].Action = "hacked"
	retAgain := tr.GetActivityByUser("u1")
	assert.Len(t, retAgain, 1)
	assert.Equal(t, "view", retAgain[0].Action)
}

func TestTracker_GetActivityStats_Empty(t *testing.T) {
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

func TestTracker_GetActivityStats_CountsAndTimesAndMostFrequent(t *testing.T) {
	tr := NewTracker()

	// Log three activities then fix timestamps deterministically
	_ = tr.LogActivity("u1", "login", nil)
	_ = tr.LogActivity("u1", "purchase", nil)
	_ = tr.LogActivity("u1", "login", nil)

	// Adjust timestamps to known values
	base := time.Now().Add(-2 * time.Hour)
	tr.mu.Lock()
	tr.activities["u1"][0].Timestamp = base.Add(30 * time.Minute) // 30m
	tr.activities["u1"][1].Timestamp = base.Add(10 * time.Minute) // 10m (earliest)
	tr.activities["u1"][2].Timestamp = base.Add(90 * time.Minute) // 90m (latest)
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["purchase"])
	assert.Equal(t, base.Add(10*time.Minute).Unix(), stats.FirstActivity.Unix())
	assert.Equal(t, base.Add(90*time.Minute).Unix(), stats.LastActivity.Unix())
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_InclusiveFilter(t *testing.T) {
	tr := NewTracker()

	// Create user and activities
	_ = tr.LogActivity("u1", "a_out_before", nil)
	_ = tr.LogActivity("u1", "b_start", nil)
	_ = tr.LogActivity("u1", "c_inside", nil)
	_ = tr.LogActivity("u1", "d_end", nil)
	_ = tr.LogActivity("u1", "e_out_after", nil)

	// Fix timestamps deterministically
	now := time.Now()
	start := now.Add(-1 * time.Hour)
	end := now.Add(1 * time.Hour)

	tr.mu.Lock()
	logs := tr.activities["u1"]
	// Order: out_before < start < inside < end < out_after
	logs[0].Timestamp = start.Add(-10 * time.Minute) // outside before
	logs[1].Timestamp = start                        // exactly start
	logs[2].Timestamp = start.Add(10 * time.Minute)  // inside
	logs[3].Timestamp = end                          // exactly end
	logs[4].Timestamp = end.Add(10 * time.Minute)    // outside after
	tr.activities["u1"] = logs
	tr.mu.Unlock()

	filtered := tr.GetActivityByDateRange("u1", start, end)
	// Should include b_start, c_inside, d_end
	assert.Len(t, filtered, 3)
	actions := make(map[string]bool)
	for _, l := range filtered {
		actions[l.Action] = true
	}
	assert.True(t, actions["b_start"])
	assert.True(t, actions["c_inside"])
	assert.True(t, actions["d_end"])
	assert.False(t, actions["a_out_before"])
	assert.False(t, actions["e_out_after"])
}

func TestTracker_GetActivityByDateRange_UnknownUser(t *testing.T) {
	tr := NewTracker()
	now := time.Now()
	filtered := tr.GetActivityByDateRange("nope", now.Add(-time.Hour), now.Add(time.Hour))
	assert.NotNil(t, filtered)
	assert.Len(t, filtered, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("charlie", "x", nil)
	_ = tr.LogActivity("alice", "y", nil)
	_ = tr.LogActivity("bob", "z", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity_Behavior(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("u1", "x", nil)
	_ = tr.LogActivity("u1", "y", nil)
	_ = tr.LogActivity("u2", "z", nil)

	// Delete non-existent
	ok := tr.DeleteUserActivity("nouser")
	assert.False(t, ok)

	// Delete existing
	ok = tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	acts := tr.GetActivityByUser("u1")
	assert.Len(t, acts, 0)

	// Only u2 remains
	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)

	// Deleting again should return false
	assert.False(t, tr.DeleteUserActivity("u1"))
}

func Test_findMostFrequentAction(t *testing.T) {
	// Empty
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// Single
	assert.Equal(t, "a", findMostFrequentAction(map[string]int{"a": 1}))

	// Multiple with clear winner
	counts := map[string]int{"login": 5, "purchase": 2, "click": 3}
	mf := findMostFrequentAction(counts)
	assert.Equal(t, "login", mf)
}

func Test_generateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	// Validate layout: "<YYYYMMDDhhmmss>-<rune>"
	parts := strings.Split(id1, "-")
	assert.Len(t, parts, 2)
	ts := parts[0]
	_, err := time.Parse("20060102150405", ts)
	assert.NoError(t, err)

	// Suffix should be exactly 1 rune constructed from the counter
	assert.True(t, strings.HasSuffix(id1, string(rune(1))))
	assert.True(t, strings.HasSuffix(id2, string(rune(2))))
}

func TestTracker_ConcurrentLogActivity(t *testing.T) {
	tr := NewTracker()
	const n = 50

	var wg sync.WaitGroup
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			_ = tr.LogActivity("userC", "action", map[string]interface{}{"n": i})
		}(i)
	}
	wg.Wait()

	logs := tr.GetActivityByUser("userC")
	assert.Len(t, logs, n)
	// Ensure IDs are unique
	seen := make(map[string]bool)
	for _, l := range logs {
		if seen[l.ID] {
			t.Fatalf("duplicate ID detected: %s", l.ID)
		}
		seen[l.ID] = true
	}
}
