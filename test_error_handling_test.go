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
	t.Parallel()

	type setupFn func(t *testing.T) string

	tests := []struct {
		name        string
		setup       setupFn
		expectNil   bool
		verifyAttrs func(t *testing.T, cfg map[string]interface{})
	}{
		{
			name: "nonexistent file returns nil",
			setup: func(t *testing.T) string {
				return filepath.Join(t.TempDir(), "does-not-exist.json")
			},
			expectNil: true,
		},
		{
			name: "empty file returns nil",
			setup: func(t *testing.T) string {
				dir := t.TempDir()
				p := filepath.Join(dir, "empty.json")
				require.NoError(t, os.WriteFile(p, []byte(""), 0600))
				return p
			},
			expectNil: true,
		},
		{
			name: "invalid JSON returns nil",
			setup: func(t *testing.T) string {
				dir := t.TempDir()
				p := filepath.Join(dir, "bad.json")
				require.NoError(t, os.WriteFile(p, []byte("not-json"), 0600))
				return p
			},
			expectNil: true,
		},
		{
			name: "valid flat JSON returns populated map",
			setup: func(t *testing.T) string {
				dir := t.TempDir()
				p := filepath.Join(dir, "ok.json")
				content := `{"a": 1, "s": "x", "b": true}`
				require.NoError(t, os.WriteFile(p, []byte(content), 0600))
				return p
			},
			expectNil: false,
			verifyAttrs: func(t *testing.T, cfg map[string]interface{}) {
				assert.NotNil(t, cfg)
				// numbers are float64 in encoding/json when decoding into interface{}
				if assert.Contains(t, cfg, "a") {
					assert.Equal(t, float64(1), cfg["a"])
				}
				if assert.Contains(t, cfg, "s") {
					assert.Equal(t, "x", cfg["s"])
				}
				if assert.Contains(t, cfg, "b") {
					assert.Equal(t, true, cfg["b"])
				}
			},
		},
		{
			name: "valid nested JSON returns nested map",
			setup: func(t *testing.T) string {
				dir := t.TempDir()
				p := filepath.Join(dir, "nested.json")
				content := `{"nested": {"k": "v"}}`
				require.NoError(t, os.WriteFile(p, []byte(content), 0600))
				return p
			},
			expectNil: false,
			verifyAttrs: func(t *testing.T, cfg map[string]interface{}) {
				assert.NotNil(t, cfg)
				nestedVal, ok := cfg["nested"]
				if assert.True(t, ok, "nested key should exist") && assert.NotNil(t, nestedVal) {
					nestedMap, ok := nestedVal.(map[string]interface{})
					if assert.True(t, ok, "nested should be a map") && nestedMap != nil {
						if assert.Contains(t, nestedMap, "k") {
							assert.Equal(t, "v", nestedMap["k"])
						}
					}
				}
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			path := tt.setup(t)
			got := ReadConfig(path)
			if tt.expectNil {
				assert.Nil(t, got)
				return
			}
			assert.NotNil(t, got)
			if tt.verifyAttrs != nil {
				tt.verifyAttrs(t, got)
			}
		})
	}
}

func TestWriteLog(t *testing.T) {
	// Do not run in parallel because tests change the working directory
	chdirTemp := func(t *testing.T) (restore func()) {
		t.Helper()
		dir := t.TempDir()
		orig, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(dir))
		return func() {
			_ = os.Chdir(orig)
		}
	}

	tests := []struct {
		name        string
		setup       func(t *testing.T)
		expectPanic bool
		after       func(t *testing.T)
	}{
		{
			name: "panics when app.log is a directory (OpenFile fails, then nil write)",
			setup: func(t *testing.T) {
				restore := chdirTemp(t)
				t.Cleanup(restore)
				require.NoError(t, os.Mkdir("app.log", 0755))
			},
			expectPanic: true,
		},
		{
			name: "does not panic when app.log exists as a file",
			setup: func(t *testing.T) {
				restore := chdirTemp(t)
				t.Cleanup(restore)
				require.NoError(t, os.WriteFile("app.log", []byte("existing"), 0644))
			},
			expectPanic: false,
			after: func(t *testing.T) {
				_, err := os.Stat("app.log")
				assert.NoError(t, err)
			},
		},
		{
			name: "does not panic when app.log does not exist and can be created",
			setup: func(t *testing.T) {
				restore := chdirTemp(t)
				t.Cleanup(restore)
				// No file created here; WriteLog should attempt to create it
			},
			expectPanic: false,
			after: func(t *testing.T) {
				_, err := os.Stat("app.log")
				assert.NoError(t, err, "app.log should be created")
			},
		},
		{
			name: "panics when directory is not writable (skip on Windows)",
			setup: func(t *testing.T) {
				if runtime.GOOS == "windows" {
					t.Skip("permission test skipped on Windows")
				}
				restore := chdirTemp(t)
				t.Cleanup(restore)
				require.NoError(t, os.Chmod(".", 0555))
				t.Cleanup(func() { _ = os.Chmod(".", 0755) })
			},
			expectPanic: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			tt.setup(t)
			if tt.expectPanic {
				assert.Panics(t, func() {
					WriteLog("hello")
				})
			} else {
				assert.NotPanics(t, func() {
					WriteLog("hello")
				})
			}
			if tt.after != nil {
				tt.after(t)
			}
		})
	}
}

func TestProcessData(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name        string
		input       string
		expectPanic bool
		want        string
	}{
		{
			name:        "empty string panics",
			input:       "",
			expectPanic: true,
		},
		{
			name:        "simple string returns same",
			input:       "hello",
			expectPanic: false,
			want:        "hello",
		},
		{
			name:        "whitespace string returns same",
			input:       "   ",
			expectPanic: false,
			want:        "   ",
		},
		{
			name:        "unicode string returns same",
			input:       "こんにちは世界",
			expectPanic: false,
			want:        "こんにちは世界",
		},
		{
			name:        "long string returns same",
			input:       "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			expectPanic: false,
			want:        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if tt.expectPanic {
				assert.Panics(t, func() {
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
