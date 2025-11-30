package middleware

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestValidateParseRequest(t *testing.T) {
	type exp struct {
		Field  string
		Reason string
	}
	tests := []struct {
		name       string
		content    string
		path       string
		wantErrs   []exp
		wantLogged bool
	}{
		{
			name:     "valid input",
			content:  "hello world",
			path:     "dir/file.txt",
			wantErrs: nil,
		},
		{
			name:     "empty content",
			content:  "",
			path:     "a",
			wantErrs: []exp{{Field: "content", Reason: "Content is required and cannot be empty"}},
		},
		{
			name:     "content too large",
			content:  strings.Repeat("a", MaxContentSize+1),
			path:     "a",
			wantErrs: []exp{{Field: "content", Reason: "Content exceeds maximum size of 1MB"}},
		},
		{
			name:     "content contains null byte",
			content:  "x\x00y",
			path:     "a",
			wantErrs: []exp{{Field: "content", Reason: "Content contains invalid null bytes"}},
		},
		{
			name:     "path too long",
			content:  "hello",
			path:     strings.Repeat("a", MaxPathLength+1),
			wantErrs: []exp{{Field: "path", Reason: "Path exceeds maximum length"}},
		},
		{
			name:     "path traversal with dots",
			content:  "hello",
			path:     "../etc",
			wantErrs: []exp{{Field: "path", Reason: "Path contains potential directory traversal"}},
		},
		{
			name:     "path traversal with tilde",
			content:  "hello",
			path:     "~/home",
			wantErrs: []exp{{Field: "path", Reason: "Path contains potential directory traversal"}},
		},
		{
			name:     "multiple errors aggregated",
			content:  "",
			path:     "../" + strings.Repeat("a", MaxPathLength+10),
			wantErrs: []exp{{Field: "content", Reason: "Content is required and cannot be empty"}, {Field: "path", Reason: "Path exceeds maximum length"}, {Field: "path", Reason: "Path contains potential directory traversal"}},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ClearValidationErrors()
			errs := ValidateParseRequest(tt.content, tt.path)

			if len(tt.wantErrs) == 0 {
				assert.Empty(t, errs)
				assert.Empty(t, GetValidationErrors())
				return
			}

			require.Len(t, errs, len(tt.wantErrs))
			for _, e := range errs {
				assert.NotEmpty(t, e.Field)
				assert.NotEmpty(t, e.Reason)
				assert.False(t, e.Time.IsZero())
			}

			// Check content matches expected (ignoring Time and order)
			for _, we := range tt.wantErrs {
				found := false
				for _, e := range errs {
					if e.Field == we.Field && e.Reason == we.Reason {
						found = true
						break
					}
				}
				assert.True(t, found, "expected error not found: %+v", we)
			}

			// Logged errors should match count
			logged := GetValidationErrors()
			require.Len(t, logged, len(tt.wantErrs))
			for _, we := range tt.wantErrs {
				found := false
				for _, e := range logged {
					if e.Field == we.Field && e.Reason == we.Reason {
						found = true
						break
					}
				}
				assert.True(t, found, "expected logged error not found: %+v", we)
			}
		})
	}
}

func TestValidateDiffRequest(t *testing.T) {
	type exp struct {
		Field  string
		Reason string
	}
	tests := []struct {
		name         string
		oldContent   string
		newContent   string
		expectedErrs []exp
	}{
		{
			name:         "both empty",
			oldContent:   "",
			newContent:   "",
			expectedErrs: []exp{{Field: "old_content", Reason: "Old content is required"}, {Field: "new_content", Reason: "New content is required"}},
		},
		{
			name:         "old too large",
			oldContent:   strings.Repeat("x", MaxContentSize+1),
			newContent:   "ok",
			expectedErrs: []exp{{Field: "old_content", Reason: "Old content exceeds maximum size"}},
		},
		{
			name:         "new too large",
			oldContent:   "ok",
			newContent:   strings.Repeat("y", MaxContentSize+1),
			expectedErrs: []exp{{Field: "new_content", Reason: "New content exceeds maximum size"}},
		},
		{
			name:         "valid diff",
			oldContent:   "hello",
			newContent:   "world",
			expectedErrs: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ClearValidationErrors()
			errs := ValidateDiffRequest(tt.oldContent, tt.newContent)

			if len(tt.expectedErrs) == 0 {
				assert.Empty(t, errs)
				assert.Empty(t, GetValidationErrors())
				return
			}

			require.Len(t, errs, len(tt.expectedErrs))
			for _, e := range errs {
				assert.NotEmpty(t, e.Field)
				assert.NotEmpty(t, e.Reason)
				assert.False(t, e.Time.IsZero())
			}
			for _, we := range tt.expectedErrs {
				found := false
				for _, e := range errs {
					if e.Field == we.Field && e.Reason == we.Reason {
						found = true
						break
					}
				}
				assert.True(t, found, "expected error not found: %+v", we)
			}

			// Logged
			logged := GetValidationErrors()
			require.Len(t, logged, len(tt.expectedErrs))
		})
	}
}

func TestSanitizeInput_RemovesControlCharsExceptWhitespace(t *testing.T) {
	input := "A\x00B\x01C\nD\rE\tF\x0bG\x0cH\x1fI\x7fJ"
	out := SanitizeInput(input)
	assert.Equal(t, "ABC\nD\rE\tFGHIJ", out)
}

func TestSanitizeRequestBody_JSON_SanitizesAndResetsBody(t *testing.T) {
	body := `{"content":"A\u0000B","path":"\u0000dir/\tfile","old_content":"\u0001Y","new_content":"Z\u007f"}`
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewBufferString(body))
	SanitizeRequestBody(req)

	// Body should be readable again and sanitized
	var m map[string]string
	require.NoError(t, json.NewDecoder(req.Body).Decode(&m))

	assert.Equal(t, "AB", m["content"])
	assert.Equal(t, "dir/\tfile", m["path"])
	assert.Equal(t, "Y", m["old_content"])
	assert.Equal(t, "Z", m["new_content"])

	// ContentLength should match body size
	b2, err := json.Marshal(m)
	require.NoError(t, err)
	assert.Equal(t, int64(len(b2)), req.ContentLength)
}

func TestSanitizeRequestBody_InvalidJSON_PreservesOriginal(t *testing.T) {
	orig := `{"content":`
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewBufferString(orig))
	SanitizeRequestBody(req)
	b, err := ioReadAll(req.Body)
	require.NoError(t, err)
	assert.Equal(t, orig, string(b))
}

func TestValidationMiddleware_POST_SanitizesBodyForNextHandler(t *testing.T) {
	body := `{"content":"A\u0000B","path":"\u0000dir","old_content":"\u0001Y","new_content":"Z\u007f"}`
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewBufferString(body))
	rr := httptest.NewRecorder()

	var seen map[string]string
	var handlerCalled bool

	h := ValidationMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handlerCalled = true
		require.NoError(t, json.NewDecoder(r.Body).Decode(&seen))
		assert.Equal(t, "AB", seen["content"])
		assert.Equal(t, "dir", seen["path"])
		assert.Equal(t, "Y", seen["old_content"])
		assert.Equal(t, "Z", seen["new_content"])
	}))

	h.ServeHTTP(rr, req)
	assert.True(t, handlerCalled)
}

func TestValidationMiddleware_POST_InvalidJSON_PassesThrough(t *testing.T) {
	orig := `{"content":`
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewBufferString(orig))
	rr := httptest.NewRecorder()

	var got string
	h := ValidationMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, err := ioReadAll(r.Body)
		require.NoError(t, err)
		got = string(b)
	}))

	h.ServeHTTP(rr, req)
	assert.Equal(t, orig, got)
}

func TestValidationMiddleware_NonPOST_NoSanitize(t *testing.T) {
	body := `{"content":"A\u0000B"}`
	req := httptest.NewRequest(http.MethodGet, "/", bytes.NewBufferString(body))
	rr := httptest.NewRecorder()

	var seen map[string]string
	var originalLen = int64(len(body))
	h := ValidationMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		require.NoError(t, json.NewDecoder(r.Body).Decode(&seen))
		// Ensure not sanitized: string contains NUL rune
		assert.True(t, strings.ContainsRune(seen["content"], rune(0)))
		assert.Equal(t, originalLen, r.ContentLength)
	}))

	h.ServeHTTP(rr, req)
}

func TestGetAndClearValidationErrors(t *testing.T) {
	ClearValidationErrors()
	assert.Empty(t, GetValidationErrors())

	errs := []ValidationError{
		{Field: "f1", Reason: "r1", Time: time.Now()},
		{Field: "f2", Reason: "r2", Time: time.Now()},
	}
	logValidationErrors(errs)
	got := GetValidationErrors()
	require.Len(t, got, 2)

	ClearValidationErrors()
	assert.Empty(t, GetValidationErrors())
}

func TestLogValidationErrors_CapsAt100(t *testing.T) {
	ClearValidationErrors()
	var errs []ValidationError
	for i := 0; i < 120; i++ {
		errs = append(errs, ValidationError{
			Field:  fmt.Sprintf("f%03d", i),
			Reason: "x",
			Time:   time.Now(),
		})
	}
	logValidationErrors(errs)

	got := GetValidationErrors()
	require.Len(t, got, 100)
	assert.Equal(t, "f020", got[0].Field)
	assert.Equal(t, "f119", got[99].Field)
}

func TestContainsNullBytes(t *testing.T) {
	assert.True(t, containsNullBytes("abc\x00def"))
	assert.False(t, containsNullBytes("abcdef"))
}

// helper to avoid shadowing io.ReadAll if needed in older versions
func ioReadAll(r io.Reader) ([]byte, error) {
	return io.ReadAll(r)
}
