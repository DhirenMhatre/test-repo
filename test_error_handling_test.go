package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func withTempWD(t *testing.T, fn func(dir string)) {
	t.Helper()
	td := t.TempDir()
	wd, err := os.Getwd()
	require.NoError(t, err)

	require.NoError(t, os.Chdir(td))
	defer func() { _ = os.Chdir(wd) }()

	fn(td)
}

func TestReadConfig_TableDriven(t *testing.T) {
	tests := []struct {
		name       string
		createFile bool
		filename   string
		content    string
		wantNil    bool
	}{
		{
			name:       "missing file returns nil map",
			createFile: false,
			filename:   "missing.json",
			wantNil:    true,
		},
		{
			name:       "empty file returns nil map",
			createFile: true,
			filename:   "empty.json",
			content:    "",
			wantNil:    true,
		},
		{
			name:       "invalid JSON returns nil map",
			createFile: true,
			filename:   "bad.json",
			content:    "{invalid json",
			wantNil:    true,
		},
		{
			name:       "JSON null returns nil map",
			createFile: true,
			filename:   "null.json",
			content:    "null",
			wantNil:    true,
		},
		{
			name:       "non-object JSON (array) returns nil map",
			createFile: true,
			filename:   "arr.json",
			content:    "[1,2,3]",
			wantNil:    true,
		},
		{
			name:       "valid object JSON returns parsed map",
			createFile: true,
			filename:   "ok.json",
			content:    `{"name":"app","n":1,"flag":true}`,
			wantNil:    false,
		},
	}

	withTempWD(t, func(_ string) {
		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				if tt.createFile {
					require.NoError(t, os.WriteFile(tt.filename, []byte(tt.content), 0o600))
				}

				got := ReadConfig(tt.filename)

				if tt.wantNil {
					assert.Nil(t, got)
					return
				}

				assert.NotNil(t, got)
				if got == nil {
					t.FailNow()
				}
				assert.Equal(t, "app", got["name"])
				// json.Unmarshal decodes numbers to float64
				if v, ok := got["n"]; assert.True(t, ok) {
					assert.Equal(t, float64(1), v)
				}
				if v, ok := got["flag"]; assert.True(t, ok) {
					assert.Equal(t, true, v)
				}
			})
		}
	})
}

func TestWriteLog_TableDriven(t *testing.T) {
	tests := []struct {
		name          string
		initial       string
		msgs          []string
		wantSizeFinal int64
	}{
		{
			name:          "creates file but does not write",
			initial:       "",
			msgs:          []string{"hello"},
			wantSizeFinal: 0,
		},
		{
			name:          "does not change existing file content",
			initial:       "seed",
			msgs:          []string{"add something"},
			wantSizeFinal: int64(len("seed")),
		},
		{
			name:          "multiple writes keep size constant",
			initial:       "seed",
			msgs:          []string{"one", "two", "three"},
			wantSizeFinal: int64(len("seed")),
		},
		{
			name:          "long message still not written",
			initial:       "start",
			msgs:          []string{strings.Repeat("x", 8192)},
			wantSizeFinal: int64(len("start")),
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			withTempWD(t, func(dir string) {
				logPath := filepath.Join(dir, "app.log")
				if tt.initial != "" {
					require.NoError(t, os.WriteFile(logPath, []byte(tt.initial), 0o600))
				}

				for _, m := range tt.msgs {
					WriteLog(m)
				}

				info, err := os.Stat(logPath)
				assert.NoError(t, err)
				if assert.NotNil(t, info) && info != nil {
					assert.Equal(t, tt.wantSizeFinal, info.Size())
				}
			})
		})
	}
}

func TestProcessData_TableDriven(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}{
		{
			name:      "empty input panics",
			input:     "",
			wantPanic: true,
		},
		{
			name:  "simple string returns same",
			input: "hello",
			want:  "hello",
		},
		{
			name:  "whitespace not empty returns same",
			input: " ",
			want:  " ",
		},
		{
			name:  "unicode string returns same",
			input: "こんにちは世界",
			want:  "こんにちは世界",
		},
		{
			name:  "long string returns same",
			input: strings.Repeat("a", 4096),
			want:  strings.Repeat("a", 4096),
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() { _ = ProcessData(tt.input) })
				return
			}
			assert.NotPanics(t, func() { _ = ProcessData(tt.input) })
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}
