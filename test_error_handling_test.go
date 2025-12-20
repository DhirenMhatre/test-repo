package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReadConfig(t *testing.T) {
	tmp := t.TempDir()

	type tc struct {
		name     string
		filename string
		create   bool
		contents string
		wantNil  bool
		check    func(t *testing.T, cfg map[string]interface{})
	}

	tests := []tc{
		{
			name:     "missing file returns nil map",
			filename: "missing.json",
			create:   false,
			wantNil:  true,
		},
		{
			name:     "invalid JSON returns nil map",
			filename: "bad.json",
			create:   true,
			contents: "{ invalid json",
			wantNil:  true,
		},
		{
			name:     "empty file returns nil map",
			filename: "empty.json",
			create:   true,
			contents: "",
			wantNil:  true,
		},
		{
			name:     "valid empty object returns empty non-nil map",
			filename: "empty_obj.json",
			create:   true,
			contents: "{}",
			wantNil:  false,
			check: func(t *testing.T, cfg map[string]interface{}) {
				assert.NotNil(t, cfg)
				assert.Equal(t, 0, len(cfg))
			},
		},
		{
			name:     "valid object with fields",
			filename: "valid.json",
			create:   true,
			contents: `{"a":1,"b":"x"}`,
			wantNil:  false,
			check: func(t *testing.T, cfg map[string]interface{}) {
				assert.NotNil(t, cfg)
				v, ok := cfg["a"]
				assert.True(t, ok)
				// JSON numbers decode to float64
				assert.Equal(t, float64(1), v)
				b, ok := cfg["b"]
				assert.True(t, ok)
				assert.Equal(t, "x", b)
			},
		},
		{
			name:     "top-level array into map returns nil map",
			filename: "array.json",
			create:   true,
			contents: `["x", "y"]`,
			wantNil:  true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(tmp, tt.filename)
			if tt.create {
				err := os.WriteFile(path, []byte(tt.contents), 0o644)
				assert.NoError(t, err)
			}
			cfg := ReadConfig(path)

			if tt.wantNil {
				assert.Nil(t, cfg)
				return
			}
			assert.NotNil(t, cfg)
			if tt.check != nil {
				tt.check(t, cfg)
			}
		})
	}
}

func TestWriteLog_NotPanicsAndCreatesFile(t *testing.T) {
	tests := []struct {
		name    string
		message string
	}{
		{"empty message", ""},
		{"ascii message", "hello world"},
		{"unicode message", "こんにちは世界🌏"},
		{"long message", strings.Repeat("x", 8192)},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.NotPanics(t, func() {
				WriteLog(tt.message)
			})
			// After calling WriteLog, app.log should exist in the current working directory
			_, err := os.Stat("app.log")
			assert.NoError(t, err)
		})
	}
}

func TestWriteLog_RepeatedCalls_DoNotPanic(t *testing.T) {
	assert.NotPanics(t, func() {
		WriteLog("first")
		WriteLog("second")
		WriteLog("third")
	})
	_, err := os.Stat("app.log")
	assert.NoError(t, err)
}

func TestProcessData(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}{
		{"normal string", "hello", "hello", false},
		{"single space", " ", " ", false},
		{"numeric string", "0", "0", false},
		{"unicode", "中文输入", "中文输入", false},
		{"special chars", "\n\t\r", "\n\t\r", false},
		{"long string", strings.Repeat("a", 10000), strings.Repeat("a", 10000), false},
		{"empty input panics", "", "", true},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			var got string
			assert.NotPanics(t, func() {
				got = ProcessData(tt.input)
			})
			assert.Equal(t, tt.want, got)
		})
	}
}
