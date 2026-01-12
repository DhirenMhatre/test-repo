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
			name:       "invalid JSON still returns map (due to ignored error)",
			path:       invalidJSONPath,
			wantNonNil: true,
		},
		{
			name:       "empty file returns nil map (unmarshal on empty slice)",
			path:       emptyFilePath,
			wantNonNil: false,
		},
		{
			name:       "non-existent file returns nil map (ignored read error)",
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

	type sample struct {
		Name string `json:"name"`
		Age  int    `json:"age"`
	}

	obj := sample{Name: "alice", Age: 30}
	b, err := json.Marshal(obj)
	assert.NoError(t, err)

	path := filepath.Join(tmpDir, "config.json")
	err = os.WriteFile(path, b, 0o644)
	assert.NoError(t, err)

	tests := []struct {
		name        string
		path        string
		expectName  string
		expectAge   float64
		expectEmpty bool
	}{
		{
			name:       "valid struct marshaled to map",
			path:       path,
			expectName: "alice",
			expectAge:  30,
		},
		{
			name:        "missing file returns nil map",
			path:        filepath.Join(tmpDir, "missing.json"),
			expectEmpty: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			cfg := ReadConfig(tt.path)
			if tt.expectEmpty {
				assert.Nil(t, cfg)
				return
			}

			assert.NotNil(t, cfg)

			nameVal, ok := cfg["name"]
			assert.True(t, ok)
			assert.Equal(t, tt.expectName, nameVal)

			ageVal, ok := cfg["age"]
			assert.True(t, ok)
			ageFloat, ok := ageVal.(float64)
			assert.True(t, ok)
			assert.Equal(t, tt.expectAge, ageFloat)
		})
	}
}

func TestReadConfig_IdempotentCalls(t *testing.T) {
	tmpDir := t.TempDir()

	path := filepath.Join(tmpDir, "config.json")
	content := `{"flag":true}`
	err := os.WriteFile(path, []byte(content), 0o644)
	assert.NoError(t, err)

	first := ReadConfig(path)
	second := ReadConfig(path)

	assert.NotNil(t, first)
	assert.NotNil(t, second)
	assert.Equal(t, first, second)
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
		initialExists bool
		initialData   string
		message       string
	}{
		{
			name:          "create new log file and write message",
			initialExists: false,
			message:       "hello world",
		},
		{
			name:          "append to existing log file",
			initialExists: true,
			initialData:   "existing\n",
			message:       "new entry",
		},
		{
			name:          "write empty message",
			initialExists: false,
			message:       "",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			logPath := filepath.Join(tmpDir, "app.log")

			if tt.initialExists {
				err := os.WriteFile(logPath, []byte(tt.initialData), 0o644)
				assert.NoError(t, err)
			} else {
				_ = os.Remove(logPath)
			}

			WriteLog(tt.message)

			data, err := os.ReadFile(logPath)
			assert.NoError(t, err)

			if tt.initialExists {
				assert.Equal(t, tt.initialData+tt.message, string(data))
			} else {
				assert.Equal(t, tt.message, string(data))
			}
		})
	}
}

func TestWriteLog_MultipleSequentialWrites(t *testing.T) {
	tmpDir := t.TempDir()
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	messages := []string{"first\n", "second\n", "third\n"}

	for _, msg := range messages {
		WriteLog(msg)
	}

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Equal(t, "first\nsecond\nthird\n", string(data))
}

func TestWriteLog_RecreateAfterRemoval(t *testing.T) {
	tmpDir := t.TempDir()
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	WriteLog("initial")
	err = os.Remove("app.log")
	assert.NoError(t, err)

	WriteLog("after-remove")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Equal(t, "after-remove", string(data))
}

func TestProcessData_TableDriven(t *testing.T) {
	tests := []struct {
		name          string
		input         string
		want          string
		wantPanic     bool
		panicContains string
	}{
		{
			name:      "non-empty string returns same value",
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
			name:          "empty string panics",
			input:         "",
			wantPanic:     true,
			panicContains: "empty input",
		},
		{
			name:          "explicit empty literal panics",
			input:         string([]byte{}),
			wantPanic:     true,
			panicContains: "empty input",
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
						msg, ok := r.(string)
						if ok {
							assert.Contains(t, msg, tt.panicContains)
						}
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

func TestProcessData_IdempotentNonEmpty(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{
			name:  "simple word",
			input: "data",
		},
		{
			name:  "with numbers",
			input: "123abc",
		},
		{
			name:  "with symbols",
			input: "!@#$%",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			first := ProcessData(tt.input)
			second := ProcessData(tt.input)
			assert.Equal(t, tt.input, first)
			assert.Equal(t, first, second)
		})
	}
}

func TestProcessData_PanicMessageExact(t *testing.T) {
	defer func() {
		r := recover()
		assert.NotNil(t, r)
		if r != nil {
			msg, ok := r.(string)
			assert.True(t, ok)
			assert.Equal(t, "empty input", msg)
		}
	}()
	_ = ProcessData("")
}
