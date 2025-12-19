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

func TestReadConfig(t *testing.T) {
	t.Parallel()

	type tc struct {
		name       string
		content    *string
		wantNil    bool
		wantLen    int
		wantFields map[string]interface{}
	}
	validObj := `{"a":1,"b":"x"}`
	emptyObj := `{}`

	tests := []tc{
		{
			name:    "missing file returns nil map",
			content: nil,
			wantNil: true,
		},
		{
			name:    "invalid json returns nil map",
			content: ptr("{invalid"),
			wantNil: true,
		},
		{
			name:    "empty file returns nil map",
			content: ptr(""),
			wantNil: true,
		},
		{
			name:    "json null returns nil map",
			content: ptr("null"),
			wantNil: true,
		},
		{
			name:       "valid json object returns populated map",
			content:    &validObj,
			wantNil:    false,
			wantLen:    2,
			wantFields: map[string]interface{}{"a": float64(1), "b": "x"},
		},
		{
			name:       "valid empty object returns non-nil empty map",
			content:    &emptyObj,
			wantNil:    false,
			wantLen:    0,
			wantFields: map[string]interface{}{},
		},
	}
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, "cfg.json")
			if tt.content != nil {
				require.NoError(t, os.WriteFile(path, []byte(*tt.content), 0o644))
			} else {
				path = filepath.Join(dir, "missing.json")
			}

			got := ReadConfig(path)

			if tt.wantNil {
				assert.Nil(t, got)
				return
			}
			assert.NotNil(t, got)
			assert.Equal(t, tt.wantLen, len(got))
			for k, v := range tt.wantFields {
				_, ok := got[k]
				assert.True(t, ok, "expected key %q", k)
				if ok {
					assert.Equal(t, v, got[k])
				}
			}
		})
	}
}

func TestWriteLog(t *testing.T) {
	type tc struct {
		name           string
		initialContent *string
		message        string
		repeat         int
		wantSize       int64
	}
	initStr := "PRE"
	tests := []tc{
		{
			name:           "creates file but does not write",
			initialContent: nil,
			message:        "hello",
			repeat:         1,
			wantSize:       0,
		},
		{
			name:           "preserves pre-existing content",
			initialContent: &initStr,
			message:        "A",
			repeat:         1,
			wantSize:       int64(len(initStr)),
		},
		{
			name:           "multiple calls do not append",
			initialContent: nil,
			message:        "X",
			repeat:         3,
			wantSize:       0,
		},
		{
			name:           "empty message no-op",
			initialContent: &initStr,
			message:        "",
			repeat:         1,
			wantSize:       int64(len(initStr)),
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			origWD, err := os.Getwd()
			require.NoError(t, err)
			require.NoError(t, os.Chdir(dir))
			defer func() { _ = os.Chdir(origWD) }()

			if tt.initialContent != nil {
				require.NoError(t, os.WriteFile("app.log", []byte(*tt.initialContent), 0o644))
			}

			if tt.repeat <= 0 {
				tt.repeat = 1
			}
			for i := 0; i < tt.repeat; i++ {
				WriteLog(tt.message)
				// Force GC to run os.File finalizers so the descriptor is closed.
				runtime.GC()
			}

			info, err := os.Stat("app.log")
			require.NoError(t, err, "app.log should exist")
			assert.Equal(t, tt.wantSize, info.Size())

			data, err := os.ReadFile("app.log")
			require.NoError(t, err)
			if tt.initialContent != nil {
				assert.Equal(t, *tt.initialContent, string(data))
			} else {
				assert.Equal(t, "", string(data))
			}
		})
	}
}

func TestProcessData(t *testing.T) {
	type tc struct {
		name      string
		input     string
		want      string
		wantPanic bool
	}
	long := strings.Repeat("x", 1024)

	tests := []tc{
		{
			name:      "empty input panics",
			input:     "",
			wantPanic: true,
		},
		{
			name:  "non-empty returned as-is",
			input: "abc",
			want:  "abc",
		},
		{
			name:  "whitespace preserved",
			input: "   ",
			want:  "   ",
		},
		{
			name:  "long string preserved",
			input: long,
			want:  long,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantPanic {
				assert.Panics(t, func() {
					_ = ProcessData(tt.input)
				})
				return
			}
			got := ProcessData(tt.input)
			assert.Equal(t, tt.want, got)
		})
	}
}

func ptr[T any](v T) *T {
	return &v
}
