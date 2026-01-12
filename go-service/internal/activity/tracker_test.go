package activity

import (
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
	meta := map[string]interface{}{"ip": "127.0.0.1"}

	log := tr.LogActivity("user1", "login", meta)

	assert.NotNil(t, log)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.Equal(t, meta, log.Metadata)
	assert.NotEmpty(t, log.ID)
	assert.False(t, log.Timestamp.IsZero())

	// Ensure it was stored
	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 1)
	assert.Equal(t, log.ID, logs[0].ID)
}

func TestTracker_LogActivity_IDCounterIncrements(t *testing.T) {
	tr := NewTracker()

	log1 := tr.LogActivity("user1", "a1", nil)
	log2 := tr.LogActivity("user1", "a2", nil)

	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, 2, tr.idCounter)
}

func TestTracker_GetActivityByUser_EmptyForUnknownUser(t *testing.T) {
	tr := NewTracker()

	logs := tr.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("user1", "a1", nil)
	tr.LogActivity("user1", "a2", nil)

	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 2)

	// Mutate returned slice and ensure internal state is not affected
	logs[0].Action = "modified"

	internal := tr.GetActivityByUser("user1")
	assert.Equal(t, "a1", internal[0].Action)
}

func TestTracker_GetActivityStats_NoActivity(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("user1")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_WithActivities(t *testing.T) {
	tr := NewTracker()

	// We control timestamps by directly setting them after logging
	log1 := tr.LogActivity("user1", "login", nil)
	log2 := tr.LogActivity("user1", "click", nil)
	log3 := tr.LogActivity("user1", "click", nil)
	log4 := tr.LogActivity("user1", "logout", nil)

	// Ensure timestamps are in some order; adjust if needed
	now := time.Now()
	tr.mu.Lock()
	logs := tr.activities["user1"]
	logs[0].Timestamp = now.Add(-10 * time.Minute)
	logs[1].Timestamp = now.Add(-5 * time.Minute)
	logs[2].Timestamp = now.Add(-3 * time.Minute)
	logs[3].Timestamp = now.Add(-1 * time.Minute)
	tr.activities["user1"] = logs
	tr.mu.Unlock()

	stats := tr.GetActivityStats("user1")

	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, 2, stats.ActionCounts["click"])
	assert.Equal(t, 1, stats.ActionCounts["logout"])
	assert.Equal(t, "click", stats.MostFrequent)

	assert.WithinDuration(t, now.Add(-10*time.Minute), stats.FirstActivity, time.Second)
	assert.WithinDuration(t, now.Add(-1*time.Minute), stats.LastActivity, time.Second)
}

func TestTracker_GetActivityStats_MultipleUsersIsolation(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("user1", "login", nil)
	tr.LogActivity("user2", "login", nil)
	tr.LogActivity("user1", "click", nil)

	stats1 := tr.GetActivityStats("user1")
	stats2 := tr.GetActivityStats("user2")

	assert.Equal(t, 2, stats1.TotalActions)
	assert.Equal(t, 1, stats2.TotalActions)
	assert.Equal(t, 2, len(stats1.ActionCounts))
	assert.Equal(t, 1, len(stats2.ActionCounts))
}

func TestTracker_GetActivityByDateRange_NoUser(t *testing.T) {
	tr := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now()

	res := tr.GetActivityByDateRange("unknown", start, end)
	assert.NotNil(t, res)
	assert.Len(t, res, 0)
}

func TestTracker_GetActivityByDateRange_FiltersCorrectly(t *testing.T) {
	tr := NewTracker()
	userID := "user1"
	now := time.Now()

	// Create logs and then override timestamps for determinism
	tr.LogActivity(userID, "a1", nil) // will become t1
	tr.LogActivity(userID, "a2", nil) // t2
	tr.LogActivity(userID, "a3", nil) // t3

	tr.mu.Lock()
	logs := tr.activities[userID]
	t1 := now.Add(-3 * time.Hour)
	t2 := now.Add(-2 * time.Hour)
	t3 := now.Add(-1 * time.Hour)
	logs[0].Timestamp = t1
	logs[1].Timestamp = t2
	logs[2].Timestamp = t3
	tr.activities[userID] = logs
	tr.mu.Unlock()

	tests := []struct {
		name      string
		start     time.Time
		end       time.Time
		wantIDs   []string
		wantCount int
	}{
		{
			name:      "full range includes all",
			start:     t1,
			end:       t3,
			wantCount: 3,
		},
		{
			name:      "middle range includes only t2",
			start:     t2,
			end:       t2,
			wantCount: 1,
		},
		{
			name:      "range excluding all",
			start:     now.Add(1 * time.Hour),
			end:       now.Add(2 * time.Hour),
			wantCount: 0,
		},
		{
			name:      "open upper bound includes t1 and t2",
			start:     t1,
			end:       t2,
			wantCount: 2,
		},
		{
			name:      "open lower bound includes t2 and t3",
			start:     t2,
			end:       t3,
			wantCount: 2,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			res := tr.GetActivityByDateRange(userID, tt.start, tt.end)
			assert.Len(t, res, tt.wantCount)
			for _, log := range res {
				assert.True(t, (log.Timestamp.Equal(tt.start) || log.Timestamp.After(tt.start)))
				assert.True(t, (log.Timestamp.Equal(tt.end) || log.Timestamp.Before(tt.end)))
			}
		})
	}
}

func TestTracker_GetAllUsers_Empty(t *testing.T) {
	tr := NewTracker()

	users := tr.GetAllUsers()
	assert.NotNil(t, users)
	assert.Len(t, users, 0)
}

func TestTracker_GetAllUsers_SortedAndUnique(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("userB", "a1", nil)
	tr.LogActivity("userA", "a2", nil)
	tr.LogActivity("userC", "a3", nil)
	tr.LogActivity("userA", "a4", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"userA", "userB", "userC"}, users)
}

func TestTracker_DeleteUserActivity_UserNotExists(t *testing.T) {
	tr := NewTracker()

	ok := tr.DeleteUserActivity("unknown")
	assert.False(t, ok)
}

func TestTracker_DeleteUserActivity_RemovesUserData(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("user1", "a1", nil)
	tr.LogActivity("user1", "a2", nil)
	tr.LogActivity("user2", "b1", nil)

	ok := tr.DeleteUserActivity("user1")
	assert.True(t, ok)

	// user1 should have no logs
	logs1 := tr.GetActivityByUser("user1")
	assert.Len(t, logs1, 0)

	// user2 should still have logs
	logs2 := tr.GetActivityByUser("user2")
	assert.Len(t, logs2, 1)

	// GetAllUsers should not include user1
	users := tr.GetAllUsers()
	assert.Equal(t, []string{"user2"}, users)
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	// Basic format check: should contain a dash
	assert.Contains(t, id1, "-")
}

func TestFindMostFrequentAction_Empty(t *testing.T) {
	res := findMostFrequentAction(map[string]int{})
	assert.Equal(t, "", res)
}

func TestFindMostFrequentAction_Single(t *testing.T) {
	res := findMostFrequentAction(map[string]int{"login": 3})
	assert.Equal(t, "login", res)
}

func TestFindMostFrequentAction_Multiple(t *testing.T) {
	counts := map[string]int{
		"login":  2,
		"click":  5,
		"logout": 1,
	}

	res := findMostFrequentAction(counts)
	assert.Equal(t, "click", res)
}

func TestFindMostFrequentAction_TieReturnsOneOfMax(t *testing.T) {
	counts := map[string]int{
		"login": 2,
		"click": 2,
	}

	res := findMostFrequentAction(counts)
	assert.Contains(t, []string{"login", "click"}, res)
}
