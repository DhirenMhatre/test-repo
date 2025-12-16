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
	t.Run("various inputs", func(t *testing.T) {
		tests := []struct {
			name       string
			prepare    func(t *testing.T) string
			expectNil  bool
			validate   func(t *testing.T, got map[string]interface{})
			skipOnOS   string
			skipReason string
		}{
			{
				name: "missing file returns nil",
				prepare: func(t *testing.T) string {
					return filepath.Join(t.TempDir(), "nope.json")
				},
				expectNil: true,
			},
			{
				name: "invalid JSON returns nil",
				prepare: func(t *testing.T) string {
					fp := filepath.Join(t.TempDir(), "bad.json")
					require.NoError(t, os.WriteFile(fp, []byte("{not-json"), 0o644))
					return fp
				},
				expectNil: true,
			},
			{
				name: "empty file returns nil",
				prepare: func(t *testing.T) string {
					fp := filepath.Join(t.TempDir(), "empty.json")
					require.NoError(t, os.WriteFile(fp, []byte(""), 0o644))
					return fp
				},
				expectNil: true,
			},
			{
				name: "valid JSON object returns populated map",
				prepare: func(t *testing.T) string {
					fp := filepath.Join(t.TempDir(), "good.json")
					data := `{"foo":"bar","n":1,"b":true}`
					require.NoError(t, os.WriteFile(fp, []byte(data), 0o644))
					return fp
				},
				expectNil: false,
				validate: func(t *testing.T, got map[string]interface{}) {
					assert.NotNil(t, got)
					assert.Equal(t, "bar", got["foo"])
					// encoding/json unmarshals numbers into float64 when decoding into interface{}
					assert.Equal(t, float64(1), got["n"])
					assert.Equal(t, true, got["b"])
				},
			},
			{
				name: "non-object JSON returns nil",
				prepare: func(t *testing.T) string {
					fp := filepath.Join(t.TempDir(), "array.json")
					require.NoError(t, os.WriteFile(fp, []byte(`["a",1]`), 0o644))
					return fp
				},
				expectNil: true,
			},
			{
				name: "permission denied returns nil",
				prepare: func(t *testing.T) string {
					fp := filepath.Join(t.TempDir(), "conf.json")
					require.NoError(t, os.WriteFile(fp, []byte(`{"x":1}`), 0o000))
					t.Cleanup(func() { _ = os.Chmod(fp, 0o644) })
					return fp
				},
				expectNil:  true,
				skipOnOS:   "windows",
				skipReason: "chmod-based permission tests are unreliable on Windows",
			},
		}

		for _, tt := range tests {
			tt := tt
			t.Run(tt.name, func(t *testing.T) {
				if tt.skipOnOS != "" && runtime.GOOS == tt.skipOnOS {
					t.Skip(tt.skipReason)
				}
				t.Parallel()
				path := tt.prepare(t)
				got := ReadConfig(path)

				if tt.expectNil {
					assert.Nil(t, got)
					return
				}
				assert.NotNil(t, got)
				if tt.validate != nil {
					tt.validate(t, got)
				}
			})
		}
	})
}

func TestWriteLog(t *testing.T) {
	// Do not run these subtests in parallel because they change process working directory
	t.Run("creates file and remains empty when writing message", func(t *testing.T) {
		temp := t.TempDir()
		wd, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(temp))
		t.Cleanup(func() { _ = os.Chdir(wd) })

		WriteLog("hello world")

		info, err := os.Stat("app.log")
		require.NoError(t, err)
		assert.False(t, info.IsDir())
		assert.Equal(t, int64(0), info.Size(), "file should exist but remain empty due to read-only open flags")
	})

	t.Run("creates file with empty message", func(t *testing.T) {
		temp := t.TempDir()
		wd, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(temp))
		t.Cleanup(func() { _ = os.Chdir(wd) })

		WriteLog("")

		info, err := os.Stat("app.log")
		require.NoError(t, err)
		assert.False(t, info.IsDir())
		assert.Equal(t, int64(0), info.Size())
	})

	t.Run("multiple writes still empty", func(t *testing.T) {
		temp := t.TempDir()
		wd, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(temp))
		t.Cleanup(func() { _ = os.Chdir(wd) })

		WriteLog("first")
		WriteLog("second")

		info, err := os.Stat("app.log")
		require.NoError(t, err)
		assert.Equal(t, int64(0), info.Size())
	})

	t.Run("panics when directory is not writable", func(t *testing.T) {
		if runtime.GOOS == "windows" {
			t.Skip("chmod-based permission tests are unreliable on Windows")
		}

		base := t.TempDir()
		roDir := filepath.Join(base, "ro")
		require.NoError(t, os.Mkdir(roDir, 0o755))
		// Remove write bit
		require.NoError(t, os.Chmod(roDir, 0o555))
		t.Cleanup(func() { _ = os.Chmod(roDir, 0o755) })

		wd, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(roDir))
		t.Cleanup(func() { _ = os.Chdir(wd) })

		assert.Panics(t, func() {
			WriteLog("should panic due to nil file handle (open failed)")
		})
	})
}

func TestProcessData(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		want        string
		shouldPanic bool
		panicVal    interface{}
	}{
		{
			name:  "simple string",
			input: "abc",
			want:  "abc",
		},
		{
			name:  "emoji preserved",
			input: "hello😀",
			want:  "hello😀",
		},
		{
			name:  "spaces preserved",
			input: "  spaced  ",
			want:  "  spaced  ",
		},
		{
			name:  "numeric string",
			input: "12345",
			want:  "12345",
		},
		{
			name:  "long string",
			input: strings.Repeat("x", 1024),
			want:  strings.Repeat("x", 1024),
		},
		{
			name:        "empty panics",
			input:       "",
			shouldPanic: true,
			panicVal:    "empty input",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if tt.shouldPanic {
				assert.PanicsWithValue(t, tt.panicVal, func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}
