# gitops-infra

Activity 1: GitOps Deployment Pipeline with ArgoCD.

## Structure

```text
dev/task-tracker/
  namespace.yaml
  deployment.yaml  # nginx:1.27, replicas: 2 -> 3 for auto-sync test
  service.yaml     # ClusterIP :80
task-tracker-app.yaml  # ArgoCD Application (automated prune + selfHeal)
```

## Flow

Git change -> ArgoCD detects -> ArgoCD syncs -> Kubernetes updated.
Manual `kubectl scale` drift is auto-corrected via `selfHeal: true`.
