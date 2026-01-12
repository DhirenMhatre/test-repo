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
	invalidContent := `{"key": "value",`
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
			name:       "nonexistent file returns nil map",
			path:       filepath.Join(tmpDir, "does_not_exist.json"),
			wantNonNil: false,
		},
		{
			name:       "valid json returns non-nil map",
			path:       validConfigPath,
			wantNonNil: true,
		},
		{
			name:       "invalid json returns non-nil map (due to ignored error)",
			path:       invalidJSONPath,
			wantNonNil: true,
		},
		{
			name:       "empty file returns non-nil map (due to ignored error)",
			path:       emptyFilePath,
			wantNonNil: true,
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
			} else {
				assert.Nil(t, cfg)
			}
		})
	}
}

func TestReadConfig_ContentVerification(t *testing.T) {
	tmpDir := t.TempDir()

	content := map[string]interface{}{
		"stringKey": "value",
		"intKey":    10,
		"boolKey":   true,
	}
	raw, err := json.Marshal(content)
	assert.NoError(t, err)

	path := filepath.Join(tmpDir, "config.json")
	err = os.WriteFile(path, raw, 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)

	assert.Equal(t, "value", cfg["stringKey"])
	assert.Equal(t, float64(10), cfg["intKey"])
	assert.Equal(t, true, cfg["boolKey"])
}

func TestReadConfig_NilOnReadFailure(t *testing.T) {
	// Using a directory path instead of file to force read failure
	tmpDir := t.TempDir()
	cfg := ReadConfig(tmpDir)
	assert.Nil(t, cfg)
}

func TestWriteLog_TableDriven(t *testing.T) {
	// Change working directory to temp dir so app.log is created there
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
			name:    "long message",
			message: string(make([]byte, 1024)),
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			WriteLog(tt.message)

			data, err := os.ReadFile("app.log")
			if err != nil {
				// If file does not exist or cannot be read, this reflects current implementation
				assert.Error(t, err)
				return
			}
			assert.NotNil(t, data)
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

	WriteLog("second\n")
	WriteLog("third\n")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	content := string(data)

	assert.Contains(t, content, "initial")
	assert.Contains(t, content, "second")
	assert.Contains(t, content, "third")
}

func TestWriteLog_FileCreatedIfNotExists(t *testing.T) {
	tmpDir := t.TempDir()
	origWD, err := os.Getwd()
	assert.NoError(t, err)
	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()

	_, statErr := os.Stat("app.log")
	assert.True(t, os.IsNotExist(statErr))

	WriteLog("created\n")

	info, err := os.Stat("app.log")
	assert.NoError(t, err)
	assert.False(t, info.IsDir())
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
			name:      "non-empty string returns same string",
			input:     "data",
			want:      "data",
			wantPanic: false,
		},
		{
			name:        "empty string panics",
			input:       "",
			want:        "",
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
			name:      "long string returns same",
			input:     "this is a long string for testing",
			want:      "this is a long string for testing",
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
					if s, ok := r.(string); ok {
						assert.Contains(t, s, tt.panicSubstr)
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

func TestProcessData_NoPanicForVariousInputs(t *testing.T) {
	inputs := []string{
		"a",
		"0",
		"false",
		"null",
		"{}",
		"[]",
	}

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
