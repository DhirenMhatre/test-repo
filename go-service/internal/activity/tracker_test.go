package activity

import (
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func ts(y, m, d, h, min, s int) time.Time {
	return time.Date(y, time.Month(m), d, h, min, s, 0, time.UTC)
}

func TestNewTracker_Init(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Empty(t, tr.GetAllUsers())
}

func TestTracker_LogActivity_BasicProperties(t *testing.T) {
	tr := NewTracker()
	before := time.Now()
	md := map[string]interface{}{"ip": "1.2.3.4", "ua": "test"}
	log := tr.LogActivity("user1", "login", md)
	after := time.Now()

	assert.NotNil(t, log)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.Equal(t, md, log.Metadata)
	assert.NotEmpty(t, log.ID)
	assert.Contains(t, log.ID, "-")
	assert.False(t, log.Timestamp.Before(before))
	assert.False(t, log.Timestamp.After(after))

	got := tr.GetActivityByUser("user1")
	assert.Len(t, got, 1)
	assert.Equal(t, "login", got[0].Action)
}

func TestTracker_LogActivity_IDUniqueSequential(t *testing.T) {
	tr := NewTracker()
	log1 := tr.LogActivity("u1", "a1", nil)
	log2 := tr.LogActivity("u1", "a2", nil)

	assert.NotEqual(t, log1.ID, log2.ID)
	assert.NotEmpty(t, log1.ID)
	assert.NotEmpty(t, log2.ID)
}

func TestTracker_GetActivityByUser_CopyIndependence(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)
	tr.LogActivity("u2", "b1", nil)

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 2)
	assert.Equal(t, "a1", got[0].Action)
	assert.Equal(t, "a2", got[1].Action)

	// Mutate returned slice and element; it should not affect stored activities
	got = append(got, ActivityLog{UserID: "u1", Action: "SHOULD_NOT_APPEAR"})
	got[0].Action = "modified"

	got2 := tr.GetActivityByUser("u1")
	assert.Len(t, got2, 2)
	assert.Equal(t, "a1", got2[0].Action)
	assert.Equal(t, "a2", got2[1].Action)
}

func TestTracker_GetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("missing")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_NonEmpty(t *testing.T) {
	tr := NewTracker()

	t1 := ts(2024, 1, 1, 10, 0, 0)
	t2 := ts(2024, 1, 2, 11, 0, 0)
	t3 := ts(2024, 1, 3, 12, 0, 0)

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "login", Timestamp: t1},
		{ID: "2", UserID: "u1", Action: "click", Timestamp: t2},
		{ID: "3", UserID: "u1", Action: "click", Timestamp: t3},
	}
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["click"])
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, t1, stats.FirstActivity)
	assert.Equal(t, t3, stats.LastActivity)
	assert.Equal(t, "click", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_InclusiveAndBoundaries(t *testing.T) {
	tr := NewTracker()

	start := ts(2024, 2, 1, 9, 0, 0)
	mid := ts(2024, 2, 1, 12, 0, 0)
	end := ts(2024, 2, 1, 15, 0, 0)

	tr.mu.Lock()
	tr.activities["ua"] = []ActivityLog{
		{ID: "s", UserID: "ua", Action: "S", Timestamp: start},
		{ID: "m", UserID: "ua", Action: "M", Timestamp: mid},
		{ID: "e", UserID: "ua", Action: "E", Timestamp: end},
	}
	tr.mu.Unlock()

	// Inclusive edges: should include all three
	got := tr.GetActivityByDateRange("ua", start, end)
	assert.Len(t, got, 3)

	// From mid to end: should include last two
	got = tr.GetActivityByDateRange("ua", mid, end)
	assert.Len(t, got, 2)
	assert.Equal(t, "M", got[0].Action)
	assert.Equal(t, "E", got[1].Action)

	// From start to mid: should include first two
	got = tr.GetActivityByDateRange("ua", start, mid)
	assert.Len(t, got, 2)
	assert.Equal(t, "S", got[0].Action)
	assert.Equal(t, "M", got[1].Action)

	// Inverted range: no results
	got = tr.GetActivityByDateRange("ua", end, start)
	assert.Empty(t, got)

	// Missing user
	assert.Empty(t, tr.GetActivityByDateRange("missing", start, end))
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["b"] = []ActivityLog{{ID: "1", UserID: "b", Action: "x", Timestamp: ts(2024, 1, 1, 0, 0, 0)}}
	tr.activities["a"] = []ActivityLog{{ID: "2", UserID: "a", Action: "y", Timestamp: ts(2024, 1, 1, 0, 1, 0)}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)
	tr.LogActivity("u2", "b1", nil)

	ok := tr.DeleteUserActivity("missing")
	assert.False(t, ok)

	ok = tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Empty(t, tr.GetActivityByUser("u1"))

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)
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

func Test_generateID_SuffixMatchesCounter(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	id10 := generateID(10)

	assert.True(t, strings.Contains(id1, "-"))
	assert.True(t, strings.HasSuffix(id1, string(rune(1))))
	assert.True(t, strings.HasSuffix(id2, string(rune(2))))
	assert.True(t, strings.HasSuffix(id10, string(rune(10))))
	assert.NotEqual(t, id1, id2)
}

func TestTracker_LogActivity_ConcurrentSafety(t *testing.T) {
	tr := NewTracker()
	const n = 100
	var wg sync.WaitGroup
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			tr.LogActivity("uC", "act", map[string]interface{}{"i": i})
		}(i)
	}
	wg.Wait()

	got := tr.GetActivityByUser("uC")
	assert.Len(t, got, n)
}
