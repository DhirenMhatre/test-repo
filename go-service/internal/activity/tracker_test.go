package activity

import (
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)

	users := tr.GetAllUsers()
	assert.Equal(t, 0, len(users))

	logs := tr.GetActivityByUser("nonexistent")
	assert.Equal(t, 0, len(logs))

	stats := tr.GetActivityStats("nonexistent")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, "", stats.MostFrequent)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
}

func TestTracker_LogActivity_And_GetActivityByUser_CopyIsolation(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"k": "v"}

	log := tr.LogActivity("u1", "login", meta)
	assert.Equal(t, 1, tr.idCounter)
	assert.Equal(t, "u1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.False(t, log.Timestamp.IsZero())
	assert.NotEmpty(t, log.ID)

	// Get and modify returned slice to ensure isolation (copy semantics)
	logs := tr.GetActivityByUser("u1")
	assert.Equal(t, 1, len(logs))
	assert.Equal(t, "login", logs[0].Action)

	// Modify returned data
	logs[0].Action = "modified"
	logs2 := tr.GetActivityByUser("u1")
	assert.Equal(t, 1, len(logs2))
	assert.Equal(t, "login", logs2[0].Action, "internal slice should not be affected by modifications to returned slice")
}

func TestTracker_GetActivityStats_Computation(t *testing.T) {
	tr := NewTracker()
	t1 := time.Date(2023, 10, 1, 10, 0, 0, 0, time.UTC)
	t2 := t1.Add(10 * time.Minute)
	t3 := t1.Add(30 * time.Minute)

	entries := []ActivityLog{
		{ID: "1", UserID: "u1", Action: "view", Timestamp: t2},
		{ID: "2", UserID: "u1", Action: "click", Timestamp: t3},
		{ID: "3", UserID: "u1", Action: "view", Timestamp: t1},
	}

	tr.mu.Lock()
	tr.activities["u1"] = entries
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["click"])
	assert.True(t, stats.FirstActivity.Equal(t1))
	assert.True(t, stats.LastActivity.Equal(t3))
	assert.Equal(t, "view", stats.MostFrequent)
}

func TestTracker_GetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("none")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 1, 1, 12, 0, 0, 0, time.UTC)

	entries := []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a", Timestamp: base.Add(-2 * time.Hour)},
		{ID: "2", UserID: "u1", Action: "b", Timestamp: base.Add(-1 * time.Hour)}, // start
		{ID: "3", UserID: "u1", Action: "c", Timestamp: base},                     // end
		{ID: "4", UserID: "u1", Action: "d", Timestamp: base.Add(1 * time.Hour)},
	}

	tr.mu.Lock()
	tr.activities["u1"] = entries
	tr.mu.Unlock()

	start := base.Add(-1 * time.Hour)
	end := base
	res := tr.GetActivityByDateRange("u1", start, end)
	if assert.Equal(t, 2, len(res)) {
		assert.True(t, res[0].Timestamp.Equal(start))
		assert.True(t, res[1].Timestamp.Equal(end))
	}
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["userB"] = []ActivityLog{{ID: "1", UserID: "userB", Action: "x", Timestamp: time.Now()}}
	tr.activities["userA"] = []ActivityLog{{ID: "2", UserID: "userA", Action: "y", Timestamp: time.Now()}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"userA", "userB"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "login", Timestamp: time.Now()},
		{ID: "2", UserID: "u1", Action: "click", Timestamp: time.Now()},
	}
	tr.mu.Unlock()

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	logs := tr.GetActivityByUser("u1")
	assert.Equal(t, 0, len(logs))

	// Delete non-existent user
	ok2 := tr.DeleteUserActivity("u1")
	assert.False(t, ok2)
}

func TestGenerateID_UniquenessAndFormat(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEqual(t, id1, id2)
	assert.Contains(t, id1, "-")
	assert.Contains(t, id2, "-")

	// Check prefix length (timestamp) is 14 characters
	parts1 := []rune(id1)
	hyphenIdx := -1
	for i, r := range parts1 {
		if r == '-' {
			hyphenIdx = i
			break
		}
	}
	assert.Equal(t, 14, hyphenIdx)
	assert.Greater(t, len(id1), 15)
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	singleMax := map[string]int{"a": 5, "b": 3}
	assert.Equal(t, "a", findMostFrequentAction(singleMax))

	// Tie case, result should be one of the max keys
	tie := map[string]int{"x": 2, "y": 2}
	res := findMostFrequentAction(tie)
	assert.Contains(t, []string{"x", "y"}, res)
}

func TestTracker_LogActivity_Concurrency(t *testing.T) {
	tr := NewTracker()
	var wg sync.WaitGroup
	n := 100
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			tr.LogActivity("uC", "action", map[string]interface{}{"i": i})
		}(i)
	}
	wg.Wait()

	logs := tr.GetActivityByUser("uC")
	assert.Equal(t, n, len(logs))
}
