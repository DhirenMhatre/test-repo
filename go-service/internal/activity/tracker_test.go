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
	users := tr.GetAllUsers()
	assert.Equal(t, 0, len(users))
}

func TestLogActivity_Basic(t *testing.T) {
	tr := NewTracker()
	md := map[string]interface{}{"ip": "1.2.3.4"}
	before := time.Now()
	log := tr.LogActivity("u1", "login", md)
	after := time.Now()

	assert.NotNil(t, log)
	assert.Equal(t, "u1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotEmpty(t, log.ID)
	assert.True(t, !log.Timestamp.Before(before) && !log.Timestamp.After(after), "timestamp should be between before and after")

	// Verify it was stored and order is preserved
	logs := tr.GetActivityByUser("u1")
	assert.Equal(t, 1, len(logs))
	assert.Equal(t, log.ID, logs[0].ID)

	// Returned slice should be a copy; modifying it should not affect internal state
	logs[0].Action = "changed"
	logs = append(logs, ActivityLog{ID: "x", UserID: "u1"})
	logsAgain := tr.GetActivityByUser("u1")
	assert.Equal(t, 1, len(logsAgain))
	assert.Equal(t, "login", logsAgain[0].Action)
}

func TestGetActivityByUser_EmptyWhenMissing(t *testing.T) {
	tr := NewTracker()
	got := tr.GetActivityByUser("missing")
	assert.Equal(t, 0, len(got))
}

func TestGetActivityByUser_OrderPreserved(t *testing.T) {
	tr := NewTracker()
	a1 := tr.LogActivity("u", "a1", nil)
	time.Sleep(1 * time.Millisecond)
	a2 := tr.LogActivity("u", "a2", nil)

	got := tr.GetActivityByUser("u")
	assert.Equal(t, 2, len(got))
	assert.Equal(t, a1.ID, got[0].ID)
	assert.Equal(t, a2.ID, got[1].ID)
}

func TestGetActivityByDateRange_Inclusive(t *testing.T) {
	tr := NewTracker()
	l1 := tr.LogActivity("u", "a1", nil)
	time.Sleep(2 * time.Millisecond)
	l2 := tr.LogActivity("u", "a2", nil)
	time.Sleep(2 * time.Millisecond)
	l3 := tr.LogActivity("u", "a3", nil)

	// inclusive bounds should include l2 and l3
	got := tr.GetActivityByDateRange("u", l2.Timestamp, l3.Timestamp)
	assert.Equal(t, 2, len(got))
	assert.Equal(t, l2.ID, got[0].ID)
	assert.Equal(t, l3.ID, got[1].ID)

	// Single point inclusive
	got2 := tr.GetActivityByDateRange("u", l1.Timestamp, l1.Timestamp)
	assert.Equal(t, 1, len(got2))
	assert.Equal(t, l1.ID, got2[0].ID)

	// Range with no results
	start := l1.Timestamp.Add(-10 * time.Second)
	end := l1.Timestamp.Add(-5 * time.Second)
	got3 := tr.GetActivityByDateRange("u", start, end)
	assert.Equal(t, 0, len(got3))
}

func TestGetActivityByDateRange_FiltersPerUser(t *testing.T) {
	tr := NewTracker()
	l1 := tr.LogActivity("u1", "a1", nil)
	time.Sleep(1 * time.Millisecond)
	_ = tr.LogActivity("u2", "a2", nil) // different user, in same time range
	time.Sleep(1 * time.Millisecond)
	l3 := tr.LogActivity("u1", "a3", nil)

	got := tr.GetActivityByDateRange("u1", l1.Timestamp, l3.Timestamp)
	assert.Equal(t, 2, len(got))
	assert.Equal(t, l1.ID, got[0].ID)
	assert.Equal(t, l3.ID, got[1].ID)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("b", "x", nil)
	_ = tr.LogActivity("a", "y", nil)
	_ = tr.LogActivity("c", "z", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	// delete non-existent
	ok := tr.DeleteUserActivity("missing")
	assert.False(t, ok)

	// create and delete
	_ = tr.LogActivity("u", "a1", nil)
	_ = tr.LogActivity("u", "a2", nil)

	ok = tr.DeleteUserActivity("u")
	assert.True(t, ok)

	// Should be gone
	assert.Equal(t, 0, len(tr.GetActivityByUser("u")))
	// Not present in users list
	users := tr.GetAllUsers()
	for _, u := range users {
		assert.NotEqual(t, "u", u)
	}
}

func TestGetActivityStats_Empty(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("none")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestGetActivityStats_WithData(t *testing.T) {
	tr := NewTracker()

	// Manually seed out-of-order timestamps to verify min/max selection regardless of order.
	base := time.Date(2025, 1, 1, 10, 0, 0, 0, time.UTC)
	logs := []ActivityLog{
		{ID: "1", UserID: "u", Action: "login", Timestamp: base.Add(2 * time.Hour)},
		{ID: "2", UserID: "u", Action: "purchase", Timestamp: base.Add(1 * time.Hour)},
		{ID: "3", UserID: "u", Action: "login", Timestamp: base.Add(3 * time.Hour)},
	}
	tr.mu.Lock()
	tr.activities["u"] = logs
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["purchase"])
	assert.Equal(t, base.Add(1*time.Hour), stats.FirstActivity)
	assert.Equal(t, base.Add(3*time.Hour), stats.LastActivity)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"a": 2,
		"b": 5,
		"c": 1,
	}
	assert.Equal(t, "b", findMostFrequentAction(counts))
}

func TestGenerateID_Suffix(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.True(t, strings.HasSuffix(id1, "-\x01"), "id1 should end with control char for 1")
	assert.True(t, strings.HasSuffix(id2, "-\x02"), "id2 should end with control char for 2")
	assert.NotEqual(t, id1, id2)
}

func TestConcurrentLogActivity(t *testing.T) {
	tr := NewTracker()
	const n = 200
	var wg sync.WaitGroup
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func() {
			defer wg.Done()
			_ = tr.LogActivity("u", "act", nil)
		}()
	}
	wg.Wait()

	logs := tr.GetActivityByUser("u")
	assert.Equal(t, n, len(logs))

	// Ensure IDs are unique
	seen := make(map[string]struct{}, n)
	for _, l := range logs {
		_, dup := seen[l.ID]
		assert.False(t, dup, "duplicate ID detected: %s", l.ID)
		seen[l.ID] = struct{}{}
	}
}
