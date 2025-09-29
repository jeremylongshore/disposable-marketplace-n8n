#!/bin/bash

# Disposable Marketplace Workflow Validation Script
# Validates the N8N workflow for common issues and best practices
# Optimized for performance with parallel processing and caching

set -euo pipefail

# Initialize global variables
VALIDATE_ALL=true
VALIDATE_SECURITY=false
VALIDATE_STRUCTURE=false
VALIDATE_PERFORMANCE=false
VALIDATE_DOCS=false
VALIDATE_TESTS=false
SHOW_TIMING=false
VERBOSE=false
PARALLEL=true
WORKFLOW_FILE="workflow.json"

# Parse command line arguments
PARSE_ARGS() {

    while [[ $# -gt 0 ]]; do
        case $1 in
            --security-only)
                VALIDATE_ALL=false
                VALIDATE_SECURITY=true
                shift
                ;;
            --structure-only)
                VALIDATE_ALL=false
                VALIDATE_STRUCTURE=true
                shift
                ;;
            --performance-only)
                VALIDATE_ALL=false
                VALIDATE_PERFORMANCE=true
                shift
                ;;
            --docs-only)
                VALIDATE_ALL=false
                VALIDATE_DOCS=true
                shift
                ;;
            --tests-only)
                VALIDATE_ALL=false
                VALIDATE_TESTS=true
                shift
                ;;
            --timing)
                SHOW_TIMING=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --no-parallel)
                PARALLEL=false
                shift
                ;;
            --file)
                WORKFLOW_FILE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Validation Options:
  --security-only     Run only security checks
  --structure-only    Run only structure validation
  --performance-only  Run only performance checks
  --docs-only         Run only documentation checks
  --tests-only        Run only test script validation

Control Options:
  --timing           Show timing for each validation step
  --verbose          Show detailed output
  --no-parallel      Disable parallel processing
  --file FILE        Specify workflow file (default: workflow.json)

General:
  --help, -h         Show this help message

Examples:
  $0                          # Run all validations
  $0 --security-only --timing # Run only security checks with timing
  $0 --structure-only         # Run only structure validation
  $0 --file my-workflow.json  # Validate specific file
EOF
}

echo "🔍 Validating Disposable Marketplace N8N Workflow"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0
PASSED=0

# Performance tracking
START_TIME=$(date +%s.%N)
STEP_TIMES=()

# Cache for expensive operations
declare -A FILE_CACHE
declare -A JQ_CACHE

# Helper functions
error() {
    echo -e "${RED}❌ ERROR: $1${NC}"
    ((ERRORS++))
}

warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
    ((WARNINGS++))
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((PASSED++))
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}🔍 DEBUG: $1${NC}"
    fi
}

timing() {
    if [[ "$SHOW_TIMING" == "true" ]]; then
        echo -e "${PURPLE}⏱️  TIMING: $1${NC}"
    fi
}

start_timer() {
    STEP_START=$(date +%s.%N)
}

end_timer() {
    local step_name="$1"
    local step_end=$(date +%s.%N)
    local duration
    if command -v bc &> /dev/null; then
        duration=$(echo "$step_end - $STEP_START" | bc -l 2>/dev/null || echo "0")
    else
        # Fallback to integer arithmetic (less precise but works)
        local step_end_int=${step_end%.*}
        local step_start_int=${STEP_START%.*}
        duration=$((step_end_int - step_start_int))
    fi
    STEP_TIMES+=("$step_name:$duration")
    timing "$step_name completed in ${duration}s"
}

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local step_name="$3"
    local percentage=$((current * 100 / total))
    local bar_length=30
    local filled_length=$((percentage * bar_length / 100))

    printf "\r${BLUE}[$"
    printf "%*s" $filled_length | tr ' ' '='
    printf "%*s" $((bar_length - filled_length)) | tr ' ' '-'
    printf "] %d%% %s${NC}" $percentage "$step_name"

    if [[ $current -eq $total ]]; then
        echo  # New line when complete
    fi
}

# Cached file reading
read_file_cached() {
    local file="$1"
    local cache_key="file_$file"

    # Check if key exists in cache
    if [[ -z "${FILE_CACHE[$cache_key]:-}" ]]; then
        if [[ -f "$file" ]]; then
            FILE_CACHE[$cache_key]=$(cat "$file")
            debug "Cached contents of $file"
        else
            FILE_CACHE[$cache_key]="FILE_NOT_FOUND"
        fi
    fi

    if [[ "${FILE_CACHE[$cache_key]}" == "FILE_NOT_FOUND" ]]; then
        return 1
    else
        echo "${FILE_CACHE[$cache_key]}"
        return 0
    fi
}

# Cached JQ operations
jq_cached() {
    local query="$1"
    local file="$2"
    local cache_key="jq_${query}_${file}"

    # Check if key exists in cache
    if [[ -z "${JQ_CACHE[$cache_key]:-}" ]]; then
        if JQ_CACHE[$cache_key]=$(jq "$query" "$file" 2>/dev/null); then
            debug "Cached JQ result for: $query"
        else
            JQ_CACHE[$cache_key]="JQ_ERROR"
            return 1
        fi
    fi

    if [[ "${JQ_CACHE[$cache_key]}" == "JQ_ERROR" ]]; then
        return 1
    else
        echo "${JQ_CACHE[$cache_key]}"
        return 0
    fi
}

# Optimized pattern matching
FAST_GREP_PATTERNS=(
    "password|secret|token|api_key|apikey|api-key"
    "YOUR_N8N_URL|your-n8n|localhost|127\.0\.0\.1"
    "http://[^\"]*"
    "while|for.*1000|setTimeout.*0"
)

# Pre-compile regex patterns for better performance
compile_patterns() {
    debug "Compiling regex patterns for faster matching"
    # Note: GREP_OPTIONS is deprecated, patterns are used directly with grep -E
    return 0
}

# Check if required tools are installed
check_dependencies() {
    start_timer
    info "Checking dependencies..."

    local missing_deps=()
    local optional_deps=()

    # Required dependencies
    command -v jq &> /dev/null || missing_deps+=("jq")
    command -v curl &> /dev/null || missing_deps+=("curl")

    # Optional dependencies for enhanced performance
    command -v parallel &> /dev/null || optional_deps+=("parallel")
    command -v bc &> /dev/null || optional_deps+=("bc")
    command -v pv &> /dev/null || optional_deps+=("pv")

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        echo "Install with: sudo apt-get install ${missing_deps[*]}"
        exit 1
    fi

    if [[ ${#optional_deps[@]} -gt 0 && "$VERBOSE" == "true" ]]; then
        warning "Optional dependencies missing: ${optional_deps[*]}"
        echo "Install for enhanced performance: sudo apt-get install ${optional_deps[*]}"
    fi

    success "All required dependencies are installed"
    end_timer "dependency_check"
}

# Validate JSON syntax
validate_json() {
    start_timer
    info "Validating JSON syntax..."

    if [[ ! -f "$WORKFLOW_FILE" ]]; then
        error "Workflow file '$WORKFLOW_FILE' not found"
        return 1
    fi

    # Fast syntax check without parsing entire file
    if ! jq empty "$WORKFLOW_FILE" 2>/dev/null; then
        error "$WORKFLOW_FILE has invalid JSON syntax"

        # Provide helpful error details if verbose
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Detailed JSON error:"
            jq empty "$WORKFLOW_FILE" 2>&1 | head -5
        fi
        return 1
    fi

    # Cache the file size for performance monitoring
    local file_size=$(stat -f%z "$WORKFLOW_FILE" 2>/dev/null || stat -c%s "$WORKFLOW_FILE" 2>/dev/null || echo "unknown")
    debug "Workflow file size: $file_size bytes"

    success "JSON syntax is valid"
    end_timer "json_validation"
}

# Check workflow structure
validate_structure() {
    start_timer
    info "Validating workflow structure..."

    local checks=0
    local total_checks=6

    # Batch JQ operations for better performance
    local structure_data
    if ! structure_data=$(jq_cached '{
        name: .name,
        nodes: .nodes,
        node_count: (.nodes | length),
        webhook_count: ([.nodes[] | select(.type == "n8n-nodes-base.webhook")] | length),
        http_count: ([.nodes[] | select(.type == "n8n-nodes-base.httpRequest")] | length),
        function_count: ([.nodes[] | select(.type == "n8n-nodes-base.function")] | length),
        has_connections: (.connections != null),
        node_types: [.nodes[].type] | unique
    }' "$WORKFLOW_FILE"); then
        error "Failed to parse workflow structure"
        return 1
    fi

    debug "Extracted structure data in single JQ operation"

    # Check required top-level fields
    show_progress $((++checks)) $total_checks "Checking workflow name"
    if ! echo "$structure_data" | jq -e '.name' > /dev/null; then
        error "Missing required field: name"
    else
        local workflow_name=$(echo "$structure_data" | jq -r '.name')
        success "Workflow name: $workflow_name"
    fi

    show_progress $((++checks)) $total_checks "Checking nodes array"
    if ! echo "$structure_data" | jq -e '.nodes' > /dev/null; then
        error "Missing required field: nodes"
        return 1
    fi

    # Count nodes
    show_progress $((++checks)) $total_checks "Counting workflow nodes"
    local node_count=$(echo "$structure_data" | jq -r '.node_count')
    if [[ "$node_count" -lt 5 ]]; then
        warning "Only $node_count nodes found. Expected at least 5 for a complete workflow."
    else
        success "Found $node_count workflow nodes"
    fi

    # Check for required node types
    show_progress $((++checks)) $total_checks "Checking webhook nodes"
    local webhook_count=$(echo "$structure_data" | jq -r '.webhook_count')
    if [[ "$webhook_count" -lt 1 ]]; then
        error "No webhook nodes found. At least one webhook is required."
    else
        success "Found $webhook_count webhook node(s)"
    fi

    show_progress $((++checks)) $total_checks "Checking HTTP request nodes"
    local http_count=$(echo "$structure_data" | jq -r '.http_count')
    if [[ "$http_count" -lt 1 ]]; then
        warning "No HTTP request nodes found. Consider adding external API integrations."
    else
        success "Found $http_count HTTP request node(s)"
    fi

    show_progress $((++checks)) $total_checks "Checking function nodes"
    local function_count=$(echo "$structure_data" | jq -r '.function_count')
    if [[ "$function_count" -lt 1 ]]; then
        warning "No function nodes found. Consider adding data processing logic."
    else
        success "Found $function_count function node(s)"
    fi

    # Additional structure validations
    if [[ "$VERBOSE" == "true" ]]; then
        info "Node type summary:"
        echo "$structure_data" | jq -r '.node_types[]' | sort | uniq -c | while read count type; do
            echo "  $count x $type"
        done
    fi

    end_timer "structure_validation"
}

# Security checks
security_check() {
    start_timer
    info "Running security checks..."

    local checks=0
    local total_checks=4

    # Read file once for all security checks
    local workflow_content
    if ! workflow_content=$(read_file_cached "$WORKFLOW_FILE"); then
        error "Could not read workflow file for security analysis"
        return 1
    fi

    debug "Loaded workflow content for security analysis (${#workflow_content} chars)"

    # Check for hardcoded credentials using optimized pattern
    show_progress $((++checks)) $total_checks "Checking for credentials"
    if echo "$workflow_content" | grep -qiE "${FAST_GREP_PATTERNS[0]}"; then
        error "Potential hardcoded credentials found in $WORKFLOW_FILE"
        echo "  Please use environment variables for sensitive data"

        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Found patterns:"
            echo "$workflow_content" | grep -iE "${FAST_GREP_PATTERNS[0]}" | head -3 | sed 's/^/    /'
        fi
    else
        success "No hardcoded credentials detected"
    fi

    # Check for placeholder URLs
    show_progress $((++checks)) $total_checks "Checking for placeholder URLs"
    if echo "$workflow_content" | grep -qE "${FAST_GREP_PATTERNS[1]}"; then
        warning "Placeholder or localhost URLs found"
        echo "  Remember to configure proper URLs before production deployment"

        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Found URLs:"
            echo "$workflow_content" | grep -oE "${FAST_GREP_PATTERNS[1]}" | head -3 | sed 's/^/    /'
        fi
    else
        success "No placeholder URLs detected"
    fi

    # Check for HTTP URLs (should be HTTPS)
    show_progress $((++checks)) $total_checks "Checking for insecure URLs"
    local http_urls
    if http_urls=$(echo "$workflow_content" | grep -oE "${FAST_GREP_PATTERNS[2]}" | grep -v localhost); then
        warning "HTTP URLs found. Consider using HTTPS for security:"
        echo "$http_urls" | head -5 | sed 's/^/    /'

        if [[ $(echo "$http_urls" | wc -l) -gt 5 ]]; then
            echo "    ... and $(($(echo "$http_urls" | wc -l) - 5)) more"
        fi
    else
        success "No insecure HTTP URLs detected"
    fi

    # Additional security checks
    show_progress $((++checks)) $total_checks "Checking for security best practices"

    # Check for potential code injection points
    if echo "$workflow_content" | grep -qE "eval\(|Function\(|setTimeout.*\$|setInterval.*\$"; then
        warning "Potential code injection vulnerabilities detected"
        echo "  Review dynamic code execution patterns"
    else
        success "No obvious code injection patterns detected"
    fi

    end_timer "security_check"
}

# Validate webhook endpoints
validate_webhooks() {
    start_timer
    info "Validating webhook configurations..."

    # Extract webhook data in single JQ operation
    local webhook_data
    if ! webhook_data=$(jq_cached '[
        .nodes[] |
        select(.type == "n8n-nodes-base.webhook") |
        {
            name: .name,
            path: .parameters.path,
            httpMethod: .parameters.httpMethod,
            responseMode: .parameters.responseMode
        }
    ]' "$WORKFLOW_FILE"); then
        error "Failed to extract webhook configurations"
        return 1
    fi

    local webhook_count=$(echo "$webhook_data" | jq 'length')

    if [[ "$webhook_count" -eq 0 ]]; then
        error "No webhook configurations found"
        return 1
    fi

    info "Found $webhook_count webhook endpoint(s):"

    # Process webhooks in parallel if possible
    if [[ "$PARALLEL" == "true" ]] && command -v parallel &> /dev/null; then
        debug "Processing webhooks in parallel"
        echo "$webhook_data" | jq -r '.[] | @base64' | parallel -j4 validate_single_webhook
    else
        # Sequential processing
        echo "$webhook_data" | jq -c '.[]' | while read -r webhook; do
            validate_single_webhook_direct "$webhook"
        done
    fi

    success "Webhook validation complete"
    end_timer "webhook_validation"
}

# Helper function for single webhook validation
validate_single_webhook() {
    local webhook_b64="$1"
    local webhook=$(echo "$webhook_b64" | base64 -d)
    validate_single_webhook_direct "$webhook"
}

validate_single_webhook_direct() {
    local webhook="$1"
    local name=$(echo "$webhook" | jq -r '.name')
    local path=$(echo "$webhook" | jq -r '.path')
    local method=$(echo "$webhook" | jq -r '.httpMethod // "GET"')

    echo "  - /$path ($method) [$name]"

    # Check for common issues
    if [[ "$path" == *" "* ]]; then
        warning "Webhook path contains spaces: $path"
    fi

    if [[ "$path" != */disposable-marketplace/* ]]; then
        warning "Webhook path doesn't follow expected pattern: $path"
    fi

    # Check for security issues
    if [[ "$method" == "GET" ]] && [[ "$path" == *"offer"* ]]; then
        warning "Webhook /$path uses GET method for potentially sensitive data"
    fi
}

# Validate test script
validate_test_script() {
    start_timer
    info "Validating test script..."

    local test_script="test-requests.sh"

    if [[ ! -f "$test_script" ]]; then
        warning "$test_script not found"
        end_timer "test_script_validation"
        return 0
    fi

    local checks=0
    local total_checks=3

    # Check executable permissions
    show_progress $((++checks)) $total_checks "Checking executable permissions"
    if [[ ! -x "$test_script" ]]; then
        warning "$test_script is not executable. Run: chmod +x $test_script"
    else
        success "Test script is executable"
    fi

    # Check shell syntax
    show_progress $((++checks)) $total_checks "Validating shell syntax"
    if bash -n "$test_script" 2>/dev/null; then
        success "Test script syntax is valid"
    else
        error "Test script has syntax errors"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Syntax errors:"
            bash -n "$test_script" 2>&1 | head -3 | sed 's/^/    /'
        fi
    fi

    # Check for placeholder URLs in test script
    show_progress $((++checks)) $total_checks "Checking for placeholder URLs"
    if read_file_cached "$test_script" | grep -qE "your-n8n|YOUR_N8N_URL|localhost.*webhook"; then
        warning "Test script contains placeholder URLs"
        echo "  Update BASE_URL in $test_script before testing"

        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Found placeholders:"
            read_file_cached "$test_script" | grep -E "your-n8n|YOUR_N8N_URL|localhost.*webhook" | head -3 | sed 's/^/    /'
        fi
    else
        success "Test script URLs look configured"
    fi

    end_timer "test_script_validation"
}

# Validate CSV example
validate_csv_example() {
    start_timer
    info "Validating CSV example..."

    local csv_file="example-resellers.csv"

    if [[ ! -f "$csv_file" ]]; then
        warning "$csv_file not found"
        end_timer "csv_validation"
        return 0
    fi

    local checks=0
    local total_checks=4

    # Read CSV content once
    local csv_content
    if ! csv_content=$(read_file_cached "$csv_file"); then
        error "Could not read $csv_file"
        end_timer "csv_validation"
        return 1
    fi

    # Check CSV headers
    show_progress $((++checks)) $total_checks "Validating CSV headers"
    local headers=$(echo "$csv_content" | head -1)
    local required_headers="id,name,email,region,trust_score"

    if [[ "$headers" != *"$required_headers"* ]]; then
        error "CSV missing required headers. Expected: $required_headers"
        echo "  Found: $headers"
    else
        success "CSV headers are correct"
    fi

    # Count CSV rows
    show_progress $((++checks)) $total_checks "Counting CSV rows"
    local csv_rows=$(($(echo "$csv_content" | wc -l) - 1))
    if [[ "$csv_rows" -lt 3 ]]; then
        warning "Only $csv_rows example resellers. Consider adding more for testing."
    elif [[ "$csv_rows" -gt 100 ]]; then
        warning "Large CSV file ($csv_rows rows). May slow down testing."
    else
        success "Found $csv_rows example resellers"
    fi

    # Validate email format in CSV
    show_progress $((++checks)) $total_checks "Validating email formats"
    local invalid_emails=0
    while IFS=',' read -r id name email region trust_score rest; do
        if [[ "$email" != "email" ]] && [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            ((invalid_emails++))
            if [[ "$VERBOSE" == "true" ]] && [[ "$invalid_emails" -le 3 ]]; then
                warning "Invalid email format: $email"
            fi
        fi
    done <<< "$csv_content"

    if [[ "$invalid_emails" -eq 0 ]]; then
        success "All email formats are valid"
    else
        warning "$invalid_emails invalid email format(s) found"
    fi

    # Check trust score range
    show_progress $((++checks)) $total_checks "Validating trust scores"
    local invalid_scores=0
    while IFS=',' read -r id name email region trust_score rest; do
        if [[ "$trust_score" != "trust_score" ]] && [[ ! "$trust_score" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            ((invalid_scores++))
        elif [[ "$trust_score" != "trust_score" ]] && [[ "${trust_score%.*}" -gt 10 ]]; then
            ((invalid_scores++))
        fi
    done <<< "$csv_content"

    if [[ "$invalid_scores" -eq 0 ]]; then
        success "All trust scores are in valid range (0-10)"
    else
        warning "$invalid_scores invalid trust score(s) found"
    fi

    end_timer "csv_validation"
}

# Check documentation
validate_documentation() {
    start_timer
    info "Validating documentation..."

    local checks=0
    local total_checks=6

    # Check README.md
    show_progress $((++checks)) $total_checks "Checking README.md"
    if [[ ! -f "README.md" ]]; then
        error "README.md is missing"
    else
        local readme_content
        if readme_content=$(read_file_cached "README.md"); then
            # Check for required sections
            local missing_sections=()

            if ! echo "$readme_content" | grep -qE "## (Quick [Ss]tart|Getting [Ss]tarted|Installation)"; then
                missing_sections+=("Quick Start/Getting Started")
            fi

            if ! echo "$readme_content" | grep -q "workflow\.json\|$WORKFLOW_FILE"; then
                missing_sections+=("Workflow file reference")
            fi

            if ! echo "$readme_content" | grep -qE "## (API|Endpoints|Usage)"; then
                missing_sections+=("API documentation")
            fi

            if [[ ${#missing_sections[@]} -eq 0 ]]; then
                success "README.md exists and looks complete"
            else
                warning "README.md missing sections: ${missing_sections[*]}"
            fi

            # Check README length
            local readme_lines=$(echo "$readme_content" | wc -l)
            if [[ "$readme_lines" -lt 20 ]]; then
                warning "README.md is quite short ($readme_lines lines). Consider adding more detail."
            fi
        else
            error "Could not read README.md"
        fi
    fi

    # Check for other important files
    show_progress $((++checks)) $total_checks "Checking LICENSE"
    if [[ -f "LICENSE" ]]; then
        success "LICENSE file exists"
    else
        warning "LICENSE file missing"
    fi

    show_progress $((++checks)) $total_checks "Checking SECURITY.md"
    if [[ -f "SECURITY.md" ]]; then
        success "SECURITY.md exists"
    else
        warning "SECURITY.md missing (recommended for production workflows)"
    fi

    show_progress $((++checks)) $total_checks "Checking CONTRIBUTING.md"
    if [[ -f "CONTRIBUTING.md" ]]; then
        success "CONTRIBUTING.md exists"
    else
        warning "CONTRIBUTING.md missing (recommended for open source projects)"
    fi

    # Check for CLAUDE.md (project-specific guidance)
    show_progress $((++checks)) $total_checks "Checking CLAUDE.md"
    if [[ -f "CLAUDE.md" ]]; then
        success "CLAUDE.md exists (good for AI-assisted development)"

        if [[ "$VERBOSE" == "true" ]]; then
            local claude_content
            if claude_content=$(read_file_cached "CLAUDE.md"); then
                local claude_lines=$(echo "$claude_content" | wc -l)
                info "CLAUDE.md contains $claude_lines lines of guidance"
            fi
        fi
    else
        info "CLAUDE.md missing (optional but helpful for AI development)"
    fi

    # Check for change log
    show_progress $((++checks)) $total_checks "Checking for changelog"
    if [[ -f "CHANGELOG.md" ]] || [[ -f "CHANGES.md" ]] || [[ -f "HISTORY.md" ]]; then
        success "Changelog file exists"
    else
        warning "No changelog file found (CHANGELOG.md recommended)"
    fi

    end_timer "documentation_validation"
}

# Performance checks
performance_check() {
    start_timer
    info "Running performance checks..."

    local checks=0
    local total_checks=5

    # Check workflow file size
    show_progress $((++checks)) $total_checks "Checking file size"
    local workflow_size=$(stat -f%z "$WORKFLOW_FILE" 2>/dev/null || stat -c%s "$WORKFLOW_FILE" 2>/dev/null || echo "0")

    if [[ "$workflow_size" -gt 100000 ]]; then
        error "Workflow file is very large (${workflow_size} bytes). Consider splitting into multiple workflows."
    elif [[ "$workflow_size" -gt 50000 ]]; then
        warning "Workflow file is large (${workflow_size} bytes). Consider optimization."
    else
        success "Workflow file size is reasonable (${workflow_size} bytes)"
    fi

    # Check node complexity
    show_progress $((++checks)) $total_checks "Analyzing node complexity"
    local node_count=$(jq_cached '.nodes | length' "$WORKFLOW_FILE")

    if [[ "$node_count" -gt 50 ]]; then
        warning "High node count ($node_count). Consider workflow decomposition."
    elif [[ "$node_count" -gt 100 ]]; then
        error "Very high node count ($node_count). Workflow may be too complex."
    else
        success "Node count is reasonable ($node_count)"
    fi

    # Check for potential performance issues in function nodes
    show_progress $((++checks)) $total_checks "Checking function node performance"
    local function_code
    if function_code=$(jq_cached -r '.nodes[] | select(.type == "n8n-nodes-base.function") | .parameters.functionCode' "$WORKFLOW_FILE"); then

        if echo "$function_code" | grep -qE "${FAST_GREP_PATTERNS[3]}"; then
            warning "Potential performance issues detected in function nodes"
            echo "  Check for infinite loops or blocking operations"

            if [[ "$VERBOSE" == "true" ]]; then
                echo "  Problematic patterns found:"
                echo "$function_code" | grep -E "${FAST_GREP_PATTERNS[3]}" | head -3 | sed 's/^/    /'
            fi
        else
            success "No obvious performance issues detected in functions"
        fi
    else
        info "No function nodes found to analyze"
    fi

    # Check connection complexity
    show_progress $((++checks)) $total_checks "Analyzing connection complexity"
    local connection_count
    if connection_count=$(jq_cached '[.connections | to_entries[] | .value | to_entries[] | .value[]] | length' "$WORKFLOW_FILE" 2>/dev/null); then
        if [[ "$connection_count" -gt 100 ]]; then
            warning "High connection count ($connection_count). May impact performance."
        else
            success "Connection complexity is reasonable ($connection_count connections)"
        fi
    fi

    # Memory usage estimation
    show_progress $((++checks)) $total_checks "Estimating memory requirements"
    local estimated_memory=$((workflow_size * 10))  # Rough estimation

    if [[ "$estimated_memory" -gt 10485760 ]]; then  # 10MB
        warning "Estimated memory usage: $((estimated_memory / 1048576))MB. Monitor in production."
    else
        success "Estimated memory usage: $((estimated_memory / 1024))KB"
    fi

    end_timer "performance_check"
}

# Run validations based on flags
run_validations() {
    local validation_functions=()

    if [[ "$VALIDATE_ALL" == "true" ]]; then
        validation_functions=("check_dependencies" "validate_json" "validate_structure" "security_check" "validate_webhooks" "validate_test_script" "validate_csv_example" "validate_documentation" "performance_check")
    else
        validation_functions=("check_dependencies" "validate_json")  # Always run these

        [[ "$VALIDATE_SECURITY" == "true" ]] && validation_functions+=("security_check")
        [[ "$VALIDATE_STRUCTURE" == "true" ]] && validation_functions+=("validate_structure")
        [[ "$VALIDATE_PERFORMANCE" == "true" ]] && validation_functions+=("performance_check")
        [[ "$VALIDATE_DOCS" == "true" ]] && validation_functions+=("validate_documentation")
        [[ "$VALIDATE_TESTS" == "true" ]] && validation_functions+=("validate_test_script" "validate_csv_example")

        # If webhooks are in the workflow, always validate them
        if jq_cached -e '.nodes[] | select(.type == "n8n-nodes-base.webhook")' "$WORKFLOW_FILE" >/dev/null 2>&1; then
            validation_functions+=("validate_webhooks")
        fi
    fi

    info "Running ${#validation_functions[@]} validation steps"
    echo

    # Run validations in parallel if possible and requested
    if [[ "$PARALLEL" == "true" ]] && command -v parallel &> /dev/null && [[ ${#validation_functions[@]} -gt 3 ]]; then
        info "Running validations in parallel mode"

        # Create temporary files for parallel execution
        local temp_dir=$(mktemp -d)
        local results_file="$temp_dir/results"

        # Export functions and variables for parallel
        export -f error warning success info debug timing start_timer end_timer
        export -f read_file_cached jq_cached show_progress
        export RED GREEN YELLOW BLUE PURPLE CYAN NC
        export WORKFLOW_FILE VERBOSE SHOW_TIMING
        export -A FILE_CACHE JQ_CACHE

        # Run validations in parallel (limit to 4 concurrent)
        printf '%s\n' "${validation_functions[@]}" | parallel -j4 --results "$temp_dir" '{}'

        # Collect results
        find "$temp_dir" -name "stdout" -exec cat {} \;

        rm -rf "$temp_dir"
    else
        # Sequential execution
        for func in "${validation_functions[@]}"; do
            "$func"
            echo
        done
    fi
}

# Generate final summary with timing information
generate_summary() {
    local end_time=$(date +%s.%N)
    local total_duration
    if command -v bc &> /dev/null; then
        total_duration=$(echo "$end_time - $START_TIME" | bc -l 2>/dev/null || echo "unknown")
    else
        local end_int=${end_time%.*}
        local start_int=${START_TIME%.*}
        total_duration=$((end_int - start_int))
    fi

    echo "=================================================="
    echo "📊 VALIDATION SUMMARY"
    echo "=================================================="
    echo -e "${GREEN}✅ Passed: $PASSED${NC}"
    echo -e "${YELLOW}⚠️  Warnings: $WARNINGS${NC}"
    echo -e "${RED}❌ Errors: $ERRORS${NC}"

    if [[ "$SHOW_TIMING" == "true" ]]; then
        echo
        echo "⏱️  TIMING BREAKDOWN:"
        echo "--------------------------------------------------"
        for step_time in "${STEP_TIMES[@]}"; do
            local step_name="${step_time%:*}"
            local duration="${step_time#*:}"
            printf "  %-25s %8.3fs\n" "$step_name" "$duration"
        done
        echo "--------------------------------------------------"
        printf "  %-25s %8.3fs\n" "TOTAL" "$total_duration"
    fi

    echo

    if [[ "$ERRORS" -eq 0 ]]; then
        echo -e "${GREEN}🎉 Workflow validation completed successfully!${NC}"
        if [[ "$WARNINGS" -gt 0 ]]; then
            echo -e "${YELLOW}⚠️  Consider addressing the warnings above for production deployment.${NC}"
        fi

        if [[ "$SHOW_TIMING" == "true" ]]; then
            echo -e "${BLUE}ℹ️  Total validation time: ${total_duration}s${NC}"
        fi

        return 0
    else
        echo -e "${RED}💥 Workflow validation failed with $ERRORS error(s).${NC}"
        echo "Please fix the errors above before deploying."
        return 1
    fi
}

# Main validation
main() {
    # Initialize
    compile_patterns || { error "Failed to initialize patterns"; exit 1; }

    # Parse command line arguments
    PARSE_ARGS "$@" || { error "Failed to parse arguments"; exit 1; }

    # Show configuration if verbose
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        info "Configuration:"
        echo "  Workflow file: ${WORKFLOW_FILE:-workflow.json}"
        echo "  Parallel processing: ${PARALLEL:-true}"
        echo "  Show timing: ${SHOW_TIMING:-false}"
        echo "  Validate all: ${VALIDATE_ALL:-true}"
        echo
    fi

    # Run the validations
    run_validations || { error "Validation execution failed"; exit 1; }

    # Generate and show summary
    if generate_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"