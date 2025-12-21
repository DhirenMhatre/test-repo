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
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
}

func TestLogActivityAndGetActivityByUser(t *testing.T) {
	tr := NewTracker()

	md1 := map[string]interface{}{"ip": "1.2.3.4"}
	md2 := map[string]interface{}{"ip": "5.6.7.8"}
	a1 := tr.LogActivity("u1", "login", md1)
	a2 := tr.LogActivity("u1", "purchase", md2)

	assert.NotNil(t, a1)
	assert.NotNil(t, a2)
	assert.Equal(t, "u1", a1.UserID)
	assert.Equal(t, "login", a1.Action)
	assert.NotEmpty(t, a1.ID)
	assert.True(t, strings.Contains(a1.ID, "-"))
	assert.WithinDuration(t, time.Now(), a1.Timestamp, time.Second)
	assert.Equal(t, md1, a1.Metadata)

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 2)
	assert.Equal(t, "login", logs[0].Action)
	assert.Equal(t, "purchase", logs[1].Action)

	logs[0].Action = "modified"
	logsAgain := tr.GetActivityByUser("u1")
	assert.Equal(t, "login", logsAgain[0].Action)

	none := tr.GetActivityByUser("nope")
	assert.Len(t, none, 0)
}

func TestGetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("nouser")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestGetActivityStats_WithData(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2025, 1, 1, 12, 0, 0, 0, time.UTC)

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "A", Timestamp: base.Add(3 * time.Minute)},
		{ID: "2", UserID: "u1", Action: "B", Timestamp: base.Add(1 * time.Minute)},
		{ID: "3", UserID: "u1", Action: "A", Timestamp: base.Add(2 * time.Minute)},
		{ID: "4", UserID: "u1", Action: "C", Timestamp: base.Add(4 * time.Minute)},
	}
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["A"])
	assert.Equal(t, 1, stats.ActionCounts["B"])
	assert.Equal(t, 1, stats.ActionCounts["C"])
	assert.Equal(t, base.Add(1*time.Minute), stats.FirstActivity)
	assert.Equal(t, base.Add(4*time.Minute), stats.LastActivity)
	assert.Equal(t, "A", stats.MostFrequent)
}

func TestGetActivityByDateRange_Bounds(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2025, 2, 1, 0, 0, 0, 0, time.UTC)

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "tick", Timestamp: base.Add(0 * time.Hour)},
		{ID: "2", UserID: "u1", Action: "tick", Timestamp: base.Add(1 * time.Hour)},
		{ID: "3", UserID: "u1", Action: "tick", Timestamp: base.Add(2 * time.Hour)},
		{ID: "4", UserID: "u1", Action: "tick", Timestamp: base.Add(3 * time.Hour)},
		{ID: "5", UserID: "u1", Action: "tick", Timestamp: base.Add(4 * time.Hour)},
	}
	tr.mu.Unlock()

	start := base.Add(1 * time.Hour)
	end := base.Add(3 * time.Hour)

	got := tr.GetActivityByDateRange("u1", start, end)
	assert.Len(t, got, 3)
	assert.True(t, got[0].Timestamp.Equal(start))
	assert.True(t, got[2].Timestamp.Equal(end))

	none := tr.GetActivityByDateRange("nouser", start, end)
	assert.Len(t, none, 0)

	outside := tr.GetActivityByDateRange("u1", base.Add(5*time.Hour), base.Add(6*time.Hour))
	assert.Len(t, outside, 0)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.mu.Lock()
	tr.activities["charlie"] = []ActivityLog{{ID: "1", UserID: "charlie", Action: "A", Timestamp: time.Now()}}
	tr.activities["alice"] = []ActivityLog{{ID: "2", UserID: "alice", Action: "B", Timestamp: time.Now()}}
	tr.activities["bob"] = []ActivityLog{{ID: "3", UserID: "bob", Action: "C", Timestamp: time.Now()}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "A", Timestamp: time.Now()},
		{ID: "2", UserID: "u1", Action: "B", Timestamp: time.Now()},
	}
	tr.mu.Unlock()

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 0)

	ok2 := tr.DeleteUserActivity("u1")
	assert.False(t, ok2)

	ok3 := tr.DeleteUserActivity("nouser")
	assert.False(t, ok3)
}

func TestGenerateID_Basic(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.True(t, strings.Contains(id1, "-"))
	assert.True(t, strings.Contains(id2, "-"))
	assert.NotEqual(t, id1, id2)
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login":    3,
		"purchase": 1,
		"logout":   2,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}

func TestConcurrent_LogActivity(t *testing.T) {
	tr := NewTracker()
	var wg sync.WaitGroup
	n := 200

	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			tr.LogActivity("u-conc", "A", map[string]interface{}{"i": i})
		}(i)
	}
	wg.Wait()

	logs := tr.GetActivityByUser("u-conc")
	assert.Len(t, logs, n)

	stats := tr.GetActivityStats("u-conc")
	assert.Equal(t, n, stats.TotalActions)
	assert.Equal(t, 1, stats.UniqueActions)
	assert.Equal(t, n, stats.ActionCounts["A"])
}
