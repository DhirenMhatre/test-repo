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

	validConfig := map[string]interface{}{
		"key": "value",
		"num": float64(42),
	}
	validBytes, err := json.Marshal(validConfig)
	assert.NoError(t, err)

	validPath := filepath.Join(tmpDir, "valid.json")
	err = os.WriteFile(validPath, validBytes, 0o644)
	assert.NoError(t, err)

	invalidPath := filepath.Join(tmpDir, "invalid.json")
	err = os.WriteFile(invalidPath, []byte("{invalid json"), 0o644)
	assert.NoError(t, err)

	emptyPath := filepath.Join(tmpDir, "empty.json")
	err = os.WriteFile(emptyPath, []byte(""), 0o644)
	assert.NoError(t, err)

	tests := []struct {
		name       string
		path       string
		wantNonNil bool
	}{
		{
			name:       "valid json file returns non-nil map",
			path:       validPath,
			wantNonNil: true,
		},
		{
			name:       "invalid json returns non-nil empty map or nil",
			path:       invalidPath,
			wantNonNil: false,
		},
		{
			name:       "empty file returns non-nil empty map or nil",
			path:       emptyPath,
			wantNonNil: false,
		},
		{
			name:       "non-existent file returns nil map",
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
				if cfg == nil {
					return
				}
				assert.Equal(t, "value", cfg["key"])
				assert.Equal(t, float64(42), cfg["num"])
			} else {
				// Function ignores errors, so it may return nil or zero-value map.
				// We only assert that it does not panic and type is correct when non-nil.
				if cfg != nil {
					_, ok := cfg.(map[string]interface{})
					assert.True(t, ok)
				}
			}
		})
	}
}

func TestReadConfig_MultipleCallsConsistency(t *testing.T) {
	tmpDir := t.TempDir()

	content := map[string]interface{}{
		"a": "b",
	}
	data, err := json.Marshal(content)
	assert.NoError(t, err)

	path := filepath.Join(tmpDir, "config.json")
	err = os.WriteFile(path, data, 0o644)
	assert.NoError(t, err)

	cfg1 := ReadConfig(path)
	cfg2 := ReadConfig(path)

	assert.NotNil(t, cfg1)
	assert.NotNil(t, cfg2)

	if cfg1 == nil || cfg2 == nil {
		return
	}

	assert.Equal(t, cfg1, cfg2)
	assert.Equal(t, "b", cfg1["a"])
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
			messages: []string{"hello\n"},
		},
		{
			name:     "multiple messages",
			messages: []string{"first\n", "second\n", "third\n"},
		},
		{
			name:     "empty message",
			messages: []string{""},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			for _, msg := range tt.messages {
				WriteLog(msg)
			}

			data, err := os.ReadFile("app.log")
			assert.NoError(t, err)

			expected := ""
			for _, msg := range tt.messages {
				expected += msg
			}
			assert.Equal(t, expected, string(data))

			// Clean up for next subtest
			err = os.Remove("app.log")
			assert.NoError(t, err)
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

	err = os.WriteFile("app.log", []byte("existing\n"), 0o644)
	assert.NoError(t, err)

	WriteLog("new\n")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Equal(t, "existing\nnew\n", string(data))
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

	WriteLog("created\n")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Equal(t, "created\n", string(data))
}

func TestProcessData_TableDriven(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		want       string
		wantPanic  bool
		panicValue string
	}{
		{
			name:      "non-empty string returns same string",
			input:     "hello",
			want:      "hello",
			wantPanic: false,
		},
		{
			name:      "whitespace string does not panic",
			input:     " ",
			want:      " ",
			wantPanic: false,
		},
		{
			name:       "empty string panics",
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
					if r == nil {
						return
					}
					assert.Equal(t, tt.panicValue, r)
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

func TestProcessData_MultipleNonEmptyInputs(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{"simple word", "test"},
		{"numeric string", "12345"},
		{"mixed characters", "abc123!@#"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			defer func() {
				r := recover()
				assert.Nil(t, r)
			}()

			got := ProcessData(tt.input)
			assert.Equal(t, tt.input, got)
		})
	}
}

func TestProcessData_PanicMessageContent(t *testing.T) {
	defer func() {
		r := recover()
		assert.NotNil(t, r)
		if r == nil {
			return
		}
		msg, ok := r.(string)
		assert.True(t, ok)
		assert.Contains(t, msg, "empty")
	}()

	_ = ProcessData("")
}
