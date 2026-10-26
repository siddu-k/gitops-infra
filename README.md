# GitOps Implementation with ArgoCD

## 1. Project Title

**GitOps Implementation with ArgoCD — Multi-Environment Deployment, Promotion, Rollback and Security**

## 2. Project Objective

Git is used as the **single source of truth** for Kubernetes application deployment.
ArgoCD continuously watches the repository, reconciles the cluster against the manifests
in Git, and heals any manual drift. This project extends the basic Activity 1 pipeline
(`dev` only) into a **multi-environment GitOps system** with `dev`, `staging` and `prod`
environments, an environment promotion workflow, rollback, RBAC and AppProject controls.

## 3. Tools Used

| Tool | Purpose |
|---|---|
| Git / GitHub | Source of truth repository |
| Kubernetes (Kind) | Local cluster (`gitops-cluster`) |
| Docker Desktop | Container runtime for Kind |
| kubectl | Cluster management |
| ArgoCD | Declarative GitOps controller (v3.5) |
| ArgoCD CLI | History/rollback/RBAC administration |
| Helm | ArgoCD installation manifests |

## 4. Architecture

```
                 GitHub Repository
                 (siddu-k/gitops-infra)
                       |
                       v
                    ArgoCD
   (diff detection -> sync -> self-healing -> rollback)
                       |
          +------------+------------+
          v            v            v
         DEV        STAGING        PROD
      (3 pods)     (2 pods)      (3 pods)
```

Applications managed by ArgoCD:

| Application | Path | Destination namespace | Replicas | Image |
|---|---|---|---|---|
| task-tracker-dev | dev/task-tracker | dev | 3 | nginx:1.27 |
| task-tracker-staging | staging/task-tracker | staging | 2 | nginx:1.28 |
| task-tracker-prod | prod/task-tracker | prod | 3 | nginx:1.28 |

## 5. Repository Structure

```
gitops-infra/
├── dev/task-tracker/        namespace.yaml deployment.yaml service.yaml
├── staging/task-tracker/    namespace.yaml deployment.yaml service.yaml
├── prod/task-tracker/       namespace.yaml deployment.yaml service.yaml
├── task-tracker-app.yaml      (Application -> dev)
├── task-tracker-staging.yaml  (Application -> staging)
├── task-tracker-prod.yaml     (Application -> prod)
├── gitops-project.yaml        (AppProject: controlled access)
└── README.md
```

Each environment folder is independent; ArgoCD Applications point at the matching
folder/namespace. Promotion = an identical Git change applied to the next folder.

## 6. GitOps Workflow

```
Git Commit
    ↓
ArgoCD Detects Change (repo polling every ~3 min)
    ↓
Application Synchronization (automated, prune + selfHeal)
    ↓
Kubernetes Deployment (rolling update)
    ↓
Health Monitoring (health status continuously evaluated)
    ↓
Self-Healing / Rollback
```

Promotion workflow: DEV -> testing -> STAGING -> approval -> PRODUCTION.
Promotion is performed by Git commits only — no `kubectl apply` is used to change the
desired state.

## 7. Security

### 7.1 RBAC (Part I, Step 20)
Configured in `argocd-rbac-cm` (`policy.csv`):

```
p, role:developer, applications, get, */*, allow
p, role:developer, applications, sync, */task-tracker-dev, allow
p, role:qa, applications, get, */*, allow
p, role:qa, applications, sync, */task-tracker-staging, allow
p, role:admin, applications, *, */*, allow
g, admin, role:admin
g, developer-user, role:developer
g, qa-user, role:qa
```

Verified against real API tokens:
- `developer-user` → sync `task-tracker-dev`: ALLOW; staging/prod: `PermissionDenied`
- `qa-user` → sync `task-tracker-staging`: ALLOW; dev: `PermissionDenied`

### 7.2 AppProject (Part J, Step 21)
`gitops-project.yaml` whitelists the single source repo and restricts destinations to
the `dev`, `staging` and `prod` namespaces only — preventing an Application from
deploying to arbitrary cluster namespaces.

### 7.3 Default admin credential rotation
The initial admin password was rotated (`argocd-secret` bcrypt update) before any
RBAC change, and the ArgoCD UI is only reachable through an authenticated HTTPS
endpoint (self-signed TLS in the local kind cluster; behind a real ingress this would
be replaced by a valid CA-issued certificate).

### 7.4 Recommended/hardening (not in lab scope)
- Git branch protection on `main` (PR approvals before prod folders change)
- Secret management (SOPS + age, sealed-secrets, or external-secrets; GitOps repos
  must never hold plaintext credentials)
- TLS/HTTPS end to end (ArgoCD ingress via cert-manager)
- Audit logs (`argocd audit-logs`, activity events stored in Redis/K8s events)

## 8. Policy-as-Code (Part K, Step 22)

Production workloads should be guarded by policy-as-code tools —
**Kyverno** or **OPA Gatekeeper** — enforced inside the GitOps workflow so that a
rejected resource never leaves Git:

Three example policies to enforce in production manifests:

1. **Prevent privileged containers** — `spec.containers[*].securityContext.privileged`
   must be `false`/absent. (Kyverno: `ClusterPolicy` with `checkPrivileged: true` /
   Gatekeeper: `K8sPSPPrivilegedContainer` template.)
2. **Require resource limits** — every container must define
   `resources.limits` (cpu / memory). (Gatekeeper: `K8sContainerLimits` template.)
3. **Require approved container registries** — image references must start with
   approved registry prefixes (e.g. only `nginx`, `prod-registry.internal/...`).
   (Gatekeeper: `K8sAllowedRepos`; Kyverno `verifyImages`.)

Example Kyverno validation (`policies/no-privileged.yaml`):

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: no-privileged-containers
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-privileged
      match:
        resources:
          kinds: [Pod]
      validate:
        message: "Privileged containers are not allowed in production deployments."
        pattern:
          spec:
            containers:
              - =(securityContext):
                  =(privileged): "false"
```

Integration into the GitOps workflow: policies run as an AdmissionController in the
cluster; because ArgoCD applies manifests directly to the API server, a non-compliant
manifest fails both CI checks (argo-cd-vault/kustomize-conformance) and the live apply,
and ArgoCD surfaces the failed sync in the Application history.

## 9. Testing Evidence (summary of executed tests)

| # | Test | Expected | Actual | Status |
|---|---|---|---|---|
| 1 | Dev change (nginx:1.27→1.28, commit 42533d7) | ArgoCD auto-sync updates dev | rollout completed, image=1.28 | PASS |
| 2 | Promote to staging (commit 5bade7c) | staging auto-syncs | rollout completed, image=1.28 | PASS |
| 3 | Promote to production (commit dbf4e75) | prod auto-syncs | rollout completed, image=1.28 | PASS |
| 4 | Drift: `kubectl scale --replicas=1 -n prod` | selfHeal restores 3 replicas | desired 1/actual 1 → 3/3 in ~5 s | PASS |
| 5 | Rollback via `argocd app history` + `app rollback` | dev returns to previous version | Git revert commit 877286f keeps cluster and Git consistent | PASS |
| 6 | RBAC: developer-user sync staging/prod | PermissionDenied | `permission denied: applications, sync` | PASS |
| 7 | RBAC: qa-user sync dev | PermissionDenied | `permission denied: applications, sync` | PASS |
| 8 | AppProject restrictions | only dev/staging/prod destinations | destinations enforced | PASS |

All three ArgoCD Applications report **Synced / Healthy**.
Screenshots: see the report document.

## 10. Notes

- The kind node's local context survives restarts; if ArgoCD looks unhealthy after a
  Docker restart, wait for pods then check `kubectl get applications -n argocd`.
- Rollback requires `--sync-policy none` first; long-term, correct the desired state in
  Git (as done with commit 877286f).
