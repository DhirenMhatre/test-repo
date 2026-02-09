package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReadConfig_TableDriven(t *testing.T) {
	type testCase struct {
		name         string
		setupFile    func(t *testing.T) string
		expectConfig map[string]interface{}
	}

	tests := []testCase{
		{
			name: "ValidJSONConfig",
			setupFile: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				path := filepath.Join(dir, "config.json")
				content := `{"key":"value","number":42}`
				err := os.WriteFile(path, []byte(content), 0o644)
				assert.NoError(t, err)
				return path
			},
			expectConfig: map[string]interface{}{
				"key":    "value",
				"number": float64(42),
			},
		},
		{
			name: "InvalidJSONConfig",
			setupFile: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				path := filepath.Join(dir, "config.json")
				content := `{"key": "value",` // invalid JSON
				err := os.WriteFile(path, []byte(content), 0o644)
				assert.NoError(t, err)
				return path
			},
			expectConfig: map[string]interface{}(nil),
		},
		{
			name: "MissingFile",
			setupFile: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				return filepath.Join(dir, "does_not_exist.json")
			},
			expectConfig: map[string]interface{}(nil),
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			path := tt.setupFile(t)

			cfg := ReadConfig(path)

			if tt.expectConfig == nil {
				assert.Nil(t, cfg)
				return
			}

			assert.NotNil(t, cfg)
			for k, v := range tt.expectConfig {
				got, ok := cfg[k]
				assert.True(t, ok, "expected key %q to exist", k)
				switch expected := v.(type) {
				case float64:
					gotFloat, ok := got.(float64)
					assert.True(t, ok, "expected key %q to be float64", k)
					assert.Equal(t, expected, gotFloat)
				default:
					assert.Equal(t, expected, got)
				}
			}
		})
	}
}

func TestReadConfig_EmptyFileAndWhitespace(t *testing.T) {
	tests := []struct {
		name      string
		content   string
		expectNil bool
	}{
		{
			name:      "EmptyFile",
			content:   "",
			expectNil: true,
		},
		{
			name:      "WhitespaceOnly",
			content:   "   \n\t",
			expectNil: true,
		},
		{
			name:      "SimpleObject",
			content:   `{"a":1}`,
			expectNil: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, "config.json")
			err := os.WriteFile(path, []byte(tt.content), 0o644)
			assert.NoError(t, err)

			cfg := ReadConfig(path)

			if tt.expectNil {
				assert.Nil(t, cfg)
				return
			}

			assert.NotNil(t, cfg)
			raw, err := os.ReadFile(path)
			assert.NoError(t, err)
			var expected map[string]interface{}
			err = json.Unmarshal(raw, &expected)
			assert.NoError(t, err)
			assert.Equal(t, expected, cfg)
		})
	}
}

func TestWriteLog_TableDriven(t *testing.T) {
	tests := []struct {
		name        string
		setupPath   func(t *testing.T) string
		message     string
		shouldExist bool
	}{
		{
			name: "WriteToExistingFile",
			setupPath: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				path := filepath.Join(dir, "app.log")
				err := os.WriteFile(path, []byte("initial\n"), 0o644)
				assert.NoError(t, err)
				// chdir so WriteLog writes to this file name
				err = os.Chdir(dir)
				assert.NoError(t, err)
				return path
			},
			message:     "hello world",
			shouldExist: true,
		},
		{
			name: "WriteToNewFile",
			setupPath: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				path := filepath.Join(dir, "app.log")
				err := os.Chdir(dir)
				assert.NoError(t, err)
				return path
			},
			message:     "new file content",
			shouldExist: true,
		},
		{
			name: "EmptyMessage",
			setupPath: func(t *testing.T) string {
				t.Helper()
				dir := t.TempDir()
				path := filepath.Join(dir, "app.log")
				err := os.Chdir(dir)
				assert.NoError(t, err)
				return path
			},
			message:     "",
			shouldExist: true,
		},
	}

	originalWD, err := os.Getwd()
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(originalWD)
	}()

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			path := tt.setupPath(t)

			WriteLog(tt.message)

			_, statErr := os.Stat(path)
			if tt.shouldExist {
				assert.NoError(t, statErr)
				data, readErr := os.ReadFile(path)
				assert.NoError(t, readErr)
				if tt.message != "" {
					assert.Contains(t, string(data), tt.message)
				}
			} else {
				assert.Error(t, statErr)
			}
		})
	}
}

func TestWriteLog_MultipleWritesAppendBehavior(t *testing.T) {
	originalWD, err := os.Getwd()
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(originalWD)
	}()

	dir := t.TempDir()
	err = os.Chdir(dir)
	assert.NoError(t, err)

	messages := []string{"first\n", "second\n", "third\n"}

	for _, msg := range messages {
		WriteLog(msg)
	}

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	content := string(data)

	for _, msg := range messages {
		assert.Contains(t, content, msg)
	}
}

func TestProcessData_TableDriven(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		wantPanic bool
	}{
		{
			name:      "NonEmptyInput",
			input:     "data",
			wantPanic: false,
		},
		{
			name:      "WhitespaceInput",
			input:     "  ",
			wantPanic: false,
		},
		{
			name:      "EmptyInputPanics",
			input:     "",
			wantPanic: true,
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
				assert.Equal(t, tt.input, got)
			})
		})
	}
}

func TestProcessData_RepeatedCalls(t *testing.T) {
	inputs := []string{"one", "two", "three"}
	for _, in := range inputs {
		in := in
		t.Run("Input_"+in, func(t *testing.T) {
			assert.NotPanics(t, func() {
				got := ProcessData(in)
				assert.Equal(t, in, got)
			})
		})
	}
}
