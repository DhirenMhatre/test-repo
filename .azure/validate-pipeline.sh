#!/bin/bash
# Azure Pipelines Validation Script
# Checks if the pipeline configuration is valid and dependencies are ready

set -e

echo "========================================="
echo "Azure Pipelines Validation"
echo "========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if pipeline files exist
echo "1. Checking pipeline files..."
if [ -f "azure-pipelines.yml" ]; then
    echo -e "${GREEN}✓${NC} azure-pipelines.yml found"
else
    echo -e "${RED}✗${NC} azure-pipelines.yml NOT found"
    exit 1
fi

if [ -f ".azure/pipelines/quick-test.yml" ]; then
    echo -e "${GREEN}✓${NC} quick-test.yml found"
else
    echo -e "${YELLOW}⚠${NC} quick-test.yml NOT found (optional)"
fi

echo ""

# Check YAML syntax (basic validation)
echo "2. Validating YAML syntax..."
if command -v yamllint &> /dev/null; then
    yamllint azure-pipelines.yml && echo -e "${GREEN}✓${NC} YAML syntax valid" || echo -e "${RED}✗${NC} YAML syntax errors"
else
    echo -e "${YELLOW}⚠${NC} yamllint not installed, skipping YAML validation"
    echo "   Install with: pip install yamllint"
fi

echo ""

# Check for required tools
echo "3. Checking local development tools..."

# Go
if command -v go &> /dev/null; then
    echo -e "${GREEN}✓${NC} Go $(go version | awk '{print $3}')"
else
    echo -e "${YELLOW}⚠${NC} Go not installed"
fi

# Python
if command -v python3 &> /dev/null; then
    echo -e "${GREEN}✓${NC} Python $(python3 --version | awk '{print $2}')"
else
    echo -e "${YELLOW}⚠${NC} Python not installed"
fi

# Ruby
if command -v ruby &> /dev/null; then
    echo -e "${GREEN}✓${NC} Ruby $(ruby --version | awk '{print $2}')"
else
    echo -e "${YELLOW}⚠${NC} Ruby not installed"
fi

# Node.js
if command -v node &> /dev/null; then
    echo -e "${GREEN}✓${NC} Node.js $(node --version)"
else
    echo -e "${YELLOW}⚠${NC} Node.js not installed"
fi

echo ""

# Check project structure
echo "4. Checking project structure..."
projects_found=0

# Change to repository root if we're in .azure directory
if [ -f "../azure-pipelines.yml" ]; then
    cd ..
fi

if [ -f "go-service/go.mod" ]; then
    echo -e "${GREEN}✓${NC} Go service found"
    projects_found=$((projects_found + 1))
fi

if [ -f "python-service/requirements.txt" ]; then
    echo -e "${GREEN}✓${NC} Python service found"
    projects_found=$((projects_found + 1))
fi

if [ -f "ruby-service/Gemfile" ]; then
    echo -e "${GREEN}✓${NC} Ruby service found"
    projects_found=$((projects_found + 1))
fi

if [ -f "js-service/package.json" ]; then
    echo -e "${GREEN}✓${NC} JavaScript service found"
    projects_found=$((projects_found + 1))
fi

echo ""
echo "Found $projects_found out of 4 services"

echo ""

# Check test files
echo "5. Checking for test files..."
go_tests=$(find . -name "*_test.go" 2>/dev/null | wc -l)
py_tests=$(find . -name "test_*.py" -o -name "*_test.py" 2>/dev/null | wc -l)
rb_tests=$(find . -name "*_spec.rb" 2>/dev/null | wc -l)
js_tests=$(find . -name "*.test.js" -o -name "*.test.ts" -o -name "*.spec.js" -o -name "*.spec.ts" 2>/dev/null | wc -l)

echo "  - Go test files: $go_tests"
echo "  - Python test files: $py_tests"
echo "  - Ruby spec files: $rb_tests"
echo "  - JavaScript/TypeScript test files: $js_tests"

total_tests=$((go_tests + py_tests + rb_tests + js_tests))
if [ $total_tests -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $total_tests test files"
else
    echo -e "${YELLOW}⚠${NC} No test files found"
fi

echo ""
echo "========================================="
echo "Validation Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Commit the pipeline files to your repository"
echo "  2. Push to Azure DevOps"
echo "  3. Create a new pipeline in Azure DevOps using azure-pipelines.yml"
echo "  4. Create a PR to test the pipeline"
echo ""
echo "For detailed setup instructions, see:"
echo "  .azure/AZURE_PIPELINES_SETUP.md"
echo ""
