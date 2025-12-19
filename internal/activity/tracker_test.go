package activity

import (
	"fmt"
	"sort"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type ActivityLog struct {
	ID        string
	UserID    string
	Action    string
	Timestamp time.Time
	Metadata  map[string]interface{}
}

type ActivityStats struct {
	TotalActions  int
	UniqueActions int
	ActionCounts  map[string]int
	FirstActivity time.Time
	LastActivity  time.Time
	MostFrequent  string
}

type Tracker struct {
	activities map[string][]ActivityLog
	counter    uint64
}

func NewTracker() *Tracker {
	return &Tracker{
		activities: make(map[string][]ActivityLog),
	}
}

func (t *Tracker) LogActivity(userID, action string, metadata map[string]interface{}) *ActivityLog {
	if t == nil {
		return nil
	}
	cnt := atomic.AddUint64(&t.counter, 1)
	id := generateID(int(cnt))
	log := ActivityLog{
		ID:        id,
		UserID:    userID,
		Action:    action,
		Timestamp: time.Now(),
		Metadata:  metadata,
	}
	t.activities[userID] = append(t.activities[userID], log)
	return &log
}

func (t *Tracker) GetActivityByUser(userID string) []ActivityLog {
	if t == nil {
		return []ActivityLog{}
	}
	src := t.activities[userID]
	if len(src) == 0 {
		return []ActivityLog{}
	}
	dst := make([]ActivityLog, len(src))
	copy(dst, src)
	return dst
}

func (t *Tracker) GetActivityStats(userID string) *ActivityStats {
	stats := &ActivityStats{
		ActionCounts: make(map[string]int),
	}
	if t == nil {
		return stats
	}
	logs := t.activities[userID]
	if len(logs) == 0 {
		return stats
	}
	for i, l := range logs {
		stats.TotalActions++
		stats.ActionCounts[l.Action]++
		if i == 0 || l.Timestamp.Before(stats.FirstActivity) {
			stats.FirstActivity = l.Timestamp
		}
		if i == 0 || l.Timestamp.After(stats.LastActivity) {
			stats.LastActivity = l.Timestamp
		}
	}
	stats.UniqueActions = len(stats.ActionCounts)
	stats.MostFrequent = findMostFrequentAction(stats.ActionCounts)
	return stats
}

func (t *Tracker) GetActivityByDateRange(userID string, start, end time.Time) []ActivityLog {
	if t == nil {
		return []ActivityLog{}
	}
	if start.After(end) {
		return []ActivityLog{}
	}
	src := t.activities[userID]
	if len(src) == 0 {
		return []ActivityLog{}
	}
	res := make([]ActivityLog, 0, len(src))
	for _, l := range src {
		if (l.Timestamp.Equal(start) || l.Timestamp.After(start)) && (l.Timestamp.Equal(end) || l.Timestamp.Before(end)) {
			res = append(res, l)
		}
	}
	return res
}

func (t *Tracker) GetAllUsers() []string {
	if t == nil {
		return []string{}
	}
	users := make([]string, 0, len(t.activities))
	for u := range t.activities {
		users = append(users, u)
	}
	sort.Strings(users)
	return users
}

func (t *Tracker) DeleteUserActivity(userID string) bool {
	if t == nil {
		return false
	}
	if _, ok := t.activities[userID]; ok {
		delete(t.activities, userID)
		return true
	}
	return false
}

func generateID(counter int) string {
	return fmt.Sprintf("%d-%s", time.Now().UnixNano(), string(rune(counter)))
}

func findMostFrequentAction(m map[string]int) string {
	maxCount := -1
	var result string
	for k, v := range m {
		if v > maxCount {
			maxCount = v
			result = k
		}
	}
	return result
}

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	require.NotNil(t, tr)

	users := tr.GetAllUsers()
	assert.Empty(t, users)

	// Unknown user returns empty slice, not nil
	logs := tr.GetActivityByUser("unknown")
	assert.NotNil(t, logs)
	assert.Len(t, logs, 0)
}

func TestTracker_LogActivity_AssignsIDAndTimestamp(t *testing.T) {
	tr := NewTracker()

	before := time.Now()
	first := tr.LogActivity("u1", "login", map[string]interface{}{"ip": "127.0.0.1"})
	after := time.Now()

	require.NotNil(t, first)
	assert.NotEmpty(t, first.ID)
	assert.Equal(t, "u1", first.UserID)
	assert.Equal(t, "login", first.Action)
	assert.WithinRange(t, first.Timestamp, before, after)
	assert.Equal(t, "127.0.0.1", first.Metadata["ip"])

	second := tr.LogActivity("u1", "view", nil)
	require.NotNil(t, second)
	assert.NotEmpty(t, second.ID)
	assert.NotEqual(t, first.ID, second.ID, "IDs should be unique per call")

	// Ensure order of insertion is preserved in GetActivityByUser
	logs := tr.GetActivityByUser("u1")
	require.Len(t, logs, 2)
	assert.Equal(t, first.ID, logs[0].ID)
	assert.Equal(t, second.ID, logs[1].ID)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	l := tr.LogActivity("u1", "act", map[string]interface{}{"k": "v"})
	require.NotNil(t, l)

	logs := tr.GetActivityByUser("u1")
	require.Len(t, logs, 1)
	// Mutate returned slice and element, ensure internal state unaffected
	logs[0].Action = "mutated"
	logs = append(logs, ActivityLog{ID: "x"})
	logs2 := tr.GetActivityByUser("u1")
	require.Len(t, logs2, 1)
	assert.Equal(t, "act", logs2[0].Action)
}

func TestTracker_GetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()

	stats := tr.GetActivityStats("missing")
	assert.NotNil(t, stats)
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	require.NotNil(t, stats.ActionCounts)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_ComputedFields(t *testing.T) {
	tr := NewTracker()

	base := time.Date(2025, 1, 2, 3, 4, 5, 0, time.UTC)
	// Seed controlled logs directly
	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "login", Timestamp: base.Add(10 * time.Minute)},
		{ID: "2", UserID: "u1", Action: "view", Timestamp: base.Add(-5 * time.Minute)},
		{ID: "3", UserID: "u1", Action: "view", Timestamp: base.Add(20 * time.Minute)},
		{ID: "4", UserID: "u1", Action: "logout", Timestamp: base.Add(25 * time.Minute)},
	}

	stats := tr.GetActivityStats("u1")
	require.NotNil(t, stats)
	assert.Equal(t, 4, stats.TotalActions)
	assert.Equal(t, 3, stats.UniqueActions)

	require.Len(t, stats.ActionCounts, 3)
	assert.Equal(t, 2, stats.ActionCounts["view"])
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, 1, stats.ActionCounts["logout"])

	assert.Equal(t, base.Add(-5*time.Minute), stats.FirstActivity)
	assert.Equal(t, base.Add(25*time.Minute), stats.LastActivity)
	assert.Equal(t, "view", stats.MostFrequent)
}

func TestTracker_GetActivityByDateRange_InclusiveAndUnknownUser(t *testing.T) {
	tr := NewTracker()
	base := time.Date(2025, 2, 1, 12, 0, 0, 0, time.UTC)

	tr.activities["u1"] = []ActivityLog{
		{ID: "1", UserID: "u1", Action: "a", Timestamp: base.Add(-2 * time.Hour)},
		{ID: "2", UserID: "u1", Action: "b", Timestamp: base},                    // exactly at start
		{ID: "3", UserID: "u1", Action: "c", Timestamp: base.Add(2 * time.Hour)}, // exactly at end (we'll set end accordingly)
	}

	// Unknown user => empty
	unknown := tr.GetActivityByDateRange("unknown", base.Add(-24*time.Hour), base.Add(24*time.Hour))
	assert.Empty(t, unknown)

	// Inclusive start
	r1 := tr.GetActivityByDateRange("u1", base, base.Add(90*time.Minute))
	require.Len(t, r1, 1)
	assert.Equal(t, "2", r1[0].ID)

	// Inclusive end
	r2 := tr.GetActivityByDateRange("u1", base.Add(90*time.Minute), base.Add(2*time.Hour))
	require.Len(t, r2, 1)
	assert.Equal(t, "3", r2[0].ID)

	// Whole range including all
	r3 := tr.GetActivityByDateRange("u1", base.Add(-2*time.Hour), base.Add(2*time.Hour))
	require.Len(t, r3, 3)

	// Start after end -> no results
	r4 := tr.GetActivityByDateRange("u1", base.Add(3*time.Hour), base.Add(2*time.Hour))
	assert.Len(t, r4, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.activities["z"] = []ActivityLog{{ID: "1", UserID: "z"}}
	tr.activities["a"] = []ActivityLog{{ID: "2", UserID: "a"}}
	tr.activities["m"] = []ActivityLog{{ID: "3", UserID: "m"}}
	// Duplicate user entries should not duplicate users in list
	tr.activities["a"] = append(tr.activities["a"], ActivityLog{ID: "4", UserID: "a"})

	users := tr.GetAllUsers()
	require.Equal(t, []string{"a", "m", "z"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.activities["u1"] = []ActivityLog{{ID: "1", UserID: "u1"}}

	// Delete existing
	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)
	assert.Empty(t, tr.GetActivityByUser("u1"))

	// Delete non-existing
	ok = tr.DeleteUserActivity("nope")
	assert.False(t, ok)
}

func Test_generateID_SuffixByCounterAndUniqueness(t *testing.T) {
	id := generateID(65) // 'A'
	require.NotEmpty(t, id)
	assert.Contains(t, id, "-")
	assert.HasSuffix(t, id, "-A")

	// Different counters produce different IDs even within same second
	id2 := generateID(66) // 'B'
	assert.NotEqual(t, id, id2)
	assert.HasSuffix(t, id2, "-B")
}

func Test_findMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	m := map[string]int{
		"view":  3,
		"login": 1,
		"edit":  2,
	}
	assert.Equal(t, "view", findMostFrequentAction(m))
}
