#!/bin/bash

# Master Test Runner
# Executes all test suites and generates comprehensive reports

set -e

# Test framework setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS_DIR="$SCRIPT_DIR/tests/results"
mkdir -p "$TEST_RESULTS_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test suite tracking
declare -A TEST_SUITES=(
    ["unit"]="Unit Tests"
    ["integration"]="Integration Tests"
    ["security"]="Security Compliance"
    ["validation"]="Manifest Validation"
    ["health"]="Service Health Checks"
)

# Results tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0

# Execution options
VERBOSE=${VERBOSE:-false}
FAIL_FAST=${FAIL_FAST:-false}
PARALLEL=${PARALLEL:-false}
OUTPUT_FORMAT=${OUTPUT_FORMAT:-"console"}

# Utility functions
log_header() {
    echo ""
    echo -e "${PURPLE}================================================================${NC}"
    echo -e "${PURPLE} $1${NC}"
    echo -e "${PURPLE}================================================================${NC}"
}

log_suite() {
    echo -e "${CYAN}🧪 $1${NC}"
    echo "----------------------------------------"
}

log_result() {
    local suite="$1"
    local status="$2"
    local message="$3"

    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✅ $suite: $message${NC}"
    else
        echo -e "${RED}❌ $suite: $message${NC}"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--fail-fast)
                FAIL_FAST=true
                shift
                ;;
            -p|--parallel)
                PARALLEL=true
                shift
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --suite)
                SELECTED_SUITE="$2"
                shift 2
                ;;
            -h|--help)
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
Home Lab Test Suite Runner

Usage: $0 [OPTIONS]

Options:
    -v, --verbose       Enable verbose output
    -f, --fail-fast     Stop on first test failure
    -p, --parallel      Run test suites in parallel
    --format FORMAT     Output format (console, json, junit)
    --suite SUITE       Run specific test suite only
    -h, --help          Show this help message

Available Test Suites:
    unit                DNS updater unit tests
    integration         Integration and API tests
    security            Security compliance tests
    validation          Kubernetes manifest validation
    health              Service health checks

Examples:
    $0                      # Run all test suites
    $0 --suite security     # Run only security tests
    $0 -v -f               # Verbose output, fail fast
    $0 --parallel          # Run suites in parallel
EOF
}

# Run individual test suite
run_test_suite() {
    local suite_name="$1"
    local suite_description="$2"
    local test_command="$3"

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    log_suite "$suite_description"

    local start_time=$(date +%s)
    local exit_code=0

    if [ "$VERBOSE" = "true" ]; then
        eval "$test_command" || exit_code=$?
    else
        eval "$test_command" >/dev/null 2>&1 || exit_code=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Parse test results from JSON if available
    local suite_tests=0
    local suite_passed=0
    local suite_failed=0

    if [ -f "$TEST_RESULTS_DIR/${suite_name}-tests.json" ]; then
        suite_tests=$(grep '"total_tests"' "$TEST_RESULTS_DIR/${suite_name}-tests.json" | grep -o '[0-9]*' | head -1 || echo "0")
        suite_passed=$(grep '"passed"' "$TEST_RESULTS_DIR/${suite_name}-tests.json" | grep -o '[0-9]*' | head -1 || echo "0")
        suite_failed=$(grep '"failed"' "$TEST_RESULTS_DIR/${suite_name}-tests.json" | grep -o '[0-9]*' | head -1 || echo "0")
    elif [ -f "$TEST_RESULTS_DIR/${suite_name}.json" ]; then
        suite_tests=$(grep '"total_tests"' "$TEST_RESULTS_DIR/${suite_name}.json" | grep -o '[0-9]*' | head -1 || echo "0")
        suite_passed=$(grep '"passed"' "$TEST_RESULTS_DIR/${suite_name}.json" | grep -o '[0-9]*' | head -1 || echo "0")
        suite_failed=$(grep '"failed"' "$TEST_RESULTS_DIR/${suite_name}.json" | grep -o '[0-9]*' | head -1 || echo "0")
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + suite_tests))
    TOTAL_PASSED=$((TOTAL_PASSED + suite_passed))
    TOTAL_FAILED=$((TOTAL_FAILED + suite_failed))

    if [ "$exit_code" -eq 0 ]; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        log_result "$suite_description" "PASS" "Completed in ${duration}s ($suite_passed/$suite_tests tests passed)"
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        log_result "$suite_description" "FAIL" "Failed in ${duration}s ($suite_passed/$suite_tests tests passed)"

        if [ "$FAIL_FAST" = "true" ]; then
            echo -e "${RED}💥 Stopping due to --fail-fast flag${NC}"
            exit 1
        fi
    fi

    return $exit_code
}

# Run all test suites
run_all_tests() {
    log_header "🚀 Starting Home Lab Test Suite"

    # Clean previous results
    rm -f "$TEST_RESULTS_DIR"/*.json 2>/dev/null || true

    local suite_exit_codes=()

    # Unit Tests
    if [ -z "$SELECTED_SUITE" ] || [ "$SELECTED_SUITE" = "unit" ]; then
        run_test_suite "dns-updater-unit" "DNS Updater Unit Tests" \
            "chmod +x tests/unit/dns-updater-tests.sh && tests/unit/dns-updater-tests.sh"
        suite_exit_codes+=($?)
    fi

    # Integration Tests
    if [ -z "$SELECTED_SUITE" ] || [ "$SELECTED_SUITE" = "integration" ]; then
        run_test_suite "dns-updater-integration" "DNS Updater Integration Tests" \
            "chmod +x tests/integration/dns-updater-integration-tests.sh && tests/integration/dns-updater-integration-tests.sh"
        suite_exit_codes+=($?)

        run_test_suite "k8s-manifest-validation" "Kubernetes Manifest Validation" \
            "chmod +x tests/integration/k8s-manifest-validation-tests.sh && tests/integration/k8s-manifest-validation-tests.sh"
        suite_exit_codes+=($?)

        run_test_suite "service-health" "Service Health Checks" \
            "chmod +x tests/integration/service-health-tests.sh && tests/integration/service-health-tests.sh"
        suite_exit_codes+=($?)
    fi

    # Security Tests
    if [ -z "$SELECTED_SUITE" ] || [ "$SELECTED_SUITE" = "security" ]; then
        run_test_suite "security-compliance" "Security Compliance Tests" \
            "chmod +x tests/security/security-compliance-tests.sh && tests/security/security-compliance-tests.sh"
        suite_exit_codes+=($?)
    fi
}

# Generate comprehensive report
generate_final_report() {
    local overall_success_rate=0
    if [ "$TOTAL_TESTS" -gt 0 ]; then
        overall_success_rate=$((TOTAL_PASSED * 100 / TOTAL_TESTS))
    fi

    local status="PASS"
    if [ "$FAILED_SUITES" -gt 0 ]; then
        status="FAIL"
    fi

    # Console output
    log_header "📊 Final Test Report"

    echo -e "${BLUE}Test Suite Results:${NC}"
    echo -e "  Total Suites:     ${YELLOW}$TOTAL_SUITES${NC}"
    echo -e "  Passed Suites:    ${GREEN}$PASSED_SUITES${NC}"
    echo -e "  Failed Suites:    ${RED}$FAILED_SUITES${NC}"
    echo ""
    echo -e "${BLUE}Individual Test Results:${NC}"
    echo -e "  Total Tests:      ${YELLOW}$TOTAL_TESTS${NC}"
    echo -e "  Passed Tests:     ${GREEN}$TOTAL_PASSED${NC}"
    echo -e "  Failed Tests:     ${RED}$TOTAL_FAILED${NC}"
    echo -e "  Success Rate:     ${CYAN}$overall_success_rate%${NC}"
    echo ""

    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}🎉 Overall Status: ALL TESTS PASSED${NC}"
    else
        echo -e "${RED}💥 Overall Status: SOME TESTS FAILED${NC}"
    fi

    # Generate JSON report
    cat > "$TEST_RESULTS_DIR/test-summary.json" << EOF
{
  "test_run": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "status": "$status",
    "duration_seconds": $(($(date +%s) - START_TIME))
  },
  "suite_summary": {
    "total_suites": $TOTAL_SUITES,
    "passed_suites": $PASSED_SUITES,
    "failed_suites": $FAILED_SUITES,
    "suite_success_rate": $(echo "scale=2; $PASSED_SUITES * 100 / $TOTAL_SUITES" | bc 2>/dev/null || echo "0")
  },
  "test_summary": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $TOTAL_PASSED,
    "failed_tests": $TOTAL_FAILED,
    "test_success_rate": $overall_success_rate
  },
  "recommendations": [
    "Review failed test cases for improvement opportunities",
    "Integrate test suite into CI/CD pipeline",
    "Monitor test results trends over time",
    "Add additional test coverage for edge cases",
    "Consider implementing automated test reporting"
  ]
}
EOF

    # Show recommendations
    echo ""
    echo -e "${BLUE}💡 Recommendations:${NC}"
    if [ "$overall_success_rate" -ge 90 ]; then
        echo "  • Excellent test coverage! Consider adding edge case tests"
        echo "  • Integrate into CI/CD pipeline for automated testing"
    elif [ "$overall_success_rate" -ge 75 ]; then
        echo "  • Good test foundation. Review failed tests for improvements"
        echo "  • Add more comprehensive integration tests"
    else
        echo "  • Focus on fixing failing tests to improve reliability"
        echo "  • Review test framework setup and dependencies"
    fi

    echo "  • Results saved to: $TEST_RESULTS_DIR/"
}

# Main execution
main() {
    local START_TIME=$(date +%s)

    parse_args "$@"

    # Change to script directory
    cd "$(dirname "$0")"

    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"

    # Run tests
    run_all_tests

    # Generate final report
    generate_final_report

    # Exit with appropriate code
    if [ "$FAILED_SUITES" -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function with all arguments
main "$@"
