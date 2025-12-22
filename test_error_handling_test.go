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
	t.Run("missing file returns nil map", func(t *testing.T) {
		cfg := ReadConfig(filepath.Join(t.TempDir(), "does-not-exist.json"))
		assert.Nil(t, cfg)
	})

	t.Run("invalid JSON returns nil map", func(t *testing.T) {
		dir := t.TempDir()
		p := filepath.Join(dir, "bad.json")
		require.NoError(t, os.WriteFile(p, []byte("{ invalid json"), 0o644))

		cfg := ReadConfig(p)
		assert.Nil(t, cfg)
	})

	t.Run("empty file returns nil map", func(t *testing.T) {
		dir := t.TempDir()
		p := filepath.Join(dir, "empty.json")
		require.NoError(t, os.WriteFile(p, []byte(""), 0o644))

		cfg := ReadConfig(p)
		assert.Nil(t, cfg)
	})

	t.Run("valid JSON object returns populated map", func(t *testing.T) {
		dir := t.TempDir()
		p := filepath.Join(dir, "good.json")
		require.NoError(t, os.WriteFile(p, []byte(`{"a":1,"b":"x","c":true}`), 0o644))

		cfg := ReadConfig(p)
		if assert.NotNil(t, cfg) {
			assert.Contains(t, cfg, "a")
			assert.Contains(t, cfg, "b")
			assert.Contains(t, cfg, "c")

			// json.Unmarshal into interface{} uses float64 for numbers
			assert.Equal(t, float64(1), cfg["a"])
			assert.Equal(t, "x", cfg["b"])
			assert.Equal(t, true, cfg["c"])
		}
	})

	t.Run("JSON array into map returns nil map", func(t *testing.T) {
		dir := t.TempDir()
		p := filepath.Join(dir, "array.json")
		require.NoError(t, os.WriteFile(p, []byte(`[1,2,3]`), 0o644))

		cfg := ReadConfig(p)
		assert.Nil(t, cfg)
	})

	t.Run("permission denied returns nil map (unix only)", func(t *testing.T) {
		if runtime.GOOS == "windows" {
			t.Skip("permission bits not reliable on Windows")
		}
		dir := t.TempDir()
		p := filepath.Join(dir, "cfg.json")
		require.NoError(t, os.WriteFile(p, []byte(`{"k":"v"}`), 0o000))

		cfg := ReadConfig(p)
		assert.Nil(t, cfg)
	})
}

func TestWriteLog(t *testing.T) {
	t.Run("creates file in writable dir without panic", func(t *testing.T) {
		dir := t.TempDir()
		oldWD, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(dir))
		t.Cleanup(func() { _ = os.Chdir(oldWD) })

		assert.NotPanics(t, func() {
			WriteLog("hello world")
		})

		info, statErr := os.Stat("app.log")
		if assert.NoError(t, statErr) && assert.NotNil(t, info) {
			assert.False(t, info.IsDir())
			assert.Equal(t, int64(0), info.Size(), "file should exist but be empty due to read-only open flags")
		}
	})

	t.Run("repeated calls do not panic and file remains", func(t *testing.T) {
		dir := t.TempDir()
		oldWD, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(dir))
		t.Cleanup(func() { _ = os.Chdir(oldWD) })

		assert.NotPanics(t, func() { WriteLog("first") })
		assert.NotPanics(t, func() { WriteLog("second") })

		_, statErr := os.Stat("app.log")
		assert.NoError(t, statErr)
	})

	t.Run("existing read-only file does not panic and size unchanged (unix only)", func(t *testing.T) {
		if runtime.GOOS == "windows" {
			t.Skip("chmod semantics differ on Windows")
		}
		dir := t.TempDir()
		oldWD, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(dir))
		t.Cleanup(func() { _ = os.Chdir(oldWD) })

		// Seed file with content and make it read-only
		seed := []byte("existing-content")
		require.NoError(t, os.WriteFile("app.log", seed, 0o444))

		beforeInfo, err := os.Stat("app.log")
		require.NoError(t, err)
		beforeSize := beforeInfo.Size()

		assert.NotPanics(t, func() { WriteLog("new data that won't be written") })

		afterInfo, err := os.Stat("app.log")
		require.NoError(t, err)
		assert.Equal(t, beforeSize, afterInfo.Size(), "size should remain unchanged")
	})

	t.Run("non-writable dir causes panic due to nil file dereference (unix only)", func(t *testing.T) {
		if runtime.GOOS == "windows" {
			t.Skip("permission bits not reliable on Windows")
		}
		dir := t.TempDir()
		require.NoError(t, os.Chmod(dir, 0o555)) // read+exec only (no write)

		oldWD, err := os.Getwd()
		require.NoError(t, err)
		require.NoError(t, os.Chdir(dir))
		t.Cleanup(func() { _ = os.Chdir(oldWD) })

		assert.Panics(t, func() {
			WriteLog("should panic due to OpenFile failure and nil deref")
		})
	})
}

func TestProcessData(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}{
		{"empty input panics", "", "", true},
		{"simple non-empty", "abc", "abc", false},
		{"whitespace", "   ", "   ", false},
		{"unicode", "你好，世界", "你好，世界", false},
		{"long string", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", false},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() { _ = ProcessData(tt.input) })
				return
			}
			assert.NotPanics(t, func() {
				got := ProcessData(tt.input)
				assert.Equal(t, tt.want, got)
			})
		})
	}
}
