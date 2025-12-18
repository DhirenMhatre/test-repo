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
	assert.Empty(t, tr.GetAllUsers())
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()
	before := time.Now()
	log := tr.LogActivity("u1", "login", map[string]interface{}{"ip": "127.0.0.1"})
	after := time.Now()

	assert.NotNil(t, log)
	assert.Equal(t, "u1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotEmpty(t, log.ID)
	assert.False(t, log.Timestamp.Before(before))
	assert.False(t, log.Timestamp.After(after))

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 1)
	assert.Equal(t, "login", logs[0].Action)
}

func TestTracker_LogActivity_Concurrent(t *testing.T) {
	tr := NewTracker()
	var wg sync.WaitGroup
	n := 100

	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			tr.LogActivity("u1", "act", nil)
		}()
	}
	wg.Wait()

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, n)
}

func TestTracker_GetActivityByUser_CopyIndependence(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a", nil)

	logs1 := tr.GetActivityByUser("u1")
	assert.Len(t, logs1, 1)
	logs1[0].Action = "mutated"

	logs2 := tr.GetActivityByUser("u1")
	assert.Equal(t, "a", logs2[0].Action)
}

func TestTracker_GetActivityByUser_EmptyForUnknown(t *testing.T) {
	tr := NewTracker()
	logs := tr.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("nouser")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, "", stats.MostFrequent)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
}

func TestTracker_GetActivityStats_Computation(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2021, 3, 14, 15, 9, 26, 0, time.UTC)

	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a", Timestamp: base.Add(10 * time.Minute)},
		{ID: "2", UserID: "u1", Action: "b", Timestamp: base.Add(5 * time.Minute)},
		{ID: "3", UserID: "u1", Action: "a", Timestamp: base.Add(20 * time.Minute)},
	}

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["a"])
	assert.Equal(t, 1, stats.ActionCounts["b"])
	assert.Equal(t, base.Add(5*time.Minute), stats.FirstActivity)
	assert.Equal(t, base.Add(20*time.Minute), stats.LastActivity)
	assert.Equal(t, "a", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()
	base := time.Now().Add(-time.Hour)
	start := base
	mid := base.Add(10 * time.Minute)
	end := base.Add(20 * time.Minute)

	tr.activities["u"] = []ActivityLog{
		{ID: "s", UserID: "u", Action: "start", Timestamp: start},
		{ID: "m", UserID: "u", Action: "mid", Timestamp: mid},
		{ID: "e", UserID: "u", Action: "end", Timestamp: end},
	}

	all := tr.GetActivityByDateRange("u", start, end)
	assert.Len(t, all, 3)

	onlyMid := tr.GetActivityByDateRange("u", mid, mid)
	assert.Len(t, onlyMid, 1)
	assert.Equal(t, "mid", onlyMid[0].Action)

	none := tr.GetActivityByDateRange("unknown", start, end)
	assert.Len(t, none, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.activities["b"] = []ActivityLog{{UserID: "b"}}
	tr.activities["c"] = []ActivityLog{{UserID: "c"}}
	tr.activities["a"] = []ActivityLog{{UserID: "a"}}

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	assert.False(t, tr.DeleteUserActivity("nouser"))

	tr.activities["u"] = []ActivityLog{
		{ID: "1", UserID: "u", Action: "x", Timestamp: time.Now()},
		{ID: "2", UserID: "u", Action: "y", Timestamp: time.Now()},
	}
	ok := tr.DeleteUserActivity("u")
	assert.True(t, ok)
	assert.Len(t, tr.GetActivityByUser("u"), 0)
	assert.NotContains(t, tr.GetAllUsers(), "u")

	assert.False(t, tr.DeleteUserActivity("u"))
}

func Test_generateID_SuffixAndLength(t *testing.T) {
	id1 := generateID(1)
	assert.True(t, strings.HasSuffix(id1, "-\x01"))
	assert.Len(t, id1, 16)

	idA := generateID(65)
	assert.True(t, strings.HasSuffix(idA, "-A"))
}

func Test_findMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"a": 2,
		"b": 1,
		"c": 3,
	}
	assert.Equal(t, "c", findMostFrequentAction(counts))
}
