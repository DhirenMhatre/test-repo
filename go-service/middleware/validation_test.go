package middleware

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestValidateParseRequest_EmptyContent(t *testing.T) {
	ClearValidationErrors()
	t.Cleanup(ClearValidationErrors)

	errors := ValidateParseRequest("", "valid/path")
	assert.Len(t, errors, 1)
	assert.Equal(t, "content", errors[0].Field)
	assert.Equal(t, "Content is required and cannot be empty", errors[0].Reason)
	assert.False(t, errors[0].Time.IsZero())

	// Logged
	logged := GetValidationErrors()
	assert.Len(t, logged, 1)
	assert.Equal(t, "content", logged[0].Field)
	assert.Equal(t, "Content is required and cannot be empty", logged[0].Reason)
}

func TestValidateParseRequest_ContentTooLarge(t *testing.T) {
	ClearValidationErrors()
	t.Cleanup(ClearValidationErrors)

	content := strings.Repeat("a", MaxContentSize+1)
	errors := ValidateParseRequest(content, "path")
	assert.Len(t, errors, 1)
	assert.Equal(t, "content", errors[0].Field)
	assert.Equal(t, "Content exceeds maximum size of 1MB", errors[0].Reason)
	assert.False(t, errors[0].Time.IsZero())
}

func TestValidateParseRequest_ContentNullBytes(t *testing.T) {
	ClearValidationErrors()
	t.Cleanup(ClearValidationErrors)

	content := "hello\x00world"
	errors := ValidateParseRequest(content, "path")
	assert.Len(t, errors, 1)
	assert.Equal(t, "content", errors[0].Field)
	assert.Equal(t, "Content contains invalid null bytes", errors[0].Reason)
}

func TestValidateParseRequest_PathTooLongAndTraversal(t *testing.T) {
	ClearValidationErrors()
	t.Cleanup(ClearValidationErrors)

	path := strings.Repeat("a", MaxPathLength+1) + "../"
	errors := ValidateParseRequest("ok", path)
	assert.Len(t, errors, 2)
	assert.Equal(t, "path", errors[0].Field)
	assert.Equal(t, "Path exceeds maximum length", errors[0].Reason)
	assert.Equal(t, "path", errors[1].Field)
	assert.Equal(t, "Path contains potential directory traversal", errors[1].Reason)
}

func TestValidateParseRequest_NoErrors_NoLog(t *testing.T) {
	ClearValidationErrors()
	t.Cleanup(ClearValidationErrors)

	errors := ValidateParseRequest("ok", "valid/path")
	assert.Len(t, errors, 0)

	logged := GetValidationErrors()
	assert.Len(t, logged, 0)
}

func TestValidateDiffRequest_BothRequiredErrors(t *testing.T) {
	ClearValidationErrors()
	t.Cleanup(ClearValidationErrors)

	errors := ValidateDiffRequest("", "")
	assert.Len(t, errors, 2)

	fields := []string{errors[0].Field, errors[1].Field}
	reasons := []string{errors[0].Reason, errors[1].Reason}

	assert.Contains(t, fields, "old_content")
	assert.Contains(t, fields, "new_content")
	assert.Contains(t, reasons, "Old content is required")
	assert.Contains(t, reasons, "New content is required")
}

func TestValidateDiffRequest_SizeErrors(t *testing.T) {
	ClearValidationErrors()
	t.Cleanup(ClearValidationErrors)

	oldContent := strings.Repeat("x", MaxContentSize+1)
	newContent := strings.Repeat("y", MaxContentSize+1)
	errors := ValidateDiffRequest(oldContent, newContent)
	assert.Len(t, errors, 2)

	fields := []string{errors[0].Field, errors[1].Field}
	reasons := []string{errors[0].Reason, errors[1].Reason}

	assert.Contains(t, fields, "old_content")
	assert.Contains(t, fields, "new_content")
	assert.Contains(t, reasons, "Old content exceeds maximum size")
	assert.Contains(t, reasons, "New content exceeds maximum size")
}

func TestSanitizeInput_RemovesControlChars(t *testing.T) {
	in := "Hello\x00World\x01\x02Test\n\t\rEnd\x7f" // \n \t \r should remain, others removed
	out := SanitizeInput(in)
	assert.Equal(t, "HelloWorldTest\n\t\rEnd", out)
}

func TestSanitizeRequestBody_JSONSanitization(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "/parse", nil)
	orig := map[string]any{
		"content":     "Hi\x00there \x7f",
		"path":        "../secret",
		"old_content": "A\x01B",
		"new_content": "C\x11D",
		"other":       123,
	}
	raw, _ := json.Marshal(orig)
	r.Body = io.NopCloser(bytes.NewReader(raw))

	SanitizeRequestBody(r)

	gotBody, err := io.ReadAll(r.Body)
	assert.NoError(t, err)

	// ContentLength should match body length
	assert.Equal(t, int64(len(gotBody)), r.ContentLength)

	var got map[string]any
	_ = json.Unmarshal(gotBody, &got)

	// Verify sanitized fields
	assert.Equal(t, "Hithere ", got["content"])
	assert.Equal(t, "../secret", got["path"])
	assert.Equal(t, "AB", got["old_content"])
	assert.Equal(t, "CD", got["new_content"])
	// Non-string should remain
	assert.Equal(t, float64(123), got["other"])
}

func TestSanitizeRequestBody_InvalidJSON_Preserved(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "/parse", bytes.NewBufferString("{invalid json"))
	orig, _ := io.ReadAll(r.Body)
	r.Body = io.NopCloser(bytes.NewReader(orig))

	SanitizeRequestBody(r)

	got, err := io.ReadAll(r.Body)
	assert.NoError(t, err)
	assert.Equal(t, string(orig), string(got))
}

type errReadCloser struct{}

func (e *errReadCloser) Read(p []byte) (int, error) { return 0, errors.New("boom") }
func (e *errReadCloser) Close() error               { return nil }

func TestSanitizeRequestBody_ReadError_NoPanic(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "/parse", nil)
	r.Body = &errReadCloser{}

	// Should not panic and should return early
	SanitizeRequestBody(r)

	// Body remains our errReadCloser
	_, err := r.Body.Read(make([]byte, 10))
	assert.Error(t, err)
}

func TestValidationMiddleware_NonPOST_Passthrough(t *testing.T) {
	body := "raw-body-\x00-with-controls"
	r := httptest.NewRequest(http.MethodGet, "/any", bytes.NewBufferString(body))
	w := httptest.NewRecorder()

	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(b)
	})

	mw := ValidationMiddleware(h)
	mw.ServeHTTP(w, r)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, body, w.Body.String())
}

func TestValidationMiddleware_POST_JSON_Sanitized(t *testing.T) {
	orig := map[string]any{
		"content": "A\x00B",
		"path":    "x",
	}
	raw, _ := json.Marshal(orig)
	r := httptest.NewRequest(http.MethodPost, "/parse", bytes.NewReader(raw))
	w := httptest.NewRecorder()

	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Echo sanitized body
		b, _ := io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(b)
	})

	mw := ValidationMiddleware(h)
	mw.ServeHTTP(w, r)

	assert.Equal(t, http.StatusOK, w.Code)

	var got map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &got)
	assert.Equal(t, "AB", got["content"])
	assert.Equal(t, "x", got["path"])
}

func TestValidationMiddleware_POST_NonJSON_Preserved(t *testing.T) {
	body := "<<<not-json>>>\x00"
	r := httptest.NewRequest(http.MethodPost, "/parse", bytes.NewBufferString(body))
	w := httptest.NewRecorder()

	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(b)
	})

	mw := ValidationMiddleware(h)
	mw.ServeHTTP(w, r)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, body, w.Body.String())
}

func TestGetAndClearValidationErrors_CopyIsolation(t *testing.T) {
	ClearValidationErrors()
	t.Cleanup(ClearValidationErrors)

	errs := []ValidationError{
		{Field: "f1", Reason: "r1", Time: time.Now()},
		{Field: "f2", Reason: "r2", Time: time.Now()},
	}
	logValidationErrors(errs)

	got := GetValidationErrors()
	assert.Equal(t, 2, len(got))
	// mutate returned slice
	got[0].Field = "mutated"

	// internal should be unchanged
	got2 := GetValidationErrors()
	assert.Equal(t, "f1", got2[0].Field)
}

func TestLogValidationErrors_TrimsTo100(t *testing.T) {
	ClearValidationErrors()
	t.Cleanup(ClearValidationErrors)

	var many []ValidationError
	for i := 0; i < 120; i++ {
		many = append(many, ValidationError{
			Field:  "f" + strconvIt(i),
			Reason: "reason",
			Time:   time.Now(),
		})
	}
	logValidationErrors(many)

	got := GetValidationErrors()
	assert.Equal(t, 100, len(got))
	assert.Equal(t, "f20", got[0].Field)
	assert.Equal(t, "f119", got[99].Field)
}

func TestContainsNullBytes(t *testing.T) {
	assert.True(t, containsNullBytes("a\x00b"))
	assert.False(t, containsNullBytes("abc"))
}

// helper to avoid importing strconv in tests
func strconvIt(i int) string {
	digits := "0123456789"
	if i == 0 {
		return "0"
	}
	var b []byte
	n := i
	for n > 0 {
		b = append([]byte{digits[n%10]}, b...)
		n /= 10
	}
	return string(b)
}
