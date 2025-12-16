package activity

import (
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_Init(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Empty(t, tr.activities)
}

func TestLogActivity_SetsFieldsAndStores(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"ip": "127.0.0.1"}
	before := time.Now()
	log := tr.LogActivity("user1", "login", meta)
	after := time.Now()

	assert.NotNil(t, log)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotEmpty(t, log.ID)
	assert.NotNil(t, log.Metadata)
	assert.Equal(t, meta, log.Metadata)
	assert.False(t, log.Timestamp.Before(before))
	assert.False(t, log.Timestamp.After(after))

	// Verify it is stored
	got := tr.GetActivityByUser("user1")
	assert.Len(t, got, 1)
	assert.Equal(t, log.ID, got[0].ID)
	assert.Equal(t, "login", got[0].Action)
}

func TestGetActivityByUser_EmptyAndCopy(t *testing.T) {
	tr := NewTracker()

	// Empty user should return empty slice
	none := tr.GetActivityByUser("unknown")
	assert.NotNil(t, none)
	assert.Len(t, none, 0)

	// Add two logs
	tr.LogActivity("copyuser", "a1", nil)
	tr.LogActivity("copyuser", "a2", nil)

	orig := tr.GetActivityByUser("copyuser")
	assert.Len(t, orig, 2)

	// Modify returned slice - should not affect internal storage
	orig = append(orig, ActivityLog{UserID: "copyuser", Action: "a3"})
	assert.Len(t, orig, 3)

	again := tr.GetActivityByUser("copyuser")
	assert.Len(t, again, 2)

	// Modify element in returned slice - should not affect stored data (struct copy)
	orig[0].Action = "modified"
	after := tr.GetActivityByUser("copyuser")
	assert.Equal(t, "a1", after[0].Action)
}

func TestGetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("nope")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestGetActivityStats_WithLogs(t *testing.T) {
	tr := NewTracker()
	u := "u1"

	// Create 3 logs
	tr.LogActivity(u, "login", nil)
	tr.LogActivity(u, "logout", nil)
	tr.LogActivity(u, "login", nil)

	// Normalize timestamps to controlled values
	base := time.Date(2025, 1, 2, 15, 0, 0, 0, time.UTC)
	tr.mu.Lock()
	tr.activities[u][0].Timestamp = base.Add(-2 * time.Hour)
	tr.activities[u][1].Timestamp = base.Add(3 * time.Hour)
	tr.activities[u][2].Timestamp = base.Add(1 * time.Hour)
	tr.mu.Unlock()

	stats := tr.GetActivityStats(u)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["logout"])
	assert.Equal(t, "login", stats.MostFrequent)
	assert.Equal(t, base.Add(-2*time.Hour), stats.FirstActivity)
	assert.Equal(t, base.Add(3*time.Hour), stats.LastActivity)
}

func TestGetActivityByDateRange_InclusiveAndEmpty(t *testing.T) {
	tr := NewTracker()
	u := "rangeUser"

	// Create logs and then set deterministic timestamps
	tr.LogActivity(u, "a-1h", nil)
	tr.LogActivity(u, "a0h", nil)
	tr.LogActivity(u, "a+1h", nil)
	tr.LogActivity(u, "a+2h", nil)

	base := time.Date(2025, 6, 1, 12, 0, 0, 0, time.UTC)
	tr.mu.Lock()
	tr.activities[u][0].Timestamp = base.Add(-1 * time.Hour)
	tr.activities[u][1].Timestamp = base
	tr.activities[u][2].Timestamp = base.Add(1 * time.Hour)
	tr.activities[u][3].Timestamp = base.Add(2 * time.Hour)
	tr.mu.Unlock()

	// Inclusive boundaries: [base, base+1h]
	got := tr.GetActivityByDateRange(u, base, base.Add(1*time.Hour))
	assert.Len(t, got, 2)
	var actions []string
	for _, l := range got {
		actions = append(actions, l.Action)
	}
	assert.ElementsMatch(t, []string{"a0h", "a+1h"}, actions)

	// Start > end should yield empty result
	got2 := tr.GetActivityByDateRange(u, base.Add(1*time.Hour), base)
	assert.Len(t, got2, 0)

	// Unknown user
	got3 := tr.GetActivityByDateRange("unknown", base, base.Add(time.Hour))
	assert.Len(t, got3, 0)

	// Single exact boundary match (start == end == timestamp)
	got4 := tr.GetActivityByDateRange(u, base, base)
	assert.Len(t, got4, 1)
	assert.Equal(t, "a0h", got4[0].Action)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("b", "x", nil)
	tr.LogActivity("a", "x", nil)
	tr.LogActivity("c", "x", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)

	// After delete, list updates
	tr.DeleteUserActivity("b")
	users2 := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "c"}, users2)
}

func TestDeleteUserActivity_Behavior(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("deluser", "x", nil)

	ok := tr.DeleteUserActivity("deluser")
	assert.True(t, ok)
	assert.Len(t, tr.GetActivityByUser("deluser"), 0)

	ok2 := tr.DeleteUserActivity("missing")
	assert.False(t, ok2)
}

func TestFindMostFrequentAction(t *testing.T) {
	// Empty
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// Unique max
	counts := map[string]int{
		"login":  5,
		"logout": 2,
		"view":   3,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}

func TestGenerateID_FormatAndSuffix(t *testing.T) {
	// Use a counter that maps to a printable rune
	id := generateID(65) // 'A'
	assert.NotEmpty(t, id)
	assert.True(t, strings.Contains(id, "-"))
	parts := strings.Split(id, "-")
	assert.Len(t, parts, 2)
	// Timestamp format length should be 14 (YYYYMMDDHHMMSS)
	assert.Len(t, parts[0], 14)
	assert.Equal(t, "A", parts[1])
}

func TestConcurrency_LogAndRead(t *testing.T) {
	tr := NewTracker()
	u := "conc"
	const n = 200

	var wg sync.WaitGroup
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			tr.LogActivity(u, "act", map[string]interface{}{"i": i})
		}(i)
	}
	wg.Wait()

	got := tr.GetActivityByUser(u)
	assert.Len(t, got, n)
}
