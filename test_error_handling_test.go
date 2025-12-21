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
	tmp := t.TempDir()

	emptyFile := filepath.Join(tmp, "empty.json")
	require.NoError(t, os.WriteFile(emptyFile, []byte(""), 0o600))

	invalidFile := filepath.Join(tmp, "invalid.json")
	require.NoError(t, os.WriteFile(invalidFile, []byte("not-json"), 0o600))

	validEmptyObj := filepath.Join(tmp, "empty_obj.json")
	require.NoError(t, os.WriteFile(validEmptyObj, []byte("{}"), 0o600))

	validConfig := filepath.Join(tmp, "valid.json")
	require.NoError(t, os.WriteFile(validConfig, []byte(`{"a":1,"b":"x","nested":{"y":true}}`), 0o600))

	tests := []struct {
		name       string
		path       string
		assertions func(t *testing.T, got map[string]interface{})
	}{
		{
			name: "missing file returns nil map",
			path: filepath.Join(tmp, "nope.json"),
			assertions: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name: "empty path returns nil map",
			path: "",
			assertions: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name: "empty file returns nil map",
			path: emptyFile,
			assertions: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name: "invalid json returns nil map",
			path: invalidFile,
			assertions: func(t *testing.T, got map[string]interface{}) {
				assert.Nil(t, got)
			},
		},
		{
			name: "valid empty object returns empty map",
			path: validEmptyObj,
			assertions: func(t *testing.T, got map[string]interface{}) {
				assert.NotNil(t, got)
				assert.Equal(t, 0, len(got))
			},
		},
		{
			name: "valid json returns populated map",
			path: validConfig,
			assertions: func(t *testing.T, got map[string]interface{}) {
				if assert.NotNil(t, got) {
					av, ok := got["a"]
					assert.True(t, ok)
					if assert.IsType(t, float64(0), av) {
						assert.Equal(t, float64(1), av.(float64))
					}

					bv, ok := got["b"]
					assert.True(t, ok)
					if assert.IsType(t, "", bv) {
						assert.Equal(t, "x", bv.(string))
					}

					nv, ok := got["nested"]
					assert.True(t, ok)
					if assert.NotNil(t, nv) {
						nested, ok := nv.(map[string]interface{})
						if assert.True(t, ok) && assert.NotNil(t, nested) {
							yv, ok := nested["y"]
							assert.True(t, ok)
							if assert.IsType(t, true, yv) {
								assert.Equal(t, true, yv.(bool))
							}
						}
					}
				}
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			got := ReadConfig(tt.path)
			tt.assertions(t, got)
		})
	}
}

func TestWriteLog(t *testing.T) {
	tests := []struct {
		name       string
		setup      func(t *testing.T, dir string)
		message    string
		assertions func(t *testing.T, dir string)
		skipWin    bool
	}{
		{
			name: "creates file if missing but writes nothing (open is read-only)",
			setup: func(t *testing.T, dir string) {
				// no-op
			},
			message: "hello world",
			assertions: func(t *testing.T, dir string) {
				path := filepath.Join(dir, "app.log")
				_, err := os.Stat(path)
				assert.NoError(t, err)
				data, err := os.ReadFile(path)
				require.NoError(t, err)
				assert.Equal(t, 0, len(data), "content should be empty because file is opened without write flag")
			},
		},
		{
			name: "does not append when file exists",
			setup: func(t *testing.T, dir string) {
				require.NoError(t, os.WriteFile(filepath.Join(dir, "app.log"), []byte("old"), 0o644))
			},
			message: "new",
			assertions: func(t *testing.T, dir string) {
				path := filepath.Join(dir, "app.log")
				data, err := os.ReadFile(path)
				require.NoError(t, err)
				assert.Equal(t, "old", string(data))
			},
		},
		{
			name: "empty message still creates file but writes nothing",
			setup: func(t *testing.T, dir string) {
				// ensure no file
			},
			message: "",
			assertions: func(t *testing.T, dir string) {
				path := filepath.Join(dir, "app.log")
				_, err := os.Stat(path)
				assert.NoError(t, err)
				data, err := os.ReadFile(path)
				require.NoError(t, err)
				assert.Equal(t, "", string(data))
			},
		},
		{
			name: "non-writable directory prevents file creation",
			setup: func(t *testing.T, dir string) {
				require.NoError(t, os.Chmod(dir, 0o555))
				t.Cleanup(func() {
					_ = os.Chmod(dir, 0o755)
				})
			},
			message: "msg",
			assertions: func(t *testing.T, dir string) {
				_, err := os.Stat(filepath.Join(dir, "app.log"))
				assert.Error(t, err, "file should not exist when directory not writable")
			},
			skipWin: runtime.GOOS == "windows",
		},
		{
			name: "existing read-only file remains unchanged",
			setup: func(t *testing.T, dir string) {
				path := filepath.Join(dir, "app.log")
				require.NoError(t, os.WriteFile(path, []byte("ro"), 0o444))
				t.Cleanup(func() {
					_ = os.Chmod(path, 0o644)
				})
			},
			message: "ignored",
			assertions: func(t *testing.T, dir string) {
				path := filepath.Join(dir, "app.log")
				data, err := os.ReadFile(path)
				require.NoError(t, err)
				assert.Equal(t, "ro", string(data))
			},
			skipWin: runtime.GOOS == "windows",
		},
	}

	for _, tt := range tests {
		tt := tt
		if tt.skipWin {
			continue
		}
		t.Run(tt.name, func(t *testing.T) {
			tmp := t.TempDir()
			orig, err := os.Getwd()
			require.NoError(t, err)
			require.NoError(t, os.Chdir(tmp))
			t.Cleanup(func() {
				_ = os.Chdir(orig)
			})

			if tt.setup != nil {
				tt.setup(t, tmp)
			}

			WriteLog(tt.message)

			if tt.assertions != nil {
				tt.assertions(t, tmp)
			}
		})
	}
}

func TestProcessData(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		want       string
		wantPanics bool
	}{
		{name: "non-empty string returns same", input: "hello", want: "hello"},
		{name: "whitespace preserved", input: "  world  ", want: "  world  "},
		{name: "unicode preserved", input: "🙂 unicode", want: "🙂 unicode"},
		{name: "numeric string", input: "12345", want: "12345"},
		{name: "special characters", input: "!@#$%^&*()", want: "!@#$%^&*()"},
		{name: "single space not empty", input: " ", want: " "},
		{name: "very long string", input: strings.Repeat("a", 1024), want: strings.Repeat("a", 1024)},
		{name: "empty string panics", input: "", wantPanics: true},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanics {
				assert.Panics(t, func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
			assert.Equal(t, len(tt.input), len(got))
		})
	}
}
