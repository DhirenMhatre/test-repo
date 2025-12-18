package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func withTempWD(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	old, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(dir))
	t.Cleanup(func() { _ = os.Chdir(old) })
	return dir
}

func TestReadConfig_Table(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		setup    func(dir string) string
		wantNil  bool
		wantKeys int
	}{
		{
			name: "missing file returns nil map",
			setup: func(dir string) string {
				return filepath.Join(dir, "missing.json")
			},
			wantNil:  true,
			wantKeys: 0,
		},
		{
			name: "empty file returns nil map",
			setup: func(dir string) string {
				p := filepath.Join(dir, "empty.json")
				require.NoError(t, os.WriteFile(p, []byte(""), 0o644))
				return p
			},
			wantNil:  true,
			wantKeys: 0,
		},
		{
			name: "invalid JSON returns nil map",
			setup: func(dir string) string {
				p := filepath.Join(dir, "invalid.json")
				require.NoError(t, os.WriteFile(p, []byte("{ invalid"), 0o644))
				return p
			},
			wantNil:  true,
			wantKeys: 0,
		},
		{
			name: "empty object yields empty non-nil map",
			setup: func(dir string) string {
				p := filepath.Join(dir, "empty_object.json")
				require.NoError(t, os.WriteFile(p, []byte("{}"), 0o644))
				return p
			},
			wantNil:  false,
			wantKeys: 0,
		},
		{
			name: "valid object yields keys",
			setup: func(dir string) string {
				p := filepath.Join(dir, "valid.json")
				require.NoError(t, os.WriteFile(p, []byte(`{"a":1,"b":"x"}`), 0o644))
				return p
			},
			wantNil:  false,
			wantKeys: 2,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			path := tt.setup(dir)

			got := ReadConfig(path)

			if tt.wantNil {
				assert.Nil(t, got)
				return
			}
			assert.NotNil(t, got)
			assert.Equal(t, tt.wantKeys, len(got))
		})
	}
}

func TestReadConfig_ValidValuesTypes(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	p := filepath.Join(dir, "config.json")
	require.NoError(t, os.WriteFile(p, []byte(`{"num":1,"str":"ok","nested":{"x":2}}`), 0o644))

	got := ReadConfig(p)
	assert.NotNil(t, got, "config should not be nil for valid JSON")

	if assert.Contains(t, got, "num") {
		_, isFloat := got["num"].(float64)
		assert.True(t, isFloat, "numbers unmarshal to float64")
	}
	if assert.Contains(t, got, "str") {
		_, isString := got["str"].(string)
		assert.True(t, isString, "string value expected")
	}
	if assert.Contains(t, got, "nested") {
		nested, isMap := got["nested"].(map[string]interface{})
		if assert.True(t, isMap, "nested object should be a map") && nested != nil {
			if assert.Contains(t, nested, "x") {
				_, isFloat := nested["x"].(float64)
				assert.True(t, isFloat, "nested number should be float64")
			}
		}
	}
}

func TestReadConfig_DirectoryPathReturnsNil(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()

	got := ReadConfig(dir)
	assert.Nil(t, got, "reading a directory should result in nil config due to read/unmarshal errors")
}

func TestReadConfig_UTF8Content(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	p := filepath.Join(dir, "utf8.json")
	require.NoError(t, os.WriteFile(p, []byte(`{"msg":"こんにちは"}`), 0o644))

	got := ReadConfig(p)
	assert.NotNil(t, got)
	if assert.Contains(t, got, "msg") {
		assert.Equal(t, "こんにちは", got["msg"])
	}
}

func TestWriteLog_CreatesAppLogInCWDAndNoContent(t *testing.T) {
	withTempWD(t)

	_, err := os.Stat("app.log")
	assert.True(t, os.IsNotExist(err), "app.log should not exist before call")

	WriteLog("hello world")

	fi, statErr := os.Stat("app.log")
	assert.NoError(t, statErr, "app.log should be created")
	if assert.NotNil(t, fi) {
		data, readErr := os.ReadFile("app.log")
		assert.NoError(t, readErr)
		assert.Equal(t, 0, len(data), "content should remain empty because write errors are ignored")
	}
}

func TestWriteLog_PreexistingFileContentUnchanged(t *testing.T) {
	withTempWD(t)
	seed := []byte("seed")
	require.NoError(t, os.WriteFile("app.log", seed, 0o644))

	WriteLog("ignored write")

	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Equal(t, string(seed), string(data), "content should be unchanged due to missing write flags and ignored errors")
}

func TestWriteLog_MultipleCalls_NoPanic_FileExistsAndEmpty(t *testing.T) {
	withTempWD(t)

	tests := []struct {
		name    string
		message string
	}{
		{"empty message", ""},
		{"short message", "hello"},
		{"unicode message", "🔥✨こんにちは🌟"},
		{"long message", strings.Repeat("x", 10_000)},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.NotPanics(t, func() { WriteLog(tt.message) })
		})
	}

	_, statErr := os.Stat("app.log")
	assert.NoError(t, statErr, "app.log should exist after calls")
	data, err := os.ReadFile("app.log")
	assert.NoError(t, err)
	assert.Equal(t, 0, len(data), "file should remain empty because writes fail and errors are ignored")
}

func TestWriteLog_RepeatedOpenCloseLeakSafeForFewCalls(t *testing.T) {
	withTempWD(t)

	for i := 0; i < 5; i++ {
		WriteLog("msg")
	}
	// Validate file presence and emptiness
	fi, err := os.Stat("app.log")
	assert.NoError(t, err)
	if assert.NotNil(t, fi) {
		data, rErr := os.ReadFile("app.log")
		assert.NoError(t, rErr)
		assert.Equal(t, 0, len(data))
	}
}

func TestProcessData_Table_ReturnsSameString(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name  string
		input string
	}{
		{"simple", "abc"},
		{"space", " "},
		{"unicode", "こんにちは"},
		{"with newline", "a\nb"},
		{"number string", "0"},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			got := ProcessData(tt.input)
			assert.Equal(t, tt.input, got)
		})
	}
}

func TestProcessData_PanicsOnEmpty(t *testing.T) {
	t.Parallel()
	assert.Panics(t, func() { ProcessData("") })
}

func TestProcessData_PanicsWithValue(t *testing.T) {
	t.Parallel()
	assert.PanicsWithValue(t, "empty input", func() { ProcessData("") })
}

func TestProcessData_NotPanicsOnNonEmpty(t *testing.T) {
	t.Parallel()
	assert.NotPanics(t, func() { ProcessData("non-empty") })
}
