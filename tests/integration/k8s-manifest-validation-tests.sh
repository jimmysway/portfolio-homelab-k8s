#!/bin/bash

# Kubernetes Manifest Validation Tests
# Validates YAML syntax, schema compliance, and best practices

set -e

# Test framework setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTFOLIO_DIR="$SCRIPT_DIR/../.."
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

# Test utility functions
log_test() {
    echo -e "${BLUE}[K8S VALIDATION]${NC} $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

assert_success() {
    local exit_code="$1"
    local message="$2"

    if [ "$exit_code" -eq 0 ]; then
        echo -e "${GREEN}  ✓ PASS:${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}  ✗ FAIL:${NC} $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_contains() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if echo "$actual" | grep -q "$expected"; then
        echo -e "${GREEN}  ✓ PASS:${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}  ✗ FAIL:${NC} $message"
        echo -e "${RED}    Expected to contain: '$expected'${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test: YAML Syntax Validation
test_yaml_syntax() {
    log_test "Testing YAML syntax validation"

    local yaml_files_found=0
    local yaml_files_valid=0

    # Find all YAML/YML files
    find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" | while read -r yaml_file; do
        yaml_files_found=$((yaml_files_found + 1))

        # Test YAML syntax using Python
        if python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
            yaml_files_valid=$((yaml_files_valid + 1))
            echo "    ✓ Valid: $(basename "$yaml_file")"
        else
            echo "    ✗ Invalid: $(basename "$yaml_file")"
        fi
    done

    # Since we're in a subshell, we need to check differently
    local total_yaml=$(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" | wc -l)
    local invalid_yaml=$(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -exec python3 -c "import yaml; yaml.safe_load(open('{}'))" \; 2>&1 | grep -c "Error" || echo "0")

    if [ "$invalid_yaml" -eq 0 ]; then
        assert_success 0 "All $total_yaml YAML files have valid syntax"
    else
        assert_success 1 "$invalid_yaml YAML files have syntax errors"
    fi
}

# Test: Kubernetes Schema Validation
test_k8s_schema_validation() {
    log_test "Testing Kubernetes schema validation"

    # Mock kubeval functionality (would normally use kubeval tool)
    local k8s_files=()
    while IFS= read -r -d '' file; do
        k8s_files+=("$file")
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    local schema_valid=0
    local schema_total=0

    for file in "${k8s_files[@]}"; do
        # Check if file contains Kubernetes resources
        if grep -q "apiVersion:" "$file" && grep -q "kind:" "$file"; then
            schema_total=$((schema_total + 1))

            # Basic schema validation checks
            local has_metadata=$(grep -c "metadata:" "$file" || echo "0")
            local has_name=$(grep -c "name:" "$file" || echo "0")

            if [ "$has_metadata" -gt 0 ] && [ "$has_name" -gt 0 ]; then
                schema_valid=$((schema_valid + 1))
                echo "    ✓ Schema valid: $(basename "$file")"
            else
                echo "    ✗ Schema invalid: $(basename "$file")"
            fi
        fi
    done

    if [ "$schema_total" -eq 0 ]; then
        assert_success 0 "No Kubernetes manifests found to validate"
    elif [ "$schema_valid" -eq "$schema_total" ]; then
        assert_success 0 "All $schema_total Kubernetes manifests have valid schema"
    else
        assert_success 1 "$((schema_total - schema_valid))/$schema_total manifests have schema issues"
    fi
}

# Test: Resource Naming Conventions
test_naming_conventions() {
    log_test "Testing Kubernetes naming conventions"

    local naming_issues=0

    # Check for proper resource naming (lowercase, hyphens)
    while IFS= read -r -d '' file; do
        if grep -q "apiVersion:" "$file"; then
            # Extract resource names
            local names=$(grep "name:" "$file" | grep -v "#" | sed 's/.*name: *//g' | sed 's/"//g')

            while IFS= read -r name; do
                if [ -n "$name" ]; then
                    # Check if name follows Kubernetes conventions
                    if [[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
                        echo "    ✓ Valid name: $name"
                    else
                        echo "    ✗ Invalid name: $name (should be lowercase with hyphens)"
                        naming_issues=$((naming_issues + 1))
                    fi
                fi
            done <<< "$names"
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    assert_success $([ "$naming_issues" -eq 0 ] && echo "0" || echo "1") "Kubernetes naming conventions compliance ($naming_issues issues found)"
}

# Test: Security Context Validation
test_security_contexts() {
    log_test "Testing security context configurations"

    local deployments_with_security=0
    local total_deployments=0

    # Find deployment files
    while IFS= read -r -d '' file; do
        if grep -q "kind: Deployment" "$file"; then
            total_deployments=$((total_deployments + 1))

            # Check for security contexts
            if grep -q "securityContext:" "$file"; then
                local has_non_root=$(grep -c "runAsNonRoot: true" "$file" || echo "0")
                local has_read_only_fs=$(grep -c "readOnlyRootFilesystem: true" "$file" || echo "0")
                local drops_caps=$(grep -c "drop:" "$file" || echo "0")

                if [ "$has_non_root" -gt 0 ] || [ "$has_read_only_fs" -gt 0 ] || [ "$drops_caps" -gt 0 ]; then
                    deployments_with_security=$((deployments_with_security + 1))
                    echo "    ✓ Security context found: $(basename "$file")"
                else
                    echo "    ⚠ Weak security context: $(basename "$file")"
                fi
            else
                echo "    ✗ No security context: $(basename "$file")"
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_deployments" -eq 0 ]; then
        assert_success 0 "No deployments found to check"
    else
        local security_ratio=$((deployments_with_security * 100 / total_deployments))
        if [ "$security_ratio" -ge 80 ]; then
            assert_success 0 "$deployments_with_security/$total_deployments deployments have security contexts"
        else
            assert_success 1 "Only $deployments_with_security/$total_deployments deployments have security contexts"
        fi
    fi
}

# Test: Resource Limits Validation
test_resource_limits() {
    log_test "Testing resource limits configuration"

    local containers_with_limits=0
    local total_containers=0

    # Count containers with resource limits
    while IFS= read -r -d '' file; do
        if grep -q "containers:" "$file"; then
            # Count container definitions
            local container_count=$(grep -c "- name:" "$file" | head -1)
            total_containers=$((total_containers + container_count))

            # Check for resource limits
            local resources_count=$(grep -c "resources:" "$file" || echo "0")
            local limits_count=$(grep -c "limits:" "$file" || echo "0")
            local requests_count=$(grep -c "requests:" "$file" || echo "0")

            if [ "$limits_count" -gt 0 ] && [ "$requests_count" -gt 0 ]; then
                containers_with_limits=$((containers_with_limits + resources_count))
                echo "    ✓ Resource limits found: $(basename "$file")"
            else
                echo "    ⚠ Missing resource limits: $(basename "$file")"
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_containers" -eq 0 ]; then
        assert_success 0 "No containers found to check"
    else
        local limits_ratio=$((containers_with_limits * 100 / total_containers))
        if [ "$limits_ratio" -ge 50 ]; then
            assert_success 0 "Resource limits configured appropriately"
        else
            assert_success 1 "Insufficient resource limits configuration"
        fi
    fi
}

# Test: Namespace Usage
test_namespace_usage() {
    log_test "Testing namespace usage"

    local resources_with_namespace=0
    local total_resources=0

    while IFS= read -r -d '' file; do
        if grep -q "apiVersion:" "$file" && grep -q "kind:" "$file"; then
            total_resources=$((total_resources + 1))

            if grep -q "namespace:" "$file"; then
                resources_with_namespace=$((resources_with_namespace + 1))
                echo "    ✓ Namespace specified: $(basename "$file")"
            else
                # Check if it's a cluster-wide resource that doesn't need namespace
                local kind=$(grep "kind:" "$file" | head -1 | sed 's/.*kind: *//' | sed 's/ *$//')
                if [[ "$kind" =~ ^(ClusterRole|ClusterRoleBinding|PersistentVolume|StorageClass|Namespace)$ ]]; then
                    resources_with_namespace=$((resources_with_namespace + 1))
                    echo "    ✓ Cluster resource (no namespace needed): $(basename "$file")"
                else
                    echo "    ⚠ No namespace specified: $(basename "$file")"
                fi
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_resources" -eq 0 ]; then
        assert_success 0 "No resources found to check"
    else
        local namespace_ratio=$((resources_with_namespace * 100 / total_resources))
        if [ "$namespace_ratio" -ge 90 ]; then
            assert_success 0 "Good namespace usage ($resources_with_namespace/$total_resources resources)"
        else
            assert_success 1 "Poor namespace usage ($resources_with_namespace/$total_resources resources)"
        fi
    fi
}

# Test: Label and Selector Consistency
test_labels_and_selectors() {
    log_test "Testing label and selector consistency"

    local consistent_selectors=0
    local total_selectors=0

    # Find deployments and services with selectors
    while IFS= read -r -d '' file; do
        if grep -q "selector:" "$file"; then
            total_selectors=$((total_selectors + 1))

            # Basic check for label/selector presence
            local has_labels=$(grep -c "labels:" "$file" || echo "0")
            local has_selector=$(grep -c "selector:" "$file" || echo "0")

            if [ "$has_labels" -gt 0 ] && [ "$has_selector" -gt 0 ]; then
                consistent_selectors=$((consistent_selectors + 1))
                echo "    ✓ Labels and selectors present: $(basename "$file")"
            else
                echo "    ⚠ Missing labels or selectors: $(basename "$file")"
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_selectors" -eq 0 ]; then
        assert_success 0 "No selectors found to check"
    else
        local consistency_ratio=$((consistent_selectors * 100 / total_selectors))
        if [ "$consistency_ratio" -ge 90 ]; then
            assert_success 0 "Good label/selector consistency ($consistent_selectors/$total_selectors)"
        else
            assert_success 1 "Poor label/selector consistency ($consistent_selectors/$total_selectors)"
        fi
    fi
}

# Test: Ingress Configuration
test_ingress_configuration() {
    log_test "Testing ingress configuration"

    local secure_ingresses=0
    local total_ingresses=0

    while IFS= read -r -d '' file; do
        if grep -q "kind: Ingress" "$file"; then
            total_ingresses=$((total_ingresses + 1))

            # Check for TLS configuration
            local has_tls=$(grep -c "tls:" "$file" || echo "0")
            local has_cert_resolver=$(grep -c "certresolver" "$file" || echo "0")

            if [ "$has_tls" -gt 0 ] || [ "$has_cert_resolver" -gt 0 ]; then
                secure_ingresses=$((secure_ingresses + 1))
                echo "    ✓ Secure ingress: $(basename "$file")"
            else
                echo "    ⚠ Insecure ingress: $(basename "$file")"
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_ingresses" -eq 0 ]; then
        assert_success 0 "No ingresses found to check"
    else
        if [ "$secure_ingresses" -eq "$total_ingresses" ]; then
            assert_success 0 "All ingresses are properly secured ($secure_ingresses/$total_ingresses)"
        else
            assert_success 1 "Some ingresses lack security configuration ($secure_ingresses/$total_ingresses)"
        fi
    fi
}

# Run all tests
echo -e "${BLUE}🧪 Running Kubernetes Manifest Validation Tests${NC}"
echo "======================================================="

test_yaml_syntax
test_k8s_schema_validation
test_naming_conventions
test_security_contexts
test_resource_limits
test_namespace_usage
test_labels_and_selectors
test_ingress_configuration

# Test summary
echo ""
echo "======================================================="
echo -e "${BLUE}📊 Kubernetes Validation Summary${NC}"
echo "======================================================="
echo -e "Tests Run:    ${YELLOW}$TESTS_RUN${NC}"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

# Generate test report
cat > "$TEST_RESULTS_DIR/k8s-manifest-validation.json" << EOF
{
  "test_suite": "k8s-manifest-validation",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_tests": $TESTS_RUN,
  "passed": $TESTS_PASSED,
  "failed": $TESTS_FAILED,
  "success_rate": $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_RUN" | bc 2>/dev/null || echo "0"),
  "validation_categories": {
    "yaml_syntax": "$([ $TESTS_FAILED -eq 0 ] && echo "passed" || echo "check logs")",
    "k8s_schema": "$([ $TESTS_FAILED -eq 0 ] && echo "passed" || echo "check logs")",
    "security_contexts": "$([ $TESTS_FAILED -eq 0 ] && echo "passed" || echo "check logs")",
    "resource_limits": "$([ $TESTS_FAILED -eq 0 ] && echo "passed" || echo "check logs")",
    "namespace_usage": "$([ $TESTS_FAILED -eq 0 ] && echo "passed" || echo "check logs")",
    "ingress_security": "$([ $TESTS_FAILED -eq 0 ] && echo "passed" || echo "check logs")"
  }
}
EOF

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All Kubernetes manifest validation tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some Kubernetes manifest validation tests failed!${NC}"
    echo -e "${YELLOW}💡 Consider reviewing the failed validations for best practices${NC}"
    exit 1
fi
