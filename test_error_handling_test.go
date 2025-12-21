package main

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	dir := t.TempDir()

	validPath := filepath.Join(dir, "valid.json")
	require.NoError(t, os.WriteFile(validPath, []byte(`{"a":1,"b":"x","ok":true}`), 0o600))

	emptyPath := filepath.Join(dir, "empty.json")
	require.NoError(t, os.WriteFile(emptyPath, []byte(``), 0o600))

	malformedPath := filepath.Join(dir, "malformed.json")
	require.NoError(t, os.WriteFile(malformedPath, []byte(`{this is not valid json`), 0o600))

	permDeniedPath := filepath.Join(dir, "denied.json")
	require.NoError(t, os.WriteFile(permDeniedPath, []byte(`{"k":"v"}`), 0o600))
	// Change permission to none, only meaningful on Unix-like systems
	if runtime.GOOS != "windows" {
		require.NoError(t, os.Chmod(permDeniedPath, 0o000))
	}

	tests := []struct {
		name          string
		path          string
		expectNil     bool
		expectKeys    map[string]interface{}
		skipOnWindows bool
	}{
		{
			name:      "NonexistentFile_ReturnsNil",
			path:      filepath.Join(dir, "does_not_exist.json"),
			expectNil: true,
		},
		{
			name:      "EmptyFile_ReturnsNil",
			path:      emptyPath,
			expectNil: true,
		},
		{
			name:      "MalformedJSON_ReturnsNil",
			path:      malformedPath,
			expectNil: true,
		},
		{
			name:      "DirectoryPath_ReturnsNil",
			path:      dir,
			expectNil: true,
		},
		{
			name:      "ValidJSON_ReturnsMap",
			path:      validPath,
			expectNil: false,
			expectKeys: map[string]interface{}{
				"a":  float64(1), // numbers decode to float64
				"b":  "x",
				"ok": true,
			},
		},
		{
			name:          "PermissionDenied_ReturnsNil",
			path:          permDeniedPath,
			expectNil:     true,
			skipOnWindows: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.skipOnWindows && runtime.GOOS == "windows" {
				t.Skip("Skipping permission-based test on Windows")
			}
			got := ReadConfig(tt.path)
			if tt.expectNil {
				assert.Nil(t, got)
				return
			}
			assert.NotNil(t, got)
			for k, v := range tt.expectKeys {
				val, ok := got[k]
				assert.True(t, ok, "expected key %q", k)
				assert.Equal(t, v, val)
			}
		})
	}
}

func TestWriteLog(t *testing.T) {
	tests := []struct {
		name          string
		setup         func(t *testing.T) (workDir string, expectExists bool, expectContent string, message string)
		expectPanic   bool
		skipOnWindows bool
	}{
		{
			name: "WritableDir_NewFileCreatedButEmpty",
			setup: func(t *testing.T) (string, bool, string, string) {
				wd := t.TempDir()
				return wd, true, "", "hello world"
			},
			expectPanic:   false,
			skipOnWindows: runtime.GOOS == "windows", // avoid leaking open file handle on Windows
		},
		{
			name: "WritableDir_PreExistingFileRemainsUnchanged",
			setup: func(t *testing.T) (string, bool, string, string) {
				wd := t.TempDir()
				path := filepath.Join(wd, "app.log")
				require.NoError(t, os.WriteFile(path, []byte("start"), 0o600))
				return wd, true, "start", "append attempt"
			},
			expectPanic:   false,
			skipOnWindows: runtime.GOOS == "windows", // avoid leaking open file handle on Windows
		},
		{
			name: "ReadOnlyDir_CreateFails_PanicsAndNoFile",
			setup: func(t *testing.T) (string, bool, string, string) {
				wd := t.TempDir()
				require.NoError(t, os.Chmod(wd, 0o500)) // read/execute only, no write -> cannot create file
				return wd, false, "", "msg"
			},
			expectPanic:   true,
			skipOnWindows: runtime.GOOS == "windows",
		},
		{
			name: "ExistingFile_NoPermissions_PanicsAndUnchanged",
			setup: func(t *testing.T) (string, bool, string, string) {
				wd := t.TempDir()
				path := filepath.Join(wd, "app.log")
				require.NoError(t, os.WriteFile(path, []byte("locked"), 0o600))
				require.NoError(t, os.Chmod(path, 0o000))
				return wd, true, "locked", "blocked write"
			},
			expectPanic:   true,
			skipOnWindows: runtime.GOOS == "windows",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.skipOnWindows {
				t.Skip("Skipping test on Windows due to differing file semantics")
			}
			origWD, err := os.Getwd()
			require.NoError(t, err)
			workDir, expectExists, expectContent, msg := tt.setup(t)
			require.NoError(t, os.Chdir(workDir))
			defer func() {
				_ = os.Chmod(filepath.Join(workDir, "app.log"), 0o600)
				_ = os.Chdir(origWD)
			}()

			logPath := filepath.Join(workDir, "app.log")
			if tt.expectPanic {
				assert.Panics(t, func() {
					WriteLog(msg)
				})
			} else {
				assert.NotPanics(t, func() {
					WriteLog(msg)
				})
			}

			_, statErr := os.Stat(logPath)
			if expectExists {
				assert.NoError(t, statErr, "expected app.log to exist")
				data, rErr := os.ReadFile(logPath)
				assert.NoError(t, rErr)
				assert.Equal(t, expectContent, string(data))
			} else {
				assert.True(t, os.IsNotExist(statErr), "expected app.log to not exist")
			}
		})
	}
}

func TestProcessData(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		want       string
		wantPanic  bool
		panicValue interface{}
	}{
		{
			name:  "NonEmpty_ReturnsSame",
			input: "hello",
			want:  "hello",
		},
		{
			name:  "Whitespace_ReturnsSame",
			input: "   ",
			want:  "   ",
		},
		{
			name:  "Unicode_ReturnsSame",
			input: "こんにちは世界",
			want:  "こんにちは世界",
		},
		{
			name: "VeryLong_ReturnsSame",
			input: func() string {
				s := ""
				for i := 0; i < 5000; i++ {
					s += "x"
				}
				return s
			}(),
			want: func() string {
				s := ""
				for i := 0; i < 5000; i++ {
					s += "x"
				}
				return s
			}(),
		},
		{
			name:       "Empty_Panics",
			input:      "",
			wantPanic:  true,
			panicValue: "empty input",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				if tt.panicValue != nil {
					assert.PanicsWithValue(t, tt.panicValue, func() { _ = ProcessData(tt.input) })
				} else {
					assert.Panics(t, func() { _ = ProcessData(tt.input) })
				}
				return
			}
			var got string
			assert.NotPanics(t, func() { got = ProcessData(tt.input) })
			assert.Equal(t, tt.want, got)
		})
	}
}
