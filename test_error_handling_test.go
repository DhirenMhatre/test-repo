package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReadConfig(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name         string
		setup        func(t *testing.T) string
		assertConfig func(t *testing.T, cfg map[string]interface{})
	}{
		{
			name: "missing file returns nil map (errors ignored)",
			setup: func(t *testing.T) string {
				t.Helper()
				return filepath.Join(t.TempDir(), "does-not-exist.json")
			},
			assertConfig: func(t *testing.T, cfg map[string]interface{}) {
				t.Helper()
				assert.Nil(t, cfg)
			},
		},
		{
			name: "invalid json returns nil map (errors ignored)",
			setup: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				p := filepath.Join(dir, "bad.json")
				err := os.WriteFile(p, []byte("{not-json"), 0600)
				assert.NoError(t, err)
				return p
			},
			assertConfig: func(t *testing.T, cfg map[string]interface{}) {
				t.Helper()
				assert.Nil(t, cfg)
			},
		},
		{
			name: "valid json returns parsed map",
			setup: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				p := filepath.Join(dir, "good.json")
				err := os.WriteFile(p, []byte(`{"a":1,"b":"x","c":true}`), 0600)
				assert.NoError(t, err)
				return p
			},
			assertConfig: func(t *testing.T, cfg map[string]interface{}) {
				t.Helper()
				if assert.NotNil(t, cfg) {
					assert.Equal(t, float64(1), cfg["a"])
					assert.Equal(t, "x", cfg["b"])
					assert.Equal(t, true, cfg["c"])
				}
			},
		},
		{
			name: "valid json empty object returns non-nil empty map",
			setup: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				p := filepath.Join(dir, "empty.json")
				err := os.WriteFile(p, []byte(`{}`), 0600)
				assert.NoError(t, err)
				return p
			},
			assertConfig: func(t *testing.T, cfg map[string]interface{}) {
				t.Helper()
				if assert.NotNil(t, cfg) {
					assert.Len(t, cfg, 0)
				}
			},
		},
		{
			name: "valid json array is ignored by map unmarshal resulting nil map",
			setup: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				p := filepath.Join(dir, "array.json")
				err := os.WriteFile(p, []byte(`[1,2,3]`), 0600)
				assert.NoError(t, err)
				return p
			},
			assertConfig: func(t *testing.T, cfg map[string]interface{}) {
				t.Helper()
				assert.Nil(t, cfg)
			},
		},
		{
			name: "valid json nested object parses into nested map",
			setup: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				p := filepath.Join(dir, "nested.json")
				err := os.WriteFile(p, []byte(`{"nested":{"k":"v"},"n":2}`), 0600)
				assert.NoError(t, err)
				return p
			},
			assertConfig: func(t *testing.T, cfg map[string]interface{}) {
				t.Helper()
				if assert.NotNil(t, cfg) {
					assert.Equal(t, float64(2), cfg["n"])
					nested, ok := cfg["nested"].(map[string]interface{})
					if assert.True(t, ok) {
						assert.Equal(t, "v", nested["k"])
					}
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := tt.setup(t)
			cfg := ReadConfig(p)
			tt.assertConfig(t, cfg)
		})
	}
}

func TestWriteLog(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name         string
		messageParts []string
	}{
		{
			name:         "writes a simple message",
			messageParts: []string{"hello\n"},
		},
		{
			name:         "writes multiple messages sequentially",
			messageParts: []string{"first\n", "second\n", "third\n"},
		},
		{
			name:         "writes empty message without panicking",
			messageParts: []string{""},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			origWD, err := os.Getwd()
			assert.NoError(t, err)
			tmp := t.TempDir()
			err = os.Chdir(tmp)
			assert.NoError(t, err)
			t.Cleanup(func() {
				_ = os.Chdir(origWD)
			})

			for _, msg := range tt.messageParts {
				assert.NotPanics(t, func() {
					WriteLog(msg)
				})
			}

			data, err := os.ReadFile(filepath.Join(tmp, "app.log"))
			assert.NoError(t, err)

			content := string(data)
			for _, msg := range tt.messageParts {
				assert.Contains(t, content, msg)
			}
		})
	}
}

func TestWriteLog_Appends(t *testing.T) {
	t.Parallel()

	origWD, err := os.Getwd()
	assert.NoError(t, err)
	tmp := t.TempDir()
	err = os.Chdir(tmp)
	assert.NoError(t, err)
	t.Cleanup(func() {
		_ = os.Chdir(origWD)
	})

	WriteLog("a\n")
	WriteLog("b\n")

	data, err := os.ReadFile(filepath.Join(tmp, "app.log"))
	assert.NoError(t, err)
	assert.True(t, strings.Contains(string(data), "a\n"))
	assert.True(t, strings.Contains(string(data), "b\n"))
}

func TestProcessData(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}{
		{
			name:      "non-empty returns input",
			input:     "abc",
			want:      "abc",
			wantPanic: false,
		},
		{
			name:      "spaces-only is non-empty and returns as-is",
			input:     "   ",
			want:      "   ",
			wantPanic: false,
		},
		{
			name:      "unicode input returns as-is",
			input:     "こんにちは",
			want:      "こんにちは",
			wantPanic: false,
		},
		{
			name:      "empty string panics",
			input:     "",
			want:      "",
			wantPanic: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() {
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

func TestProcessData_PanicMessage(t *testing.T) {
	t.Parallel()

	assert.PanicsWithValue(t, "empty input", func() {
		_ = ProcessData("")
	})
}

func TestProcessData_IdempotentForValidInput(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		input string
	}{
		{"simple", "x"},
		{"with newline", "line1\nline2"},
		{"with null byte", "a\x00b"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			out1 := ProcessData(tt.input)
			out2 := ProcessData(out1)
			assert.Equal(t, tt.input, out1)
			assert.Equal(t, tt.input, out2)
		})
	}
}
