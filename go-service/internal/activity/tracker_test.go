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
	assert.Equal(t, 0, tr.idCounter)
	assert.Empty(t, tr.activities)
}

func TestTracker_LogActivity_Basic(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "1.2.3.4"}
	al := tr.LogActivity("user1", "login", meta)
	assert.NotNil(t, al)
	assert.Equal(t, "user1", al.UserID)
	assert.Equal(t, "login", al.Action)
	assert.NotEmpty(t, al.ID)
	assert.WithinDuration(t, time.Now(), al.Timestamp, 2*time.Second)
	assert.Equal(t, meta, al.Metadata)
	assert.Equal(t, 1, tr.idCounter)

	// Ensure stored in internal map
	stored := tr.activities["user1"]
	assert.Len(t, stored, 1)
	assert.Equal(t, stored[0].ID, al.ID)
	assert.Equal(t, stored[0].UserID, al.UserID)
	assert.Equal(t, stored[0].Action, al.Action)
}

func TestTracker_GetActivityByUser_CopyAndEmpty(t *testing.T) {
	tr := NewTracker()

	// Empty user should return empty slice, not nil
	gotEmpty := tr.GetActivityByUser("nope")
	assert.NotNil(t, gotEmpty)
	assert.Len(t, gotEmpty, 0)

	// Populate activities
	tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)

	got := tr.GetActivityByUser("u1")
	assert.Len(t, got, 2)
	// Modify returned slice should not change internal state (copy of slice, not deep copy)
	got[0].Action = "changed"
	internal := tr.activities["u1"]
	assert.Equal(t, "a1", internal[0].Action)
}

func TestTracker_GetActivityStats_TableDriven(t *testing.T) {
	base := time.Date(2024, 5, 1, 12, 0, 0, 0, time.UTC)

	type testCase struct {
		name       string
		setup      func(tr *Tracker)
		userID     string
		total      int
		unique     int
		first      time.Time
		last       time.Time
		mostFreq   string
		actionCnts map[string]int
	}
	tests := []testCase{
		{
			name: "empty user",
			setup: func(tr *Tracker) {
				// nothing
			},
			userID:     "unknown",
			total:      0,
			unique:     0,
			first:      time.Time{},
			last:       time.Time{},
			mostFreq:   "",
			actionCnts: map[string]int{},
		},
		{
			name: "populated stats",
			setup: func(tr *Tracker) {
				tr.activities["u"] = []ActivityLog{
					{ID: "1", UserID: "u", Action: "login", Timestamp: base.Add(-10 * time.Minute)},
					{ID: "2", UserID: "u", Action: "view", Timestamp: base.Add(-5 * time.Minute)},
					{ID: "3", UserID: "u", Action: "view", Timestamp: base.Add(-1 * time.Minute)},
				}
			},
			userID:   "u",
			total:    3,
			unique:   2,
			first:    base.Add(-10 * time.Minute),
			last:     base.Add(-1 * time.Minute),
			mostFreq: "view",
			actionCnts: map[string]int{
				"login": 1,
				"view":  2,
			},
		},
	}

	for _, tt := range tests {
		tr := NewTracker()
		tt.setup(tr)

		t.Run(tt.name, func(t *testing.T) {
			stats := tr.GetActivityStats(tt.userID)
			assert.Equal(t, tt.total, stats.TotalActions)
			assert.Equal(t, tt.unique, stats.UniqueActions)
			assert.Equal(t, tt.mostFreq, stats.MostFrequent)
			if tt.total == 0 {
				assert.True(t, stats.FirstActivity.IsZero())
				assert.True(t, stats.LastActivity.IsZero())
			} else {
				assert.Equal(t, tt.first, stats.FirstActivity)
				assert.Equal(t, tt.last, stats.LastActivity)
			}
			assert.Equal(t, tt.actionCnts, stats.ActionCounts)
		})
	}
}

func TestTracker_GetActivityByDateRange_InclusiveAndEmpty(t *testing.T) {
	tr := NewTracker()
	user := "u"

	base := time.Date(2024, 6, 1, 10, 0, 0, 0, time.UTC)
	t1 := base
	t2 := base.Add(1 * time.Minute)
	t3 := base.Add(2 * time.Minute)

	tr.activities[user] = []ActivityLog{
		{ID: "1", UserID: user, Action: "a", Timestamp: t1},
		{ID: "2", UserID: user, Action: "b", Timestamp: t2},
		{ID: "3", UserID: user, Action: "c", Timestamp: t3},
	}

	// Non-existent user
	none := tr.GetActivityByDateRange("nope", t1, t3)
	assert.Len(t, none, 0)

	// Full inclusive range
	full := tr.GetActivityByDateRange(user, t1, t3)
	assert.Len(t, full, 3)
	assert.Equal(t, []string{"a", "b", "c"}, []string{full[0].Action, full[1].Action, full[2].Action})

	// Exact boundary inclusive single point
	exact := tr.GetActivityByDateRange(user, t2, t2)
	assert.Len(t, exact, 1)
	assert.Equal(t, "b", exact[0].Action)

	// Exclude endpoints by nudging inward
	exclusive := tr.GetActivityByDateRange(user, t1.Add(1*time.Nanosecond), t3.Add(-1*time.Nanosecond))
	assert.Len(t, exclusive, 1)
	assert.Equal(t, "b", exclusive[0].Action)

	// No overlap
	noOverlap := tr.GetActivityByDateRange(user, t3.Add(1*time.Second), t3.Add(2*time.Second))
	assert.Len(t, noOverlap, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()

	tr.activities["b"] = []ActivityLog{{UserID: "b", Action: "x", Timestamp: time.Now()}}
	tr.activities["a"] = []ActivityLog{{UserID: "a", Action: "y", Timestamp: time.Now()}}
	tr.activities["c"] = []ActivityLog{{UserID: "c", Action: "z", Timestamp: time.Now()}}

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)

	// Empty tracker
	tr2 := NewTracker()
	assert.Empty(t, tr2.GetAllUsers())
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a", Timestamp: time.Now()},
		{ID: "2", UserID: "u1", Action: "b", Timestamp: time.Now()},
	}
	tr.activities["u2"] = []ActivityLog{
		{ID: "3", UserID: "u2", Action: "c", Timestamp: time.Now()},
	}

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	_, exists := tr.activities["u1"]
	assert.False(t, exists)

	// Deleting again should return false
	ok = tr.DeleteUserActivity("u1")
	assert.False(t, ok)

	// Other user remains
	_, exists = tr.activities["u2"]
	assert.True(t, exists)
}

func TestGenerateID_SuffixAndUniqueness(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)
	assert.NotEqual(t, id1, id2)

	// Check hyphen and suffix equals rune of counter
	idx1 := strings.LastIndex(id1, "-")
	assert.NotEqual(t, -1, idx1)
	suffix1 := id1[idx1+1:]
	assert.Equal(t, string(rune(1)), suffix1)

	idx2 := strings.LastIndex(id2, "-")
	assert.NotEqual(t, -1, idx2)
	suffix2 := id2[idx2+1:]
	assert.Equal(t, string(rune(2)), suffix2)
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"view":  5,
		"login": 2,
		"edit":  3,
	}
	assert.Equal(t, "view", findMostFrequentAction(counts))

	counts2 := map[string]int{"only": 1}
	assert.Equal(t, "only", findMostFrequentAction(counts2))
}
