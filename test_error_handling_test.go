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

func TestReadConfig_Table(t *testing.T) {
	dir := t.TempDir()

	tests := []struct {
		name       string
		filename   string
		content    string
		createFile bool
		expectNil  bool
		check      func(t *testing.T, got map[string]interface{})
	}{
		{
			name:       "nonexistent file returns nil map",
			filename:   "missing.json",
			createFile: false,
			expectNil:  true,
		},
		{
			name:       "empty file returns nil map",
			filename:   "empty.json",
			content:    "",
			createFile: true,
			expectNil:  true,
		},
		{
			name:       "invalid JSON returns nil map",
			filename:   "invalid.json",
			content:    "{not-json",
			createFile: true,
			expectNil:  true,
		},
		{
			name:       "empty object returns non-nil empty map",
			filename:   "empty_obj.json",
			content:    "{}",
			createFile: true,
			expectNil:  false,
			check: func(t *testing.T, got map[string]interface{}) {
				assert.Equal(t, 0, len(got))
			},
		},
		{
			name:       "valid simple object",
			filename:   "simple.json",
			content:    `{"a":1,"b":"x"}`,
			createFile: true,
			expectNil:  false,
			check: func(t *testing.T, got map[string]interface{}) {
				assert.Contains(t, got, "a")
				assert.Contains(t, got, "b")
				av, aok := got["a"]
				bv, bok := got["b"]
				require.True(t, aok)
				require.True(t, bok)
				// JSON numbers are float64 in interface{}
				assert.IsType(t, float64(0), av)
				assert.Equal(t, "x", bv)
			},
		},
		{
			name:       "whitespace and object",
			filename:   "ws.json",
			content:    "  \n {  } \n ",
			createFile: true,
			expectNil:  false,
			check: func(t *testing.T, got map[string]interface{}) {
				assert.Equal(t, 0, len(got))
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			fp := filepath.Join(dir, tt.filename)
			if tt.createFile {
				require.NoError(t, os.WriteFile(fp, []byte(tt.content), 0o644))
			}
			got := ReadConfig(fp)
			if tt.expectNil {
				assert.Nil(t, got)
				return
			}
			assert.NotNil(t, got)
			if tt.check != nil {
				tt.check(t, got)
			}
		})
	}
}

func TestReadConfig_ArrayTopLevel_ReturnsNil(t *testing.T) {
	dir := t.TempDir()
	fp := filepath.Join(dir, "arr.json")
	require.NoError(t, os.WriteFile(fp, []byte(`[]`), 0o644))

	got := ReadConfig(fp)
	assert.Nil(t, got)
}

func TestReadConfig_NullJSON_ReturnsNil(t *testing.T) {
	dir := t.TempDir()
	fp := filepath.Join(dir, "null.json")
	require.NoError(t, os.WriteFile(fp, []byte(`null`), 0o644))

	got := ReadConfig(fp)
	assert.Nil(t, got)
}

func TestReadConfig_ValidJSONWithNestedTypes(t *testing.T) {
	dir := t.TempDir()
	fp := filepath.Join(dir, "nested.json")
	content := `{
		"nums": [1, 2, 3],
		"nested": {"x": true},
		"pi": 3.14,
		"name": "go",
		"nullv": null
	}`
	require.NoError(t, os.WriteFile(fp, []byte(content), 0o644))

	got := ReadConfig(fp)
	require.NotNil(t, got)

	// name
	assert.Equal(t, "go", got["name"])

	// pi as float64
	piv, ok := got["pi"]
	require.True(t, ok)
	assert.IsType(t, float64(0), piv)

	// nested map
	nested, ok := got["nested"].(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, true, nested["x"])

	// nums slice
	nums, ok := got["nums"].([]interface{})
	require.True(t, ok)
	assert.Equal(t, 3, len(nums))
	assert.IsType(t, float64(0), nums[0])

	// nullv present with nil value
	_, ok = got["nullv"]
	assert.True(t, ok)
	assert.Nil(t, got["nullv"])
}

func TestReadConfig_WhitespaceOnlyFile_ReturnsNil(t *testing.T) {
	dir := t.TempDir()
	fp := filepath.Join(dir, "ws_only.json")
	require.NoError(t, os.WriteFile(fp, []byte("   \n\t  "), 0o644))

	got := ReadConfig(fp)
	assert.Nil(t, got)
}

func TestReadConfig_TwoSequentialCallsIndependent(t *testing.T) {
	dir := t.TempDir()
	fp1 := filepath.Join(dir, "one.json")
	fp2 := filepath.Join(dir, "two.json")
	require.NoError(t, os.WriteFile(fp1, []byte(`{"k1":"v1"}`), 0o644))
	require.NoError(t, os.WriteFile(fp2, []byte(`{"k2":"v2"}`), 0o644))

	m1 := ReadConfig(fp1)
	m2 := ReadConfig(fp2)

	require.NotNil(t, m1)
	require.NotNil(t, m2)
	assert.Equal(t, "v1", m1["k1"])
	assert.Nil(t, m1["k2"])
	assert.Equal(t, "v2", m2["k2"])
	assert.Nil(t, m2["k1"])

	// mutate m1 and ensure m2 unaffected
	m1["extra"] = "x"
	assert.Nil(t, m2["extra"])
}

func TestWriteLog_CreatesFileButWritesZeroBytes(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on Windows due to open handle cleanup behavior")
	}
	dir := t.TempDir()
	wd, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(dir))
	defer func() {
		_ = os.Chdir(wd)
	}()

	WriteLog("hello world")
	// Encourage finalizers to close file descriptors
	runtime.GC()

	st, err := os.Stat("app.log")
	require.NoError(t, err)
	assert.False(t, st.IsDir())
	assert.Equal(t, int64(0), st.Size())

	data, err := os.ReadFile("app.log")
	require.NoError(t, err)
	assert.Equal(t, "", string(data))
}

func TestWriteLog_PanicWhenOpenFailsDueToPermissions(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("chmod protections are unreliable on Windows")
	}
	parent := t.TempDir()
	roDir := filepath.Join(parent, "ro")
	require.NoError(t, os.Mkdir(roDir, 0o555))
	defer func() { _ = os.Chmod(roDir, 0o755) }()

	wd, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(roDir))
	defer func() {
		_ = os.Chdir(wd)
	}()

	assert.Panics(t, func() {
		WriteLog("should panic due to nil file on open failure")
	})

	_, err = os.Stat("app.log")
	assert.Error(t, err)
}

func TestWriteLog_MultipleCallsDoNotAppend(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("skip on Windows due to open handle cleanup behavior")
	}
	dir := t.TempDir()
	wd, err := os.Getwd()
	require.NoError(t, err)
	require.NoError(t, os.Chdir(dir))
	defer func() {
		_ = os.Chdir(wd)
	}()

	for i := 0; i < 3; i++ {
		WriteLog(strings.Repeat("x", 10))
	}
	runtime.GC()

	st, err := os.Stat("app.log")
	require.NoError(t, err)
	assert.Equal(t, int64(0), st.Size())
}

func TestProcessData_ReturnsInput_Table(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{"non-empty simple", "abc"},
		{"whitespace preserved", "   "},
		{"numeric string", "123"},
		{"special chars", "!@#$%^&*()"},
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
	assert.PanicsWithValue(t, "empty input", func() {
		_ = ProcessData("")
	})
}

func TestProcessData_DoesNotPanicOnLongInput(t *testing.T) {
	long := strings.Repeat("x", 4096)
	assert.NotPanics(t, func() {
		out := ProcessData(long)
		assert.Equal(t, long, out)
	})
}
