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
	assert.Equal(t, 0, len(tr.activities))
	assert.Equal(t, 0, tr.idCounter)
}

func TestTracker_LogActivity_AssignsAndStores(t *testing.T) {
	tr := NewTracker()
	meta := map[string]interface{}{"ip": "127.0.0.1"}

	log := tr.LogActivity("u1", "login", meta)

	assert.NotNil(t, log)
	assert.NotEmpty(t, log.ID)
	assert.Equal(t, "u1", log.UserID)
	assert.Equal(t, "login", log.Action)
	assert.Equal(t, meta, log.Metadata)
	assert.False(t, log.Timestamp.IsZero())

	logs := tr.GetActivityByUser("u1")
	assert.Len(t, logs, 1)
	assert.Equal(t, log.ID, logs[0].ID)
	assert.Equal(t, "login", logs[0].Action)
}

func TestTracker_GetActivityByUser_Empty(t *testing.T) {
	tr := NewTracker()
	got := tr.GetActivityByUser("missing")
	assert.NotNil(t, got)
	assert.Len(t, got, 0)
}

func TestTracker_GetActivityByUser_ReturnsCopy(t *testing.T) {
	tr := NewTracker()
	a1 := tr.LogActivity("u1", "a1", nil)
	tr.LogActivity("u1", "a2", nil)

	// Modify returned slice; internal state should remain unchanged.
	ret := tr.GetActivityByUser("u1")
	assert.Len(t, ret, 2)
	ret[0].Action = "changed"
	ret = append(ret[:0], ret[1:]...)

	ret2 := tr.GetActivityByUser("u1")
	assert.Len(t, ret2, 2)
	assert.Equal(t, "a1", ret2[0].Action)
	assert.Equal(t, a1.ID, ret2[0].ID)
}

func TestTracker_GetActivityStats_EmptyUser(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("ghost")

	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.NotNil(t, stats.ActionCounts)
	assert.Len(t, stats.ActionCounts, 0)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestTracker_GetActivityStats_WithData(t *testing.T) {
	tr := NewTracker()

	a1 := tr.LogActivity("u2", "login", nil)
	time.Sleep(25 * time.Millisecond)
	a2 := tr.LogActivity("u2", "click", nil)
	time.Sleep(25 * time.Millisecond)
	a3 := tr.LogActivity("u2", "click", nil)

	stats := tr.GetActivityStats("u2")

	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 1, stats.ActionCounts["login"])
	assert.Equal(t, 2, stats.ActionCounts["click"])
	assert.Equal(t, "click", stats.MostFrequent)

	assert.True(t, stats.FirstActivity.Equal(a1.Timestamp))
	assert.True(t, stats.LastActivity.Equal(a3.Timestamp))
	assert.False(t, stats.FirstActivity.After(stats.LastActivity))
}

func TestTracker_GetActivityByDateRange_InclusiveAndFiltering(t *testing.T) {
	tr := NewTracker()

	a1 := tr.LogActivity("u3", "act1", nil)
	time.Sleep(25 * time.Millisecond)
	a2 := tr.LogActivity("u3", "act2", nil)
	time.Sleep(25 * time.Millisecond)
	a3 := tr.LogActivity("u3", "act3", nil)

	// Inclusive of same start and end
	onlyA2 := tr.GetActivityByDateRange("u3", a2.Timestamp, a2.Timestamp)
	assert.Len(t, onlyA2, 1)
	assert.Equal(t, a2.ID, onlyA2[0].ID)

	// Inclusive start..end - verify order
	a1a2 := tr.GetActivityByDateRange("u3", a1.Timestamp, a2.Timestamp)
	assert.Len(t, a1a2, 2)
	ids := []string{a1a2[0].ID, a1a2[1].ID}
	assert.Equal(t, []string{a1.ID, a2.ID}, ids)

	a2a3 := tr.GetActivityByDateRange("u3", a2.Timestamp, a3.Timestamp)
	assert.Len(t, a2a3, 2)
	ids = []string{a2a3[0].ID, a2a3[1].ID}
	assert.Equal(t, []string{a2.ID, a3.ID}, ids)

	none := tr.GetActivityByDateRange("missing", a1.Timestamp, a3.Timestamp)
	assert.Len(t, none, 0)
}

func TestTracker_GetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("c", "x", nil)
	tr.LogActivity("a", "x", nil)
	tr.LogActivity("b", "x", nil)
	// Duplicate user should not duplicate in list
	tr.LogActivity("b", "y", nil)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"a", "b", "c"}, users)
}

func TestTracker_DeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	tr.LogActivity("u1", "a", nil)
	tr.LogActivity("u1", "b", nil)
	tr.LogActivity("u2", "c", nil)

	ok := tr.DeleteUserActivity("u1")
	assert.True(t, ok)

	users := tr.GetAllUsers()
	assert.Equal(t, []string{"u2"}, users)

	u1Logs := tr.GetActivityByUser("u1")
	assert.Len(t, u1Logs, 0)

	ok2 := tr.DeleteUserActivity("u1")
	assert.False(t, ok2)

	ok3 := tr.DeleteUserActivity("missing")
	assert.False(t, ok3)
}

func Test_generateID_UniquenessAndHyphen(t *testing.T) {
	id1 := generateID(1)
	id2 := generateID(2)

	assert.NotEqual(t, id1, id2)
	assert.Contains(t, id1, "-")

	parts := strings.SplitN(id1, "-", 2)
	assert.Len(t, parts, 2)
	assert.GreaterOrEqual(t, len(parts[1]), 1)
}

func Test_findMostFrequentAction(t *testing.T) {
	assert.Equal(t, "", findMostFrequentAction(map[string]int{}))

	counts := map[string]int{
		"login":    5,
		"click":    3,
		"purchase": 2,
	}
	assert.Equal(t, "login", findMostFrequentAction(counts))
}