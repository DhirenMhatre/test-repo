package activity

import (
	"sort"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
	assert.Len(t, tr.activities, 0)
}

func TestTracker_LogActivity_StoresAndIDCounter(t *testing.T) {
	tr := NewTracker()
	metadata := map[string]interface{}{"ip": "127.0.0.1"}

	log1 := tr.LogActivity("u1", "login", metadata)
	assert.NotNil(t, log1)
	assert.Equal(t, "u1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.Equal(t, "127.0.0.1", log1.Metadata["ip"])
	assert.False(t, log1.Timestamp.IsZero())

	// idCounter should be incremented
	c1 := tr.idCounter
	assert.GreaterOrEqual(t, c1, 1)
	assert.NotEmpty(t, log1.ID)
	assert.Equal(t, rune(c1), lastRune(log1.ID))

	// Second activity increments counter and generates a distinct ID
	log2 := tr.LogActivity("u1", "click", nil)
	c2 := tr.idCounter
	assert.Equal(t, c1+1, c2)
	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, rune(c2), lastRune(log2.ID))

	// Stored logs present
	stored := tr.GetActivityByUser("u1")
	assert.Len(t, stored, 2)
	assert.Equal(t, "login", stored[0].Action)
	assert.Equal(t, "click", stored[1].Action)
}

func TestTracker_LogActivity_ReturnedLogIsIndependent(t *testing.T) {
	tr := NewTracker()
	ret := tr.LogActivity("u1", "login", map[string]interface{}{"k": "v"})
	assert.NotNil(t, ret)
	assert.Equal(t, "login", ret.Action)

	// Mutate returned pointer; stored log should not change
	ret.Action = "modified"
	stored := tr.GetActivityByUser("u1")
	assert.Len(t, stored, 1)
	assert.Equal(t, "login", stored[0].Action)
}

func TestTracker_GetActivityByUser_EmptyAndCopyIsolation(t *testing.T) {
	tr := NewTracker()

	// Empty for unknown user
	logs := tr.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)

	// Copy isolation
	tr.LogActivity("u1", "a1", nil)
	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 1)
	got[0].Action = "changed"

	got2 := tr.GetActivityByUser("u1")
	assert.Len(t, got2, 1)
	assert.Equal(t, "a1", got2[0].Action)
}

func TestTracker_GetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("u1")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.Equal(t, "", stats.MostFrequent)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
}

func TestTracker_GetActivityStats_Computed(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("u1", "A", nil)
	tr.LogActivity("u1", "B", nil)
	tr.LogActivity("u1", "A", nil)

	// Set deterministic timestamps
	base := time.Date(2025, 1, 2, 15, 4, 5, 0, time.UTC)
	t1 := base.Add(-2 * time.Hour)
	t2 := base.Add(-1 * time.Hour)
	t3 := base

	tr.mu.Lock()
	logs := tr.activities["u1"]
	logs[0].Timestamp = t1
	logs[1].Timestamp = t2
	logs[2].Timestamp = t3
	tr.activities["u1"] = logs
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["A"])
	assert.Equal(t, 1, stats.ActionCounts["B"])
	assert.Equal(t, t1, stats.FirstActivity)
	assert.Equal(t, t3, stats.LastActivity)
	assert.Equal(t, "A", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_InclusiveBoundsAndFiltering(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "A", nil)
	tr.LogActivity("u1", "B", nil)
	tr.LogActivity("u1", "C", nil)

	// Assign exact timestamps
	base := time.Date(2025, 2, 10, 10, 0, 0, 0, time.UTC)
	t1 := base.Add(-30 * time.Minute) // out of range
	t2 := base                        // start
	t3 := base.Add(30 * time.Minute)  // middle
	t4 := base.Add(60 * time.Minute)  // end
	t5 := base.Add(90 * time.Minute)  // out of range

	tr.mu.Lock()
	u1 := tr.activities["u1"]
	// Ensure we have 3 logs as expected
	assert.Len(t, u1, 3)
	u1[0].Timestamp = t2
	u1[1].Timestamp = t4
	u1[2].Timestamp = t3
	tr.activities["u1"] = u1
	tr.mu.Unlock()

	// Add a different user outside range to ensure filtering by user works
	tr.LogActivity("u2", "X", nil)
	tr.mu.Lock()
	u2 := tr.activities["u2"]
	u2[0].Timestamp = t5
	tr.activities["u2"] = u2
	tr.mu.Unlock()

	// Range [t2, t4] inclusive should include t2, t3, t4
	filtered := tr.GetActivityByDateRange("u1", t2, t4)
	assert.Len(t, filtered, 3)

	// Validate included timestamps set
	ts := make([]time.Time, 0, len(filtered))
	for _, l := range filtered {
		ts = append(ts, l.Timestamp)
	}
	sort.Slice(ts, func(i, j int) bool { return ts[i].Before(ts[j]) })
	assert.Equal(t, []time.Time{t2, t3, t4}, ts)

	// Range excluding boundaries: (t2+1ns, t4-1ns) -> only t3
	filtered2 := tr.GetActivityByDateRange("u1", t2.Add(1), t4.Add(-1))
	assert.Len(t, filtered2, 1)
	assert.Equal(t, t3, filtered2[0].Timestamp)

	// Unknown user yields empty slice
	none := tr.GetActivityByDateRange("unknown", t2, t4)
	assert.NotNil(t, none)
	assert.Len(t, none, 0)
}

func TestTracker_GetAllUsers_SortedAndUnique(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("c", "act", nil)
	tr.LogActivity("a", "act", nil)
	tr.LogActivity("b", "act", nil)
	tr.LogActivity("a", "act2", nil)

	users := tr.GetAllUsers()
	assert.True(t, sort.StringsAreSorted(users))
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestTracker_DeleteUserActivity_Behavior(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "A", nil)
	tr.LogActivity("u1", "B", nil)
	tr.LogActivity("u2", "C", nil)

	// Delete existing user
	deleted := tr.DeleteUserActivity("u1")
	assert.True(t, deleted)
	assert.Len(t, tr.GetActivityByUser("u1"), 0)

	// Other user's data remains
	assert.Len(t, tr.GetActivityByUser("u2"), 1)

	// Delete non-existent user
	deleted2 := tr.DeleteUserActivity("unknown")
	assert.False(t, deleted2)

	// Users list should not include u1
	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)
}

func TestGenerateID_SuffixRune(t *testing.T) {
	// Using several counters including non-printable and typical ASCII
	counters := []int{1, 2, 10, 65}
	for _, c := range counters {
		id := generateID(c)
		assert.NotEmpty(t, id)
		assert.Equal(t, rune(c), lastRune(id))
	}
}

func TestFindMostFrequentAction(t *testing.T) {
	tests := []struct {
		name   string
		input  map[string]int
		expect []string // allow multiple in tie
	}{
		{
			name:   "empty",
			input:  map[string]int{},
			expect: []string{""},
		},
		{
			name: "unique max",
			input: map[string]int{
				"a": 1,
				"b": 3,
				"c": 2,
			},
			expect: []string{"b"},
		},
		{
			name: "tie",
			input: map[string]int{
				"x": 2,
				"y": 2,
			},
			expect: []string{"x", "y"},
		},
	}
	for _, tt := range tests {
		got := findMostFrequentAction(tt.input)
		assert.Contains(t, tt.expect, got, tt.name)
	}
}

// helper to extract the last rune from a string
func lastRune(s string) rune {
	rs := []rune(s)
	return rs[len(rs)-1]
}
