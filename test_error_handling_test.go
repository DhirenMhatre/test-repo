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
	t.Run("table-driven", func(t *testing.T) {
		dir := t.TempDir()
		tests := []struct {
			name       string
			filename   string
			writeFile  bool
			contents   string
			expectNil  bool
			expectData map[string]interface{}
		}{
			{
				name:      "missing file returns nil",
				filename:  "missing.json",
				writeFile: false,
				expectNil: true,
			},
			{
				name:      "empty file returns nil",
				filename:  "empty.json",
				writeFile: true,
				contents:  "",
				expectNil: true,
			},
			{
				name:      "invalid JSON returns nil",
				filename:  "invalid.json",
				writeFile: true,
				contents:  "{bad",
				expectNil: true,
			},
			{
				name:      "JSON array returns nil due to type mismatch",
				filename:  "array.json",
				writeFile: true,
				contents:  `["a", 1, true]`,
				expectNil: true,
			},
			{
				name:      "valid JSON object returns map",
				filename:  "valid.json",
				writeFile: true,
				contents:  `{"k":"v","n":1}`,
				expectNil: false,
				expectData: map[string]interface{}{
					"k": "v",
					"n": float64(1),
				},
			},
			{
				name:      "nested object returns map",
				filename:  "nested.json",
				writeFile: true,
				contents:  `{"a":{"b":2}}`,
				expectNil: false,
				expectData: map[string]interface{}{
					"a": map[string]interface{}{"b": float64(2)},
				},
			},
		}

		for _, tt := range tests {
			tt := tt
			t.Run(tt.name, func(t *testing.T) {
				fp := filepath.Join(dir, tt.filename)
				if tt.writeFile {
					require.NoError(t, os.WriteFile(fp, []byte(tt.contents), 0o644))
				}
				var got map[string]interface{}
				if tt.writeFile {
					got = ReadConfig(fp)
				} else {
					got = ReadConfig(fp) // file does not exist
				}

				if tt.expectNil {
					assert.Nil(t, got)
					return
				}

				assert.NotNil(t, got)
				assert.Equal(t, tt.expectData, got)
			})
		}
	})
}

func TestProcessData(t *testing.T) {
	tests := []struct {
		name      string
		in        string
		want      string
		wantPanic bool
	}{
		{
			name:      "empty input panics with specific message",
			in:        "",
			wantPanic: true,
		},
		{
			name: "single space returns same",
			in:   " ",
			want: " ",
		},
		{
			name: "simple string returns same",
			in:   "hello",
			want: "hello",
		},
		{
			name: "unicode string returns same",
			in:   "你好，世界",
			want: "你好，世界",
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
			if tt.wantPanic {
				assert.PanicsWithValue(t, "empty input", func() {
					_ = ProcessData(tt.in)
				})
				return
			}
			got := ProcessData(tt.in)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestWriteLog_FileBehavior(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Skipping WriteLog tests on Windows due to open handle and removal semantics")
	}

	t.Run("creates file but does not write content", func(t *testing.T) {
		dir := t.TempDir()
		origWD, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(dir))
		defer os.Chdir(origWD)

		_, err = os.Stat("app.log")
		assert.True(t, os.IsNotExist(err))

		WriteLog("hello world") // ignored write error, but file likely created

		fi, err := os.Stat("app.log")
		require.NoError(t, err)
		assert.Equal(t, int64(0), fi.Size(), "expected zero size because file opened read-only and write failed")
	})

	t.Run("does not append to existing file", func(t *testing.T) {
		dir := t.TempDir()
		origWD, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(dir))
		defer os.Chdir(origWD)

		initial := []byte("abc")
		require.NoError(t, os.WriteFile("app.log", initial, 0o644))
		before, err := os.Stat("app.log")
		require.NoError(t, err)
		beforeSize := before.Size()

		WriteLog("more data that should not be written")

		after, err := os.Stat("app.log")
		require.NoError(t, err)
		assert.Equal(t, beforeSize, after.Size(), "size should remain unchanged")
	})

	t.Run("unwritable directory - file not created", func(t *testing.T) {
		dir := t.TempDir()
		// Remove write permission
		require.NoError(t, os.Chmod(dir, 0o555))
		// Restore permission after test so TempDir can be cleaned up
		defer os.Chmod(dir, 0o755)

		origWD, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(dir))
		defer os.Chdir(origWD)

		WriteLog("should fail silently and not create app.log")

		_, err = os.Stat("app.log")
		assert.True(t, os.IsNotExist(err), "app.log should not exist in an unwritable directory")
	})
}
