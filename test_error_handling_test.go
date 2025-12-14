package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	t.Run("table-driven", func(t *testing.T) {
		dir := t.TempDir()

		// Prepare files
		validPath := filepath.Join(dir, "valid.json")
		require.NoError(t, os.WriteFile(validPath, []byte(`{"foo":"bar","answer":42}`), 0o644))

		emptyPath := filepath.Join(dir, "empty.json")
		require.NoError(t, os.WriteFile(emptyPath, []byte(``), 0o644))

		malformedPath := filepath.Join(dir, "malformed.json")
		require.NoError(t, os.WriteFile(malformedPath, []byte(`{ not: valid json }`), 0o644))

		emptyObjPath := filepath.Join(dir, "emptyobj.json")
		require.NoError(t, os.WriteFile(emptyObjPath, []byte(`{}`), 0o644))

		nonexistentPath := filepath.Join(dir, "does-not-exist.json")

		tests := []struct {
			name    string
			path    string
			wantNil bool
			check   func(t *testing.T, got map[string]interface{})
		}{
			{
				name:    "non-existent file returns nil map",
				path:    nonexistentPath,
				wantNil: true,
			},
			{
				name: "valid JSON returns populated map",
				path: validPath,
				check: func(t *testing.T, got map[string]interface{}) {
					assert.NotNil(t, got)
					assert.Equal(t, "bar", got["foo"])
					// JSON numbers are float64 by default
					assert.Equal(t, float64(42), got["answer"])
				},
			},
			{
				name:    "empty file returns nil map",
				path:    emptyPath,
				wantNil: true,
			},
			{
				name:    "malformed JSON returns nil map",
				path:    malformedPath,
				wantNil: true,
			},
			{
				name: "empty object returns empty non-nil map",
				path: emptyObjPath,
				check: func(t *testing.T, got map[string]interface{}) {
					assert.NotNil(t, got)
					assert.Equal(t, 0, len(got))
				},
			},
		}

		for _, tt := range tests {
			tt := tt
			t.Run(tt.name, func(t *testing.T) {
				got := ReadConfig(tt.path)
				if tt.wantNil {
					assert.Nil(t, got)
					return
				}
				assert.NotNil(t, got)
				if tt.check != nil {
					tt.check(t, got)
				}
			})
		}
	})
}

func TestWriteLog(t *testing.T) {
	t.Run("table-driven", func(t *testing.T) {
		tests := []struct {
			name           string
			setup          func(t *testing.T, dir string)
			expectExists   bool
			expectContents string
			expectPanic    bool
		}{
			{
				name: "creates file when missing but writes nothing (open read-only)",
				setup: func(t *testing.T, dir string) {
					// Ensure "app.log" does not exist
					_, err := os.Stat(filepath.Join(dir, "app.log"))
					if err == nil {
						require.NoError(t, os.Remove(filepath.Join(dir, "app.log")))
					} else {
						assert.True(t, os.IsNotExist(err))
					}
				},
				expectExists:   true,
				expectContents: "",
			},
			{
				name: "pre-existing file remains unchanged due to read-only open",
				setup: func(t *testing.T, dir string) {
					require.NoError(t, os.WriteFile(filepath.Join(dir, "app.log"), []byte("initial"), 0o644))
				},
				expectExists:   true,
				expectContents: "initial",
			},
			{
				name: "path is a directory and function panics on nil file use",
				setup: func(t *testing.T, dir string) {
					require.NoError(t, os.Mkdir(filepath.Join(dir, "app.log"), 0o755))
				},
				expectPanic: true,
			},
		}

		for _, tt := range tests {
			tt := tt
			t.Run(tt.name, func(t *testing.T) {
				dir := t.TempDir()
				cwd, err := os.Getwd()
				require.NoError(t, err)
				require.NoError(t, os.Chdir(dir))
				defer func() { _ = os.Chdir(cwd) }()

				if tt.setup != nil {
					tt.setup(t, dir)
				}

				if tt.expectPanic {
					assert.Panics(t, func() {
						WriteLog("hello")
					})
					return
				}

				assert.NotPanics(t, func() {
					WriteLog("hello")
				})

				path := filepath.Join(dir, "app.log")
				_, statErr := os.Stat(path)
				if tt.expectExists {
					assert.NoError(t, statErr)
				} else {
					assert.True(t, os.IsNotExist(statErr))
				}

				if tt.expectExists {
					data, readErr := os.ReadFile(path)
					require.NoError(t, readErr)
					assert.Equal(t, tt.expectContents, string(data))
				}
			})
		}
	})
}

func TestProcessData(t *testing.T) {
	t.Run("table-driven", func(t *testing.T) {
		tests := []struct {
			name       string
			input      string
			want       string
			wantPanic  bool
			panicMatch string
		}{
			{"non-empty returns same", "hello", "hello", false, ""},
			{"whitespace allowed", " ", " ", false, ""},
			{"unicode allowed", "🙂 unicode", "🙂 unicode", false, ""},
			{"empty panics", "", "", true, "empty input"},
		}

		for _, tt := range tests {
			tt := tt
			t.Run(tt.name, func(t *testing.T) {
				if tt.wantPanic {
					assert.PanicsWithValue(t, tt.panicMatch, func() {
						_ = ProcessData(tt.input)
					})
					return
				}
				assert.NotPanics(t, func() {
					got := ProcessData(tt.input)
					assert.Equal(t, tt.want, got)
				})
				got := ProcessData(tt.input)
				assert.Equal(t, tt.want, got)
			})
		}
	})
}
