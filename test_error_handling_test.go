package main

import (
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	dir := t.TempDir()

	tests := []struct {
		name          string
		content       string
		create        bool
		permDenied    bool
		skipOnWindows bool
		expectedNil   bool
		expectedMap   map[string]interface{}
	}{
		{
			name:        "missing file returns nil map",
			create:      false,
			expectedNil: true,
		},
		{
			name:        "empty file returns nil map",
			create:      true,
			content:     "",
			expectedNil: true,
		},
		{
			name:        "malformed json returns nil map",
			create:      true,
			content:     "{ invalid json ",
			expectedNil: true,
		},
		{
			name:        "empty object returns non-nil empty map",
			create:      true,
			content:     "{}",
			expectedNil: false,
			expectedMap: map[string]interface{}{},
		},
		{
			name:        "valid object returns populated map",
			create:      true,
			content:     `{"a":1,"b":"x"}`,
			expectedNil: false,
			expectedMap: map[string]interface{}{"a": float64(1), "b": "x"},
		},
		{
			name:        "array top-level returns nil map",
			create:      true,
			content:     `["not","an","object"]`,
			expectedNil: true,
		},
		{
			name:          "permission denied returns nil map",
			create:        true,
			content:       "{}",
			permDenied:    true,
			skipOnWindows: true,
			expectedNil:   true,
		},
	}

	for i, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := filepath.Join(dir, "file_"+strconv.Itoa(i)+".json")
			if tt.create {
				require.NoError(t, os.WriteFile(p, []byte(tt.content), 0600))
			}
			if tt.permDenied {
				if runtime.GOOS == "windows" && tt.skipOnWindows {
					t.Skip("permission semantics differ on Windows")
				}
				require.NoError(t, os.Chmod(p, 0000))
				defer func() {
					_ = os.Chmod(p, 0600)
				}()
			}

			got := ReadConfig(p)
			if tt.expectedNil {
				assert.Nil(t, got)
				return
			}
			assert.NotNil(t, got)
			if tt.expectedMap != nil {
				assert.Equal(t, tt.expectedMap, got)
			}
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
			name:  "normal string returns same",
			input: "hello",
			want:  "hello",
		},
		{
			name:  "whitespace string returns same",
			input: " ",
			want:  " ",
		},
		{
			name:  "unicode string returns same",
			input: "こんにちは",
			want:  "こんにちは",
		},
		{
			name:      "empty input panics",
			input:     "",
			wantPanic: true,
		},
		{
			name:  "long string returns same",
			input: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			want:  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		},
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

func TestWriteLog(t *testing.T) {
	origWD, err := os.Getwd()
	require.NoError(t, err)

	t.Run("creates app.log but does not write content", func(t *testing.T) {
		tmp := t.TempDir()
		require.NoError(t, os.Chdir(tmp))
		defer func() { _ = os.Chdir(origWD) }()

		WriteLog("hello world")

		info, statErr := os.Stat("app.log")
		assert.NoError(t, statErr)
		if info != nil {
			assert.Equal(t, int64(0), info.Size())
		} else {
			t.Fatal("app.log should exist")
		}
	})

	t.Run("existing read-only app.log remains empty after write attempt", func(t *testing.T) {
		tmp := t.TempDir()
		require.NoError(t, os.Chdir(tmp))
		defer func() { _ = os.Chdir(origWD) }()

		require.NoError(t, os.WriteFile("app.log", nil, 0444))

		WriteLog("test message")

		info, err := os.Stat("app.log")
		assert.NoError(t, err)
		if assert.NotNil(t, info) {
			assert.Equal(t, int64(0), info.Size())
		}
	})

	t.Run("multiple writes keep file empty", func(t *testing.T) {
		tmp := t.TempDir()
		require.NoError(t, os.Chdir(tmp))
		defer func() { _ = os.Chdir(origWD) }()

		WriteLog("first")
		WriteLog("second")
		WriteLog("third")

		info, err := os.Stat("app.log")
		assert.NoError(t, err)
		if assert.NotNil(t, info) {
			assert.Equal(t, int64(0), info.Size())
		}
	})

	t.Run("read-only directory causes panic on open (unix only)", func(t *testing.T) {
		if runtime.GOOS == "windows" {
			t.Skip("permission semantics differ on Windows")
		}
		tmp := t.TempDir()
		roDir := filepath.Join(tmp, "ro")
		require.NoError(t, os.Mkdir(roDir, 0500))
		require.NoError(t, os.Chdir(roDir))
		defer func() {
			_ = os.Chmod(roDir, 0700)
			_ = os.Chdir(origWD)
		}()

		assert.Panics(t, func() { WriteLog("should panic due to open error") })
	})
}
