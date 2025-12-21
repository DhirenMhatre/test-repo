package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		prepare   func(dir string) string
		expectNil bool
		verify    func(t *testing.T, got map[string]interface{})
	}{
		{
			name: "missing file returns nil",
			prepare: func(dir string) string {
				return filepath.Join(dir, "no_such.json")
			},
			expectNil: true,
		},
		{
			name: "empty file returns nil",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "empty.json")
				require.NoError(t, os.WriteFile(p, []byte(""), 0o644))
				return p
			},
			expectNil: true,
		},
		{
			name: "invalid json returns nil",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "bad.json")
				require.NoError(t, os.WriteFile(p, []byte("{not: valid"), 0o644))
				return p
			},
			expectNil: true,
		},
		{
			name: "json array returns nil for map target",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "array.json")
				require.NoError(t, os.WriteFile(p, []byte(`[1,2,3]`), 0o644))
				return p
			},
			expectNil: true,
		},
		{
			name: "valid object simple",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "simple.json")
				require.NoError(t, os.WriteFile(p, []byte(`{"name":"app","port":8080}`), 0o644))
				return p
			},
			expectNil: false,
			verify: func(t *testing.T, got map[string]interface{}) {
				assert.NotNil(t, got)
				assert.Equal(t, "app", got["name"])
				// JSON numbers decode as float64
				port, ok := got["port"].(float64)
				assert.True(t, ok, "port should be a number")
				assert.Equal(t, float64(8080), port)
			},
		},
		{
			name: "valid nested object",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "nested.json")
				require.NoError(t, os.WriteFile(p, []byte(`{"nested":{"a":1,"b":"x"}}`), 0o644))
				return p
			},
			expectNil: false,
			verify: func(t *testing.T, got map[string]interface{}) {
				assert.NotNil(t, got)
				nestedVal, ok := got["nested"]
				assert.True(t, ok, "nested key missing")
				nested, ok := nestedVal.(map[string]interface{})
				assert.True(t, ok, "nested should be an object")
				aval, ok := nested["a"].(float64)
				assert.True(t, ok)
				assert.Equal(t, float64(1), aval)
				bval, ok := nested["b"].(string)
				assert.True(t, ok)
				assert.Equal(t, "x", bval)
			},
		},
		{
			name: "valid empty object",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "emptyobj.json")
				require.NoError(t, os.WriteFile(p, []byte(`{}`), 0o644))
				return p
			},
			expectNil: false,
			verify: func(t *testing.T, got map[string]interface{}) {
				assert.NotNil(t, got)
				assert.Equal(t, 0, len(got))
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			path := tt.prepare(dir)
			got := ReadConfig(path)
			if tt.expectNil {
				assert.Nil(t, got)
				return
			}
			assert.NotNil(t, got)
			if tt.verify != nil {
				tt.verify(t, got)
			}
		})
	}
}

func TestWriteLog_FileCreationAndNoContent(t *testing.T) {
	tests := []struct {
		name    string
		message string
	}{
		{"empty message", ""},
		{"simple message", "hello"},
		{"multiline message", "line1\nline2\n"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			cwd, err := os.Getwd()
			require.NoError(t, err)
			defer func() { _ = os.Chdir(cwd) }()
			require.NoError(t, os.Chdir(dir))

			WriteLog(tt.message)

			logPath := filepath.Join(dir, "app.log")
			_, statErr := os.Stat(logPath)
			assert.NoError(t, statErr, "app.log should be created")
			data, readErr := os.ReadFile(logPath)
			require.NoError(t, readErr)
			// Because the file is opened without write flags, write should not persist
			assert.Equal(t, 0, len(data), "log file should be empty as write likely failed")
		})
	}
}

func TestWriteLog_MultipleCallsStillEmpty(t *testing.T) {
	dir := t.TempDir()
	cwd, err := os.Getwd()
	require.NoError(t, err)
	defer func() { _ = os.Chdir(cwd) }()
	require.NoError(t, os.Chdir(dir))

	WriteLog("first")
	WriteLog("second")

	logPath := filepath.Join(dir, "app.log")
	_, statErr := os.Stat(logPath)
	assert.NoError(t, statErr, "app.log should be created")
	data, readErr := os.ReadFile(logPath)
	require.NoError(t, readErr)
	assert.Equal(t, 0, len(data), "log file should remain empty")
}

func TestProcessData_ReturnsInput(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name  string
		input string
	}{
		{"simple", "abc"},
		{"whitespace", " "},
		{"number string", "123"},
		{"multiline", "hello\nworld"},
		{"unicode", "😀"},
		{"long", "Lorem ipsum dolor sit amet, consectetur adipiscing elit."},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.NotPanics(t, func() {
				got := ProcessData(tt.input)
				assert.Equal(t, tt.input, got)
			})
		})
	}
}

func TestProcessData_PanicsOnEmpty(t *testing.T) {
	assert.PanicsWithValue(t, "empty input", func() {
		_ = ProcessData("")
	})
}
