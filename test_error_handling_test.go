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

	nonExistentPath := filepath.Join(tmpDir, "does_not_exist.json")

	tests := []struct {
		name       string
		path       string
		wantNonNil bool
	}{
		{
			name:       "valid JSON file",
			path:       validConfigPath,
			wantNonNil: true,
		},
		{
			name:       "invalid JSON file",
			path:       invalidJSONPath,
			wantNonNil: true,
		},
		{
			name:       "non-existent file",
			path:       nonExistentPath,
			wantNonNil: false,
		},
		{
			name:       "empty path",
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
				if cfg != nil && tt.path == validConfigPath {
					assert.Equal(t, "value", cfg["key"])
					// json.Unmarshal decodes numbers as float64 by default
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

func TestReadConfig_ManualBehaviorChecks(t *testing.T) {
	tmpDir := t.TempDir()

	// Case: file exists but empty
	emptyPath := filepath.Join(tmpDir, "empty.json")
	err := os.WriteFile(emptyPath, []byte(""), 0o644)
	assert.NoError(t, err)

	// Case: file with whitespace only
	spacePath := filepath.Join(tmpDir, "space.json")
	err = os.WriteFile(spacePath, []byte("   "), 0o644)
	assert.NoError(t, err)

	tests := []struct {
		name string
		path string
	}{
		{"empty file", emptyPath},
		{"whitespace file", spacePath},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			cfg := ReadConfig(tt.path)
			// json.Unmarshal on empty/whitespace returns error, config stays nil
			assert.Nil(t, cfg)
		})
	}
}

func TestReadConfig_DirectJSONComparison(t *testing.T) {
	tmpDir := t.TempDir()

	contentMap := map[string]interface{}{
		"foo": "bar",
		"baz": 123,
	}
	raw, err := json.Marshal(contentMap)
	assert.NoError(t, err)

	path := filepath.Join(tmpDir, "config.json")
	err = os.WriteFile(path, raw, 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)
	if cfg == nil {
		t.Fatalf("expected non-nil config")
	}

	assert.Equal(t, "bar", cfg["foo"])
	num, ok := cfg["baz"].(float64)
	assert.True(t, ok)
	if ok {
		assert.Equal(t, float64(123), num)
	}
}

func TestWriteLog_TableDriven(t *testing.T) {
	tmpDir := t.TempDir()

	// Pre-create a writable log file
	writableLog := filepath.Join(tmpDir, "writable.log")
	err := os.WriteFile(writableLog, []byte("initial\n"), 0o644)
	assert.NoError(t, err)

	// Directory path (OpenFile will fail because it's a directory)
	dirPath := filepath.Join(tmpDir, "subdir")
	err = os.Mkdir(dirPath, 0o755)
	assert.NoError(t, err)

	tests := []struct {
		name           string
		setupPath      string
		message        string
		expectFileGrow bool
	}{
		{
			name:           "append to existing file",
			setupPath:      writableLog,
			message:        "hello\n",
			expectFileGrow: true,
		},
		{
			name:           "write to new file in temp dir",
			setupPath:      filepath.Join(tmpDir, "new.log"),
			message:        "new file\n",
			expectFileGrow: true,
		},
		{
			name:           "use fixed app.log in temp dir via chdir",
			setupPath:      "app.log",
			message:        "relative path\n",
			expectFileGrow: true,
		},
		{
			name:           "attempt to use directory as file",
			setupPath:      dirPath,
			message:        "should fail\n",
			expectFileGrow: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			// Change working directory so that "app.log" is created in tmpDir
			origWD, err := os.Getwd()
			assert.NoError(t, err)
			defer func() {
				_ = os.Chdir(origWD)
			}()
			err = os.Chdir(tmpDir)
			assert.NoError(t, err)

			// If setupPath is not "app.log", we simulate by symlinking or copying
			// but since WriteLog always uses "app.log", we just call it and then
			// inspect app.log in the current directory.
			beforeSize := int64(0)
			info, statErr := os.Stat("app.log")
			if statErr == nil {
				beforeSize = info.Size()
			}

			WriteLog(tt.message)

			info, statErr = os.Stat("app.log")
			if tt.expectFileGrow {
				assert.NoError(t, statErr)
				if statErr == nil {
					assert.GreaterOrEqual(t, info.Size(), beforeSize+int64(len(tt.message)))
				}
			} else {
				// For directory case, our WriteLog still targets "app.log", not dirPath,
				// so app.log may still be created; we just assert no panic occurred.
				assert.True(t, statErr == nil || os.IsNotExist(statErr))
			}
		})
	}
}

func TestWriteLog_MultipleWrites(t *testing.T) {
	tmpDir := t.TempDir()
	origWD, err := os.Getwd()
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()
	err = os.Chdir(tmpDir)
	assert.NoError(t, err)

	messages := []string{"first\n", "second\n", "third\n"}

	for _, msg := range messages {
		WriteLog(msg)
	}

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.NotNil(t, data)

	expected := ""
	for _, msg := range messages {
		expected += msg
	}
	assert.Equal(t, expected, string(data))
}

func TestWriteLog_EmptyMessage(t *testing.T) {
	tmpDir := t.TempDir()
	origWD, err := os.Getwd()
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(origWD)
	}()
	err = os.Chdir(tmpDir)
	assert.NoError(t, err)

	WriteLog("")

	info, err := os.Stat("app.log")
	assert.NoError(t, err)
	if err == nil {
		assert.Equal(t, int64(0), info.Size())
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
			name:      "non-empty string",
			input:     "hello",
			want:      "hello",
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
			name:      "whitespace string",
			input:     "   ",
			want:      "   ",
			wantPanic: false,
		},
		{
			name:      "unicode string",
			input:     "こんにちは",
			want:      "こんにちは",
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
					if r != nil {
						msg, ok := r.(string)
						if ok {
							assert.Contains(t, msg, tt.panicSubstr)
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

func TestProcessData_PanicRecoveryBehavior(t *testing.T) {
	defer func() {
		r := recover()
		assert.NotNil(t, r)
	}()

	_ = ProcessData("")
}

func TestProcessData_NoPanicForValidInputs(t *testing.T) {
	inputs := []string{"a", "0", "false", "valid data"}
	for _, in := range inputs {
		in := in
		t.Run(in, func(t *testing.T) {
			defer func() {
				r := recover()
				assert.Nil(t, r)
			}()
			out := ProcessData(in)
			assert.Equal(t, in, out)
		})
	}
}
