#!/usr/bin/env python3
"""Render and check lab manifests without requiring a running Kubernetes cluster."""
import subprocess
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "rendered"
OUT.mkdir(exist_ok=True)
REPOSITORY = "ghcr.io/valentin-meltz/efrei-devops_project-lab-1"
ANNOTATIONS = ("kubernetes.io/change-cause", "lab.efrei.io/owner", "lab.efrei.io/ticket",
               "lab.efrei.io/release", "lab.efrei.io/git-commit",
               "lab.efrei.io/pull-request", "lab.efrei.io/pipeline-run")


def render(name, path):
    result = subprocess.run(["kubectl", "kustomize", str(path)], check=True,
                            text=True, capture_output=True)
    (OUT / f"{name}.yaml").write_text(result.stdout)
    return [obj for obj in yaml.safe_load_all(result.stdout) if obj]


def only(items, kind):
    matches = [obj for obj in items if obj.get("kind") == kind]
    assert len(matches) == 1, f"Expected one {kind}, found {len(matches)}"
    return matches[0]


for env, replicas in (("dev", 3), ("staging", 3), ("prod", 5)):
    items = render(env, ROOT / "k8s" / "overlays" / env)
    deploy, svc, config = (only(items, kind) for kind in
                           ("Deployment", "Service", "ConfigMap"))
    assert all(obj["metadata"].get("namespace") == env for obj in items)
    assert deploy["spec"]["replicas"] == replicas
    assert deploy["spec"]["selector"]["matchLabels"] == {"app": "myapp"}
    assert deploy["spec"]["template"]["metadata"]["labels"]["app"] == "myapp"
    assert deploy["metadata"]["labels"]["env"] == env
    assert config["data"]["APP_ENV"] == env
    assert svc["spec"]["selector"] == {"app": "myapp"}
    assert svc["spec"]["ports"][0]["port"] == 80
    assert svc["spec"]["ports"][0]["targetPort"] == "http"
    container = deploy["spec"]["template"]["spec"]["containers"][0]
    assert container["ports"][0]["containerPort"] == 3000
    # The image is pinned to a full commit SHA and the traceability annotations
    # describe that same commit (they must be updated together with the tag).
    repository, tag = container["image"].rsplit(":", 1)
    assert repository == REPOSITORY and len(tag) == 40, container["image"]
    annotations = deploy["metadata"]["annotations"]
    assert all(annotations.get(key) for key in ANNOTATIONS), annotations
    assert annotations["lab.efrei.io/git-commit"] == tag
    assert tag[:7] in annotations["kubernetes.io/change-cause"]
    template_annotations = deploy["spec"]["template"]["metadata"]["annotations"]
    assert template_annotations["lab.efrei.io/git-commit"] == tag
    assert template_annotations["lab.efrei.io/release"] == annotations["lab.efrei.io/release"]
    assert deploy["spec"]["template"]["spec"]["imagePullSecrets"] == [{"name": "ghcr-pull"}]
    for probe in ("readinessProbe", "livenessProbe"):
        assert container[probe]["httpGet"] == {"path": "/health", "port": "http"}
    assert container["resources"]["requests"] and container["resources"]["limits"]
    envvars = {item["name"]: item["valueFrom"] for item in container["env"]}
    assert envvars["APP_ENV"]["configMapKeyRef"]["name"] == config["metadata"]["name"]
    assert envvars["API_KEY"]["secretKeyRef"] == {"name": "myapp-secret", "key": "API_KEY"}
    assert deploy["spec"]["strategy"]["rollingUpdate"]["maxUnavailable"] == 0
    print(f"OK {env}: {replicas} replicas, {annotations['lab.efrei.io/release']} ({tag[:7]}), "
          "probes, config, Secret and pull secret references")

rbac = render("rbac", ROOT / "k8s" / "rbac")
assert {o["kind"] for o in rbac} == {"Role", "RoleBinding", "ServiceAccount"}
role = only(rbac, "Role")
assert role["rules"] == [{"apiGroups": [""], "resources": ["pods"], "verbs": ["get", "list", "watch"]}]
assert all(o["metadata"].get("namespace") == "dev" for o in rbac)
print("OK RBAC: read-only pod access in dev")
print("NOTE: image tag/package existence and runtime deployment are not verified by this check")
