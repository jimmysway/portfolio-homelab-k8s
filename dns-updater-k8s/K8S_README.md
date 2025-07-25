# Cloudflare DDNS Updater - Kubernetes Deployment

This directory contains everything you need to deploy the Cloudflare DDNS updater to a Kubernetes cluster.
```

## 🚀 Quick Start

### 1. Update Your Credentials

Edit `k8s/secret.yaml` and replace the base64-encoded values with your actual credentials:

```bash
# Encode your email
echo -n "your-email@example.com" | base64

# Encode your API token
echo -n "your-cloudflare-api-token" | base64

# Encode your zone identifier
echo -n "your-zone-identifier" | base64
```

### 2. Update Configuration

Edit `k8s/configmap.yaml` to match your domain settings:

```yaml
data:
  DOMAIN_NAME: "yourdomain.com"
  RECORD_NAMES: "home www"  # Space-separated list
  TTL: "1"
  PROXY: "false"
  # ... other settings
```

### 3. Deploy

Run the deployment script:

```bash
./deploy.sh
```

Or deploy manually:

```bash
# Build the image
docker build -t cloudflare-ddns:latest .

# Deploy to Kubernetes
kubectl apply -k k8s/

# Check status
kubectl get pods -n cloudflare-ddns
```

## 🔧 Configuration Options

### ConfigMap (`k8s/configmap.yaml`)
- `DOMAIN_NAME`: Your domain name (e.g., "example.com")
- `RECORD_NAMES`: Space-separated list of subdomains (e.g., "home www api")
- `TTL`: DNS record TTL in seconds (1 = automatic)
- `PROXY`: Enable Cloudflare proxy ("true" or "false")
- `UPDATE_IPV6`: Update IPv6 records ("true" or "false")
- `MODE`: "loop" for continuous updates or "once" for single run
- `REPEAT_SECONDS`: Update interval in seconds (default: 300)
- `LOG_LEVEL`: "D" (Debug), "I" (Info), or "E" (Error)

### Secret (`k8s/secret.yaml`)
- `AUTH_EMAIL`: Your Cloudflare account email
- `AUTH_KEY`: Your Cloudflare API token
- `ZONE_IDENTIFIER`: Your domain's zone identifier from Cloudflare

## 📋 Management Commands

### View Logs
```bash
kubectl logs -f -n cloudflare-ddns deployment/cloudflare-ddns
```

### Update Configuration
```bash
# Edit the configmap
kubectl edit configmap cloudflare-ddns-config -n cloudflare-ddns

# Or update the file and apply
kubectl apply -k k8s/
```

### Restart Deployment
```bash
kubectl rollout restart deployment/cloudflare-ddns -n cloudflare-ddns
```

### Delete Deployment
```bash
kubectl delete -k k8s/
```

## 🏗️ For Infrastructure Repository

To integrate this into your infrastructure repository:

1. Copy the `k8s/` directory to your infrastructure repo
2. Update the `kustomization.yaml` to reference your container registry
3. Set up your CI/CD pipeline to build and push the image
4. Use ArgoCD, Flux, or similar for GitOps deployment

Example for container registry:

```yaml
# In kustomization.yaml
images:
- name: cloudflare-ddns
  newName: your-registry.com/cloudflare-ddns
  newTag: v1.0.0
```

## 🔒 Security Features

- Runs as non-root user (UID 1000)
- Read-only root filesystem
- Drops all capabilities
- Resource limits applied
- Secrets stored in Kubernetes secrets (not in plain text)

## 🐛 Troubleshooting

### Pod Not Starting
```bash
kubectl describe pod -n cloudflare-ddns -l app=cloudflare-ddns
```

### Check Logs
```bash
kubectl logs -n cloudflare-ddns deployment/cloudflare-ddns
```

### Test Configuration
```bash
# Run a one-time update
kubectl patch deployment cloudflare-ddns -n cloudflare-ddns -p '{"spec":{"template":{"spec":{"containers":[{"name":"cloudflare-ddns","env":[{"name":"MODE","value":"once"}]}]}}}}'
```

## 📈 Monitoring

The application logs IP changes and update results. You can integrate with your monitoring stack by:

1. Using a log aggregator (ELK, Loki, etc.)
2. Setting up alerts on error logs
3. Monitoring the deployment health with standard Kubernetes metrics
