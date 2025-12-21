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

	t.Run("various inputs", func(t *testing.T) {
		t.Parallel()

		type tc struct {
			name    string
			setup   func(t *testing.T) string
			wantNil bool
			check   func(t *testing.T, got map[string]interface{})
			wantLen int
			cleanup func()
		}

		tests := []tc{
			{
				name: "non-existent file returns nil map",
				setup: func(t *testing.T) string {
					t.Helper()
					return filepath.Join(t.TempDir(), "missing.json")
				},
				wantNil: true,
			},
			{
				name: "invalid JSON returns nil map",
				setup: func(t *testing.T) string {
					t.Helper()
					dir := t.TempDir()
					p := filepath.Join(dir, "bad.json")
					require.NoError(t, os.WriteFile(p, []byte("{not: valid json"), 0o644))
					return p
				},
				wantNil: true,
			},
			{
				name: "empty file returns nil map",
				setup: func(t *testing.T) string {
					t.Helper()
					dir := t.TempDir()
					p := filepath.Join(dir, "empty.json")
					require.NoError(t, os.WriteFile(p, []byte(""), 0o644))
					return p
				},
				wantNil: true,
			},
			{
				name: "empty object returns empty non-nil map",
				setup: func(t *testing.T) string {
					t.Helper()
					dir := t.TempDir()
					p := filepath.Join(dir, "empty_obj.json")
					require.NoError(t, os.WriteFile(p, []byte(`{}`), 0o644))
					return p
				},
				wantNil: false,
				wantLen: 0,
			},
			{
				name: "simple object returns map with values",
				setup: func(t *testing.T) string {
					t.Helper()
					dir := t.TempDir()
					p := filepath.Join(dir, "simple.json")
					require.NoError(t, os.WriteFile(p, []byte(`{"a":1,"b":"x"}`), 0o644))
					return p
				},
				wantNil: false,
				check: func(t *testing.T, got map[string]interface{}) {
					valA, ok := got["a"]
					assert.True(t, ok, "key a present")
					if assert.IsType(t, float64(0), valA) {
						assert.Equal(t, float64(1), valA)
					}
					valB, ok := got["b"]
					assert.True(t, ok, "key b present")
					assert.Equal(t, "x", valB)
				},
			},
			{
				name: "nested object returns nested map",
				setup: func(t *testing.T) string {
					t.Helper()
					dir := t.TempDir()
					p := filepath.Join(dir, "nested.json")
					require.NoError(t, os.WriteFile(p, []byte(`{"n":{"x":2}}`), 0o644))
					return p
				},
				wantNil: false,
				check: func(t *testing.T, got map[string]interface{}) {
					nRaw, ok := got["n"]
					assert.True(t, ok, "key n present")
					if assert.IsType(t, map[string]interface{}{}, nRaw) {
						n := nRaw.(map[string]interface{})
						x, okx := n["x"]
						assert.True(t, okx, "key x present")
						if assert.IsType(t, float64(0), x) {
							assert.Equal(t, float64(2), x)
						}
					}
				},
			},
			{
				name: "array JSON returns nil map",
				setup: func(t *testing.T) string {
					t.Helper()
					dir := t.TempDir()
					p := filepath.Join(dir, "array.json")
					require.NoError(t, os.WriteFile(p, []byte(`[1,2,3]`), 0o644))
					return p
				},
				wantNil: true,
			},
		}

		for _, tt := range tests {
			tt := tt
			t.Run(tt.name, func(t *testing.T) {
				t.Parallel()
				path := tt.setup(t)
				got := ReadConfig(path)

				if tt.wantNil {
					assert.Nil(t, got)
					return
				}

				assert.NotNil(t, got)
				if tt.wantLen >= 0 {
					assert.Equal(t, tt.wantLen, len(got))
				}
				if tt.check != nil {
					tt.check(t, got)
				}
			})
		}
	})
}

func TestWriteLog_ContentUnchanged(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		preContent *string
		message    string
		want       string
	}{
		{
			name:       "creates file but cannot write - empty initial",
			preContent: nil, // file does not exist initially
			message:    "hello world",
			want:       "", // write fails, file stays empty
		},
		{
			name:       "existing content unchanged",
			preContent: ptrStr("old"),
			message:    "new",
			want:       "old",
		},
		{
			name:       "multi-line message not appended",
			preContent: ptrStr("line1\n"),
			message:    "line2\n",
			want:       "line1\n",
		},
		{
			name:       "empty message no-op",
			preContent: ptrStr("seed"),
			message:    "",
			want:       "seed",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			// Use unique working directory per subtest
			wd, err := os.Getwd()
			require.NoError(t, err)
			dir := t.TempDir()
			require.NoError(t, os.Chdir(dir))
			t.Cleanup(func() { _ = os.Chdir(wd) })

			if tt.preContent != nil {
				require.NoError(t, os.WriteFile("app.log", []byte(*tt.preContent), 0o644))
			}

			WriteLog(tt.message)

			// File should exist after WriteLog due to O_CREATE, even if empty.
			data, err := os.ReadFile("app.log")
			require.NoError(t, err)
			assert.Equal(t, tt.want, string(data))
		})
	}
}

func TestWriteLog_PanicsWhenOpenFails(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("chmod not reliable on Windows for this scenario")
	}
	t.Parallel()

	wd, err := os.Getwd()
	require.NoError(t, err)
	dir := t.TempDir()
	require.NoError(t, os.Chdir(dir))
	t.Cleanup(func() { _ = os.Chdir(wd) })

	// Make directory non-writable to force os.OpenFile to fail
	require.NoError(t, os.Chmod(dir, 0o555))
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })

	assert.Panics(t, func() {
		WriteLog("should panic due to nil file.WriteString")
	})
}

func TestProcessData(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		in        string
		want      string
		wantPanic bool
	}{
		{
			name:      "empty input panics",
			in:        "",
			wantPanic: true,
		},
		{
			name: "simple string returns same",
			in:   "hello",
			want: "hello",
		},
		{
			name: "whitespace string returns same",
			in:   " ",
			want: " ",
		},
		{
			name: "unicode string returns same",
			in:   "こんにちは世界",
			want: "こんにちは世界",
		},
		{
			name: "long string returns same",
			in:   "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			want: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			if tt.wantPanic {
				assert.Panics(t, func() { _ = ProcessData(tt.in) })
				return
			}

			assert.NotPanics(t, func() {
				got := ProcessData(tt.in)
				assert.Equal(t, tt.want, got)
			})
		})
	}
}

func ptrStr(s string) *string { return &s }
