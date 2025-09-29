#!/bin/bash

# Security Testing Suite for N8N Workflow
# Comprehensive security analysis including OWASP Top 10 and workflow-specific threats
# Tests for credential exposure, injection vulnerabilities, and configuration issues

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW_FILE="${PROJECT_ROOT}/workflow.json"
REPORT_DIR="${SCRIPT_DIR}/../reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SECURITY_REPORT="${REPORT_DIR}/security-report-${TIMESTAMP}.json"
VERBOSE=${VERBOSE:-false}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Counters
VULNERABILITIES=0
WARNINGS=0
PASSED=0

# Results storage
declare -a SECURITY_RESULTS=()

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

log_vulnerability() {
    echo -e "${RED}[VULN]${NC} $1"
    ((VULNERABILITIES++))
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

add_result() {
    local test_name="$1"
    local severity="$2"
    local description="$3"
    local details="${4:-}"

    SECURITY_RESULTS+=("{\"test\":\"$test_name\",\"severity\":\"$severity\",\"description\":\"$description\",\"details\":\"$details\"}")
}

# Check dependencies
check_dependencies() {
    log_info "Checking security testing dependencies..."

    local missing_deps=()

    command -v jq &> /dev/null || missing_deps+=("jq")
    command -v curl &> /dev/null || missing_deps+=("curl")

    # Optional security tools
    local optional_tools=()
    command -v semgrep &> /dev/null || optional_tools+=("semgrep")
    command -v bandit &> /dev/null || optional_tools+=("bandit")
    command -v safety &> /dev/null || optional_tools+=("safety")

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_vulnerability "Missing required dependencies: ${missing_deps[*]}"
        echo "Install with: sudo apt-get install ${missing_deps[*]}"
        exit 1
    fi

    if [[ ${#optional_tools[@]} -gt 0 && "$VERBOSE" == "true" ]]; then
        log_warning "Optional security tools missing: ${optional_tools[*]}"
        echo "Install for enhanced security scanning:"
        echo "  pip install semgrep bandit safety"
    fi

    log_success "Security testing dependencies verified"
}

# Test 1: Credential and Secret Detection
test_credential_exposure() {
    log_info "Testing for exposed credentials and secrets..."

    local workflow_content
    if ! workflow_content=$(cat "$WORKFLOW_FILE" 2>/dev/null); then
        log_vulnerability "Cannot read workflow file: $WORKFLOW_FILE"
        add_result "credential_exposure" "high" "Cannot access workflow file" "$WORKFLOW_FILE"
        return 1
    fi

    # High-risk patterns
    local high_risk_patterns=(
        "password\s*[:=]\s*['\"][^'\"]{3,}['\"]"
        "secret\s*[:=]\s*['\"][^'\"]{3,}['\"]"
        "api[_-]?key\s*[:=]\s*['\"][^'\"]{10,}['\"]"
        "token\s*[:=]\s*['\"][^'\"]{10,}['\"]"
        "private[_-]?key\s*[:=]\s*['\"][^'\"]{10,}['\"]"
        "sk-[a-zA-Z0-9]{32,}"
        "xoxb-[a-zA-Z0-9-]+"
        "ghp_[a-zA-Z0-9]{36}"
        "ey[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*"
    )

    # Medium-risk patterns
    local medium_risk_patterns=(
        "auth\s*[:=]\s*['\"][^'\"]{5,}['\"]"
        "bearer\s*[:=]\s*['\"][^'\"]{5,}['\"]"
        "x-api-key\s*[:=]\s*['\"][^'\"]{5,}['\"]"
        "authorization\s*[:=]\s*['\"][^'\"]{5,}['\"]"
    )

    local found_secrets=false

    # Check high-risk patterns
    for pattern in "${high_risk_patterns[@]}"; do
        if echo "$workflow_content" | grep -qiE "$pattern"; then
            local matches
            matches=$(echo "$workflow_content" | grep -iE "$pattern" | head -3)
            log_vulnerability "High-risk credential pattern detected: $pattern"
            add_result "credential_exposure" "high" "Potential hardcoded credential" "$pattern"

            if [[ "$VERBOSE" == "true" ]]; then
                echo "  Matches:"
                echo "$matches" | sed 's/^/    /'
            fi
            found_secrets=true
        fi
    done

    # Check medium-risk patterns
    for pattern in "${medium_risk_patterns[@]}"; do
        if echo "$workflow_content" | grep -qiE "$pattern"; then
            log_warning "Medium-risk authentication pattern detected: $pattern"
            add_result "credential_exposure" "medium" "Potential authentication credential" "$pattern"
            found_secrets=true
        fi
    done

    # Check for environment variable usage (good practice)
    if echo "$workflow_content" | grep -qE "\\\$\{[^}]+\}|process\.env\.|NODE_ENV"; then
        log_success "Environment variable usage detected (good practice)"
        add_result "credential_exposure" "info" "Environment variables used appropriately" ""
    fi

    if [[ "$found_secrets" == "false" ]]; then
        log_success "No hardcoded credentials detected"
        add_result "credential_exposure" "pass" "No hardcoded credentials found" ""
    fi
}

# Test 2: Injection Vulnerability Detection
test_injection_vulnerabilities() {
    log_info "Testing for injection vulnerabilities..."

    local workflow_content
    workflow_content=$(cat "$WORKFLOW_FILE")

    # Extract function code from workflow
    local function_codes
    function_codes=$(echo "$workflow_content" | jq -r '.nodes[] | select(.type == "n8n-nodes-base.function") | .parameters.functionCode' 2>/dev/null || echo "")

    if [[ -z "$function_codes" ]]; then
        log_warning "No function nodes found for injection testing"
        add_result "injection_vulnerabilities" "info" "No function nodes to analyze" ""
        return 0
    fi

    # Code injection patterns
    local injection_patterns=(
        "eval\s*\("
        "Function\s*\("
        "setTimeout\s*\([^,]*\$"
        "setInterval\s*\([^,]*\$"
        "new\s+Function\s*\("
        "vm\.runInThisContext"
        "vm\.runInNewContext"
        "child_process\.exec.*\$"
        "require\s*\([^)]*\$"
    )

    local found_injection=false

    for pattern in "${injection_patterns[@]}"; do
        if echo "$function_codes" | grep -qE "$pattern"; then
            local matches
            matches=$(echo "$function_codes" | grep -E "$pattern" | head -3)
            log_vulnerability "Potential code injection vulnerability: $pattern"
            add_result "injection_vulnerabilities" "high" "Potential code injection" "$pattern"

            if [[ "$VERBOSE" == "true" ]]; then
                echo "  Matches:"
                echo "$matches" | sed 's/^/    /'
            fi
            found_injection=true
        fi
    done

    # SQL injection patterns (if any database interactions)
    local sql_patterns=(
        "SELECT.*\+.*\$"
        "INSERT.*\+.*\$"
        "UPDATE.*\+.*\$"
        "DELETE.*\+.*\$"
        "query\s*\([^)]*\$[^)]*\)"
    )

    for pattern in "${sql_patterns[@]}"; do
        if echo "$function_codes" | grep -qiE "$pattern"; then
            log_vulnerability "Potential SQL injection vulnerability: $pattern"
            add_result "injection_vulnerabilities" "high" "Potential SQL injection" "$pattern"
            found_injection=true
        fi
    done

    # Command injection patterns
    local command_patterns=(
        "exec\s*\([^)]*\$[^)]*\)"
        "spawn\s*\([^)]*\$[^)]*\)"
        "system\s*\([^)]*\$[^)]*\)"
        "shell_exec.*\$"
    )

    for pattern in "${command_patterns[@]}"; do
        if echo "$function_codes" | grep -qiE "$pattern"; then
            log_vulnerability "Potential command injection vulnerability: $pattern"
            add_result "injection_vulnerabilities" "high" "Potential command injection" "$pattern"
            found_injection=true
        fi
    done

    if [[ "$found_injection" == "false" ]]; then
        log_success "No injection vulnerabilities detected"
        add_result "injection_vulnerabilities" "pass" "No injection patterns found" ""
    fi
}

# Test 3: Insecure Communication
test_insecure_communication() {
    log_info "Testing for insecure communication..."

    local workflow_content
    workflow_content=$(cat "$WORKFLOW_FILE")

    # Check for HTTP URLs (should be HTTPS)
    local http_urls
    if http_urls=$(echo "$workflow_content" | grep -oE 'http://[^"'\''[:space:]]+' | grep -v localhost); then
        log_warning "Insecure HTTP URLs detected (should use HTTPS):"
        echo "$http_urls" | head -5 | sed 's/^/  /'
        add_result "insecure_communication" "medium" "HTTP URLs found" "$http_urls"

        if [[ $(echo "$http_urls" | wc -l) -gt 5 ]]; then
            echo "  ... and $(($(echo "$http_urls" | wc -l) - 5)) more"
        fi
    else
        log_success "No insecure HTTP URLs detected"
        add_result "insecure_communication" "pass" "No HTTP URLs found" ""
    fi

    # Check for weak TLS configurations
    local weak_tls_patterns=(
        "sslVersion.*['\"]?ssl[v]?[12]['\"]?"
        "secureProtocol.*['\"]?SSL"
        "ciphers.*['\"]?RC4"
        "ciphers.*['\"]?DES"
        "rejectUnauthorized.*false"
    )

    local found_weak_tls=false
    for pattern in "${weak_tls_patterns[@]}"; do
        if echo "$workflow_content" | grep -qiE "$pattern"; then
            log_vulnerability "Weak TLS configuration detected: $pattern"
            add_result "insecure_communication" "high" "Weak TLS configuration" "$pattern"
            found_weak_tls=true
        fi
    done

    if [[ "$found_weak_tls" == "false" ]]; then
        log_success "No weak TLS configurations detected"
        add_result "insecure_communication" "pass" "No weak TLS configurations" ""
    fi
}

# Test 4: Input Validation
test_input_validation() {
    log_info "Testing input validation mechanisms..."

    local workflow_content
    workflow_content=$(cat "$WORKFLOW_FILE")

    # Check for validation patterns in function nodes
    local function_codes
    function_codes=$(echo "$workflow_content" | jq -r '.nodes[] | select(.type == "n8n-nodes-base.function") | .parameters.functionCode' 2>/dev/null || echo "")

    local validation_patterns=(
        "validate"
        "sanitize"
        "escape"
        "filter"
        "match\s*\("
        "test\s*\("
        "typeof"
        "instanceof"
        "hasOwnProperty"
        "Array\.isArray"
    )

    local found_validation=false
    for pattern in "${validation_patterns[@]}"; do
        if echo "$function_codes" | grep -qiE "$pattern"; then
            found_validation=true
            break
        fi
    done

    if [[ "$found_validation" == "true" ]]; then
        log_success "Input validation patterns detected"
        add_result "input_validation" "pass" "Input validation mechanisms found" ""
    else
        log_warning "No input validation patterns detected"
        add_result "input_validation" "medium" "No input validation found" "Consider adding input validation"
    fi

    # Check for dangerous input handling
    local dangerous_patterns=(
        "\\\$json\[.*\\\$"
        "\\\$input.*\\\$"
        "innerHTML.*\\\$"
        "document\.write.*\\\$"
    )

    local found_dangerous=false
    for pattern in "${dangerous_patterns[@]}"; do
        if echo "$function_codes" | grep -qE "$pattern"; then
            log_vulnerability "Dangerous input handling detected: $pattern"
            add_result "input_validation" "high" "Dangerous input handling" "$pattern"
            found_dangerous=true
        fi
    done

    if [[ "$found_dangerous" == "false" ]]; then
        log_success "No dangerous input handling patterns detected"
        add_result "input_validation" "pass" "No dangerous input patterns" ""
    fi
}

# Test 5: Configuration Security
test_configuration_security() {
    log_info "Testing configuration security..."

    local workflow_content
    workflow_content=$(cat "$WORKFLOW_FILE")

    # Check for development/debug configurations
    local debug_patterns=(
        "debug.*true"
        "development"
        "localhost"
        "127\.0\.0\.1"
        "0\.0\.0\.0"
        "YOUR_.*_URL"
        "test.*password"
        "admin.*admin"
    )

    local found_debug=false
    for pattern in "${debug_patterns[@]}"; do
        if echo "$workflow_content" | grep -qiE "$pattern"; then
            log_warning "Development/debug configuration detected: $pattern"
            add_result "configuration_security" "medium" "Development configuration" "$pattern"
            found_debug=true
        fi
    done

    if [[ "$found_debug" == "false" ]]; then
        log_success "No development configurations detected"
        add_result "configuration_security" "pass" "No development configs" ""
    fi

    # Check for proper error handling
    local error_handling_patterns=(
        "try\s*\{"
        "catch\s*\("
        "throw\s*"
        "error"
        "Error"
    )

    local found_error_handling=false
    local function_codes
    function_codes=$(echo "$workflow_content" | jq -r '.nodes[] | select(.type == "n8n-nodes-base.function") | .parameters.functionCode' 2>/dev/null || echo "")

    for pattern in "${error_handling_patterns[@]}"; do
        if echo "$function_codes" | grep -qE "$pattern"; then
            found_error_handling=true
            break
        fi
    done

    if [[ "$found_error_handling" == "true" ]]; then
        log_success "Error handling mechanisms detected"
        add_result "configuration_security" "pass" "Error handling found" ""
    else
        log_warning "Limited error handling detected"
        add_result "configuration_security" "medium" "Limited error handling" "Consider adding error handling"
    fi
}

# Test 6: Dependency Security
test_dependency_security() {
    log_info "Testing dependency security..."

    # Check for potentially dangerous Node.js modules usage
    local workflow_content
    workflow_content=$(cat "$WORKFLOW_FILE")

    local dangerous_modules=(
        "child_process"
        "fs"
        "path"
        "os"
        "crypto"
        "cluster"
        "vm"
        "worker_threads"
    )

    local found_dangerous_modules=false
    for module in "${dangerous_modules[@]}"; do
        if echo "$workflow_content" | grep -qE "require\s*\(\s*['\"]$module['\"]"; then
            log_warning "Potentially dangerous module usage: $module"
            add_result "dependency_security" "medium" "Dangerous module usage" "$module"
            found_dangerous_modules=true
        fi
    done

    if [[ "$found_dangerous_modules" == "false" ]]; then
        log_success "No dangerous module usage detected"
        add_result "dependency_security" "pass" "No dangerous modules" ""
    fi

    # Check if package.json exists for dependency scanning
    if [[ -f "${PROJECT_ROOT}/package.json" ]]; then
        log_info "Found package.json, checking for known vulnerabilities..."

        if command -v npm &> /dev/null; then
            if npm audit --json > /tmp/npm_audit.json 2>/dev/null; then
                local vulnerabilities
                vulnerabilities=$(jq -r '.metadata.vulnerabilities.total' /tmp/npm_audit.json 2>/dev/null || echo "0")

                if [[ "$vulnerabilities" -gt 0 ]]; then
                    log_vulnerability "npm audit found $vulnerabilities vulnerabilities"
                    add_result "dependency_security" "high" "npm vulnerabilities found" "$vulnerabilities vulnerabilities"
                else
                    log_success "npm audit found no vulnerabilities"
                    add_result "dependency_security" "pass" "No npm vulnerabilities" ""
                fi
                rm -f /tmp/npm_audit.json
            else
                log_warning "Could not run npm audit"
                add_result "dependency_security" "info" "npm audit failed" ""
            fi
        fi
    else
        log_info "No package.json found, skipping dependency vulnerability check"
        add_result "dependency_security" "info" "No package.json found" ""
    fi
}

# Test 7: Access Control
test_access_control() {
    log_info "Testing access control mechanisms..."

    local workflow_content
    workflow_content=$(cat "$WORKFLOW_FILE")

    # Check webhook authentication
    local webhook_nodes
    webhook_nodes=$(echo "$workflow_content" | jq -r '.nodes[] | select(.type == "n8n-nodes-base.webhook") | .parameters' 2>/dev/null || echo "")

    if [[ -n "$webhook_nodes" ]]; then
        # Check for authentication configuration
        if echo "$webhook_nodes" | grep -qE "authentication|auth|bearer|apikey"; then
            log_success "Webhook authentication configuration detected"
            add_result "access_control" "pass" "Webhook authentication found" ""
        else
            log_warning "No webhook authentication detected"
            add_result "access_control" "medium" "No webhook authentication" "Consider adding authentication"
        fi

        # Check for CORS configuration
        if echo "$webhook_nodes" | grep -qE "cors|origin|headers"; then
            log_success "CORS configuration detected"
            add_result "access_control" "pass" "CORS configuration found" ""
        else
            log_warning "No CORS configuration detected"
            add_result "access_control" "medium" "No CORS configuration" "Consider CORS settings"
        fi
    else
        log_info "No webhook nodes found for access control testing"
        add_result "access_control" "info" "No webhooks to test" ""
    fi
}

# Test 8: Data Protection
test_data_protection() {
    log_info "Testing data protection mechanisms..."

    local workflow_content
    workflow_content=$(cat "$WORKFLOW_FILE")

    # Check for sensitive data handling
    local sensitive_data_patterns=(
        "ssn"
        "social.*security"
        "credit.*card"
        "passport"
        "driver.*license"
        "personal.*info"
        "pii"
        "gdpr"
        "ccpa"
    )

    local found_sensitive=false
    for pattern in "${sensitive_data_patterns[@]}"; do
        if echo "$workflow_content" | grep -qiE "$pattern"; then
            log_warning "Potential sensitive data handling: $pattern"
            add_result "data_protection" "medium" "Sensitive data reference" "$pattern"
            found_sensitive=true
        fi
    done

    if [[ "$found_sensitive" == "false" ]]; then
        log_success "No obvious sensitive data handling detected"
        add_result "data_protection" "pass" "No sensitive data patterns" ""
    fi

    # Check for encryption/hashing
    local crypto_patterns=(
        "encrypt"
        "decrypt"
        "hash"
        "bcrypt"
        "scrypt"
        "pbkdf2"
        "crypto\."
    )

    local found_crypto=false
    for pattern in "${crypto_patterns[@]}"; do
        if echo "$workflow_content" | grep -qiE "$pattern"; then
            found_crypto=true
            break
        fi
    done

    if [[ "$found_crypto" == "true" ]]; then
        log_success "Cryptographic functions detected"
        add_result "data_protection" "pass" "Cryptographic functions found" ""
    else
        log_info "No cryptographic functions detected"
        add_result "data_protection" "info" "No crypto functions" ""
    fi
}

# Generate security report
generate_security_report() {
    log_info "Generating security report..."

    # Ensure reports directory exists
    mkdir -p "$REPORT_DIR"

    # Create JSON report
    local json_report="{
        \"timestamp\": \"$(date -Iseconds)\",
        \"workflow_file\": \"$WORKFLOW_FILE\",
        \"summary\": {
            \"vulnerabilities\": $VULNERABILITIES,
            \"warnings\": $WARNINGS,
            \"passed\": $PASSED,
            \"total_tests\": $((VULNERABILITIES + WARNINGS + PASSED))
        },
        \"results\": [
            $(IFS=','; echo "${SECURITY_RESULTS[*]}")
        ]
    }"

    echo "$json_report" | jq '.' > "$SECURITY_REPORT"

    # Create markdown report
    local md_report="${REPORT_DIR}/security-report-${TIMESTAMP}.md"
    cat > "$md_report" << EOF
# Security Assessment Report

**Generated:** $(date)
**Workflow:** $WORKFLOW_FILE

## Summary

- **High Vulnerabilities:** $VULNERABILITIES
- **Warnings:** $WARNINGS
- **Passed Tests:** $PASSED
- **Total Tests:** $((VULNERABILITIES + WARNINGS + PASSED))

## Security Score

EOF

    local total_tests=$((VULNERABILITIES + WARNINGS + PASSED))
    if [[ $total_tests -gt 0 ]]; then
        local score=$(( (PASSED * 100) / total_tests ))
        echo "**Score: ${score}%**" >> "$md_report"
    else
        echo "**Score: N/A**" >> "$md_report"
    fi

    cat >> "$md_report" << EOF

## Recommendations

EOF

    if [[ $VULNERABILITIES -gt 0 ]]; then
        cat >> "$md_report" << EOF
### Critical Issues
- Address all high-severity vulnerabilities immediately
- Review credential management practices
- Implement proper input validation

EOF
    fi

    if [[ $WARNINGS -gt 0 ]]; then
        cat >> "$md_report" << EOF
### Improvements
- Consider implementing suggested security measures
- Review configuration settings for production deployment
- Add comprehensive error handling

EOF
    fi

    cat >> "$md_report" << EOF
## Detailed Results

See JSON report for detailed findings: \`$(basename "$SECURITY_REPORT")\`

---
*Generated by N8N Workflow Security Scanner*
EOF

    echo
    log_success "Security reports generated:"
    echo "  JSON: $SECURITY_REPORT"
    echo "  Markdown: $md_report"
}

# Main execution
main() {
    echo "🔒 N8N Workflow Security Testing Suite"
    echo "======================================"
    echo

    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat << EOF
Usage: $0 [OPTIONS]

Options:
  --verbose, -v    Enable verbose output
  --help, -h       Show this help message

Environment Variables:
  VERBOSE=true     Enable verbose output
  WORKFLOW_FILE    Path to workflow file (default: workflow.json)

Examples:
  $0                    # Run all security tests
  $0 --verbose          # Run with detailed output
  VERBOSE=true $0       # Run with environment variable

EOF
        exit 0
    fi

    if [[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]]; then
        VERBOSE=true
    fi

    if [[ ! -f "$WORKFLOW_FILE" ]]; then
        log_vulnerability "Workflow file not found: $WORKFLOW_FILE"
        exit 1
    fi

    check_dependencies

    # Run security tests
    test_credential_exposure
    test_injection_vulnerabilities
    test_insecure_communication
    test_input_validation
    test_configuration_security
    test_dependency_security
    test_access_control
    test_data_protection

    echo
    echo "======================================"
    echo "Security Assessment Complete"
    echo "======================================"

    generate_security_report

    echo
    if [[ $VULNERABILITIES -eq 0 ]]; then
        if [[ $WARNINGS -eq 0 ]]; then
            log_success "🎉 No security issues detected!"
            exit 0
        else
            log_warning "⚠️  Security assessment completed with $WARNINGS warning(s)"
            log_info "Review warnings for potential improvements"
            exit 0
        fi
    else
        log_vulnerability "❌ Security assessment failed with $VULNERABILITIES vulnerability(ies)"
        log_info "Address vulnerabilities before production deployment"
        exit 1
    fi
}

# Run main function
main "$@"