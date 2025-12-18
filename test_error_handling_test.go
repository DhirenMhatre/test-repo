package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig_TableDriven(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		content  string
		exists   bool
		wantNil  bool
		expected map[string]interface{}
	}{
		{
			name:    "nonexistent file returns nil map",
			exists:  false,
			wantNil: true,
		},
		{
			name:    "invalid JSON returns nil map",
			content: "{ invalid json",
			exists:  true,
			wantNil: true,
		},
		{
			name:    "empty file returns nil map",
			content: "",
			exists:  true,
			wantNil: true,
		},
		{
			name:    "valid JSON returns parsed map",
			content: `{"a":1, "b":"x"}`,
			exists:  true,
			wantNil: false,
			expected: map[string]interface{}{
				"a": float64(1),
				"b": "x",
			},
		},
	}

	for _, tt := range tests {
		tt := tt // capture
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			path := filepath.Join(dir, "config.json")
			if tt.exists {
				require.NoError(t, os.WriteFile(path, []byte(tt.content), 0o600))
			}

			got := ReadConfig(path)

			if tt.wantNil {
				assert.Nil(t, got)
				return
			}

			assert.NotNil(t, got)
			// Compare expected keys/values if present
			for k, v := range tt.expected {
				assert.Equal(t, v, got[k])
			}
			// Ensure sizes match
			assert.Equal(t, len(tt.expected), len(got))
		})
	}
}

func TestWriteLog_TableDriven(t *testing.T) {
	tests := []struct {
		name        string
		preExist    bool
		preContent  string
		message     string
		wantContent string
	}{
		{
			name:        "creates file but writes nothing",
			preExist:    false,
			preContent:  "",
			message:     "hello",
			wantContent: "",
		},
		{
			name:        "existing file remains unchanged",
			preExist:    true,
			preContent:  "existing",
			message:     "new message",
			wantContent: "existing",
		},
		{
			name:        "empty message still results in empty content",
			preExist:    false,
			preContent:  "",
			message:     "",
			wantContent: "",
		},
		{
			name:        "multiple lines message still not written",
			preExist:    false,
			preContent:  "",
			message:     "line1\nline2\nline3",
			wantContent: "",
		},
	}

	for _, tt := range tests {
		tt := tt // capture
		t.Run(tt.name, func(t *testing.T) {
			// Use a temp working directory to isolate "app.log"
			dir := t.TempDir()
			origWD, err := os.Getwd()
			require.NoError(t, err)
			defer func() {
				_ = os.Chdir(origWD)
			}()
			require.NoError(t, os.Chdir(dir))

			logPath := filepath.Join(dir, "app.log")

			if tt.preExist {
				require.NoError(t, os.WriteFile(logPath, []byte(tt.preContent), 0o600))
			}

			// Call the function under test
			WriteLog(tt.message)

			// app.log should exist
			_, statErr := os.Stat(logPath)
			assert.NoError(t, statErr)

			// Reads should succeed and content should match expectations
			data, readErr := os.ReadFile(logPath)
			require.NoError(t, readErr)
			assert.Equal(t, tt.wantContent, string(data))
		})
	}
}

func TestWriteLog_LargeMessageDoesNotPanicAndStaysEmpty(t *testing.T) {
	dir := t.TempDir()
	origWD, err := os.Getwd()
	require.NoError(t, err)
	defer func() { _ = os.Chdir(origWD) }()
	require.NoError(t, os.Chdir(dir))

	large := strings.Repeat("x", 1024*64) // 64KB
	assert.NotPanics(t, func() {
		WriteLog(large)
	})

	data, readErr := os.ReadFile("app.log")
	require.NoError(t, readErr)
	assert.Equal(t, "", string(data))
}

func TestProcessData_TableDriven(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}{
		{
			name:      "empty input panics",
			input:     "",
			wantPanic: true,
		},
		{
			name:      "simple input returns same",
			input:     "hello",
			want:      "hello",
			wantPanic: false,
		},
		{
			name:      "whitespace input returns same",
			input:     "   ",
			want:      "   ",
			wantPanic: false,
		},
		{
			name:      "long input returns same",
			input:     strings.Repeat("ab", 1024),
			want:      strings.Repeat("ab", 1024),
			wantPanic: false,
		},
	}

	for _, tt := range tests {
		tt := tt // capture
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestProcessData_PanicMessage(t *testing.T) {
	assert.PanicsWithValue(t, "empty input", func() {
		_ = ProcessData("")
	})
}
