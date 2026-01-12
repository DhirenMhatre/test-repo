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
			name: "invalid JSON returns nil map due to unmarshal error",
			path: invalidJSONPath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				assert.Nil(t, cfg)
			},
		},
		{
			name: "empty file returns nil map due to unmarshal error",
			path: emptyFilePath,
			assertFunc: func(t *testing.T, cfg map[string]interface{}) {
				assert.Nil(t, cfg)
			},
		},
		{
			name: "non-existent file returns nil map due to read error",
			path: nonExistentPath,
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

	val1, ok1 := cfg1["a"].(float64)
	assert.True(t, ok1)
	assert.Equal(t, float64(1), val1)

	val2, ok2 := cfg2["b"].(float64)
	assert.True(t, ok2)
	assert.Equal(t, float64(2), val2)

	_, hasBInCfg1 := cfg1["b"]
	_, hasAInCfg2 := cfg2["a"]
	assert.False(t, hasBInCfg1)
	assert.False(t, hasAInCfg2)
}

func TestReadConfig_UnmarshalBehaviorWithDifferentTypes(t *testing.T) {
	tmpDir := t.TempDir()

	path := filepath.Join(tmpDir, "mixed.json")
	content := `{"str":"text","bool":true,"arr":[1,2,3]}`
	err := os.WriteFile(path, []byte(content), 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)

	str, ok := cfg["str"].(string)
	assert.True(t, ok)
	assert.Equal(t, "text", str)

	boolean, ok := cfg["bool"].(bool)
	assert.True(t, ok)
	assert.True(t, boolean)

	arr, ok := cfg["arr"].([]interface{})
	assert.True(t, ok)
	assert.Len(t, arr, 3)
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
			name:     "single short message",
			messages: []string{"hello world\n"},
		},
		{
			name:     "multiple messages appended",
			messages: []string{"first line\n", "second line\n", "third line\n"},
		},
		{
			name:     "empty message",
			messages: []string{""},
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
			if len(tt.messages) == 1 && tt.messages[0] == "" {
				assert.NoError(t, err)
				assert.Equal(t, "", string(data))
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

	initialContent := "existing content\n"
	err = os.WriteFile("app.log", []byte(initialContent), 0o644)
	assert.NoError(t, err)

	newMessage := "new log entry\n"
	WriteLog(newMessage)

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Equal(t, initialContent+newMessage, string(data))
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

	messages := []string{"one\n", "two\n", "three\n", "four\n", "five\n"}
	for _, msg := range messages {
		WriteLog(msg)
	}

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)

	expected := ""
	for _, msg := range messages {
		expected += msg
	}
	assert.Equal(t, expected, string(data))
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
			name:      "whitespace string does not panic and returns same string",
			input:     "   ",
			want:      "   ",
			wantPanic: false,
		},
		{
			name:       "empty string panics with specific message",
			input:      "",
			wantPanic:  true,
			panicValue: "empty input",
		},
		{
			name:      "long string returns same string",
			input:     "this is a longer input string to verify behavior",
			want:      "this is a longer input string to verify behavior",
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

			defer func() {
				r := recover()
				assert.Nil(t, r)
			}()

			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestProcessData_IdempotentForSameInput(t *testing.T) {
	input := "repeatable"
	first := ProcessData(input)
	second := ProcessData(input)
	assert.Equal(t, first, second)
	assert.Equal(t, input, first)
}

func TestProcessData_DifferentInputsProduceDifferentOutputs(t *testing.T) {
	tests := []struct {
		name   string
		input1 string
		input2 string
	}{
		{
			name:   "simple different strings",
			input1: "foo",
			input2: "bar",
		},
		{
			name:   "case sensitivity",
			input1: "Hello",
			input2: "hello",
		},
		{
			name:   "prefix difference",
			input1: "abc",
			input2: "abcd",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			out1 := ProcessData(tt.input1)
			out2 := ProcessData(tt.input2)
			assert.NotEqual(t, out1, out2)
		})
	}
}

func TestReadConfig_RawJSONCompatibility(t *testing.T) {
	tmpDir := t.TempDir()

	path := filepath.Join(tmpDir, "raw.json")
	content := `{"nested":{"inner":"value"},"list":[{"k":1},{"k":2}]}`
	err := os.WriteFile(path, []byte(content), 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)

	raw, err := json.Marshal(cfg)
	assert.NoError(t, err)

	var reparsed map[string]interface{}
	err = json.Unmarshal(raw, &reparsed)
	assert.NoError(t, err)
	assert.NotNil(t, reparsed)

	nested, ok := reparsed["nested"].(map[string]interface{})
	assert.True(t, ok)
	assert.Equal(t, "value", nested["inner"])
}
