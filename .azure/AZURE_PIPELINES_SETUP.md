# Azure Pipelines Setup Guide

This repository is configured with Azure Pipelines for continuous integration testing across multiple languages.

## Pipeline Files

### 1. Main Pipeline: `azure-pipelines.yml`
**Location**: Root directory
**Trigger**: PRs and commits to main/master/develop/codity/* branches
**Jobs**:
- `GoTests` - Tests all Go modules
- `PythonTests` - Tests all Python packages
- `RubyTests` - Tests all Ruby projects
- `JavaScriptTests` - Tests all Node.js/TypeScript projects
- `IntegrationTests` - Runs after all language tests pass

### 2. Quick Test Pipeline: `.azure/pipelines/quick-test.yml`
**Location**: `.azure/pipelines/quick-test.yml`
**Trigger**: PRs only, especially for `codity/*` branches
**Purpose**: Faster feedback for generated tests
**Jobs**: Same languages but optimized for speed

## Supported Languages & Test Commands

### Go (1.21)
```bash
cd go-service
go mod download
go test -v ./...
```

### Python (3.11)
```bash
cd python-service
pip install -r requirements.txt
pytest -v
```

### Ruby (3.2)
```bash
cd ruby-service
bundle install
bundle exec rspec --format documentation
```

### JavaScript/TypeScript (Node 20)
```bash
cd js-service
npm install
npm test
```

## Setup in Azure DevOps

### 1. Create New Pipeline

1. Go to **Pipelines** → **New Pipeline**
2. Select **Azure Repos Git** (or GitHub if using GitHub)
3. Choose your repository
4. Select **Existing Azure Pipelines YAML file**
5. Choose `/azure-pipelines.yml`
6. Click **Run**

### 2. Configure Branch Protection

1. Go to **Repos** → **Branches**
2. Select your main branch → **Branch Policies**
3. Enable **Build Validation**
4. Add the pipeline you just created
5. Set **Policy requirement** to **Required**

### 3. Configure PR Triggers

The pipeline is already configured to run on all PRs:
```yaml
pr:
  branches:
    include:
      - '*'
```

## Testing the Pipeline

### Test Locally (Optional)
Before pushing, you can test locally using Make:
```bash
# Test all languages
make test

# Test individual languages
cd go-service && go test -v ./...
cd python-service && pytest -v
cd ruby-service && bundle exec rspec
cd js-service && npm test
```

### Create Test PR
1. Create a new branch:
   ```bash
   git checkout -b test/azure-pipeline
   ```

2. Make a small change to any file

3. Commit and push:
   ```bash
   git add .
   git commit -m "Test Azure Pipeline"
   git push origin test/azure-pipeline
   ```

4. Create a Pull Request in Azure DevOps

5. Watch the pipeline run automatically!

## Pipeline Stages & Jobs

### Stage 1: Test
Runs all language-specific tests in parallel:
```
┌─────────────────────────────────────────┐
│           Test Stage (Parallel)          │
├──────────┬──────────┬──────────┬─────────┤
│  Go      │ Python   │  Ruby    │   JS    │
│  Tests   │  Tests   │  Tests   │  Tests  │
└──────────┴──────────┴──────────┴─────────┘
```

### Stage 2: Integration Tests
Runs only after all language tests pass:
```
┌─────────────────────────────────────────┐
│        Integration Tests Stage           │
│  (Depends on: Test Stage Success)        │
└─────────────────────────────────────────┘
```

## CI Status Badges

Add to your README.md:
```markdown
[![Build Status](https://dev.azure.com/{organization}/{project}/_apis/build/status/{pipeline-name}?branchName=main)](https://dev.azure.com/{organization}/{project}/_build/latest?definitionId={pipeline-id}&branchName=main)
```

## Troubleshooting

### Pipeline doesn't trigger on PR
- Check **Branch Policies** are enabled
- Verify `pr:` trigger in YAML
- Ensure Azure Pipelines has repository access

### Tests fail in pipeline but pass locally
- Check Python/Ruby/Node versions match
- Verify all dependencies are installed
- Check for environment-specific issues

### Go tests timeout
- Increase timeout in pipeline settings
- Optimize test execution
- Consider splitting into multiple jobs

### Python tests fail with import errors
- Ensure all `requirements.txt` files are found
- Check PYTHONPATH settings
- Verify package structure

### Ruby tests fail with bundle errors
- Check Gemfile.lock is committed
- Verify Ruby version matches
- Try `bundle update` locally

### JavaScript tests fail
- Check Node.js version (20.x)
- Verify package.json scripts
- Ensure all dependencies are in package.json

## Codity Integration

This repository is integrated with **Codity** for automated test generation and CI auto-fixing.

### How It Works
1. Comment `/generate-tests` on any Azure DevOps PR
2. Codity analyzes changed files
3. Generates tests for Go, Python, Ruby, and JavaScript/TypeScript
4. Creates a test branch: `codity/add-tests-pr-{id}`
5. Commits generated tests
6. **Azure Pipeline runs automatically**
7. **CI Auto-Fixer monitors the build**:
   - Attempt 1: Applies comprehensive fixes
   - Attempt 2: Retry with adjustments
   - Attempt 3: Final fix attempt
   - Cleanup: Removes failing tests, keeps passing ones
8. Final PR comment with results

### CI Auto-Fixer Features
- ✅ Monitors Azure Pipelines build status
- ✅ Parses test failure logs (Go, Python, Ruby, Jest)
- ✅ Applies strategic fixes using LLM
- ✅ 3 automatic fix attempts
- ✅ Intelligent cleanup preserving passing tests
- ✅ Full metrics tracking in database

### Test Branch Pipeline
Test branches (`codity/*`) trigger the pipeline automatically:
```yaml
trigger:
  branches:
    include:
      - 'codity/*'
```

This ensures generated tests are validated immediately after commit.

## Advanced Configuration

### Custom Test Commands
Edit `azure-pipelines.yml` to customize test commands:
```yaml
- script: |
    go test -v -race -coverprofile=coverage.out ./...
  displayName: 'Run Go Tests with Coverage'
```

### Parallel Execution
Tests run in parallel by default. To run sequentially:
```yaml
jobs:
  - job: AllTests
    steps:
      - script: make test
```

### Cache Dependencies
Speed up builds by caching:
```yaml
- task: Cache@2
  inputs:
    key: 'go | "$(Agent.OS)" | go-service/go.sum'
    path: $(go env GOMODCACHE)
  displayName: 'Cache Go modules'
```

## Pipeline Monitoring

### View Pipeline Runs
1. Go to **Pipelines** → **All Pipelines**
2. Select your pipeline
3. View run history and logs

### Failed Build Notification
- Configure email notifications in Azure DevOps
- Integrate with Slack/Teams for alerts
- Set up Azure Monitor for analytics

## Support

For issues:
- Check pipeline logs in Azure DevOps
- Review this documentation
- Test locally using `make test`
- Contact DevOps team

---

**Last Updated**: 2025-12-13
**Pipeline Version**: 1.0
**Codity Integration**: Enabled
