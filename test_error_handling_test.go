package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReadConfig_Table(t *testing.T) {
	tmp := t.TempDir()

	tests := []struct {
		name       string
		filename   string
		content    []byte
		create     bool
		expectNil  bool
		expectLen  *int
		expectKeys map[string]interface{}
	}{
		{
			name:      "missing file returns nil",
			filename:  "missing.json",
			create:    false,
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
			name:      "invalid JSON returns nil",
			filename:  "invalid.json",
			content:   []byte("{ not: json }"),
			create:    true,
			expectNil: true,
		},
		{
			name:      "json null returns nil",
			filename:  "null.json",
			content:   []byte("null"),
			create:    true,
			expectNil: true,
		},
		{
			name:      "empty object returns empty map",
			filename:  "empty_object.json",
			content:   []byte("{}"),
			create:    true,
			expectNil: false,
			expectLen: func() *int { i := 0; return &i }(),
		},
		{
			name:     "object with keys",
			filename: "keys.json",
			content:  []byte(`{"name":"app","version":1}`),
			create:   true,
			expectKeys: map[string]interface{}{
				"name":    "app",
				"version": float64(1),
			},
			expectNil: false,
			expectLen: func() *int { i := 2; return &i }(),
		},
		{
			name:      "whitespace and empty object",
			filename:  "ws.json",
			content:   []byte(" \n {} \n "),
			create:    true,
			expectNil: false,
			expectLen: func() *int { i := 0; return &i }(),
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(tmp, tt.filename)
			if tt.create {
				err := os.WriteFile(path, tt.content, 0o644)
				assert.NoError(t, err)
			}
			cfg := ReadConfig(path)
			if tt.expectNil {
				assert.Nil(t, cfg)
				return
			}
			assert.NotNil(t, cfg)
			if tt.expectLen != nil {
				assert.Equal(t, *tt.expectLen, len(cfg))
			}
			for k, v := range tt.expectKeys {
				_, ok := cfg[k]
				assert.True(t, ok, "expected key %q not found", k)
				assert.Equal(t, v, cfg[k])
			}
		})
	}
}

func TestWriteLog_Table(t *testing.T) {
	tests := []struct {
		name        string
		setup       func(t *testing.T)
		message     string
		expectPanic bool
		expectDir   bool
	}{
		{
			name:        "creates log file without panic",
			setup:       func(t *testing.T) {},
			message:     "hello",
			expectPanic: false,
			expectDir:   false,
		},
		{
			name: "app.log is a directory - panics",
			setup: func(t *testing.T) {
				err := os.Mkdir("app.log", 0o755)
				assert.NoError(t, err)
			},
			message:     "should panic",
			expectPanic: true,
			expectDir:   true,
		},
		{
			name: "pre-existing file remains without panic",
			setup: func(t *testing.T) {
				err := os.WriteFile("app.log", []byte("existing"), 0o644)
				assert.NoError(t, err)
			},
			message:     "world",
			expectPanic: false,
			expectDir:   false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			// Isolate CWD per subtest
			oldwd, err := os.Getwd()
			assert.NoError(t, err)
			t.Cleanup(func() { _ = os.Chdir(oldwd) })

			tmp := t.TempDir()
			err = os.Chdir(tmp)
			assert.NoError(t, err)

			tt.setup(t)

			if tt.expectPanic {
				assert.Panics(t, func() {
					WriteLog(tt.message)
				})
			} else {
				assert.NotPanics(t, func() {
					WriteLog(tt.message)
				})
			}

			info, statErr := os.Stat("app.log")
			if tt.expectPanic && tt.expectDir {
				assert.NoError(t, statErr)
				assert.True(t, info.IsDir())
				return
			}
			assert.NoError(t, statErr)
			assert.False(t, info.IsDir())
		})
	}
}

func TestProcessData_Table(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		expectPanic bool
		want        string
	}{
		{
			name:        "empty input panics",
			input:       "",
			expectPanic: true,
		},
		{
			name:        "simple string",
			input:       "hello",
			expectPanic: false,
			want:        "hello",
		},
		{
			name:        "single space",
			input:       " ",
			expectPanic: false,
			want:        " ",
		},
		{
			name:        "unicode string",
			input:       "こんにちは",
			expectPanic: false,
			want:        "こんにちは",
		},
		{
			name:        "long string",
			input:       "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			expectPanic: false,
			want:        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.expectPanic {
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
