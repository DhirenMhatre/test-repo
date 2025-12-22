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

	tests := []struct {
		name       string
		content    string
		filename   string
		createFile bool
		wantNil    bool
		wantChecks func(t *testing.T, cfg map[string]interface{})
	}{
		{
			name:       "missing file returns nil",
			filename:   "missing.json",
			createFile: false,
			wantNil:    true,
		},
		{
			name:       "empty file returns nil",
			filename:   "empty.json",
			createFile: true,
			content:    "",
			wantNil:    true,
		},
		{
			name:       "invalid JSON returns nil",
			filename:   "invalid.json",
			createFile: true,
			content:    "{not:valid",
			wantNil:    true,
		},
		{
			name:       "JSON array returns nil because target is map",
			filename:   "array.json",
			createFile: true,
			content:    "[1,2,3]",
			wantNil:    true,
		},
		{
			name:       "valid flat JSON object",
			filename:   "valid.json",
			createFile: true,
			content:    `{"a":1,"b":"x"}`,
			wantNil:    false,
			wantChecks: func(t *testing.T, cfg map[string]interface{}) {
				assert.NotNil(t, cfg)
				av, ok := cfg["a"].(float64)
				assert.True(t, ok)
				assert.Equal(t, float64(1), av)

				bv, ok := cfg["b"].(string)
				assert.True(t, ok)
				assert.Equal(t, "x", bv)
			},
		},
		{
			name:       "valid nested JSON object",
			filename:   "nested.json",
			createFile: true,
			content:    `{"nested":{"n":2},"arr":[1,2]}`,
			wantNil:    false,
			wantChecks: func(t *testing.T, cfg map[string]interface{}) {
				assert.NotNil(t, cfg)
				nested, ok := cfg["nested"].(map[string]interface{})
				assert.True(t, ok)
				if assert.NotNil(t, nested) {
					nv, ok := nested["n"].(float64)
					assert.True(t, ok)
					assert.Equal(t, float64(2), nv)
				}
				// array should be present but we don't dereference without checks
				_, ok = cfg["arr"].([]interface{})
				assert.True(t, ok)
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(tmp, tt.filename)
			if tt.createFile {
				err := os.WriteFile(path, []byte(tt.content), 0o644)
				assert.NoError(t, err)
			}
			cfg := ReadConfig(path)
			if tt.wantNil {
				assert.Nil(t, cfg)
				return
			}
			assert.NotNil(t, cfg)
			if tt.wantChecks != nil {
				tt.wantChecks(t, cfg)
			}
		})
	}
}

func TestWriteLog_FileCreatedButNoContent(t *testing.T) {
	tests := []struct {
		name    string
		message string
	}{
		{"normal message", "hello world"},
		{"empty message", ""},
		{"multiline message", "line1\nline2"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			tmp := t.TempDir()
			wd, err := os.Getwd()
			assert.NoError(t, err)

			err = os.Chdir(tmp)
			assert.NoError(t, err)
			defer func() {
				_ = os.Chdir(wd)
			}()

			_, statErr := os.Stat("app.log")
			assert.True(t, os.IsNotExist(statErr))

			// Should not panic in writable directory
			assert.NotPanics(t, func() {
				WriteLog(tt.message)
			})

			info, err := os.Stat("app.log")
			assert.NoError(t, err)
			assert.False(t, info.IsDir())

			// Because file opened without write flag, writes fail and file stays empty.
			assert.Equal(t, int64(0), info.Size())
		})
	}
}

func TestWriteLog_MultipleCallsStillEmpty(t *testing.T) {
	tmp := t.TempDir()
	wd, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmp)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(wd)
	}()

	assert.NotPanics(t, func() {
		WriteLog("first")
		WriteLog("second")
		WriteLog(strings.Repeat("x", 1024))
	})

	info, err := os.Stat("app.log")
	assert.NoError(t, err)
	assert.Equal(t, int64(0), info.Size())
}

func TestProcessData(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		want        string
		shouldPanic bool
		panicMsg    string
	}{
		{"non-empty simple", "abc", "abc", false, ""},
		{"single char", "x", "x", false, ""},
		{"whitespace", "   ", "   ", false, ""},
		{"unicode", "こんにちは世界", "こんにちは世界", false, ""},
		{"emoji", "hello 👋🌍", "hello 👋🌍", false, ""},
		{"long string", strings.Repeat("a", 2048), strings.Repeat("a", 2048), false, ""},
		{"json-looking string", `{"k":"v"}`, `{"k":"v"}`, false, ""},
		{"special chars", "!@#$%^&*()_+-=[]{}|;':,./<>?", "!@#$%^&*()_+-=[]{}|;':,./<>?", false, ""},
		{"empty panics", "", "", true, "empty input"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.shouldPanic {
				assert.PanicsWithValue(t, tt.panicMsg, func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			assert.NotPanics(t, func() {
				got := ProcessData(tt.input)
				assert.Equal(t, tt.want, got)
			})
		})
	}
}
