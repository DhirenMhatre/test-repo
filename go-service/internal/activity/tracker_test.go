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

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()

	pre := time.Now()
	log1 := tr.LogActivity("u1", "login", nil)
	post := time.Now()

	assert.NotNil(t, log1)
	assert.Equal(t, "u1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.NotEmpty(t, log1.ID)
	assert.True(t, (log1.Timestamp.Equal(pre) || log1.Timestamp.After(pre)) && (log1.Timestamp.Equal(post) || log1.Timestamp.Before(post)), "timestamp not within expected range")
	assert.Equal(t, 1, tr.idCounter)

	log2 := tr.LogActivity("u1", "logout", map[string]interface{}{"ip": "127.0.0.1"})
	assert.NotNil(t, log2)
	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, 2, tr.idCounter)

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 2)
	assert.Contains(t, []string{log1.ID, log2.ID}, logs[0].ID)
	assert.Contains(t, []string{log1.ID, log2.ID}, logs[1].ID)
}

func TestTracker_GetActivityByUser_EmptyAndCopyIsolation(t *testing.T) {
	tr := NewTracker()

	// Empty - should return empty slice, not nil
	empty := tr.GetActivityByUser("missing")
	assert.NotNil(t, empty)
	assert.Len(t, empty, 0)

	// Populate and verify copy isolation
	_ = tr.LogActivity("u1", "act", nil)
	ret1 := tr.GetActivityByUser("u1")
	assert.Len(t, ret1, 1)
	assert.Equal(t, "act", ret1[0].Action)

	// Modify returned slice element - should not affect internal state
	ret1[0].Action = "modified"
	ret2 := tr.GetActivityByUser("u1")
	assert.Equal(t, "act", ret2[0].Action)

	// Append to returned slice - should not affect internal slice length
	ret1 = append(ret1, ActivityLog{Action: "extra"})
	ret3 := tr.GetActivityByUser("u1")
	assert.Len(t, ret3, 1)
}

func TestTracker_GetActivityStats_EmptyAndPopulated(t *testing.T) {
	tr := NewTracker()

	// Empty user
	emptyStats := tr.GetActivityStats("nouser")
	assert.Equal(t, 0, emptyStats.TotalActions)
	assert.Equal(t, 0, emptyStats.UniqueActions)
	assert.NotNil(t, emptyStats.ActionCounts)
	assert.Len(t, emptyStats.ActionCounts, 0)
	assert.Equal(t, "", emptyStats.MostFrequent)

	// Populate deterministic timestamps
	_ = tr.LogActivity("u1", "login", nil)
	_ = tr.LogActivity("u1", "logout", nil)
	_ = tr.LogActivity("u1", "login", nil)
	_ = tr.LogActivity("u1", "view", nil)

	base := time.Date(2024, 1, 2, 3, 4, 5, 0, time.UTC)
	tr.mu.Lock()
	tr.activities["u1"][0].Timestamp = base.Add(30 * time.Minute) // login
	tr.activities["u1"][1].Timestamp = base.Add(10 * time.Minute) // logout - earliest
	tr.activities["u1"][2].Timestamp = base.Add(20 * time.Minute) // login
	tr.activities["u1"][3].Timestamp = base.Add(40 * time.Minute) // view - latest
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["logout"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.Equal(t, base.Add(10*time.Minute), stats.FirstActivity)
	assert.Equal(t, base.Add(40*time.Minute), stats.LastActivity)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 7, 1, 10, 0, 0, 0, time.UTC)

	_ = tr.LogActivity("u1", "a0", nil)  // +0m
	_ = tr.LogActivity("u1", "a10", nil) // +10m
	_ = tr.LogActivity("u1", "a20", nil) // +20m
	_ = tr.LogActivity("u1", "a30", nil) // +30m
	tr.mu.Lock()
	tr.activities["u1"][0].Timestamp = base
	tr.activities["u1"][1].Timestamp = base.Add(10 * time.Minute)
	tr.activities["u1"][2].Timestamp = base.Add(20 * time.Minute)
	tr.activities["u1"][3].Timestamp = base.Add(30 * time.Minute)
	tr.mu.Unlock()

	// Inclusive range [10m, 20m] should include both a10 and a20
	filtered := tr.GetActivityByDateRange("u1", base.Add(10*time.Minute), base.Add(20*time.Minute))
	assert.Len(t, filtered, 2)
	got := map[string]bool{}
	for _, l := range filtered {
		got[l.Action] = true
	}
	assert.True(t, got["a10"])
	assert.True(t, got["a20"])

	// Empty for missing user
	none := tr.GetActivityByDateRange("missing", base, base.Add(1*time.Hour))
	assert.NotNil(t, none)
	assert.Len(t, none, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("b", "act", nil)
	_ = tr.LogActivity("a", "act", nil)
	_ = tr.LogActivity("c", "act", nil)
	_ = tr.LogActivity("a", "act2", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("u1", "a1", nil)
	_ = tr.LogActivity("u1", "a2", nil)
	_ = tr.LogActivity("u2", "b1", nil)

	// Delete existing user
	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Len(t, tr.GetActivityByUser("u1"), 0)

	// Delete again - should return false
	ok = tr.DeleteUserActivity("u1")
	assert.False(t, ok)

	// Delete non-existent
	ok = tr.DeleteUserActivity("nouser")
	assert.False(t, ok)

	// Ensure other user untouched
	assert.Len(t, tr.GetActivityByUser("u2"), 1)
}

func TestGenerateID_FormatAndSuffix(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	parts1 := strings.SplitN(id1, "-", 2)
	parts2 := strings.SplitN(id2, "-", 2)
	assert.Len(t, parts1, 2)
	assert.Len(t, parts2, 2)

	// Prefix should be formatted as 14 chars "YYYYMMDDHHMMSS"
	assert.Len(t, parts1[0], 14)
	assert.Len(t, parts2[0], 14)

	// Suffix equals string(rune(counter))
	assert.Equal(t, string(rune(1)), parts1[1])
	assert.Equal(t, string(rune(2)), parts2[1])
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	m := map[string]int{"a": 1}
	assert.Equal(t, "a", findMostFrequentAction(m))

	m2 := map[string]int{"login": 3, "logout": 1, "view": 2}
	assert.Equal(t, "login", findMostFrequentAction(m2))
}

func TestTracker_ConcurrentLogging(t *testing.T) {
	tr := NewTracker()
	var wg sync.WaitGroup
	const goroutines = 5
	const perG = 20

	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			for j := 0; j < perG; j++ {
				_ = tr.LogActivity("user", "act", map[string]interface{}{"g": idx, "n": j})
			}
		}(i)
	}
	wg.Wait()

	logs := tr.GetActivityByUser("user")
	assert.Len(t, logs, goroutines*perG)
}

func TestTracker_MetadataRetention(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"k": "v"}
	_ = tr.LogActivity("u", "a", meta)

	// Mutate original map after logging
	meta["k"] = "changed"

	logs := tr.GetActivityByUser("u")
	assert.Len(t, logs, 1)
	val, ok := logs[0].Metadata["k"]
	assert.True(t, ok)
	assert.Equal(t, "changed", val)
}
