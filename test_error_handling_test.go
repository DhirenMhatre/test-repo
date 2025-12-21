package main

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	tmp := t.TempDir()

	type tc struct {
		name     string
		filename string
		content  []byte // nil means do not create file -> missing file case
		wantNil  bool
		want     map[string]interface{}
	}

	validPath := filepath.Join(tmp, "valid.json")
	emptyPath := filepath.Join(tmp, "empty.json")
	badPath := filepath.Join(tmp, "bad.json")
	arrayPath := filepath.Join(tmp, "array.json")
	missingPath := filepath.Join(tmp, "missing.json")

	tests := []tc{
		{
			name:     "missing file returns nil map",
			filename: missingPath,
			content:  nil,
			wantNil:  true,
		},
		{
			name:     "empty file returns nil map",
			filename: emptyPath,
			content:  []byte(""),
			wantNil:  true,
		},
		{
			name:     "malformed JSON returns nil map",
			filename: badPath,
			content:  []byte("{ not-json "),
			wantNil:  true,
		},
		{
			name:     "array JSON returns nil map (type mismatch)",
			filename: arrayPath,
			content:  []byte(`["a", 1]`),
			wantNil:  true,
		},
		{
			name:     "valid JSON object returns parsed map",
			filename: validPath,
			content:  []byte(`{"name":"service","port":8080,"enabled":true,"threshold":0.75}`),
			want: map[string]interface{}{
				"name":      "service",
				"port":      float64(8080),
				"enabled":   true,
				"threshold": 0.75,
			},
			wantNil: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.content != nil {
				require.NoError(t, os.WriteFile(tt.filename, tt.content, 0o644))
			}
			cfg := ReadConfig(tt.filename)
			if tt.wantNil {
				assert.Nil(t, cfg)
				return
			}
			assert.NotNil(t, cfg)
			assert.Equal(t, tt.want, cfg)
		})
	}
}

func TestWriteLog_FileCreationAndNoContent(t *testing.T) {
	// WriteLog opens with O_APPEND|O_CREATE but without O_WRONLY => writes fail silently.
	tmp := t.TempDir()

	origWD, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(tmp))
	t.Cleanup(func() { _ = os.Chdir(origWD) })

	// Ensure no pre-existing app.log
	_, err = os.Stat("app.log")
	if err == nil {
		require.NoError(t, os.Remove("app.log"))
	}

	tests := []struct {
		name    string
		message string
	}{
		{"writes_hello_creates_file_but_no_content", "hello"},
		{"writes_empty_creates_file_but_no_content", ""},
		{"writes_unicode_creates_file_but_no_content", "🙂🚀"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			WriteLog(tt.message)

			info, statErr := os.Stat("app.log")
			assert.NoError(t, statErr)
			if info != nil {
				assert.Equal(t, int64(0), info.Size(), "content should not be written due to read-only descriptor")
			} else {
				t.Fatal("expected app.log to exist")
			}
		})
	}
}

func TestWriteLog_MultipleCalls_NoContentAppended(t *testing.T) {
	tmp := t.TempDir()

	origWD, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(tmp))
	t.Cleanup(func() { _ = os.Chdir(origWD) })

	WriteLog("first")
	WriteLog("second")
	WriteLog("third")

	info, statErr := os.Stat("app.log")
	assert.NoError(t, statErr)
	if assert.NotNil(t, info) {
		assert.Equal(t, int64(0), info.Size(), "should remain empty because writes fail")
	}
}

func TestWriteLog_PanicsOnPermissionDenied_UnixOnly(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("permission model differs on Windows")
	}

	tmp := t.TempDir()
	noWrite := filepath.Join(tmp, "no-write")
	require.NoError(t, os.Mkdir(noWrite, 0o755))
	// Remove write permission from the directory so creation fails.
	require.NoError(t, os.Chmod(noWrite, 0o555))
	t.Cleanup(func() { _ = os.Chmod(noWrite, 0o755) })

	origWD, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(noWrite))
	t.Cleanup(func() { _ = os.Chdir(origWD) })

	assert.Panics(t, func() {
		WriteLog("this should panic because file open fails and file is nil")
	})
}

func TestProcessData(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		want        string
		wantPanic   bool
		description string
	}{
		{"empty_input_panics", "", "", true, "panic on empty input"},
		{"simple_string_returns_same", "hello", "hello", false, "returns input"},
		{"whitespace_preserved", "  spaced  ", "  spaced  ", false, "returns input unchanged"},
		{"unicode_string", "🙂🚀", "🙂🚀", false, "returns input unchanged"},
		{"multiline_string", "line1\nline2", "line1\nline2", false, "returns input unchanged"},
		{"long_string", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", false, "returns input unchanged"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() { _ = ProcessData(tt.input) })
				return
			}
			assert.NotPanics(t, func() { _ = ProcessData(tt.input) })
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}
