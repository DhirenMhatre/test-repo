package activity

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.NotNil(t, tr.activities)
	assert.Equal(t, 0, tr.idCounter)
	assert.Empty(t, tr.activities)
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
	assert.WithinDuration(t, time.Now(), log.Timestamp, time.Second)
	assert.Equal(t, 1, tr.idCounter)

	// Ensure it is stored
	stored := tr.GetActivityByUser("user1")
	assert.Len(t, stored, 1)
	assert.Equal(t, log.ID, stored[0].ID)
}

func TestTracker_LogActivity_IDCounterIncrements(t *testing.T) {
	tr := NewTracker()

	log1 := tr.LogActivity("user1", "a1", nil)
	log2 := tr.LogActivity("user1", "a2", nil)
	log3 := tr.LogActivity("user1", "a3", nil)

	assert.NotEqual(t, log1.ID, log2.ID)
	assert.NotEqual(t, log2.ID, log3.ID)
	assert.Equal(t, 3, tr.idCounter)
}

func TestTracker_GetActivityByUser_EmptyAndIsolation(t *testing.T) {
	tr := NewTracker()

	// No activities yet
	logs := tr.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Empty(t, logs)

	// Add activities for multiple users
	tr.LogActivity("user1", "login", nil)
	tr.LogActivity("user1", "logout", nil)
	tr.LogActivity("user2", "login", nil)

	user1Logs := tr.GetActivityByUser("user1")
	user2Logs := tr.GetActivityByUser("user2")

	assert.Len(t, user1Logs, 2)
	assert.Len(t, user2Logs, 1)

	for _, l := range user1Logs {
		assert.Equal(t, "user1", l.UserID)
	}
	for _, l := range user2Logs {
		assert.Equal(t, "user2", l.UserID)
	}
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("user1", "login", nil)

	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 1)

	// Mutate returned slice and element; internal state should not change
	logs[0].Action = "mutated"
	logs = append(logs, ActivityLog{UserID: "user1", Action: "extra"})

	internal := tr.GetActivityByUser("user1")
	assert.Len(t, internal, 1)
	assert.Equal(t, "login", internal[0].Action)
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

func TestTracker_GetActivityStats_SingleUserMultipleActions(t *testing.T) {
	tr := NewTracker()

	// Ensure deterministic timestamps by overriding after creation
	now := time.Now()
	a1 := tr.LogActivity("user1", "login", nil)
	a1.Timestamp = now.Add(-10 * time.Minute)

	a2 := tr.LogActivity("user1", "view", nil)
	a2.Timestamp = now.Add(-5 * time.Minute)

	a3 := tr.LogActivity("user1", "login", nil)
	a3.Timestamp = now.Add(-1 * time.Minute)

	// Another user to ensure isolation
	tr.LogActivity("user2", "login", nil)

	stats := tr.GetActivityStats("user1")

	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.WithinDuration(t, now.Add(-10*time.Minute), stats.FirstActivity, time.Second)
	assert.WithinDuration(t, now.Add(-1*time.Minute), stats.LastActivity, time.Second)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityStats_SingleActionType(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("user1", "only", nil)
	tr.LogActivity("user1", "only", nil)

	stats := tr.GetActivityStats("user1")
	assert.Equal(t, 2, stats.TotalActions)
	assert.Equal(t, 1, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["only"])
	assert.Equal(t, "only", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_EmptyAndNoUser(t *testing.T) {
	tr := NewTracker()
	start := time.Now().Add(-time.Hour)
	end := time.Now().Add(time.Hour)

	// No such user
	logs := tr.GetActivityByDateRange("user1", start, end)
	assert.NotNil(t, logs)
	assert.Empty(t, logs)
}

func TestTracker_GetActivityByDateRange_InclusiveBounds(t *testing.T) {
	tr := NewTracker()
	base := time.Now()

	// Create logs and then adjust timestamps to precise values
	l1 := tr.LogActivity("user1", "a1", nil)
	l1.Timestamp = base.Add(-2 * time.Hour)

	l2 := tr.LogActivity("user1", "a2", nil)
	l2.Timestamp = base

	l3 := tr.LogActivity("user1", "a3", nil)
	l3.Timestamp = base.Add(2 * time.Hour)

	start := base
	end := base.Add(2 * time.Hour)

	// Range should include timestamps equal to start and end
	logs := tr.GetActivityByDateRange("user1", start, end)
	assert.Len(t, logs, 2)

	ids := []string{logs[0].Action, logs[1].Action}
	assert.Contains(t, ids, "a2")
	assert.Contains(t, ids, "a3")
}

func TestTracker_GetActivityByDateRange_OutsideRange(t *testing.T) {
	tr := NewTracker()
	base := time.Now()

	l1 := tr.LogActivity("user1", "before", nil)
	l1.Timestamp = base.Add(-3 * time.Hour)

	l2 := tr.LogActivity("user1", "inside", nil)
	l2.Timestamp = base.Add(-1 * time.Hour)

	l3 := tr.LogActivity("user1", "after", nil)
	l3.Timestamp = base.Add(3 * time.Hour)

	start := base.Add(-2 * time.Hour)
	end := base.Add(2 * time.Hour)

	logs := tr.GetActivityByDateRange("user1", start, end)
	assert.Len(t, logs, 1)
	assert.Equal(t, "inside", logs[0].Action)
}

func TestTracker_GetAllUsers_Empty(t *testing.T) {
	tr := NewTracker()
	users := tr.GetAllUsers()
	assert.NotNil(t, users)
	assert.Empty(t, users)
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

func TestTracker_DeleteUserActivity_NonExisting(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("user1", "a1", nil)

	ok := tr.DeleteUserActivity("unknown")
	assert.False(t, ok)

	// Ensure existing user still has activity
	logs := tr.GetActivityByUser("user1")
	assert.Len(t, logs, 1)
}

func TestTracker_DeleteUserActivity_Existing(t *testing.T) {
	tr := NewTracker()

	tr.LogActivity("user1", "a1", nil)
	tr.LogActivity("user1", "a2", nil)
	tr.LogActivity("user2", "b1", nil)

	ok := tr.DeleteUserActivity("user1")
	assert.True(t, ok)

	// user1 should have no logs
	user1Logs := tr.GetActivityByUser("user1")
	assert.Empty(t, user1Logs)

	// user2 should remain
	user2Logs := tr.GetActivityByUser("user2")
	assert.Len(t, user2Logs, 1)

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
	assert.Contains(t, id2, "-")
}

func TestFindMostFrequentAction_Empty(t *testing.T) {
	result := findMostFrequentAction(map[string]int{})
	assert.Equal(t, "", result)
}

func TestFindMostFrequentAction_SingleAndMultiple(t *testing.T) {
	tests := []struct {
		name     string
		input    map[string]int
		expected string
	}{
		{
			name:     "single action",
			input:    map[string]int{"login": 3},
			expected: "login",
		},
		{
			name:     "multiple actions",
			input:    map[string]int{"login": 3, "view": 1, "logout": 2},
			expected: "login",
		},
		{
			name:  "tie chooses first max encountered",
			input: map[string]int{"a": 2, "b": 2},
			// result can be "a" or "b" depending on map iteration order; just assert it's one of them
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := findMostFrequentAction(tt.input)
			if tt.expected != "" {
				assert.Equal(t, tt.expected, result)
			} else {
				assert.Contains(t, []string{"a", "b"}, result)
			}
		})
	}
}
