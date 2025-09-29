#!/bin/bash

# Test Environment Setup Script
# Prepares the testing environment and installs all necessary dependencies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# Install system dependencies
install_system_deps() {
    local os=$(detect_os)
    log_info "Installing system dependencies for $os..."

    case "$os" in
        "linux")
            # Update package list
            if command -v apt-get &> /dev/null; then
                sudo apt-get update

                # Install required packages
                sudo apt-get install -y \
                    jq \
                    curl \
                    bc \
                    parallel \
                    shellcheck \
                    git

                log_success "System dependencies installed via apt"

            elif command -v yum &> /dev/null; then
                sudo yum install -y \
                    jq \
                    curl \
                    bc \
                    parallel \
                    ShellCheck \
                    git

                log_success "System dependencies installed via yum"

            else
                log_warning "Unknown Linux package manager. Please install manually: jq, curl, bc, parallel, shellcheck"
            fi
            ;;

        "macos")
            # Install via Homebrew
            if ! command -v brew &> /dev/null; then
                log_error "Homebrew not found. Please install Homebrew first: https://brew.sh"
                exit 1
            fi

            brew install jq curl bc parallel shellcheck git
            log_success "System dependencies installed via Homebrew"
            ;;

        "windows")
            log_warning "Windows detected. Please install dependencies manually:"
            echo "  - jq: https://stedolan.github.io/jq/"
            echo "  - curl: Usually available in Windows 10+"
            echo "  - Git: https://git-scm.com/download/win"
            ;;

        *)
            log_warning "Unknown OS. Please install manually: jq, curl, bc, parallel, shellcheck"
            ;;
    esac
}

# Install BATS testing framework
install_bats() {
    log_info "Installing BATS testing framework..."

    if command -v bats &> /dev/null; then
        log_success "BATS already installed"
        return 0
    fi

    # Create temporary directory for BATS installation
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    # Clone and install BATS
    git clone https://github.com/bats-core/bats-core.git
    cd bats-core

    if [[ $(detect_os) == "macos" ]]; then
        # On macOS, install to user directory if sudo not available
        if ./install.sh /usr/local 2>/dev/null; then
            log_success "BATS installed to /usr/local"
        else
            ./install.sh "$HOME/.local"
            log_success "BATS installed to $HOME/.local"
            log_warning "Add $HOME/.local/bin to your PATH"
        fi
    else
        sudo ./install.sh /usr/local
        log_success "BATS installed to /usr/local"
    fi

    # Clean up
    cd "$PROJECT_ROOT"
    rm -rf "$temp_dir"
}

# Install Node.js dependencies
install_node_deps() {
    log_info "Installing Node.js dependencies..."

    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        log_error "Node.js not found. Please install Node.js 16+ from https://nodejs.org"
        exit 1
    fi

    local node_version=$(node --version | sed 's/v//')
    log_info "Node.js version: $node_version"

    # Check Node.js version (require 16+)
    if [ "$(printf '%s\n' "16.0.0" "$node_version" | sort -V | head -n1)" != "16.0.0" ]; then
        log_error "Node.js 16+ required. Current version: $node_version"
        exit 1
    fi

    # Install test dependencies
    cd "$TESTS_DIR"

    if [[ -f package-lock.json ]]; then
        npm ci
    else
        npm install
    fi

    log_success "Node.js dependencies installed"
    cd "$PROJECT_ROOT"
}

# Install Python security tools
install_python_security_tools() {
    log_info "Installing Python security tools..."

    if ! command -v python3 &> /dev/null; then
        log_warning "Python3 not found. Skipping Python security tools."
        return 0
    fi

    if ! command -v pip3 &> /dev/null; then
        log_warning "pip3 not found. Skipping Python security tools."
        return 0
    fi

    # Install security scanning tools
    pip3 install --user bandit safety semgrep || {
        log_warning "Failed to install some Python security tools. Continuing..."
    }

    log_success "Python security tools installed"
}

# Create test directories
create_test_dirs() {
    log_info "Creating test directories..."

    local dirs=(
        "$TESTS_DIR/fixtures"
        "$TESTS_DIR/mocks"
        "$TESTS_DIR/reports"
        "$TESTS_DIR/reports/coverage"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done

    log_success "Test directories created"
}

# Create test configuration files
create_test_config() {
    log_info "Creating test configuration files..."

    # Create .env.test file
    cat > "$TESTS_DIR/.env.test" << 'EOF'
# Test Environment Configuration
TEST_DEBUG=false
TEST_TIMEOUT=30000
MOCK_SERVER_PORT=3001
N8N_URL=http://localhost:5678

# CI Environment Detection
CI=${CI:-false}
GITHUB_ACTIONS=${GITHUB_ACTIONS:-false}

# Test Data URLs
TEST_CSV_URL=https://httpbin.org/response-headers?content-type=text/csv
INVALID_CSV_URL=https://httpbin.org/status/404
EOF

    # Create .bats_env file
    cat > "$TESTS_DIR/.bats_env" << 'EOF'
# BATS Test Environment
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TEST_DEBUG=${TEST_DEBUG:-false}
export TEST_TIMEOUT=${TEST_TIMEOUT:-30}
EOF

    log_success "Test configuration files created"
}

# Set up test fixtures
setup_test_fixtures() {
    log_info "Setting up test fixtures..."

    local fixtures_dir="$TESTS_DIR/fixtures"

    # Create sample CSV files
    cat > "$fixtures_dir/valid-resellers.csv" << 'EOF'
id,name,email,region,trust_score,specialty
ROLEX_SPEC,Rolex Specialists Inc,info@rolexspec.com,US,9.5,Rolex Only
WATCH_EXPERT,Watch Experts Ltd,contact@watchexp.com,UK,8.7,Luxury Watches
TIME_DEALERS,Time Dealers Co,sales@timedealers.com,US,9.2,Vintage Watches
SWISS_CONNECT,Swiss Connection,hello@swissconn.com,CH,9.8,Swiss Watches
LUXURY_TIME,Luxury Time LLC,info@luxurytime.com,US,8.5,High-End Watches
EOF

    cat > "$fixtures_dir/invalid-resellers.csv" << 'EOF'
name,email
Test Reseller,test@example.com
Another Reseller,another@example.com
EOF

    cat > "$fixtures_dir/malformed-resellers.csv" << 'EOF'
id,name,email,region,trust_score
RESELLER_1,Test Reseller 1,invalid-email,US,not-a-number
RESELLER_2,"Reseller with, comma",test@example.com,UK,8.5
EOF

    # Create test workflow files
    cat > "$fixtures_dir/minimal-workflow.json" << 'EOF'
{
  "name": "Minimal Test Workflow",
  "nodes": [
    {
      "id": "webhook1",
      "name": "Test Webhook",
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

    cat > "$fixtures_dir/invalid-workflow.json" << 'EOF'
{
  "name": "Invalid Workflow"
  "nodes": [
    {
      "missing": "comma above"
    }
  ]
}
EOF

    log_success "Test fixtures created"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."

    local errors=0

    # Check required commands
    local required_commands=("jq" "curl" "node" "npm")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            log_success "$cmd is available"
        else
            log_error "$cmd is not available"
            ((errors++))
        fi
    done

    # Check BATS
    if command -v bats &> /dev/null; then
        log_success "BATS is available"
    else
        log_warning "BATS is not available (optional for some tests)"
    fi

    # Check Node.js dependencies
    cd "$TESTS_DIR"
    if npm list --depth=0 &> /dev/null; then
        log_success "Node.js dependencies are properly installed"
    else
        log_error "Node.js dependencies have issues"
        ((errors++))
    fi
    cd "$PROJECT_ROOT"

    # Check test files
    if [[ -f "$PROJECT_ROOT/workflow.json" ]]; then
        if jq empty "$PROJECT_ROOT/workflow.json" &> /dev/null; then
            log_success "Main workflow.json is valid"
        else
            log_error "Main workflow.json is invalid JSON"
            ((errors++))
        fi
    else
        log_warning "Main workflow.json not found"
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "All verifications passed!"
        return 0
    else
        log_error "$errors verification(s) failed"
        return 1
    fi
}

# Run a quick test
run_quick_test() {
    log_info "Running quick test..."

    cd "$TESTS_DIR"

    # Test Node.js setup
    if node -e "console.log('Node.js test passed')" &> /dev/null; then
        log_success "Node.js quick test passed"
    else
        log_error "Node.js quick test failed"
        return 1
    fi

    # Test BATS if available
    if command -v bats &> /dev/null; then
        # Create a simple test
        cat > "/tmp/quick-test.bats" << 'EOF'
#!/usr/bin/env bats

@test "basic test" {
    [ "$?" -eq 0 ]
}
EOF

        if bats "/tmp/quick-test.bats" &> /dev/null; then
            log_success "BATS quick test passed"
        else
            log_warning "BATS quick test failed"
        fi

        rm -f "/tmp/quick-test.bats"
    fi

    cd "$PROJECT_ROOT"
    log_success "Quick test completed"
}

# Main setup function
main() {
    echo "🔧 N8N Workflow Test Environment Setup"
    echo "======================================"
    echo

    log_info "Starting test environment setup..."
    echo

    # Run setup steps
    install_system_deps
    echo

    install_bats
    echo

    install_node_deps
    echo

    install_python_security_tools
    echo

    create_test_dirs
    echo

    create_test_config
    echo

    setup_test_fixtures
    echo

    verify_installation
    echo

    run_quick_test
    echo

    log_success "🎉 Test environment setup completed!"
    echo
    echo "Next steps:"
    echo "  1. Run all tests: cd tests && npm test"
    echo "  2. Run unit tests: cd tests && npm run test:unit"
    echo "  3. Run integration tests: cd tests && npm run test:integration"
    echo "  4. Run security tests: tests/security/security-tests.sh"
    echo "  5. Run performance tests: cd tests && npm run test:performance"
    echo
    echo "For detailed test documentation, see: tests/README.md"
}

# Handle command line arguments
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << 'EOF'
N8N Workflow Test Environment Setup

Usage: ./setup.sh [OPTIONS]

Options:
  --help, -h    Show this help message
  --verify      Only run verification checks
  --quick-test  Only run quick tests

This script sets up the complete testing environment including:
- System dependencies (jq, curl, bc, parallel, shellcheck)
- BATS testing framework
- Node.js dependencies
- Python security tools
- Test directories and configuration
- Test fixtures and sample data

EOF
    exit 0
fi

if [[ "${1:-}" == "--verify" ]]; then
    verify_installation
    exit $?
fi

if [[ "${1:-}" == "--quick-test" ]]; then
    run_quick_test
    exit $?
fi

# Run main setup
main