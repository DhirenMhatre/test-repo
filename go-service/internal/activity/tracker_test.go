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
	assert.Empty(t, tr.activities)
}

func TestTracker_LogActivity_And_GetActivityByUser(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1"}
	l1 := tr.LogActivity("u1", "login", meta)
	assert.NotNil(t, l1)
	assert.Equal(t, "u1", l1.UserID)
	assert.Equal(t, "login", l1.Action)
	assert.NotEmpty(t, l1.ID)
	assert.False(t, l1.Timestamp.IsZero())
	assert.Equal(t, meta, l1.Metadata)

	l2 := tr.LogActivity("u1", "view", nil)
	assert.NotNil(t, l2)
	assert.NotEmpty(t, l2.ID)
	assert.NotEqual(t, l1.ID, l2.ID)

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 2)
	assert.Equal(t, "login", logs[0].Action)
	assert.Equal(t, "view", logs[1].Action)
}

func TestTracker_GetActivityByUser_UnknownUserReturnsEmpty(t *testing.T) {
	tr := NewTracker()
	logs := tr.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "original", nil)

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 1)
	// Mutate returned slice and element
	got[0].Action = "mutated"
	got = append(got, ActivityLog{Action: "extra"})

	// Internal state should not change
	got2 := tr.GetActivityByUser("u1")
	assert.Len(t, got2, 1)
	assert.Equal(t, "original", got2[0].Action)
}

func TestTracker_GetActivityStats_NoLogs(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("nouser")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_WithLogs(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2023, 7, 1, 12, 0, 0, 0, time.UTC)
	logs := []ActivityLog{
		{ID: "1", UserID: "u1", Action: "login", Timestamp: base.Add(1 * time.Minute)},
		{ID: "2", UserID: "u1", Action: "view", Timestamp: base.Add(2 * time.Minute)},
		{ID: "3", UserID: "u1", Action: "view", Timestamp: base.Add(3 * time.Minute)},
	}
	tr.mu.Lock()
	tr.activities["u1"] = logs
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.NotNil(t, stats)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, base.Add(1*time.Minute), stats.FirstActivity)
	assert.Equal(t, base.Add(3*time.Minute), stats.LastActivity)
	assert.Equal(t, "view", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2024, 1, 2, 10, 0, 0, 0, time.UTC)
	u1logs := []ActivityLog{
		{ID: "a0", UserID: "u1", Action: "a", Timestamp: base.Add(0 * time.Minute)},
		{ID: "a1", UserID: "u1", Action: "b", Timestamp: base.Add(1 * time.Minute)},
		{ID: "a2", UserID: "u1", Action: "c", Timestamp: base.Add(2 * time.Minute)},
		{ID: "a3", UserID: "u1", Action: "d", Timestamp: base.Add(3 * time.Minute)},
		{ID: "a4", UserID: "u1", Action: "e", Timestamp: base.Add(4 * time.Minute)},
	}
	tr.mu.Lock()
	tr.activities["u1"] = u1logs
	tr.mu.Unlock()

	tests := []struct {
		name      string
		userID    string
		start     time.Time
		end       time.Time
		wantCount int
	}{
		{
			name:      "full range inclusive",
			userID:    "u1",
			start:     base,
			end:       base.Add(4 * time.Minute),
			wantCount: 5,
		},
		{
			name:      "middle range",
			userID:    "u1",
			start:     base.Add(1 * time.Minute),
			end:       base.Add(3 * time.Minute),
			wantCount: 3,
		},
		{
			name:      "single instant inclusive",
			userID:    "u1",
			start:     base.Add(2 * time.Minute),
			end:       base.Add(2 * time.Minute),
			wantCount: 1,
		},
		{
			name:      "start after end returns empty",
			userID:    "u1",
			start:     base.Add(3 * time.Minute),
			end:       base.Add(2 * time.Minute),
			wantCount: 0,
		},
		{
			name:      "unknown user",
			userID:    "unknown",
			start:     base,
			end:       base.Add(10 * time.Minute),
			wantCount: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tr.GetActivityByDateRange(tt.userID, tt.start, tt.end)
			assert.Len(t, got, tt.wantCount)
		})
	}
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	// Insert activities under different users
	tr.mu.Lock()
	tr.activities["u2"] = []ActivityLog{{ID: "x", UserID: "u2", Action: "a", Timestamp: time.Now()}}
	tr.activities["u1"] = []ActivityLog{{ID: "y", UserID: "u1", Action: "b", Timestamp: time.Now()}}
	tr.activities["u3"] = []ActivityLog{{ID: "z", UserID: "u3", Action: "c", Timestamp: time.Now()}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u1", "u2", "u3"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.mu.Lock()
	tr.activities["u1"] = []ActivityLog{{ID: "1", UserID: "u1", Action: "a", Timestamp: time.Now()}}
	tr.activities["u2"] = []ActivityLog{{ID: "2", UserID: "u2", Action: "b", Timestamp: time.Now()}}
	tr.mu.Unlock()

	assert.False(t, tr.DeleteUserActivity("u3"))

	assert.True(t, tr.DeleteUserActivity("u1"))
	logsU1 := tr.GetActivityByUser("u1")
	assert.Len(t, logsU1, 0)

	logsU2 := tr.GetActivityByUser("u2")
	assert.Len(t, logsU2, 1)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)
}

func Test_generateID_Structure(t *testing.T) {
	id := generateID(1)
	assert.Len(t, id, 16, "expected time format 14 chars + '-' + 1 rune")
	assert.Equal(t, byte('-'), id[14])
	assert.Equal(t, byte(1), id[15])

	id2 := generateID(2)
	assert.Len(t, id2, 16)
	assert.Equal(t, byte('-'), id2[14])
	assert.Equal(t, byte(2), id2[15])
}

func Test_findMostFrequentAction(t *testing.T) {
	// Empty
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	// Single max
	ac := map[string]int{
		"login": 1,
		"view":  3,
		"edit":  2,
	}
	assert.Equal(t, "view", findMostFrequentAction(ac))
}
