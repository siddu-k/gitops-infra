#!/bin/bash
# Activity 1 - WSL Ubuntu tool installer
# Run: bash scripts/00-install-tools-wsl.sh 2>&1 | tee install-log.txt
set -e
echo "=== docker check (needs Docker Desktop + WSL integration) ==="
docker --version || echo "MISSING: Install Docker Desktop on Windows, enable WSL integration for Ubuntu"

echo "=== kubectl ==="
if ! command -v kubectl >/dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi
kubectl version --client

echo "=== kind ==="
if ! command -v kind >/dev/null; then
  curl -Lo ./kind "https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64"
  chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
fi
kind --version

echo "=== helm ==="
if ! command -v helm >/dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version
echo "DONE"
