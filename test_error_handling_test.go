package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReadConfig_Table(t *testing.T) {
	dir := t.TempDir()

	tests := []struct {
		name     string
		setup    func(t *testing.T) string
		wantNil  bool
		validate func(t *testing.T, got map[string]interface{})
	}{
		{
			name: "missing file returns nil",
			setup: func(t *testing.T) string {
				return filepath.Join(dir, "does-not-exist.json")
			},
			wantNil: true,
		},
		{
			name: "empty file returns nil",
			setup: func(t *testing.T) string {
				p := filepath.Join(dir, "empty.json")
				err := os.WriteFile(p, []byte(""), 0o644)
				assert.NoError(t, err)
				return p
			},
			wantNil: true,
		},
		{
			name: "invalid JSON returns nil",
			setup: func(t *testing.T) string {
				p := filepath.Join(dir, "invalid.json")
				err := os.WriteFile(p, []byte("not json"), 0o644)
				assert.NoError(t, err)
				return p
			},
			wantNil: true,
		},
		{
			name: "valid JSON object returns populated map",
			setup: func(t *testing.T) string {
				p := filepath.Join(dir, "valid.json")
				err := os.WriteFile(p, []byte(`{"a":1,"b":"x"}`), 0o644)
				assert.NoError(t, err)
				return p
			},
			wantNil: false,
			validate: func(t *testing.T, got map[string]interface{}) {
				if assert.NotNil(t, got) {
					assert.Equal(t, float64(1), got["a"])
					assert.Equal(t, "x", got["b"])
				}
			},
		},
		{
			name: "valid empty object returns non-nil empty map",
			setup: func(t *testing.T) string {
				p := filepath.Join(dir, "empty_obj.json")
				err := os.WriteFile(p, []byte(`{}`), 0o644)
				assert.NoError(t, err)
				return p
			},
			wantNil: false,
			validate: func(t *testing.T, got map[string]interface{}) {
				if assert.NotNil(t, got) {
					assert.Equal(t, 0, len(got))
				}
			},
		},
		{
			name: "array JSON returns nil because unmarshal into map fails",
			setup: func(t *testing.T) string {
				p := filepath.Join(dir, "array.json")
				err := os.WriteFile(p, []byte(`["a",1]`), 0o644)
				assert.NoError(t, err)
				return p
			},
			wantNil: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			path := tt.setup(t)
			got := ReadConfig(path)
			if tt.wantNil {
				assert.Nil(t, got)
				return
			}
			assert.NotNil(t, got)
			if tt.validate != nil {
				tt.validate(t, got)
			}
		})
	}
}

func TestWriteLog_Table(t *testing.T) {
	origWD, err := os.Getwd()
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	dir := t.TempDir()
	err = os.Chdir(dir)
	assert.NoError(t, err)

	tests := []struct {
		name         string
		preSetup     func(t *testing.T)
		message      string
		expectDir    bool
		expectExists bool
	}{
		{
			name: "creates file when absent",
			preSetup: func(t *testing.T) {
				_, err := os.Stat("app.log")
				assert.True(t, os.IsNotExist(err))
			},
			message:      "hello world",
			expectDir:    false,
			expectExists: true,
		},
		{
			name: "app.log pre-exists as file",
			preSetup: func(t *testing.T) {
				err := os.WriteFile("app.log", []byte("seed"), 0o644)
				assert.NoError(t, err)
				info, err := os.Stat("app.log")
				assert.NoError(t, err)
				assert.False(t, info.IsDir())
			},
			message:      "another line",
			expectDir:    false,
			expectExists: true,
		},
		{
			name: "app.log is a directory remains directory",
			preSetup: func(t *testing.T) {
				err := os.Mkdir("app.log", 0o755)
				assert.NoError(t, err)
				info, err := os.Stat("app.log")
				assert.NoError(t, err)
				assert.True(t, info.IsDir())
			},
			message:      "should not convert directory",
			expectDir:    true,
			expectExists: true,
		},
		{
			name: "empty message still creates file",
			preSetup: func(t *testing.T) {
				_ = os.Remove("app.log")
			},
			message:      "",
			expectDir:    false,
			expectExists: true,
		},
		{
			name: "unicode message does not panic",
			preSetup: func(t *testing.T) {
				_ = os.Remove("app.log")
			},
			message:      "こんにちは世界 🌏",
			expectDir:    false,
			expectExists: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.preSetup != nil {
				tt.preSetup(t)
			}
			WriteLog(tt.message)

			info, err := os.Stat("app.log")
			if tt.expectExists {
				assert.NoError(t, err)
				if assert.NotNil(t, info) {
					assert.Equal(t, tt.expectDir, info.IsDir())
				}
			} else {
				assert.True(t, os.IsNotExist(err))
			}
		})
	}
}

func TestProcessData_ReturnsInput_Table(t *testing.T) {
	long := strings.Repeat("abc", 100)
	tests := []struct {
		name  string
		input string
	}{
		{"simple", "hello"},
		{"space only not empty", " "},
		{"unicode", "你好，世界"},
		{"with newline", "line1\nline2"},
		{"long string", long},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			got := ProcessData(tt.input)
			assert.Equal(t, tt.input, got)
		})
	}
}

func TestProcessData_PanicsOnEmpty(t *testing.T) {
	assert.PanicsWithValue(t, "empty input", func() {
		_ = ProcessData("")
	})
}
