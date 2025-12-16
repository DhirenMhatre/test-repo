package main

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig_CommonCases(t *testing.T) {
	dir := t.TempDir()

	tests := []struct {
		name      string
		filename  string
		contents  []byte
		expectNil bool
		validate  func(t *testing.T, cfg map[string]interface{})
	}{
		{
			name:      "missing file returns nil map",
			filename:  "missing.json",
			expectNil: true,
		},
		{
			name:      "empty file returns nil map",
			filename:  "empty.json",
			contents:  []byte(""),
			expectNil: true,
		},
		{
			name:      "whitespace only returns nil map",
			filename:  "ws.json",
			contents:  []byte("   \n\t"),
			expectNil: true,
		},
		{
			name:      "invalid json returns nil map",
			filename:  "invalid.json",
			contents:  []byte("{ invalid json"),
			expectNil: true,
		},
		{
			name:     "valid object returns populated map",
			filename: "valid.json",
			contents: []byte(`{"name":"app","port":8080,"enabled":true}`),
			validate: func(t *testing.T, cfg map[string]interface{}) {
				if assert.NotNil(t, cfg, "config should not be nil for valid JSON") {
					assert.Equal(t, "app", cfg["name"])
					assert.Equal(t, float64(8080), cfg["port"])
					assert.Equal(t, true, cfg["enabled"])
				}
			},
		},
		{
			name:      "json null results in nil map",
			filename:  "null.json",
			contents:  []byte("null"),
			expectNil: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := filepath.Join(dir, tt.filename)
			if tt.contents != nil {
				require.NoError(t, os.WriteFile(p, tt.contents, 0o644))
			}
			cfg := ReadConfig(p)
			if tt.expectNil {
				assert.Nil(t, cfg, "expected nil config")
				return
			}
			assert.NotNil(t, cfg, "expected non-nil config")
			if tt.validate != nil {
				tt.validate(t, cfg)
			}
		})
	}
}

func TestReadConfig_ComplexNested(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "nested.json")
	data := []byte(`{"nested":{"a":1,"b":"x"},"arr":[1,"x",true,null]}`)
	require.NoError(t, os.WriteFile(p, data, 0o644))

	cfg := ReadConfig(p)
	if assert.NotNil(t, cfg) {
		nestedRaw, ok := cfg["nested"]
		assert.True(t, ok, "nested key should exist")
		if ok {
			nested, ok2 := nestedRaw.(map[string]interface{})
			assert.True(t, ok2, "nested should be a map")
			if ok2 && assert.NotNil(t, nested) {
				assert.Equal(t, float64(1), nested["a"])
				assert.Equal(t, "x", nested["b"])
			}
		}

		arrRaw, ok := cfg["arr"]
		assert.True(t, ok, "arr key should exist")
		if ok {
			arr, ok2 := arrRaw.([]interface{})
			assert.True(t, ok2, "arr should be a slice")
			if ok2 && assert.NotNil(t, arr) && assert.GreaterOrEqual(t, len(arr), 4) {
				assert.Equal(t, float64(1), arr[0])
				assert.Equal(t, "x", arr[1])
				assert.Equal(t, true, arr[2])
				assert.Nil(t, arr[3])
			}
		}
	}
}

func TestReadConfig_EmptyObject(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "emptyobj.json")
	require.NoError(t, os.WriteFile(p, []byte(`{}`), 0o644))

	cfg := ReadConfig(p)
	if assert.NotNil(t, cfg) {
		assert.Equal(t, 0, len(cfg))
	}
}

func TestProcessData_Table(t *testing.T) {
	tests := []struct {
		name      string
		in        string
		want      string
		wantPanic bool
	}{
		{name: "empty string panics", in: "", wantPanic: true},
		{name: "simple string", in: "hello", want: "hello"},
		{name: "space string", in: " ", want: " "},
		{name: "unicode string", in: "こんにちは", want: "こんにちは"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.PanicsWithValue(t, "empty input", func() {
					_ = ProcessData(tt.in)
				})
				return
			}
			got := ProcessData(tt.in)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestWriteLog_CreatesFileAndDoesNotWrite(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Skipping WriteLog file behavior test on Windows due to file sharing semantics")
	}
	dir := t.TempDir()

	wd, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(dir))
	defer func() { _ = os.Chdir(wd) }()

	WriteLog("hello world")

	fi, err := os.Stat("app.log")
	require.NoError(t, err, "app.log should be created")
	assert.Zero(t, fi.Size(), "file should be empty because opened read-only")
}

func TestWriteLog_MultipleCalls_StillEmpty(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Skipping WriteLog file behavior test on Windows due to file sharing semantics")
	}
	dir := t.TempDir()

	wd, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(dir))
	defer func() { _ = os.Chdir(wd) }()

	for i := 0; i < 3; i++ {
		WriteLog("msg")
	}

	fi, err := os.Stat("app.log")
	require.NoError(t, err)
	assert.Zero(t, fi.Size(), "file should remain empty after multiple writes")
}

func TestWriteLog_PreExistingFileUnchanged(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Skipping WriteLog file behavior test on Windows due to file sharing semantics")
	}
	dir := t.TempDir()

	wd, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(dir))
	defer func() { _ = os.Chdir(wd) }()

	// Prepare pre-existing file with content
	require.NoError(t, os.WriteFile("app.log", []byte("old"), 0o644))

	WriteLog("new content that should not be written")

	// Verify content remains unchanged (may still be readable even if file is open read-only)
	data, err := os.ReadFile("app.log")
	require.NoError(t, err)
	assert.Equal(t, "old", string(data), "pre-existing content should remain unchanged")
}

func TestWriteLog_ReadOnlyDir_NoFileCreated(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Skipping WriteLog permission test on Windows due to differing semantics")
	}
	dir := t.TempDir()
	roDir := filepath.Join(dir, "ro")
	require.NoError(t, os.Mkdir(roDir, 0o555)) // read/execute only

	wd, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(roDir))
	defer func() { _ = os.Chdir(wd) }()

	WriteLog("should fail to create file")

	_, err = os.Stat("app.log")
	assert.Error(t, err, "stat should error because file should not be created")
	assert.True(t, os.IsNotExist(err), "file should not exist in read-only directory")
}
