package main

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReadConfig_Table(t *testing.T) {
	dir := t.TempDir()

	writeFile := func(name, content string) string {
		p := filepath.Join(dir, name)
		err := os.WriteFile(p, []byte(content), 0o644)
		assert.NoError(t, err)
		return p
	}

	validPath := writeFile("valid.json", `{"name":"demo","enabled":true}`)
	emptyObjectPath := writeFile("empty.json", `{}`)
	malformedPath := writeFile("malformed.json", `{"incomplete": true`)
	nonJSONPath := writeFile("nonjson.txt", `hello world`)
	emptyFilePath := writeFile("emptyfile.json", ``)
	arrayJSONPath := writeFile("array.json", `[]`)

	tests := []struct {
		name     string
		path     string
		wantNil  bool
		wantSize int
	}{
		{"valid JSON object", validPath, false, 2},
		{"empty JSON object", emptyObjectPath, false, 0},
		{"malformed JSON", malformedPath, true, 0},
		{"non-JSON content", nonJSONPath, true, 0},
		{"empty file", emptyFilePath, true, 0},
		{"array JSON into map", arrayJSONPath, true, 0},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			cfg := ReadConfig(tt.path)
			if tt.wantNil {
				assert.Nil(t, cfg)
				return
			}
			assert.NotNil(t, cfg)
			assert.Equal(t, tt.wantSize, len(cfg))
			if tt.path == validPath {
				// Expect map with "name":"demo","enabled":true
				val, ok := cfg["name"]
				assert.True(t, ok)
				assert.Equal(t, "demo", val)
				ben, ok := cfg["enabled"]
				assert.True(t, ok)
				assert.Equal(t, true, ben)
			}
		})
	}
}

func TestReadConfig_NumberTypes(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "numbers.json")
	err := os.WriteFile(path, []byte(`{"n": 42}`), 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)
	v, ok := cfg["n"]
	assert.True(t, ok)
	// JSON numbers decode to float64
	f, ok := v.(float64)
	assert.True(t, ok)
	assert.Equal(t, float64(42), f)
}

func TestReadConfig_ValidNested(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "nested.json")
	err := os.WriteFile(path, []byte(`{"nested":{"a":1},"list":[1,2]}`), 0o644)
	assert.NoError(t, err)

	cfg := ReadConfig(path)
	assert.NotNil(t, cfg)

	nested, ok := cfg["nested"]
	assert.True(t, ok)
	nm, ok := nested.(map[string]interface{})
	assert.True(t, ok)
	av, ok := nm["a"]
	assert.True(t, ok)
	af, ok := av.(float64)
	assert.True(t, ok)
	assert.Equal(t, float64(1), af)

	list, ok := cfg["list"]
	assert.True(t, ok)
	ls, ok := list.([]interface{})
	assert.True(t, ok)
	assert.Len(t, ls, 2)
}

func TestWriteLog_CreatesFileAndDoesNotWrite_OnWritableDir_UnixOnly(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("file unlink semantics differ on Windows")
	}
	origWD, err := os.Getwd()
	assert.NoError(t, err)
	defer func() { _ = os.Chdir(origWD) }()

	dir := t.TempDir()
	err = os.Chdir(dir)
	assert.NoError(t, err)

	// Call function; it should attempt to append but file is opened read-only,
	// so no bytes are written. It should still create the file.
	assert.NotPanics(t, func() { WriteLog("hello world") })

	// File should exist
	_, statErr := os.Stat("app.log")
	assert.NoError(t, statErr)

	// File should be empty due to failed write
	data, readErr := os.ReadFile("app.log")
	assert.NoError(t, readErr)
	assert.Len(t, data, 0)

	// Remove file to avoid t.TempDir cleanup issues
	rmErr := os.Remove("app.log")
	assert.NoError(t, rmErr)
}

func TestWriteLog_ReadOnlyDir_NoFileCreated(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("chmod read-only dir semantics differ on Windows")
	}

	origWD, err := os.Getwd()
	assert.NoError(t, err)
	defer func() { _ = os.Chdir(origWD) }()

	dir := t.TempDir()
	err = os.Chmod(dir, 0o555) // read & execute only
	assert.NoError(t, err)

	err = os.Chdir(dir)
	assert.NoError(t, err)

	tests := []struct {
		name    string
		message string
	}{
		{"empty message", ""},
		{"non-empty message", "test log"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			assert.NotPanics(t, func() { WriteLog(tt.message) })
			_, statErr := os.Stat("app.log")
			assert.True(t, os.IsNotExist(statErr))
		})
	}

	// Restore permissions so t.TempDir can clean up
	_ = os.Chmod(dir, 0o755)
}

func TestWriteLog_MultipleCalls_StillEmptyFile_UnixOnly(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("file unlink semantics differ on Windows")
	}
	origWD, err := os.Getwd()
	assert.NoError(t, err)
	defer func() { _ = os.Chdir(origWD) }()

	dir := t.TempDir()
	err = os.Chdir(dir)
	assert.NoError(t, err)

	assert.NotPanics(t, func() { WriteLog("first") })
	assert.NotPanics(t, func() { WriteLog("second") })

	data, readErr := os.ReadFile("app.log")
	assert.NoError(t, readErr)
	assert.Len(t, data, 0)

	rmErr := os.Remove("app.log")
	assert.NoError(t, rmErr)
}

func TestProcessData_Table(t *testing.T) {
	tests := []struct {
		name         string
		input        string
		want         string
		wantPanic    bool
		panicMessage string
	}{
		{"non-empty", "hello", "hello", false, ""},
		{"spaces string", "   ", "   ", false, ""},
		{"unicode", "😀", "😀", false, ""},
		{"empty panics", "", "", true, "empty input"},
		{"long string", "abcdefghijklmnopqrstuvwxyz", "abcdefghijklmnopqrstuvwxyz", false, ""},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.PanicsWithValue(t, tt.panicMessage, func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			assert.NotPanics(t, func() { _ = ProcessData(tt.input) })
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}
