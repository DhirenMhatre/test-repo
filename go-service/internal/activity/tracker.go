package activity

import (
	"sort"
	"sync"
	"time"
)

type ActivityLog struct {
	ID        string                 `json:"id"`
	UserID    string                 `json:"user_id"`
	Action    string                 `json:"action"`
	Timestamp time.Time              `json:"timestamp"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

type ActivityStats struct {
	TotalActions  int               `json:"total_actions"`
	UniqueActions int               `json:"unique_actions"`
	ActionCounts  map[string]int    `json:"action_counts"`
	FirstActivity time.Time         `json:"first_activity"`
	LastActivity  time.Time         `json:"last_activity"`
	MostFrequent  string            `json:"most_frequent_action"`
}

type Tracker struct {
	mu         sync.RWMutex
	activities map[string][]ActivityLog // key: user_id
	idCounter  int
}

func NewTracker() *Tracker {
	return &Tracker{
		activities: make(map[string][]ActivityLog),
		idCounter:  0,
	}
}

func (t *Tracker) LogActivity(userID, action string, metadata map[string]interface{}) *ActivityLog {
	t.mu.Lock()
	defer t.mu.Unlock()

	t.idCounter++
	log := ActivityLog{
		ID:        generateID(t.idCounter),
		UserID:    userID,
		Action:    action,
		Timestamp: time.Now(),
		Metadata:  metadata,
	}

	t.activities[userID] = append(t.activities[userID], log)
	return &log
}

func (t *Tracker) GetActivityByUser(userID string) []ActivityLog {
	t.mu.RLock()
	defer t.mu.RUnlock()

	logs, exists := t.activities[userID]
	if !exists {
		return []ActivityLog{}
	}

	result := make([]ActivityLog, len(logs))
	copy(result, logs)
	return result
}

func (t *Tracker) GetActivityStats(userID string) *ActivityStats {
	t.mu.RLock()
	defer t.mu.RUnlock()

	logs, exists := t.activities[userID]
	if !exists || len(logs) == 0 {
		return &ActivityStats{
			TotalActions:  0,
			UniqueActions: 0,
			ActionCounts:  make(map[string]int),
		}
	}

	actionCounts := make(map[string]int)
	var firstActivity, lastActivity time.Time
	firstActivity = logs[0].Timestamp
	lastActivity = logs[0].Timestamp

	for _, log := range logs {
		actionCounts[log.Action]++
		if log.Timestamp.Before(firstActivity) {
			firstActivity = log.Timestamp
		}
		if log.Timestamp.After(lastActivity) {
			lastActivity = log.Timestamp
		}
	}

	mostFrequent := findMostFrequentAction(actionCounts)

	return &ActivityStats{
		TotalActions:  len(logs),
		UniqueActions: len(actionCounts),
		ActionCounts:  actionCounts,
		FirstActivity: firstActivity,
		LastActivity:  lastActivity,
		MostFrequent:  mostFrequent,
	}
}

func (t *Tracker) GetActivityByDateRange(userID string, start, end time.Time) []ActivityLog {
	t.mu.RLock()
	defer t.mu.RUnlock()

	logs, exists := t.activities[userID]
	if !exists {
		return []ActivityLog{}
	}

	var filtered []ActivityLog
	for _, log := range logs {
		if (log.Timestamp.Equal(start) || log.Timestamp.After(start)) &&
			(log.Timestamp.Equal(end) || log.Timestamp.Before(end)) {
			filtered = append(filtered, log)
		}
	}

	return filtered
}

func (t *Tracker) GetAllUsers() []string {
	t.mu.RLock()
	defer t.mu.RUnlock()

	users := make([]string, 0, len(t.activities))
	for userID := range t.activities {
		users = append(users, userID)
	}

	sort.Strings(users)
	return users
}

func (t *Tracker) DeleteUserActivity(userID string) bool {
	t.mu.Lock()
	defer t.mu.Unlock()

	if _, exists := t.activities[userID]; !exists {
		return false
	}

	delete(t.activities, userID)
	return true
}

func generateID(counter int) string {
	return time.Now().Format("20060102150405") + "-" + string(rune(counter))
}

func findMostFrequentAction(actionCounts map[string]int) string {
	if len(actionCounts) == 0 {
		return ""
	}

	maxCount := 0
	mostFrequent := ""

	for action, count := range actionCounts {
		if count > maxCount {
			maxCount = count
			mostFrequent = action
		}
	}

	return mostFrequent
}
