# EFREI DevOps — Lab 2

**Session 2: Kubernetes, Multi-environment Deployment and Audit**
Continuation of Lab 1: a Fastify API on port 3000 exposing `GET /health` (probes) and `GET /` (release information: version, commit, environment, pod).

- Answers to questions 1–8: [ANSWERS.md](ANSWERS.md)
- Captured outputs for every part: [evidence/README.md](evidence/README.md)

## Architecture

`Pull Request (reviewed) → GitHub Actions → multi-arch GHCR image tagged with the commit SHA → Kustomize overlay → Deployment → Service → Pods`

| Environment | Namespace | Replicas | APP_ENV | Release |
| --- | --- | ---: | --- | --- |
| Development | `dev` | 3 | `dev` | v1.1.0 (`982483e`, PR #9) |
| Staging | `staging` | 3 | `staging` | v1.0.0 (`ba33ff1`, PR #8) |
| Production | `prod` | 5 | `prod` | v1.0.0 (`ba33ff1`, PR #8) |

```text
k8s/
  base/                 Deployment (probes, resources, ConfigMap/Secret env, release annotations) + Service
  overlays/{dev,staging,prod}/   namespace, env label, replicas, APP_ENV, pinned image tag
  rbac/                 viewer ServiceAccount, read-only pod-reader Role, RoleBinding (dev)
  experiments/          disposable drills: broken probes, in-cluster traffic generator
  kind/                 audit policy and kind config for the API server audit bonus
scripts/
  create_pull_secret.sh       ghcr-pull imagePullSecret from a token file (never printed)
  evidence/0N-*.sh            one script per lab part, writes evidence/0N-*/
  validate_manifests.py       renders the overlays and checks invariants (also run in CI)
  create_audit_cluster.sh     kind cluster with API server auditing (bonus)
```

The Service listens on port 80 and targets the container port 3000. Rolling updates use `maxSurge: 1` and `maxUnavailable: 0`; a 5 s `preStop` sleep lets a terminating pod finish serving while it leaves the Service endpoints.

## Images and traceability

Images are built and pushed by the `publish` job of `.github/workflows/ci.yml` on every merge to `main`, for `linux/amd64` and `linux/arm64` (the kind node of this lab is arm64), tagged with the full commit SHA:

| Release | Commit (= image tag) | Pull request | CI run |
| --- | --- | --- | --- |
| v1.0.0 | `ba33ff148f57ad68f209a683faeb358a1389c4df` | [#8](https://github.com/Valentin-Meltz/EFREI-devops_project-lab-1/pull/8) | [44285404917](https://github.com/Valentin-Meltz/EFREI-devops_project-lab-1/actions/runs/44285404917) |
| v1.1.0 | `982483e48711ca36531464c164ad73718640ee22` | [#9](https://github.com/Valentin-Meltz/EFREI-devops_project-lab-1/pull/9) | [44314886057](https://github.com/Valentin-Meltz/EFREI-devops_project-lab-1/actions/runs/44314886057) |

The Deployment carries the release annotations declaratively (`k8s/base/deployment.yaml`, overridden by the dev overlay for v1.1.0): `kubernetes.io/change-cause`, `lab.efrei.io/release`, `git-commit`, `pull-request`, `pipeline-run`, `owner` and `ticket` (change ticket: [issue #7](https://github.com/Valentin-Meltz/EFREI-devops_project-lab-1/issues/7)). `scripts/validate_manifests.py` fails if the `git-commit` annotation does not match the image tag. They are not added with `kubectl annotate`, which would create drift (see Q8).

## Prerequisites

Docker, `kind`, `kubectl` (with its bundled Kustomize), `jq`, `gh` (for part 6) and Python 3 with PyYAML (for the validator and the audit cluster helper).

The GHCR package is **private**. Create a classic GitHub token with only the `read:packages` scope (GHCR does not accept fine-grained tokens), save it outside the repository, then create the pull secret in each namespace:

```bash
# copy the token to the clipboard first; it is never displayed
mkdir -p ~/.config && pbpaste > ~/.config/ghcr-pull-token && chmod 600 ~/.config/ghcr-pull-token
scripts/create_pull_secret.sh            # creates/updates ghcr-pull in dev, staging and prod
```

The Deployment only references the secret by name (`imagePullSecrets: ghcr-pull`); no credential is ever written in a manifest.

## Running the lab

Each part has a script that runs the real commands, prints them with their output and saves the same output under `evidence/`. They refuse to run if the current context is not `kind-devops-lab`.

### 1. Cluster and namespaces

```bash
kind create cluster --name devops-lab
kubectl create namespace dev && kubectl create namespace staging && kubectl create namespace prod
scripts/create_pull_secret.sh
scripts/evidence/01-cluster.sh
```

### 2. First deployment — `scripts/evidence/02-first-deployment.sh`

Creates `myapp-config` and the fake `myapp-secret` in `dev`, applies the base (`kubectl apply -f k8s/base/deployment.yaml -f k8s/base/service.yaml -n dev`; `kustomization.yaml` is not a cluster object), reaches the app with `kubectl port-forward svc/myapp 8080:80`, deletes a pod and watches the ReplicaSet replace it, scales to 5 then back to 3.

### 3. Probes, resources and configuration — `scripts/evidence/03-probes-config.sh`

Shows the probes, requests/limits and environment injection, proves the Secret is only base64-encoded, then deploys `k8s/experiments/broken-probe` (a one-replica copy of the app whose probes call `/broken`) next to the real app, observes it with `kubectl describe`, and deletes it. The real `myapp` is never modified.

### 4. Multi-environment with Kustomize — `scripts/evidence/04-kustomize.sh`

Removes the part 2 objects from `dev`, creates the fake Secret in `staging`/`prod`, previews and diffs the rendered overlays, applies the three overlays and records `kubectl get all` in each namespace.

```bash
kubectl kustomize k8s/overlays/prod
kubectl apply -k k8s/overlays/dev && kubectl apply -k k8s/overlays/staging && kubectl apply -k k8s/overlays/prod
kubectl get deploy -A -l app=myapp -L env
```

### 5. Rolling update and rollback — `scripts/evidence/05-rollout.sh`

Requires dev on v1.0.0 (end of part 4) and the dev overlay pinned to v1.1.0. Starts `k8s/experiments/traffic-generator.yaml` (a pod calling `http://myapp/` every 0.2 s), shows `kubectl diff -k`, applies the overlay and waits for the old pods to be gone. Then it deploys a non-existent tag with `kubectl set image`, shows the stalled rollout, runs `kubectl rollout undo`, prints the revision history, checks that `kubectl diff -k` is empty again, and counts the HTTP results of the whole run.

### 6. Audit and traceability — `scripts/evidence/06-traceability.sh`

Run it right after part 5 (events expire after one hour). Prints the prod release annotations, walks from a prod pod back to its image digest, commit, PR, reviewer and CI run, reconstructs the dev history from events, `describe` and ReplicaSets, applies `k8s/rbac` and tests the viewer account with `kubectl auth can-i` and real requests.

### 6.4 Bonus: API server audit — `scripts/evidence/07-api-audit.sh`

See [docs/audit-guide.md](docs/audit-guide.md).

## Automated checks

The `validate-manifests` CI job (and `python3 scripts/validate_manifests.py` locally) renders the three overlays and RBAC and checks namespaces, replicas, selectors, ports, probes, resources, ConfigMap/Secret/pull secret references, and that each overlay's release annotations match its image tag. Static validation only: it does not prove that the image exists or that the deployment works; the scripts above do.

## Cleanup

```bash
kind delete cluster --name devops-audit     # bonus cluster
kind delete cluster --name devops-lab
rm ~/.config/ghcr-pull-token                # then revoke the token on github.com/settings/tokens
```
