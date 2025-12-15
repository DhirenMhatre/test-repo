package activity

import (
	"strings"
	"sync"
	"testing"
	"time"
	"unicode"

	"github.com/stretchr/testify/assert"
)

func TestNewTracker_InitialState(t *testing.T) {
	tr := NewTracker()
	assert.NotNil(t, tr)
	assert.Empty(t, tr.GetAllUsers())
	assert.Empty(t, tr.GetActivityByUser("unknown"))
	stats := tr.GetActivityStats("unknown")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestLogActivity_AssignsIDAndStores(t *testing.T) {
	tr := NewTracker()
	u := "u1"

	log1 := tr.LogActivity(u, "login", map[string]interface{}{"ip": "127.0.0.1"})
	assert.NotNil(t, log1)
	assert.Equal(t, u, log1.UserID)
	assert.Equal(t, "login", log1.Action)
	assert.NotEmpty(t, log1.ID)
	assert.False(t, log1.Timestamp.IsZero())

	log2 := tr.LogActivity(u, "view", nil)
	assert.NotNil(t, log2)
	assert.NotEqual(t, log1.ID, log2.ID, "expected unique IDs for each activity")

	// ensure activities stored
	got := tr.GetActivityByUser(u)
	assert.Len(t, got, 2)
	assert.Equal(t, "login", got[0].Action)
	assert.Equal(t, "view", got[1].Action)
}

func TestGetActivityByUser_ReturnsCopyIsolationAndOrder(t *testing.T) {
	tr := NewTracker()
	u := "userA"

	tr.LogActivity(u, "a1", nil)
	tr.LogActivity(u, "a2", nil)
	tr.LogActivity(u, "a3", nil)

	orig := tr.GetActivityByUser(u)
	assert.Len(t, orig, 3)
	assert.Equal(t, []string{"a1", "a2", "a3"}, []string{orig[0].Action, orig[1].Action, orig[2].Action})

	// mutate returned slice; ensure internal state unaffected
	orig[0].Action = "hacked"
	after := tr.GetActivityByUser(u)
	assert.Equal(t, []string{"a1", "a2", "a3"}, []string{after[0].Action, after[1].Action, after[2].Action})
}

func TestGetActivityStats_WithLogs(t *testing.T) {
	tr := NewTracker()
	u := "statsUser"

	// Create three activities; then normalize timestamps and actions deterministically
	tr.LogActivity(u, "x", nil)
	tr.LogActivity(u, "y", nil)
	tr.LogActivity(u, "x", nil)

	base := time.Date(2025, 1, 2, 3, 4, 5, 0, time.UTC)
	tr.mu.Lock()
	// Ensure deterministic timestamps and actions
	if logs := tr.activities[u]; len(logs) == 3 {
		tr.activities[u][0].Timestamp = base.Add(0 * time.Second)
		tr.activities[u][0].Action = "alpha"
		tr.activities[u][1].Timestamp = base.Add(10 * time.Second)
		tr.activities[u][1].Action = "beta"
		tr.activities[u][2].Timestamp = base.Add(20 * time.Second)
		tr.activities[u][2].Action = "alpha"
	}
	tr.mu.Unlock()

	stats := tr.GetActivityStats(u)
	assert.Equal(t, 3, stats.TotalActions)
	assert.Equal(t, 2, stats.UniqueActions)
	assert.Equal(t, 2, stats.ActionCounts["alpha"])
	assert.Equal(t, 1, stats.ActionCounts["beta"])
	assert.Equal(t, base, stats.FirstActivity)
	assert.Equal(t, base.Add(20*time.Second), stats.LastActivity)
	assert.Equal(t, "alpha", stats.MostFrequent)
}

func TestGetActivityStats_NoLogs(t *testing.T) {
	tr := NewTracker()
	stats := tr.GetActivityStats("nope")
	assert.Equal(t, 0, stats.TotalActions)
	assert.Equal(t, 0, stats.UniqueActions)
	assert.Empty(t, stats.ActionCounts)
	assert.True(t, stats.FirstActivity.IsZero())
	assert.True(t, stats.LastActivity.IsZero())
	assert.Equal(t, "", stats.MostFrequent)
}

func TestGetActivityByDateRange_TableDriven(t *testing.T) {
	tr := NewTracker()
	u := "rangeUser"

	a1 := tr.LogActivity(u, "a", nil)
	a2 := tr.LogActivity(u, "b", nil)
	a3 := tr.LogActivity(u, "c", nil)

	base := time.Date(2025, 6, 1, 12, 0, 0, 0, time.UTC)
	tr.mu.Lock()
	if logs := tr.activities[u]; len(logs) == 3 {
		tr.activities[u][0].Timestamp = base.Add(0 * time.Second)   // a1
		tr.activities[u][1].Timestamp = base.Add(60 * time.Second)  // a2
		tr.activities[u][2].Timestamp = base.Add(120 * time.Second) // a3
	}
	tr.mu.Unlock()

	tests := []struct {
		name      string
		start     time.Time
		end       time.Time
		wantIDs   map[string]struct{}
		wantCount int
	}{
		{
			name:      "include boundaries both ends",
			start:     base.Add(60 * time.Second),
			end:       base.Add(120 * time.Second),
			wantIDs:   map[string]struct{}{a2.ID: {}, a3.ID: {}},
			wantCount: 2,
		},
		{
			name:      "single point exact match",
			start:     base,
			end:       base,
			wantIDs:   map[string]struct{}{a1.ID: {}},
			wantCount: 1,
		},
		{
			name:      "no matches",
			start:     base.Add(-10 * time.Minute),
			end:       base.Add(-9 * time.Minute),
			wantIDs:   map[string]struct{}{},
			wantCount: 0,
		},
		{
			name:      "all three",
			start:     base,
			end:       base.Add(120 * time.Second),
			wantIDs:   map[string]struct{}{a1.ID: {}, a2.ID: {}, a3.ID: {}},
			wantCount: 3,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tr.GetActivityByDateRange(u, tt.start, tt.end)
			assert.Len(t, got, tt.wantCount)
			for _, g := range got {
				_, ok := tt.wantIDs[g.ID]
				assert.True(t, ok, "unexpected ID in results: %s", g.ID)
			}
		})
	}
}

func TestGetAllUsers_Sorted(t *testing.T) {
	tr := NewTracker()
	users := []string{"u3", "u1", "u2"}
	for _, u := range users {
		tr.LogActivity(u, "act", nil)
	}

	got := tr.GetAllUsers()
	assert.Equal(t, []string{"u1", "u2", "u3"}, got)
}

func TestDeleteUserActivity(t *testing.T) {
	tr := NewTracker()
	u1 := "toDelete"
	u2 := "stay"

	tr.LogActivity(u1, "a", nil)
	tr.LogActivity(u1, "b", nil)
	tr.LogActivity(u2, "c", nil)

	ok := tr.DeleteUserActivity(u1)
	assert.True(t, ok, "expected delete to succeed")

	assert.Empty(t, tr.GetActivityByUser(u1), "expected all activities for u1 deleted")
	assert.Len(t, tr.GetActivityByUser(u2), 1, "other user's activities should remain")

	ok2 := tr.DeleteUserActivity("missing")
	assert.False(t, ok2, "expected delete to fail for missing user")
}

func TestGenerateID_Format(t *testing.T) {
	id := generateID(65) // 'A'
	parts := strings.Split(id, "-")
	assert.Len(t, parts, 2, "expected ID to contain single hyphen")
	prefix := parts[0]
	suffix := parts[1]

	assert.Equal(t, "A", suffix, "expected rune suffix to match counter as rune")
	assert.Len(t, prefix, 14, "expected timestamp prefix length 14 (YYYYMMDDhhmmss)")

	for _, r := range prefix {
		assert.True(t, unicode.IsDigit(r), "non-digit in timestamp prefix: %q", r)
	}
}

func TestFindMostFrequentAction(t *testing.T) {
	tests := []struct {
		name   string
		input  map[string]int
		expect string
	}{
		{
			name:   "simple winner",
			input:  map[string]int{"a": 3, "b": 1, "c": 2},
			expect: "a",
		},
		{
			name:   "empty map",
			input:  map[string]int{},
			expect: "",
		},
		{
			name:   "single entry",
			input:  map[string]int{"only": 7},
			expect: "only",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := findMostFrequentAction(tt.input)
			assert.Equal(t, tt.expect, got)
		})
	}
}

func TestConcurrentLogActivity(t *testing.T) {
	tr := NewTracker()
	users := []string{"u1", "u2", "u3", "u4", "u5"}
	var wg sync.WaitGroup

	n := 200
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			u := users[i%len(users)]
			tr.LogActivity(u, "act", map[string]interface{}{"i": i})
		}(i)
	}
	wg.Wait()

	total := 0
	for _, u := range users {
		total += len(tr.GetActivityByUser(u))
	}
	assert.Equal(t, n, total, "expected all activities to be logged")
	assert.ElementsMatch(t, users, tr.GetAllUsers())
}
