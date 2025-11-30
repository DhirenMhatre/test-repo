package activity

import (
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func mustTime(t testing.TB, y int, mo time.Month, d, h, mi, s int) time.Time {
	t.Helper()
	return time.Date(y, mo, d, h, mi, s, 0, time.UTC)
}

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.Empty(t, tr.GetAllUsers())
}

func TestLogActivity_AssignsIDAndTimestampAndStores(t *testing.T) {
	tr := NewTracker()

	before := time.Now().Add(-1 * time.Second)
	md := map[string]interface{}{"ip": "127.0.0.1", "ua": "test"}
	l1 := tr.LogActivity("u1", "login", md)
	after := time.Now().Add(1 * time.Second)

	assert.NotNil(t, l1)
	assert.NotEmpty(t, l1.ID)
	assert.Equal(t, "u1", l1.UserID)
	assert.Equal(t, "login", l1.Action)
	assert.NotZero(t, l1.Timestamp)
	assert.True(t, (l1.Timestamp.After(before) || l1.Timestamp.Equal(before)) && (l1.Timestamp.Before(after) || l1.Timestamp.Equal(after)))
	assert.Equal(t, md, l1.Metadata)

	// Second log should have a different ID
	l2 := tr.LogActivity("u1", "click", nil)
	assert.NotEqual(t, l1.ID, l2.ID)

	// Verify storage via GetActivityByUser
	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 2)
	assert.Equal(t, "login", logs[0].Action)
	assert.Equal(t, "click", logs[1].Action)
}

func TestGetActivityByUser_EmptyAndCopyIsolation(t *testing.T) {
	tr := NewTracker()

	// No logs yet
	logs := tr.GetActivityByUser("nouser")
	assert.Equal(t, 0, len(logs))

	// Add one log
	_ = tr.LogActivity("userA", "act1", nil)
	got1 := tr.GetActivityByUser("userA")
	assert.Len(t, got1, 1)

	// Mutate returned slice content - should not affect internal storage
	got1[0].Action = "mutated"
	got2 := tr.GetActivityByUser("userA")
	assert.Len(t, got2, 1)
	assert.Equal(t, "act1", got2[0].Action)
}

func TestGetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("nouser")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestGetActivityStats_WithLogs(t *testing.T) {
	tr := NewTracker()

	u := "user1"
	t1 := mustTime(t, 2025, time.January, 1, 9, 0, 0)
	t2 := mustTime(t, 2025, time.January, 1, 10, 0, 0)
	t3 := mustTime(t, 2025, time.January, 1, 11, 0, 0)

	tr.activities[u] = []ActivityLog{
		{ID: "a", UserID: u, Action: "login", Timestamp: t2},
		{ID: "b", UserID: u, Action: "view", Timestamp: t1},
		{ID: "c", UserID: u, Action: "view", Timestamp: t3},
	}

	stats := tr.GetActivityStats(u)
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.True(t, stats.FirstActivity.Equal(t1))
	assert.True(t, stats.LastActivity.Equal(t3))
	assert.Equal(t, "view", stats.MostFrequent)
}

func TestGetActivityByDateRange_InclusiveAndFiltering(t *testing.T) {
	tr := NewTracker()

	u1 := "u1"
	t1 := mustTime(t, 2025, time.February, 1, 9, 0, 0)
	t2 := mustTime(t, 2025, time.February, 1, 10, 0, 0)
	t3 := mustTime(t, 2025, time.February, 1, 11, 0, 0)
	t4 := mustTime(t, 2025, time.February, 1, 12, 0, 0)

	tr.activities[u1] = []ActivityLog{
		{ID: "1", UserID: u1, Action: "A", Timestamp: t1},
		{ID: "2", UserID: u1, Action: "B", Timestamp: t2},
		{ID: "3", UserID: u1, Action: "C", Timestamp: t3},
		{ID: "4", UserID: u1, Action: "D", Timestamp: t4},
	}

	// Inclusive bounds: include t2 and t3 when range [t2, t3]
	got := tr.GetActivityByDateRange(u1, t2, t3)
	assert.Len(t, got, 2)
	assert.Equal(t, "B", got[0].Action)
	assert.Equal(t, "C", got[1].Action)

	// Range outside any logs
	none := tr.GetActivityByDateRange(u1, mustTime(t, 2025, time.February, 2, 0, 0, 0), mustTime(t, 2025, time.February, 2, 23, 59, 59))
	assert.Empty(t, none)

	// Start > End should simply yield empty per implementation
	empty := tr.GetActivityByDateRange(u1, t3, t2)
	assert.Empty(t, empty)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.activities["charlie"] = nil
	tr.activities["alice"] = []ActivityLog{{UserID: "alice", Action: "x"}}
	tr.activities["bob"] = []ActivityLog{{UserID: "bob", Action: "y"}}

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a"},
		{ID: "2", UserID: "u1", Action: "b"},
	}
	tr.activities["u2"] = []ActivityLog{
		{ID: "3", UserID: "u2", Action: "c"},
	}

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Empty(t, tr.GetActivityByUser("u1"))
	assert.Len(t, tr.GetActivityByUser("u2"), 1)

	// Deleting again should return false
	assert.False(t, tr.DeleteUserActivity("u1"))
}

func TestGenerateID_BasicUniquenessAndSuffix(t *testing.T) {
	id1 := generateID(65) // 'A'
	id2 := generateID(66) // 'B'

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.True(t, strings.HasSuffix(id1, "-A"), "id1 suffix should be -A, got: %q", id1)
	assert.True(t, strings.HasSuffix(id2, "-B"), "id2 suffix should be -B, got: %q", id2)
}

func TestFindMostFrequentAction(t *testing.T) {
	// Empty
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// Single
	assert.Equal(t, "login", findMostFrequentAction(map[string]int{"login": 1}))

	// Multiple
	ac := map[string]int{
		"view":     2,
		"click":    5,
		"purchase": 1,
	}
	assert.Equal(t, "click", findMostFrequentAction(ac))
}

func TestConcurrentAccess_NoRace(t *testing.T) {
	tr := NewTracker()
	var wg sync.WaitGroup

	// Writers for same and different users
	users := []string{"uA", "uB", "uC"}
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			u := users[idx%len(users)]
			for j := 0; j < 500; j++ {
				tr.LogActivity(u, "act", nil)
			}
		}(i)
	}

	// Readers
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 500; j++ {
				_ = tr.GetAllUsers()
				_ = tr.GetActivityByUser("uA")
				_ = tr.GetActivityStats("uB")
			}
		}()
	}

	wg.Wait()

	// Sanity: total logs for known users should be at least the writes for those users
	totalWrites := 0
	perUserWrites := map[string]int{"uA": 0, "uB": 0, "uC": 0}
	for i := 0; i < 6; i++ {
		perUserWrites[users[i%len(users)]] += 500
		totalWrites += 500
	}
	gotCount := len(tr.GetActivityByUser("uA")) + len(tr.GetActivityByUser("uB")) + len(tr.GetActivityByUser("uC"))
	assert.Equal(t, totalWrites, gotCount)
}
