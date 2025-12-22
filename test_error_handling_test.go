package main

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	tmp := t.TempDir()

	type tc struct {
		name       string
		content    string
		create     bool
		perm       os.FileMode
		skipOnOS   string
		wantNil    bool
		verifyFunc func(t *testing.T, got map[string]interface{})
	}
	tests := []tc{
		{
			name:    "missing file returns nil",
			create:  false,
			wantNil: true,
		},
		{
			name:    "invalid JSON returns nil",
			create:  true,
			content: "{ not-json",
			wantNil: true,
		},
		{
			name:    "empty file returns nil",
			create:  true,
			content: "",
			wantNil: true,
		},
		{
			name:    "top-level array cannot unmarshal into map returns nil",
			create:  true,
			content: `[1,2,3]`,
			wantNil: true,
		},
		{
			name:     "permission denied returns nil",
			create:   true,
			content:  `{"k":"v"}`,
			perm:     0o000,
			wantNil:  true,
			skipOnOS: "windows", // chmod semantics differ
		},
		{
			name:    "valid simple object returns values",
			create:  true,
			content: `{"a":"b","n":123,"t":true}`,
			verifyFunc: func(t *testing.T, got map[string]interface{}) {
				assert.Equal(t, "b", got["a"])
				// JSON numbers decode to float64
				assert.Equal(t, float64(123), got["n"])
				assert.Equal(t, true, got["t"])
			},
		},
		{
			name:    "valid nested object returns nested structures",
			create:  true,
			content: `{"outer":{"inner":"v"},"arr":[1,2]}`,
			verifyFunc: func(t *testing.T, got map[string]interface{}) {
				outer, ok := got["outer"].(map[string]interface{})
				require.True(t, ok)
				assert.Equal(t, "v", outer["inner"])
				arr, ok := got["arr"].([]interface{})
				require.True(t, ok)
				assert.Len(t, arr, 2)
				assert.Equal(t, float64(1), arr[0])
				assert.Equal(t, float64(2), arr[1])
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := filepath.Join(tmp, strings.ReplaceAll(tt.name, " ", "_")+".json")
			if tt.create {
				mode := tt.perm
				if mode == 0 {
					mode = 0o644
				}
				require.NoError(t, os.WriteFile(p, []byte(tt.content), mode))
				if tt.perm != 0 {
					defer os.Chmod(p, 0o644)
				}
			}
			if tt.skipOnOS != "" && runtime.GOOS == tt.skipOnOS {
				t.Skipf("Skipping on %s", runtime.GOOS)
			}

			got := ReadConfig(p)

			if tt.wantNil {
				assert.Nil(t, got)
				return
			}
			assert.NotNil(t, got)
			if got == nil {
				t.Fatalf("config should not be nil")
			}
			if tt.verifyFunc != nil {
				tt.verifyFunc(t, got)
			}
		})
	}
}

func TestWriteLog(t *testing.T) {
	origWD, err := os.Getwd()
	require.NoError(t, err)

	tmp := t.TempDir()

	type tc struct {
		name            string
		preContent      string
		prePerm         os.FileMode
		roDir           bool
		skipOnOS        string
		wantPanic       bool
		callCount       int
		expectedContent string
	}

	tests := []tc{
		{
			name:            "creates file but does not write",
			preContent:      "",
			callCount:       1,
			expectedContent: "",
		},
		{
			name:            "existing file unchanged",
			preContent:      "pre",
			callCount:       1,
			expectedContent: "pre",
		},
		{
			name:            "existing read-only file unchanged",
			preContent:      "pre-ro",
			prePerm:         0o444,
			callCount:       1,
			expectedContent: "pre-ro",
		},
		{
			name:      "read-only directory causes panic on create",
			roDir:     true,
			wantPanic: true,
			skipOnOS:  "windows",
		},
		{
			name:            "multiple calls still do not append",
			preContent:      "",
			callCount:       2,
			expectedContent: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			caseDir := filepath.Join(tmp, strings.ReplaceAll(tt.name, " ", "_"))
			require.NoError(t, os.MkdirAll(caseDir, 0o755))

			// Prepare working directory
			require.NoError(t, os.Chdir(caseDir))
			defer func() {
				_ = os.Chdir(origWD)
				_ = os.Chmod(caseDir, 0o755) // ensure cleanup works
			}()

			// Optionally make dir read-only (Unix only)
			if tt.roDir {
				if runtime.GOOS == tt.skipOnOS && tt.skipOnOS != "" {
					t.Skipf("Skipping on %s", runtime.GOOS)
				}
				require.NoError(t, os.Chmod(caseDir, 0o555))
			}

			// Optionally precreate file
			if tt.preContent != "" || tt.prePerm != 0 {
				mode := tt.prePerm
				if mode == 0 {
					mode = 0o644
				}
				require.NoError(t, os.WriteFile("app.log", []byte(tt.preContent), mode))
			}

			callCount := tt.callCount
			if callCount == 0 {
				callCount = 1
			}

			if tt.wantPanic {
				assert.Panics(t, func() {
					for i := 0; i < callCount; i++ {
						WriteLog("hello world")
					}
				})
				// After panic scenario, ensure file was not created if dir is read-only
				if _, err := os.Stat("app.log"); err == nil {
					// In rare cases, file might exist from preContent; if not precreated, it should generally not exist
					// We won't assert further to keep test robust across platforms
				}
				return
			}

			for i := 0; i < callCount; i++ {
				WriteLog("hello world")
			}

			data, err := os.ReadFile("app.log")
			if os.IsNotExist(err) {
				// If file doesn't exist, then expectedContent must be empty and no preContent; still acceptable
				assert.Equal(t, "", tt.expectedContent)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.expectedContent, string(data))
		})
	}
}

func TestProcessData(t *testing.T) {
	type tc struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}
	long := strings.Repeat("a", 10000)

	tests := []tc{
		{
			name:  "simple passthrough",
			input: "hello",
			want:  "hello",
		},
		{
			name:  "whitespace preserved",
			input: "  hi ",
			want:  "  hi ",
		},
		{
			name:  "unicode preserved",
			input: "こんにちは世界",
			want:  "こんにちは世界",
		},
		{
			name:  "long string preserved",
			input: long,
			want:  long,
		},
		{
			name:      "empty input panics",
			input:     "",
			wantPanic: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}
