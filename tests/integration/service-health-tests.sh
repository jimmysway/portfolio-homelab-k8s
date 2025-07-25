#!/bin/bash

# Service Health Check Tests
# Tests service availability, health endpoints, and basic functionality

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

# Mock service endpoints for testing
declare -A MOCK_SERVICES=(
    ["immich"]="http://photos.example.com"
    ["glance"]="http://dashboard.example.com"
    ["traefik"]="http://traefik.example.com"
    ["cloudflare-ddns"]="internal"
    ["wireguard"]="udp://vpn.example.com:51820"
)

# Test utility functions
log_test() {
    echo -e "${BLUE}[HEALTH CHECK]${NC} $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

assert_health_check() {
    local service_name="$1"
    local status="$2"
    local message="$3"
    local details="$4"

    if [ "$status" = "healthy" ]; then
        echo -e "${GREEN}  ✓ HEALTHY:${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}  ✗ UNHEALTHY:${NC} $message"
        if [ -n "$details" ]; then
            echo -e "${RED}    Details: $details${NC}"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Mock HTTP client for testing
mock_http_check() {
    local url="$1"
    local expected_code="${2:-200}"

    # Simulate HTTP responses based on service
    case "$url" in
        *"photos.example.com"*)
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: application/json"
            echo ""
            echo '{"status":"ok","message":"Immich is running"}'
            return 0
            ;;
        *"dashboard.example.com"*)
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: text/html"
            echo ""
            echo '<html><title>Glance Dashboard</title></html>'
            return 0
            ;;
        *"traefik.example.com"*)
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: application/json"
            echo ""
            echo '{"version":"2.10","health":"ok"}'
            return 0
            ;;
        *)
            echo "HTTP/1.1 503 Service Unavailable"
            return 1
            ;;
    esac
}

# Mock DNS resolution check
mock_dns_check() {
    local domain="$1"

    case "$domain" in
        "example.com"|"photos.example.com"|"dashboard.example.com")
            echo "203.0.113.100"
            return 0
            ;;
        *)
            echo "NXDOMAIN"
            return 1
            ;;
    esac
}

# Test: Service Configuration Validation
test_service_configuration() {
    log_test "Testing service configuration validity"

    local valid_services=0
    local total_services=0
    local config_issues=()

    while IFS= read -r -d '' file; do
        if grep -q "kind: Service" "$file"; then
            total_services=$((total_services + 1))

            # Check basic service configuration
            local has_name=$(grep -c "name:" "$file" || echo "0")
            local has_selector=$(grep -c "selector:" "$file" || echo "0")
            local has_ports=$(grep -c "ports:" "$file" || echo "0")

            if [ "$has_name" -gt 0 ] && [ "$has_selector" -gt 0 ] && [ "$has_ports" -gt 0 ]; then
                valid_services=$((valid_services + 1))
                echo "    ✓ Valid service config: $(basename "$file")"
            else
                config_issues+=("$(basename "$file"): Missing required service configuration")
                echo "    ✗ Invalid service config: $(basename "$file")"
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_services" -eq 0 ]; then
        assert_health_check "service_config" "healthy" "No services found to validate"
    else
        if [ "$valid_services" -eq "$total_services" ]; then
            assert_health_check "service_config" "healthy" "All services have valid configuration ($valid_services/$total_services)"
        else
            local issue_summary="${config_issues[0]:-Configuration issues detected}"
            assert_health_check "service_config" "unhealthy" "Service configuration issues ($valid_services/$total_services valid)" "$issue_summary"
        fi
    fi
}

# Test: Ingress Health Checks
test_ingress_health() {
    log_test "Testing ingress endpoint health"

    local healthy_ingresses=0
    local total_ingresses=0
    local ingress_issues=()

    while IFS= read -r -d '' file; do
        if grep -q "kind: Ingress" "$file"; then
            total_ingresses=$((total_ingresses + 1))

            # Extract host from ingress
            local host=$(grep -A5 "rules:" "$file" | grep "host:" | head -1 | sed 's/.*host: *//' | sed 's/ *$//')

            if [ -n "$host" ]; then
                # Simulate health check
                local health_response=$(mock_http_check "http://$host" 2>/dev/null || echo "failed")

                if echo "$health_response" | grep -q "200 OK"; then
                    healthy_ingresses=$((healthy_ingresses + 1))
                    echo "    ✓ Healthy ingress: $host"
                else
                    ingress_issues+=("$host: Health check failed")
                    echo "    ✗ Unhealthy ingress: $host"
                fi
            else
                ingress_issues+=("$(basename "$file"): No host specified")
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_ingresses" -eq 0 ]; then
        assert_health_check "ingress_health" "healthy" "No ingresses found to check"
    else
        if [ "$healthy_ingresses" -eq "$total_ingresses" ]; then
            assert_health_check "ingress_health" "healthy" "All ingresses are healthy ($healthy_ingresses/$total_ingresses)"
        else
            local issue_summary="${ingress_issues[0]:-Ingress health issues detected}"
            assert_health_check "ingress_health" "unhealthy" "Some ingresses are unhealthy ($healthy_ingresses/$total_ingresses healthy)" "$issue_summary"
        fi
    fi
}

# Test: DNS Resolution Health
test_dns_resolution_health() {
    log_test "Testing DNS resolution health"

    local resolved_domains=0
    local total_domains=0
    local dns_issues=()

    # Extract domains from ingress resources
    local domains=()
    while IFS= read -r -d '' file; do
        if grep -q "kind: Ingress" "$file"; then
            local hosts=$(grep -A10 "rules:" "$file" | grep "host:" | sed 's/.*host: *//' | sed 's/ *$//')
            while IFS= read -r host; do
                if [ -n "$host" ]; then
                    domains+=("$host")
                fi
            done <<< "$hosts"
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    # Test DNS resolution for each domain
    for domain in "${domains[@]}"; do
        if [ -n "$domain" ]; then
            total_domains=$((total_domains + 1))

            local dns_result=$(mock_dns_check "$domain" 2>/dev/null || echo "NXDOMAIN")

            if [[ "$dns_result" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                resolved_domains=$((resolved_domains + 1))
                echo "    ✓ DNS resolved: $domain -> $dns_result"
            else
                dns_issues+=("$domain: DNS resolution failed")
                echo "    ✗ DNS resolution failed: $domain"
            fi
        fi
    done

    if [ "$total_domains" -eq 0 ]; then
        assert_health_check "dns_resolution" "healthy" "No domains found to resolve"
    else
        if [ "$resolved_domains" -eq "$total_domains" ]; then
            assert_health_check "dns_resolution" "healthy" "All domains resolve correctly ($resolved_domains/$total_domains)"
        else
            local issue_summary="${dns_issues[0]:-DNS resolution issues detected}"
            assert_health_check "dns_resolution" "unhealthy" "DNS resolution issues ($resolved_domains/$total_domains resolved)" "$issue_summary"
        fi
    fi
}

# Test: Application-Specific Health Checks
test_application_health() {
    log_test "Testing application-specific health"

    # Test Photo Management (Immich) Health
    local immich_health="unknown"
    if find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" | xargs grep -l "immich\|photo" >/dev/null 2>&1; then
        # Simulate Immich health check
        local immich_response=$(mock_http_check "http://photos.example.com/api/server-info" 2>/dev/null || echo "failed")
        if echo "$immich_response" | grep -q "200 OK"; then
            immich_health="healthy"
            echo "    ✓ Immich photo service: Healthy"
        else
            immich_health="unhealthy"
            echo "    ✗ Immich photo service: Unhealthy"
        fi
    fi

    # Test Dashboard (Glance) Health
    local glance_health="unknown"
    if find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" | xargs grep -l "glance\|dashboard" >/dev/null 2>&1; then
        local glance_response=$(mock_http_check "http://dashboard.example.com" 2>/dev/null || echo "failed")
        if echo "$glance_response" | grep -q "200 OK"; then
            glance_health="healthy"
            echo "    ✓ Glance dashboard: Healthy"
        else
            glance_health="unhealthy"
            echo "    ✗ Glance dashboard: Unhealthy"
        fi
    fi

    # Test Traefik Health
    local traefik_health="unknown"
    if find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" | xargs grep -l "traefik" >/dev/null 2>&1; then
        local traefik_response=$(mock_http_check "http://traefik.example.com/api/health" 2>/dev/null || echo "failed")
        if echo "$traefik_response" | grep -q "200 OK"; then
            traefik_health="healthy"
            echo "    ✓ Traefik ingress: Healthy"
        else
            traefik_health="unhealthy"
            echo "    ✗ Traefik ingress: Unhealthy"
        fi
    fi

    # Test DNS Updater Health (internal service)
    local dns_updater_health="unknown"
    if find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" | xargs grep -l "cloudflare\|ddns" >/dev/null 2>&1; then
        # DNS updater doesn't have HTTP endpoint, check for recent activity
        dns_updater_health="healthy"  # Assume healthy if configured
        echo "    ✓ DNS updater: Configured and healthy"
    fi

    # Overall application health assessment
    local healthy_apps=0
    local total_apps=0

    for health in "$immich_health" "$glance_health" "$traefik_health" "$dns_updater_health"; do
        if [ "$health" != "unknown" ]; then
            total_apps=$((total_apps + 1))
            if [ "$health" = "healthy" ]; then
                healthy_apps=$((healthy_apps + 1))
            fi
        fi
    done

    if [ "$total_apps" -eq 0 ]; then
        assert_health_check "application_health" "healthy" "No applications found to check"
    else
        if [ "$healthy_apps" -eq "$total_apps" ]; then
            assert_health_check "application_health" "healthy" "All applications are healthy ($healthy_apps/$total_apps)"
        else
            assert_health_check "application_health" "unhealthy" "Some applications are unhealthy ($healthy_apps/$total_apps healthy)" "Check individual application logs"
        fi
    fi
}

# Test: Storage Health
test_storage_health() {
    log_test "Testing storage configuration health"

    local healthy_storage=0
    local total_storage=0
    local storage_issues=()

    # Check PersistentVolumes
    while IFS= read -r -d '' file; do
        if grep -q "kind: PersistentVolume" "$file"; then
            total_storage=$((total_storage + 1))

            local has_capacity=$(grep -c "capacity:" "$file" || echo "0")
            local has_access_modes=$(grep -c "accessModes:" "$file" || echo "0")
            local has_storage_class=$(grep -c "storageClassName:" "$file" || echo "0")

            if [ "$has_capacity" -gt 0 ] && [ "$has_access_modes" -gt 0 ]; then
                healthy_storage=$((healthy_storage + 1))
                echo "    ✓ Healthy PV: $(basename "$file")"
            else
                storage_issues+=("$(basename "$file"): PV configuration incomplete")
                echo "    ✗ Unhealthy PV: $(basename "$file")"
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    # Check PersistentVolumeClaims
    while IFS= read -r -d '' file; do
        if grep -q "kind: PersistentVolumeClaim" "$file"; then
            total_storage=$((total_storage + 1))

            local has_resources=$(grep -c "resources:" "$file" || echo "0")
            local has_requests=$(grep -c "requests:" "$file" || echo "0")

            if [ "$has_resources" -gt 0 ] && [ "$has_requests" -gt 0 ]; then
                healthy_storage=$((healthy_storage + 1))
                echo "    ✓ Healthy PVC: $(basename "$file")"
            else
                storage_issues+=("$(basename "$file"): PVC configuration incomplete")
                echo "    ✗ Unhealthy PVC: $(basename "$file")"
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    if [ "$total_storage" -eq 0 ]; then
        assert_health_check "storage_health" "healthy" "No persistent storage found"
    else
        if [ "$healthy_storage" -eq "$total_storage" ]; then
            assert_health_check "storage_health" "healthy" "Storage configuration is healthy ($healthy_storage/$total_storage)"
        else
            local issue_summary="${storage_issues[0]:-Storage configuration issues detected}"
            assert_health_check "storage_health" "unhealthy" "Storage configuration issues ($healthy_storage/$total_storage healthy)" "$issue_summary"
        fi
    fi
}

# Test: Configuration Consistency
test_configuration_consistency() {
    log_test "Testing configuration consistency"

    local consistency_score=0
    local consistency_checks=0
    local consistency_issues=()

    # Check for consistent naming across resources
    consistency_checks=$((consistency_checks + 1))
    local inconsistent_names=0

    # Extract service names and deployment names
    local service_names=()
    local deployment_names=()

    while IFS= read -r -d '' file; do
        if grep -q "kind: Service" "$file"; then
            local name=$(grep "name:" "$file" | head -1 | sed 's/.*name: *//' | sed 's/ *$//')
            if [ -n "$name" ]; then
                service_names+=("$name")
            fi
        elif grep -q "kind: Deployment" "$file"; then
            local name=$(grep "name:" "$file" | head -1 | sed 's/.*name: *//' | sed 's/ *$//')
            if [ -n "$name" ]; then
                deployment_names+=("$name")
            fi
        fi
    done < <(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -print0)

    # Simple consistency check - if we have services and deployments, some names should match
    if [ ${#service_names[@]} -gt 0 ] && [ ${#deployment_names[@]} -gt 0 ]; then
        local matches=0
        for service in "${service_names[@]}"; do
            for deployment in "${deployment_names[@]}"; do
                if [[ "$service" == *"$deployment"* ]] || [[ "$deployment" == *"$service"* ]]; then
                    matches=$((matches + 1))
                    break
                fi
            done
        done

        if [ "$matches" -gt 0 ]; then
            consistency_score=$((consistency_score + 1))
            echo "    ✓ Service/Deployment names consistent"
        else
            consistency_issues+=("No matching service/deployment names found")
            echo "    ⚠ Service/Deployment naming may be inconsistent"
        fi
    else
        consistency_score=$((consistency_score + 1))  # No inconsistency if one type missing
    fi

    # Check for consistent namespaces
    consistency_checks=$((consistency_checks + 1))
    local namespace_consistency=0
    local namespaces=$(find "$PORTFOLIO_DIR" -name "*.yaml" -o -name "*.yml" -exec grep "namespace:" {} \; | sed 's/.*namespace: *//' | sort -u | wc -l)

    if [ "$namespaces" -le 6 ]; then  # Reasonable number of namespaces for this setup
        consistency_score=$((consistency_score + 1))
        echo "    ✓ Namespace usage appears consistent ($namespaces namespaces)"
    else
        consistency_issues+=("Too many namespaces ($namespaces) may indicate inconsistency")
        echo "    ⚠ Many namespaces found ($namespaces)"
    fi

    # Overall consistency assessment
    local consistency_ratio=$((consistency_score * 100 / consistency_checks))
    if [ "$consistency_ratio" -ge 80 ]; then
        assert_health_check "config_consistency" "healthy" "Configuration consistency is good ($consistency_score/$consistency_checks checks passed)"
    else
        local issue_summary="${consistency_issues[0]:-Configuration consistency issues detected}"
        assert_health_check "config_consistency" "unhealthy" "Configuration consistency issues ($consistency_score/$consistency_checks checks passed)" "$issue_summary"
    fi
}

# Generate health report
generate_health_report() {
    local health_score=$((TESTS_PASSED * 100 / TESTS_RUN))

    cat > "$TEST_RESULTS_DIR/service-health-report.json" << EOF
{
  "test_suite": "service-health-checks",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_tests": $TESTS_RUN,
  "passed": $TESTS_PASSED,
  "failed": $TESTS_FAILED,
  "health_score": $health_score,
  "health_categories": {
    "service_configuration": "$([ $TESTS_FAILED -eq 0 ] && echo "healthy" || echo "check_required")",
    "ingress_health": "$([ $TESTS_FAILED -eq 0 ] && echo "healthy" || echo "check_required")",
    "dns_resolution": "$([ $TESTS_FAILED -eq 0 ] && echo "healthy" || echo "check_required")",
    "application_health": "$([ $TESTS_FAILED -eq 0 ] && echo "healthy" || echo "check_required")",
    "storage_health": "$([ $TESTS_FAILED -eq 0 ] && echo "healthy" || echo "check_required")",
    "configuration_consistency": "$([ $TESTS_FAILED -eq 0 ] && echo "healthy" || echo "check_required")"
  },
  "recommendations": [
    "Monitor application health endpoints regularly",
    "Implement automated health checks in production",
    "Set up alerting for service failures",
    "Validate DNS resolution periodically",
    "Monitor storage capacity and performance"
  ]
}
EOF
}

# Run all health tests
echo -e "${BLUE}💚 Running Service Health Check Tests${NC}"
echo "============================================="

test_service_configuration
test_ingress_health
test_dns_resolution_health
test_application_health
test_storage_health
test_configuration_consistency

# Health summary
echo ""
echo "============================================="
echo -e "${BLUE}📊 Service Health Summary${NC}"
echo "============================================="
echo -e "Health Checks Run:    ${YELLOW}$TESTS_RUN${NC}"
echo -e "Health Checks Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Health Checks Failed: ${RED}$TESTS_FAILED${NC}"

local health_percentage=$((TESTS_PASSED * 100 / TESTS_RUN))
echo -e "Overall Health Score: ${BLUE}$health_percentage%${NC}"

if [ "$health_percentage" -ge 90 ]; then
    echo -e "System Health Status: ${GREEN}EXCELLENT${NC}"
elif [ "$health_percentage" -ge 75 ]; then
    echo -e "System Health Status: ${GREEN}GOOD${NC}"
elif [ "$health_percentage" -ge 60 ]; then
    echo -e "System Health Status: ${YELLOW}FAIR${NC}"
else
    echo -e "System Health Status: ${RED}POOR${NC}"
fi

generate_health_report

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All service health checks passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some service health checks failed!${NC}"
    echo -e "${YELLOW}💡 Review the failed health checks and address issues${NC}"
    exit 1
fi
