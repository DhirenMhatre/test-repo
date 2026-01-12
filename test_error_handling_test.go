package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReadConfig_TableDriven(t *testing.T) {
	tmpDir := t.TempDir()

	validConfig := map[string]interface{}{
		"key": "value",
		"num": float64(42),
	}
	validBytes, err := json.Marshal(validConfig)
	assert.NoError(t, err)

	validPath := filepath.Join(tmpDir, "valid.json")
	err = os.WriteFile(validPath, validBytes, 0o644)
	assert.NoError(t, err)

	invalidPath := filepath.Join(tmpDir, "invalid.json")
	err = os.WriteFile(invalidPath, []byte("{invalid json"), 0o644)
	assert.NoError(t, err)

	emptyPath := filepath.Join(tmpDir, "empty.json")
	err = os.WriteFile(emptyPath, []byte(""), 0o644)
	assert.NoError(t, err)

	tests := []struct {
		name       string
		path       string
		wantNonNil bool
	}{
		{
			name:       "valid json file returns populated map",
			path:       validPath,
			wantNonNil: true,
		},
		{
			name:       "invalid json returns nil map",
			path:       invalidPath,
			wantNonNil: false,
		},
		{
			name:       "empty file returns nil map",
			path:       emptyPath,
			wantNonNil: false,
		},
		{
			name:       "nonexistent file returns nil map",
			path:       filepath.Join(tmpDir, "does_not_exist.json"),
			wantNonNil: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			cfg := ReadConfig(tt.path)
			if tt.wantNonNil {
				assert.NotNil(t, cfg)
				if cfg == nil {
					return
				}
				assert.Equal(t, "value", cfg["key"])
				assert.Equal(t, float64(42), cfg["num"])
			} else {
				assert.Nil(t, cfg)
			}
		})
	}
}

func TestReadConfig_MultipleCallsSameFile(t *testing.T) {
	tmpDir := t.TempDir()

	content := map[string]interface{}{
		"a": "b",
	}
	data, err := json.Marshal(content)
	assert.NoError(t, err)

	path := filepath.Join(tmpDir, "config.json")
	err = os.WriteFile(path, data, 0o644)
	assert.NoError(t, err)

	tests := []struct {
		name string
	}{
		{name: "first call"},
		{name: "second call"},
		{name: "third call"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			cfg := ReadConfig(path)
			assert.NotNil(t, cfg)
			if cfg == nil {
				return
			}
			assert.Equal(t, "b", cfg["a"])
		})
	}
}

func TestWriteLog_TableDriven(t *testing.T) {
	// Note: WriteLog always writes to "app.log" in current directory.
	// Use a temporary working directory to isolate the file.
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	tmpDir := t.TempDir()
	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	tests := []struct {
		name     string
		messages []string
	}{
		{
			name:     "single short message",
			messages: []string{"hello"},
		},
		{
			name:     "multiple messages",
			messages: []string{"first line\n", "second line\n", "third line"},
		},
		{
			name:     "empty and non-empty messages",
			messages: []string{"", "non-empty", ""},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			for _, msg := range tt.messages {
				WriteLog(msg)
			}

			data, err := os.ReadFile("app.log")
			assert.NoError(t, err)

			combined := ""
			for _, msg := range tt.messages {
				combined += msg
			}
			assert.Equal(t, combined, string(data))
		})
	}
}

func TestWriteLog_AppendBehavior(t *testing.T) {
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	tmpDir := t.TempDir()
	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	tests := []struct {
		name          string
		firstMessage  string
		secondMessage string
	}{
		{
			name:          "append two messages",
			firstMessage:  "first",
			secondMessage: "second",
		},
		{
			name:          "append with newline",
			firstMessage:  "line1\n",
			secondMessage: "line2\n",
		},
		{
			name:          "append empty then text",
			firstMessage:  "",
			secondMessage: "text",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			_ = os.Remove("app.log")

			WriteLog(tt.firstMessage)
			WriteLog(tt.secondMessage)

			data, err := os.ReadFile("app.log")
			assert.NoError(t, err)
			assert.Equal(t, tt.firstMessage+tt.secondMessage, string(data))
		})
	}
}

func TestProcessData_TableDriven(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		want       string
		wantPanic  bool
		panicValue interface{}
	}{
		{
			name:      "non-empty string returns same string",
			input:     "hello",
			want:      "hello",
			wantPanic: false,
		},
		{
			name:      "whitespace string does not panic",
			input:     "   ",
			want:      "   ",
			wantPanic: false,
		},
		{
			name:       "empty string panics",
			input:      "",
			wantPanic:  true,
			panicValue: "empty input",
		},
		{
			name:       "another empty string case panics",
			input:      "",
			wantPanic:  true,
			panicValue: "empty input",
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
				got := ProcessData(tt.input)
				assert.Equal(t, tt.want, got)
			})
		})
	}
}

func TestProcessData_MultipleNonEmptyInputs(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{name: "simple word", input: "data"},
		{name: "numeric string", input: "12345"},
		{name: "mixed characters", input: "a1!@#"},
		{name: "unicode", input: "こんにちは"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.NotPanics(t, func() {
				got := ProcessData(tt.input)
				assert.Equal(t, tt.input, got)
			})
		})
	}
}
