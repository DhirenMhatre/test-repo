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

	// Ensure it is stored internally
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
	logs[0].Action = "mutated"

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
	assert.Equal(t, 0, len(stats.ActionCounts))
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_WithActivities(t *testing.T) {
	tr := NewTracker()

	// Manually control timestamps by directly setting activities
	base := time.Now().Add(-10 * time.Minute)
	logs := []ActivityLog{
		{
			ID:        "1",
			UserID:    "user1",
			Action:    "login",
			Timestamp: base.Add(1 * time.Minute),
		},
		{
			ID:        "2",
			UserID:    "user1",
			Action:    "view",
			Timestamp: base.Add(2 * time.Minute),
		},
		{
			ID:        "3",
			UserID:    "user1",
			Action:    "login",
			Timestamp: base.Add(3 * time.Minute),
		},
	}
	tr.activities["user1"] = logs

	stats := tr.GetActivityStats("user1")
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["view"])
	assert.Equal(t, logs[0].Timestamp, stats.FirstActivity)
	assert.Equal(t, logs[2].Timestamp, stats.LastActivity)
	assert.Equal(t, "login", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_NoUser(t *testing.T) {
	tr := NewTracker()
	start := time.Now().Add(-1 * time.Hour)
	end := time.Now()

	res := tr.GetActivityByDateRange("unknown", start, end)
	assert.NotNil(t, res)
	assert.Len(t, res, 0)
}

func TestTracker_GetActivityByDateRange_FiltersCorrectly(t *testing.T) {
	tr := NewTracker()

	base := time.Now().Add(-10 * time.Minute)
	logs := []ActivityLog{
		{
			ID:        "1",
			UserID:    "user1",
			Action:    "a1",
			Timestamp: base.Add(1 * time.Minute),
		},
		{
			ID:        "2",
			UserID:    "user1",
			Action:    "a2",
			Timestamp: base.Add(3 * time.Minute),
		},
		{
			ID:        "3",
			UserID:    "user1",
			Action:    "a3",
			Timestamp: base.Add(5 * time.Minute),
		},
	}
	tr.activities["user1"] = logs

	tests := []struct {
		name    string
		start   time.Time
		end     time.Time
		wantIDs []string
	}{
		{
			name:    "full range includes all",
			start:   base,
			end:     base.Add(6 * time.Minute),
			wantIDs: []string{"1", "2", "3"},
		},
		{
			name:    "middle range",
			start:   base.Add(2 * time.Minute),
			end:     base.Add(4 * time.Minute),
			wantIDs: []string{"2"},
		},
		{
			name:    "exact boundaries inclusive",
			start:   logs[0].Timestamp,
			end:     logs[2].Timestamp,
			wantIDs: []string{"1", "2", "3"},
		},
		{
			name:    "no overlap",
			start:   base.Add(6 * time.Minute),
			end:     base.Add(7 * time.Minute),
			wantIDs: []string{},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			got := tr.GetActivityByDateRange("user1", tt.start, tt.end)
			assert.Len(t, got, len(tt.wantIDs))
			for i, id := range tt.wantIDs {
				assert.Equal(t, id, got[i].ID)
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

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.activities["userB"] = []ActivityLog{{UserID: "userB"}}
	tr.activities["userA"] = []ActivityLog{{UserID: "userA"}}
	tr.activities["userC"] = []ActivityLog{{UserID: "userC"}}

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"userA", "userB", "userC"}, users)
}

func TestTracker_DeleteUserActivity_UserExists(t *testing.T) {
	tr := NewTracker()
	tr.activities["user1"] = []ActivityLog{{UserID: "user1"}}

	ok := tr.DeleteUserActivity("user1")
	assert.True(t, ok)

	_, exists := tr.activities["user1"]
	assert.False(t, exists)
}

func TestTracker_DeleteUserActivity_UserNotExists(t *testing.T) {
	tr := NewTracker()

	ok := tr.DeleteUserActivity("user1")
	assert.False(t, ok)
}

func TestGenerateID_FormatAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	timePart1 := id1[:14]
	sep1 := id1[14]
	counterPart1 := id1[15:]

	assert.Len(t, timePart1, 14)
	assert.Equal(t, '-', sep1)
	assert.Equal(t, string(rune(1)), counterPart1)

	id2 := generateID(2)
	assert.NotEqual(t, id1, id2)
}

func TestFindMostFrequentAction_Empty(t *testing.T) {
	res := findMostFrequentAction(map[string]int{})
	assert.Equal(t, "", res)
}

func TestFindMostFrequentAction_Single(t *testing.T) {
	res := findMostFrequentAction(map[string]int{"a": 1})
	assert.Equal(t, "a", res)
}

func TestFindMostFrequentAction_Multiple(t *testing.T) {
	counts := map[string]int{
		"a": 1,
		"b": 3,
		"c": 2,
	}
	res := findMostFrequentAction(counts)
	assert.Equal(t, "b", res)
}
