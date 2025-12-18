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
	t.Run("table", func(t *testing.T) {
		type testCase struct {
			name     string
			prepare  func(t *testing.T) string
			validate func(t *testing.T, got map[string]interface{})
		}

		tests := []testCase{
			{
				name: "non-existent file returns nil map",
				prepare: func(t *testing.T) string {
					return filepath.Join(t.TempDir(), "does-not-exist.json")
				},
				validate: func(t *testing.T, got map[string]interface{}) {
					assert.Nil(t, got)
				},
			},
			{
				name: "invalid json returns nil map",
				prepare: func(t *testing.T) string {
					dir := t.TempDir()
					p := filepath.Join(dir, "bad.json")
					writeFile(t, p, []byte("{ invalid json"))
					return p
				},
				validate: func(t *testing.T, got map[string]interface{}) {
					assert.Nil(t, got)
				},
			},
			{
				name: "valid json returns populated map",
				prepare: func(t *testing.T) string {
					dir := t.TempDir()
					p := filepath.Join(dir, "good.json")
					writeFile(t, p, []byte(`{"a":1,"b":"x"}`))
					return p
				},
				validate: func(t *testing.T, got map[string]interface{}) {
					require.NotNil(t, got)
					assert.Equal(t, "x", got["b"])
					// numbers decode as float64 into interface{}
					assert.Equal(t, float64(1), got["a"])
				},
			},
			{
				name: "empty object yields empty non-nil map",
				prepare: func(t *testing.T) string {
					dir := t.TempDir()
					p := filepath.Join(dir, "empty.json")
					writeFile(t, p, []byte(`{}`))
					return p
				},
				validate: func(t *testing.T, got map[string]interface{}) {
					require.NotNil(t, got)
					assert.Equal(t, 0, len(got))
				},
			},
			{
				name: "nested json unmarshals as nested maps",
				prepare: func(t *testing.T) string {
					dir := t.TempDir()
					p := filepath.Join(dir, "nested.json")
					writeFile(t, p, []byte(`{"nested":{"y":2,"z":"ok"}}`))
					return p
				},
				validate: func(t *testing.T, got map[string]interface{}) {
					require.NotNil(t, got)
					nestedRaw, ok := got["nested"]
					require.True(t, ok)
					require.NotNil(t, nestedRaw)
					nested, ok := nestedRaw.(map[string]interface{})
					require.True(t, ok)
					require.NotNil(t, nested)
					assert.Equal(t, float64(2), nested["y"])
					assert.Equal(t, "ok", nested["z"])
				},
			},
		}

		for _, tt := range tests {
			tt := tt
			t.Run(tt.name, func(t *testing.T) {
				p := tt.prepare(t)
				got := ReadConfig(p)
				tt.validate(t, got)
			})
		}
	})

	t.Run("permission denied returns nil map (unix only)", func(t *testing.T) {
		if runtime.GOOS == "windows" {
			t.Skip("chmod semantics differ on Windows")
		}
		dir := t.TempDir()
		p := filepath.Join(dir, "cfg.json")
		writeFile(t, p, []byte(`{"ok":true}`))
		require.NoError(t, os.Chmod(p, 0o000))
		t.Cleanup(func() { _ = os.Chmod(p, 0o600) })

		got := ReadConfig(p)
		assert.Nil(t, got)
	})
}

func TestWriteLog(t *testing.T) {
	type testCase struct {
		name     string
		messages []string
		want     string
	}

	tests := []testCase{
		{
			name:     "single write creates file with content",
			messages: []string{"hello"},
			want:     "hello",
		},
		{
			name:     "multiple writes append content",
			messages: []string{"a", "b", "c"},
			want:     "abc",
		},
		{
			name:     "empty write creates empty file",
			messages: []string{""},
			want:     "",
		},
		{
			name:     "mix of empty and non-empty writes",
			messages: []string{"first", "", "third"},
			want:     "firstthird",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			// isolate cwd in a temp dir since WriteLog uses hardcoded "app.log"
			origCwd, err := os.Getwd()
			require.NoError(t, err)
			tmp := t.TempDir()
			require.NoError(t, os.Chdir(tmp))
			defer func() { _ = os.Chdir(origCwd) }()

			for _, m := range tt.messages {
				WriteLog(m)
			}

			data, err := os.ReadFile("app.log")
			require.NoError(t, err)
			assert.Equal(t, tt.want, string(data))
		})
	}
}

func TestProcessData(t *testing.T) {
	type testCase struct {
		name   string
		input  string
		want   string
		panics bool
		panVal string
	}

	tests := []testCase{
		{
			name:   "returns input unchanged",
			input:  "hello",
			want:   "hello",
			panics: false,
		},
		{
			name:   "whitespace is valid input",
			input:  " ",
			want:   " ",
			panics: false,
		},
		{
			name:   "numeric string",
			input:  "123",
			want:   "123",
			panics: false,
		},
		{
			name:   "emoji string",
			input:  "emoji 😀",
			want:   "emoji 😀",
			panics: false,
		},
		{
			name:   "empty input panics",
			input:  "",
			panics: true,
			panVal: "empty input",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.panics {
				assert.PanicsWithValue(t, tt.panVal, func() {
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

func writeFile(t *testing.T, path string, data []byte) {
	t.Helper()
	dir := filepath.Dir(path)
	require.NoError(t, os.MkdirAll(dir, 0o755))
	require.NoError(t, os.WriteFile(path, data, 0o600))
}
