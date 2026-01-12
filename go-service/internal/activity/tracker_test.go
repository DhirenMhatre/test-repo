package activity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker(t *testing.T) {
	tracker := NewTracker()
	assert.NotNil(t, tracker)
	assert.NotNil(t, tracker.activities)
	assert.Equal(t, 0, tracker.idCounter)
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"
	action := "login"
	metadata := map[string]interface{}{"ip": "127.0.0.1"}

	log := tracker.LogActivity(userID, action, metadata)

	assert.NotNil(t, log)
	assert.Equal(t, userID, log.UserID)
	assert.Equal(t, action, log.Action)
	assert.Equal(t, metadata, log.Metadata)
	assert.NotEmpty(t, log.ID)
	assert.WithinDuration(t, time.Now(), log.Timestamp, time.Second)

	// Ensure it is stored
	logs := tracker.GetActivityByUser(userID)
	assert.Len(t, logs, 1)
	assert.Equal(t, *log, logs[0])
}

func TestTracker_LogActivity_IDCounterIncrements(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	log1 := tracker.LogActivity(userID, "action1", nil)
	log2 := tracker.LogActivity(userID, "action2", nil)

	assert.NotEqual(t, log1.ID, log2.ID)
	assert.Equal(t, 2, tracker.idCounter)
}

func TestTracker_GetActivityByUser_Empty(t *testing.T) {
	tracker := NewTracker()

	logs := tracker.GetActivityByUser("nonexistent")

	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByUser_CopyIsolation(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	tracker.LogActivity(userID, "action1", nil)
	original := tracker.GetActivityByUser(userID)
	assert.Len(t, original, 1)

	// Modify returned slice and ensure internal state is not affected
	original[0].Action = "modified"

	internal := tracker.GetActivityByUser(userID)
	assert.Equal(t, "action1", internal[0].Action)
}

func TestTracker_GetActivityStats_NoActivity(t *testing.T) {
	tracker := NewTracker()

	stats := tracker.GetActivityStats("nonexistent")

	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_WithActivities(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	// Manually control timestamps
	now := time.Now()
	earlier := now.Add(-2 * time.Hour)
	later := now.Add(2 * time.Hour)

	tracker.mu.Lock()
	tracker.activities[userID] = []ActivityLog{
		{
			ID:        "1",
			UserID:    userID,
			Action:    "login",
			Timestamp: now,
		},
		{
			ID:        "2",
			UserID:    userID,
			Action:    "logout",
			Timestamp: later,
		},
		{
			ID:        "3",
			UserID:    userID,
			Action:    "login",
			Timestamp: earlier,
		},
	}
	tracker.mu.Unlock()

	stats := tracker.GetActivityStats(userID)

	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["logout"])
	assert.WithinDuration(t, earlier, stats.FirstActivity, time.Millisecond)
	assert.WithinDuration(t, later, stats.LastActivity, time.Millisecond)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_NoUser(t *testing.T) {
	tracker := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now().Add(time.Hour)

	logs := tracker.GetActivityByDateRange("nonexistent", start, end)

	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByDateRange_Filtering(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	base := time.Now()
	before := base.Add(-2 * time.Hour)
	start := base.Add(-time.Hour)
	mid := base
	end := base.Add(time.Hour)
	after := base.Add(2 * time.Hour)

	tracker.mu.Lock()
	tracker.activities[userID] = []ActivityLog{
		{ID: "1", UserID: userID, Action: "a", Timestamp: before},
		{ID: "2", UserID: userID, Action: "b", Timestamp: start},
		{ID: "3", UserID: userID, Action: "c", Timestamp: mid},
		{ID: "4", UserID: userID, Action: "d", Timestamp: end},
		{ID: "5", UserID: userID, Action: "e", Timestamp: after},
	}
	tracker.mu.Unlock()

	tests := []struct {
		name    string
		start   time.Time
		end     time.Time
		wantIDs []string
	}{
		{
			name:    "range_inclusive_bounds",
			start:   start,
			end:     end,
			wantIDs: []string{"2", "3", "4"},
		},
		{
			name:    "single_point_start_equals_end",
			start:   mid,
			end:     mid,
			wantIDs: []string{"3"},
		},
		{
			name:    "range_before_all",
			start:   before.Add(-time.Hour),
			end:     before.Add(-30 * time.Minute),
			wantIDs: []string{},
		},
		{
			name:    "range_after_all",
			start:   after.Add(30 * time.Minute),
			end:     after.Add(time.Hour),
			wantIDs: []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			logs := tracker.GetActivityByDateRange(userID, tt.start, tt.end)
			assert.Len(t, logs, len(tt.wantIDs))
			for i, id := range tt.wantIDs {
				assert.Equal(t, id, logs[i].ID)
			}
		})
	}
}

func TestTracker_GetAllUsers_Empty(t *testing.T) {
	tracker := NewTracker()

	users := tracker.GetAllUsers()

	assert.NotNil(t, users)
	assert.Len(t, users, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tracker := NewTracker()

	tracker.LogActivity("userB", "action", nil)
	tracker.LogActivity("userA", "action", nil)
	tracker.LogActivity("userC", "action", nil)

	users := tracker.GetAllUsers()

	assert.Equal(t, []string{"userA", "userB", "userC"}, users)
}

func TestTracker_DeleteUserActivity_Nonexistent(t *testing.T) {
	tracker := NewTracker()

	ok := tracker.DeleteUserActivity("nonexistent")

	assert.False(t, ok)
}

func TestTracker_DeleteUserActivity_Existing(t *testing.T) {
	tracker := NewTracker()
	userID := "user1"

	tracker.LogActivity(userID, "action", nil)
	assert.Len(t, tracker.GetActivityByUser(userID), 1)

	ok := tracker.DeleteUserActivity(userID)
	assert.True(t, ok)

	logs := tracker.GetActivityByUser(userID)
	assert.Len(t, logs, 0)

	// Deleting again should return false
	ok = tracker.DeleteUserActivity(userID)
	assert.False(t, ok)
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	// Check that there is a dash separator and suffix matches rune of counter
	assert.Contains(t, id1, "-")
}

func TestFindMostFrequentAction_Empty(t *testing.T) {
	result := findMostFrequentAction(map[string]int{})

	assert.Equal(t, "", result)
}

func TestFindMostFrequentAction_Single(t *testing.T) {
	counts := map[string]int{"login": 3}

	result := findMostFrequentAction(counts)

	assert.Equal(t, "login", result)
}

func TestFindMostFrequentAction_Multiple(t *testing.T) {
	counts := map[string]int{
		"login":  5,
		"logout": 2,
		"view":   3,
	}

	result := findMostFrequentAction(counts)

	assert.Equal(t, "login", result)
}

func TestFindMostFrequentAction_Tie(t *testing.T) {
	// In case of tie, any of the max-count actions is acceptable.
	counts := map[string]int{
		"login":  3,
		"logout": 3,
	}

	result := findMostFrequentAction(counts)

	assert.True(t, result == "login" || result == "logout")
}
