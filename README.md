# EFREI DevOps — Lab 2

**Session 2: Kubernetes, Multi-environment Deployment and Audit**  
Continuation of [Lab 1](https://github.com/Valentin-Meltz/EFREI-devops_project-lab-1), a Fastify API exposing `GET /health` on port 3000.

## Architecture

`Git commit → GitHub Actions → GHCR image → Kustomize overlays → Kubernetes Deployment → Service → Pods`

| Environment | Namespace | Replicas | APP_ENV |
| --- | --- | ---: | --- |
| Development | `dev` | 3 | `dev` |
| Staging | `staging` | 3 | `staging` |
| Production | `prod` | 5 | `prod` |

All three environments share the same base Deployment and Service. `myapp` exposes port 80 and forwards traffic to the application's port 3000. Readiness and liveness probes check `/health`. CPU/memory requests and limits are configured. Rolling updates use `maxSurge: 1`, `maxUnavailable: 0`.

## Prerequisites

Docker, `kind`, `kubectl` with integrated Kustomize, access to the published Lab 1 GHCR image. If GHCR is private, configure `imagePullSecrets` separately and do not commit credentials.

**Image reference:** `ghcr.io/valentin-meltz/efrei-devops_project-lab-1:c1a13166bf8f835fb6633f0ce675db6f69cfbbce` (Lab 1 `main`, merge PR #5). The commit SHA is confirmed from Git history; **publication and pull access on GHCR have not been verified**. Confirm the package version and access before deploying. All three overlays pin this same tag; the Deployment and Pod template annotate the same source commit. The pipeline run URL and reviewer must be obtained from the actual Lab 1 GitHub Actions run / pull request, not inferred.

## 1. Cluster and namespaces

```bash
kind create cluster --name devops-lab
kubectl cluster-info
kubectl get nodes
for ns in dev staging prod; do kubectl create namespace "$ns"; done
```

## 2. First deployment (base)

The base Deployment requires `myapp-config` and `myapp-secret` in the target namespace. Create them first (the key is deliberately fake):

```bash
kubectl create configmap myapp-config --from-literal=APP_ENV=dev -n dev
kubectl create secret generic myapp-secret --from-literal=API_KEY=changeme -n dev
kubectl apply -f k8s/base/ -n dev
kubectl rollout status deployment/myapp -n dev --timeout=180s
kubectl get all -n dev
kubectl port-forward svc/myapp 8080:80 -n dev
# In another terminal: curl -i http://localhost:8080/health
```

Observe self-healing and scaling:

```bash
kubectl get pods -n dev
kubectl delete pod <POD_NAME> -n dev
kubectl get pods -n dev -w
kubectl scale deployment/myapp --replicas=5 -n dev
kubectl get deployment myapp -n dev
kubectl scale deployment/myapp --replicas=3 -n dev
```

## 3. Probes, resources and configuration

The base manifest includes readiness/liveness probes, CPU/memory resources, `APP_ENV` from a ConfigMap and `API_KEY` from a Secret. To observe a failed probe, temporarily change `/health` to `/broken` in a disposable deployment, apply it, then inspect `kubectl describe pod ... -n dev` and restore `/health`. Never leave the broken probe committed.

## 4. Kustomize environments

**Important:** do not mix the initial `kubectl apply -f k8s/base/` workflow with overlays without cleaning up: Kustomize-generated ConfigMap names have hashes and should be managed consistently. For the final environment deployment, remove the initial `dev` Deployment and Service first (do not delete the namespace), then deploy overlays.

```bash
kubectl delete -f k8s/base/ -n dev --ignore-not-found
kubectl kustomize k8s/overlays/prod
```

Create the fake Secret in each namespace **before applying the overlays** (the ConfigMaps are generated automatically):

```bash
for ns in dev staging prod; do
  kubectl create secret generic myapp-secret --from-literal=API_KEY=changeme -n "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl apply -k k8s/overlays/dev
kubectl apply -k k8s/overlays/staging
kubectl apply -k k8s/overlays/prod
for ns in dev staging prod; do
  kubectl rollout status deployment/myapp -n "$ns" --timeout=180s
  kubectl get all -n "$ns"
done
kubectl get deploy -A -l app=myapp
```

The generated ConfigMaps are environment-specific. The demo Secret is created outside Git, avoiding real credentials in manifests. In a real environment, use a secret manager.

## 5. Rolling update and rollback

For a genuine successful rolling update, first publish a **new working Lab 1 image** with a changed application response and tests. Record the original SHA and the new SHA. Update `newTag` in `k8s/overlays/dev/kustomization.yaml` to the new SHA and apply:

```bash
kubectl apply -k k8s/overlays/dev
kubectl rollout status deployment/myapp -n dev --timeout=180s
kubectl rollout history deployment/myapp -n dev
```

To demonstrate a failed image pull, set the dev overlay's `newTag` to `intentionally-missing-image-tag`, apply it and inspect the rollout. The rollout should stall; do not assume `kubectl rollout status` will finish successfully:

```bash
kubectl apply -k k8s/overlays/dev
kubectl get pods -n dev
kubectl describe deployment/myapp -n dev
kubectl rollout status deployment/myapp -n dev --timeout=60s
kubectl rollout undo deployment/myapp -n dev
kubectl rollout status deployment/myapp -n dev --timeout=180s
kubectl rollout history deployment/myapp -n dev
```

**After the demo**, restore the valid `newTag` in Git and re-apply the overlay so the declarative state matches the cluster. Record the output and images used for the evidence.

## 6. RBAC and audit traceability

```bash
kubectl apply -k k8s/rbac
kubectl auth can-i list pods -n dev --as=system:serviceaccount:dev:viewer
kubectl auth can-i delete pods -n dev --as=system:serviceaccount:dev:viewer
kubectl annotate deployment myapp -n prod \
  git-commit="c1a13166bf8f835fb6633f0ce675db6f69cfbbce" \
  pipeline-run="<REAL_GITHUB_ACTIONS_RUN_URL>" \
  owner="devops-team" ticket="OPS-123" --overwrite
kubectl get events -n prod --sort-by=.metadata.creationTimestamp
kubectl describe deployment myapp -n prod
```

Expected RBAC decisions for the viewer account are `yes` for listing pods and `no` for deleting pods, subject to the cluster's actual authorization policy. The audit annotations are examples and **must** be replaced with real references before claiming traceability.

### Optional API server audit bonus

See [docs/audit-guide.md](docs/audit-guide.md) for a dedicated kind cluster configuration and an audit-log inspection procedure.

## Answers and evidence

- [ANSWERS.md](ANSWERS.md): all eight theory answers.
- [docs/deployment-guide.md](docs/deployment-guide.md): evidence collection checklist.
- [evidence/README.md](evidence/README.md): evidence inventory (populate after execution).

No execution results are claimed by this repository unless captured in `evidence/`.

## Automated checks

The `Validate Kubernetes manifests` workflow renders all three overlays and RBAC, checks expected namespaces, replicas, selectors, ports, probes, resource policies and configuration references, then checks Kubernetes resource schemas with kubeconform. Rendered manifests are uploaded as a CI artifact. This is static validation; it does **not** prove image availability or successful deployment.

```bash
python3 -m pip install PyYAML==6.0.2
python3 scripts/validate_manifests.py  # requires kubectl
```

The real image reference must be confirmed from the Lab 1 GHCR package before runtime deployment. The placeholder is deliberately not presented as a working image.
