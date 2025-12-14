package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	t.Parallel()

	t.Run("various inputs", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()

		// Prepare files
		nonexistent := filepath.Join(dir, "no_such_file.json")

		invalid := filepath.Join(dir, "invalid.json")
		require.NoError(t, os.WriteFile(invalid, []byte("{invalid json"), 0o644))

		emptyFile := filepath.Join(dir, "empty.json")
		require.NoError(t, os.WriteFile(emptyFile, []byte(""), 0o644))

		emptyObject := filepath.Join(dir, "empty_object.json")
		require.NoError(t, os.WriteFile(emptyObject, []byte("{}"), 0o644))

		valid := filepath.Join(dir, "valid.json")
		require.NoError(t, os.WriteFile(valid, []byte(`{"a":1,"b":"x","nested":{"k":"v"}}`), 0o644))

		wrongTopLevel := filepath.Join(dir, "array.json")
		require.NoError(t, os.WriteFile(wrongTopLevel, []byte(`[]`), 0o644))

		tests := []struct {
			name     string
			path     string
			validate func(t *testing.T, got map[string]interface{})
		}{
			{
				name: "nonexistent file returns nil map",
				path: nonexistent,
				validate: func(t *testing.T, got map[string]interface{}) {
					assert.Nil(t, got)
				},
			},
			{
				name: "invalid JSON returns nil map",
				path: invalid,
				validate: func(t *testing.T, got map[string]interface{}) {
					assert.Nil(t, got)
				},
			},
			{
				name: "empty file returns nil map",
				path: emptyFile,
				validate: func(t *testing.T, got map[string]interface{}) {
					assert.Nil(t, got)
				},
			},
			{
				name: "empty object returns non-nil empty map",
				path: emptyObject,
				validate: func(t *testing.T, got map[string]interface{}) {
					assert.NotNil(t, got)
					assert.Len(t, got, 0)
				},
			},
			{
				name: "valid JSON returns parsed map",
				path: valid,
				validate: func(t *testing.T, got map[string]interface{}) {
					assert.NotNil(t, got)
					assert.Equal(t, float64(1), got["a"])
					assert.Equal(t, "x", got["b"])

					nestedVal, ok := got["nested"]
					assert.True(t, ok)
					nested, ok := nestedVal.(map[string]interface{})
					assert.True(t, ok)
					if assert.NotNil(t, nested) {
						assert.Equal(t, "v", nested["k"])
					}
				},
			},
			{
				name: "wrong top-level JSON type returns nil map",
				path: wrongTopLevel,
				validate: func(t *testing.T, got map[string]interface{}) {
					assert.Nil(t, got)
				},
			},
		}

		for _, tt := range tests {
			tt := tt
			t.Run(tt.name, func(t *testing.T) {
				t.Parallel()
				got := ReadConfig(tt.path)
				tt.validate(t, got)
			})
		}
	})
}

func TestWriteLog(t *testing.T) {
	// Do not run in parallel; this test changes process working directory.
	// Each subtest uses its own temp dir to avoid interference.

	tests := []struct {
		name     string
		setup    func(t *testing.T, dir string)
		testFunc func(t *testing.T, dir string)
	}{
		{
			name: "creates file but writes nothing due to read-only open flags",
			setup: func(t *testing.T, dir string) {
				// nothing
				_ = dir
			},
			testFunc: func(t *testing.T, dir string) {
				origWD, err := os.Getwd()
				require.NoError(t, err)
				require.NoError(t, os.Chdir(dir))
				t.Cleanup(func() { _ = os.Chdir(origWD) })

				WriteLog("hello world")

				fi, statErr := os.Stat(filepath.Join(dir, "app.log"))
				assert.NoError(t, statErr)
				if assert.NotNil(t, fi) {
					assert.Equal(t, int64(0), fi.Size(), "expected zero bytes written")
				}
			},
		},
		{
			name: "multiple calls do not append anything",
			setup: func(t *testing.T, dir string) {
				// nothing
				_ = dir
			},
			testFunc: func(t *testing.T, dir string) {
				origWD, err := os.Getwd()
				require.NoError(t, err)
				require.NoError(t, os.Chdir(dir))
				t.Cleanup(func() { _ = os.Chdir(origWD) })

				WriteLog("first")
				WriteLog("second")

				fi, statErr := os.Stat(filepath.Join(dir, "app.log"))
				assert.NoError(t, statErr)
				if assert.NotNil(t, fi) {
					assert.Equal(t, int64(0), fi.Size(), "expected zero bytes written after multiple calls")
				}
			},
		},
		{
			name: "panics when app.log is a directory (OpenFile fails, then nil deref on WriteString)",
			setup: func(t *testing.T, dir string) {
				require.NoError(t, os.Mkdir(filepath.Join(dir, "app.log"), 0o755))
			},
			testFunc: func(t *testing.T, dir string) {
				origWD, err := os.Getwd()
				require.NoError(t, err)
				require.NoError(t, os.Chdir(dir))
				t.Cleanup(func() { _ = os.Chdir(origWD) })

				assert.Panics(t, func() { WriteLog("msg") })
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			if tt.setup != nil {
				tt.setup(t, dir)
			}
			tt.testFunc(t, dir)
		})
	}
}

func TestProcessData(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}{
		{
			name:      "returns same non-empty string",
			input:     "hello",
			want:      "hello",
			wantPanic: false,
		},
		{
			name:      "returns whitespace string as-is",
			input:     "   ",
			want:      "   ",
			wantPanic: false,
		},
		{
			name:      "returns unicode string as-is",
			input:     "😀🚀✨",
			want:      "😀🚀✨",
			wantPanic: false,
		},
		{
			name:      "panics on empty input",
			input:     "",
			want:      "",
			wantPanic: true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() { _ = ProcessData(tt.input) })
				return
			}
			assert.NotPanics(t, func() {
				got := ProcessData(tt.input)
				assert.Equal(t, tt.want, got)
			})
		})
	}
}
