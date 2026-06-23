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

	validPath := filepath.Join(tmpDir, "valid.json")
	validContent := `{"key":"value","number":42}`
	err := os.WriteFile(validPath, []byte(validContent), 0o644)
	assert.NoError(t, err)

	invalidJSONPath := filepath.Join(tmpDir, "invalid.json")
	invalidContent := `{"key":`
	err = os.WriteFile(invalidJSONPath, []byte(invalidContent), 0o644)
	assert.NoError(t, err)

	emptyFilePath := filepath.Join(tmpDir, "empty.json")
	err = os.WriteFile(emptyFilePath, []byte(""), 0o644)
	assert.NoError(t, err)

	tests := []struct {
		name        string
		path        string
		expectEmpty bool
	}{
		{
			name:        "valid JSON file returns parsed map",
			path:        validPath,
			expectEmpty: false,
		},
		{
			name:        "non-existent file returns empty map",
			path:        filepath.Join(tmpDir, "does_not_exist.json"),
			expectEmpty: true,
		},
		{
			name:        "invalid JSON returns empty map",
			path:        invalidJSONPath,
			expectEmpty: true,
		},
		{
			name:        "empty file returns empty map",
			path:        emptyFilePath,
			expectEmpty: true,
		},
		{
			name:        "empty path returns empty map",
			path:        "",
			expectEmpty: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			cfg := ReadConfig(tt.path)
			assert.NotNil(t, cfg)

			if tt.expectEmpty {
				assert.Equal(t, 0, len(cfg))
			} else {
				assert.Greater(t, len(cfg), 0)
				raw, ok := cfg["key"]
				assert.True(t, ok)
				str, ok := raw.(string)
				assert.True(t, ok)
				assert.Equal(t, "value", str)

				numRaw, ok := cfg["number"]
				assert.True(t, ok)
				_, ok = numRaw.(float64)
				assert.True(t, ok)
			}
		})
	}
}

func TestReadConfig_DoesNotPanicOnLargeFile(t *testing.T) {
	tmpDir := t.TempDir()
	largePath := filepath.Join(tmpDir, "large.json")

	largeMap := map[string]interface{}{}
	for i := 0; i < 1000; i++ {
		key := "key_" + string(rune('a'+(i%26))) + string(rune('A'+(i%26)))
		largeMap[key] = i
	}
	data, err := json.Marshal(largeMap)
	assert.NoError(t, err)

	err = os.WriteFile(largePath, data, 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(largePath)
	assert.NotNil(t, cfg)
	assert.GreaterOrEqual(t, len(cfg), 1)
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
		name           string
		message        string
		repeat         int
		expectFile     bool
		expectedSuffix string
	}{
		{
			name:           "single write creates file with message",
			message:        "hello world",
			repeat:         1,
			expectFile:     true,
			expectedSuffix: "hello world",
		},
		{
			name:           "multiple writes append to file",
			message:        "line",
			repeat:         3,
			expectFile:     true,
			expectedSuffix: "line",
		},
		{
			name:           "empty message still creates file",
			message:        "",
			repeat:         1,
			expectFile:     true,
			expectedSuffix: "",
		},
	}

	logPath := filepath.Join(tmpDir, "app.log")

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			_ = os.Remove(logPath)

			for i := 0; i < tt.repeat; i++ {
				WriteLog(tt.message)
			}

			_, err := os.Stat(logPath)
			if tt.expectFile {
				assert.NoError(t, err)
				content, readErr := os.ReadFile(logPath)
				assert.NoError(t, readErr)

				if tt.repeat > 1 && tt.message != "" {
					expectedCount := tt.repeat
					actualCount := 0
					for _, b := range content {
						if b == 'l' {
							actualCount++
						}
					}
					assert.GreaterOrEqual(t, actualCount, expectedCount)
				}

				if tt.expectedSuffix != "" {
					assert.Contains(t, string(content), tt.expectedSuffix)
				}
			} else {
				assert.Error(t, err)
			}
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

	WriteLog("second")
	WriteLog("third")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	str := string(data)
	assert.Contains(t, str, "initial")
	assert.Contains(t, str, "second")
	assert.Contains(t, str, "third")
}

func TestProcessData_TableDriven(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		expectPanic bool
	}{
		{
			name:        "non-empty string returns same value",
			input:       "hello",
			expectPanic: false,
		},
		{
			name:        "whitespace string does not panic",
			input:       "   ",
			expectPanic: false,
		},
		{
			name:        "single character string",
			input:       "a",
			expectPanic: false,
		},
		{
			name:        "empty string panics",
			input:       "",
			expectPanic: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.expectPanic {
				defer func() {
					r := recover()
					assert.NotNil(t, r)
					if r != nil {
						msg, ok := r.(string)
						if ok {
							assert.Contains(t, msg, "empty input")
						}
					}
				}()
				_ = ProcessData(tt.input)
				return
			}

			defer func() {
				r := recover()
				assert.Nil(t, r)
			}()

			out := ProcessData(tt.input)
			assert.Equal(t, tt.input, out)
		})
	}
}

func TestProcessData_MultipleSequentialCalls(t *testing.T) {
	inputs := []string{"one", "two", "three"}
	for _, in := range inputs {
		in := in
		t.Run("input_"+in, func(t *testing.T) {
			defer func() {
				r := recover()
				assert.Nil(t, r)
			}()
			out := ProcessData(in)
			assert.Equal(t, in, out)
		})
	}
}

func TestProcessData_PanicMessageExact(t *testing.T) {
	defer func() {
		r := recover()
		assert.NotNil(t, r)
		msg, ok := r.(string)
		assert.True(t, ok)
		assert.Equal(t, "empty input", msg)
	}()
	_ = ProcessData("")
}
