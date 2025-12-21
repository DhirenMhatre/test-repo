package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadConfig(t *testing.T) {
	tmp := t.TempDir()

	type args struct {
		path string
	}

	writeFile := func(name string, content []byte) string {
		p := filepath.Join(tmp, name)
		require.NoError(t, os.WriteFile(p, content, 0o644))
		return p
	}

	tests := []struct {
		name       string
		setup      func() args
		wantNilMap bool
		verify     func(t *testing.T, cfg map[string]interface{})
	}{
		{
			name: "missing file returns nil map",
			setup: func() args {
				return args{path: filepath.Join(tmp, "does_not_exist.json")}
			},
			wantNilMap: true,
		},
		{
			name: "empty file returns nil map",
			setup: func() args {
				return args{path: writeFile("empty.json", []byte{})}
			},
			wantNilMap: true,
		},
		{
			name: "whitespace-only file returns nil map",
			setup: func() args {
				return args{path: writeFile("space.json", []byte(" \n\t"))}
			},
			wantNilMap: true,
		},
		{
			name: "invalid json returns nil map",
			setup: func() args {
				return args{path: writeFile("invalid.json", []byte("{ invalid json"))}
			},
			wantNilMap: true,
		},
		{
			name: "json array into map returns nil map",
			setup: func() args {
				return args{path: writeFile("array.json", []byte(`[1,2,3]`))}
			},
			wantNilMap: true,
		},
		{
			name: "valid json object populates map",
			setup: func() args {
				return args{path: writeFile("object.json", []byte(`{"a":1,"b":"x"}`))}
			},
			wantNilMap: false,
			verify: func(t *testing.T, cfg map[string]interface{}) {
				assert.NotNil(t, cfg)
				assert.Contains(t, cfg, "a")
				assert.Contains(t, cfg, "b")
				if assert.IsType(t, float64(0), cfg["a"]) {
					assert.Equal(t, float64(1), cfg["a"])
				}
				if assert.IsType(t, "", cfg["b"]) {
					assert.Equal(t, "x", cfg["b"])
				}
			},
		},
		{
			name: "nested json object keeps nested map values",
			setup: func() args {
				return args{path: writeFile("nested.json", []byte(`{"nested":{"x":2},"arr":[1,3],"flag":true}`))}
			},
			wantNilMap: false,
			verify: func(t *testing.T, cfg map[string]interface{}) {
				assert.NotNil(t, cfg)
				nestedVal, ok := cfg["nested"]
				assert.True(t, ok)
				nested, ok := nestedVal.(map[string]interface{})
				if assert.True(t, ok, "nested should be a map") {
					if xv, ok := nested["x"]; assert.True(t, ok) {
						assert.Equal(t, float64(2), xv)
					}
				}
				_, ok = cfg["arr"]
				assert.True(t, ok)
				_, ok = cfg["flag"]
				assert.True(t, ok)
			},
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			args := tt.setup()
			cfg := ReadConfig(args.path)
			if tt.wantNilMap {
				assert.Nil(t, cfg)
				return
			}
			assert.NotNil(t, cfg)
			if tt.verify != nil {
				tt.verify(t, cfg)
			}
		})
	}
}

func TestWriteLog_NotPanicsAndCreatesFile(t *testing.T) {
	// Change working directory to a temp dir to isolate side effects
	orig, err := os.Getwd()
	require.NoError(t, err)
	t.Cleanup(func() { _ = os.Chdir(orig) })
	tmp := t.TempDir()
	require.NoError(t, os.Chdir(tmp))

	assert.NotPanics(t, func() { WriteLog("hello") }, "WriteLog should not panic on writable directory")

	// File should exist regardless of write errors
	_, statErr := os.Stat("app.log")
	assert.NoError(t, statErr, "app.log should be created")
}

func TestWriteLog_MultipleCalls_NotPanics_FileExists(t *testing.T) {
	orig, err := os.Getwd()
	require.NoError(t, err)
	t.Cleanup(func() { _ = os.Chdir(orig) })
	tmp := t.TempDir()
	require.NoError(t, os.Chdir(tmp))

	for i := 0; i < 3; i++ {
		assert.NotPanics(t, func() { WriteLog("msg") })
	}

	// Ensure file exists after multiple calls
	_, statErr := os.Stat("app.log")
	assert.NoError(t, statErr)
}

func TestWriteLog_ReadOnlyFile_NotPanics(t *testing.T) {
	orig, err := os.Getwd()
	require.NoError(t, err)
	t.Cleanup(func() { _ = os.Chdir(orig) })
	tmp := t.TempDir()
	require.NoError(t, os.Chdir(tmp))

	// Pre-create a read-only app.log
	require.NoError(t, os.WriteFile("app.log", []byte("preexisting"), 0o444))

	// Even if file is read-only, function should not panic (it ignores all errors)
	assert.NotPanics(t, func() { WriteLog("attempt") })

	// File should still exist
	_, statErr := os.Stat("app.log")
	assert.NoError(t, statErr)
}

func TestProcessData_Table(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		want        string
		wantPanic   bool
		description string
	}{
		{name: "empty string panics", input: "", wantPanic: true},
		{name: "simple string", input: "hello", want: "hello"},
		{name: "single space", input: " ", want: " "},
		{name: "unicode emoji", input: "😀", want: "😀"},
		{name: "multi-line", input: "line1\nline2\n", want: "line1\nline2\n"},
		{name: "long string", input: "abcdefghijklmnopqrstuvwxyz0123456789", want: "abcdefghijklmnopqrstuvwxyz0123456789"},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() { _ = ProcessData(tt.input) })
				return
			}
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestProcessData_IdentityProperties(t *testing.T) {
	// Additional focused identity checks for various inputs
	inputs := []string{
		"a",
		"GoLang",
		"12345",
		"こんにちは",
		" with leading space",
		"trailing space ",
		"\t tabs \t",
	}
	for _, in := range inputs {
		in := in
		t.Run("identity_"+in, func(t *testing.T) {
			assert.NotPanics(t, func() {
				got := ProcessData(in)
				assert.Equal(t, in, got)
			})
		})
	}
}
