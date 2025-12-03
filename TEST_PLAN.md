# Custom Instructions Testing Plan

This document outlines comprehensive tests to ensure the custom instruction system is truly generic.

## Test Scenarios

### 1. **Lambda/List Comprehension Detection**
- **File**: `test_loops.py`
- **Instruction**: `.codity/review-instructions.yaml` (current)
- **Priority**: "Long for loops performing simple operations that could be replaced with lambda functions or list comprehensions"
- **Expected**: System should detect all 3 for-loop patterns and suggest list comprehensions
- **Validates**: Pattern matching for iterative code

### 2. **Memory Leak Detection**
- **File**: `test_memory_patterns.py`
- **Instruction**: `.codity/test-instructions-memory.yaml`
- **Priority**: "Unclosed file handles", "Database connections not properly closed"
- **Expected**: System should detect all unclosed resources (4 instances)
- **Validates**: Resource management pattern detection across different contexts

### 3. **Error Handling Gaps**
- **File**: `test_error_handling.go`
- **Instruction**: `.codity/test-instructions-error-handling.yaml`
- **Priority**: "Ignored errors or return values", "Functions that panic instead of returning errors"
- **Expected**: System should detect all ignored errors (4 instances) and panic usage
- **Validates**: Language-specific error handling patterns (Go)

### 4. **Security Vulnerabilities**
- **File**: `test_authentication.ts`
- **Instruction**: `.codity/test-instructions-security.yaml`
- **Priority**: "Hardcoded credentials", "Weak password validation", "Missing authorization checks"
- **Expected**: System should detect hardcoded secrets (2), weak auth (1), missing authz (1), weak comparison (1), JWT issue (1)
- **Validates**: Multi-language security pattern detection (TypeScript)

### 5. **Performance Anti-Patterns**
- **File**: `test_performance.rb`
- **Instruction**: `.codity/test-instructions-performance.yaml`
- **Priority**: "N+1 query patterns", "String concatenation in loops", "Nested loops"
- **Expected**: System should detect N+1 queries (1), string concat (1), nested loops (1), memory issues (1)
- **Validates**: Language-specific performance patterns (Ruby)

## Testing Process

### Step 1: Test Each Pattern Individually
1. Copy one test instruction file to `.codity/review-instructions.yaml`
2. Commit the corresponding test file
3. Trigger PR review with `@codity review`
4. Verify that ONLY the priority areas are flagged
5. Verify that skip_categories are respected

### Step 2: Test Skip Categories
1. Add test patterns to `skip_categories` in instruction file
2. Verify those patterns are NOT flagged in review
3. Example: Add "memory leaks" to skip_categories, ensure memory issues are ignored

### Step 3: Test Confidence Thresholds
1. Set confidence_threshold to 80
2. Verify only high-confidence issues are reported
3. Set confidence_threshold to 40
4. Verify more issues are reported

### Step 4: Test Negative Cases
Create files with GOOD patterns:
- Proper list comprehensions
- Proper resource cleanup (with statements, defer, etc.)
- Proper error handling
- No hardcoded credentials
- Optimized algorithms

Verify system doesn't flag these as issues.

### Step 5: Test Cross-Language Genericity
Submit PR with multiple languages (Python, Go, TypeScript, Ruby) and verify:
- Same instruction works across all languages semantically
- Language-specific idioms are understood
- Priority areas are enforced regardless of language

## Success Criteria

✅ **Generic Pattern Matching**: System detects patterns described in natural language, not hardcoded strings

✅ **Semantic Understanding**: LLM understands intent (e.g., "long for loops" matches various loop patterns)

✅ **Priority Enforcement**: Issues in priority_areas are ALWAYS flagged

✅ **Skip Enforcement**: Issues in skip_categories are NEVER flagged

✅ **Language Agnostic**: Same instruction concept works across Python, Go, TypeScript, Ruby

✅ **Confidence Filtering**: Confidence threshold properly filters low-confidence issues

✅ **No False Positives**: Good code patterns are not flagged

✅ **No Hardcoded Values**: System works for ANY user-defined priority, not just test cases

## Validation Commands

```bash
# Test 1: Lambda functions
cp .codity/review-instructions.yaml .codity/backup.yaml
git add test_loops.py
git commit -m "Test: for loops that need list comprehensions"
git push
# Trigger review, expect 3 warnings about list comprehensions

# Test 2: Memory leaks
cp .codity/test-instructions-memory.yaml .codity/review-instructions.yaml
git add test_memory_patterns.py .codity/review-instructions.yaml
git commit -m "Test: memory leak detection"
git push
# Trigger review, expect 4 warnings about unclosed resources

# Test 3: Error handling (Go)
cp .codity/test-instructions-error-handling.yaml .codity/review-instructions.yaml
git add test_error_handling.go .codity/review-instructions.yaml
git commit -m "Test: Go error handling"
git push
# Trigger review, expect 5 warnings about ignored errors/panics

# Test 4: Security (TypeScript)
cp .codity/test-instructions-security.yaml .codity/review-instructions.yaml
git add test_authentication.ts .codity/review-instructions.yaml
git commit -m "Test: TypeScript security issues"
git push
# Trigger review, expect 6 warnings about auth/hardcoded secrets

# Test 5: Performance (Ruby)
cp .codity/test-instructions-performance.yaml .codity/review-instructions.yaml
git add test_performance.rb .codity/review-instructions.yaml
git commit -m "Test: Ruby performance anti-patterns"
git push
# Trigger review, expect 4 warnings about N+1/string concat/nested loops
```

## Expected Behavior Matrix

| Test | Priority Set | Expected Warnings | Should Skip |
|------|-------------|------------------|-------------|
| test_loops.py | Code Efficiency | 3 (for loops) | style, formatting |
| test_memory_patterns.py | Memory Management | 4 (unclosed resources) | style, formatting |
| test_error_handling.go | Error Handling | 5 (ignored errors) | style, performance |
| test_authentication.ts | Authentication | 6 (auth issues) | performance, style |
| test_performance.rb | Performance | 4 (N+1, loops) | security, style |

## Notes

- Each test should be run on a separate branch or separate PR
- Monitor terminal logs for "LLM filtering" messages
- Check "Feedbacks before filtering" vs "Feedbacks after filtering" counts
- Verify custom instructions are loaded: "✅ Successfully loaded custom review instructions"
