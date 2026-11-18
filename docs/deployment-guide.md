# Evidence run order

The scripts in `scripts/evidence/` reproduce the lab end to end. They run against the `kind-devops-lab` context only and overwrite their own file in `evidence/`.

| Order | Command | State before | State after |
| --- | --- | --- | --- |
| 0 | `kind create cluster --name devops-lab`, create the three namespaces, `scripts/create_pull_secret.sh` | — | empty namespaces with `ghcr-pull` |
| 1 | `scripts/evidence/01-cluster.sh` | | |
| 2 | `scripts/evidence/02-first-deployment.sh` | no `myapp` objects in `dev` | base Deployment/Service + hand-made ConfigMap and Secret in `dev` |
| 3 | `scripts/evidence/03-probes-config.sh` | part 2 | unchanged (the broken-probe drill is deleted at the end) |
| 4 | `scripts/evidence/04-kustomize.sh` | part 2 | the three overlays deployed, all on v1.0.0 |
| 5 | point `k8s/overlays/dev` to v1.1.0, then `scripts/evidence/05-rollout.sh` | dev on v1.0.0 | dev on v1.1.0, revisions 1, 3 (drill), 4 |
| 6 | `scripts/evidence/06-traceability.sh` (within the hour, for events) | part 5 | + `viewer` ServiceAccount, Role and RoleBinding |
| 7 | `scripts/evidence/07-api-audit.sh` | audit cluster from `scripts/create_audit_cluster.sh` with `ghcr-pull` in `dev` | dev overlay deployed on `devops-audit` |

## Re-running a part

- **Part 2**: `kubectl delete -f k8s/base/deployment.yaml -f k8s/base/service.yaml -n dev`, then delete `configmap/myapp-config` and `secret/myapp-secret` in `dev`.
- **Part 5**: dev must be back at the end state of part 4. Delete `deployment/myapp` in `dev` and apply the dev overlay with the v1.0.0 tag and without the release patch (identical to the staging overlay with `dev` values), then run the script with the overlay pointing to v1.1.0 again.
- **Part 7**: delete `deployment/myapp`, `service/myapp`, the `env=dev` ConfigMap and `secret/myapp-secret` in `dev` on `devops-audit`, so `kubectl apply` creates them again.
