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
	assert.Empty(t, tr.GetAllUsers())
	assert.Empty(t, tr.GetActivityByUser("missing"))
}

func TestLogActivity_StoresAndReturns(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1"}
	log1 := tr.LogActivity("u1", "login", meta)
	assert.NotNil(t, log1)
	assert.Equal(t, "u1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.NotEmpty(t, log1.ID)
	assert.False(t, log1.Timestamp.IsZero())

	log2 := tr.LogActivity("u1", "click", nil)
	assert.NotNil(t, log2)
	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, 2, tr.idCounter)

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 2)
	assert.Equal(t, "login", logs[0].Action)
	assert.Equal(t, "click", logs[1].Action)
}

func TestGetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)

	orig := tr.GetActivityByUser("u1")
	assert.Len(t, orig, 2)

	// Modify returned slice and element; tracker should not be affected (slice and struct copy).
	orig[0].Action = "mutated"
	orig = append(orig, ActivityLog{UserID: "u1", Action: "extra"})
	again := tr.GetActivityByUser("u1")

	assert.Len(t, again, 2)
	assert.Equal(t, "a1", again[0].Action)
	assert.Equal(t, "a2", again[1].Action)
}

func TestGetActivityStats_EmptyUser(t *testing.T) {
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

func TestGetActivityStats_WithData(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 6, 1, 10, 0, 0, 0, time.UTC)

	// Inject deterministic logs with known timestamps.
	logs := []ActivityLog{
		{ID: "1", UserID: "u1", Action: "login", Timestamp: base},
		{ID: "2", UserID: "u1", Action: "click", Timestamp: base.Add(1 * time.Hour)},
		{ID: "3", UserID: "u1", Action: "login", Timestamp: base.Add(2 * time.Hour)},
		{ID: "4", UserID: "u1", Action: "purchase", Timestamp: base.Add(3 * time.Hour)},
	}
	tr.mu.Lock()
	tr.activities["u1"] = append([]ActivityLog(nil), logs...)
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["click"])
	assert.Equal(t, 1, stats.ActionCounts["purchase"])
	assert.True(t, stats.FirstActivity.Equal(base))
	assert.True(t, stats.LastActivity.Equal(base.Add(3*time.Hour)))
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestGetActivityByDateRange_Various(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2025, 1, 2, 3, 0, 0, 0, time.UTC)
	u := "u-range"

	// Inject deterministic logs.
	logs := []ActivityLog{
		{ID: "a", UserID: u, Action: "a0", Timestamp: base},
		{ID: "b", UserID: u, Action: "a1", Timestamp: base.Add(1 * time.Hour)},
		{ID: "c", UserID: u, Action: "a2", Timestamp: base.Add(2 * time.Hour)},
	}
	tr.mu.Lock()
	tr.activities[u] = append([]ActivityLog(nil), logs...)
	tr.mu.Unlock()

	tests := []struct {
		name    string
		start   time.Time
		end     time.Time
		wantIDs []string
	}{
		{"all-inclusive", base, base.Add(2 * time.Hour), []string{"a", "b", "c"}},
		{"middle-two", base.Add(30 * time.Minute), base.Add(2 * time.Hour), []string{"b", "c"}},
		{"single-exact", base.Add(1 * time.Hour), base.Add(1 * time.Hour), []string{"b"}},
		{"start-eq-first", base, base.Add(1 * time.Hour), []string{"a", "b"}},
		{"end-before-start", base.Add(2 * time.Hour), base.Add(1 * time.Hour), []string{}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tr.GetActivityByDateRange(u, tc.start, tc.end)
			if len(tc.wantIDs) == 0 {
				assert.Empty(t, got)
				return
			}
			assert.Len(t, got, len(tc.wantIDs))
			for i := range got {
				assert.Equal(t, tc.wantIDs[i], got[i].ID)
			}
		})
	}

	// Unknown user
	none := tr.GetActivityByDateRange("missing", base, base.Add(1*time.Hour))
	assert.Empty(t, none)
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
	tr.LogActivity("u1", "login", nil)
	tr.LogActivity("u2", "login", nil)
	tr.LogActivity("u1", "click", nil)

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Empty(t, tr.GetActivityByUser("u1"))

	// Other user remains
	u2logs := tr.GetActivityByUser("u2")
	assert.Len(t, u2logs, 1)
	assert.Equal(t, "login", u2logs[0].Action)

	// Deleting again should return false
	assert.False(t, tr.DeleteUserActivity("u1"))

	// Deleting non-existent user should return false
	assert.False(t, tr.DeleteUserActivity("missing"))
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"a": 3,
		"b": 1,
		"c": 2,
	}
	assert.Equal(t, "a", findMostFrequentAction(counts))
}

func TestGenerateID(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.True(t, strings.Contains(id1, "-"))
}

func TestConcurrentLogActivity(t *testing.T) {
	tr := NewTracker()

	const (
		goroutines = 10
		perG       = 100
	)
	var wg sync.WaitGroup
	wg.Add(goroutines)
	for i := 0; i < goroutines; i++ {
		go func(i int) {
			defer wg.Done()
			for j := 0; j < perG; j++ {
				tr.LogActivity("u-concurrent", "act", nil)
			}
		}(i)
	}
	wg.Wait()

	logs := tr.GetActivityByUser("u-concurrent")
	assert.Len(t, logs, goroutines*perG)
}
