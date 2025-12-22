package activity

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_InitialState(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)
	assert.NotNil(t, tk.activities)
	assert.Len(t, tk.activities, 0)
	assert.Equal(t, 0, tk.idCounter)
}

func TestTracker_LogActivity_AppendsAndReturnsCopy(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	meta := map[string]interface{}{"ip": "127.0.0.1", "n": 1}

	start := time.Now()
	logPtr := tk.LogActivity("u1", "login", meta)
	end := time.Now()

	assert.NotNil(t, logPtr)
	assert.Equal(t, "u1", logPtr.UserID)
	assert.Equal(t, "login", logPtr.Action)
	assert.True(t, !logPtr.Timestamp.Before(start) && !logPtr.Timestamp.After(end))

	stored := tk.GetActivityByUser("u1")
	assert.Len(t, stored, 1)
	assert.Equal(t, logPtr.ID, stored[0].ID)
	assert.Equal(t, logPtr.UserID, stored[0].UserID)
	assert.Equal(t, logPtr.Action, stored[0].Action)
	assert.True(t, stored[0].Timestamp.Equal(logPtr.Timestamp))

	assert.NotNil(t, stored[0].Metadata)
	assert.Equal(t, "127.0.0.1", stored[0].Metadata["ip"])
	meta["ip"] = "10.0.0.1"
	stored2 := tk.GetActivityByUser("u1")
	assert.Equal(t, "10.0.0.1", stored2[0].Metadata["ip"])

	origID := stored2[0].ID
	logPtr.ID = "mutated"
	stored3 := tk.GetActivityByUser("u1")
	assert.Equal(t, origID, stored3[0].ID)
}

func TestTracker_LogActivity_IDCounterIncrements(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	l1 := tk.LogActivity("u1", "a1", nil)
	l2 := tk.LogActivity("u1", "a2", nil)

	assert.NotNil(t, l1)
	assert.NotNil(t, l2)
	assert.NotEqual(t, l1.ID, l2.ID)
	assert.Equal(t, 2, tk.idCounter)
}

func TestTracker_GetActivityByUser_NotFoundReturnsEmpty(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	logs := tk.GetActivityByUser("missing")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByUser_ReturnsCopyOfSlice(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	tk.LogActivity("u1", "a1", nil)
	tk.LogActivity("u1", "a2", nil)

	logs1 := tk.GetActivityByUser("u1")
	assert.Len(t, logs1, 2)

	logs1[0].Action = "mutated"
	logs2 := tk.GetActivityByUser("u1")
	assert.Equal(t, "a1", logs2[0].Action)
	assert.Equal(t, "a2", logs2[1].Action)

	logs1 = append(logs1, ActivityLog{UserID: "u1", Action: "a3"})
	logs3 := tk.GetActivityByUser("u1")
	assert.Len(t, logs3, 2)
}

func TestTracker_GetActivityStats_NoUserOrEmpty(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	statsMissing := tk.GetActivityStats("missing")
	assert.NotNil(t, statsMissing)
	assert.Equal(t, 0, statsMissing.TotalActions)
	assert.Equal(t, 0, statsMissing.UniqueActions)
	assert.NotNil(t, statsMissing.ActionCounts)
	assert.Len(t, statsMissing.ActionCounts, 0)

	assert.True(t, statsMissing.FirstActivity.IsZero())
	assert.True(t, statsMissing.LastActivity.IsZero())
	assert.Equal(t, "", statsMissing.MostFrequent)

	tk.mu.Lock()
	tk.activities["u1"] = []ActivityLog{}
	tk.mu.Unlock()

	statsEmpty := tk.GetActivityStats("u1")
	assert.NotNil(t, statsEmpty)
	assert.Equal(t, 0, statsEmpty.TotalActions)
	assert.Equal(t, 0, statsEmpty.UniqueActions)
	assert.NotNil(t, statsEmpty.ActionCounts)
	assert.Len(t, statsEmpty.ActionCounts, 0)

	assert.True(t, statsEmpty.FirstActivity.IsZero())
	assert.True(t, statsEmpty.LastActivity.IsZero())
	assert.Equal(t, "", statsEmpty.MostFrequent)
}

func TestTracker_GetActivityStats_ComputesCountsAndRangeAndMostFrequent(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	user := "u1"
	base := time.Date(2025, 1, 2, 3, 4, 5, 0, time.UTC)

	tk.mu.Lock()
	tk.activities[user] = []ActivityLog{
		{ID: "1", UserID: user, Action: "view", Timestamp: base.Add(2 * time.Hour)},
		{ID: "2", UserID: user, Action: "click", Timestamp: base.Add(1 * time.Hour)},
		{ID: "3", UserID: user, Action: "view", Timestamp: base.Add(3 * time.Hour)},
		{ID: "4", UserID: user, Action: "purchase", Timestamp: base.Add(30 * time.Minute)},
	}
	tk.mu.Unlock()

	stats := tk.GetActivityStats(user)
	assert.NotNil(t, stats)

	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)

	assert.Equal(t, map[string]int{
		"view":     2,
		"click":    1,
		"purchase": 1,
	}, stats.ActionCounts)

	assert.Equal(t, base.Add(30*time.Minute), stats.FirstActivity)
	assert.Equal(t, base.Add(3*time.Hour), stats.LastActivity)
	assert.Equal(t, "view", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_FiltersInclusive(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	user := "u1"
	base := time.Date(2025, 2, 3, 10, 0, 0, 0, time.UTC)

	l0 := ActivityLog{ID: "0", UserID: user, Action: "a", Timestamp: base.Add(-1 * time.Minute)}
	l1 := ActivityLog{ID: "1", UserID: user, Action: "b", Timestamp: base.Add(0 * time.Minute)}
	l2 := ActivityLog{ID: "2", UserID: user, Action: "c", Timestamp: base.Add(1 * time.Minute)}
	l3 := ActivityLog{ID: "3", UserID: user, Action: "d", Timestamp: base.Add(2 * time.Minute)}
	l4 := ActivityLog{ID: "4", UserID: user, Action: "e", Timestamp: base.Add(3 * time.Minute)}
	l5 := ActivityLog{ID: "5", UserID: user, Action: "f", Timestamp: base.Add(-2 * time.Minute)}

	tk.mu.Lock()
	tk.activities[user] = []ActivityLog{l0, l1, l2, l3, l4, l5}
	tk.mu.Unlock()

	start := base.Add(0 * time.Minute)
	end := base.Add(2 * time.Minute)

	filtered := tk.GetActivityByDateRange(user, start, end)
	assert.NotNil(t, filtered)

	// Source preserves insertion order; it does not sort.
	// Based on the inserted slice, IDs in range are: 1,2,3 (and then 5 is out; 0 out; 4 out)
	assert.Len(t, filtered, 3)
	assert.Equal(t, []string{"1", "2", "3"}, []string{filtered[0].ID, filtered[1].ID, filtered[2].ID})
}

func TestTracker_GetActivityByDateRange_UserNotFoundReturnsEmpty(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	start := time.Now().Add(-time.Hour)
	end := time.Now()
	filtered := tk.GetActivityByDateRange("missing", start, end)
	assert.NotNil(t, filtered)
	assert.Len(t, filtered, 0)
}

func TestTracker_GetActivityByDateRange_StartAfterEndReturnsEmpty(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	user := "u1"
	base := time.Date(2025, 3, 4, 12, 0, 0, 0, time.UTC)

	tk.mu.Lock()
	tk.activities[user] = []ActivityLog{
		{ID: "1", UserID: user, Action: "a", Timestamp: base},
	}
	tk.mu.Unlock()

	// Source code does not special-case start > end; it will simply filter out everything.
	start := base.Add(1 * time.Hour)
	end := base.Add(-1 * time.Hour)

	filtered := tk.GetActivityByDateRange(user, start, end)
	assert.NotNil(t, filtered)
	assert.Len(t, filtered, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	tk.LogActivity("charlie", "a", nil)
	tk.LogActivity("alice", "a", nil)
	tk.LogActivity("bob", "a", nil)

	users := tk.GetAllUsers()
	assert.Equal(t, []string{"alice", "bob", "charlie"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	okMissing := tk.DeleteUserActivity("missing")
	assert.False(t, okMissing)

	tk.LogActivity("u1", "a", nil)
	assert.Len(t, tk.GetActivityByUser("u1"), 1)

	ok := tk.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Len(t, tk.GetActivityByUser("u1"), 0)

	okAgain := tk.DeleteUserActivity("u1")
	assert.False(t, okAgain)
}

func TestGenerateID_ContainsTimestampPrefixAndCounterRuneSuffix(t *testing.T) {
	counter := 7
	before := time.Now().Format("20060102150405")
	id := generateID(counter)
	after := time.Now().Format("20060102150405")

	assert.NotEmpty(t, id)

	// Source format: timestamp(14) + "-" + string(rune(counter)) (1 rune; may be multi-byte).
	assert.GreaterOrEqual(t, len(id), len("20060102150405-")+1)
	assert.Equal(t, byte('-'), id[len("20060102150405")])

	prefix := id[:len("20060102150405")]
	assert.True(t, prefix == before || prefix == after, "prefix=%s before=%s after=%s", prefix, before, after)

	wantSuffix := string(rune(counter))
	assert.Equal(t, len("20060102150405-")+len(wantSuffix), len(id))
	assert.Equal(t, wantSuffix, id[len("20060102150405-"):])
}

func TestFindMostFrequentAction(t *testing.T) {
	t.Run("empty map", func(t *testing.T) {
		assert.Equal(t, "", findMostFrequentAction(map[string]int{}))
	})

	t.Run("single element", func(t *testing.T) {
		assert.Equal(t, "view", findMostFrequentAction(map[string]int{"view": 1}))
	})

	t.Run("returns max", func(t *testing.T) {
		m := map[string]int{"a": 2, "b": 5, "c": 4}
		assert.Equal(t, "b", findMostFrequentAction(m))
	})

	t.Run("ties returns one of the max", func(t *testing.T) {
		m := map[string]int{"a": 5, "b": 5, "c": 1}
		got := findMostFrequentAction(m)
		assert.Contains(t, []string{"a", "b"}, got)
	})
}

func TestTracker_ConcurrentLogActivity_NoDataRaceAndCountsMatch(t *testing.T) {
	tk := NewTracker()
	assert.NotNil(t, tk)

	const goroutines = 20
	const perG = 50
	user := "u1"

	var wg sync.WaitGroup
	wg.Add(goroutines)

	for g := 0; g < goroutines; g++ {
		go func(g int) {
			defer wg.Done()
			for i := 0; i < perG; i++ {
				tk.LogActivity(user, fmt.Sprintf("action-%d", i%5), nil)
			}
		}(g)
	}
	wg.Wait()

	logs := tk.GetActivityByUser(user)
	assert.Len(t, logs, goroutines*perG)

	stats := tk.GetActivityStats(user)
	assert.NotNil(t, stats)
	assert.Equal(t, goroutines*perG, stats.TotalActions)
	assert.Equal(t, 5, stats.UniqueActions)
	sum := 0
	for _, c := range stats.ActionCounts {
		sum += c
	}
	assert.Equal(t, stats.TotalActions, sum)
}
