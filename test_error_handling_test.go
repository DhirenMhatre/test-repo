package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	dir := t.TempDir()

	tests := []struct {
		name     string
		content  string
		filename string
		setup    func(string) string
		validate func(t *testing.T, got map[string]interface{})
	}{
		{
			name:    "valid JSON object returns populated map",
			content: `{"name":"app","version":1,"active":true}`,
			setup: func(d string) string {
				p := filepath.Join(d, "valid.json")
				require.NoError(t, os.WriteFile(p, []byte(`{"name":"app","version":1,"active":true}`), 0o644))
				return p
			},
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.NotNil(t, got)
				assert.Equal(t, "app", got["name"])
				// Numbers become float64 in encoding/json when unmarshaling into interface{}
				assert.Equal(t, float64(1), got["version"])
				assert.Equal(t, true, got["active"])
			},
		},
		{
			name:    "empty object yields empty non-nil map",
			content: `{}`,
			setup: func(d string) string {
				p := filepath.Join(d, "empty_object.json")
				require.NoError(t, os.WriteFile(p, []byte(`{}`), 0o644))
				return p
			},
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.NotNil(t, got)
				assert.Len(t, got, 0)
			},
		},
		{
			name:    "invalid JSON yields nil map",
			content: `{invalid`,
			setup: func(d string) string {
				p := filepath.Join(d, "invalid.json")
				require.NoError(t, os.WriteFile(p, []byte(`{invalid`), 0o644))
				return p
			},
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name: "nonexistent file yields nil map",
			setup: func(d string) string {
				return filepath.Join(d, "does-not-exist.json")
			},
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name: "empty file yields nil map",
			setup: func(d string) string {
				p := filepath.Join(d, "empty.json")
				require.NoError(t, os.WriteFile(p, []byte(""), 0o644))
				return p
			},
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name:    "JSON null yields nil map",
			content: `null`,
			setup: func(d string) string {
				p := filepath.Join(d, "null.json")
				require.NoError(t, os.WriteFile(p, []byte(`null`), 0o644))
				return p
			},
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
	}

	for _, tt := range tests {
		path := tt.setup(dir)
		t.Run(tt.name, func(t *testing.T) {
			got := ReadConfig(path)
			tt.validate(t, got)
		})
	}
}

func TestWriteLog_CreatesFile(t *testing.T) {
	tests := []struct {
		name    string
		message string
	}{
		{"normal message", "hello world"},
		{"empty message", ""},
		{"long message", "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			wd, err := os.Getwd()
			require.NoError(t, err)
			t.Cleanup(func() { _ = os.Chdir(wd) })

			dir := t.TempDir()
			require.NoError(t, os.Chdir(dir))

			WriteLog(tt.message)

			info, statErr := os.Stat(filepath.Join(dir, "app.log"))
			assert.NoError(t, statErr)
			assert.False(t, info.IsDir())
		})
	}
}

func TestWriteLog_IdempotentCalls(t *testing.T) {
	wd, err := os.Getwd()
	require.NoError(t, err)
	t.Cleanup(func() { _ = os.Chdir(wd) })

	dir := t.TempDir()
	require.NoError(t, os.Chdir(dir))

	WriteLog("first")
	WriteLog("second")

	_, statErr := os.Stat(filepath.Join(dir, "app.log"))
	assert.NoError(t, statErr)
}

func TestProcessData_ReturnsInput(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{"simple", "data"},
		{"whitespace", "  spaced  "},
		{"unicode", "こんにちは世界"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ProcessData(tt.input)
			assert.Equal(t, tt.input, got)
		})
	}
}

func TestProcessData_PanicsOnEmpty(t *testing.T) {
	assert.Panics(t, func() {
		_ = ProcessData("")
	})
}

func TestProcessData_PanicValue(t *testing.T) {
	assert.PanicsWithValue(t, "empty input", func() {
		_ = ProcessData("")
	})
}
