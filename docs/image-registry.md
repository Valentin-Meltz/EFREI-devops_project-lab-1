# Container images (GHCR)

Package: `ghcr.io/valentin-meltz/efrei-devops_project-lab-1` — **private**
(`https://github.com/Valentin-Meltz/EFREI-devops_project-lab-1/pkgs/container/efrei-devops_project-lab-1`).

The `publish` job of `.github/workflows/ci.yml` runs on every push to `main` (that is, on every merged PR). It builds `linux/amd64` and `linux/arm64` with Buildx/QEMU, passes the commit SHA as `GIT_SHA` (returned by `GET /` and set as the `org.opencontainers.image.revision` label), and tags the image with the full commit SHA. Tags are never reused, so a tag identifies exactly one commit.

| Release | Tag (merge commit) | PR / reviewer | CI run | Used by |
| --- | --- | --- | --- | --- |
| v1.0.0 | `ba33ff148f57ad68f209a683faeb358a1389c4df` | #8, approved by Z3rbe | 44285404917 | base, staging, prod |
| v1.1.0 | `982483e48711ca36531464c164ad73718640ee22` | #9, approved by Z3rbe | 44314886057 | dev |

Older tags (`c1a1316…`, `109fec2…`, `1e10231…`) are amd64-only and fail on an arm64 node with `no match for platform in manifest`; they are not used.

## Pulling from the cluster

The package is private, so every namespace that runs `myapp` needs the `ghcr-pull` secret (`kubernetes.io/dockerconfigjson`). Use a classic token with the single scope `read:packages` (GHCR does not accept fine-grained tokens), stored outside the repository, and run `scripts/create_pull_secret.sh`. The script builds the docker config with shell builtins and pipes it to `kubectl` on stdin, so the token never appears on a command line or in an output. Manifests only reference the secret by name.

## Releasing a new version

1. Merge a reviewed PR to `main`; wait for the `publish` job.
2. In the target overlay, set `images[].newTag` to the merge commit SHA **and** update the release annotations (`change-cause`, `release`, `git-commit`, `pull-request`, `pipeline-run`) with a patch, as `k8s/overlays/dev` does for v1.1.0.
3. `python3 scripts/validate_manifests.py` fails if `git-commit` does not match the tag.
4. `kubectl diff -k k8s/overlays/<env>`, then `kubectl apply -k k8s/overlays/<env>`.
