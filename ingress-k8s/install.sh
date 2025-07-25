#!/bin/bash

# Traefik Installation Script using Helm

echo "Installing Traefik using Helm..."

# Add Traefik Helm repository
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Create namespace
kubectl create namespace traefik-system --dry-run=client -o yaml | kubectl apply -f -

# Install or upgrade Traefik
helm upgrade --install traefik traefik/traefik \
  --namespace traefik-system \
  --values values.yaml \
  --wait

echo "Traefik installation completed!"

# Show status
echo "Checking Traefik status..."
kubectl get pods -n traefik-system
kubectl get svc -n traefik-system

echo ""
echo "To access the Traefik dashboard, create an ingress or use port-forward:"
echo "kubectl port-forward -n traefik-system svc/traefik 9000:9000"
echo "Then visit: http://localhost:9000/dashboard/"
