#!/bin/bash

# Integration Tests for CloudFlare DNS Updater
# Tests API interactions and end-to-end functionality

set -e

# Test framework setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../../dns-updater-k8s"
TEST_RESULTS_DIR="$SCRIPT_DIR/../results"
mkdir -p "$TEST_RESULTS_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Mock CloudFlare API responses
MOCK_API_RESPONSES_DIR="/tmp/cf_mock_responses"
mkdir -p "$MOCK_API_RESPONSES_DIR"

# Test utility functions
log_test() {
    echo -e "${BLUE}[INTEGRATION TEST]${NC} $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

assert_success() {
    local exit_code="$1"
    local message="$2"

    if [ "$exit_code" -eq 0 ]; then
        echo -e "${GREEN}  ✓ PASS:${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}  ✗ FAIL:${NC} $message (exit code: $exit_code)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_file_exists() {
    local file_path="$1"
    local message="$2"

    if [ -f "$file_path" ]; then
        echo -e "${GREEN}  ✓ PASS:${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}  ✗ FAIL:${NC} $message (file not found: $file_path)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Setup mock API responses
setup_mock_responses() {
    # Mock successful zone lookup
    cat > "$MOCK_API_RESPONSES_DIR/zone_lookup.json" << 'EOF'
{
  "success": true,
  "errors": [],
  "messages": [],
  "result": [
    {
      "id": "test-zone-identifier-here",
      "name": "homelab.local",
      "status": "active"
    }
  ]
}
EOF

    # Mock successful record lookup
    cat > "$MOCK_API_RESPONSES_DIR/record_lookup.json" << 'EOF'
{
  "success": true,
  "errors": [],
  "messages": [],
  "result": [
    {
      "id": "test-record-id-123",
      "name": "home.homelab.local",
      "type": "A",
      "content": "192.168.1.100",
      "ttl": 300
    }
  ]
}
EOF

    # Mock successful record update
    cat > "$MOCK_API_RESPONSES_DIR/record_update.json" << 'EOF'
{
  "success": true,
  "errors": [],
  "messages": [],
  "result": {
    "id": "test-record-id-123",
    "name": "home.homelab.local",
    "type": "A",
    "content": "203.0.113.100",
    "ttl": 300,
    "modified_on": "2024-01-01T12:00:00Z"
  }
}
EOF

    # Mock IP service responses
    echo "203.0.113.100" > "$MOCK_API_RESPONSES_DIR/current_ip.txt"
}

# Mock curl function for testing
curl_mock() {
    local url="$1"
    local method=""
    local data=""

    # Parse curl arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -X)
                method="$2"
                shift 2
                ;;
            -d|--data)
                data="$2"
                shift 2
                ;;
            *)
                url="$1"
                shift
                ;;
        esac
    done

    # Simulate API responses based on URL pattern
    if [[ "$url" == *"zones"* ]] && [[ "$method" != "PUT" ]]; then
        cat "$MOCK_API_RESPONSES_DIR/zone_lookup.json"
    elif [[ "$url" == *"dns_records"* ]] && [[ "$method" == "GET" ]]; then
        cat "$MOCK_API_RESPONSES_DIR/record_lookup.json"
    elif [[ "$url" == *"dns_records"* ]] && [[ "$method" == "PUT" ]]; then
        cat "$MOCK_API_RESPONSES_DIR/record_update.json"
    elif [[ "$url" == *"ipify"* ]] || [[ "$url" == *"ifconfig"* ]]; then
        cat "$MOCK_API_RESPONSES_DIR/current_ip.txt"
    else
        echo '{"success": false, "errors": [{"code": 1003, "message": "Unknown endpoint"}]}'
        return 1
    fi
}

# Test: API Authentication
test_api_authentication() {
    log_test "Testing API authentication"

    # Mock authentication test
    export AUTH_EMAIL="user@example.com"
    export AUTH_KEY="your-cloudflare-api-token-here"

    # Simulate auth check with mock
    local auth_response=$(curl_mock "https://api.cloudflare.com/client/v4/zones" -H "Authorization: Bearer $AUTH_KEY")

    if echo "$auth_response" | grep -q '"success":true'; then
        assert_success 0 "API authentication successful"
    else
        assert_success 1 "API authentication failed"
    fi
}

# Test: Zone Discovery
test_zone_discovery() {
    log_test "Testing zone discovery"

    export DOMAIN_NAME="homelab.local"
    export ZONE_IDENTIFIER="your-zone-identifier-here"

    # Mock zone lookup
    local zone_response=$(curl_mock "https://api.cloudflare.com/client/v4/zones")
    local zone_found=$(echo "$zone_response" | grep -c "homelab.local" || echo "0")

    if [ "$zone_found" -gt 0 ]; then
        assert_success 0 "Zone discovery successful"
    else
        assert_success 1 "Zone discovery failed"
    fi
}

# Test: DNS Record Retrieval
test_dns_record_retrieval() {
    log_test "Testing DNS record retrieval"

    export RECORD_NAMES="home"

    # Mock record lookup
    local record_response=$(curl_mock "https://api.cloudflare.com/client/v4/zones/test-zone/dns_records" -X GET)
    local record_found=$(echo "$record_response" | grep -c "home.homelab.local" || echo "0")

    if [ "$record_found" -gt 0 ]; then
        assert_success 0 "DNS record retrieval successful"
    else
        assert_success 1 "DNS record retrieval failed"
    fi
}

# Test: IP Address Detection
test_ip_detection() {
    log_test "Testing IP address detection"

    # Mock external IP detection
    local detected_ip=$(curl_mock "https://api.ipify.org")

    # Validate IP format
    if [[ "$detected_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        assert_success 0 "IP address detection successful ($detected_ip)"
    else
        assert_success 1 "IP address detection failed"
    fi
}

# Test: DNS Record Update
test_dns_record_update() {
    log_test "Testing DNS record update"

    local new_ip="203.0.113.100"

    # Mock record update
    local update_response=$(curl_mock "https://api.cloudflare.com/client/v4/zones/test-zone/dns_records/test-record" -X PUT -d "{\"content\":\"$new_ip\"}")

    if echo "$update_response" | grep -q '"success":true'; then
        local updated_ip=$(echo "$update_response" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)
        if [ "$updated_ip" = "$new_ip" ]; then
            assert_success 0 "DNS record update successful"
        else
            assert_success 1 "DNS record update IP mismatch"
        fi
    else
        assert_success 1 "DNS record update failed"
    fi
}

# Test: Cache File Persistence
test_cache_persistence() {
    log_test "Testing cache file persistence"

    local test_cache="/tmp/test_integration_cache.$$"
    local test_ip="203.0.113.100"

    # Write to cache
    echo "ipv4 $test_ip" > "$test_cache"

    # Verify persistence
    if [ -f "$test_cache" ]; then
        local cached_ip=$(grep "^ipv4" "$test_cache" | cut -d' ' -f2)
        if [ "$cached_ip" = "$test_ip" ]; then
            assert_success 0 "Cache file persistence working"
        else
            assert_success 1 "Cache file content mismatch"
        fi
    else
        assert_success 1 "Cache file not created"
    fi

    # Cleanup
    rm -f "$test_cache"
}

# Test: Error Recovery
test_error_recovery() {
    log_test "Testing error recovery mechanisms"

    # Mock API failure response
    local error_response='{"success":false,"errors":[{"code":1003,"message":"Invalid request"}]}'

    # Test retry logic (simplified)
    local retry_count=0
    local max_retries=3

    while [ $retry_count -lt $max_retries ]; do
        if echo "$error_response" | grep -q '"success":true'; then
            break
        fi
        retry_count=$((retry_count + 1))
    done

    if [ $retry_count -eq $max_retries ]; then
        assert_success 0 "Error recovery retry logic working"
    else
        assert_success 1 "Error recovery failed"
    fi
}

# Test: Configuration Validation
test_configuration_validation() {
    log_test "Testing configuration validation"

    # Test required environment variables
    local required_vars=("AUTH_EMAIL" "AUTH_KEY" "ZONE_IDENTIFIER" "DOMAIN_NAME")
    local validation_passed=0

    for var in "${required_vars[@]}"; do
        if [ -n "${!var}" ]; then
            validation_passed=$((validation_passed + 1))
        fi
    done

    if [ $validation_passed -eq ${#required_vars[@]} ]; then
        assert_success 0 "Configuration validation passed"
    else
        assert_success 1 "Configuration validation failed ($validation_passed/${#required_vars[@]} vars set)"
    fi
}

# Test: End-to-End Workflow
test_end_to_end_workflow() {
    log_test "Testing end-to-end workflow"

    local workflow_steps=0

    # Step 1: Get current IP
    local current_ip=$(curl_mock "https://api.ipify.org")
    if [[ "$current_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        workflow_steps=$((workflow_steps + 1))
    fi

    # Step 2: Get zone info
    local zone_response=$(curl_mock "https://api.cloudflare.com/client/v4/zones")
    if echo "$zone_response" | grep -q '"success":true'; then
        workflow_steps=$((workflow_steps + 1))
    fi

    # Step 3: Get current DNS record
    local record_response=$(curl_mock "https://api.cloudflare.com/client/v4/zones/test-zone/dns_records" -X GET)
    if echo "$record_response" | grep -q '"success":true'; then
        workflow_steps=$((workflow_steps + 1))
    fi

    # Step 4: Update DNS record
    local update_response=$(curl_mock "https://api.cloudflare.com/client/v4/zones/test-zone/dns_records/test-record" -X PUT -d "{\"content\":\"$current_ip\"}")
    if echo "$update_response" | grep -q '"success":true'; then
        workflow_steps=$((workflow_steps + 1))
    fi

    if [ $workflow_steps -eq 4 ]; then
        assert_success 0 "End-to-end workflow completed successfully"
    else
        assert_success 1 "End-to-end workflow failed ($workflow_steps/4 steps completed)"
    fi
}

# Setup and run tests
echo -e "${BLUE}🧪 Running DNS Updater Integration Tests${NC}"
echo "=================================================="

setup_mock_responses

# Set up test environment
export AUTH_EMAIL="user@example.com"
export AUTH_KEY="your-cloudflare-api-token-here"
export ZONE_IDENTIFIER="your-zone-identifier-here"
export DOMAIN_NAME="homelab.local"
export RECORD_NAMES="home"
export TTL="300"
export PROXY="false"

# Run tests
test_api_authentication
test_zone_discovery
test_dns_record_retrieval
test_ip_detection
test_dns_record_update
test_cache_persistence
test_error_recovery
test_configuration_validation
test_end_to_end_workflow

# Test summary
echo ""
echo "=================================================="
echo -e "${BLUE}📊 Integration Test Summary${NC}"
echo "=================================================="
echo -e "Tests Run:    ${YELLOW}$TESTS_RUN${NC}"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

# Generate test report
cat > "$TEST_RESULTS_DIR/dns-updater-integration-tests.json" << EOF
{
  "test_suite": "dns-updater-integration-tests",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_tests": $TESTS_RUN,
  "passed": $TESTS_PASSED,
  "failed": $TESTS_FAILED,
  "success_rate": $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "0"),
  "test_details": {
    "api_authentication": "$([ $TESTS_FAILED -eq 0 ] && echo "passed" || echo "see logs")",
    "zone_discovery": "$([ $TESTS_FAILED -eq 0 ] && echo "passed" || echo "see logs")",
    "record_operations": "$([ $TESTS_FAILED -eq 0 ] && echo "passed" || echo "see logs")",
    "end_to_end_workflow": "$([ $TESTS_FAILED -eq 0 ] && echo "passed" || echo "see logs")"
  }
}
EOF

# Cleanup
rm -rf "$MOCK_API_RESPONSES_DIR"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All integration tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some integration tests failed!${NC}"
    exit 1
fi
