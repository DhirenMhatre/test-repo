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

	nonExistingPath := filepath.Join(tmpDir, "does_not_exist.json")

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
				assert.Equal(t, float64(42), cfg["number"])
			},
		},
		{
			name: "invalid JSON returns nil map",
			path: invalidJSONPath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				assert.Nil(t, cfg)
			},
		},
		{
			name: "empty file returns nil map",
			path: emptyFilePath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				assert.Nil(t, cfg)
			},
		},
		{
			name: "non-existing file returns nil map",
			path: nonExistingPath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
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

func TestReadConfig_MultipleCallsIndependence(t *testing.T) {
	tmpDir := t.TempDir()

	path1 := filepath.Join(tmpDir, "config1.json")
	content1 := `{"a":1}`
	err := os.WriteFile(path1, []byte(content1), 0o644)
	assert.NoError(t, err)

	path2 := filepath.Join(tmpDir, "config2.json")
	content2 := `{"b":2}`
	err = os.WriteFile(path2, []byte(content2), 0o644)
	assert.NoError(t, err)

	cfg1 := ReadConfig(path1)
	cfg2 := ReadConfig(path2)

	assert.NotNil(t, cfg1)
	assert.NotNil(t, cfg2)
	assert.NotEqual(t, cfg1, cfg2)
	assert.Contains(t, cfg1, "a")
	assert.NotContains(t, cfg1, "b")
	assert.Contains(t, cfg2, "b")
	assert.NotContains(t, cfg2, "a")
}

func TestReadConfig_EmptyPath(t *testing.T) {
	cfg := ReadConfig("")
	assert.Nil(t, cfg)
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
		name     string
		messages []string
	}{
		{
			name:     "single message",
			messages: []string{"hello world"},
		},
		{
			name:     "multiple messages",
			messages: []string{"first line\n", "second line\n", "third line"},
		},
		{
			name:     "empty message",
			messages: []string{""},
		},
		{
			name:     "mixed messages",
			messages: []string{"alpha", "", "beta\n", "gamma"},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			err := os.Remove("app.log")
			if err != nil && !os.IsNotExist(err) {
				assert.NoError(t, err)
			}

			for _, msg := range tt.messages {
				WriteLog(msg)
			}

			data, err := os.ReadFile("app.log")
			if len(tt.messages) == 0 {
				assert.True(t, os.IsNotExist(err))
				return
			}
			assert.NoError(t, err)

			content := string(data)
			for _, msg := range tt.messages {
				assert.Contains(t, content, msg)
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

	initialContent := "existing content\n"
	err = os.WriteFile("app.log", []byte(initialContent), 0o644)
	assert.NoError(t, err)

	WriteLog("new line 1\n")
	WriteLog("new line 2")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)

	content := string(data)
	assert.Contains(t, content, initialContent)
	assert.Contains(t, content, "new line 1\n")
	assert.Contains(t, content, "new line 2")
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

	WriteLog("created by WriteLog")

	info, err := os.Stat("app.log")
	assert.NoError(t, err)
	assert.False(t, info.IsDir())

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Contains(t, string(data), "created by WriteLog")
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
			name:      "whitespace string returns same string",
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
			name:      "long string returns same string",
			input:     "this is a longer input string for testing",
			want:      "this is a longer input string for testing",
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
					if tt.panicValue != nil {
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

func TestProcessData_MultipleSequentialCalls(t *testing.T) {
	inputs := []string{"one", "two", "three"}
	results := make([]string, 0, len(inputs))

	for _, in := range inputs {
		results = append(results, ProcessData(in))
	}

	assert.Len(t, results, len(inputs))
	for i, in := range inputs {
		assert.Equal(t, in, results[i])
	}
}

func TestProcessData_PanicMessageType(t *testing.T) {
	defer func() {
		r := recover()
		assert.NotNil(t, r)

		switch v := r.(type) {
		case string:
			assert.Equal(t, "empty input", v)
		default:
			assert.Fail(t, "unexpected panic type", "type: %T", v)
		}
	}()

	_ = ProcessData("")
}

func TestReadConfig_ReturnsIndependentMaps(t *testing.T) {
	tmpDir := t.TempDir()

	path := filepath.Join(tmpDir, "config.json")
	content := `{"key":"value"}`
	err := os.WriteFile(path, []byte(content), 0o644)
	assert.NoError(t, err)

	cfg1 := ReadConfig(path)
	cfg2 := ReadConfig(path)

	if cfg1 == nil || cfg2 == nil {
		t.Fatalf("expected non-nil configs, got cfg1=%v cfg2=%v", cfg1, cfg2)
	}

	assert.NotSame(t, cfg1, cfg2)

	cfg1["key"] = "modified"
	assert.Equal(t, "modified", cfg1["key"])
	assert.Equal(t, "value", cfg2["key"])
}

func TestReadConfig_HandlesLargeJSON(t *testing.T) {
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "large.json")

	largeMap := map[string]interface{}{}
	for i := 0; i < 100; i++ {
		key := "key_" + string(rune('a'+(i%26)))
		largeMap[key] = i
	}

	data, err := json.Marshal(largeMap)
	assert.NoError(t, err)

	err = os.WriteFile(path, data, 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)
	for k, v := range largeMap {
		assert.Contains(t, cfg, k)
		assert.Equal(t, float64(v.(int)), cfg[k])
	}
}
