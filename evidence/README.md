# Evidence inventory

Real outputs captured on 2026-11-18 on the kind cluster `devops-lab` (Kubernetes v1.37.0, one arm64 node) and, for the bonus, on `devops-audit`. Each file was written by the script of the same number in `scripts/evidence/`, which prints every command (`$ …`) followed by its output. Nothing here was edited by hand.

| Part | File | What it shows |
| --- | --- | --- |
| 1 | [01-cluster/cluster-setup.txt](01-cluster/cluster-setup.txt) | kind cluster, Ready node, `dev`/`staging`/`prod` namespaces |
| 2 | [02-first-deployment/first-deployment.txt](02-first-deployment/first-deployment.txt) | base applied in `dev`, `get all`, `/health` → `200 OK` through port-forward, deleted pod replaced by the ReplicaSet, scale 5 → 3 |
| 3 | [03-probes-config/probes-config.txt](03-probes-config/probes-config.txt) | probes and resources, `APP_ENV`/`API_KEY` injection, Secret is base64 only, broken-probe drill: readiness 404 → `ready=false`, liveness 404 → restart |
| 4 | [04-kustomize/kustomize.txt](04-kustomize/kustomize.txt) | rendered prod overlay, dev vs prod diff, **`kubectl get all` in dev, staging and prod**, replicas 3/3/5, per-environment `APP_ENV` |
| 5 | [05-rollout/rollout.txt](05-rollout/rollout.txt) | **rolling update v1.0.0 → v1.1.0, failed rollout (`ImagePullBackOff`), rollback**, revision history, no drift after rollback |
| 5 | [05-rollout/traffic.log](05-rollout/traffic.log) | every request of the in-cluster client during part 5: 370 requests, 370 `HTTP 200` |
| 6 | [06-traceability/traceability.txt](06-traceability/traceability.txt) | release annotations, pod → digest → commit → PR #8 → reviewer → CI run, events, **RBAC manifests applied and `auth can-i` results** |
| 6.4 | [07-api-audit/api-audit.txt](07-api-audit/api-audit.txt) | bonus: audit policy, API server flags, audit entries of the `kubectl apply` |

## Deliverables checklist

- `k8s/` with base and three overlays: [`k8s/`](../k8s)
- `kubectl get all` in each namespace: part 4
- Successful rolling update and rollback: part 5
- RBAC manifests ([`k8s/rbac/`](../k8s/rbac)) and `auth can-i` results: part 6
- Answers to questions 1–8: [`ANSWERS.md`](../ANSWERS.md)

## Notes on the runs

- Part 2 was run three times. The first run's `rollout status` hit its 180 s timeout because the very first image pull on the node took 2 min 53 s; the second run printed a harmless `NotFound` from waiting on a pod that was being deleted. The scripts were fixed (420 s timeout, wait on the Deployment instead) and `dev` was reset before the run kept here.
- Part 5 was run twice: in the first run the drill's `change-cause` annotation was not applied (shell quoting), so the history was misleading. `dev` was reset to the end state of part 4 (fresh v1.0.0 Deployment) and the script was run again. Both runs had zero failed requests.
- Parts 3 and 6 were run twice after fixing how a result was shown: `wget localhost` resolved to IPv6 `::1` while the app listens on IPv4 (now `127.0.0.1`), the EndpointSlice column listed not-ready endpoints too (now the `ready` condition is printed), and `can-i get pods/log` was read by kubectl as a pod named `log` (now `--subresource=log`, answer `no`).
- The only expected error in part 5 is `error: timed out waiting for the condition`, from `rollout status` on the broken tag.
- The `Forbidden` errors in part 6 are the expected RBAC denials for the viewer account.
- Bonus: the raw API server log `evidence/audit/audit.log` is git-ignored (every request of the cluster, with users, source IPs and certificate fingerprints); only the relevant entries are kept in part 7. The first run of script 07 wrote its own output into that raw log instead of `07-api-audit/` (a variable name clash, fixed); those lines were removed from the raw log and the script was run again. Its audit entries are still listed, which is what an audit log is for.
- The fake API key `changeme` appears on purpose. The GHCR pull token never appears in any output.

# Lab 3: Terraform

Real outputs captured on 2026-11-24 with Terraform v1.17.2 and Docker 28.4.0 (Docker Desktop, arm64). Same rule as above: each file is written by the script of the same number in `scripts/evidence/` and was not edited by hand. Applies use `-auto-approve` so the scripts are not interactive.

| Part | File | What it shows |
| --- | --- | --- |
| 1 | [08-terraform-quickstart/quickstart.txt](08-terraform-quickstart/quickstart.txt) | `init`/`fmt`/`validate`/`plan`, apply and `curl :8081` → `200 OK`, port 8081 → 8082 plan (**`-/+` must be replaced, `# forces replacement`**), `show` and `state list`, **container deleted with `docker rm -f` → plan proposes to create it again** (`-detailed-exitcode` 2), re-apply → exit code 0, what the state holds and `git check-ignore` on it (Q2) |

- The script starts by destroying any previous run and setting `external` back to 8081, then changes it to 8082 itself (1.3). It leaves `tf-web` running on 8082 and `main.tf` at 8082, the end state of part 1.
