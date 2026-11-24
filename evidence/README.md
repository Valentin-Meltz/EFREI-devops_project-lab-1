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

Real outputs captured on 2026-11-24 with Terraform v1.17.2 and Docker 28.4.0 (Docker Desktop, arm64). Same rule as above: each file is written by the script of the same number in `scripts/evidence/` and was not edited by hand. Applies use `-auto-approve` and the state migration uses `-force-copy`, so the scripts are not interactive.

| Part | File | What it shows |
| --- | --- | --- |
| 1 | [08-terraform-quickstart/quickstart.txt](08-terraform-quickstart/quickstart.txt) | `init`/`fmt`/`validate`/`plan`, apply and `curl :8081` → `200 OK`, port 8081 → 8082 plan (**`-/+` must be replaced, `# forces replacement`**), `show` and `state list`, **container deleted with `docker rm -f` → plan proposes to create it again** (`-detailed-exitcode` 2), re-apply → exit code 0, what the state holds and `git check-ignore` on it (Q2) |
| 2 | [09-terraform-modules/modules.txt](09-terraform-modules/modules.txt) | `webapp` module code, quickstart destroyed, **dev and staging applied separately** (`-chdir` + `-var-file`), **`webapp-dev` :8083 and `webapp-staging` :8084 side by side**, both `200 OK`, outputs, one state per folder with the same addresses, dev plan unchanged after the staging apply (exit code 0), variable validation errors (Q3) |
| 3 | [10-terraform-state/state.txt](10-terraform-state/state.txt) | `.gitignore` checked with `git check-ignore` (state, plans, `.terraform/`, `*.secret.tfvars` and auto-loaded tfvars ignored; `dev.tfvars` and lock files kept), committed lock files, **dev state migrated to the shared folder** (`init -migrate-state`), `state list`/`state show`, **drift: `webapp-dev` recreated by hand on 8085 → `plan -refresh-only` and `plan` report `has been deleted`** (exit code 2), apply blocked by the name conflict, back to 8083 (exit code 0), **state lock: second plan gets `Error acquiring the state lock`** (Q4), state file permissions and content (Q5) |
| 4 | [11-terraform-preview/preview.txt](11-terraform-preview/preview.txt) | preview code (Service, pull secret, `owner`/`expires` labels), **PR 42 (v1.1.0) and PR 43 (v1.0.0) in `pr-42` and `pr-43`, one state file each** (`init -reconfigure -backend-config=path=state/pr-<n>.tfstate`), `kubectl get all`, `GET /` from each preview through port-forward, init refusing to switch PR without `-reconfigure`, GHCR token absent from both states (write-only), **PR 42 destroyed: namespace `NotFound`, PR 43 still serving**, expired-preview query (Q6) |
| 5 | [12-terraform-ci/ci.txt](12-terraform-ci/ci.txt) | `terraform` workflow (read-only token, actions pinned to SHAs, **no `terraform apply`**), Checkov policy, **3 runs on PR #12: pass, fail on the deliberate misconfiguration (`CKV_K8S_16` privileged, `CKV_K8S_20` privilege escalation), pass after the revert**, uploaded plan artifacts and the downloaded dev plan, checks on the head of the PR (Q7, Q8) |

- Script 08 starts by destroying any previous run and setting `external` back to 8081, then changes it to 8082 itself (1.3), and leaves `main.tf` at 8082, the end state of part 1. Script 09 then destroys `tf-web`: the module replaces it.
- The module sets `keep_locally = true` on its image: dev and staging use the same `nginx:1.27` on the same Docker host, and destroying one environment must not try to delete an image the other still runs.
- Script 10 starts by moving the dev state back into `infra/envs/dev` and emptying the shared folder, so that 3.3 is always a real migration. It leaves the dev state in `/Users/Shared/terraform-state/efrei-devops-lab/dev/` and `webapp-dev` on 8083. The only expected errors are the name conflict of the apply in 3.5 and `Error acquiring the state lock` in the locking demo.
- In script 10 the lock's `Who` field (local user and machine name) is masked with `sed`, and `ls -n` prints numeric owner IDs instead of the local user name. Both commands appear in the log.
- Script 11 runs on the kind cluster `devops-lab` (Kubernetes v1.37.0) and leaves the `pr-43` preview running. It reads the GHCR pull token from `~/.config/ghcr-pull-token` into `TF_VAR_ghcr_token` without printing it. The log contains the token 0 times, raw or base64-encoded (checked after the run), and the state files contain it 0 times (checked in the log). The only expected errors are init refusing to switch PR without `-reconfigure`, and the `NotFound` of the destroyed namespace.
- Script 12 only queries GitHub (`gh`) and Git. The three runs it records were triggered by pushing `5f88cc5` (workflow), `d1f5323` (deliberate misconfiguration, 5.5) and `cab99bd` (its revert, 5.6) to PR #12.
- Part 1 was merged on its own in PR #11. PR #12 brings parts 2 to 5.
