# Lab 2 — Answers (Session 2)

Each answer ends with what was actually observed on the kind cluster; the full outputs are in [`evidence/`](evidence/README.md).

## Q1 — What is the role of a namespace? Does it provide strong security isolation by itself?
A namespace logically groups namespaced Kubernetes resources and scopes resource names, RBAC permissions, quotas, and policies. It is useful for separating `dev`, `staging`, and `prod` within one cluster. It is **not** a strong security boundary by itself: workloads may still share nodes, the kernel, and networking. For stronger separation, apply least-privilege RBAC, NetworkPolicies with a compatible CNI, Pod Security Admission, resource quotas, and separate clusters for sensitive trust boundaries.

**Observed:** the three environments run side by side on the same single node (`devops-lab-control-plane`), each with its own `myapp` Deployment, Service and ConfigMap ([04](evidence/04-kustomize/kustomize.txt)). The `viewer` account bound in `dev` gets `no` for `list pods -n prod`: RBAC, not the namespace itself, is what enforces the separation ([06](evidence/06-traceability/traceability.txt)).

## Q2 — Why does Kubernetes recreate the deleted pod? Which component is responsible?
The Deployment specifies a desired replica count. Its ReplicaSet continuously compares desired and actual pods. When a pod is deleted, the **ReplicaSet controller** (in kube-controller-manager) creates a replacement to restore the desired count; the scheduler assigns it to a node and the kubelet starts its containers. The Deployment controller manages ReplicaSets and rollouts, rather than directly recreating each pod.

**Observed:** right after `kubectl delete pod`, the replacement pod is already `ContainerCreating` (age `0s`) while the deleted one is still `Terminating`, and the event `SuccessfulCreate … replicaset/myapp-6c88f95f57 Created pod` is emitted by the ReplicaSet ([02](evidence/02-first-deployment/first-deployment.txt)).

## Q3 — Readiness versus liveness; what happens to traffic when readiness fails?
A **readiness probe** determines whether a pod should receive traffic. If it fails, Kubernetes marks the pod unready and removes it from the Service's ready endpoints (after endpoint propagation); the container is not restarted. A **liveness probe** determines whether the container should be restarted when it is unhealthy. A failed liveness probe eventually causes kubelet to restart the container, according to probe thresholds and restart policy. Both use `/health` in this lab, but production applications may need separate checks.

**Observed** with both probes pointed at `/broken` ([03](evidence/03-probes-config/probes-config.txt)): `Readiness probe failed: HTTP probe failed with statuscode: 404` keeps the pod `0/1`; its EndpointSlice lists it with `ready=false` and a request to its Service is refused. After 3 liveness failures the kubelet logs `Container myapp failed liveness probe, will be restarted` and `RESTARTS` goes to 1. The real app's three endpoints stay `ready=true`.

## Q4 — Is a Kubernetes Secret encrypted by default? How would you improve this?
A Secret's `data` field is base64-encoded, **not encrypted**. Kubernetes API access is normally protected with TLS, but Secret data in etcd is not encrypted at rest unless encryption at rest is configured. Improve protection using encryption at rest with a KMS provider, restricted RBAC (who can `get secrets`), external secret management (for example a CSI driver or external-secrets integration), rotation, and avoiding plaintext secrets in Git or command history. This lab's fake key is only a demonstration; the real credential of the lab (the GHCR pull token) is created out of band by `scripts/create_pull_secret.sh` and never committed.

**Observed:** `kubectl get secret myapp-secret -o jsonpath='{.data}'` returns `{"API_KEY":"Y2hhbmdlbWU="}`, which `base64 -d` turns back into `changeme` ([03](evidence/03-probes-config/probes-config.txt)). Anyone allowed to read the Secret can read the key; the `viewer` account cannot (`get secrets` → `no`, [06](evidence/06-traceability/traceability.txt)).

## Q5 — How does Kustomize help hybrid/multi-cloud deployments? What differs in real clusters?
A reusable `base` defines the application once; `overlays` specify environment-dependent namespaces, replica counts, labels, image versions and configuration. This reduces duplication and configuration drift across on-premises and cloud deployments, and the difference between two targets is a small, reviewable file. Real clusters may differ in ingress/load-balancer controllers, storage classes, networking/CNI, DNS, IAM/workload identity, secret backends, node architectures, security policies, quotas, and observability. Kustomize provides portable manifests, but does not itself provision or secure cloud infrastructure.

**Observed:** one base renders three environments that differ only in namespace, `env` label, replica count and `APP_ENV` (`diff` of the rendered dev and prod overlays in [04](evidence/04-kustomize/kustomize.txt)), and dev can run a newer release than staging/prod by overriding only the image tag and its annotations. The node architecture difference was met in practice: the Lab 1 image was amd64-only and could not run on the arm64 kind node, so the pipeline now publishes `linux/amd64` + `linux/arm64` (PR #8).

## Q6 — Why did the broken rollout not take down the application?
The Deployment uses RollingUpdate with `maxUnavailable: 0` and `maxSurge: 1`. A new pod with an invalid image cannot become Ready, so the Deployment never scales the healthy old ReplicaSet down to make room for it. The Service keeps routing to the Ready old pods. The rollout stalls (and would report `ProgressDeadlineExceeded` after `progressDeadlineSeconds`); `kubectl rollout undo` restores the previous pod template. This assumes the existing pods and cluster capacity stay healthy; it is not a universal zero-downtime guarantee.

**Observed** ([05](evidence/05-rollout/rollout.txt)), with an in-cluster client calling `GET /` every 0.2 s during the whole run ([traffic log](evidence/05-rollout/traffic.log)):
- rolling update v1.0.0 → v1.1.0: 111 requests, 111 `HTTP 200`, answered by both versions during the transition (57 / 54);
- broken tag `does-not-exist`: the new pod is stuck in `ErrImagePull`/`ImagePullBackOff`, `rollout status` times out, the three v1.1.0 pods stay Ready; after `rollout undo`: 259 requests, 259 `HTTP 200`;
- in total 370 requests and **0 failures**. The `preStop` sleep of 5 s keeps a terminating pod serving while it is removed from the endpoints, which closes the remaining race during scale-down.

## Q7 — From a production pod, how do you find its commit, reviewer and pipeline run?
Inspect the pod's image reference and digest and follow its ownership (pod → ReplicaSet → Deployment). Read the release annotations (commit SHA, pull request, pipeline run, owner, ticket) and check that the commit matches the image tag. Then use GitHub: the commit leads to its Pull Request and review history, and the Actions run for that commit shows the job that published the GHCR image. A reliable chain is **pod → image tag/digest → commit → Pull Request/reviewer → CI run → registry artifact**. Annotations must be populated by the release process; they are not independent proof, so they are cross-checked with the image tag, the commit baked into the image, and GitHub.

**Observed** for pod `myapp-868cbb4c55-2nb65` in `prod` ([06](evidence/06-traceability/traceability.txt)): ReplicaSet `myapp-868cbb4c55` (revision 1) of Deployment `myapp`; image tag `ba33ff1…`, digest `sha256:d80cb6ac…`; the app itself reports `"commit":"ba33ff148f57…"`; that commit is the merge of **PR #8**, authored by Valentin-Meltz, **approved and merged by Z3rbe**; CI run [44285404917](https://github.com/Valentin-Meltz/EFREI-devops_project-lab-1/actions/runs/44285404917) (`build-test` and `publish`: success); change ticket: issue #7.

## Q8 — Why is manual `kubectl edit` in production a traceability risk?
`kubectl edit` changes live cluster state without updating Git, creating configuration drift and bypassing Pull Request review, CI checks and deployment approvals. The change may later be silently overwritten by the next declarative deployment, and the reason and the reviewer are hard to reconstruct (the API server audit log records *who* and *when*, not *why*). Prefer Git-reviewed manifests, automated deployment pipelines, protected environments and audit logging. Emergency changes should be recorded and reconciled back to Git immediately.

**Observed:** the broken-tag drill was an imperative change (`kubectl set image`). It produced revision 3 of the Deployment, which exists nowhere in Git; only the `change-cause` annotation set by hand explains it ([05](evidence/05-rollout/rollout.txt)). `kubectl diff -k k8s/overlays/dev` is the check that detects such drift: it is empty again after the rollback. On the audit cluster, every `kubectl apply` appears with its user, verb, object and `auditID` ([07](evidence/07-api-audit/api-audit.txt)).

# Lab 3 — Answers (Session 3)

Same format as Lab 2: each answer ends with what was actually observed, and the full outputs are in [`evidence/`](evidence/README.md#lab-3-terraform).

## Q1 — What did Terraform propose after the container was deleted by hand? What is this situation called?
Terraform proposed to **create the container again** (`+ docker_container.web will be created`, `Plan: 1 to add, 0 to change, 0 to destroy`) and left the image untouched. Before planning, Terraform refreshes its state: it asks the Docker API about each resource it manages, finds that `tf-web` no longer exists, and compares that reality with the configuration, which still declares it. The plan is the list of actions that brings the real infrastructure back to what the code declares. This situation is called **drift** (configuration or infrastructure drift): the infrastructure was changed outside Terraform, by an out-of-band change, and no longer matches the code and the state. Terraform does not know who made the change or why; the next `apply` simply re-imposes the code. That is why every change must go through the code: otherwise the next apply silently undoes it.

**Observed** ([08](evidence/08-terraform-quickstart/quickstart.txt)): after `docker rm -f tf-web`, `docker ps -a` has no `tf-web`, and `terraform plan` refreshes `docker_container.web` and plans one create with the same port 8082. `plan -detailed-exitcode` returns **2** (changes pending), which is what a scheduled drift check in CI would alert on. After `apply` the container is back (`200 OK` on 8082) and the same check returns **0**. Here the drift appears only as a plain `+ create`, without the "Objects have changed outside of Terraform" note. A normal plan only lists the outside changes that are relevant to it, meaning referenced by another resource or an output, and nothing references the quickstart container. `plan -refresh-only` always lists them. In part 3 the module's `container_name` output references the container, so the normal plan shows `has been deleted` as well ([10](evidence/10-terraform-state/state.txt)).

## Q2 — Why should the state file never be committed to Git?
- **Secrets in clear text.** The state stores every attribute of every resource, as returned by the provider, in plain JSON: generated passwords, private keys, tokens, connection strings. Marking a variable or output `sensitive` only hides it from the CLI output; the value is still written to the state. Git history is permanent and copied into every clone, fork and CI cache, so a leaked secret means rewriting history and rotating the secret.
- **No locking, stale copies.** The state is the only record that maps the code to real resource IDs. Git has no locking: two people applying from two checkouts work on two different states, and the later push overwrites the earlier one or conflicts. With a stale state, Terraform believes resources do not exist (duplicates, name conflicts) or still exist (wrong destroys), and merging JSON state by hand can corrupt it.
- **It is runtime data, not source code.** It changes on every apply, so the history would fill with noise and every apply would need a commit.

The state belongs in a remote backend with encryption at rest, access control, versioning and locking (S3, GCS, Azure Blob, HCP Terraform). What belongs in Git is the code and `.terraform.lock.hcl`, which pins the provider versions and checksums.

**Observed** ([08](evidence/08-terraform-quickstart/quickstart.txt)): the quickstart state holds no secret, but it already records details of the host: the container's hostname, its bridge IP `172.17.0.2`, the gateway, the MAC address and the image digest, along with its `serial` (25 after a few runs of part 1) and `lineage`. `.gitignore` excludes `*.tfstate`, `*.tfstate.*` (the `.backup` file) and `.terraform/`, and `git check-ignore -v` confirms each one. Only `main.tf` and `.terraform.lock.hcl` are committed.

## Q3 — What are the advantages of one folder and one state per environment compared to workspaces?
With workspaces, every environment shares one folder, one configuration and one backend. The active environment is a hidden local setting (`terraform workspace select`), and the code tells environments apart through `terraform.workspace`. With one folder and one state per environment:
- **Explicit target, smaller blast radius.** The environment is in the path of every command (`-chdir=infra/envs/staging`) and of every plan. There is no "current workspace" to forget, so applying a dev change to prod by mistake is much harder, and a broken or locked state only blocks one environment.
- **Separate backends and credentials.** Each folder can have its own backend (bucket, account, key) and its own access rights: a developer can apply dev without being able to read or write the prod state. The workspaces of one configuration share the same backend and the same credentials.
- **Environments can differ when they need to.** Each root can pin a different module version (promote a module change dev → staging → prod), a different provider version, or extra resources such as prod-only monitoring, without `terraform.workspace == "prod" ? … : …` conditionals spread through the code.
- **Reviewable and automatable per environment.** A Pull Request diff shows which environment changes. CI can plan and apply per folder through path filters, and CODEOWNERS or protected environments can require an extra approval for the prod folder only.

The cost is some duplication of the root module, kept small by putting the logic in the shared module: here each root is about 30 lines. Workspaces remain handy for short-lived, identical copies of one configuration.

**Observed** ([09](evidence/09-terraform-modules/modules.txt)): the dev and staging root modules are identical (empty `diff`). They differ only by their folder, their tfvars and their state: each folder has its own `terraform.tfstate` and `.terraform.lock.hcl`. Both states use the same addresses (`module.webapp.docker_container.web`, `module.webapp.docker_image.app`) but point to different containers, `webapp-dev` on 8083 and `webapp-staging` on 8084, which run side by side and both answer `200 OK`. After staging was applied, the dev plan is empty (`-detailed-exitcode` 0): one environment's apply cannot touch the other's resources.

## Q4 — Why is a remote backend with locking essential for a team? Which problems does it prevent?
The state is the only record of what Terraform manages. In a team, every person and the CI pipeline must work from the same, latest state, and never write it at the same time. A remote backend gives one shared copy; locking gives one writer at a time. Together they prevent:
- **Concurrent applies.** Two applies start from the same state, both change the infrastructure, and the last one to write the state wins: the first one's changes are no longer tracked (orphaned or duplicated resources), or the state is corrupted. With a lock, the second operation stops with `Error acquiring the state lock`, or waits with `-lock-timeout`.
- **Stale and divergent copies.** With state on laptops (or in Git), each person plans against their own copy: Terraform tries to recreate what a colleague already created, which ends in name conflicts like the one in 3.5, or it overwrites or destroys their work. With a shared backend everyone plans against the latest state.
- **Lost state.** If a laptop's state file is lost, Terraform loses track of everything and would try to create it all again. Remote backends are durable and usually versioned, so a bad state write can be rolled back.
- **Uncontrolled access.** The state holds secrets (Q5). A backend centralizes encryption at rest, access control and audit logs, instead of copies spread over every machine.

A lock must not be bypassed with `-lock=false`, and `terraform force-unlock` is only for a lock whose holder is known to be dead.

**Observed** ([10](evidence/10-terraform-state/state.txt)): `init -migrate-state -backend-config=shared.backend.hcl` copied the dev state to the shared folder `/Users/Shared/terraform-state/efrei-devops-lab/dev/`, and the backend recorded in `.terraform/` now points there. init left the old local copy in place, and that copy would silently go stale, so it was removed: the shared state is the only one. While a first apply waits at its approval prompt, `.terraform.tfstate.lock.info` appears in the shared folder (lock ID, `OperationTypeApply`, who, when). A second `plan -lock-timeout=3s` fails with `Error acquiring the state lock`, showing the same lock ID. Once the first apply is answered `no` (`Apply cancelled.`), the lock file disappears and the next plan runs (exit code 0). The local backend locks with operating-system file locks, which is fine for one machine but not reliable on every network share. That is one reason teams use a real remote backend with native locking (S3 with a lock file or DynamoDB, GCS, azurerm, HCP Terraform).

## Q5 — What information in a state file can be sensitive?
- **Secrets stored as resource attributes**, in clear text: database passwords, `random_password` results, private keys (`tls_private_key`), access keys and tokens, client certificates and kubeconfig credentials, connection strings, and the environment variables of a container. Marking a variable or output `sensitive` only hides it from the CLI output: the value is still written to the state.
- **Secrets read by data sources**, such as a secret-manager value read at plan time: the result is persisted in the state.
- **Output values**, including those marked `sensitive`.
- **A map of the infrastructure**: resource IDs, account IDs and ARNs, internal IP addresses, hostnames, network layout, firewall rules and image digests. That is valuable for reconnaissance even without a password.
- **Metadata about the operators**: the lock records which user on which machine is running Terraform.

Anyone who can read the backend can read all of this. That is why access to the backend is restricted, encrypted at rest and audited, and why state and saved plans (which hold the same values) never go to Git or into CI logs. Recent Terraform versions can also keep some secrets out of the state entirely, with ephemeral resources and write-only arguments.

**Observed** ([10](evidence/10-terraform-state/state.txt)): the dev state holds no password, but `state show` prints all 72 attributes of the container: command, entrypoint, environment variables, hostname, the bridge IP `172.17.0.2`, ports and image. If the Lab 2 `API_KEY` were passed to this container as an environment variable, it would sit in clear text in `env`. In the shared folder the state file is `-rw-r--r--`, readable by every account on this Mac, so whoever can read the backend reads everything. The lock info names the local user and machine (`Who`), which is why that field is masked in the evidence.

Part 4 keeps a real secret out of the state. The GHCR pull token reaches Terraform through an ephemeral variable (`TF_VAR_ghcr_token`) and goes to Kubernetes through the write-only argument `data_wo`. In both preview states the secret has `data: null`, and the token appears 0 times, raw or base64-encoded ([11](evidence/11-terraform-preview/preview.txt)).

## Q6 — What could go wrong if the preview environment is never destroyed? List three mitigations.
A forgotten preview keeps running, and nobody looks at it any more:
- **Cost and capacity.** Each preview reserves CPU and memory, and in the cloud often a load balancer, public IPs and volumes too. Dozens of abandoned PRs fill the shared cluster: new previews stay `Pending`, the autoscaler adds nodes, and the bill grows silently.
- **Security.** The preview runs old code that is never patched, sometimes with debug settings or test data, and sometimes behind a public URL. It also keeps credentials alive: here every preview namespace holds a copy of the GHCR pull token in its `ghcr-pull` Secret. Every forgotten preview adds to the attack surface.
- **Confusion and drift.** Stale environments trigger alerts and mislead people about what is deployed. Quotas and names run out. If the per-PR state file is lost, nobody can destroy the preview cleanly or say who owns it.
- **Data and compliance.** A preview filled with a copy of real data keeps personal data longer than allowed.

Mitigations:
1. **Destroy on PR close.** A workflow triggered by `pull_request` with `types: [closed]` runs `terraform destroy` with that PR's state and then deletes the state. Merged and abandoned PRs both clean up after themselves.
2. **A TTL with a scheduled cleanup job.** Every preview gets `owner` and `expires` labels at creation. A scheduled job (a cron workflow or a Kubernetes CronJob) lists the namespaces labelled `purpose=preview` whose `expires` date has passed, destroys them, and notifies the owner. Extending a preview is an explicit action.
3. **Caps per preview and in total.** Small requests and limits plus one replica per preview, a `ResourceQuota`/`LimitRange` in each preview namespace, and a limit on the number of concurrent previews. Scaling idle previews to zero helps too.
4. **Cost visibility.** The `purpose`, `pr` and `owner` labels feed cost-allocation reports and budget alerts, so a forgotten preview is noticed and has someone to blame.

**Observed** ([11](evidence/11-terraform-preview/preview.txt)):
- PR 42 (release v1.1.0) and PR 43 (release v1.0.0) run side by side in `pr-42` and `pr-43`. Each has its own state file (`state/pr-42.tfstate`, `state/pr-43.tfstate`) and the same resource names. Each answers with its own version and `"environment":"pr-4x"`.
- Switching PRs without `-reconfigure` is refused (`Backend configuration changed`), so one PR's state cannot be migrated into another's by mistake.
- `terraform destroy` for PR 42 removes the namespace and everything in it: `namespaces "pr-42" not found`, `No resources found in pr-42 namespace`, and its state holds 0 resources. PR 43 keeps running and answering.
- The namespaces carry `owner=Valentin-Meltz` and `expires=2026-11-27` (creation date + 3 days, unchanged by later plans). The cleanup query finds no expired preview today; with a simulated date of 2026-12-31 it lists `pr-43 owner=Valentin-Meltz expired=2026-11-27`.
- Each preview requests 50m CPU and 64Mi of memory, with 1 replica.

## Q7 — Why run `plan` on a Pull Request but `apply` only after merge?
`plan` is read-only: it changes nothing, so it can run on every Pull Request, including unreviewed code. It shows reviewers the real impact of the change on the infrastructure, next to the code diff, and catches errors before anything is touched. `apply` changes real infrastructure, so it must only run on code that has been reviewed, approved and merged into the branch that describes production. Applying from Pull Requests instead would mean:
- **Unreviewed changes in production**, and changes left applied by a Pull Request that is later closed without merging.
- **Several open Pull Requests applying in turn.** Each one overwrites the others, the infrastructure flips back and forth, and it no longer matches `main` or any single branch.
- **Write credentials in Pull Request jobs**, which may run code from a fork or a compromised dependency.
- **A stale plan.** A plan computed on a branch can be outdated by the time of the merge (other merges, drift). After the merge, plan again from `main`, ideally apply exactly that saved plan, and gate the job with a protected environment that requires approval.

**Observed** ([12](evidence/12-terraform-ci/ci.txt)):
- The workflow runs only on `pull_request` (paths `infra/**`), with a read-only token (`permissions: contents: read`). Its only Terraform commands are `fmt`, `init`, `validate`, `plan` and `show`, and there is no `terraform apply` in it.
- Each run uploads the text plan of dev and staging as artifacts (`plan-dev`, `plan-staging`, kept 7 days). The CI plans against an empty state (`Plan: 2 to add`), because the real dev state is in a folder on the lab machine.
- The misconfigured commit `d1f5323` was validated, planned and scanned. It failed on Checkov, was never applied, and was reverted before any merge.
- On this repository, `main` requires one approving review but only `build-test` as a required check. To make a red Checkov block the merge by itself, the Terraform jobs should become required checks too. That also means running the workflow on every Pull Request: a path-filtered workflow produces no check at all on a Pull Request that does not touch `infra/**`, and a required check would then wait forever.

## Q8 — Why should a CI pipeline use short-lived credentials (OIDC) rather than long-lived access keys?
A long-lived access key stored as a CI secret stays valid for months, until someone rotates it by hand. Any leak (a log line, a compromised action or dependency, a malicious Pull Request, a copied secret) gives an attacker working credentials, usable from anywhere until the leak is noticed. Such a key is often shared by several workflows and rarely rotated, so its blast radius is large and its use is hard to attribute.

With OIDC, the job asks GitHub for a signed identity token (`permissions: id-token: write`), and the cloud provider exchanges it for temporary credentials, for example AWS `AssumeRoleWithWebIdentity`, valid for about an hour:
- **Nothing to store, nothing to rotate.** A stolen token expires on its own, quickly.
- **Scoped trust.** The cloud trust policy checks the token's claims (repository, branch, environment, workflow). Pull Request jobs can get a read-only role for `plan`, and only the `main` deployment job, behind a protected environment, can get the role that runs `apply`.
- **Attribution.** Every use is logged with the identity of the exact repository, ref and run that requested it.

**Observed** ([12](evidence/12-terraform-ci/ci.txt)):
- The Terraform workflow needs no credential at all: it has a read-only `GITHUB_TOKEN` and references no secret.
- The image publishing job of `ci.yml` pushes to GHCR with `secrets.GITHUB_TOKEN`, a token GitHub creates for each job and that expires when the job ends: the short-lived model.
- The GHCR pull token of parts 4 and Lab 2 is the opposite: a classic personal access token, long-lived. It is kept outside the repository, reaches Terraform only through an ephemeral variable, and never lands in a state.
- In March 2026, hijacked `aquasecurity/trivy-action` tags ran credential-stealing code inside CI pipelines for about 12 hours. Long-lived keys exposed to those jobs stay valid until rotated, while job tokens and OIDC credentials expire on their own. That incident is also why this workflow pins every action to a commit SHA.
