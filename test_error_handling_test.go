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
	tmp := t.TempDir()

	tests := []struct {
		name      string
		filename  string
		content   []byte
		create    bool
		expectNil bool
		expectLen int
		verify    func(t *testing.T, cfg map[string]interface{})
	}{
		{
			name:      "missing file returns nil",
			filename:  "missing.json",
			create:    false,
			expectNil: true,
		},
		{
			name:      "invalid JSON returns nil",
			filename:  "invalid.json",
			content:   []byte("not-json"),
			create:    true,
			expectNil: true,
		},
		{
			name:      "empty file returns nil",
			filename:  "empty.json",
			content:   []byte(""),
			create:    true,
			expectNil: true,
		},
		{
			name:      "json array invalid for map returns nil",
			filename:  "array.json",
			content:   []byte(`[1,2,3]`),
			create:    true,
			expectNil: true,
		},
		{
			name:      "empty object returns non-nil empty map",
			filename:  "emptyobj.json",
			content:   []byte(`{}`),
			create:    true,
			expectNil: false,
			expectLen: 0,
		},
		{
			name:      "valid object returns map with values",
			filename:  "valid.json",
			content:   []byte(`{"name":"app","port":8080}`),
			create:    true,
			expectNil: false,
			expectLen: 2,
			verify: func(t *testing.T, cfg map[string]interface{}) {
				// name should be "app"
				v, ok := cfg["name"]
				assert.True(t, ok, "expected key 'name' to exist")
				if assert.NotNil(t, v, "name value should not be nil") {
					assert.Equal(t, "app", v)
				}
				// port should be float64(8080) due to json.Unmarshal default types
				p, ok := cfg["port"]
				assert.True(t, ok, "expected key 'port' to exist")
				if assert.NotNil(t, p, "port value should not be nil") {
					assert.IsType(t, float64(0), p)
					assert.Equal(t, float64(8080), p)
				}
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(tmp, tt.filename)
			if tt.create {
				require.NoError(t, os.WriteFile(path, tt.content, 0o644))
			}

			cfg := ReadConfig(path)

			if tt.expectNil {
				assert.Nil(t, cfg)
				return
			}

			assert.NotNil(t, cfg)
			assert.Equal(t, tt.expectLen, len(cfg))
			if tt.verify != nil {
				tt.verify(t, cfg)
			}
		})
	}
}

func TestWriteLog(t *testing.T) {
	// Note: WriteLog always writes to "app.log" in the current working directory.
	// These tests change the CWD to a temp location and restore it after each case.

	t.Run("creates file but does not write content", func(t *testing.T) {
		tmp := t.TempDir()
		origWD, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(tmp))
		defer func() { _ = os.Chdir(origWD) }()

		assert.NotPanics(t, func() {
			WriteLog("hello world")
		})

		// File should exist
		_, err = os.Stat("app.log")
		assert.NoError(t, err)

		// Since the file is opened without write flags, write fails silently, content remains empty
		data, err := os.ReadFile("app.log")
		require.NoError(t, err)
		assert.Equal(t, 0, len(data))
	})

	t.Run("existing file content remains unchanged", func(t *testing.T) {
		tmp := t.TempDir()
		origWD, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(tmp))
		defer func() { _ = os.Chdir(origWD) }()

		initial := []byte("existing content")
		require.NoError(t, os.WriteFile("app.log", initial, 0o644))

		assert.NotPanics(t, func() {
			WriteLog("new content that should not be written")
		})

		data, err := os.ReadFile("app.log")
		require.NoError(t, err)
		assert.Equal(t, string(initial), string(data))
	})

	t.Run("panics when directory is not writable", func(t *testing.T) {
		if runtime.GOOS == "windows" {
			t.Skip("permission-based panic test skipped on Windows")
		}
		tmp := t.TempDir()
		roDir := filepath.Join(tmp, "ro")
		require.NoError(t, os.MkdirAll(roDir, 0o555))
		defer func() { _ = os.Chmod(roDir, 0o755) }()

		origWD, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(roDir))
		defer func() { _ = os.Chdir(origWD) }()

		assert.Panics(t, func() {
			WriteLog("should panic because cannot create app.log")
		})
	})
}

func TestProcessData(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		want       string
		wantPanic  bool
		panicValue interface{}
	}{
		{
			name:      "non-empty string returns same",
			input:     "hello",
			want:      "hello",
			wantPanic: false,
		},
		{
			name:      "whitespace string returns same",
			input:     " ",
			want:      " ",
			wantPanic: false,
		},
		{
			name:       "empty string panics",
			input:      "",
			wantPanic:  true,
			panicValue: "empty input",
		},
		{
			name:      "long string returns same",
			input:     "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
			want:      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
			wantPanic: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.PanicsWithValue(t, tt.panicValue, func() {
					_ = ProcessData(tt.input)
				})
				return
			}

			assert.NotPanics(t, func() {
				_ = ProcessData(tt.input)
			})
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}
