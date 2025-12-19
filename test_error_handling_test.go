package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func withTempWD(t *testing.T) string {
	t.Helper()
	oldWD, err := os.Getwd()
	require.NoError(t, err)
	dir := t.TempDir()
	require.NoError(t, os.Chdir(dir))
	t.Cleanup(func() {
		_ = os.Chdir(oldWD)
	})
	return dir
}

func TestReadConfig_Table(t *testing.T) {
	t.Run("table-driven", func(t *testing.T) {
		dir := t.TempDir()

		tests := []struct {
			name     string
			setup    func() string
			wantNil  bool
			wantKeys map[string]interface{}
		}{
			{
				name: "missing file returns nil map",
				setup: func() string {
					return filepath.Join(dir, "does_not_exist.json")
				},
				wantNil: true,
			},
			{
				name: "empty file returns nil map",
				setup: func() string {
					p := filepath.Join(dir, "empty.json")
					require.NoError(t, os.WriteFile(p, []byte(""), 0o644))
					return p
				},
				wantNil: true,
			},
			{
				name: "invalid JSON returns nil map",
				setup: func() string {
					p := filepath.Join(dir, "invalid.json")
					require.NoError(t, os.WriteFile(p, []byte("{not-json"), 0o644))
					return p
				},
				wantNil: true,
			},
			{
				name: "valid JSON returns populated map",
				setup: func() string {
					p := filepath.Join(dir, "valid.json")
					require.NoError(t, os.WriteFile(p, []byte(`{"name":"app","port":8080}`), 0o644))
					return p
				},
				wantNil:  false,
				wantKeys: map[string]interface{}{"name": "app", "port": float64(8080)},
			},
			{
				name: "empty object returns empty non-nil map",
				setup: func() string {
					p := filepath.Join(dir, "empty_obj.json")
					require.NoError(t, os.WriteFile(p, []byte(`{}`), 0o644))
					return p
				},
				wantNil:  false,
				wantKeys: map[string]interface{}{},
			},
		}

		for _, tt := range tests {
			tt := tt
			t.Run(tt.name, func(t *testing.T) {
				p := tt.setup()
				got := ReadConfig(p)
				if tt.wantNil {
					assert.Nil(t, got)
					return
				}
				assert.NotNil(t, got)
				for k, v := range tt.wantKeys {
					val, ok := got[k]
					assert.True(t, ok, "expected key %q to exist", k)
					assert.Equal(t, v, val, "value mismatch for key %q", k)
				}
			})
		}
	})
}

func TestReadConfig_ArrayInput_ReturnsNil(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "array.json")
	require.NoError(t, os.WriteFile(p, []byte(`["not","an","object"]`), 0o644))

	got := ReadConfig(p)
	assert.Nil(t, got)
}

func TestReadConfig_NestedJSON_Types(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "nested.json")
	json := `{"enabled":true,"port":8080,"nested":{"k":"v"}}`
	require.NoError(t, os.WriteFile(p, []byte(json), 0o644))

	cfg := ReadConfig(p)
	assert.NotNil(t, cfg)

	enabled, ok := cfg["enabled"].(bool)
	assert.True(t, ok)
	assert.True(t, enabled)

	port, ok := cfg["port"].(float64)
	assert.True(t, ok)
	assert.Equal(t, float64(8080), port)

	nested, ok := cfg["nested"].(map[string]interface{})
	assert.True(t, ok)
	assert.NotNil(t, nested)
	val, ok := nested["k"].(string)
	assert.True(t, ok)
	assert.Equal(t, "v", val)
}

func TestWriteLog_Table(t *testing.T) {
	tests := []struct {
		name         string
		prep         func(base string)
		wantContents string
	}{
		{
			name: "fresh directory - creates file but writes nothing",
			prep: func(base string) {
				// nothing
			},
			wantContents: "",
		},
		{
			name: "pre-existing file preserved",
			prep: func(base string) {
				require.NoError(t, os.WriteFile(filepath.Join(base, "app.log"), []byte("seed"), 0o644))
			},
			wantContents: "seed",
		},
		{
			name: "read-only file preserved",
			prep: func(base string) {
				p := filepath.Join(base, "app.log")
				require.NoError(t, os.WriteFile(p, []byte("seed"), 0o444))
				_ = os.Chmod(p, 0o444) // ensure read-only where supported
			},
			wantContents: "seed",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			dir := withTempWD(t)
			tt.prep(dir)

			assert.NotPanics(t, func() {
				WriteLog("hello world")
			})

			data, err := os.ReadFile("app.log")
			if tt.wantContents == "" {
				// In a fresh directory, the file should exist and be empty (created by O_CREATE but write fails).
				assert.NoError(t, err)
				assert.Equal(t, 0, len(data))
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.wantContents, string(data))
		})
	}
}

func TestWriteLog_MultipleCalls_StillNoContent(t *testing.T) {
	_ = withTempWD(t)

	WriteLog("first")
	WriteLog("second")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Equal(t, 0, len(data))
}

func TestWriteLog_DoesNotPanic(t *testing.T) {
	assert.NotPanics(t, func() {
		WriteLog("any message")
	})
}

func TestWriteLog_PreservesExistingContent(t *testing.T) {
	dir := withTempWD(t)
	p := filepath.Join(dir, "app.log")
	require.NoError(t, os.WriteFile(p, []byte("original"), 0o644))

	WriteLog("should not be appended")

	content, err := os.ReadFile(p)
	assert.NoError(t, err)
	assert.Equal(t, "original", string(content))
}

func TestProcessData_Table(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}{
		{"empty input panics", "", "", true},
		{"non-empty same output", "hello", "hello", false},
		{"whitespace preserved", "   ", "   ", false},
		{"long string preserved", "abcdefghijklmnopqrstuvwxyz", "abcdefghijklmnopqrstuvwxyz", false},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			var got string
			assert.NotPanics(t, func() {
				got = ProcessData(tt.input)
			})
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestProcessData_EmptyPanics(t *testing.T) {
	assert.Panics(t, func() {
		_ = ProcessData("")
	})
}

func TestProcessData_NoMutation(t *testing.T) {
	in := "unchanged"
	out := ProcessData(in)
	assert.Equal(t, in, out)
}
