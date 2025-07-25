# Home Lab Kubernetes Infrastructure

A production-ready home laboratory environment demonstrating enterprise-level DevOps practices, container orchestration, and distributed systems management.

## Architecture Overview

This repository showcases a complete Kubernetes-based home lab infrastructure with multiple services working in harmony:

- **DNS Management**: Automated dynamic DNS updates with external API integration
- **Ingress Controller**: SSL termination and traffic routing with Traefik
- **Media Management**: Self-hosted photo management with persistent storage
- **Dashboard**: Centralized monitoring and information aggregation
- **VPN Access**: Secure remote access via WireGuard
- **Infrastructure**: Core cluster services and namespace management

## Technical Stack

- **Container Orchestration**: Kubernetes
- **Ingress**: Traefik with Let's Encrypt SSL
- **Storage**: Persistent volumes with local storage provisioner
- **Networking**: CNI with service mesh capabilities
- **Security**: Non-root containers, RBAC, network policies
- **Configuration**: GitOps with Kustomize and Helm

## Demonstrated Skills

### Distributed Systems
- Multi-service architecture with service discovery
- Container orchestration and lifecycle management
- State management with persistent storage
- Network segmentation and security policies

### Cloud & Infrastructure
- Infrastructure as Code (IaC) practices
- Container security best practices
- Resource management and scaling
- SSL/TLS certificate automation

### API Integration
- REST API consumption and error handling
- Authentication and rate limiting
- Configuration management with secrets
- Monitoring and observability

## Testing Framework

**Enterprise-level testing practices with 85%+ test coverage**

This repository includes a comprehensive test suite that demonstrates professional software development practices:

### Test Coverage
- **42+ individual tests** across 5 test suites
- **Unit tests** for DNS updater functions and logic
- **Integration tests** for API interactions and service health
- **Security compliance tests** validating 10+ security controls
- **Infrastructure validation** for Kubernetes manifests
- **Automated CI/CD** pipeline with GitHub Actions

### Quick Start
```bash
# Run all tests
./run-all-tests.sh

# Run specific test suite
./run-all-tests.sh --suite security

# View test results
cat tests/results/test-summary.json
```

**Key Testing Features:**
- Automated test execution with detailed reporting
- Security compliance validation (80%+ score)
- Mock frameworks for isolated testing
- CI/CD integration with automated PR comments
- Comprehensive test documentation

See [Testing Documentation](docs/TESTING.md) for complete details.

## Security & Pre-commit Checks

**Automated security scanning to prevent sensitive data leaks**

This repository includes pre-commit hooks that automatically scan for sensitive data before commits:

### Security Checks
- **Secrets Detection**: Scans for API keys, tokens, and credentials
- **Basic Security**: Checks for personal emails, domains, and hardcoded secrets
- **File Validation**: Ensures YAML/JSON syntax and prevents large file commits
- **Code Quality**: Enforces consistent formatting and line endings

### Setup Pre-commit
```bash
# Install pre-commit
pip install pre-commit

# Install the git hooks
pre-commit install

# Run manually on all files
pre-commit run --all-files
```

### What Gets Checked
- Personal email addresses and domains
- API keys and authentication tokens
- Private keys and certificates
- Hardcoded passwords and secrets
- Large files (>1MB)
- YAML/JSON syntax errors
- Merge conflicts

**Security Features:**
- Prevents accidental commit of sensitive data
- Automated scanning of all file types
- Clear error messages with remediation steps
- Fast execution with minimal overhead
- Easy to customize and extend

## Deployment

Each service includes comprehensive deployment documentation:
- Kubernetes manifests with Kustomize overlays
- Helm charts for complex applications
- Security configurations and RBAC
- Resource limits and health checks

## Repository Structure

```
portfolio-homelab-k8s/
├── dns-updater-k8s/          # Dynamic DNS management
├── ingress-k8s/              # Traefik ingress controller
├── photo-management-k8s/     # Immich photo service
├── dashboard-k8s/            # Glance dashboard
├── vpn-k8s/                  # WireGuard VPN
├── infrastructure-k8s/       # Core cluster services
├── tests/                    # Comprehensive test suite
├── docs/                     # Architecture documentation
└── .git/hooks/              # Pre-commit security checks
```

## Security Considerations

- All containers run as non-root users
- Read-only root filesystems where possible
- Kubernetes secrets for sensitive data
- Network policies for service isolation
- Regular security updates and scanning
- Automated pre-commit security validation

This infrastructure demonstrates production-ready practices suitable for enterprise environments while maintaining the flexibility and learning opportunities of a home lab setup.
