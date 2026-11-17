#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence/audit
# kind extraMounts hostPath must be absolute; generated config is local-only.
python3 - <<'PY2'
from pathlib import Path
import yaml
root = Path.cwd()
config = yaml.safe_load((root / "k8s/kind/cluster-audit.yaml").read_text())
mounts = config["nodes"][0]["extraMounts"]
mounts[0]["hostPath"] = str(root / "k8s/kind/audit-policy.yaml")
mounts[1]["hostPath"] = str(root / "evidence/audit")
Path("/tmp/efrei-kind-audit.yaml").write_text(yaml.safe_dump(config, sort_keys=False))
PY2
kind create cluster --name devops-audit --config /tmp/efrei-kind-audit.yaml
kubectl config use-context kind-devops-audit
