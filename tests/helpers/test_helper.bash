#!/usr/bin/env bash

# Test helper functions for bats tests
# Provides common utilities and setup for all test files

# Set up environment variables
export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
export TEST_TIMEOUT=30

# Colors for test output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m' # No Color

# Test utilities
test_info() {
    echo "# INFO: $1" >&3
}

test_debug() {
    if [[ "${TEST_DEBUG:-false}" == "true" ]]; then
        echo "# DEBUG: $1" >&3
    fi
}

test_warning() {
    echo "# WARNING: $1" >&3
}

# Skip test with reason
skip_if_missing() {
    local command="$1"
    local reason="$2"

    if ! command -v "$command" &> /dev/null; then
        skip "$reason (missing: $command)"
    fi
}

# Check if we're in CI environment
is_ci() {
    [[ "${CI:-false}" == "true" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]
}

# Wait for condition with timeout
wait_for_condition() {
    local condition="$1"
    local timeout="${2:-10}"
    local interval="${3:-1}"

    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if eval "$condition"; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    return 1
}

# Create temporary test files
create_test_workflow() {
    local filename="${1:-test-workflow.json}"
    local content="${2:-basic}"

    case "$content" in
        "basic")
            cat > "$filename" << 'EOF'
{
  "name": "Test Workflow",
  "nodes": [
    {
      "id": "webhook1",
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "test/webhook",
        "httpMethod": "POST"
      }
    }
  ],
  "connections": {}
}
EOF
            ;;
        "complex")
            cat > "$filename" << 'EOF'
{
  "name": "Complex Test Workflow",
  "nodes": [
    {
      "id": "webhook1",
      "name": "Start Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "disposable-marketplace/start",
        "httpMethod": "POST",
        "responseMode": "lastNode"
      }
    },
    {
      "id": "function1",
      "name": "Validate Input",
      "type": "n8n-nodes-base.function",
      "parameters": {
        "functionCode": "return [{json: $json}];"
      }
    },
    {
      "id": "http1",
      "name": "Fetch Data",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "https://api.example.com/data",
        "method": "GET"
      }
    }
  ],
  "connections": {
    "webhook1": {
      "main": [
        [
          {
            "node": "function1",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "function1": {
      "main": [
        [
          {
            "node": "http1",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  }
}
EOF
            ;;
        "invalid")
            echo 'invalid json content{' > "$filename"
            ;;
        "empty")
            echo '{}' > "$filename"
            ;;
    esac
}

create_test_csv() {
    local filename="${1:-test-resellers.csv}"
    local rows="${2:-5}"

    cat > "$filename" << 'EOF'
id,name,email,region,trust_score,specialty
EOF

    for i in $(seq 1 "$rows"); do
        echo "RESELLER_${i},Test Reseller ${i},test${i}@example.com,US,7.5,General" >> "$filename"
    done
}

# Mock server utilities
start_mock_server() {
    local port="${1:-3000}"
    local responses_file="${2:-}"

    if command -v python3 &> /dev/null; then
        # Start simple Python HTTP server for testing
        python3 -c "
import http.server
import socketserver
import json
from urllib.parse import urlparse, parse_qs

class MockHandler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

        response = {'status': 'success', 'received': post_data.decode('utf-8')[:100]}
        self.wfile.write(json.dumps(response).encode())

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{\"status\":\"ok\"}')
        else:
            super().do_GET()

with socketserver.TCPServer(('', $port), MockHandler) as httpd:
    httpd.serve_forever()
" &
        echo $! > "${TEST_DIR}/mock_server.pid"

        # Wait for server to start
        wait_for_condition "curl -s http://localhost:$port/health > /dev/null 2>&1" 5
    else
        skip "Python3 not available for mock server"
    fi
}

stop_mock_server() {
    if [[ -f "${TEST_DIR}/mock_server.pid" ]]; then
        local pid=$(cat "${TEST_DIR}/mock_server.pid")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid"
        fi
        rm -f "${TEST_DIR}/mock_server.pid"
    fi
}

# Performance testing utilities
measure_execution_time() {
    local command="$1"
    local start_time end_time duration

    start_time=$(date +%s.%N)
    eval "$command"
    local exit_code=$?
    end_time=$(date +%s.%N)

    if command -v bc &> /dev/null; then
        duration=$(echo "$end_time - $start_time" | bc -l)
    else
        duration=$((${end_time%.*} - ${start_time%.*}))
    fi

    echo "$duration"
    return $exit_code
}

# File size utilities
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Memory usage utilities
get_memory_usage() {
    local pid="$1"
    if ps -p "$pid" > /dev/null 2>&1; then
        ps -o rss= -p "$pid" | tr -d ' '
    else
        echo "0"
    fi
}

# Network testing utilities
is_port_open() {
    local host="${1:-localhost}"
    local port="$2"
    local timeout="${3:-5}"

    if command -v nc &> /dev/null; then
        nc -z -w "$timeout" "$host" "$port" 2>/dev/null
    elif command -v telnet &> /dev/null; then
        timeout "$timeout" telnet "$host" "$port" </dev/null 2>/dev/null | grep -q "Connected"
    else
        # Fallback using /dev/tcp (bash built-in)
        timeout "$timeout" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null
    fi
}

# JSON utilities
validate_json() {
    local file="$1"
    if command -v jq &> /dev/null; then
        jq empty "$file" 2>/dev/null
    elif command -v python3 &> /dev/null; then
        python3 -c "import json; json.load(open('$file'))" 2>/dev/null
    else
        return 1
    fi
}

extract_json_field() {
    local file="$1"
    local field="$2"

    if command -v jq &> /dev/null; then
        jq -r "$field" "$file" 2>/dev/null
    elif command -v python3 &> /dev/null; then
        python3 -c "
import json
import sys
try:
    data = json.load(open('$file'))
    # Simple field extraction (extend as needed)
    if '$field' == '.name':
        print(data.get('name', ''))
    elif '$field' == '.nodes | length':
        print(len(data.get('nodes', [])))
    else:
        print('')
except:
    print('')
"
    else
        return 1
    fi
}

# Security testing utilities
check_for_secrets() {
    local file="$1"
    local patterns=(
        "password.*="
        "secret.*="
        "token.*="
        "api[_-]?key.*="
        "Bearer [A-Za-z0-9]+"
        "sk-[A-Za-z0-9]+"
    )

    for pattern in "${patterns[@]}"; do
        if grep -qiE "$pattern" "$file" 2>/dev/null; then
            return 0  # Found potential secret
        fi
    done
    return 1  # No secrets found
}

# CSV utilities
validate_csv_headers() {
    local file="$1"
    local required_headers="$2"

    if [[ -f "$file" ]]; then
        local headers=$(head -1 "$file")
        [[ "$headers" == *"$required_headers"* ]]
    else
        return 1
    fi
}

count_csv_rows() {
    local file="$1"
    if [[ -f "$file" ]]; then
        echo $(($(wc -l < "$file") - 1))  # Subtract header row
    else
        echo "0"
    fi
}

# Cleanup utilities
cleanup_test_files() {
    local pattern="${1:-test-*}"
    find "${TEST_DIR:-/tmp}" -name "$pattern" -type f -delete 2>/dev/null || true
}

# Load environment-specific configurations
load_test_config() {
    local config_file="${PROJECT_ROOT}/tests/.env.test"
    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
    fi
}

# Initialize test environment
setup_test_environment() {
    # Load test configuration
    load_test_config

    # Set default timeouts
    export TEST_TIMEOUT="${TEST_TIMEOUT:-30}"
    export MOCK_SERVER_PORT="${MOCK_SERVER_PORT:-3001}"

    # Create test directories if needed
    mkdir -p "${TEST_DIR}/fixtures" "${TEST_DIR}/reports"
}

# Validate test environment
validate_test_environment() {
    local missing_commands=()

    # Check required commands
    command -v jq &> /dev/null || missing_commands+=("jq")
    command -v curl &> /dev/null || missing_commands+=("curl")

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        skip "Missing required commands: ${missing_commands[*]}"
    fi
}