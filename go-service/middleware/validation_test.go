package middleware

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestValidateParseRequest(t *testing.T) {
	ClearValidationErrors()

	tests := []struct {
		name          string
		content       string
		path          string
		wantErrFields []string
		wantReasons   []string
	}{
		{
			name:          "valid input",
			content:       "hello world",
			path:          "file.txt",
			wantErrFields: nil,
		},
		{
			name:          "empty content",
			content:       "",
			path:          "file.txt",
			wantErrFields: []string{"content"},
			wantReasons:   []string{"Content is required and cannot be empty"},
		},
		{
			name:          "content too big",
			content:       strings.Repeat("a", MaxContentSize+1),
			path:          "file.txt",
			wantErrFields: []string{"content"},
			wantReasons:   []string{"Content exceeds maximum size of 1MB"},
		},
		{
			name:          "content with null bytes",
			content:       "abc\x00def",
			path:          "file.txt",
			wantErrFields: []string{"content"},
			wantReasons:   []string{"Content contains invalid null bytes"},
		},
		{
			name:          "path too long",
			content:       "ok",
			path:          strings.Repeat("a", MaxPathLength+1),
			wantErrFields: []string{"path"},
			wantReasons:   []string{"Path exceeds maximum length"},
		},
		{
			name:          "path traversal detected",
			content:       "ok",
			path:          "../etc/passwd",
			wantErrFields: []string{"path"},
			wantReasons:   []string{"Path contains potential directory traversal"},
		},
		{
			name:          "path too long and traversal",
			content:       "ok",
			path:          strings.Repeat(".", MaxPathLength+1),
			wantErrFields: []string{"path", "path"},
			wantReasons:   []string{"Path exceeds maximum length", "Path contains potential directory traversal"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			before := GetValidationErrors()
			errs := ValidateParseRequest(tt.content, tt.path)

			if len(tt.wantErrFields) == 0 {
				assert.Empty(t, errs)
				after := GetValidationErrors()
				assert.Equal(t, len(before), len(after))
				return
			}

			assert.Equal(t, len(tt.wantErrFields), len(errs))
			for i := range tt.wantErrFields {
				assert.Equal(t, tt.wantErrFields[i], errs[i].Field)
				if i < len(tt.wantReasons) {
					assert.Equal(t, tt.wantReasons[i], errs[i].Reason)
				}
				assert.False(t, errs[i].Time.IsZero())
			}

			after := GetValidationErrors()
			assert.Equal(t, len(before)+len(errs), len(after))
		})
	}
}

func TestValidateDiffRequest(t *testing.T) {
	ClearValidationErrors()

	tests := []struct {
		name          string
		oldContent    string
		newContent    string
		wantErrFields []string
		wantReasons   []string
	}{
		{
			name:          "both ok",
			oldContent:    "old",
			newContent:    "new",
			wantErrFields: nil,
		},
		{
			name:          "old missing",
			oldContent:    "",
			newContent:    "new",
			wantErrFields: []string{"old_content"},
			wantReasons:   []string{"Old content is required"},
		},
		{
			name:          "new missing",
			oldContent:    "old",
			newContent:    "",
			wantErrFields: []string{"new_content"},
			wantReasons:   []string{"New content is required"},
		},
		{
			name:          "old too big",
			oldContent:    strings.Repeat("x", MaxContentSize+1),
			newContent:    "new",
			wantErrFields: []string{"old_content"},
			wantReasons:   []string{"Old content exceeds maximum size"},
		},
		{
			name:          "new too big",
			oldContent:    "old",
			newContent:    strings.Repeat("x", MaxContentSize+1),
			wantErrFields: []string{"new_content"},
			wantReasons:   []string{"New content exceeds maximum size"},
		},
		{
			name:          "both missing",
			oldContent:    "",
			newContent:    "",
			wantErrFields: []string{"old_content", "new_content"},
			wantReasons:   []string{"Old content is required", "New content is required"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			before := GetValidationErrors()
			errs := ValidateDiffRequest(tt.oldContent, tt.newContent)
			if len(tt.wantErrFields) == 0 {
				assert.Empty(t, errs)
				after := GetValidationErrors()
				assert.Equal(t, len(before), len(after))
				return
			}
			assert.Equal(t, len(tt.wantErrFields), len(errs))
			for i := range tt.wantErrFields {
				assert.Equal(t, tt.wantErrFields[i], errs[i].Field)
				if i < len(tt.wantReasons) {
					assert.Equal(t, tt.wantReasons[i], errs[i].Reason)
				}
				assert.False(t, errs[i].Time.IsZero())
			}
			after := GetValidationErrors()
			assert.Equal(t, len(before)+len(errs), len(after))
		})
	}
}

func TestSanitizeInput_RemovesControlCharactersExceptWhitespace(t *testing.T) {
	input := "A\x00B\x01C\nD\rE\tF\x0BG\x0EH\x7FI"
	got := SanitizeInput(input)
	assert.Equal(t, "ABC\nD\rE\tFGHI", got)
}

func TestSanitizeRequestBody_SanitizesKnownJSONFields(t *testing.T) {
	raw := map[string]interface{}{
		"content":     "A\x00B",
		"path":        "P\x01Q",
		"old_content": "O\x0BP",
		"new_content": "N\x7FO",
		"untouched":   123,
	}
	b, _ := json.Marshal(raw)
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewReader(b))

	SanitizeRequestBody(req)

	gotBytes, err := io.ReadAll(req.Body)
	assert.NoError(t, err)

	var got map[string]interface{}
	err = json.Unmarshal(gotBytes, &got)
	assert.NoError(t, err)

	assert.Equal(t, "AB", got["content"])
	assert.Equal(t, "PQ", got["path"])
	assert.Equal(t, "OP", got["old_content"])
	assert.Equal(t, "NO", got["new_content"])
	assert.Equal(t, float64(123), got["untouched"])
	assert.Equal(t, int64(len(gotBytes)), req.ContentLength)
}

func TestSanitizeRequestBody_InvalidJSONKeepsOriginal(t *testing.T) {
	orig := []byte("not json")
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewReader(orig))

	SanitizeRequestBody(req)

	got, err := io.ReadAll(req.Body)
	assert.NoError(t, err)
	assert.Equal(t, orig, got)
}

func TestValidationMiddleware_SanitizesPOSTJSON(t *testing.T) {
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(body)
	})

	srv := httptest.NewServer(ValidationMiddleware(h))
	defer srv.Close()

	// JSON string with escaped null byte; middleware should decode, sanitize, re-encode without the null
	payload := `{"content":"A\u0000B","path":"X\u0007Y"}`
	resp, err := http.Post(srv.URL, "application/json", bytes.NewBufferString(payload))
	assert.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, http.StatusOK, resp.StatusCode)
	respBody, _ := io.ReadAll(resp.Body)

	var got map[string]string
	err = json.Unmarshal(respBody, &got)
	assert.NoError(t, err)
	assert.Equal(t, "AB", got["content"])
	assert.Equal(t, "XY", got["path"])
}

func TestValidationMiddleware_PassesThroughNonPOST(t *testing.T) {
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(body)
	})

	srv := httptest.NewServer(ValidationMiddleware(h))
	defer srv.Close()

	payload := `{"content":"A\u0000B"}`
	req, _ := http.NewRequest(http.MethodGet, srv.URL, bytes.NewBufferString(payload))
	resp, err := http.DefaultClient.Do(req)
	assert.NoError(t, err)
	defer resp.Body.Close()
	assert.Equal(t, http.StatusOK, resp.StatusCode)

	respBody, _ := io.ReadAll(resp.Body)
	// Because middleware bypasses non-POST, the body should be unchanged
	assert.Equal(t, payload, string(respBody))
}

func TestValidationMiddleware_PostInvalidJSON_PassesOriginal(t *testing.T) {
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(body)
	})

	srv := httptest.NewServer(ValidationMiddleware(h))
	defer srv.Close()

	payload := "not json"
	resp, err := http.Post(srv.URL, "text/plain", bytes.NewBufferString(payload))
	assert.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, http.StatusOK, resp.StatusCode)
	respBody, _ := io.ReadAll(resp.Body)
	assert.Equal(t, payload, string(respBody))
}

func TestGetAndClearValidationErrors(t *testing.T) {
	ClearValidationErrors()
	assert.Empty(t, GetValidationErrors())

	_ = ValidateParseRequest("", "ok/path") // logs one error
	errs := GetValidationErrors()
	assert.Len(t, errs, 1)
	assert.Equal(t, "content", errs[0].Field)

	// Ensure returned slice is a copy
	errs = append(errs, ValidationError{Field: "should_not_affect"})
	errs2 := GetValidationErrors()
	assert.Len(t, errs2, 1)

	ClearValidationErrors()
	assert.Empty(t, GetValidationErrors())
}

func TestValidationErrorLog_TruncatesTo100(t *testing.T) {
	ClearValidationErrors()
	for i := 0; i < 120; i++ {
		_ = ValidateParseRequest("", "x")
	}
	errs := GetValidationErrors()
	assert.Len(t, errs, 100)
}

func TestValidateParseRequest_DoesNotLogOnSuccess(t *testing.T) {
	ClearValidationErrors()
	errs := ValidateParseRequest("ok", "path/file.txt")
	assert.Empty(t, errs)
	assert.Empty(t, GetValidationErrors())
}
