# Task 3 – GitOps

**Author:** Ankit Kumar

## What is GitOps?

GitOps is a way of running infrastructure and applications where **the desired state of the system is stored in Git**, and an automated **agent** running next to the system keeps the live state equal to what Git says.

The term was coined by Weaveworks in 2017. The CNCF **OpenGitOps** project defines four principles:

| Principle | Meaning |
|-----------|---------|
| **Declarative** | The desired state is described (what), not scripted (how) |
| **Versioned and immutable** | The desired state is stored in a way that keeps full history and can't be silently changed: Git |
| **Pulled automatically** | Software agents pull the desired state from the source automatically |
| **Continuously reconciled** | Agents keep observing the actual state and correct any difference from the desired state |

In short: **every change is a Git commit, and deployment is a side effect of merging.**

## Git as the source of truth

Git is the only place where the intended state lives. Nobody runs `kubectl apply` or edits resources by hand in production.

What this gives me:

- **Audit trail**: `git log` shows who changed what, when and why.
- **Review**: changes go through pull requests, CI checks and approvals.
- **Rollback**: `git revert <commit>` returns the cluster to a previous known-good state.
- **Disaster recovery**: a new cluster can be rebuilt from the repo.
- **Fewer credentials**: developers need Git access, not cluster-admin access.

Common repo layouts: application code and manifests in one repo (simple, like this homework), or a separate **config/environment repo** where CI updates image tags after building.

## Declarative configuration

| Imperative | Declarative |
|------------|-------------|
| `kubectl create deployment web --image=nginx` then `kubectl scale ... --replicas=3` | A `Deployment` YAML with `replicas: 3` and `image: nginx:1.27` |
| Describes the steps | Describes the end result |
| Hard to reproduce, no history | Idempotent, diffable, versioned in Git |

Kubernetes is declarative by design, so it fits GitOps naturally. Plain YAML, **Kustomize** overlays (per-environment patches), **Helm** charts and Terraform are all declarative formats a GitOps tool can render.

## Continuous reconciliation

### Push vs pull model

| | Push model (classic CI/CD) | Pull model (GitOps) |
|---|---|---|
| Who deploys | The CI pipeline runs `kubectl apply` / `helm upgrade` | An agent **inside** the cluster pulls from Git |
| Cluster credentials | Stored in the CI system (larger attack surface) | Stay inside the cluster |
| Firewall | CI must reach the cluster API | Cluster only needs outbound access to Git |
| Drift handling | None after the pipeline finishes | Detected and corrected continuously |
| Examples | Jenkins / GitHub Actions deploy jobs | Argo CD, Flux |

### Drift detection and self-heal

**Drift** is any difference between the live cluster and Git, for example someone runs `kubectl scale deployment web --replicas=5` or deletes a Service.

The reconciliation loop:

```
loop:
  desired = render(manifests from Git @ targetRevision)
  live    = read(cluster state)
  if desired != live:
      mark application OutOfSync
      if automated sync: apply(desired)       # self-heal
      if prune enabled:  delete(objects removed from Git)
```

Argo CD polls Git every 3 minutes by default (a webhook makes it instant). With `selfHeal: true` it reverts manual changes; with `prune: true` it deletes resources that were removed from Git.

## GitOps workflow

```
 Developer                 GitHub                        Kubernetes cluster
 ---------                 ------                        ------------------
 edit YAML
 (e.g. replicas: 3)
     |
     | git push (branch)
     v
 +-----------+   CI checks   +-------------+
 | Pull      | ------------> | Review +    |
 | Request   |  (lint, kube- | approve     |
 +-----------+   conform)    +------+------+
                                    | merge
                                    v
                             +-------------+   poll / webhook   +-------------+
                             | main branch | -----------------> |  Argo CD    |
                             | (desired    |                    |  (in-cluster|
                             |  state)     | <----------------- |   agent)    |
                             +-------------+   git pull         +------+------+
                                                                       | sync (apply diff)
                                                                       v
                                                              +-----------------+
                                                              | Deployments,    |
                                                              | Services, ...   |
                                                              | (live state)    |
                                                              +--------+--------+
                                                                       |
                                    status: Synced / OutOfSync,        |
                                    Healthy / Degraded  <--------------+
```

## Kubernetes + GitOps

### Argo CD vs Flux

Both are **CNCF graduated** projects and both implement the pull model.

| | Argo CD | Flux (v2) |
|---|---|---|
| Architecture | Application controller + repo server + API server + **web UI** | Set of small controllers (GitOps Toolkit): source, kustomize, helm, notification, image automation |
| Main CRD | `Application` (plus `AppProject`, `ApplicationSet`) | `GitRepository` + `Kustomization` / `HelmRelease` |
| UI | Rich built-in web UI with resource tree and diffs | No built-in UI (CLI-first; third-party UIs exist) |
| Multi-cluster | One central Argo CD can manage many clusters | Usually one Flux per cluster (can also target remote clusters) |
| Multi-tenancy / access | Projects, RBAC, SSO built in | Relies on Kubernetes RBAC and namespaces |
| Helm | Renders the chart to manifests and applies them | Uses the Helm SDK (real Helm releases) |
| Image update automation | Separate Argo CD Image Updater | Built in (image-reflector / image-automation controllers) |
| Good fit | Teams that want visibility and a UI, platform teams managing many apps/clusters | Lightweight, composable, fully Git-driven setups |

### Argo CD Application example

An `Application` tells Argo CD **where** the manifests are (repo, revision, path) and **where** to deploy them (cluster, namespace):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitops-demo
  namespace: argocd            # Applications live in the Argo CD namespace
spec:
  project: default
  source:
    repoURL: https://github.com/ankit14-dev/devops-heros.git
    targetRevision: main
    path: session20-monitoring-observability-gitops/homework/gitops/app
  destination:
    server: https://kubernetes.default.svc   # the cluster Argo CD runs in
    namespace: gitops-demo
  syncPolicy:
    automated:
      prune: true              # delete resources removed from Git
      selfHeal: true           # revert manual changes (drift)
    syncOptions:
      - CreateNamespace=true
```

The `Application` is applied once (`kubectl apply -n argocd -f ...`). After that, every commit to `app/` on `main` is deployed automatically.

Useful commands:

```bash
kubectl get applications -n argocd
argocd app get gitops-demo
argocd app diff gitops-demo
argocd app sync gitops-demo
argocd app history gitops-demo
```

## Hands-on demo

<!-- REAL-OUTPUT: argocd demo -->

## What I learned

- In GitOps the deploy step is a merge; the cluster pulls its own changes.
- Self-heal makes manual `kubectl` edits temporary, which pushes everyone to change things through Git.
- Rollback is just `git revert`, and the history doubles as an audit log.
- Argo CD and Flux solve the same problem; Argo CD's UI makes it easier to learn and demo.
