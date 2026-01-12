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
			name:       "invalid JSON file still returns map due to ignored error",
			path:       invalidJSONPath,
			wantNonNil: true,
		},
		{
			name:       "empty file returns nil map because unmarshal into nil map",
			path:       emptyFilePath,
			wantNonNil: false,
		},
		{
			name:       "non-existent file returns nil map due to nil data",
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

	configPath := filepath.Join(tmpDir, "config.json")
	content := `{"name":"app","enabled":true,"count":3}`
	err := os.WriteFile(configPath, []byte(content), 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(configPath)
	assert.NotNil(t, cfg)

	raw, ok := cfg["name"]
	assert.True(t, ok)
	assert.Equal(t, "app", raw)

	enabled, ok := cfg["enabled"]
	assert.True(t, ok)
	boolVal, ok := enabled.(bool)
	assert.True(t, ok)
	assert.True(t, boolVal)

	count, ok := cfg["count"]
	assert.True(t, ok)
	// JSON numbers are float64 by default
	_, ok = count.(float64)
	assert.True(t, ok)
}

func TestReadConfig_IgnoresJSONError(t *testing.T) {
	tmpDir := t.TempDir()

	path := filepath.Join(tmpDir, "bad.json")
	// Write non-JSON content
	err := os.WriteFile(path, []byte("not-json-at-all"), 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	// Because json.Unmarshal into nil map with invalid data leaves it nil
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
		name    string
		message string
	}{
		{
			name:    "simple message",
			message: "hello world",
		},
		{
			name:    "empty message",
			message: "",
		},
		{
			name:    "multi-line message",
			message: "line1\nline2\nline3",
		},
		{
			name:    "unicode message",
			message: "こんにちは世界",
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

	messages := []string{"first", "second", "third"}
	for _, msg := range messages {
		WriteLog(msg + "\n")
	}

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)

	content := string(data)
	assert.Contains(t, content, initialContent)
	for _, msg := range messages {
		assert.Contains(t, content, msg)
	}
}

func TestWriteLog_FilePermissionsAndExistence(t *testing.T) {
	tmpDir := t.TempDir()
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	WriteLog("test-permissions")

	info, err := os.Stat("app.log")
	assert.NoError(t, err)
	assert.False(t, info.IsDir())

	mode := info.Mode().Perm()
	assert.Equal(t, os.FileMode(0o644), mode)
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
			input:     "data",
			want:      "data",
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
			name:       "very long string does not panic",
			input:      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			want:       "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			wantPanic:  false,
			panicValue: nil,
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

func TestProcessData_PanicMessageType(t *testing.T) {
	assert.Panics(t, func() {
		_ = ProcessData("")
	})

	defer func() {
		if r := recover(); r != nil {
			_, ok := r.(string)
			assert.True(t, ok)
		}
	}()

	_ = ProcessData("")
}

func TestProcessData_IdempotentForSameInput(t *testing.T) {
	inputs := []string{"abc", "123", "mixed-CASE_!@#", "   spaces   "}

	for _, in := range inputs {
		in := in
		t.Run(in, func(t *testing.T) {
			first := ProcessData(in)
			second := ProcessData(in)
			assert.Equal(t, first, second)
			assert.Equal(t, in, first)
		})
	}
}

func TestReadConfig_JSONTypesRoundTrip(t *testing.T) {
	tmpDir := t.TempDir()

	type sample struct {
		Str   string                 `json:"str"`
		Num   int                    `json:"num"`
		Bool  bool                   `json:"bool"`
		Array []int                  `json:"array"`
		Obj   map[string]interface{} `json:"obj"`
	}

	orig := sample{
		Str:  "text",
		Num:  10,
		Bool: true,
		Array: []int{
			1, 2, 3,
		},
		Obj: map[string]interface{}{
			"k": "v",
		},
	}

	data, err := json.Marshal(orig)
	assert.NoError(t, err)

	path := filepath.Join(tmpDir, "complex.json")
	err = os.WriteFile(path, data, 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)

	str, ok := cfg["str"].(string)
	assert.True(t, ok)
	assert.Equal(t, orig.Str, str)

	num, ok := cfg["num"].(float64)
	assert.True(t, ok)
	assert.Equal(t, float64(orig.Num), num)

	boolean, ok := cfg["bool"].(bool)
	assert.True(t, ok)
	assert.Equal(t, orig.Bool, boolean)

	array, ok := cfg["array"].([]interface{})
	assert.True(t, ok)
	assert.Len(t, array, len(orig.Array))

	obj, ok := cfg["obj"].(map[string]interface{})
	assert.True(t, ok)
	val, ok := obj["k"].(string)
	assert.True(t, ok)
	assert.Equal(t, "v", val)
}
