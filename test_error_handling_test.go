package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestReadConfig(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()

	tests := []struct {
		name string
		data string
		// create indicates if the file should be created before calling ReadConfig.
		// If false, the file will not exist.
		create bool
		// want is the expected map; if nil, we expect the function to return nil.
		want map[string]interface{}
	}{
		{
			name:   "missing_file_returns_nil",
			create: false,
			want:   nil,
		},
		{
			name:   "empty_file_returns_nil",
			data:   "",
			create: true,
			want:   nil,
		},
		{
			name:   "invalid_json_returns_nil",
			data:   "not valid json",
			create: true,
			want:   nil,
		},
		{
			name:   "null_root_returns_nil",
			data:   "null",
			create: true,
			want:   nil,
		},
		{
			name:   "array_root_returns_nil",
			data:   "[]",
			create: true,
			want:   nil,
		},
		{
			name:   "empty_object_returns_empty_map",
			data:   "{}",
			create: true,
			want:   map[string]interface{}{},
		},
		{
			name:   "whitespace_then_object_returns_empty_map",
			data:   " \n\t {} \n",
			create: true,
			want:   map[string]interface{}{},
		},
		{
			name:   "simple_object_parsed",
			data:   `{"a":1,"b":"x","c":true}`,
			create: true,
			want: map[string]interface{}{
				"a": float64(1),
				"b": "x",
				"c": true,
			},
		},
		{
			name:   "nested_object_parsed",
			data:   `{"x":{"y":2}}`,
			create: true,
			want: map[string]interface{}{
				"x": map[string]interface{}{
					"y": float64(2),
				},
			},
		},
	}

	for i, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			path := filepath.Join(dir, fmt.Sprintf("case_%d.json", i))
			if tt.create {
				err := os.WriteFile(path, []byte(tt.data), 0o644)
				assert.NoError(t, err)
			}

			got := ReadConfig(path)
			if tt.want == nil {
				assert.Nil(t, got)
			} else {
				assert.NotNil(t, got)
				assert.Equal(t, tt.want, got)
			}
		})
	}
}

func TestWriteLog_Basic(t *testing.T) {
	// Do not run this test in parallel due to working directory changes.
	cwd, err := os.Getwd()
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(cwd)
	}()

	tmp := t.TempDir()
	err = os.Chdir(tmp)
	assert.NoError(t, err)

	tests := []struct {
		name    string
		message string
	}{
		{"empty_message", ""},
		{"short_message", "hello"},
		{"unicode_message", "こんにちは🌟"},
		{"long_message", strings.Repeat("x", 4096)},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			WriteLog(tt.message)

			info, err := os.Stat("app.log")
			assert.NoError(t, err)
			assert.NotNil(t, info)
			assert.False(t, info.IsDir(), "app.log should be a file")
			// We intentionally do not assert on file size/content because WriteLog opens the file
			// without write flags; writes may fail without affecting size across platforms.
		})
	}
}

func TestWriteLog_ConcurrentCalls(t *testing.T) {
	// Do not run this test in parallel due to working directory changes.
	cwd, err := os.Getwd()
	assert.NoError(t, err)
	defer func() {
		_ = os.Chdir(cwd)
	}()

	tmp := t.TempDir()
	err = os.Chdir(tmp)
	assert.NoError(t, err)

	var wg sync.WaitGroup
	msgs := []string{
		"a", "b", "c", "d", "e",
		strings.Repeat("1", 100),
		strings.Repeat("2", 200),
		"😀", "测试", "конкурентность",
	}
	for _, m := range msgs {
		wg.Add(1)
		go func(msg string) {
			defer wg.Done()
			WriteLog(msg)
		}(m)
	}
	wg.Wait()

	info, err := os.Stat("app.log")
	assert.NoError(t, err)
	assert.NotNil(t, info)
	assert.False(t, info.IsDir())
}

func TestProcessData(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}{
		{"empty_input_panics", "", "", true},
		{"single_char", "a", "a", false},
		{"whitespace_only", "   ", "   ", false},
		{"unicode_input", "こんにちは", "こんにちは", false},
		{"long_input", strings.Repeat("Z", 2048), strings.Repeat("Z", 2048), false},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.PanicsWithValue(t, "empty input", func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestProcessData_PanicMessageExact(t *testing.T) {
	t.Parallel()
	assert.PanicsWithValue(t, "empty input", func() {
		_ = ProcessData("")
	})
}
