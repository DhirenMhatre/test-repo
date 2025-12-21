package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig_Table(t *testing.T) {
	dir := t.TempDir()

	tests := []struct {
		name     string
		fileName string
		content  string
		validate func(t *testing.T, got map[string]interface{})
	}{
		{
			name:     "missing file returns nil map",
			fileName: "missing.json",
			content:  "",
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name:     "empty file returns nil map",
			fileName: "empty.json",
			content:  "",
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name:     "invalid JSON returns nil map",
			fileName: "invalid.json",
			content:  "{not-json",
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name:     "array JSON returns nil map",
			fileName: "array.json",
			content:  `["a", 1, true]`,
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name:     "null JSON returns nil map",
			fileName: "null.json",
			content:  `null`,
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name:     "valid empty object returns empty non-nil map",
			fileName: "empty_object.json",
			content:  `{}`,
			validate: func(t *testing.T, got map[string]interface{}) {
				require.NotNil(t, got)
				assert.Equal(t, 0, len(got))
			},
		},
		{
			name:     "valid simple object",
			fileName: "simple.json",
			content:  `{"a": 1, "b": "x"}`,
			validate: func(t *testing.T, got map[string]interface{}) {
				require.NotNil(t, got)
				assert.Equal(t, float64(1), got["a"])
				assert.Equal(t, "x", got["b"])
			},
		},
		{
			name:     "valid nested object",
			fileName: "nested.json",
			content:  `{"arr":[1,"two"], "inner":{"k":true}}`,
			validate: func(t *testing.T, got map[string]interface{}) {
				require.NotNil(t, got)
				arr, ok := got["arr"].([]interface{})
				require.True(t, ok)
				require.Len(t, arr, 2)
				assert.Equal(t, float64(1), arr[0])
				assert.Equal(t, "two", arr[1])

				inner, ok := got["inner"].(map[string]interface{})
				require.True(t, ok)
				v, ok := inner["k"].(bool)
				require.True(t, ok)
				assert.True(t, v)
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(dir, tt.fileName)
			// Only create file for cases that are not "missing file"
			if tt.name != "missing file returns nil map" {
				require.NoError(t, os.WriteFile(path, []byte(tt.content), 0o644))
			}
			got := ReadConfig(path)
			tt.validate(t, got)
		})
	}
}

func TestReadConfig_DoesNotPanicOnGarbage(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "garbage.bin")
	// Write arbitrary non-JSON bytes
	require.NoError(t, os.WriteFile(path, []byte{0x00, 0xFF, 0x10, 0x20}, 0o644))
	assert.NotPanics(t, func() {
		_ = ReadConfig(path)
	})
}

func withTempChdir(t *testing.T) string {
	orig, err := os.Getwd()
	require.NoError(t, err)

	td := t.TempDir()
	require.NoError(t, os.Chdir(td))
	t.Cleanup(func() {
		_ = os.Chdir(orig)
	})
	return td
}

func TestWriteLog_NoWriteAndNoPanic(t *testing.T) {
	_ = withTempChdir(t)

	// Pre-create app.log to avoid platform-specific OpenFile behavior
	require.NoError(t, os.WriteFile("app.log", []byte{}, 0o644))

	tests := []struct {
		name    string
		message string
	}{
		{"empty message", ""},
		{"simple message", "hello"},
		{"long message", "this is a long log message that should not be written due to read-only open flags"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.NotPanics(t, func() {
				WriteLog(tt.message)
			})
			data, err := os.ReadFile("app.log")
			require.NoError(t, err)
			assert.Equal(t, "", string(data))
		})
	}
}

func TestWriteLog_MultipleCallsKeepFileReadable(t *testing.T) {
	_ = withTempChdir(t)

	// Pre-create app.log
	require.NoError(t, os.WriteFile("app.log", []byte{}, 0o644))

	for i := 0; i < 5; i++ {
		assert.NotPanics(t, func() {
			WriteLog("line")
		})
	}
	// File should still exist and be readable
	b, err := os.ReadFile("app.log")
	require.NoError(t, err)
	assert.Equal(t, 0, len(b))

	// We can still write to it ourselves using correct flags, proving no exclusive lock remains
	f, err := os.OpenFile("app.log", os.O_WRONLY|os.O_APPEND, 0o644)
	require.NoError(t, err)
	_, err = f.WriteString("external write")
	require.NoError(t, err)
	require.NoError(t, f.Close())

	// Now content should be present
	b, err = os.ReadFile("app.log")
	require.NoError(t, err)
	assert.Equal(t, "external write", string(b))
}

func TestProcessData_Table(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		want      string
		shouldPnc bool
	}{
		{"normal", "abc", "abc", false},
		{"whitespace", "   ", "   ", false},
		{"unicode", "こんにちは", "こんにちは", false},
		{"numbers", "1234567890", "1234567890", false},
		{"long", "lorem ipsum dolor sit amet consectetur adipiscing elit", "lorem ipsum dolor sit amet consectetur adipiscing elit", false},
		{"empty panics", "", "", true},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.shouldPnc {
				assert.PanicsWithValue(t, "empty input", func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestProcessData_ReturnsInputUnchanged(t *testing.T) {
	inputs := []string{
		"case-sensitive",
		"MiXeD CaSe 123 !@#",
		"with\nnewline",
	}
	for _, in := range inputs {
		in := in
		t.Run(in, func(t *testing.T) {
			assert.Equal(t, in, ProcessData(in))
		})
	}
}
