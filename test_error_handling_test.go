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
	validContent := `{"key":"value","num":123}`
	err := os.WriteFile(validConfigPath, []byte(validContent), 0o644)
	assert.NoError(t, err)

	invalidJSONPath := filepath.Join(tmpDir, "invalid.json")
	invalidContent := `{"key":`
	err = os.WriteFile(invalidJSONPath, []byte(invalidContent), 0o644)
	assert.NoError(t, err)

	emptyFilePath := filepath.Join(tmpDir, "empty.json")
	err = os.WriteFile(emptyFilePath, []byte(""), 0o644)
	assert.NoError(t, err)

	nonExistentPath := filepath.Join(tmpDir, "does_not_exist.json")

	tests := []struct {
		name       string
		path       string
		assertFunc func(t *testing.T, cfg map[string]interface{})
	}{
		{
			name: "valid JSON file returns parsed map",
			path: validConfigPath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				assert.NotNil(t, cfg)
				assert.Equal(t, "value", cfg["key"])
				// json.Unmarshal decodes numbers as float64 by default
				num, ok := cfg["num"].(float64)
				assert.True(t, ok)
				assert.Equal(t, float64(123), num)
			},
		},
		{
			name: "invalid JSON returns nil map due to unmarshal failure",
			path: invalidJSONPath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				// Unmarshal into nil map with error ignored leaves it nil
				assert.Nil(t, cfg)
			},
		},
		{
			name: "empty file returns nil map due to unmarshal failure",
			path: emptyFilePath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				assert.Nil(t, cfg)
			},
		},
		{
			name: "non-existent file returns nil map due to read failure",
			path: nonExistentPath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				// ReadFile error ignored, data is nil, Unmarshal into nil map keeps it nil
				assert.Nil(t, cfg)
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			cfg := ReadConfig(tt.path)
			tt.assertFunc(t, cfg)
		})
	}
}

func TestReadConfig_MultipleFilesSequential(t *testing.T) {
	tmpDir := t.TempDir()

	type configCase struct {
		filename string
		content  string
	}

	configs := []configCase{
		{"c1.json", `{"a":1}`},
		{"c2.json", `{"b":"text"}`},
		{"c3.json", `{"nested":{"x":true}}`},
	}

	for _, c := range configs {
		path := filepath.Join(tmpDir, c.filename)
		err := os.WriteFile(path, []byte(c.content), 0o644)
		assert.NoError(t, err)

		cfg := ReadConfig(path)
		assert.NotNil(t, cfg)

		var expected map[string]interface{}
		err = json.Unmarshal([]byte(c.content), &expected)
		assert.NoError(t, err)
		assert.Equal(t, expected, cfg)
	}
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
		name          string
		messages      []string
		expectedLines []string
	}{
		{
			name:          "single message",
			messages:      []string{"hello"},
			expectedLines: []string{"hello"},
		},
		{
			name:          "multiple messages appended",
			messages:      []string{"first", "second", "third"},
			expectedLines: []string{"first", "second", "third"},
		},
		{
			name:          "empty and non-empty messages",
			messages:      []string{"", "non-empty", ""},
			expectedLines: []string{"", "non-empty", ""},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			_ = os.Remove("app.log")

			for _, msg := range tt.messages {
				WriteLog(msg + "\n")
			}

			data, err := os.ReadFile("app.log")
			assert.NoError(t, err)

			content := string(data)
			for _, expected := range tt.expectedLines {
				assert.Contains(t, content, expected+"\n")
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

	initialContent := "existing line\n"
	err = os.WriteFile("app.log", []byte(initialContent), 0o644)
	assert.NoError(t, err)

	WriteLog("new line 1\n")
	WriteLog("new line 2\n")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	content := string(data)

	assert.Contains(t, content, "existing line\n")
	assert.Contains(t, content, "new line 1\n")
	assert.Contains(t, content, "new line 2\n")
}

func TestWriteLog_MultipleSequentialCalls(t *testing.T) {
	tmpDir := t.TempDir()
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	messages := []string{"alpha", "beta", "gamma", "delta", "epsilon"}

	for _, msg := range messages {
		WriteLog(msg + "\n")
	}

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	content := string(data)

	for _, msg := range messages {
		assert.Contains(t, content, msg+"\n")
	}
}

func TestProcessData_TableDriven(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		want        string
		wantPanic   bool
		panicSubstr string
	}{
		{
			name:      "non-empty string returns same value",
			input:     "hello",
			want:      "hello",
			wantPanic: false,
		},
		{
			name:      "whitespace string is treated as non-empty",
			input:     "   ",
			want:      "   ",
			wantPanic: false,
		},
		{
			name:        "empty string panics",
			input:       "",
			wantPanic:   true,
			panicSubstr: "empty input",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				defer func() {
					r := recover()
					assert.NotNil(t, r)
					if s, ok := r.(string); ok {
						assert.Contains(t, s, tt.panicSubstr)
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

func TestProcessData_MultipleValues(t *testing.T) {
	inputs := []string{"one", "two", "three", "0", "!"}
	for _, in := range inputs {
		in := in
		t.Run("input_"+in, func(t *testing.T) {
			result := ProcessData(in)
			assert.Equal(t, in, result)
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
