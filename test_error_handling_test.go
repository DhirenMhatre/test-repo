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

	validConfigPath := filepath.Join(tmpDir, "valid.json")
	validContent := `{"key":"value","number":42}`
	err := os.WriteFile(validConfigPath, []byte(validContent), 0o644)
	assert.NoError(t, err)

	invalidJSONPath := filepath.Join(tmpDir, "invalid.json")
	invalidContent := `{"key":`
	err = os.WriteFile(invalidJSONPath, []byte(invalidContent), 0o644)
	assert.NoError(t, err)

	emptyFilePath := filepath.Join(tmpDir, "empty.json")
	err = os.WriteFile(emptyFilePath, []byte(""), 0o644)
	assert.NoError(t, err)

	tests := []struct {
		name       string
		path       string
		wantNonNil bool
	}{
		{
			name:       "valid JSON file returns non-nil map",
			path:       validConfigPath,
			wantNonNil: true,
		},
		{
			name:       "invalid JSON still returns map due to ignored error",
			path:       invalidJSONPath,
			wantNonNil: true,
		},
		{
			name:       "empty file returns map due to ignored error",
			path:       emptyFilePath,
			wantNonNil: true,
		},
		{
			name:       "non-existent file returns nil map due to nil slice to Unmarshal",
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
			} else {
				assert.Nil(t, cfg)
			}
		})
	}
}

func TestReadConfig_ContentBehavior(t *testing.T) {
	tmpDir := t.TempDir()

	type nested struct {
		Inner string `json:"inner"`
	}
	type sample struct {
		Name   string `json:"name"`
		Active bool   `json:"active"`
		Nested nested `json:"nested"`
	}

	s := sample{
		Name:   "test",
		Active: true,
		Nested: nested{Inner: "value"},
	}
	b, err := json.Marshal(s)
	assert.NoError(t, err)

	path := filepath.Join(tmpDir, "config.json")
	err = os.WriteFile(path, b, 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)

	nameVal, ok := cfg["name"]
	assert.True(t, ok)
	assert.Equal(t, "test", nameVal)

	activeVal, ok := cfg["active"]
	assert.True(t, ok)
	assert.Equal(t, true, activeVal)

	nestedVal, ok := cfg["nested"]
	assert.True(t, ok)
	assert.NotNil(t, nestedVal)
}

func TestReadConfig_RepeatedCalls(t *testing.T) {
	tmpDir := t.TempDir()

	path := filepath.Join(tmpDir, "config.json")
	content := `{"count":1}`
	err := os.WriteFile(path, []byte(content), 0o644)
	assert.NoError(t, err)

	cfg1 := ReadConfig(path)
	cfg2 := ReadConfig(path)

	assert.NotNil(t, cfg1)
	assert.NotNil(t, cfg2)
	assert.Equal(t, cfg1["count"], cfg2["count"])
}

func TestWriteLog_TableDriven(t *testing.T) {
	tmpDir := t.TempDir()
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	tests := []struct {
		name    string
		message string
	}{
		{
			name:    "write simple message",
			message: "hello world\n",
		},
		{
			name:    "write empty message",
			message: "",
		},
		{
			name:    "write multi-line message",
			message: "line1\nline2\n",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			WriteLog(tt.message)

			data, err := os.ReadFile("app.log")
			assert.NoError(t, err)
			assert.Contains(t, string(data), tt.message)
		})
	}
}

func TestWriteLog_AppendsToExistingFile(t *testing.T) {
	tmpDir := t.TempDir()
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	initialContent := "initial\n"
	err = os.WriteFile("app.log", []byte(initialContent), 0o644)
	assert.NoError(t, err)

	WriteLog("first\n")
	WriteLog("second\n")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	content := string(data)

	assert.Contains(t, content, "initial\n")
	assert.Contains(t, content, "first\n")
	assert.Contains(t, content, "second\n")
}

func TestWriteLog_CreatesFileIfNotExists(t *testing.T) {
	tmpDir := t.TempDir()
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	_, err = os.Stat("app.log")
	assert.True(t, os.IsNotExist(err))

	WriteLog("created\n")

	info, err := os.Stat("app.log")
	assert.NoError(t, err)
	assert.False(t, info.IsDir())

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Contains(t, string(data), "created\n")
}

func TestProcessData_TableDriven(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		want       string
		wantPanic  bool
		panicValue string
	}{
		{
			name:      "non-empty string returns same string",
			input:     "hello",
			want:      "hello",
			wantPanic: false,
		},
		{
			name:      "whitespace string does not panic",
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
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				defer func() {
					r := recover()
					assert.NotNil(t, r)
					if r != nil {
						assert.Equal(t, tt.panicValue, r)
					}
				}()
				_ = ProcessData(tt.input)
				return
			}

			result := ProcessData(tt.input)
			assert.Equal(t, tt.want, result)
		})
	}
}

func TestProcessData_RepeatedCalls(t *testing.T) {
	inputs := []string{"a", "b", "c"}
	for _, in := range inputs {
		in := in
		t.Run("input_"+in, func(t *testing.T) {
			out := ProcessData(in)
			assert.Equal(t, in, out)
		})
	}
}

func TestProcessData_PanicMessageContent(t *testing.T) {
	defer func() {
		r := recover()
		assert.NotNil(t, r)
		if r != nil {
			msg, ok := r.(string)
			assert.True(t, ok)
			assert.Contains(t, msg, "empty")
		}
	}()
	_ = ProcessData("")
}
