package main

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func chdir(t *testing.T, dir string) func() {
	t.Helper()
	prev, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(dir))
	return func() { _ = os.Chdir(prev) }
}

func TestReadConfig_Table(t *testing.T) {
	dir := t.TempDir()

	write := func(name, content string) string {
		p := filepath.Join(dir, name)
		require.NoError(t, os.WriteFile(p, []byte(content), 0o644))
		return p
	}

	tests := []struct {
		name     string
		path     string
		write    bool
		content  string
		wantNil  bool
		wantLen  int
		wantKeys map[string]any
	}{
		{
			name:    "non-existent file returns nil map",
			path:    filepath.Join(dir, "no-such.json"),
			write:   false,
			wantNil: true,
		},
		{
			name:    "empty file returns nil map",
			path:    "empty.json",
			write:   true,
			content: "",
			wantNil: true,
		},
		{
			name:    "invalid JSON returns nil map",
			path:    "invalid.json",
			write:   true,
			content: "{not:json}",
			wantNil: true,
		},
		{
			name:    "valid object JSON returns populated map",
			path:    "ok.json",
			write:   true,
			content: `{"a":1,"b":"x"}`,
			wantNil: false,
			wantLen: 2,
			wantKeys: map[string]any{
				"a": float64(1),
				"b": "x",
			},
		},
		{
			name:    "empty object JSON returns empty non-nil map",
			path:    "emptyobj.json",
			write:   true,
			content: `{}`,
			wantNil: false,
			wantLen: 0,
		},
		{
			name:    "array JSON returns nil map",
			path:    "array.json",
			write:   true,
			content: `[]`,
			wantNil: true,
		},
		{
			name:    "whitespace only file returns nil map",
			path:    "ws.json",
			write:   true,
			content: "  \n\t",
			wantNil: true,
		},
		{
			name:    "null top-level returns nil map",
			path:    "null.json",
			write:   true,
			content: "null",
			wantNil: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			path := tt.path
			if tt.write {
				path = write(tt.path, tt.content)
			}
			got := ReadConfig(path)
			if tt.wantNil {
				assert.Nil(t, got)
				return
			}
			assert.NotNil(t, got)
			assert.Equal(t, tt.wantLen, len(got))
			for k, v := range tt.wantKeys {
				val, ok := got[k]
				assert.True(t, ok, "expected key %q", k)
				assert.Equal(t, v, val, "value for key %q", k)
			}
		})
	}
}

func TestWriteLog_FileBehavior(t *testing.T) {
	dir := t.TempDir()
	restore := chdir(t, dir)
	defer restore()

	tests := []struct {
		name    string
		message string
	}{
		{"simple message", "hello"},
		{"empty message", ""},
		{"multi-line message", "line1\nline2\n"},
		{"long message", strings.Repeat("x", 2048)},
		{"unicode message", "✔︎ unicode ✓"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			_ = os.Remove("app.log")
			WriteLog(tt.message)

			info, err := os.Stat("app.log")
			require.NoError(t, err)
			require.NotNil(t, info)
			assert.False(t, info.IsDir())
			// OpenFile uses O_CREATE without write flags; write will fail silently and file remains empty
			assert.Equal(t, int64(0), info.Size(), "file should exist but be empty because write errors are ignored")
		})
	}
}

func TestWriteLog_IdempotentMultipleCalls(t *testing.T) {
	dir := t.TempDir()
	restore := chdir(t, dir)
	defer restore()

	for i := 0; i < 5; i++ {
		WriteLog("msg")
	}
	info, err := os.Stat("app.log")
	require.NoError(t, err)
	require.NotNil(t, info)
	assert.Equal(t, int64(0), info.Size(), "file remains empty after multiple calls")
}

func TestWriteLog_PanicsOnOpenFailure_UnixOnly(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("permission mode test is unreliable on Windows")
	}
	base := t.TempDir()
	ro := filepath.Join(base, "ro")
	require.NoError(t, os.Mkdir(ro, 0o555))
	restore := chdir(t, ro)
	defer func() {
		_ = os.Chmod(ro, 0o755)
		restore()
	}()

	assert.Panics(t, func() {
		WriteLog("should panic due to nil *os.File when open fails")
	})
}

func TestProcessData_ReturnsInput_NoPanic(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{"simple", "hello"},
		{"numbers", "12345"},
		{"whitespace", " "},
		{"unicode", "こんにちは世界"},
		{"long", strings.Repeat("a", 4096)},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			var out string
			assert.NotPanics(t, func() {
				out = ProcessData(tt.input)
			})
			assert.Equal(t, tt.input, out)
		})
	}
}

func TestProcessData_PanicsOnEmptyInput(t *testing.T) {
	assert.Panics(t, func() {
		_ = ProcessData("")
	})
}
