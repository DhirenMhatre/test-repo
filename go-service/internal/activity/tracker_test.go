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
	tr.mu.RLock()
	defer tr.mu.RUnlock()
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
	assert.Equal(t, 0, len(tr.activities))
}

func TestTracker_LogActivity_AppendsAndID(t *testing.T) {
	tr := NewTracker()

	md := map[string]interface{}{"k": "v"}
	log1 := tr.LogActivity("u1", "login", md)
	assert.NotNil(t, log1)
	assert.Equal(t, "u1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.NotZero(t, log1.Timestamp)
	assert.NotEmpty(t, log1.ID)

	tr.mu.RLock()
	assert.Equal(t, 1, tr.idCounter)
	assert.Equal(t, 1, len(tr.activities["u1"]))
	tr.mu.RUnlock()

	log2 := tr.LogActivity("u1", "click", nil)
	assert.NotNil(t, log2)
	assert.NotEmpty(t, log2.ID)
	assert.NotEqual(t, log1.ID, log2.ID)

	tr.mu.RLock()
	defer tr.mu.RUnlock()
	assert.Equal(t, 2, tr.idCounter)
	assert.Equal(t, 2, len(tr.activities["u1"]))
}

func TestTracker_GetActivityByUser_CopyIsolation(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 2)

	// mutate returned slice contents
	got[0].Action = "changed"

	// get again and ensure original stored data is unaffected
	gotAgain := tr.GetActivityByUser("u1")
	assert.Equal(t, "a1", gotAgain[0].Action)
	assert.Equal(t, "a2", gotAgain[1].Action)
}

func TestTracker_GetActivityByUser_NonExisting(t *testing.T) {
	tr := NewTracker()
	got := tr.GetActivityByUser("missing")
	assert.NotNil(t, got)
	assert.Len(t, got, 0)
}

func TestTracker_GetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("nouser")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_Computed(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2025, 3, 10, 12, 0, 0, 0, time.UTC)
	t1 := base.Add(-2 * time.Hour)
	t2 := base.Add(-30 * time.Minute)
	t3 := base.Add(45 * time.Minute)

	// Insert deterministic logs directly under lock
	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "login", Timestamp: t1},
		{ID: "2", UserID: "u1", Action: "click", Timestamp: t2},
		{ID: "3", UserID: "u1", Action: "click", Timestamp: t3},
	}
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["click"])
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.True(t, stats.FirstActivity.Equal(t1))
	assert.True(t, stats.LastActivity.Equal(t3))
	assert.Equal(t, "click", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2025, 1, 2, 10, 0, 0, 0, time.UTC)
	t1 := base.Add(-1 * time.Hour)
	t2 := base
	t3 := base.Add(1 * time.Hour)

	tr.mu.Lock()
	tr.activities["u"] = []ActivityLog{
		{ID: "x1", UserID: "u", Action: "a", Timestamp: t1},
		{ID: "x2", UserID: "u", Action: "b", Timestamp: t2},
		{ID: "x3", UserID: "u", Action: "c", Timestamp: t3},
	}
	tr.mu.Unlock()

	// Inclusive bounds: [t2, t3] should return x2 and x3
	got := tr.GetActivityByDateRange("u", t2, t3)
	assert.Equal(t, []string{"x2", "x3"}, idsFrom(got))

	// Inclusive on start and end equals
	got2 := tr.GetActivityByDateRange("u", t1, t1)
	assert.Equal(t, []string{"x1"}, idsFrom(got2))
}

func TestTracker_GetActivityByDateRange_NoUserOrInvalid(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2025, 1, 2, 10, 0, 0, 0, time.UTC)
	start := base
	end := base.Add(1 * time.Hour)

	// No user
	got := tr.GetActivityByDateRange("missing", start, end)
	assert.NotNil(t, got)
	assert.Len(t, got, 0)

	// start > end -> empty
	got2 := tr.GetActivityByDateRange("any", end, start)
	assert.NotNil(t, got2)
	assert.Len(t, got2, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("b", "act", nil)
	tr.LogActivity("a", "act", nil)
	tr.LogActivity("c", "act", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)
	tr.LogActivity("u2", "b1", nil)

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	gotU1 := tr.GetActivityByUser("u1")
	assert.Len(t, gotU1, 0)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)

	// Deleting non-existing user
	ok2 := tr.DeleteUserActivity("nope")
	assert.False(t, ok2)
}

func Test_generateID_SuffixRune(t *testing.T) {
	idA := generateID(65) // 'A'
	idB := generateID(66) // 'B'

	suffixA := idSuffix(idA)
	suffixB := idSuffix(idB)

	assert.Equal(t, "A", suffixA)
	assert.Equal(t, "B", suffixB)
	assert.NotEqual(t, idA, idB)
}

func Test_findMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login": 1,
		"click": 3,
		"view":  2,
	}
	assert.Equal(t, "click", findMostFrequentAction(counts))
}

func idsFrom(a []ActivityLog) []string {
	out := make([]string, len(a))
	for i := range a {
		out[i] = a[i].ID
	}
	return out
}

func idSuffix(id string) string {
	i := strings.LastIndex(id, "-")
	if i == -1 || i == len(id)-1 {
		return ""
	}
	return id[i+1:]
}
