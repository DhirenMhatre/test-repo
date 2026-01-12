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
			name:       "non-existent file returns nil map",
			path:       filepath.Join(tmpDir, "does_not_exist.json"),
			wantNonNil: false,
		},
		{
			name:       "invalid JSON returns nil map",
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
			cfg := ReadConfig(tt.path)
			if tt.wantNonNil {
				assert.NotNil(t, cfg)
				if cfg == nil {
					return
				}
				assert.Equal(t, "value", cfg["key"])
				// json.Unmarshal decodes numbers as float64 by default
				num, ok := cfg["number"].(float64)
				assert.True(t, ok)
				if ok {
					assert.Equal(t, float64(42), num)
				}
			} else {
				assert.Nil(t, cfg)
			}
		})
	}
}

func TestReadConfig_ContentVerification(t *testing.T) {
	tmpDir := t.TempDir()

	type sample struct {
		Name string `json:"name"`
		Age  int    `json:"age"`
	}

	s := sample{Name: "Alice", Age: 30}
	b, err := json.Marshal(s)
	assert.NoError(t, err)

	path := filepath.Join(tmpDir, "user.json")
	err = os.WriteFile(path, b, 0o644)
	assert.NoError(t, err)

	tests := []struct {
		name      string
		path      string
		wantName  string
		wantAge   float64
		wantNil   bool
		checkKeys bool
	}{
		{
			name:      "valid struct JSON",
			path:      path,
			wantName:  "Alice",
			wantAge:   30,
			wantNil:   false,
			checkKeys: true,
		},
		{
			name:      "missing file",
			path:      filepath.Join(tmpDir, "missing.json"),
			wantNil:   true,
			checkKeys: false,
		},
		{
			name:      "directory path instead of file",
			path:      tmpDir,
			wantNil:   true,
			checkKeys: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			cfg := ReadConfig(tt.path)
			if tt.wantNil {
				assert.Nil(t, cfg)
				return
			}
			assert.NotNil(t, cfg)
			if cfg == nil {
				return
			}
			if tt.checkKeys {
				assert.Equal(t, tt.wantName, cfg["name"])
				age, ok := cfg["age"].(float64)
				assert.True(t, ok)
				if ok {
					assert.Equal(t, tt.wantAge, age)
				}
			}
		})
	}
}

func TestWriteLog_TableDriven(t *testing.T) {
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	tmpDir := t.TempDir()
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
			name:    "message with special characters",
			message: "äöüß漢字!@#$%^&*()",
		},
		{
			name:    "message with trailing newline",
			message: "with newline\n",
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

func TestWriteLog_AppendBehavior(t *testing.T) {
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	tmpDir := t.TempDir()
	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	tests := []struct {
		name          string
		messages      []string
		expectedOrder []string
	}{
		{
			name:          "two sequential writes",
			messages:      []string{"first", "second"},
			expectedOrder: []string{"first", "second"},
		},
		{
			name:          "three sequential writes with empty",
			messages:      []string{"alpha", "", "beta"},
			expectedOrder: []string{"alpha", "", "beta"},
		},
		{
			name:          "repeated same message",
			messages:      []string{"same", "same", "same"},
			expectedOrder: []string{"same", "same", "same"},
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
			assert.NoError(t, err)
			content := string(data)

			for _, expected := range tt.expectedOrder {
				assert.Contains(t, content, expected)
			}
		})
	}
}

func TestWriteLog_PreExistingFile(t *testing.T) {
	origWD, err := os.Getwd()
	assert.NoError(t, err)

	tmpDir := t.TempDir()
	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	initialContent := "initial content\n"
	err = os.WriteFile("app.log", []byte(initialContent), 0o644)
	assert.NoError(t, err)

	tests := []struct {
		name           string
		message        string
		expectContains []string
	}{
		{
			name:           "append to existing file",
			message:        "new entry",
			expectContains: []string{"initial content", "new entry"},
		},
		{
			name:           "append another entry",
			message:        "second entry",
			expectContains: []string{"initial content", "new entry", "second entry"},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			WriteLog(tt.message)

			data, err := os.ReadFile("app.log")
			assert.NoError(t, err)
			content := string(data)

			for _, expected := range tt.expectContains {
				assert.Contains(t, content, expected)
			}
		})
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
			name:        "empty string panics",
			input:       "",
			wantPanic:   true,
			panicSubstr: "empty input",
		},
		{
			name:      "whitespace string does not panic",
			input:     " ",
			want:      " ",
			wantPanic: false,
		},
		{
			name:      "long string returns same value",
			input:     "this is a longer input string for testing",
			want:      "this is a longer input string for testing",
			wantPanic: false,
		},
		{
			name:      "unicode string returns same value",
			input:     "こんにちは世界",
			want:      "こんにちは世界",
			wantPanic: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.PanicsWithValue(t, tt.panicSubstr, func() {
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

func TestProcessData_PanicMessageDetails(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		wantPanic bool
	}{
		{
			name:      "empty input panics",
			input:     "",
			wantPanic: true,
		},
		{
			name:      "non-empty input does not panic",
			input:     "data",
			wantPanic: false,
		},
		{
			name:      "single character does not panic",
			input:     "a",
			wantPanic: false,
		},
		{
			name:      "numeric string does not panic",
			input:     "12345",
			wantPanic: false,
		},
		{
			name:      "tab character does not panic",
			input:     "\t",
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
					msg, ok := r.(string)
					assert.True(t, ok)
					if ok {
						assert.Equal(t, "empty input", msg)
					}
				}()
				_ = ProcessData(tt.input)
				return
			}

			assert.NotPanics(t, func() {
				out := ProcessData(tt.input)
				assert.Equal(t, tt.input, out)
			})
		})
	}
}

func TestProcessData_RoundTripBehavior(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{
			name:  "simple word",
			input: "test",
		},
		{
			name:  "sentence with spaces",
			input: "the quick brown fox",
		},
		{
			name:  "special characters",
			input: "!@#$%^&*()_+",
		},
		{
			name:  "json-like string",
			input: `{"key":"value"}`,
		},
		{
			name:  "multi-line string",
			input: "line1\nline2\nline3",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.NotPanics(t, func() {
				out := ProcessData(tt.input)
				assert.Equal(t, tt.input, out)
			})
		})
	}
}
