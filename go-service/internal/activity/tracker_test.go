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
	assert.Empty(t, tr.GetAllUsers())
}

func TestTracker_LogActivityAndGetActivityByUser(t *testing.T) {
	tr := NewTracker()

	meta := map[string]interface{}{"ip": "127.0.0.1"}
	a1 := tr.LogActivity("u1", "login", meta)
	a2 := tr.LogActivity("u1", "view", nil)

	assert.NotNil(t, a1)
	assert.NotNil(t, a2)
	assert.Equal(t, "u1", a1.UserID)
	assert.Equal(t, "login", a1.Action)
	assert.NotEmpty(t, a1.ID)
	assert.False(t, a1.Timestamp.IsZero())
	assert.Equal(t, meta, a1.Metadata)

	assert.NotEqual(t, a1.ID, a2.ID, "IDs should be unique for different activities")

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 2)
	assert.Equal(t, a1.ID, logs[0].ID)
	assert.Equal(t, a2.ID, logs[1].ID)

	// Non-existent user returns empty slice
	none := tr.GetActivityByUser("nope")
	assert.Empty(t, none)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "login", nil)
	tr.LogActivity("u1", "view", nil)

	// Get a copy and mutate it
	cp := tr.GetActivityByUser("u1")
	assert.Len(t, cp, 2)
	origFirst := cp[0]
	cp[0].Action = "mutated"

	// Fetch again to ensure internal state hasn't changed
	again := tr.GetActivityByUser("u1")
	assert.Len(t, again, 2)
	assert.Equal(t, origFirst.Action, again[0].Action)

	// Ensure appending to returned slice doesn't affect tracker
	cp = append(cp, ActivityLog{UserID: "u1", Action: "extra"})
	again2 := tr.GetActivityByUser("u1")
	assert.Len(t, again2, 2)
}

func TestTracker_GetActivityStats_NoData(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("ghost")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_WithData(t *testing.T) {
	tr := NewTracker()
	user := "stats"

	_ = tr.LogActivity(user, "a", nil)
	_ = tr.LogActivity(user, "b", nil)
	_ = tr.LogActivity(user, "a", nil)

	base := time.Date(2025, 1, 1, 12, 0, 0, 0, time.UTC)
	tr.mu.Lock()
	tr.activities[user][0].Timestamp = base.Add(-2 * time.Hour)
	tr.activities[user][1].Timestamp = base
	tr.activities[user][2].Timestamp = base.Add(1 * time.Hour)
	tr.mu.Unlock()

	stats := tr.GetActivityStats(user)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["a"])
	assert.Equal(t, 1, stats.ActionCounts["b"])
	assert.Equal(t, "a", stats.MostFrequent)
	assert.True(t, stats.FirstActivity.Equal(base.Add(-2*time.Hour)))
	assert.True(t, stats.LastActivity.Equal(base.Add(1 * time.Hour)))
}

func TestTracker_GetActivityByDateRange_InclusiveBoundsAndUnknownUser(t *testing.T) {
	tr := NewTracker()
	user := "range"
	// Create 5 activities; we'll adjust timestamps after creation
	_ = tr.LogActivity(user, "before", nil)   // index 0
	_ = tr.LogActivity(user, "atStart", nil)  // index 1
	_ = tr.LogActivity(user, "between", nil)  // index 2
	_ = tr.LogActivity(user, "atEnd", nil)    // index 3
	_ = tr.LogActivity(user, "after", nil)    // index 4

	base := time.Date(2025, 2, 2, 15, 0, 0, 0, time.UTC)
	start := base
	end := base.Add(2 * time.Hour)

	tr.mu.Lock()
	tr.activities[user][0].Timestamp = base.Add(-time.Minute)  // before
	tr.activities[user][1].Timestamp = start                   // atStart
	tr.activities[user][2].Timestamp = base.Add(time.Hour)     // between
	tr.activities[user][3].Timestamp = end                     // atEnd
	tr.activities[user][4].Timestamp = base.Add(3 * time.Hour) // after
	tr.mu.Unlock()

	// Inclusive at both ends
	got := tr.GetActivityByDateRange(user, start, end)
	// Should include atStart, between, atEnd, and preserve original order of those elements
	assert.Len(t, got, 3)
	assert.Equal(t, "atStart", got[0].Action)
	assert.Equal(t, "between", got[1].Action)
	assert.Equal(t, "atEnd", got[2].Action)

	// Unknown user returns empty
	assert.Empty(t, tr.GetActivityByDateRange("unknown", start, end))
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("c", "x", nil)
	tr.LogActivity("a", "x", nil)
	tr.LogActivity("b", "x", nil)
	tr.LogActivity("b", "y", nil) // multiple for same user still one user ID

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u1", "b", nil)
	tr.LogActivity("u2", "a", nil)

	// Delete existing
	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Empty(t, tr.GetActivityByUser("u1"))
	assert.Equal(t, []string{"u2"}, tr.GetAllUsers())

	// Delete non-existing
	ok2 := tr.DeleteUserActivity("u1")
	assert.False(t, ok2)
}

func TestGenerateID_FormatAndSuffix(t *testing.T) {
	id := generateID(65) // 'A'
	parts := strings.Split(id, "-")
	assert.Len(t, parts, 2)
	assert.Len(t, parts[0], 14) // "20060102150405" length
	for _, ch := range parts[0] {
		assert.True(t, ch >= '0' && ch <= '9')
	}
	assert.Equal(t, "A", parts[1])

	id2 := generateID(1)
	assert.True(t, strings.HasSuffix(id2, "-"+string(rune(1))))
}

func TestFindMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"view":  1,
		"login": 3,
		"click": 2,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}
