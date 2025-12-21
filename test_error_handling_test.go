package main

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func withTempWD(t *testing.T) (string, func()) {
	t.Helper()
	old, err := os.Getwd()
	require.NoError(t, err)
	dir := t.TempDir()
	require.NoError(t, os.Chdir(dir))
	return dir, func() { _ = os.Chdir(old) }
}

func TestReadConfig_TableDriven(t *testing.T) {
	type testCase struct {
		name           string
		build          func(t *testing.T, dir string) string
		wantNil        bool
		skipOnWindows  bool
		verifyContents func(t *testing.T, cfg map[string]interface{})
	}
	tests := []testCase{
		{
			name: "missing file returns nil map",
			build: func(t *testing.T, dir string) string {
				return filepath.Join(dir, "does-not-exist.json")
			},
			wantNil: true,
		},
		{
			name: "valid JSON returns populated map",
			build: func(t *testing.T, dir string) string {
				p := filepath.Join(dir, "good.json")
				content := []byte(`{"name":"demo","num":42}`)
				require.NoError(t, os.WriteFile(p, content, 0o644))
				return p
			},
			wantNil: false,
			verifyContents: func(t *testing.T, cfg map[string]interface{}) {
				assert.NotNil(t, cfg)
				v, ok := cfg["name"]
				assert.True(t, ok)
				assert.Equal(t, "demo", v)
				// Numbers in JSON unmarshal as float64
				n, ok := cfg["num"]
				assert.True(t, ok)
				assert.Equal(t, float64(42), n)
			},
		},
		{
			name: "malformed JSON returns nil map",
			build: func(t *testing.T, dir string) string {
				p := filepath.Join(dir, "bad.json")
				content := []byte(`{not-json`)
				require.NoError(t, os.WriteFile(p, content, 0o644))
				return p
			},
			wantNil: true,
		},
		{
			name: "directory path returns nil map",
			build: func(t *testing.T, dir string) string {
				return dir
			},
			wantNil: true,
		},
		{
			name: "permission denied returns nil map (skipped on Windows)",
			build: func(t *testing.T, dir string) string {
				p := filepath.Join(dir, "nope.json")
				require.NoError(t, os.WriteFile(p, []byte(`{"a":1}`), 0o000))
				// restore perms so cleanup works
				t.Cleanup(func() { _ = os.Chmod(p, 0o644) })
				return p
			},
			wantNil:       true,
			skipOnWindows: true,
		},
		{
			name: "empty file returns nil map",
			build: func(t *testing.T, dir string) string {
				p := filepath.Join(dir, "empty.json")
				require.NoError(t, os.WriteFile(p, []byte{}, 0o644))
				return p
			},
			wantNil: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.skipOnWindows && runtime.GOOS == "windows" {
				t.Skip("skipping permission test on windows")
			}
			dir := t.TempDir()
			path := tt.build(t, dir)
			cfg := ReadConfig(path)
			if tt.wantNil {
				assert.Nil(t, cfg)
				return
			}
			assert.NotNil(t, cfg)
			if tt.verifyContents != nil {
				tt.verifyContents(t, cfg)
			}
		})
	}
}

func TestWriteLog_TableDriven(t *testing.T) {
	type testCase struct {
		name      string
		pre       func(t *testing.T, dir string)
		message   string
		wantPanic bool
		verify    func(t *testing.T, dir string)
	}
	tests := []testCase{
		{
			name:    "creates app.log file (content likely empty due to read-only open)",
			pre:     func(t *testing.T, dir string) {},
			message: "hello",
			verify: func(t *testing.T, dir string) {
				fi, err := os.Stat(filepath.Join(dir, "app.log"))
				assert.NoError(t, err)
				assert.NotNil(t, fi)
				assert.False(t, fi.IsDir())
				assert.Equal(t, int64(0), fi.Size())
			},
		},
		{
			name: "panics when app.log is a directory",
			pre: func(t *testing.T, dir string) {
				require.NoError(t, os.Mkdir(filepath.Join(dir, "app.log"), 0o755))
			},
			message:  "will panic",
			wantPanic: true,
		},
		{
			name: "pre-existing file; no panic; file remains present",
			pre: func(t *testing.T, dir string) {
				p := filepath.Join(dir, "app.log")
				require.NoError(t, os.WriteFile(p, []byte{}, 0o644))
			},
			message: "append attempt",
			verify: func(t *testing.T, dir string) {
				_, err := os.Stat(filepath.Join(dir, "app.log"))
				assert.NoError(t, err)
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			_, restore := withTempWD(t)
			defer restore()

			dir, _ := os.Getwd()
			if tt.pre != nil {
				tt.pre(t, dir)
			}

			if tt.wantPanic {
				assert.Panics(t, func() { WriteLog(tt.message) })
				return
			}

			assert.NotPanics(t, func() { WriteLog(tt.message) })
			if tt.verify != nil {
				tt.verify(t, dir)
			}
		})
	}
}

func TestWriteLog_MultipleCalls_NoPanic_AndFileExists(t *testing.T) {
	_, restore := withTempWD(t)
	defer restore()

	assert.NotPanics(t, func() { WriteLog("first") })
	assert.NotPanics(t, func() { WriteLog("second") })

	fi, err := os.Stat("app.log")
	assert.NoError(t, err)
	assert.NotNil(t, fi)
	assert.False(t, fi.IsDir())
	// Expect size remains 0 due to read-only open flags
	assert.Equal(t, int64(0), fi.Size())
}

func TestProcessData_TableDriven(t *testing.T) {
	type testCase struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}
	tests := []testCase{
		{name: "empty input panics", input: "", wantPanic: true},
		{name: "simple string", input: "hello", want: "hello"},
		{name: "single space", input: " ", want: " "},
		{name: "unicode content", input: "こんにちは", want: "こんにちは"},
		{name: "long string", input: "abcdefghijklmnopqrstuvwxyz", want: "abcdefghijklmnopqrstuvwxyz"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() { _ = ProcessData(tt.input) })
				return
			}
			var got string
			assert.NotPanics(t, func() { got = ProcessData(tt.input) })
			assert.Equal(t, tt.want, got)
		})
	}
}
