# Lab 1 container image provenance

Source repository: `Valentin-Meltz/EFREI-devops_project-lab-1`

Source commit on `main` (merge PR #5): `c1a13166bf8f835fb6633f0ce675db6f69cfbbce`

Configured image (base + all three overlays):

```text
ghcr.io/valentin-meltz/efrei-devops_project-lab-1:c1a13166bf8f835fb6633f0ce675db6f69cfbbce
```

The commit was identified from the Git history supplied for Lab 1. **It has not been confirmed that GHCR contains this tag or that the package is publicly accessible.** The package is located at `https://github.com/Valentin-Meltz/EFREI-devops_project-lab-1/pkgs/container/efrei-devops_project-lab-1`.

Before deployment, verify the tag on the package Versions page or authenticate and run:

```bash
docker manifest inspect ghcr.io/valentin-meltz/efrei-devops_project-lab-1:c1a13166bf8f835fb6633f0ce675db6f69cfbbce
```

If GHCR is private, configure an `imagePullSecret` in each namespace; never commit registry credentials.

The Deployment and Pod template both carry `lab.efrei.io/git-commit` set to the image tag's SHA. The actual GitHub Actions run URL and PR reviewer cannot be derived from the SHA alone; obtain them from the original workflow and PR and add only verified values. A new image for a rolling update must use its own new SHA and matching traceability annotations.
