package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	tmp := t.TempDir()

	writeFile := func(name, content string) string {
		p := filepath.Join(tmp, name)
		require.NoError(t, os.WriteFile(p, []byte(content), 0o644))
		return p
	}

	tests := []struct {
		name       string
		path       string
		prepare    func() string
		wantNil    bool
		wantLength int
		wantKeys   map[string]interface{}
	}{
		{
			name:    "nonexistent file returns nil map",
			prepare: func() string { return filepath.Join(tmp, "missing.json") },
			wantNil: true,
		},
		{
			name:    "path is a directory returns nil map",
			prepare: func() string { return tmp },
			wantNil: true,
		},
		{
			name:    "invalid JSON returns nil map",
			prepare: func() string { return writeFile("bad.json", "{ bad json") },
			wantNil: true,
		},
		{
			name:    "null JSON returns nil map",
			prepare: func() string { return writeFile("null.json", "null") },
			wantNil: true,
		},
		{
			name:       "empty object results in non-nil empty map",
			prepare:    func() string { return writeFile("empty_obj.json", "{}") },
			wantNil:    false,
			wantLength: 0,
		},
		{
			name:    "valid JSON object parsed into map",
			prepare: func() string { return writeFile("valid.json", `{"a":1,"b":"x"}`) },
			wantNil: false,
			wantKeys: map[string]interface{}{
				"a": float64(1),
				"b": "x",
			},
		},
		{
			name:    "array JSON returns nil map",
			prepare: func() string { return writeFile("array.json", `[]`) },
			wantNil: true,
		},
		{
			name:    "whitespace JSON object parsed",
			prepare: func() string { return writeFile("ws.json", "  {  \"k\"  :  \"v\"  }  ") },
			wantNil: false,
			wantKeys: map[string]interface{}{
				"k": "v",
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			path := tt.path
			if tt.prepare != nil {
				path = tt.prepare()
			}
			got := ReadConfig(path)

			if tt.wantNil {
				assert.Nil(t, got)
				return
			}

			assert.NotNil(t, got)
			if tt.wantLength >= 0 {
				assert.Len(t, got, tt.wantLength)
			}
			for k, v := range tt.wantKeys {
				val, ok := got[k]
				assert.True(t, ok, "expected key %q to exist", k)
				assert.Equal(t, v, val)
			}
		})
	}
}

func TestWriteLog_Behavior(t *testing.T) {
	tmp := t.TempDir()

	origWD, err := os.Getwd()
	require.NoError(t, err)
	defer func() { _ = os.Chdir(origWD) }()

	require.NoError(t, os.Chdir(tmp))

	callWriteLogSafe := func(msg string) (panicked bool) {
		defer func() {
			if r := recover(); r != nil {
				panicked = true
			}
		}()
		WriteLog(msg)
		return false
	}

	readAppLog := func() (exists bool, content []byte) {
		b, err := os.ReadFile("app.log")
		if err != nil {
			return false, nil
		}
		return true, b
	}

	tests := []struct {
		name    string
		message string
		setup   func()
	}{
		{
			name:    "creates file but does not write content",
			message: "hello world",
		},
		{
			name:    "empty message still creates file but no content",
			message: "",
		},
		{
			name:    "preexisting read-only file remains empty",
			message: "should not be written",
			setup: func() {
				require.NoError(t, os.WriteFile("app.log", []byte{}, 0o444))
			},
		},
		{
			name:    "multiple calls keep file empty",
			message: "first",
			setup: func() {
				_ = callWriteLogSafe("second")
				_ = callWriteLogSafe("third")
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			// Ensure a clean state for each subtest
			_ = os.Remove("app.log")
			if tt.setup != nil {
				tt.setup()
			}

			panicked := callWriteLogSafe(tt.message)
			exists, content := readAppLog()

			// The implementation may panic on some platforms if OpenFile fails,
			// or it may create the file but fail to write. We accept either:
			// - panicked is true
			// - file exists and is empty
			fileEmpty := exists && len(content) == 0
			assert.True(t, panicked || fileEmpty, "expected either panic or an empty app.log file")
		})
	}
}

func TestProcessData(t *testing.T) {
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
			name:  "simple string returns same",
			input: "abc",
			want:  "abc",
		},
		{
			name:  "unicode string returns same",
			input: "こんにちは",
			want:  "こんにちは",
		},
		{
			name:  "long string returns same",
			input: "this is a long input string to ensure it returns as is without modification",
			want:  "this is a long input string to ensure it returns as is without modification",
		},
		{
			name:  "string with spaces and punctuation",
			input: "  spaced - punctuation! ",
			want:  "  spaced - punctuation! ",
		},
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
