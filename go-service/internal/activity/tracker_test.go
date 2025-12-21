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
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
	assert.Empty(t, tr.GetAllUsers())
}

func TestLogActivity_IncrementsCounterAndStores(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1"}
	before := time.Now()
	al1 := tr.LogActivity("u1", "login", meta)
	after := time.Now()

	assert.Equal(t, "u1", al1.UserID)
	assert.Equal(t, "login", al1.Action)
	assert.Equal(t, meta, al1.Metadata)
	assert.True(t, (al1.Timestamp.Equal(before) || al1.Timestamp.After(before)) && (al1.Timestamp.Equal(after) || al1.Timestamp.Before(after)), "timestamp should be between before and after")

	assert.True(t, strings.HasSuffix(al1.ID, "-"+string(rune(1))), "expected ID to end with -\\x01")

	al2 := tr.LogActivity("u1", "logout", nil)
	assert.True(t, strings.HasSuffix(al2.ID, "-"+string(rune(2))), "expected ID to end with -\\x02")

	// Ensure activities appended for user
	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 2)
	assert.Equal(t, al1.ID, logs[0].ID)
	assert.Equal(t, al2.ID, logs[1].ID)
}

func TestGetActivityByUser_NonExistent(t *testing.T) {
	tr := NewTracker()
	logs := tr.GetActivityByUser("missing")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestGetActivityByUser_DefensiveCopy(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "login", nil)

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 1)
	got[0].Action = "mutated"

	again := tr.GetActivityByUser("u1")
	assert.Equal(t, "login", again[0].Action, "expected defensive copy so mutation should not affect internal state")
}

func TestGetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("none")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestGetActivityStats_Aggregates(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 7, 10, 12, 0, 0, 0, time.UTC)

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "id1", UserID: "u1", Action: "login", Timestamp: base.Add(2 * time.Hour)},
		{ID: "id2", UserID: "u1", Action: "upload", Timestamp: base.Add(1 * time.Hour)},
		{ID: "id3", UserID: "u1", Action: "login", Timestamp: base.Add(3 * time.Hour)},
	}
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["upload"])
	assert.Equal(t, base.Add(1*time.Hour), stats.FirstActivity)
	assert.Equal(t, base.Add(3*time.Hour), stats.LastActivity)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestGetActivityByDateRange_InclusiveBounds(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 8, 1, 0, 0, 0, 0, time.UTC)
	t1 := base.Add(1 * time.Hour)
	t2 := base.Add(2 * time.Hour)
	t3 := base.Add(3 * time.Hour)

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a", Timestamp: t1},
		{ID: "2", UserID: "u1", Action: "b", Timestamp: t2},
		{ID: "3", UserID: "u1", Action: "c", Timestamp: t3},
	}
	tr.mu.Unlock()

	// Inclusive both ends
	got := tr.GetActivityByDateRange("u1", t1, t3)
	assert.Len(t, got, 3)
	assert.Equal(t, "1", got[0].ID)
	assert.Equal(t, "2", got[1].ID)
	assert.Equal(t, "3", got[2].ID)

	// Strictly inside range
	got = tr.GetActivityByDateRange("u1", t1.Add(30*time.Minute), t3.Add(-30*time.Minute))
	assert.Len(t, got, 1)
	assert.Equal(t, "2", got[0].ID)

	// No results
	got = tr.GetActivityByDateRange("u1", t3.Add(1*time.Minute), t3.Add(2*time.Minute))
	assert.Len(t, got, 0)
}

func TestGetActivityByDateRange_NonExistentUser(t *testing.T) {
	tr := NewTracker()
	base := time.Now()
	got := tr.GetActivityByDateRange("none", base, base.Add(1*time.Hour))
	assert.NotNil(t, got)
	assert.Len(t, got, 0)
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["charlie"] = []ActivityLog{{UserID: "charlie"}}
	tr.activities["alice"] = []ActivityLog{{UserID: "alice"}}
	tr.activities["bob"] = []ActivityLog{{UserID: "bob"}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestDeleteUserActivity_Behavior(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a"},
		{ID: "2", UserID: "u1", Action: "b"},
	}
	tr.activities["u2"] = []ActivityLog{
		{ID: "3", UserID: "u2", Action: "c"},
	}
	tr.mu.Unlock()

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	// u1 should be gone
	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 0)

	// u2 remains
	logs2 := tr.GetActivityByUser("u2")
	assert.Len(t, logs2, 1)

	// Deleting missing user returns false
	ok = tr.DeleteUserActivity("u1")
	assert.False(t, ok)
}

func TestGenerateID_FormatAndSuffix(t *testing.T) {
	id1 := generateID(1)
	assert.Len(t, id1, 16)
	assert.True(t, strings.HasSuffix(id1, "-"+string(rune(1))))

	id2 := generateID(2)
	assert.Len(t, id2, 16)
	assert.True(t, strings.HasSuffix(id2, "-"+string(rune(2))))

	// 65 is 'A'
	idA := generateID(65)
	assert.Len(t, idA, 16)
	assert.True(t, strings.HasSuffix(idA, "-A"))
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login":  5,
		"upload": 2,
		"share":  3,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}
