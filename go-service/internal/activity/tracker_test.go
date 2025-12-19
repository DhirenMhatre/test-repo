package activity

import (
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	users := tr.GetAllUsers()
	assert.Equal(t, 0, len(users))
}

func TestLogActivity_Basics(t *testing.T) {
	tr := NewTracker()

	before := time.Now()
	log := tr.LogActivity("user1", "login", map[string]interface{}{"ip": "127.0.0.1"})
	after := time.Now()

	assert.NotNil(t, log)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	if assert.NotNil(t, log.Metadata) {
		assert.Equal(t, "127.0.0.1", log.Metadata["ip"])
	}
	assert.NotEmpty(t, log.ID)
	assert.False(t, log.Timestamp.Before(before))
	assert.False(t, log.Timestamp.After(after))

	log2 := tr.LogActivity("user1", "logout", nil)
	assert.NotNil(t, log2)
	assert.NotEmpty(t, log2.ID)
	assert.NotEqual(t, log.ID, log2.ID)

	logs := tr.GetActivityByUser("user1")
	assert.Equal(t, 2, len(logs))
	actions := []string{logs[0].Action, logs[1].Action}
	assert.ElementsMatch(t, []string{"login", "logout"}, actions)
}

func TestGetActivityByUser_UnknownReturnsEmptyAndCopyIndependence(t *testing.T) {
	tr := NewTracker()

	unknown := tr.GetActivityByUser("does-not-exist")
	assert.Equal(t, 0, len(unknown))

	tr.LogActivity("u", "a1", nil)
	tr.LogActivity("u", "a2", nil)

	orig := tr.GetActivityByUser("u")
	assert.Equal(t, 2, len(orig))

	// Modify returned slice and its elements; should not affect internal state (slice and struct are copies).
	orig[0].Action = "modified"
	orig = append(orig, ActivityLog{Action: "new"})

	after := tr.GetActivityByUser("u")
	assert.Equal(t, 2, len(after))
	assert.NotEqual(t, "modified", after[0].Action)
}

func TestGetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("missing")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	if assert.NotNil(t, stats.ActionCounts) {
		assert.Equal(t, 0, len(stats.ActionCounts))
	}
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestGetActivityStats_WithActivities(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("u1", "view", nil)
	tr.LogActivity("u1", "view", nil)
	tr.LogActivity("u1", "click", nil)
	tr.LogActivity("u1", "view", nil)

	logs := tr.GetActivityByUser("u1")
	assert.Equal(t, 4, len(logs))

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	if assert.NotNil(t, stats.ActionCounts) {
		assert.Equal(t, 3, stats.ActionCounts["view"])
		assert.Equal(t, 1, stats.ActionCounts["click"])
	}
	assert.Equal(t, "view", stats.MostFrequent)

	// Validate FirstActivity and LastActivity match min/max timestamps from logs.
	minTS, maxTS := logs[0].Timestamp, logs[0].Timestamp
	for _, lg := range logs[1:] {
		if lg.Timestamp.Before(minTS) {
			minTS = lg.Timestamp
		}
		if lg.Timestamp.After(maxTS) {
			maxTS = lg.Timestamp
		}
	}
	assert.True(t, stats.FirstActivity.Equal(minTS))
	assert.True(t, stats.LastActivity.Equal(maxTS))
}

func TestGetActivityByDateRange_InclusiveAndUnknownUser(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("u2", "a", nil)
	tr.LogActivity("u2", "b", nil)
	tr.LogActivity("u2", "c", nil)

	logs := tr.GetActivityByUser("u2")
	if len(logs) != 3 {
		t.Fatalf("expected 3 logs, got %d", len(logs))
	}

	start := logs[0].Timestamp
	end := logs[1].Timestamp

	inRange := tr.GetActivityByDateRange("u2", start, end)
	assert.Equal(t, 2, len(inRange))
	assert.Equal(t, logs[0].ID, inRange[0].ID)
	assert.Equal(t, logs[1].ID, inRange[1].ID)

	empty := tr.GetActivityByDateRange("unknown", start, end)
	assert.Equal(t, 0, len(empty))
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("bob", "a", nil)
	tr.LogActivity("alice", "a", nil)
	tr.LogActivity("bob", "b", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob"}, users)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	// Non-existent user
	assert.False(t, tr.DeleteUserActivity("nouser"))

	tr.LogActivity("u1", "x", nil)
	tr.LogActivity("u1", "y", nil)
	tr.LogActivity("u2", "z", nil)

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	u1Logs := tr.GetActivityByUser("u1")
	assert.Equal(t, 0, len(u1Logs))

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)

	// Deleting again should return false
	assert.False(t, tr.DeleteUserActivity("u1"))
}

func TestConcurrentLogAndRead(t *testing.T) {
	tr := NewTracker()
	const goroutines = 10
	const perGoroutine = 50

	var wg sync.WaitGroup
	wg.Add(goroutines)
	for g := 0; g < goroutines; g++ {
		go func(id int) {
			defer wg.Done()
			for i := 0; i < perGoroutine; i++ {
				tr.LogActivity("concUser", "act", map[string]interface{}{"g": id, "i": i})
				_ = tr.GetActivityByUser("concUser")
			}
		}(g)
	}
	wg.Wait()

	logs := tr.GetActivityByUser("concUser")
	assert.Equal(t, goroutines*perGoroutine, len(logs))

	stats := tr.GetActivityStats("concUser")
	assert.Equal(t, goroutines*perGoroutine, stats.TotalActions)
	assert.Equal(t, 1, stats.UniqueActions)
	assert.Equal(t, "act", stats.MostFrequent)
}

func Test_generateID_Uniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
}

func Test_findMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	m := map[string]int{
		"a": 1,
		"b": 3,
		"c": 2,
	}
	assert.Equal(t, "b", findMostFrequentAction(m))
}
