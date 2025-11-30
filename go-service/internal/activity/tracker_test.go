package activity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func lastRune(s string) rune {
	r := []rune(s)
	return r[len(r)-1]
}

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Empty(t, tr.activities)
}

func TestTracker_LogActivity_StoresAndIDIncrements(t *testing.T) {
	tr := NewTracker()

	log1 := tr.LogActivity("u1", "act1", nil)
	assert.NotNil(t, log1)
	assert.Equal(t, "u1", log1.UserID)
	assert.Equal(t, "act1", log1.Action)
	assert.NotEmpty(t, log1.ID)
	assert.Equal(t, rune(1), lastRune(log1.ID))

	log2 := tr.LogActivity("u1", "act2", map[string]interface{}{"k": "v"})
	assert.NotNil(t, log2)
	assert.Equal(t, "u1", log2.UserID)
	assert.Equal(t, "act2", log2.Action)
	assert.NotEmpty(t, log2.ID)
	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, rune(2), lastRune(log2.ID))

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 2)
	assert.Equal(t, "act1", logs[0].Action)
	assert.Equal(t, "act2", logs[1].Action)
}

func TestTracker_GetActivityByUser_ReturnsCopyNotAlias(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 2)

	origFirst := got[0].Action
	got[0].Action = "modified"

	got2 := tr.GetActivityByUser("u1")
	assert.Equal(t, origFirst, got2[0].Action, "mutating returned slice should not affect internal storage")
}

func TestTracker_GetActivityByUser_Unknown(t *testing.T) {
	tr := NewTracker()
	got := tr.GetActivityByUser("unknown")
	assert.NotNil(t, got)
	assert.Len(t, got, 0)
}

func TestTracker_GetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("nouser")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_WithData(t *testing.T) {
	tr := NewTracker()

	log1 := tr.LogActivity("u", "login", nil)
	assert.NotNil(t, log1)
	time.Sleep(1 * time.Millisecond)
	log2 := tr.LogActivity("u", "view", nil)
	assert.NotNil(t, log2)
	time.Sleep(1 * time.Millisecond)
	log3 := tr.LogActivity("u", "login", nil)
	assert.NotNil(t, log3)

	stats := tr.GetActivityStats("u")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.Equal(t, "login", stats.MostFrequent)

	assert.True(t, stats.FirstActivity.Equal(log1.Timestamp))
	assert.True(t, stats.LastActivity.Equal(log3.Timestamp))

	// Ensure stats for a user with no logs remain unaffected
	empty := tr.GetActivityStats("other")
	assert.Equal(t, 0, empty.TotalActions)
	assert.Equal(t, 0, empty.UniqueActions)
	assert.Len(t, empty.ActionCounts, 0)
}

func TestTracker_GetActivityByDateRange(t *testing.T) {
	tr := NewTracker()
	user := "u1"

	l1 := tr.LogActivity(user, "a", nil)
	assert.NotNil(t, l1)
	time.Sleep(1 * time.Millisecond)
	l2 := tr.LogActivity(user, "b", nil)
	assert.NotNil(t, l2)
	time.Sleep(1 * time.Millisecond)
	l3 := tr.LogActivity(user, "c", nil)
	assert.NotNil(t, l3)

	// Inclusive bounds should include all
	all := tr.GetActivityByDateRange(user, l1.Timestamp, l3.Timestamp)
	assert.Len(t, all, 3)

	// Exact timestamp for middle entry
	mid := tr.GetActivityByDateRange(user, l2.Timestamp, l2.Timestamp)
	assert.Len(t, mid, 1)
	assert.Equal(t, "b", mid[0].Action)

	// Reversed range should yield none (no bound swap in implementation)
	none := tr.GetActivityByDateRange(user, l3.Timestamp, l1.Timestamp)
	assert.Len(t, none, 0)

	// Non-existent user
	noneUser := tr.GetActivityByDateRange("nouser", l1.Timestamp, l3.Timestamp)
	assert.Len(t, noneUser, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("charlie", "x", nil)
	tr.LogActivity("alice", "y", nil)
	tr.LogActivity("bob", "z", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	// Deleting non-existent user
	ok := tr.DeleteUserActivity("nouser")
	assert.False(t, ok)

	// Add and delete
	tr.LogActivity("u", "a", nil)
	tr.LogActivity("u", "b", nil)
	assert.Equal(t, 2, len(tr.GetActivityByUser("u")))

	ok = tr.DeleteUserActivity("u")
	assert.True(t, ok)
	assert.Len(t, tr.GetActivityByUser("u"), 0)

	// Delete again should be false
	ok = tr.DeleteUserActivity("u")
	assert.False(t, ok)
}

func Test_generateID_SuffixMatchesCounter(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	assert.Equal(t, rune(1), lastRune(id1))
	assert.Equal(t, rune(2), lastRune(id2))
}

func Test_findMostFrequentAction(t *testing.T) {
	tests := []struct {
		name   string
		input  map[string]int
		expect string
	}{
		{
			name:   "empty",
			input:  map[string]int{},
			expect: "",
		},
		{
			name:   "single",
			input:  map[string]int{"a": 1},
			expect: "a",
		},
		{
			name:   "clear max",
			input:  map[string]int{"a": 2, "b": 1, "c": 1},
			expect: "a",
		},
		{
			name:   "another clear max",
			input:  map[string]int{"login": 5, "view": 3},
			expect: "login",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := findMostFrequentAction(tt.input)
			assert.Equal(t, tt.expect, got)
		})
	}
}
