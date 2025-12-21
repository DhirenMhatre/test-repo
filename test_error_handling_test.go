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

func TestReadConfig(t *testing.T) {
	type tc struct {
		name        string
		prepare     func(dir string) string
		expectNil   bool
		expectLen   int
		expectPairs map[string]interface{}
		skipOnWin   bool
	}
	tests := []tc{
		{
			name: "missing file returns nil",
			prepare: func(dir string) string {
				return filepath.Join(dir, "missing.json")
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
			name: "whitespace only returns nil",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "ws.json")
				require.NoError(t, os.WriteFile(p, []byte(" \n\t  "), 0o644))
				return p
			},
			expectNil: true,
		},
		{
			name: "invalid JSON returns nil",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "invalid.json")
				require.NoError(t, os.WriteFile(p, []byte("{not valid json"), 0o644))
				return p
			},
			expectNil: true,
		},
		{
			name: "json null returns nil",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "null.json")
				require.NoError(t, os.WriteFile(p, []byte("null"), 0o644))
				return p
			},
			expectNil: true,
		},
		{
			name: "json array returns nil",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "array.json")
				require.NoError(t, os.WriteFile(p, []byte(`[1,2,3]`), 0o644))
				return p
			},
			expectNil: true,
		},
		{
			name: "valid empty object returns non-nil empty map",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "emptyobj.json")
				require.NoError(t, os.WriteFile(p, []byte(`{}`), 0o644))
				return p
			},
			expectNil: false,
			expectLen: 0,
		},
		{
			name: "valid object with primitives",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "prims.json")
				require.NoError(t, os.WriteFile(p, []byte(`{"foo":"bar","num":42,"bool":true}`), 0o644))
				return p
			},
			expectNil: false,
			expectLen: 3,
			expectPairs: map[string]interface{}{
				"foo":  "bar",
				"num":  float64(42),
				"bool": true,
			},
		},
		{
			name: "valid nested object",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "nested.json")
				require.NoError(t, os.WriteFile(p, []byte(`{"outer":{"inner":"x"},"n":1}`), 0o644))
				return p
			},
			expectNil: false,
			expectLen: 2,
			expectPairs: map[string]interface{}{
				"n": float64(1),
			},
		},
		{
			name: "permission denied returns nil",
			prepare: func(dir string) string {
				p := filepath.Join(dir, "denied.json")
				require.NoError(t, os.WriteFile(p, []byte(`{"x":1}`), 0o644))
				require.NoError(t, os.Chmod(p, 0o000))
				t.Cleanup(func() { _ = os.Chmod(p, 0o644) })
				return p
			},
			expectNil: true,
			skipOnWin: true, // windows permission model differs
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.skipOnWin && runtime.GOOS == "windows" {
				t.Skip("skipping on windows")
			}
			dir := t.TempDir()
			path := tt.prepare(dir)

			got := ReadConfig(path)

			if tt.expectNil {
				assert.Nil(t, got, "expected nil map for %s", tt.name)
				return
			}

			assert.NotNil(t, got, "expected non-nil map for %s", tt.name)
			assert.Equal(t, tt.expectLen, len(got))

			for k, v := range tt.expectPairs {
				val, ok := got[k]
				assert.True(t, ok, "expected key %q to exist", k)
				assert.Equal(t, v, val, "value mismatch for key %q", k)
			}

			// Additional check for nested case
			if strings.Contains(tt.name, "nested") {
				rawOuter, ok := got["outer"]
				assert.True(t, ok, "expected key 'outer'")
				if ok {
					m, ok := rawOuter.(map[string]interface{})
					assert.True(t, ok, "expected 'outer' to be a map")
					if ok {
						v, ok := m["inner"]
						assert.True(t, ok, "expected inner key")
						assert.Equal(t, "x", v)
					}
				}
			}
		})
	}
}

func TestWriteLog(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skipping WriteLog tests on windows due to file handle semantics without Close")
	}

	tests := []struct {
		name    string
		message string
	}{
		{"empty message", ""},
		{"short ascii", "hello world"},
		{"unicode and emoji", "здраво 你好 🙂"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			temp := t.TempDir()
			orig, err := os.Getwd()
			require.NoError(t, err)
			require.NoError(t, os.Chdir(temp))
			t.Cleanup(func() { _ = os.Chdir(orig) })

			assert.NotPanics(t, func() {
				WriteLog(tt.message)
			}, "WriteLog should not panic")

			// File should exist even if write failed due to flags
			_, statErr := os.Stat("app.log")
			assert.NoError(t, statErr, "app.log should exist after WriteLog")
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
		{"empty panics", "", "", true},
		{"simple echo", "abc", "abc", false},
		{"whitespace preserved", "  hi  ", "  hi  ", false},
		{"unicode", "你好", "你好", false},
		{"emoji", "🙂", "🙂", false},
		{"multiline", "line1\nline2", "line1\nline2", false},
		{"long string", strings.Repeat("a", 10000), strings.Repeat("a", 10000), false},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
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
