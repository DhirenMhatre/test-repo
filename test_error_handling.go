package main

// Test file for error handling patterns
// Should trigger warnings when priority is set to "Missing error handling" or "Error propagation"

import (
	"encoding/json"
	"os"
)

func ReadConfig(path string) map[string]interface{} {
	// Bad: Ignoring error
	data, _ := os.ReadFile(path)

	var config map[string]interface{}
	// Bad: Ignoring error
	json.Unmarshal(data, &config)

	return config
}

func WriteLog(message string) {
	file, _ := os.OpenFile("app.log", os.O_APPEND|os.O_CREATE, 0644)
	// Bad: Not checking if write succeeded
	file.WriteString(message)
	// Bad: Not closing file
}

func ProcessData(input string) string {
	// Bad: Panic instead of error return
	if input == "" {
		panic("empty input")
	}
	return input
}

// Should be caught when priority is "error handling" or "panic usage"
