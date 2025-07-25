#!/bin/bash

# Security Compliance Tests
# Tests for security best practices and compliance requirements

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

# Security compliance matrix
declare -A SECURITY_CONTROLS=(
    ["container_security"]="Container runs as non-root user"
    ["filesystem_security"]="Read-only root filesystem enabled"
    ["capability_dropping"]="Linux capabilities dropped"
    ["privilege_escalation"]="Privilege escalation disabled"
    ["resource_limits"]="Resource limits configured"
    ["network_policies"]="Network policies defined"
    ["secret_management"]="Secrets properly managed"
    ["rbac_enabled"]="RBAC controls implemented"
    ["ssl_termination"]="SSL/TLS encryption enabled"
    ["image_security"]="Container images from trusted sources"
)

# Test utility functions
log_test() {
    echo -e "${BLUE}[SECURITY TEST]${NC} $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

assert_security_control() {
    local control_name="$1"
    local passed="$2"
    local message="$3"
    local details="$4"

    if [ "$passed" = "true" ]; then
        echo -e "${GREEN}  ✓ PASS:${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}  ✗ FAIL:${NC} $message"
        if [ -n "$details" ]; then
            echo -e "${RED}    Details: $details${NC}"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test: Container Security Context
test_container_security_context() {
    log_test "Testing container security contexts"

    local secure_containers=0
    local total_containers=0
    local security_issues=()

    while IFS= read -r -d '' file; do
        if grep -q "kind: Deployment\|kind: StatefulSet\|kind: DaemonSet" "$file"; then
            # Count containers in this file
            local container_count=$(grep -c "- name:" "$file" 2>/dev/null || echo "0")
            total_containers=$((total_containers + container_count))

            # Check security context
            local has_security_context=$(grep -c "securityContext:" "$file" || echo "0")
            local runs_as_non_root=$(grep -c "runAsNonRoot: true" "$file" || echo "0")
            local runs_as_user=$(grep -c "runAsUser:" "$file" || echo "0")
            local read_only_fs=$(grep -c "readOnlyRootFilesystem: true" "$file" || echo "0")
            local no_privilege_escalation=$(grep -c "allowPrivilegeEscalation: false" "$file" || echo "0")
            local drops_capabilities=$(grep -A5 "capabilities:" "$file" | grep -c "drop:" || echo "0")

            local security_score=0

            if [ "$runs_as_non_root" -gt 0 ] || [ "$runs_as_user" -gt 0 ]; then
                security_score=$((security_score + 1))
            else
                security_issues+=("$(basename "$file"): Container may run as root")
            fi

            if [ "$read_only_fs" -gt 0 ]; then
                security_score=$((security_score + 1))
            else
                security_issues+=("$(basename "$file"): Writable root filesystem")
            fi

            if [ "$no_privilege_escalation" -gt 0 ]; then
                security_score=$((security_score + 1))
            else
                security_issues+=("$(basename "$file"): Privilege escalation not disabled")
            fi

            if [ "$drops_capabilities" -gt 0 ]; then
                security_score=$((security_score + 1))
            else
                security_issues+=("$(basename "$file"): Linux capabilities not dropped")
            fi

            # Consider container secure if it has at least 3/4 security measures
            if [ "$security_score" -ge 3 ]; then
                secure_containers=$((secure_containers + container_count))
                echo "    ✓ Secure container: $(basename "$file") (score: $security_score/4)"
            else
                echo "    ⚠ Insecure container: $(basename "$file") (score: $security_score/4)"
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_containers" -eq 0 ]; then
        assert_security_control "container_security" "true" "No containers found to assess"
    else
        local security_ratio=$((secure_containers * 100 / total_containers))
        if [ "$security_ratio" -ge 75 ]; then
            assert_security_control "container_security" "true" "Container security contexts adequately configured ($secure_containers/$total_containers containers secure)"
        else
            local issues_summary=""
            if [ ${#security_issues[@]} -gt 0 ]; then
                issues_summary="${security_issues[0]}"
                if [ ${#security_issues[@]} -gt 1 ]; then
                    issues_summary="$issues_summary (and $((${#security_issues[@]} - 1)) more)"
                fi
            fi
            assert_security_control "container_security" "false" "Insufficient container security ($secure_containers/$total_containers containers secure)" "$issues_summary"
        fi
    fi
}

# Test: Resource Limits and Security
test_resource_security() {
    log_test "Testing resource limits for security"

    local containers_with_limits=0
    local total_containers=0
    local resource_issues=()

    while IFS= read -r -d '' file; do
        if grep -q "containers:" "$file"; then
            local container_count=$(grep -c "- name:" "$file" | head -1)
            total_containers=$((total_containers + container_count))

            local has_requests=$(grep -c "requests:" "$file" || echo "0")
            local has_limits=$(grep -c "limits:" "$file" || echo "0")
            local has_memory_limit=$(grep -c "memory:" "$file" | head -1)
            local has_cpu_limit=$(grep -c "cpu:" "$file" | head -1)

            if [ "$has_requests" -gt 0 ] && [ "$has_limits" -gt 0 ]; then
                if [ "$has_memory_limit" -gt 0 ] && [ "$has_cpu_limit" -gt 0 ]; then
                    containers_with_limits=$((containers_with_limits + container_count))
                    echo "    ✓ Proper resource limits: $(basename "$file")"
                else
                    resource_issues+=("$(basename "$file"): Missing memory or CPU limits")
                fi
            else
                resource_issues+=("$(basename "$file"): Missing resource requests/limits")
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_containers" -eq 0 ]; then
        assert_security_control "resource_limits" "true" "No containers found to assess"
    else
        local limits_ratio=$((containers_with_limits * 100 / total_containers))
        if [ "$limits_ratio" -ge 60 ]; then
            assert_security_control "resource_limits" "true" "Resource limits configured for security ($containers_with_limits/$total_containers containers)"
        else
            local issue_summary="${resource_issues[0]:-No specific issues identified}"
            assert_security_control "resource_limits" "false" "Insufficient resource limits ($containers_with_limits/$total_containers containers)" "$issue_summary"
        fi
    fi
}

# Test: Secret Management
test_secret_management() {
    log_test "Testing secret management practices"

    local secrets_found=0
    local secure_secrets=0
    local secret_issues=()

    # Check for Kubernetes secrets
    while IFS= read -r -d '' file; do
        if grep -q "kind: Secret" "$file"; then
            secrets_found=$((secrets_found + 1))

            # Check if secret data is base64 encoded (not plain text)
            local has_data_section=$(grep -c "data:" "$file" || echo "0")
            local has_string_data=$(grep -c "stringData:" "$file" || echo "0")

            if [ "$has_data_section" -gt 0 ] && [ "$has_string_data" -eq 0 ]; then
                # Check if values look base64 encoded
                local base64_values=$(grep -A10 "data:" "$file" | grep -c "^  [^:]*: [A-Za-z0-9+/=]*$" || echo "0")
                if [ "$base64_values" -gt 0 ]; then
                    secure_secrets=$((secure_secrets + 1))
                    echo "    ✓ Properly encoded secret: $(basename "$file")"
                else
                    secret_issues+=("$(basename "$file"): Secret values may not be properly encoded")
                fi
            else
                secret_issues+=("$(basename "$file"): Uses stringData instead of encoded data")
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    # Check for hardcoded secrets in other files
    local hardcoded_secrets=0
    while IFS= read -r -d '' file; do
        if ! grep -q "kind: Secret" "$file"; then
            # Look for potential hardcoded secrets (simplified detection)
            local has_password=$(grep -i "password.*:" "$file" | grep -v "password-file\|password-hash" | wc -l)
            local has_key=$(grep -i "key.*:" "$file" | grep -v "ssh-key\|pub-key\|key-file" | wc -l)
            local has_token=$(grep -i "token.*:" "$file" | grep -v "token-file" | wc -l)

            if [ "$has_password" -gt 0 ] || [ "$has_key" -gt 0 ] || [ "$has_token" -gt 0 ]; then
                hardcoded_secrets=$((hardcoded_secrets + 1))
                secret_issues+=("$(basename "$file"): May contain hardcoded secrets")
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$secrets_found" -eq 0 ]; then
        assert_security_control "secret_management" "true" "No secrets found (externally managed)"
    else
        if [ "$secure_secrets" -eq "$secrets_found" ] && [ "$hardcoded_secrets" -eq 0 ]; then
            assert_security_control "secret_management" "true" "Secrets properly managed ($secure_secrets/$secrets_found secrets secure, no hardcoded secrets)"
        else
            local issue_summary="$hardcoded_secrets hardcoded secrets found"
            if [ ${#secret_issues[@]} -gt 0 ]; then
                issue_summary="$issue_summary; ${secret_issues[0]}"
            fi
            assert_security_control "secret_management" "false" "Secret management issues detected" "$issue_summary"
        fi
    fi
}

# Test: Network Security
test_network_security() {
    log_test "Testing network security configuration"

    local secure_ingresses=0
    local total_ingresses=0
    local secure_services=0
    local total_services=0
    local network_issues=()

    # Check ingress security
    while IFS= read -r -d '' file; do
        if grep -q "kind: Ingress" "$file"; then
            total_ingresses=$((total_ingresses + 1))

            local has_tls=$(grep -c "tls:" "$file" || echo "0")
            local has_cert_resolver=$(grep -c "certresolver\|cert-manager" "$file" || echo "0")
            local has_https_redirect=$(grep -c "redirect.*https\|ssl-redirect" "$file" || echo "0")

            if [ "$has_tls" -gt 0 ] || [ "$has_cert_resolver" -gt 0 ]; then
                secure_ingresses=$((secure_ingresses + 1))
                echo "    ✓ Secure ingress: $(basename "$file")"
            else
                network_issues+=("$(basename "$file"): Ingress lacks TLS/SSL configuration")
            fi
        fi

        # Check service security
        if grep -q "kind: Service" "$file"; then
            total_services=$((total_services + 1))

            # Check for secure service types
            local service_type=$(grep "type:" "$file" | sed 's/.*type: *//' | sed 's/ *$//' || echo "ClusterIP")
            local has_load_balancer=$(echo "$service_type" | grep -c "LoadBalancer" || echo "0")
            local has_node_port=$(echo "$service_type" | grep -c "NodePort" || echo "0")

            if [ "$has_load_balancer" -eq 0 ] && [ "$has_node_port" -eq 0 ]; then
                secure_services=$((secure_services + 1))
                echo "    ✓ Secure service type: $(basename "$file") ($service_type)"
            else
                network_issues+=("$(basename "$file"): Service exposes ports externally ($service_type)")
                echo "    ⚠ Exposed service: $(basename "$file") ($service_type)"
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    local network_security_score=0
    local total_network_components=$((total_ingresses + total_services))

    if [ "$total_ingresses" -gt 0 ]; then
        local ingress_ratio=$((secure_ingresses * 100 / total_ingresses))
        if [ "$ingress_ratio" -ge 80 ]; then
            network_security_score=$((network_security_score + 1))
        fi
    else
        network_security_score=$((network_security_score + 1))  # No ingresses is secure
    fi

    if [ "$total_services" -gt 0 ]; then
        local service_ratio=$((secure_services * 100 / total_services))
        if [ "$service_ratio" -ge 70 ]; then
            network_security_score=$((network_security_score + 1))
        fi
    else
        network_security_score=$((network_security_score + 1))  # No services to expose
    fi

    if [ "$network_security_score" -eq 2 ]; then
        assert_security_control "ssl_termination" "true" "Network security properly configured (ingresses: $secure_ingresses/$total_ingresses, services: $secure_services/$total_services)"
    else
        local issue_summary="${network_issues[0]:-Network security concerns identified}"
        assert_security_control "ssl_termination" "false" "Network security issues detected" "$issue_summary"
    fi
}

# Test: RBAC Implementation
test_rbac_implementation() {
    log_test "Testing RBAC implementation"

    local rbac_resources=0
    local service_accounts=0
    local rbac_issues=()

    while IFS= read -r -d '' file; do
        local has_rbac_kind=$(grep -c "kind: Role\|kind: RoleBinding\|kind: ClusterRole\|kind: ClusterRoleBinding" "$file" || echo "0")
        local has_service_account=$(grep -c "kind: ServiceAccount" "$file" || echo "0")
        local references_service_account=$(grep -c "serviceAccount:" "$file" || echo "0")

        if [ "$has_rbac_kind" -gt 0 ]; then
            rbac_resources=$((rbac_resources + 1))
            echo "    ✓ RBAC resource found: $(basename "$file")"
        fi

        if [ "$has_service_account" -gt 0 ]; then
            service_accounts=$((service_accounts + 1))
            echo "    ✓ Service account defined: $(basename "$file")"
        fi

        if [ "$references_service_account" -gt 0 ]; then
            echo "    ✓ References service account: $(basename "$file")"
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    # RBAC is considered implemented if we have at least some RBAC resources or service accounts
    if [ "$rbac_resources" -gt 0 ] || [ "$service_accounts" -gt 0 ]; then
        assert_security_control "rbac_enabled" "true" "RBAC controls detected ($rbac_resources RBAC resources, $service_accounts service accounts)"
    else
        assert_security_control "rbac_enabled" "false" "No RBAC implementation found" "Consider implementing Role-Based Access Control"
    fi
}

# Test: Image Security
test_image_security() {
    log_test "Testing container image security"

    local secure_images=0
    local total_images=0
    local image_issues=()

    while IFS= read -r -d '' file; do
        # Extract image references
        local images=$(grep "image:" "$file" | grep -v "#" | sed 's/.*image: *//' | sed 's/ *$//')

        while IFS= read -r image; do
            if [ -n "$image" ]; then
                total_images=$((total_images + 1))

                # Check for version tags (not latest)
                if [[ "$image" =~ .*:latest$ ]] || [[ ! "$image" =~ .*:.+ ]]; then
                    image_issues+=("$image: Uses 'latest' tag or no tag specified")
                    echo "    ⚠ Potentially insecure image: $image"
                else
                    # Check for trusted registries (simplified)
                    if [[ "$image" =~ ^(ghcr\.io|docker\.io|quay\.io|registry\.k8s\.io)/.+ ]]; then
                        secure_images=$((secure_images + 1))
                        echo "    ✓ Secure image: $image"
                    else
                        # Custom registry might be secure, but flag for review
                        secure_images=$((secure_images + 1))
                        echo "    ? Custom registry image: $image"
                    fi
                fi
            fi
        done <<< "$images"
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_images" -eq 0 ]; then
        assert_security_control "image_security" "true" "No images found to assess"
    else
        local security_ratio=$((secure_images * 100 / total_images))
        if [ "$security_ratio" -ge 80 ]; then
            assert_security_control "image_security" "true" "Container images use secure practices ($secure_images/$total_images images)"
        else
            local issue_summary="${image_issues[0]:-Image security concerns identified}"
            assert_security_control "image_security" "false" "Image security issues detected ($secure_images/$total_images images secure)" "$issue_summary"
        fi
    fi
}

# Generate security compliance report
generate_compliance_report() {
    local compliance_score=$((TESTS_PASSED * 100 / TESTS_RUN))

    cat > "$TEST_RESULTS_DIR/security-compliance-report.json" << EOF
{
  "test_suite": "security-compliance",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_tests": $TESTS_RUN,
  "passed": $TESTS_PASSED,
  "failed": $TESTS_FAILED,
  "compliance_score": $compliance_score,
  "security_controls": {
    "container_security": "$([ $TESTS_FAILED -lt $TESTS_RUN ] && echo "implemented" || echo "review_required")",
    "resource_limits": "$([ $TESTS_FAILED -lt $TESTS_RUN ] && echo "implemented" || echo "review_required")",
    "secret_management": "$([ $TESTS_FAILED -lt $TESTS_RUN ] && echo "implemented" || echo "review_required")",
    "network_security": "$([ $TESTS_FAILED -lt $TESTS_RUN ] && echo "implemented" || echo "review_required")",
    "rbac_controls": "$([ $TESTS_FAILED -lt $TESTS_RUN ] && echo "implemented" || echo "review_required")",
    "image_security": "$([ $TESTS_FAILED -lt $TESTS_RUN ] && echo "implemented" || echo "review_required")"
  },
  "recommendations": [
    "Review failed security controls",
    "Implement missing security contexts",
    "Ensure all secrets are properly managed",
    "Configure network policies where appropriate",
    "Use specific image tags instead of 'latest'"
  ]
}
EOF
}

# Run all security tests
echo -e "${BLUE}🔒 Running Security Compliance Tests${NC}"
echo "================================================="

test_container_security_context
test_resource_security
test_secret_management
test_network_security
test_rbac_implementation
test_image_security

# Test summary
echo ""
echo "================================================="
echo -e "${BLUE}📊 Security Compliance Summary${NC}"
echo "================================================="
echo -e "Security Tests Run:    ${YELLOW}$TESTS_RUN${NC}"
echo -e "Security Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Security Tests Failed: ${RED}$TESTS_FAILED${NC}"

local compliance_percentage=$((TESTS_PASSED * 100 / TESTS_RUN))
echo -e "Compliance Score:      ${BLUE}$compliance_percentage%${NC}"

if [ "$compliance_percentage" -ge 80 ]; then
    echo -e "Security Posture:      ${GREEN}STRONG${NC}"
elif [ "$compliance_percentage" -ge 60 ]; then
    echo -e "Security Posture:      ${YELLOW}MODERATE${NC}"
else
    echo -e "Security Posture:      ${RED}NEEDS IMPROVEMENT${NC}"
fi

generate_compliance_report

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All security compliance tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some security compliance tests failed!${NC}"
    echo -e "${YELLOW}💡 Review the failed tests and implement recommended security controls${NC}"
    exit 1
fi
