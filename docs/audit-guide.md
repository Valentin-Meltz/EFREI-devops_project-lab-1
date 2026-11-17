# Optional bonus — API server audit with kind

The helper script resolves host mount paths to absolute paths before kind starts. The kind config in `k8s/kind/cluster-audit.yaml` mounts an audit policy and host directory into the control-plane container and configures kube-apiserver audit flags.

**Run from the repository root.** Prepare the host directory before creating the cluster:

```bash
mkdir -p evidence/audit
# Use a distinct cluster name; delete an existing cluster only if you intend to recreate it.
bash scripts/create_audit_cluster.sh
kubectl config use-context kind-devops-audit
kubectl create namespace dev
kubectl apply -k k8s/overlays/dev
kubectl get events -n dev --sort-by=.metadata.creationTimestamp
```

The helper requires `python3`, `PyYAML` (`python3 -m pip install PyYAML==6.0.2`), Docker and kind. It creates a separate cluster and must be run from a checkout where the audit policy is present. The audit cluster also needs the fake `myapp-secret` in `dev` for the application to start; create it as described in the README. To locate a matching audit record:

```bash
# The host path evidence/audit receives the audit log from the API server.
grep '"verb":"patch"' evidence/audit/audit.log | tail -n 10
```

The exact verb can be `create` or `patch` depending on whether the object existed. For structured inspection, use `jq` and filter `objectRef.namespace`, `objectRef.resource`, `user.username`, `requestURI` and `stage`. Avoid committing logs containing sensitive user or request metadata. This configuration is intended for a local teaching cluster, not a production audit deployment.
