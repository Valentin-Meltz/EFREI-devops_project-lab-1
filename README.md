# EFREI DevOps – Project Lab 1

Minimal [Fastify](https://fastify.dev) API.

## Requirements

- Node.js >= 20

## Usage

```bash
npm install
npm start          # listens on http://0.0.0.0:3000
npm run dev        # restarts on file changes
npm test           # runs tests with node:test
```

Environment variables: `PORT` (default `3000`), `HOST` (default `0.0.0.0`).

## Endpoints

| Method | Path      | Response       |
|--------|-----------|----------------|
| GET    | `/health` | `200` · `OK`   |

```bash
curl http://localhost:3000/health
# OK
```

# Lab 1 – Answers

### Question 1 — Why forbid direct pushes to `main`?

`main` is the branch that gets published: every push to `main` builds and publishes a Docker image to GHCR. It must always be in a working state. Forbidding direct pushes forces every change to go through a Pull Request, which:

- **Runs the CI before the merge.** The required `build-test` check (lint, tests, Docker build) must pass, so broken code cannot reach `main`.
- **Allows code review.** A teammate reads the change before it is merged, which catches bugs earlier and shares knowledge across the team.
- **Keeps a trace of every change.** Each change on `main` is linked to a PR with its discussion, CI results and approval. This makes it easy to understand, audit or revert later.
- **Protects the shared history.** No one can accidentally `git push --force` and rewrite or lose commits on `main`.

### Question 2 — What is the difference between an image and a container?

- An **image** is a read-only, immutable template. It is a stack of filesystem layers (base OS, Node.js, `node_modules`, our `src/`) plus metadata (user, exposed port, start command). It is built once with `docker build`, can be pushed to and pulled from a registry, and does not run by itself. Example: `myapp:0.1`.
- A **container** is a running (or stopped) instance of an image. Docker adds a thin writable layer on top of the image's layers, then starts an isolated process with its own network and filesystem. It is created with `docker run`. Example: the `myapp` container.

An image is to a container what a program on disk is to a running process, or what a class is to an object. One image can run many containers at the same time. Deleting a container, and anything it wrote, never changes the image.

### Question 3 — Compare the size of your image with a non-slim base image

Same Dockerfile and same app; only the `FROM` line changes. Measured locally with Docker Desktop on arm64:

| Base image | OS | Unpacked size | Compressed (download) |
|---|---|---|---|
| `node:22` (full) | Debian 12 | ~1.2 GB | ~401 MB |
| `node:22-slim` | Debian 12 | ~268 MB | ~82 MB |
| **`node:22-alpine`** (ours) | Alpine 3.24 | **~183 MB** | **~63 MB** |

**Observation:** the full image is about **6.5 times larger** than the Alpine one, although our app (`src/` + `node_modules`, about 15 MB) is identical in all three. Almost all the size comes from the base image. The full `node:22` ships a complete Debian with build tools (`gcc`, `git`, `python3`, `curl`, …) that the app never uses at runtime; none of them exist in the Alpine image. A smaller image:

- is faster to pull and start, which speeds up CI runs, deployments and scaling;
- uses less disk and registry storage;
- has a smaller attack surface: fewer packages means fewer vulnerabilities (CVEs) and no compiler for an attacker to use.

The trade-off is that Alpine uses `musl` instead of `glibc`, which can break some npm packages with native code. `-slim` (Debian with `glibc`) is the middle ground in that case.

### Question 4 — Why tag the image with the commit SHA rather than `latest`?

- **Unique and immutable.** A SHA identifies exactly one version of the code. `latest` is a moving tag, overwritten on every push, so you never know which code it actually contains.
- **Traceability.** From `ghcr.io/valentin-meltz/efrei-devops_project-lab-1:<sha>` you can go straight back to the commit, its Pull Request and the pipeline run that built it (commit → pipeline run → image).
- **Reproducible deployments and easy rollbacks.** Deploying `:<sha>` always runs exactly the same image, and rolling back means redeploying the previous SHA. With `latest`, two servers can run different code under the same tag, especially since Docker does not pull `latest` again if it already has a local copy.

`latest` can still be added as a convenience tag, but deployments should always reference the SHA.

### Question 5 — What does "fail fast" mean in a pipeline?

It means stopping the pipeline at the first failure, and ordering the steps so that the fastest and cheapest checks run first. The developer gets feedback in seconds instead of minutes, and no time or resources are spent on a build that is already known to be broken.

In our `ci.yml`:

1. The `build-test` job runs **Install → Lint (seconds) → Tests → Docker build (slowest)**. If lint fails, the tests and the image build do not run at all.
2. The `publish` job has `needs: build-test`, so an image is **never published** if any check failed.
3. `build-test` is a **required status check** on `main`, so a red pipeline also blocks the Pull Request from being merged.
