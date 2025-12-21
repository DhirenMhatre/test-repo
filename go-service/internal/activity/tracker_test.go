package activity

import (
	"strings"
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

func TestTracker_LogActivity(t *testing.T) {
	tr := NewTracker()

	metadata := map[string]interface{}{"ip": "1.2.3.4"}
	log1 := tr.LogActivity("user1", "login", metadata)
	assert.NotNil(t, log1)
	assert.Equal(t, "user1", log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.NotZero(t, log1.Timestamp)
	assert.NotEmpty(t, log1.ID)
	assert.Equal(t, metadata, log1.Metadata)

	log2 := tr.LogActivity("user1", "view", nil)
	assert.NotNil(t, log2)
	assert.NotEmpty(t, log2.ID)
	assert.NotEqual(t, log1.ID, log2.ID)

	tr.mu.RLock()
	defer tr.mu.RUnlock()
	assert.Equal(t, 2, len(tr.activities["user1"]))
	assert.Equal(t, 2, tr.idCounter)
}

func TestTracker_GetActivityByUser_EmptyAndCopy(t *testing.T) {
	tr := NewTracker()

	// Non-existent user
	got := tr.GetActivityByUser("nouser")
	assert.NotNil(t, got)
	assert.Len(t, got, 0)

	// Add two logs
	tr.LogActivity("user1", "login", nil)
	tr.LogActivity("user1", "view", nil)

	// Get and mutate returned slice and element; original should remain unchanged
	got = tr.GetActivityByUser("user1")
	assert.Len(t, got, 2)
	firstOriginalAction := got[0].Action

	// Mutate returned slice
	got[0].Action = "mutated"
	got = append(got, ActivityLog{Action: "extra"})
	// Fetch again; should be unaffected
	got2 := tr.GetActivityByUser("user1")
	assert.Len(t, got2, 2)
	assert.Equal(t, firstOriginalAction, got2[0].Action)
}

func TestTracker_GetActivityStats_Empty(t *testing.T) {
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

func TestTracker_GetActivityStats_Computed(t *testing.T) {
	tr := NewTracker()

	base := time.Date(2025, 1, 2, 15, 4, 5, 0, time.UTC)
	logs := []ActivityLog{
		{ID: "1", UserID: "u2", Action: "login", Timestamp: base},
		{ID: "2", UserID: "u2", Action: "view", Timestamp: base.Add(2 * time.Minute)},
		{ID: "3", UserID: "u2", Action: "view", Timestamp: base.Add(5 * time.Minute)},
	}
	tr.mu.Lock()
	tr.activities["u2"] = append(tr.activities["u2"], logs...)
	tr.mu.Unlock()

	stats := tr.GetActivityStats("u2")
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, base, stats.FirstActivity)
	assert.Equal(t, base.Add(5*time.Minute), stats.LastActivity)
	assert.Equal(t, "view", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange(t *testing.T) {
	tr := NewTracker()
	userID := "rangeuser"
	base := time.Date(2025, 2, 1, 10, 0, 0, 0, time.UTC)

	// Inject deterministic logs with exact timestamps
	logs := []ActivityLog{
		{ID: "0", UserID: userID, Action: "a", Timestamp: base.Add(0 * time.Hour)},
		{ID: "1", UserID: userID, Action: "b", Timestamp: base.Add(1 * time.Hour)},
		{ID: "2", UserID: userID, Action: "c", Timestamp: base.Add(2 * time.Hour)},
		{ID: "3", UserID: userID, Action: "d", Timestamp: base.Add(3 * time.Hour)},
		{ID: "4", UserID: userID, Action: "e", Timestamp: base.Add(4 * time.Hour)},
	}
	tr.mu.Lock()
	tr.activities[userID] = append(tr.activities[userID], logs...)
	tr.mu.Unlock()

	tests := []struct {
		name       string
		start      time.Time
		end        time.Time
		wantIDs    []string
		wantLength int
	}{
		{
			name:       "middle range inclusive",
			start:      base.Add(1 * time.Hour),
			end:        base.Add(3 * time.Hour),
			wantIDs:    []string{"1", "2", "3"},
			wantLength: 3,
		},
		{
			name:       "full range inclusive",
			start:      base,
			end:        base.Add(4 * time.Hour),
			wantIDs:    []string{"0", "1", "2", "3", "4"},
			wantLength: 5,
		},
		{
			name:       "single point inclusive",
			start:      base.Add(2 * time.Hour),
			end:        base.Add(2 * time.Hour),
			wantIDs:    []string{"2"},
			wantLength: 1,
		},
		{
			name:       "outside range none",
			start:      base.Add(-3 * time.Hour),
			end:        base.Add(-1 * time.Hour),
			wantIDs:    []string{},
			wantLength: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tr.GetActivityByDateRange(userID, tt.start, tt.end)
			assert.Len(t, got, tt.wantLength)
			if len(tt.wantIDs) > 0 {
				ids := make([]string, len(got))
				for i, l := range got {
					ids[i] = l.ID
				}
				assert.Equal(t, tt.wantIDs, ids)
			}
		})
	}
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.mu.Lock()
	tr.activities["zeta"] = []ActivityLog{{UserID: "zeta"}}
	tr.activities["alpha"] = []ActivityLog{{UserID: "alpha"}}
	tr.activities["mu"] = []ActivityLog{{UserID: "mu"}}
	tr.mu.Unlock()

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"alpha", "mu", "zeta"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()

	// Deleting non-existent user returns false
	ok := tr.DeleteUserActivity("ghost")
	assert.False(t, ok)

	// Add activity and delete
	tr.LogActivity("deleteme", "ping", nil)
	tr.LogActivity("deleteme", "pong", nil)

	ok = tr.DeleteUserActivity("deleteme")
	assert.True(t, ok)

	// Verify removed
	users := tr.GetAllUsers()
	for _, u := range users {
		assert.NotEqual(t, "deleteme", u)
	}
	got := tr.GetActivityByUser("deleteme")
	assert.Len(t, got, 0)

	// Delete again => false
	assert.False(t, tr.DeleteUserActivity("deleteme"))
}

func TestGenerateID_Basic(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)

	assert.Equal(t, 1, strings.Count(id1, "-"))
	parts := strings.SplitN(id1, "-", 2)
	assert.Equal(t, 2, len(parts))
	assert.Len(t, parts[0], 14) // "20060102150405" length
	assert.NotEmpty(t, parts[1])
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"a": 2,
		"b": 5,
		"c": 3,
	}
	assert.Equal(t, "b", findMostFrequentAction(counts))
}
