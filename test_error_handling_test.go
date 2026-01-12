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
		wantNonNil bool
	}{
		{
			name:       "valid JSON file returns non-nil map",
			path:       validConfigPath,
			wantNonNil: true,
		},
		{
			name:       "invalid JSON still returns non-nil map (error ignored)",
			path:       invalidJSONPath,
			wantNonNil: true,
		},
		{
			name:       "empty file returns non-nil map (unmarshal on empty slice)",
			path:       emptyFilePath,
			wantNonNil: true,
		},
		{
			name:       "non-existent file returns nil map (read error ignored, nil slice)",
			path:       nonExistentPath,
			wantNonNil: false,
		},
		{
			name:       "empty path returns nil map (read error ignored)",
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
				// For valid JSON, ensure content is actually unmarshaled
				if tt.path == validConfigPath {
					assert.Equal(t, "value", cfg["key"])
					// JSON numbers unmarshal as float64 by default
					num, ok := cfg["number"].(float64)
					assert.True(t, ok)
					if ok {
						assert.Equal(t, float64(42), num)
					}
				}
			} else {
				assert.Nil(t, cfg)
			}
		})
	}
}

func TestReadConfig_MultipleCallsIndependence(t *testing.T) {
	tmpDir := t.TempDir()

	path1 := filepath.Join(tmpDir, "config1.json")
	path2 := filepath.Join(tmpDir, "config2.json")

	err := os.WriteFile(path1, []byte(`{"a":1}`), 0o644)
	assert.NoError(t, err)
	err = os.WriteFile(path2, []byte(`{"b":2}`), 0o644)
	assert.NoError(t, err)

	cfg1 := ReadConfig(path1)
	cfg2 := ReadConfig(path2)

	assert.NotNil(t, cfg1)
	assert.NotNil(t, cfg2)

	if cfg1 == nil || cfg2 == nil {
		t.Fatalf("configs should not be nil")
	}

	_, hasA := cfg1["a"]
	_, hasB := cfg1["b"]
	assert.True(t, hasA)
	assert.False(t, hasB)

	_, hasA2 := cfg2["a"]
	_, hasB2 := cfg2["b"]
	assert.False(t, hasA2)
	assert.True(t, hasB2)
}

func TestReadConfig_UnmarshalBehaviorMatchesStdlib(t *testing.T) {
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "config.json")
	content := `{"flag":true,"list":[1,2,3]}`
	err := os.WriteFile(path, []byte(content), 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)
	if cfg == nil {
		return
	}

	var expected map[string]interface{}
	err = json.Unmarshal([]byte(content), &expected)
	assert.NoError(t, err)

	assert.Equal(t, expected, cfg)
}

func TestWriteLog_TableDriven(t *testing.T) {
	tmpDir := t.TempDir()
	logPath := filepath.Join(tmpDir, "app.log")

	origWd, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWd)
	}()

	tests := []struct {
		name        string
		message     string
		repeat      int
		expectExist bool
	}{
		{
			name:        "single write creates file with message",
			message:     "hello\n",
			repeat:      1,
			expectExist: true,
		},
		{
			name:        "multiple writes append to same file",
			message:     "line\n",
			repeat:      3,
			expectExist: true,
		},
		{
			name:        "empty message still creates file",
			message:     "",
			repeat:      1,
			expectExist: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		_ = os.Remove(logPath)

		t.Run(tt.name, func(t *testing.T) {
			for i := 0; i < tt.repeat; i++ {
				WriteLog(tt.message)
			}

			_, statErr := os.Stat(logPath)
			if tt.expectExist {
				assert.NoError(t, statErr)
				if statErr != nil {
					return
				}
				data, readErr := os.ReadFile(logPath)
				assert.NoError(t, readErr)
				if readErr != nil {
					return
				}
				expected := ""
				for i := 0; i < tt.repeat; i++ {
					expected += tt.message
				}
				assert.Equal(t, expected, string(data))
			} else {
				assert.Error(t, statErr)
			}
		})
	}
}

func TestWriteLog_AppendsWithoutTruncation(t *testing.T) {
	tmpDir := t.TempDir()
	logPath := filepath.Join(tmpDir, "app.log")

	origWd, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWd)
	}()

	initialContent := "initial\n"
	err = os.WriteFile(logPath, []byte(initialContent), 0o644)
	assert.NoError(t, err)

	WriteLog("first\n")
	WriteLog("second\n")

	data, err := os.ReadFile(logPath)
	assert.NoError(t, err)
	if err != nil {
		return
	}

	assert.Equal(t, "initial\nfirst\nsecond\n", string(data))
}

func TestWriteLog_FilePermissionsAndCreation(t *testing.T) {
	tmpDir := t.TempDir()
	logPath := filepath.Join(tmpDir, "app.log")

	origWd, err := os.Getwd()
	assert.NoError(t, err)

	err = os.Chdir(tmpDir)
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWd)
	}()

	WriteLog("test\n")

	info, err := os.Stat(logPath)
	assert.NoError(t, err)
	if err != nil {
		return
	}

	mode := info.Mode().Perm()
	assert.Equal(t, os.FileMode(0o644), mode)
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
			name:        "empty string panics",
			input:       "",
			wantPanic:   true,
			panicSubstr: "empty input",
		},
		{
			name:        "explicit empty string panics with exact message",
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
					if r == nil {
						return
					}
					msg, ok := r.(string)
					if ok {
						assert.Contains(t, msg, tt.panicSubstr)
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
	for _, in := range inputs {
		out := ProcessData(in)
		assert.Equal(t, in, out)
	}
}

func TestProcessData_PanicDoesNotAffectSubsequentCalls(t *testing.T) {
	defer func() {
		_ = recover()
	}()

	func() {
		defer func() {
			_ = recover()
		}()
		_ = ProcessData("")
	}()

	result := ProcessData("after panic")
	assert.Equal(t, "after panic", result)
}
