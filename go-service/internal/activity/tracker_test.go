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
}

func TestTracker_LogActivity_BasicFields(t *testing.T) {
	tr := NewTracker()
	nowBefore := time.Now()

	// with metadata
	md := map[string]interface{}{"ip": "127.0.0.1", "agent": "test"}
	log := tr.LogActivity("user1", "login", md)
	assert.NotNil(t, log)
	assert.Equal(t, "user1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.NotEmpty(t, log.ID)
	assert.True(t, !log.Timestamp.Before(nowBefore))
	assert.Equal(t, md, log.Metadata)

	// with nil metadata
	log2 := tr.LogActivity("user1", "logout", nil)
	assert.NotNil(t, log2)
	assert.Nil(t, log2.Metadata)

	// IDs should be different across calls
	assert.NotEqual(t, log.ID, log2.ID)
}

func TestTracker_GetActivityByUser_EmptyAndCopyIsolation(t *testing.T) {
	tr := NewTracker()

	// Non-existent user returns empty slice (not nil)
	got := tr.GetActivityByUser("nope")
	assert.NotNil(t, got)
	assert.Empty(t, got)

	// Add some activities
	_ = tr.LogActivity("u1", "a1", nil)
	_ = tr.LogActivity("u1", "a2", nil)

	// Retrieve and modify the returned slice; internal state must not change
	first := tr.GetActivityByUser("u1")
	assert.Len(t, first, 2)
	first[0].Action = "mutated"
	first = append(first, ActivityLog{Action: "extra"})

	second := tr.GetActivityByUser("u1")
	assert.Len(t, second, 2)
	// Ensure original first element action is still "a1"
	assert.Equal(t, "a1", second[0].Action)
}

func TestTracker_GetActivityStats_EmptyAndNonEmpty(t *testing.T) {
	tr := NewTracker()

	// Empty/non-existent user
	statsEmpty := tr.GetActivityStats("nouser")
	assert.NotNil(t, statsEmpty)
	assert.Equal(t, 0, statsEmpty.TotalActions)
	assert.Equal(t, 0, statsEmpty.UniqueActions)
	assert.NotNil(t, statsEmpty.ActionCounts)
	assert.Equal(t, "", statsEmpty.MostFrequent)

	// Seed activities then adjust timestamps for deterministic first/last
	a1 := tr.LogActivity("u1", "view", nil)
	a2 := tr.LogActivity("u1", "click", nil)
	a3 := tr.LogActivity("u1", "view", nil)

	base := time.Now().Add(-2 * time.Hour).Truncate(time.Second)
	tr.mu.Lock()
	tr.activities["u1"][0].Timestamp = base.Add(10 * time.Minute)
	tr.activities["u1"][1].Timestamp = base.Add(20 * time.Minute)
	tr.activities["u1"][2].Timestamp = base.Add(30 * time.Minute)
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u1")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["click"])
	assert.Equal(t, "view", stats.MostFrequent)
	assert.True(t, stats.FirstActivity.Equal(base.Add(10*time.Minute)))
	assert.True(t, stats.LastActivity.Equal(base.Add(30*time.Minute)))

	// Ensure logs are still accessible and unchanged
	got := tr.GetActivityByUser("u1")
	assert.Equal(t, a1.UserID, got[0].UserID)
	assert.Equal(t, a2.UserID, got[1].UserID)
	assert.Equal(t, a3.UserID, got[2].UserID)
}

func TestTracker_GetActivityByDateRange_InclusiveBounds(t *testing.T) {
	tr := NewTracker()

	l1 := tr.LogActivity("u1", "a1", nil)
	l2 := tr.LogActivity("u1", "a2", nil)
	l3 := tr.LogActivity("u1", "a3", nil)

	base := time.Date(2025, 1, 10, 12, 0, 0, 0, time.UTC)
	t1 := base.Add(-1 * time.Hour)
	t2 := base
	t3 := base.Add(1 * time.Hour)

	tr.mu.Lock()
	tr.activities["u1"][0].Timestamp = t1
	tr.activities["u1"][1].Timestamp = t2
	tr.activities["u1"][2].Timestamp = t3
	tr.mu.Unlock()

	tests := []struct {
		name      string
		start     time.Time
		end       time.Time
		wantIDs   map[string]bool
		wantCount int
	}{
		{
			name:      "all inclusive",
			start:     t1,
			end:       t3,
			wantIDs:   map[string]bool{l1.ID: true, l2.ID: true, l3.ID: true},
			wantCount: 3,
		},
		{
			name:      "exact single timestamp",
			start:     t2,
			end:       t2,
			wantIDs:   map[string]bool{l2.ID: true},
			wantCount: 1,
		},
		{
			name:      "first two",
			start:     t1,
			end:       t2,
			wantIDs:   map[string]bool{l1.ID: true, l2.ID: true},
			wantCount: 2,
		},
		{
			name:      "none",
			start:     t3.Add(1 * time.Minute),
			end:       t3.Add(2 * time.Minute),
			wantIDs:   map[string]bool{},
			wantCount: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			out := tr.GetActivityByDateRange("u1", tt.start, tt.end)
			assert.Len(t, out, tt.wantCount)
			for _, o := range out {
				assert.True(t, tt.wantIDs[o.ID])
			}
		})
	}
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("u2", "a", nil)
	_ = tr.LogActivity("u1", "a", nil)
	_ = tr.LogActivity("u3", "a", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u1", "u2", "u3"}, users)
}

func TestTracker_DeleteUserActivity_Behavior(t *testing.T) {
	tr := NewTracker()
	_ = tr.LogActivity("u1", "a1", nil)
	_ = tr.LogActivity("u2", "a1", nil)

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	// u1 should be completely removed
	gotU1 := tr.GetActivityByUser("u1")
	assert.Len(t, gotU1, 0)

	// u2 should remain
	gotU2 := tr.GetActivityByUser("u2")
	assert.Len(t, gotU2, 1)

	// Deleting nonexistent user returns false
	ok2 := tr.DeleteUserActivity("nope")
	assert.False(t, ok2)
}

func TestGenerateID_UniquenessAcrossCounters(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
}

func TestFindMostFrequentAction_BasicAndEmpty(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"view":  5,
		"click": 3,
		"buy":   1,
	}
	assert.Equal(t, "view", findMostFrequentAction(counts))
}
