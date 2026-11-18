#!/usr/bin/env bash
# Creates (or updates) the `ghcr-pull` imagePullSecret used by the myapp pods.
#
# The GHCR package is private. The token must be a GitHub PAT with the single
# scope read:packages, stored outside the repository:
#   ~/.config/ghcr-pull-token   (chmod 600), or the path in $GHCR_TOKEN_FILE
#
# The token is never printed and never passed as a command-line argument: the
# docker config JSON is built with shell builtins and piped to kubectl on stdin.
#
# Usage: [KUBE_CONTEXT=<context>] scripts/create_pull_secret.sh [namespace ...]
#        (default: current context; namespaces dev staging prod)
set -euo pipefail

TOKEN_FILE="${GHCR_TOKEN_FILE:-$HOME/.config/ghcr-pull-token}"
GHCR_USER="${GHCR_USER:-Valentin-Meltz}"
KUBECTL=(kubectl ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"})
[ -s "$TOKEN_FILE" ] || { echo "Missing token file: $TOKEN_FILE" >&2; exit 1; }

token="$(tr -d '[:space:]' < "$TOKEN_FILE")"
auth="$(printf '%s:%s' "$GHCR_USER" "$token" | base64 | tr -d '\n')"
unset token

namespaces=("$@")
[ ${#namespaces[@]} -gt 0 ] || namespaces=(dev staging prod)

for ns in "${namespaces[@]}"; do
  printf '{"auths":{"ghcr.io":{"auth":"%s"}}}' "$auth" \
    | "${KUBECTL[@]}" create secret generic ghcr-pull -n "$ns" \
        --type=kubernetes.io/dockerconfigjson \
        --from-file=.dockerconfigjson=/dev/stdin \
        --dry-run=client -o yaml \
    | "${KUBECTL[@]}" apply -f -
done
