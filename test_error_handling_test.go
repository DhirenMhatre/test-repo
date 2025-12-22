package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	tests := []struct {
		name     string
		content  string
		create   bool
		wantNil  bool
		validate func(t *testing.T, got map[string]interface{})
	}{
		{
			name:    "missing file returns nil map",
			create:  false,
			wantNil: true,
		},
		{
			name:    "empty file returns nil map",
			create:  true,
			content: "",
			wantNil: true,
		},
		{
			name:    "malformed JSON returns nil map",
			create:  true,
			content: "{bad json",
			wantNil: true,
		},
		{
			name:    "null JSON returns nil map",
			create:  true,
			content: "null",
			wantNil: true,
		},
		{
			name:    "valid JSON object returns non-nil map",
			create:  true,
			content: `{"ok":true,"num":1,"msg":"hi"}`,
			wantNil: false,
			validate: func(t *testing.T, got map[string]interface{}) {
				assert.NotNil(t, got)
				assert.GreaterOrEqual(t, len(got), 3)
				// Check types and values
				if v, ok := got["ok"]; assert.True(t, ok) {
					assert.Equal(t, true, v)
				}
				if v, ok := got["num"]; assert.True(t, ok) {
					// json numbers decode to float64
					assert.Equal(t, float64(1), v)
				}
				if v, ok := got["msg"]; assert.True(t, ok) {
					assert.Equal(t, "hi", v)
				}
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			var path string
			if tt.create {
				path = filepath.Join(dir, "config.json")
				require.NoError(t, os.WriteFile(path, []byte(tt.content), 0o644))
			} else {
				path = filepath.Join(dir, "missing.json")
			}

			got := ReadConfig(path)

			if tt.wantNil {
				assert.Nil(t, got)
			} else {
				assert.NotNil(t, got)
			}
			if tt.validate != nil {
				tt.validate(t, got)
			}
		})
	}
}

func TestWriteLog(t *testing.T) {
	tests := []struct {
		name          string
		setup         func(t *testing.T, dir string) string
		message       string
		wantPanic     bool
		validateAfter func(t *testing.T, dir string)
	}{
		{
			name: "creates app.log but writes nothing when no file exists",
			setup: func(t *testing.T, dir string) string {
				return dir
			},
			message:   "hello",
			wantPanic: false,
			validateAfter: func(t *testing.T, dir string) {
				info, err := os.Stat(filepath.Join(dir, "app.log"))
				require.NoError(t, err)
				assert.EqualValues(t, 0, info.Size())
			},
		},
		{
			name: "existing file remains unchanged",
			setup: func(t *testing.T, dir string) string {
				require.NoError(t, os.WriteFile(filepath.Join(dir, "app.log"), []byte("start"), 0o644))
				return dir
			},
			message:   " - new",
			wantPanic: false,
			validateAfter: func(t *testing.T, dir string) {
				b, err := os.ReadFile(filepath.Join(dir, "app.log"))
				require.NoError(t, err)
				assert.Equal(t, "start", string(b))
			},
		},
		{
			name: "existing empty file stays empty",
			setup: func(t *testing.T, dir string) string {
				require.NoError(t, os.WriteFile(filepath.Join(dir, "app.log"), []byte(""), 0o644))
				return dir
			},
			message:   "content",
			wantPanic: false,
			validateAfter: func(t *testing.T, dir string) {
				b, err := os.ReadFile(filepath.Join(dir, "app.log"))
				require.NoError(t, err)
				assert.Equal(t, "", string(b))
			},
		},
		{
			name: "app.log is a directory causing panic",
			setup: func(t *testing.T, dir string) string {
				require.NoError(t, os.Mkdir(filepath.Join(dir, "app.log"), 0o755))
				return dir
			},
			message:   "won't matter",
			wantPanic: true,
			validateAfter: func(t *testing.T, dir string) {
				// No additional validation needed; just ensure no file was created inside directory
				fi, err := os.Stat(filepath.Join(dir, "app.log"))
				require.NoError(t, err)
				assert.True(t, fi.IsDir())
			},
		},
		{
			name: "large message does not append content",
			setup: func(t *testing.T, dir string) string {
				require.NoError(t, os.WriteFile(filepath.Join(dir, "app.log"), []byte("base"), 0o644))
				return dir
			},
			message:   strings.Repeat("a", 10000),
			wantPanic: false,
			validateAfter: func(t *testing.T, dir string) {
				b, err := os.ReadFile(filepath.Join(dir, "app.log"))
				require.NoError(t, err)
				assert.Equal(t, "base", string(b))
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			// Isolate each test in its own working directory
			dir := t.TempDir()
			wd, err := os.Getwd()
			require.NoError(t, err)
			t.Cleanup(func() {
				_ = os.Chdir(wd)
			})
			// Prepare scenario
			_ = tt.setup(t, dir)
			require.NoError(t, os.Chdir(dir))

			if tt.wantPanic {
				assert.Panics(t, func() {
					WriteLog(tt.message)
				})
			} else {
				assert.NotPanics(t, func() {
					WriteLog(tt.message)
				})
			}

			if tt.validateAfter != nil {
				tt.validateAfter(t, dir)
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
			name:      "empty input panics",
			input:     "",
			wantPanic: true,
		},
		{
			name:      "simple string returns same",
			input:     "hello",
			want:      "hello",
			wantPanic: false,
		},
		{
			name:      "whitespace returns same",
			input:     "   ",
			want:      "   ",
			wantPanic: false,
		},
		{
			name:      "multiline string returns same",
			input:     "line1\nline2\n",
			want:      "line1\nline2\n",
			wantPanic: false,
		},
		{
			name:      "unicode string returns same",
			input:     "こんにちは世界",
			want:      "こんにちは世界",
			wantPanic: false,
		},
		{
			name:      "long string returns same",
			input:     strings.Repeat("x", 4096),
			want:      strings.Repeat("x", 4096),
			wantPanic: false,
		},
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
			assert.NotPanics(t, func() {
				got := ProcessData(tt.input)
				assert.Equal(t, tt.want, got)
			})
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}
