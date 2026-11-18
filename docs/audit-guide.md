# Bonus — API server audit with kind (part 6.4)

Auditing is a kube-apiserver flag, so it needs a cluster created with it: `scripts/create_audit_cluster.sh` creates a second kind cluster, `devops-audit`, from `k8s/kind/cluster-audit.yaml`. That config mounts the policy `k8s/kind/audit-policy.yaml` and the host directory `evidence/audit/` into the control-plane node and sets `--audit-policy-file`, `--audit-log-path` and rotation flags. kind needs absolute host paths, so the script rewrites them into a temporary config (requires Python 3 with PyYAML).

The policy logs at `Metadata` level (who, what, when, result; no request or response body) the `create`, `update`, `patch` and `delete` calls on pods, services, configmaps and deployments, and nothing else. Secrets are deliberately not logged.

```bash
scripts/create_audit_cluster.sh                       # switches the context to kind-devops-audit
kubectl config use-context kind-devops-lab            # the evidence scripts expect this context
kubectl --context kind-devops-audit create namespace dev
KUBE_CONTEXT=kind-devops-audit scripts/create_pull_secret.sh dev
scripts/evidence/07-api-audit.sh
```

The script applies the dev overlay to `devops-audit`, then filters `evidence/audit/audit.log` with `jq` for `ResponseComplete` events in `dev` sent by `kubectl`. On a first apply, client-side `kubectl apply` sends `create` (HTTP 201); on later applies with changes it sends `patch`. The `requestURI` contains `fieldManager=kubectl-client-side-apply`, and the `authorization.k8s.io/reason` annotation says which RBAC binding allowed the call.

The raw log is git-ignored: it contains every request of the cluster, with user names, source IPs and certificate fingerprints. This setup is for a local teaching cluster; a production audit pipeline would ship the events to a tamper-resistant store (webhook backend, SIEM) with retention rules.
