#!/bin/bash
# Activity 1 - full run with logging for screenshots
# Usage (in WSL Ubuntu, from repo root):
#   GITHUB_USER=<your-username> bash scripts/01-run-activity1.sh 2>&1 | tee activity1-log.txt
# Every command + output goes to activity1-log.txt for your screenshots/PDF.
set -x
GITHUB_USER="${GITHUB_USER:-<your-username>}"
echo "GITHUB_USER=$GITHUB_USER"

run() { echo -e "\n===== $* ====="; "$@"; }

run docker --version
run kubectl version --client
run kind --version
run helm version

# Part A
run kind create cluster --name gitops-cluster
run kubectl cluster-info
run kubectl get nodes

# Part B
run kubectl create namespace argocd
run kubectl get namespaces
run kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
run kubectl get pods -n argocd
echo "WAIT 2-3 min, re-run: kubectl get pods -n argocd until Running"

# Part C - password (screenshot this)
run kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
echo ""
echo "UI: kubectl port-forward svc/argocd-server -n argocd 8080:443  # keep running, open https://localhost:8080 admin/<password above>"
echo "SCREENSHOT: ArgoCD login + dashboard"

# Part G/H - push check
run git status
run git log --oneline -5
run ls -R dev
run cat dev/task-tracker/namespace.yaml
run cat dev/task-tracker/deployment.yaml
run cat dev/task-tracker/service.yaml
echo "Push: git add . && git commit -m 'Add task tracker' && git push origin main"
echo "SCREENSHOT: GitHub repo files + ArgoCD Settings>Repositories Connected"

# Part I - fix repoURL then apply
sed -i "s|<your-username>|$GITHUB_USER|g" task-tracker-app.yaml || true
run cat task-tracker-app.yaml
run kubectl apply -f task-tracker-app.yaml
run kubectl get applications -n argocd

# Part J
run kubectl get pods -n dev
run kubectl get deployment -n dev
run kubectl get service -n dev
echo "SCREENSHOT: ArgoCD Healthy/Synced"

# Part K - GitOps auto-sync test (manual edit + push)
echo "DO: change dev/task-tracker/deployment.yaml replicas: 2 -> 3, then git add/commit/push"
echo "THEN: kubectl get pods -n dev  (expect 3, no kubectl deploy)"
echo "SCREENSHOT: git commit + 3 pods"

# Part L - self-heal test
run kubectl scale deployment task-tracker --replicas=1 -n dev
run kubectl get deployment task-tracker -n dev
echo "WAIT ~1-3 min for ArgoCD selfHeal, then:"
run kubectl get deployment task-tracker -n dev
echo "SCREENSHOT: back to 3 replicas"
set +x
