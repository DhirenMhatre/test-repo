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
			name:       "valid json file returns non-nil map",
			path:       validConfigPath,
			wantNonNil: true,
		},
		{
			name:       "invalid json file returns non-nil map (current impl ignores error)",
			path:       invalidJSONPath,
			wantNonNil: true,
		},
		{
			name:       "empty file returns non-nil map (current impl ignores error)",
			path:       emptyFilePath,
			wantNonNil: true,
		},
		{
			name:       "directory path returns non-nil map (current impl ignores error)",
			path:       tmpDir,
			wantNonNil: true,
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

	configPath := filepath.Join(tmpDir, "config.json")
	content := map[string]interface{}{
		"stringKey": "value",
		"intKey":    10,
		"boolKey":   true,
	}
	raw, err := json.Marshal(content)
	assert.NoError(t, err)

	err = os.WriteFile(configPath, raw, 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(configPath)
	assert.NotNil(t, cfg)

	assert.Equal(t, "value", cfg["stringKey"])
	assert.EqualValues(t, 10, cfg["intKey"])
	assert.Equal(t, true, cfg["boolKey"])
}

func TestWriteLog_TableDriven(t *testing.T) {
	tmpDir := t.TempDir()

	tests := []struct {
		name        string
		setup       func() string
		message     string
		expectWrite bool
	}{
		{
			name: "write to default app.log in temp dir via chdir",
			setup: func() string {
				origWD, err := os.Getwd()
				assert.NoError(t, err)

				err = os.Chdir(tmpDir)
				assert.NoError(t, err)

				t.Cleanup(func() {
					_ = os.Chdir(origWD)
				})

				return filepath.Join(tmpDir, "app.log")
			},
			message:     "hello world",
			expectWrite: true,
		},
		{
			name: "write empty message",
			setup: func() string {
				origWD, err := os.Getwd()
				assert.NoError(t, err)

				err = os.Chdir(tmpDir)
				assert.NoError(t, err)

				t.Cleanup(func() {
					_ = os.Chdir(origWD)
				})

				return filepath.Join(tmpDir, "app.log")
			},
			message:     "",
			expectWrite: true,
		},
		{
			name: "invalid working directory path still results in no panic",
			setup: func() string {
				origWD, err := os.Getwd()
				assert.NoError(t, err)

				nonexistent := filepath.Join(tmpDir, "nonexistent-dir")
				_ = os.Chdir(nonexistent)

				t.Cleanup(func() {
					_ = os.Chdir(origWD)
				})

				return filepath.Join(nonexistent, "app.log")
			},
			message:     "test",
			expectWrite: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			logPath := tt.setup()

			assert.NotPanics(t, func() {
				WriteLog(tt.message)
			})

			data, err := os.ReadFile(logPath)
			if tt.expectWrite {
				assert.NoError(t, err)
				assert.Contains(t, string(data), tt.message)
			} else {
				assert.Error(t, err)
			}
		})
	}
}

func TestWriteLog_MultipleWritesAppend(t *testing.T) {
	tmpDir := t.TempDir()

	origWD, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)

	t.Cleanup(func() {
		_ = os.Chdir(origWD)
	})

	WriteLog("first\n")
	WriteLog("second\n")
	WriteLog("third\n")

	data, err := os.ReadFile(filepath.Join(tmpDir, "app.log"))
	assert.NoError(t, err)
	content := string(data)

	assert.Contains(t, content, "first\n")
	assert.Contains(t, content, "second\n")
	assert.Contains(t, content, "third\n")
}

func TestProcessData_TableDriven(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		want      string
		wantPanic bool
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
			name:      "single character string",
			input:     "a",
			want:      "a",
			wantPanic: false,
		},
		{
			name:      "empty string panics",
			input:     "",
			want:      "",
			wantPanic: true,
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
				assert.Panics(t, func() {
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

func TestProcessData_IdempotentBehavior(t *testing.T) {
	inputs := []string{
		"alpha",
		"beta",
		"gamma",
		"delta",
	}

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

func TestProcessData_PanicMessage(t *testing.T) {
	assert.PanicsWithValue(t, "empty input", func() {
		_ = ProcessData("")
	})
}
