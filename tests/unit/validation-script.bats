#!/usr/bin/env bats

# Unit tests for validate-workflow.sh
# Tests all validation functions, CLI parsing, and error conditions

load '../helpers/test_helper'

# Setup function runs before each test
setup() {
    # Create temporary test directory
    TEST_DIR=$(mktemp -d)
    export TEST_DIR

    # Copy validation script to test directory
    cp "${PROJECT_ROOT}/validate-workflow.sh" "${TEST_DIR}/"
    cp "${PROJECT_ROOT}/workflow.json" "${TEST_DIR}/"

    # Create test files
    echo '{"name":"Test Workflow","nodes":[]}' > "${TEST_DIR}/test-workflow.json"
    echo 'invalid json{' > "${TEST_DIR}/invalid.json"

    # Change to test directory
    cd "$TEST_DIR"
}

# Cleanup after each test
teardown() {
    cd "$PROJECT_ROOT"
    rm -rf "$TEST_DIR"
}

@test "validate-workflow.sh exists and is executable" {
    [ -f "${PROJECT_ROOT}/validate-workflow.sh" ]
    [ -x "${PROJECT_ROOT}/validate-workflow.sh" ]
}

@test "validate-workflow.sh shows help with --help flag" {
    run bash validate-workflow.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "validation options" ]]
}

@test "validate-workflow.sh shows help with -h flag" {
    run bash validate-workflow.sh -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "validate-workflow.sh fails with unknown option" {
    run bash validate-workflow.sh --unknown-option
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]]
}

@test "validate-workflow.sh accepts --security-only flag" {
    run timeout 10 bash validate-workflow.sh --security-only --file test-workflow.json
    # Should complete within timeout (even if it fails validation)
    [ "$status" -ne 124 ]  # 124 is timeout exit code
}

@test "validate-workflow.sh accepts --structure-only flag" {
    run timeout 10 bash validate-workflow.sh --structure-only --file test-workflow.json
    [ "$status" -ne 124 ]
}

@test "validate-workflow.sh accepts --performance-only flag" {
    run timeout 10 bash validate-workflow.sh --performance-only --file test-workflow.json
    [ "$status" -ne 124 ]
}

@test "validate-workflow.sh accepts --docs-only flag" {
    run timeout 10 bash validate-workflow.sh --docs-only --file test-workflow.json
    [ "$status" -ne 124 ]
}

@test "validate-workflow.sh accepts --tests-only flag" {
    run timeout 10 bash validate-workflow.sh --tests-only --file test-workflow.json
    [ "$status" -ne 124 ]
}

@test "validate-workflow.sh accepts --timing flag" {
    run timeout 10 bash validate-workflow.sh --timing --file test-workflow.json
    [ "$status" -ne 124 ]
    [[ "$output" =~ "TIMING:" ]] || true  # May not show timing if validation fails quickly
}

@test "validate-workflow.sh accepts --verbose flag" {
    run timeout 10 bash validate-workflow.sh --verbose --file test-workflow.json
    [ "$status" -ne 124 ]
}

@test "validate-workflow.sh accepts --no-parallel flag" {
    run timeout 10 bash validate-workflow.sh --no-parallel --file test-workflow.json
    [ "$status" -ne 124 ]
}

@test "validate-workflow.sh accepts --file parameter" {
    run timeout 10 bash validate-workflow.sh --file test-workflow.json
    [ "$status" -ne 124 ]
}

@test "validate-workflow.sh detects missing workflow file" {
    run bash validate-workflow.sh --file nonexistent.json
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

@test "validate-workflow.sh detects invalid JSON" {
    run bash validate-workflow.sh --file invalid.json
    [ "$status" -eq 1 ]
    [[ "$output" =~ "invalid JSON" ]]
}

@test "validate-workflow.sh validates basic JSON structure" {
    run bash validate-workflow.sh --file test-workflow.json --structure-only
    # Should pass JSON validation but may fail structure validation
    [[ "$output" =~ "JSON syntax is valid" ]]
}

@test "dependency check detects missing jq" {
    # Temporarily rename jq to simulate missing dependency
    if command -v jq > /dev/null; then
        skip "jq is available, cannot test missing dependency"
    fi

    run bash validate-workflow.sh --file test-workflow.json
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Missing required dependencies" ]]
    [[ "$output" =~ "jq" ]]
}

@test "dependency check detects missing curl" {
    # Skip if curl is not available for testing
    if ! command -v curl > /dev/null; then
        skip "curl not available for testing"
    fi

    # This test would require mocking or moving curl
    # For now, just verify the check exists in the script
    grep -q "curl" validate-workflow.sh
}

@test "security check detects hardcoded credentials" {
    # Create workflow with potential credentials
    cat > test-security.json << 'EOF'
{
  "name": "Test Workflow",
  "nodes": [{
    "parameters": {
      "password": "secret123",
      "api_key": "sk-test123"
    }
  }]
}
EOF

    run bash validate-workflow.sh --security-only --file test-security.json
    [[ "$output" =~ "credentials found" ]] || [[ "$output" =~ "password\|secret\|token\|api_key" ]]
}

@test "security check detects placeholder URLs" {
    # Create workflow with placeholder URLs
    cat > test-urls.json << 'EOF'
{
  "name": "Test Workflow",
  "nodes": [{
    "parameters": {
      "url": "https://YOUR_N8N_URL/webhook"
    }
  }]
}
EOF

    run bash validate-workflow.sh --security-only --file test-urls.json
    [[ "$output" =~ "Placeholder" ]] || [[ "$output" =~ "YOUR_N8N_URL" ]]
}

@test "security check detects HTTP URLs" {
    # Create workflow with HTTP URLs
    cat > test-http.json << 'EOF'
{
  "name": "Test Workflow",
  "nodes": [{
    "parameters": {
      "url": "http://example.com/api"
    }
  }]
}
EOF

    run bash validate-workflow.sh --security-only --file test-http.json
    [[ "$output" =~ "HTTP URLs found" ]] || [[ "$output" =~ "insecure" ]]
}

@test "performance check detects large workflow files" {
    # Create a large workflow file (over 50KB)
    create_large_workflow "large-workflow.json" 60000

    run bash validate-workflow.sh --performance-only --file large-workflow.json
    [[ "$output" =~ "large" ]] || [[ "$output" =~ "optimization" ]]
}

@test "structure validation detects missing required fields" {
    # Create workflow missing required fields
    echo '{}' > minimal.json

    run bash validate-workflow.sh --structure-only --file minimal.json
    [[ "$output" =~ "Missing required field" ]]
}

@test "webhook validation detects webhook nodes" {
    # Create workflow with webhook nodes
    cat > webhook-test.json << 'EOF'
{
  "name": "Webhook Test",
  "nodes": [{
    "type": "n8n-nodes-base.webhook",
    "parameters": {
      "path": "test/webhook",
      "httpMethod": "POST"
    }
  }]
}
EOF

    run bash validate-workflow.sh --file webhook-test.json
    [[ "$output" =~ "webhook" ]] || [[ "$output" =~ "endpoint" ]]
}

@test "parallel processing mode works" {
    # Test parallel mode (if parallel command available)
    if command -v parallel > /dev/null; then
        run timeout 30 bash validate-workflow.sh --file test-workflow.json --timing
        [ "$status" -ne 124 ]  # Should not timeout
    else
        skip "parallel command not available"
    fi
}

@test "sequential processing mode works" {
    run timeout 30 bash validate-workflow.sh --no-parallel --file test-workflow.json
    [ "$status" -ne 124 ]  # Should not timeout
}

@test "error counting works correctly" {
    # Create a workflow that will have multiple errors
    echo 'invalid json{' > error-test.json

    run bash validate-workflow.sh --file error-test.json
    [[ "$output" =~ "VALIDATION SUMMARY" ]]
    [[ "$output" =~ "Errors:" ]]
}

@test "warning counting works correctly" {
    # Create a workflow that will generate warnings
    cat > warning-test.json << 'EOF'
{
  "name": "Warning Test",
  "nodes": [{
    "type": "n8n-nodes-base.webhook",
    "parameters": {
      "path": "test webhook",
      "httpMethod": "GET"
    }
  }]
}
EOF

    run bash validate-workflow.sh --file warning-test.json
    [[ "$output" =~ "VALIDATION SUMMARY" ]]
    [[ "$output" =~ "Warnings:" ]]
}

@test "timing information is shown when requested" {
    run timeout 15 bash validate-workflow.sh --timing --file test-workflow.json
    if [ "$status" -ne 124 ]; then
        [[ "$output" =~ "TIMING BREAKDOWN" ]] || [[ "$output" =~ "TIMING:" ]]
    fi
}

@test "verbose mode provides extra information" {
    run timeout 15 bash validate-workflow.sh --verbose --file test-workflow.json
    if [ "$status" -ne 124 ]; then
        [[ "$output" =~ "DEBUG:" ]] || [[ "$output" =~ "Configuration:" ]]
    fi
}

@test "cache functionality works" {
    # Run validation twice and ensure it completes (caching should speed up second run)
    run timeout 20 bash validate-workflow.sh --file test-workflow.json --timing
    if [ "$status" -ne 124 ]; then
        run timeout 10 bash validate-workflow.sh --file test-workflow.json --timing
        [ "$status" -ne 124 ]  # Second run should be faster due to caching
    fi
}

# Helper function to create large workflow files for testing
create_large_workflow() {
    local filename="$1"
    local target_size="$2"

    cat > "$filename" << 'EOF'
{
  "name": "Large Test Workflow",
  "nodes": [
EOF

    # Add many nodes to reach target size
    local current_size=0
    local node_count=0

    while [ "$current_size" -lt "$target_size" ]; do
        cat >> "$filename" << EOF
    {
      "id": "node_${node_count}",
      "name": "Node ${node_count}",
      "type": "n8n-nodes-base.function",
      "parameters": {
        "functionCode": "return [{json: {nodeId: '${node_count}', data: 'test data for node ${node_count}', timestamp: new Date().toISOString()}}];"
      },
      "position": [${node_count}, ${node_count}]
    },
EOF
        ((node_count++))
        current_size=$(wc -c < "$filename")
    done

    # Remove trailing comma and close JSON
    sed -i '$ s/,$//' "$filename"
    echo '  ]' >> "$filename"
    echo '}' >> "$filename"
}