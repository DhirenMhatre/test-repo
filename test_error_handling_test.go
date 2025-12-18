package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReadConfig_Table(t *testing.T) {
	dir := t.TempDir()

	type tc struct {
		name       string
		filename   string
		content    string
		createFile bool
		wantNil    bool
		wantLen    int
		checkKeys  map[string]interface{}
	}

	tests := []tc{
		{
			name:       "missing file returns nil map",
			filename:   "missing.json",
			createFile: false,
			wantNil:    true,
		},
		{
			name:       "empty file returns nil map",
			filename:   "empty.json",
			content:    "",
			createFile: true,
			wantNil:    true,
		},
		{
			name:       "invalid JSON returns nil map",
			filename:   "invalid.json",
			content:    "{not json",
			createFile: true,
			wantNil:    true,
		},
		{
			name:       "JSON array returns nil map",
			filename:   "array.json",
			content:    `["a",1]`,
			createFile: true,
			wantNil:    true,
		},
		{
			name:       "empty object produces non-nil empty map",
			filename:   "empty_object.json",
			content:    `{}`,
			createFile: true,
			wantNil:    false,
			wantLen:    0,
		},
		{
			name:       "valid object with keys populates map",
			filename:   "valid.json",
			content:    `{"a":1,"b":"x"}`,
			createFile: true,
			wantNil:    false,
			wantLen:    2,
			checkKeys: map[string]interface{}{
				"a": float64(1),
				"b": "x",
			},
		},
		{
			name:       "nested object is decoded into nested maps",
			filename:   "nested.json",
			content:    `{"outer":{"inner":42}}`,
			createFile: true,
			wantNil:    false,
			wantLen:    1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(dir, tt.filename)
			if tt.createFile {
				err := os.WriteFile(path, []byte(tt.content), 0o644)
				assert.NoError(t, err)
			}
			got := ReadConfig(path)
			if tt.wantNil {
				assert.Nil(t, got, "expected nil map")
				return
			}
			assert.NotNil(t, got, "expected non-nil map")
			if tt.wantLen >= 0 {
				assert.Len(t, got, tt.wantLen)
			}
			for k, v := range tt.checkKeys {
				val, ok := got[k]
				assert.True(t, ok, "expected key %q to exist", k)
				assert.Equal(t, v, val)
			}
			if tt.name == "nested object is decoded into nested maps" {
				outer, ok := got["outer"].(map[string]interface{})
				assert.True(t, ok)
				if assert.NotNil(t, outer) {
					assert.Equal(t, float64(42), outer["inner"])
				}
			}
		})
	}
}

func TestWriteLog_Table(t *testing.T) {
	// Change working directory to a temp dir to avoid touching repo root
	cwd, err := os.Getwd()
	assert.NoError(t, err)
	temp := t.TempDir()
	assert.NoError(t, os.Chdir(temp))
	defer func() { _ = os.Chdir(cwd) }()

	logPath := filepath.Join(temp, "app.log")

	tests := []struct {
		name    string
		message string
	}{
		{"simple message", "hello"},
		{"empty message", ""},
		{"long message", strings.Repeat("x", 2048)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.NotPanics(t, func() {
				WriteLog(tt.message)
			})
			_, statErr := os.Stat(logPath)
			assert.NoError(t, statErr, "expected app.log to exist")
		})
	}
}

func TestWriteLog_MultipleCalls_NoPanic_AndFileExists(t *testing.T) {
	cwd, err := os.Getwd()
	assert.NoError(t, err)
	temp := t.TempDir()
	assert.NoError(t, os.Chdir(temp))
	defer func() { _ = os.Chdir(cwd) }()

	logPath := filepath.Join(temp, "app.log")

	for i := 0; i < 5; i++ {
		assert.NotPanics(t, func() {
			WriteLog("msg " + strings.Repeat("y", i))
		})
	}

	_, statErr := os.Stat(logPath)
	assert.NoError(t, statErr, "expected app.log to exist after multiple writes")
}

func TestProcessData_Table(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		want        string
		shouldPanic bool
		panicValue  interface{}
	}{
		{name: "non-empty string", input: "hello", want: "hello"},
		{name: "whitespace string", input: "   ", want: "   "},
		{name: "unicode string", input: "こんにちは世界", want: "こんにちは世界"},
		{name: "long string", input: strings.Repeat("abc", 300), want: strings.Repeat("abc", 300)},
		{name: "empty string panics", input: "", shouldPanic: true, panicValue: "empty input"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.shouldPanic {
				assert.PanicsWithValue(t, tt.panicValue, func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}
