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
				num, ok := cfg["number"].(float64)
				assert.True(t, ok)
				assert.Equal(t, float64(42), num)
			},
		},
		{
			name: "invalid JSON returns nil map",
			path: invalidJSONPath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				// json.Unmarshal on invalid JSON with non-nil map leaves it nil
				assert.Nil(t, cfg)
			},
		},
		{
			name: "empty file returns nil map",
			path: emptyFilePath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				// json.Unmarshal on empty slice returns error and leaves map nil
				assert.Nil(t, cfg)
			},
		},
		{
			name: "non-existent file returns nil map",
			path: nonExistentPath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				// os.ReadFile error is ignored, data is nil, Unmarshal on nil -> empty map
				assert.NotNil(t, cfg)
				assert.Equal(t, 0, len(cfg))
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

	path1 := filepath.Join(tmpDir, "cfg1.json")
	content1 := `{"a":1}`
	err := os.WriteFile(path1, []byte(content1), 0o644)
	assert.NoError(t, err)

	path2 := filepath.Join(tmpDir, "cfg2.json")
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

func TestReadConfig_UnmarshalIntoExistingMapBehavior(t *testing.T) {
	tmpDir := t.TempDir()

	path := filepath.Join(tmpDir, "cfg.json")
	content := `{"x":10}`
	err := os.WriteFile(path, []byte(content), 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)
	assert.Equal(t, float64(10), cfg["x"])

	// Call again with same path to ensure fresh map each time
	cfg2 := ReadConfig(path)
	assert.NotNil(t, cfg2)
	assert.Equal(t, float64(10), cfg2["x"])
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
			name:     "single message append",
			messages: []string{"hello\n"},
		},
		{
			name:     "multiple messages append",
			messages: []string{"first\n", "second\n", "third\n"},
		},
		{
			name:     "empty and non-empty messages",
			messages: []string{"", "non-empty", ""},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			_ = os.Remove("app.log")

			for _, msg := range tt.messages {
				WriteLog(msg)
			}

			data, err := os.ReadFile("app.log")
			if len(tt.messages) == 0 {
				assert.Error(t, err)
				return
			}
			assert.NoError(t, err)

			expected := ""
			for _, msg := range tt.messages {
				expected += msg
			}
			assert.Equal(t, expected, string(data))
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

	initialContent := "existing\n"
	err = os.WriteFile("app.log", []byte(initialContent), 0o644)
	assert.NoError(t, err)

	WriteLog("new line\n")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Equal(t, initialContent+"new line\n", string(data))
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

	for i := 0; i < 5; i++ {
		WriteLog("line\n")
	}

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Equal(t, "line\nline\nline\nline\nline\n", string(data))
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
			name:       "explicit empty string panics with exact message",
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

func TestProcessData_PanicTypeAndMessage(t *testing.T) {
	defer func() {
		r := recover()
		assert.NotNil(t, r)

		msg, ok := r.(string)
		assert.True(t, ok)
		assert.Equal(t, "empty input", msg)
	}()

	_ = ProcessData("")
}

func TestProcessData_IdempotentForSameInput(t *testing.T) {
	input := "repeat"
	out1 := ProcessData(input)
	out2 := ProcessData(input)

	assert.Equal(t, input, out1)
	assert.Equal(t, input, out2)
	assert.Equal(t, out1, out2)
}

func TestReadConfig_WithPreExistingContentBehavior(t *testing.T) {
	tmpDir := t.TempDir()

	path := filepath.Join(tmpDir, "cfg.json")
	content := `{"k1":"v1","k2":"v2"}`
	err := os.WriteFile(path, []byte(content), 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)
	assert.Len(t, cfg, 2)
	assert.Equal(t, "v1", cfg["k1"])
	assert.Equal(t, "v2", cfg["k2"])

	// Overwrite file with different content and ensure new read reflects it
	newContent := `{"k3":"v3"}`
	err = os.WriteFile(path, []byte(newContent), 0o644)
	assert.NoError(t, err)

	cfg2 := ReadConfig(path)
	assert.NotNil(t, cfg2)
	assert.Len(t, cfg2, 1)
	assert.Equal(t, "v3", cfg2["k3"])
}

func TestReadConfig_RawJSONCompatibility(t *testing.T) {
	tmpDir := t.TempDir()

	path := filepath.Join(tmpDir, "cfg.json")
	raw := map[string]interface{}{
		"bool":   true,
		"string": "text",
		"num":    3.14,
		"obj": map[string]interface{}{
			"nested": "value",
		},
	}
	data, err := json.Marshal(raw)
	assert.NoError(t, err)

	err = os.WriteFile(path, data, 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)
	assert.Equal(t, raw["bool"], cfg["bool"])
	assert.Equal(t, raw["string"], cfg["string"])
	assert.Equal(t, raw["num"], cfg["num"])

	obj, ok := cfg["obj"].(map[string]interface{})
	assert.True(t, ok)
	assert.Equal(t, "value", obj["nested"])
}
