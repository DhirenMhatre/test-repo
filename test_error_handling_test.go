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

	invalidJSONPath := filepath.Join(tmpDir, "invalid.json")
	err = os.WriteFile(invalidJSONPath, []byte("{invalid json"), 0o644)
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
			name:       "valid json file returns non-nil map",
			path:       validPath,
			wantNonNil: true,
		},
		{
			name:       "non-existent file returns nil map",
			path:       filepath.Join(tmpDir, "does_not_exist.json"),
			wantNonNil: false,
		},
		{
			name:       "invalid json returns nil map",
			path:       invalidJSONPath,
			wantNonNil: false,
		},
		{
			name:       "empty file returns nil map",
			path:       emptyFilePath,
			wantNonNil: false,
		},
		{
			name:       "empty path returns nil map",
			path:       "",
			wantNonNil: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			got := ReadConfig(tt.path)
			if tt.wantNonNil {
				assert.NotNil(t, got)
				if got == nil {
					return
				}
				assert.Equal(t, "value", got["key"])
				assert.Equal(t, float64(42), got["num"])
			} else {
				assert.Nil(t, got)
			}
		})
	}
}

func TestReadConfig_MultipleCallsSameFile(t *testing.T) {
	tmpDir := t.TempDir()

	config := map[string]interface{}{
		"a": "b",
	}
	data, err := json.Marshal(config)
	assert.NoError(t, err)

	path := filepath.Join(tmpDir, "config.json")
	err = os.WriteFile(path, data, 0o644)
	assert.NoError(t, err)

	got1 := ReadConfig(path)
	got2 := ReadConfig(path)

	assert.NotNil(t, got1)
	assert.NotNil(t, got2)
	if got1 == nil || got2 == nil {
		return
	}
	assert.Equal(t, got1, got2)
	assert.Equal(t, "b", got1["a"])
}

func TestReadConfig_DirectoryPath(t *testing.T) {
	tmpDir := t.TempDir()

	got := ReadConfig(tmpDir)
	assert.Nil(t, got)
}

func TestWriteLog_TableDriven(t *testing.T) {
	originalWD, err := os.Getwd()
	assert.NoError(t, err)

	tmpDir := t.TempDir()
	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(originalWD)
	}()

	tests := []struct {
		name    string
		message string
	}{
		{
			name:    "single short message",
			message: "hello world\n",
		},
		{
			name:    "empty message",
			message: "",
		},
		{
			name:    "long message",
			message: "this is a much longer log message to test append behavior\n",
		},
		{
			name:    "message with newlines",
			message: "line1\nline2\nline3\n",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			WriteLog(tt.message)

			data, err := os.ReadFile("app.log")
			assert.NoError(t, err)

			content := string(data)
			assert.Contains(t, content, tt.message)
		})
	}
}

func TestWriteLog_AppendsToExistingFile(t *testing.T) {
	originalWD, err := os.Getwd()
	assert.NoError(t, err)

	tmpDir := t.TempDir()
	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(originalWD)
	}()

	initialContent := "initial\n"
	err = os.WriteFile("app.log", []byte(initialContent), 0o644)
	assert.NoError(t, err)

	messages := []string{"first\n", "second\n", "third\n"}
	for _, msg := range messages {
		WriteLog(msg)
	}

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)

	content := string(data)
	assert.Contains(t, content, initialContent)
	for _, msg := range messages {
		assert.Contains(t, content, msg)
	}
}

func TestWriteLog_MultipleSequentialCalls(t *testing.T) {
	originalWD, err := os.Getwd()
	assert.NoError(t, err)

	tmpDir := t.TempDir()
	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(originalWD)
	}()

	for i := 0; i < 5; i++ {
		WriteLog("entry\n")
	}

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)

	content := string(data)
	count := 0
	for _, ch := range content {
		if ch == '\n' {
			count++
		}
	}
	assert.GreaterOrEqual(t, count, 5)
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
			name:       "empty string panics",
			input:      "",
			wantPanic:  true,
			panicValue: "empty input",
		},
		{
			name:      "whitespace string does not panic",
			input:     " ",
			want:      " ",
			wantPanic: false,
		},
		{
			name:      "long string returns same string",
			input:     "this is a long input string for testing",
			want:      "this is a long input string for testing",
			wantPanic: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				defer func() {
					r := recover()
					assert.NotNil(t, r)
					if r == nil {
						return
					}
					assert.Equal(t, tt.panicValue, r)
				}()
				_ = ProcessData(tt.input)
				return
			}

			defer func() {
				r := recover()
				assert.Nil(t, r)
			}()

			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestProcessData_MultipleNonEmptyInputs(t *testing.T) {
	inputs := []string{"a", "b", "c", "123", "test"}
	for _, in := range inputs {
		in := in
		t.Run("input_"+in, func(t *testing.T) {
			defer func() {
				r := recover()
				assert.Nil(t, r)
			}()
			got := ProcessData(in)
			assert.Equal(t, in, got)
		})
	}
}

func TestProcessData_PanicMessageContent(t *testing.T) {
	defer func() {
		r := recover()
		assert.NotNil(t, r)
		if r == nil {
			return
		}
		msg, ok := r.(string)
		assert.True(t, ok)
		assert.Contains(t, msg, "empty")
	}()
	_ = ProcessData("")
}
