package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func resetTraces(t *testing.T) {
	traceMutex.Lock()
	defer traceMutex.Unlock()
	traceStorage = make(map[string][]TraceData)
}

func TestIsValidCorrelationID(t *testing.T) {
	tests := []struct {
		name string
		id   string
		want bool
	}{
		{"valid with hyphen and underscore", "abc_123-XYZ-7890", true},
		{"too short", "short-123", false}, // 9 chars
		{"exactly 10", "abcdefghij", true},
		{"too long", strings.Repeat("a", 101), false},
		{"invalid chars", "abc$def-123", false},
		{"valid long", strings.Repeat("a", 50) + "-ok", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isValidCorrelationID(tt.id)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestGenerateCorrelationID_ValidAndDifferent(t *testing.T) {
	id1 := generateCorrelationID()
	time.Sleep(1 * time.Millisecond)
	id2 := generateCorrelationID()

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.True(t, isValidCorrelationID(id1))
	assert.True(t, isValidCorrelationID(id2))
	assert.Contains(t, id1, "-go-")
	assert.Contains(t, id2, "-go-")
}

func TestExtractOrGenerateID(t *testing.T) {
	// Valid existing
	req1 := httptest.NewRequest(http.MethodGet, "/a", nil)
	req1.Header.Set(CorrelationIDHeader, "valid-abc_12345")
	id1 := ExtractOrGenerateID(req1)
	assert.Equal(t, "valid-abc_12345", id1)

	// Invalid existing -> generate new
	req2 := httptest.NewRequest(http.MethodGet, "/b", nil)
	req2.Header.Set(CorrelationIDHeader, "bad!") // invalid char
	id2 := ExtractOrGenerateID(req2)
	assert.NotEqual(t, "bad!", id2)
	assert.True(t, isValidCorrelationID(id2))

	// Missing header -> generate new
	req3 := httptest.NewRequest(http.MethodGet, "/c", nil)
	id3 := ExtractOrGenerateID(req3)
	assert.True(t, isValidCorrelationID(id3))
}

func TestCorrelationIDMiddleware_SetsHeader_ContextAndStoresTrace_Implicit200(t *testing.T) {
	resetTraces(t)

	var ctxID string

	handler := CorrelationIDMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if v := r.Context().Value(CorrelationIDKey); v != nil {
			if s, ok := v.(string); ok {
				ctxID = s
			}
		}
		_, _ = w.Write([]byte("OK"))
	}))

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/test-path", nil)

	handler.ServeHTTP(rr, req)

	respID := rr.Header().Get(CorrelationIDHeader)
	assert.NotEmpty(t, respID)
	assert.Equal(t, respID, ctxID)
	assert.Equal(t, http.StatusOK, rr.Code)

	traces := GetTraces(ctxID)
	if assert.Len(t, traces, 1) {
		td := traces[0]
		assert.Equal(t, "go-parser", td.Service)
		assert.Equal(t, http.MethodGet, td.Method)
		assert.Equal(t, "/test-path", td.Path)
		assert.Equal(t, ctxID, td.CorrelationID)
		assert.Equal(t, http.StatusOK, td.Status)
		assert.GreaterOrEqual(t, td.DurationMS, 0.0)
		assert.WithinDuration(t, time.Now(), td.Timestamp, time.Second)
	}
}

func TestCorrelationIDMiddleware_PropagatesIncomingValidIDAndStoresStatus(t *testing.T) {
	resetTraces(t)

	incomingID := "incoming-abc_12345"

	handler := CorrelationIDMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTeapot)
	}))

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/status", nil)
	req.Header.Set(CorrelationIDHeader, incomingID)

	handler.ServeHTTP(rr, req)

	respID := rr.Header().Get(CorrelationIDHeader)
	assert.Equal(t, incomingID, respID)
	assert.Equal(t, http.StatusTeapot, rr.Code)

	traces := GetTraces(incomingID)
	if assert.Len(t, traces, 1) {
		assert.Equal(t, http.StatusTeapot, traces[0].Status)
	}
}

func TestCorrelationIDMiddleware_GeneratesWhenIncomingInvalid(t *testing.T) {
	resetTraces(t)

	handler := CorrelationIDMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated)
	}))

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/invalid", nil)
	req.Header.Set(CorrelationIDHeader, "bad!") // invalid

	handler.ServeHTTP(rr, req)

	respID := rr.Header().Get(CorrelationIDHeader)
	assert.NotEqual(t, "bad!", respID)
	assert.True(t, isValidCorrelationID(respID))

	traces := GetTraces(respID)
	if assert.Len(t, traces, 1) {
		assert.Equal(t, http.StatusCreated, traces[0].Status)
	}
}

func TestTrackRequest_StoresWhenHeaderPresent(t *testing.T) {
	resetTraces(t)

	id := "test-123456789"
	req := httptest.NewRequest(http.MethodPost, "/track", nil)
	req.Header.Set(CorrelationIDHeader, id)

	TrackRequest(req, http.StatusCreated)

	traces := GetTraces(id)
	if assert.Len(t, traces, 1) {
		assert.Equal(t, "go-parser", traces[0].Service)
		assert.Equal(t, http.StatusCreated, traces[0].Status)
		assert.Equal(t, http.MethodPost, traces[0].Method)
		assert.Equal(t, "/track", traces[0].Path)
	}
}

func TestTrackRequest_NoHeader_NoStore(t *testing.T) {
	resetTraces(t)

	req := httptest.NewRequest(http.MethodGet, "/no-store", nil)

	TrackRequest(req, http.StatusOK)

	all := GetAllTraces()
	assert.Len(t, all, 0)
}

func TestGetTracesAndGetAllTraces_ReturnCopies(t *testing.T) {
	resetTraces(t)

	id := "copy-123456789"
	td1 := TraceData{CorrelationID: id, Timestamp: time.Now()}
	td2 := TraceData{CorrelationID: id, Timestamp: time.Now()}
	storeTrace(id, td1)
	storeTrace(id, td2)

	// GetTraces returns a copy of the slice
	ts := GetTraces(id)
	assert.Len(t, ts, 2)
	ts = append(ts, TraceData{CorrelationID: id})
	assert.Len(t, ts, 3)

	// Original storage remains unchanged
	ts2 := GetTraces(id)
	assert.Len(t, ts2, 2)

	// Mutate returned element and ensure original isn't affected
	ts2[0].Status = 999
	ts3 := GetTraces(id)
	assert.NotEqual(t, 999, ts3[0].Status)

	// GetAllTraces returns a copy of map and slices
	all := GetAllTraces()
	assert.Len(t, all, 1)
	all[id] = nil
	all2 := GetAllTraces()
	assert.Len(t, all2[id], 2)

	// Mutate inner slice
	all2[id][0].Status = 888
	ts4 := GetTraces(id)
	assert.NotEqual(t, 888, ts4[0].Status)
}

func TestCleanupOldTraces_RemovesExpired(t *testing.T) {
	resetTraces(t)

	oldID := "old-123456789"
	newID := "new-123456789"

	traceMutex.Lock()
	traceStorage[oldID] = []TraceData{{CorrelationID: oldID, Timestamp: time.Now().Add(-2 * time.Hour)}}
	traceStorage[newID] = []TraceData{{CorrelationID: newID, Timestamp: time.Now()}}
	traceMutex.Unlock()

	cleanupOldTraces()

	all := GetAllTraces()
	_, hasOld := all[oldID]
	_, hasNew := all[newID]
	assert.False(t, hasOld)
	assert.True(t, hasNew)
}

func TestResponseWriter_WriteHeader_SetsStatusAndPropagates(t *testing.T) {
	rr := httptest.NewRecorder()
	rw := &responseWriter{ResponseWriter: rr, statusCode: http.StatusOK}

	rw.WriteHeader(http.StatusCreated)

	assert.Equal(t, http.StatusCreated, rw.statusCode)
	assert.Equal(t, http.StatusCreated, rr.Code)
}
