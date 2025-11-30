package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
}

func resetTraceStorage(t *testing.T) {
	t.Helper()
	traceMutex.Lock()
	traceStorage = make(map[string][]TraceData)
	traceMutex.Unlock()
}

func TestIsValidCorrelationID(t *testing.T) {
	tests := []struct {
		name string
		id   string
		ok   bool
	}{
		{"valid underscore dash", "abc_123-def", true},
		{"min length 10", "1234567890", true},
		{"max length 100", strings.Repeat("a", 100), true},
		{"too short", "short", false},
		{"too long", strings.Repeat("a", 101), false},
		{"invalid char", "abc$123", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isValidCorrelationID(tt.id)
			assert.Equal(t, tt.ok, got)
		})
	}
}

func TestGenerateCorrelationID_IsValid(t *testing.T) {
	id := generateCorrelationID()
	assert.True(t, len(id) >= 10)
	assert.True(t, validIDRegex.MatchString(id))
}

func TestExtractOrGenerateID_ValidHeader(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.Header.Set(CorrelationIDHeader, "valid-12345")
	id := ExtractOrGenerateID(r)
	assert.Equal(t, "valid-12345", id)
}

func TestExtractOrGenerateID_InvalidHeaderGeneratesNew(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.Header.Set(CorrelationIDHeader, "short")
	id := ExtractOrGenerateID(r)
	assert.NotEqual(t, "short", id)
	assert.True(t, isValidCorrelationID(id))
}

func TestExtractOrGenerateID_NoHeaderGeneratesNew(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	id := ExtractOrGenerateID(r)
	assert.True(t, isValidCorrelationID(id))
}

func TestCorrelationIDMiddleware_SetsHeader_StoresTrace_AndContext(t *testing.T) {
	resetTraceStorage(t)

	var ctxID string
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if v := r.Context().Value(CorrelationIDKey); v != nil {
			if s, ok := v.(string); ok {
				ctxID = s
			}
		}
		w.WriteHeader(http.StatusAccepted)
	})

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/widgets", nil)

	CorrelationIDMiddleware(h).ServeHTTP(rr, req)

	respID := rr.Header().Get(CorrelationIDHeader)
	require.NotEmpty(t, respID)
	require.Equal(t, ctxID, respID)

	traces := GetTraces(respID)
	require.Len(t, traces, 1)
	td := traces[0]
	assert.Equal(t, "go-parser", td.Service)
	assert.Equal(t, "POST", td.Method)
	assert.Equal(t, "/widgets", td.Path)
	assert.Equal(t, respID, td.CorrelationID)
	assert.Equal(t, http.StatusAccepted, td.Status)
	assert.True(t, td.DurationMS >= 0.0)
	assert.WithinDuration(t, time.Now(), td.Timestamp, time.Second)
}

func TestCorrelationIDMiddleware_UsesExistingValidHeader(t *testing.T) {
	resetTraceStorage(t)

	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/path", nil)
	req.Header.Set(CorrelationIDHeader, "valid-12345")

	CorrelationIDMiddleware(h).ServeHTTP(rr, req)

	assert.Equal(t, "valid-12345", rr.Header().Get(CorrelationIDHeader))

	traces := GetTraces("valid-12345")
	require.Len(t, traces, 1)
	assert.Equal(t, "GET", traces[0].Method)
	assert.Equal(t, "/path", traces[0].Path)
	assert.Equal(t, http.StatusOK, traces[0].Status)
}

func TestCorrelationIDMiddleware_ReplacesInvalidHeader(t *testing.T) {
	resetTraceStorage(t)

	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/path", nil)
	req.Header.Set(CorrelationIDHeader, "short")

	CorrelationIDMiddleware(h).ServeHTTP(rr, req)

	respID := rr.Header().Get(CorrelationIDHeader)
	require.NotEmpty(t, respID)
	assert.NotEqual(t, "short", respID)

	traces := GetTraces(respID)
	require.Len(t, traces, 1)

	tracesShort := GetTraces("short")
	assert.Len(t, tracesShort, 0)
}

func TestResponseWriter_DefaultStatusWhenNoWriteHeader(t *testing.T) {
	resetTraceStorage(t)

	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("ok"))
	})

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/", nil)

	CorrelationIDMiddleware(h).ServeHTTP(rr, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	cid := rr.Header().Get(CorrelationIDHeader)
	traces := GetTraces(cid)
	require.Len(t, traces, 1)
	assert.Equal(t, http.StatusOK, traces[0].Status)
}

func TestResponseWriter_MultipleWriteHeader_LastWinsInStoredTrace(t *testing.T) {
	resetTraceStorage(t)

	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusCreated) // 201
		w.WriteHeader(http.StatusTeapot)  // 418, second call
	})

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	CorrelationIDMiddleware(h).ServeHTTP(rr, req)

	assert.Equal(t, http.StatusCreated, rr.Code)

	cid := rr.Header().Get(CorrelationIDHeader)
	traces := GetTraces(cid)
	require.Len(t, traces, 1)
	assert.Equal(t, http.StatusTeapot, traces[0].Status)
}

func TestTrackRequest_WithHeader(t *testing.T) {
	resetTraceStorage(t)

	req := httptest.NewRequest(http.MethodDelete, "/delete", nil)
	req.Header.Set(CorrelationIDHeader, "valid-12345")

	TrackRequest(req, http.StatusBadRequest)

	traces := GetTraces("valid-12345")
	require.Len(t, traces, 1)
	td := traces[0]
	assert.Equal(t, "DELETE", td.Method)
	assert.Equal(t, "/delete", td.Path)
	assert.Equal(t, http.StatusBadRequest, td.Status)
	assert.Equal(t, "valid-12345", td.CorrelationID)
}

func TestTrackRequest_NoHeader_DoesNothing(t *testing.T) {
	resetTraceStorage(t)

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	TrackRequest(req, http.StatusOK)

	all := GetAllTraces()
	assert.Len(t, all, 0)
}

func TestGetTraces_ReturnsCopy(t *testing.T) {
	resetTraceStorage(t)

	id := "valid-12345"
	now := time.Now()

	storeTrace(id, TraceData{Service: "go-parser", CorrelationID: id, Timestamp: now, Status: 200})
	storeTrace(id, TraceData{Service: "go-parser", CorrelationID: id, Timestamp: now.Add(time.Millisecond), Status: 201})

	got := GetTraces(id)
	require.Len(t, got, 2)

	// mutate returned copy
	got[0].Status = 500

	// original should remain unchanged
	got2 := GetTraces(id)
	require.Len(t, got2, 2)
	assert.Equal(t, 200, got2[0].Status)
	assert.Equal(t, 201, got2[1].Status)
}

func TestGetAllTraces_ReturnsDeepCopy(t *testing.T) {
	resetTraceStorage(t)

	id1 := "valid-12345"
	id2 := "valid-67890"
	storeTrace(id1, TraceData{CorrelationID: id1, Status: 200})
	storeTrace(id2, TraceData{CorrelationID: id2, Status: 201})

	m := GetAllTraces()
	require.Len(t, m, 2)

	// mutate result
	m[id1][0].Status = 500
	delete(m, id2)

	// original storage should be unaffected
	m2 := GetAllTraces()
	require.Len(t, m2, 2)
	assert.Equal(t, 200, m2[id1][0].Status)
	assert.Equal(t, 201, m2[id2][0].Status)
}

func TestCleanupOldTraces_RemovesOldByFirstTimestamp(t *testing.T) {
	resetTraceStorage(t)

	oldID := "old-12345"
	newID := "new-12345"
	cutoff := time.Now().Add(-2 * time.Hour)
	recent := time.Now()

	// Set up traces: oldID has first trace old -> should be removed
	traceMutex.Lock()
	traceStorage[oldID] = []TraceData{
		{CorrelationID: oldID, Timestamp: cutoff},
		{CorrelationID: oldID, Timestamp: recent},
	}
	// newID has first trace recent -> should stay
	traceStorage[newID] = []TraceData{
		{CorrelationID: newID, Timestamp: recent},
		{CorrelationID: newID, Timestamp: recent},
	}
	traceMutex.Unlock()

	cleanupOldTraces()

	all := GetAllTraces()
	_, hasOld := all[oldID]
	_, hasNew := all[newID]

	assert.False(t, hasOld)
	assert.True(t, hasNew)
}