package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func resetTraceStorage(t *testing.T) {
	traceMutex.Lock()
	traceStorage = make(map[string][]TraceData)
	traceMutex.Unlock()
}

func TestIsValidCorrelationID(t *testing.T) {
	tests := []struct {
		name string
		id   string
		want bool
	}{
		{
			name: "too short",
			id:   "short",
			want: false,
		},
		{
			name: "min length valid (10 chars)",
			id:   "abcdefghij",
			want: true,
		},
		{
			name: "max length valid (100 chars)",
			id:   "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			want: true,
		},
		{
			name: "too long (101 chars)",
			id:   "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			want: false,
		},
		{
			name: "invalid characters",
			id:   "abc$%defghi",
			want: false,
		},
		{
			name: "valid with hyphen and underscore",
			id:   "valid-id_with_underscore",
			want: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isValidCorrelationID(tt.id)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestGenerateCorrelationID_IsValidAndUnique(t *testing.T) {
	id1 := generateCorrelationID()
	id2 := generateCorrelationID()

	assert.NotEmpty(t, id1)
	assert.NotEmpty(t, id2)
	assert.NotEqual(t, id1, id2)
	assert.True(t, isValidCorrelationID(id1))
	assert.True(t, isValidCorrelationID(id2))
}

func TestExtractOrGenerateID_UsesValidHeader(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/path", nil)
	req.Header.Set(CorrelationIDHeader, "valid-header_12345")

	got := ExtractOrGenerateID(req)
	assert.Equal(t, "valid-header_12345", got)
}

func TestExtractOrGenerateID_IgnoresInvalidHeaderAndGenerates(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/path", nil)
	req.Header.Set(CorrelationIDHeader, "bad$id")

	got := ExtractOrGenerateID(req)
	assert.NotEmpty(t, got)
	assert.NotEqual(t, "bad$id", got)
	assert.True(t, isValidCorrelationID(got))
}

func TestTrackRequest_WithHeader_StoresTrace(t *testing.T) {
	resetTraceStorage(t)

	req := httptest.NewRequest(http.MethodPost, "/submit", nil)
	cid := "valid-corrid_123456"
	req.Header.Set(CorrelationIDHeader, cid)

	TrackRequest(req, http.StatusCreated)

	traces := GetTraces(cid)
	if assert.Len(t, traces, 1) {
		td := traces[0]
		assert.Equal(t, "go-parser", td.Service)
		assert.Equal(t, http.MethodPost, td.Method)
		assert.Equal(t, "/submit", td.Path)
		assert.Equal(t, http.StatusCreated, td.Status)
		assert.Equal(t, cid, td.CorrelationID)
		assert.WithinDuration(t, time.Now(), td.Timestamp, time.Second)
	}
}

func TestTrackRequest_NoHeader_DoesNothing(t *testing.T) {
	resetTraceStorage(t)

	req := httptest.NewRequest(http.MethodGet, "/noop", nil)

	TrackRequest(req, http.StatusOK)

	all := GetAllTraces()
	assert.Len(t, all, 0)
}

func TestCorrelationIDMiddleware_SetsHeader_Context_StoresTraceAndStatus(t *testing.T) {
	resetTraceStorage(t)

	var capturedID string
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Ensure correlation ID is available in context
		val := r.Context().Value(CorrelationIDKey)
		assert.NotNil(t, val)
		if val != nil {
			if s, ok := val.(string); ok {
				capturedID = s
			}
		}
		time.Sleep(5 * time.Millisecond) // ensure some measurable duration
		w.WriteHeader(http.StatusTeapot)
	})

	mw := CorrelationIDMiddleware(h)

	req := httptest.NewRequest(http.MethodGet, "/tea", nil)
	rr := httptest.NewRecorder()

	mw.ServeHTTP(rr, req)
	res := rr.Result()
	defer res.Body.Close()

	headerID := res.Header.Get(CorrelationIDHeader)
	assert.NotEmpty(t, headerID)
	assert.Equal(t, headerID, capturedID)

	// Verify trace stored
	traces := GetTraces(headerID)
	if assert.Len(t, traces, 1) {
		td := traces[0]
		assert.Equal(t, "go-parser", td.Service)
		assert.Equal(t, http.MethodGet, td.Method)
		assert.Equal(t, "/tea", td.Path)
		assert.Equal(t, headerID, td.CorrelationID)
		assert.Equal(t, http.StatusTeapot, td.Status)
		assert.GreaterOrEqual(t, td.DurationMS, float64(0))
		assert.WithinDuration(t, time.Now(), td.Timestamp, time.Second)
	}
}

func TestGetTraces_ReturnsCopy(t *testing.T) {
	resetTraceStorage(t)

	cid := "copy-test_123456"
	orig := TraceData{
		Service:       "go-parser",
		Method:        http.MethodGet,
		Path:          "/copy",
		Timestamp:     time.Now(),
		CorrelationID: cid,
		Status:        http.StatusOK,
	}

	storeTrace(cid, orig)

	ret := GetTraces(cid)
	assert.Len(t, ret, 1)

	// Mutate the returned slice
	ret[0].Status = 999
	ret[0].Path = "/mutated"

	// Fetch again to ensure internal state hasn't changed
	ret2 := GetTraces(cid)
	if assert.Len(t, ret2, 1) {
		assert.Equal(t, http.StatusOK, ret2[0].Status)
		assert.Equal(t, "/copy", ret2[0].Path)
	}
}

func TestGetAllTraces_ReturnsDeepCopy(t *testing.T) {
	resetTraceStorage(t)

	cid1 := "id1_1234567890"
	cid2 := "id2_1234567890"

	storeTrace(cid1, TraceData{
		Service:       "go-parser",
		Method:        http.MethodGet,
		Path:          "/a",
		Timestamp:     time.Now(),
		CorrelationID: cid1,
		Status:        http.StatusOK,
	})
	storeTrace(cid2, TraceData{
		Service:       "go-parser",
		Method:        http.MethodPost,
		Path:          "/b",
		Timestamp:     time.Now(),
		CorrelationID: cid2,
		Status:        http.StatusCreated,
	})

	all := GetAllTraces()
	assert.Len(t, all, 2)
	assert.Len(t, all[cid1], 1)
	assert.Len(t, all[cid2], 1)

	// Mutate returned map and slices
	all[cid1][0].Status = 999
	all["new"] = []TraceData{{CorrelationID: "new"}}

	// Original store should be unaffected
	all2 := GetAllTraces()
	assert.Len(t, all2, 2)
	assert.Equal(t, http.StatusOK, all2[cid1][0].Status)
	assert.Equal(t, http.StatusCreated, all2[cid2][0].Status)
	_, exists := all2["new"]
	assert.False(t, exists)
}

func TestCleanupOldTraces_RemovesOlderThanOneHour(t *testing.T) {
	resetTraceStorage(t)

	oldID := "old_1234567890"
	newID := "new_1234567890"

	oldTrace := TraceData{
		Service:       "go-parser",
		Method:        http.MethodGet,
		Path:          "/old",
		Timestamp:     time.Now().Add(-2 * time.Hour),
		CorrelationID: oldID,
		Status:        http.StatusOK,
	}
	newTrace := TraceData{
		Service:       "go-parser",
		Method:        http.MethodGet,
		Path:          "/new",
		Timestamp:     time.Now(),
		CorrelationID: newID,
		Status:        http.StatusOK,
	}

	traceMutex.Lock()
	traceStorage[oldID] = []TraceData{oldTrace}
	traceStorage[newID] = []TraceData{newTrace}
	traceMutex.Unlock()

	// Trigger cleanup
	cleanupOldTraces()

	all := GetAllTraces()
	_, oldExists := all[oldID]
	_, newExists := all[newID]

	assert.False(t, oldExists, "old traces should have been cleaned up")
	assert.True(t, newExists, "new traces should remain")
}
