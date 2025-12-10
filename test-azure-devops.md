# Azure DevOps Integration Test

This is a test file to verify Azure DevOps integration with Codity.

## Test Scenarios

1. **PR Creation**: Test creating a PR in Azure DevOps
2. **Code Review**: Verify automated code review functionality
3. **Custom Instructions**: Test custom review instructions detection
4. **Severity Badges**: Verify colored severity badges display correctly

## Expected Behavior

- PR review should start automatically
- Custom instructions should be detected from `.codity/review-instructions.yaml`
- Security, functionality, and performance issues should be identified
- Badges should display with proper colors and formatting
