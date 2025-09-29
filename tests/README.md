# N8N Workflow Test Suite

Comprehensive testing framework for the Disposable Marketplace N8N workflow including unit tests, integration tests, performance benchmarks, security scans, and end-to-end testing.

## Overview

This test suite ensures the N8N workflow is robust, secure, and performant through multiple layers of testing:

- **Unit Tests**: Validation script functions and CLI argument parsing (BATS)
- **Integration Tests**: Workflow structure and node configuration (Jest)
- **Performance Tests**: Benchmarking and memory usage analysis (Node.js)
- **Security Tests**: Vulnerability scanning and credential detection (Bash)
- **End-to-End Tests**: Complete workflow execution scenarios (Jest + Axios)
- **CI/CD Tests**: GitHub Actions automation and cross-platform testing

## Quick Start

### 1. Setup Test Environment

```bash
# Install all dependencies and configure test environment
./tests/helpers/setup.sh

# Verify installation
./tests/helpers/setup.sh --verify
```

### 2. Run All Tests

```bash
cd tests
npm test
```

### 3. Run Specific Test Categories

```bash
# Unit tests (BATS)
npm run test:unit

# Integration tests (Jest)
npm run test:integration

# Performance benchmarks
npm run test:performance

# Security tests
npm run test:security

# End-to-end tests (requires N8N instance)
npm run test:e2e
```

## Test Structure

```
tests/
├── unit/                   # BATS unit tests
│   └── validation-script.bats
├── integration/            # Jest integration tests
│   └── workflow.test.js
├── performance/            # Performance benchmarking
│   └── benchmark.js
├── security/               # Security testing
│   └── security-tests.sh
├── e2e/                    # End-to-end tests
│   └── workflow-e2e.test.js
├── fixtures/               # Test data and sample files
├── mocks/                  # Mock servers and data
├── helpers/                # Test utilities and setup
│   ├── setup.sh
│   ├── test_helper.bash
│   └── jest.setup.js
├── reports/                # Test reports and coverage
└── package.json            # Test dependencies
```

## Detailed Test Documentation

### Unit Tests (BATS)

Tests the validation script functions, CLI parsing, and bash utilities:

```bash
# Run unit tests
bats tests/unit/*.bats

# Run with verbose output
TEST_DEBUG=true bats tests/unit/*.bats
```

**Test Coverage:**
- CLI argument parsing (`--help`, `--security-only`, etc.)
- JSON validation functions
- Error handling and exit codes
- File operations and caching
- Parallel vs sequential execution
- Mock data generation

### Integration Tests (Jest)

Tests workflow structure, node configuration, and data processing:

```bash
# Run integration tests
npm run test:integration

# Run with coverage
npm run test:coverage

# Watch mode for development
npm run test:watch
```

**Test Coverage:**
- Workflow JSON structure validation
- Node type and configuration checks
- Function code syntax validation
- Security pattern detection
- Data flow validation
- Error handling mechanisms

### Performance Tests

Benchmarks execution time, memory usage, and throughput:

```bash
# Run performance tests
npm run test:performance

# View detailed performance report
cat tests/reports/performance-report.md
```

**Metrics Tracked:**
- Validation script execution time
- JSON parsing performance
- Memory usage patterns
- Large file processing
- Concurrent operation handling
- Throughput measurements

### Security Tests

Comprehensive security scanning for vulnerabilities:

```bash
# Run security tests
./tests/security/security-tests.sh

# Run with verbose output
./tests/security/security-tests.sh --verbose

# View security report
cat tests/reports/security-report-*.md
```

**Security Checks:**
- Credential and secret detection
- Code injection vulnerabilities
- Insecure communication patterns
- Input validation analysis
- Configuration security
- Dependency vulnerabilities
- Access control mechanisms
- Data protection compliance

### End-to-End Tests

Tests complete workflow execution with real scenarios:

```bash
# Start N8N instance (required)
npx n8n start

# Run E2E tests
N8N_URL=http://localhost:5678 npm run test:e2e
```

**E2E Scenarios:**
- Complete marketplace workflow
- Multi-reseller offer processing
- Offer ranking and scoring
- Error handling and edge cases
- Performance under load
- Data validation and security
- Timeout and concurrent scenarios

## Configuration

### Environment Variables

```bash
# Test environment configuration
TEST_DEBUG=true          # Enable verbose output
TEST_TIMEOUT=30000       # Default test timeout (ms)
N8N_URL=http://localhost:5678  # N8N instance URL
MOCK_SERVER_PORT=3001    # Mock server port
CI=true                  # CI environment flag
```

### Test Configuration Files

- `.env.test` - Test environment variables
- `.bats_env` - BATS-specific configuration
- `jest.config.js` - Jest configuration (in package.json)

## CI/CD Integration

The test suite integrates with GitHub Actions for automated testing:

### Workflow Triggers

- **Push** to main/master/develop branches
- **Pull requests** to main/master
- **Daily schedule** at 2 AM UTC
- **Manual trigger** with `[e2e]` in commit message

### Test Jobs

1. **Unit Tests** - BATS validation script tests
2. **Integration Tests** - Jest workflow structure tests
3. **Security Tests** - Vulnerability scanning
4. **Performance Tests** - Benchmarking and profiling
5. **Validation** - JSON validation and linting
6. **Cross-Platform** - Ubuntu/macOS with Node.js 16/18/20
7. **E2E Tests** - Complete workflow testing (scheduled)
8. **Test Summary** - Aggregate results and reporting

### Artifacts

- Test reports (JSON/Markdown)
- Coverage reports
- Performance benchmarks
- Security scan results
- Test summaries and logs

## Test Data and Fixtures

### Sample CSV Files

```
tests/fixtures/
├── valid-resellers.csv      # Complete valid CSV data
├── invalid-resellers.csv    # Missing required columns
└── malformed-resellers.csv  # Invalid data formats
```

### Mock Workflows

```
tests/fixtures/
├── minimal-workflow.json    # Basic valid workflow
├── invalid-workflow.json   # Invalid JSON syntax
└── large-workflow-*.json   # Generated large workflows
```

### Test Utilities

```javascript
// Available in all Jest tests
const { testUtils, testConstants } = require('./helpers/jest.setup');

// Generate test data
const reseller = testUtils.generateTestData.csvReseller('TEST_001');
const product = testUtils.generateTestData.product({ brand: 'Omega' });

// Wait for conditions
await testUtils.waitFor(() => condition, 10000);

// Retry flaky operations
const result = await testUtils.retry(async () => {
  return await apiCall();
}, 3, 1000);
```

## Development Workflow

### Adding New Tests

1. **Unit Tests**: Add to `tests/unit/*.bats`
2. **Integration Tests**: Add to `tests/integration/*.test.js`
3. **Performance Tests**: Extend `tests/performance/benchmark.js`
4. **Security Tests**: Extend `tests/security/security-tests.sh`

### Running Tests During Development

```bash
# Watch mode for quick feedback
npm run test:watch

# Run specific test file
npm test -- workflow.test.js

# Debug mode
TEST_DEBUG=true npm test

# Skip slow tests
npm test -- --testNamePattern="^(?!.*slow)"
```

### Test Best Practices

1. **Isolation**: Each test should be independent
2. **Deterministic**: Tests should produce consistent results
3. **Fast**: Unit tests should complete in seconds
4. **Clear**: Test names should describe expected behavior
5. **Comprehensive**: Cover happy path, edge cases, and errors

## Troubleshooting

### Common Issues

**BATS Tests Failing**
```bash
# Check BATS installation
bats --version

# Install BATS if missing
./tests/helpers/setup.sh
```

**Node.js Dependency Issues**
```bash
# Clean install
cd tests && rm -rf node_modules package-lock.json
npm install
```

**Permission Errors**
```bash
# Fix script permissions
chmod +x tests/security/security-tests.sh
chmod +x tests/helpers/setup.sh
```

**N8N Connection Issues**
```bash
# Check N8N is running
curl -f http://localhost:5678/healthz

# Start N8N if needed
npx n8n start
```

### Debug Mode

Enable verbose output for troubleshooting:

```bash
# BATS tests
TEST_DEBUG=true bats tests/unit/*.bats

# Jest tests
TEST_DEBUG=true npm test

# Security tests
./tests/security/security-tests.sh --verbose
```

## Performance Benchmarks

Current performance targets:

- **Validation Script**: < 5 seconds for complete validation
- **JSON Parsing**: < 100ms for 15KB workflow file
- **Security Scan**: < 10 seconds for full scan
- **Integration Tests**: < 30 seconds total
- **Memory Usage**: < 50MB peak during testing

## Security Standards

The security test suite checks for:

- **OWASP Top 10** vulnerabilities
- **Credential exposure** patterns
- **Injection vulnerabilities** (SQL, code, command)
- **Insecure communication** (HTTP, weak TLS)
- **Input validation** gaps
- **Configuration security** issues
- **Dependency vulnerabilities**
- **Access control** mechanisms

## Contributing

When contributing to the test suite:

1. Run the full test suite before submitting
2. Add tests for new functionality
3. Update documentation for new test categories
4. Follow existing test patterns and naming conventions
5. Ensure tests pass in CI environment

## Reports and Monitoring

Test reports are generated in `tests/reports/`:

- `performance-report.json` - Performance benchmarks
- `security-report-*.json` - Security scan results
- Coverage reports in `tests/reports/coverage/`
- CI artifacts uploaded to GitHub Actions

## Support

For test-related issues:

1. Check this README for common solutions
2. Review GitHub Actions logs for CI failures
3. Run tests locally with debug mode enabled
4. Verify test environment setup with `./tests/helpers/setup.sh --verify`

---

**Last Updated**: September 2025
**Test Suite Version**: 1.0.0
**Compatible with**: N8N 1.0+, Node.js 16+