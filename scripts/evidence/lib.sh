#!/usr/bin/env bash
# Shared helpers for the evidence scripts.
# Each script runs real kubectl commands, prints them with their output so a
# screenshot can be taken, and appends the same output to a text log in evidence/.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Refuse to run against another cluster (kind create cluster switches the context).
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-kind-devops-lab}"
if [ "$(kubectl config current-context 2>/dev/null)" != "$EXPECTED_CONTEXT" ]; then
  echo "Current kubectl context is not $EXPECTED_CONTEXT; run: kubectl config use-context $EXPECTED_CONTEXT" >&2
  exit 1
fi

# Usage: start_log <relative/path/to/log.txt> "<title>"
start_log() {
  LOG="$ROOT/$1"
  mkdir -p "$(dirname "$LOG")"
  {
    echo "### $2"
    echo "### $(date -u '+%Y-%m-%dT%H:%M:%SZ') | context: $(kubectl config current-context 2>/dev/null)"
  } | tee "$LOG"
}

# Usage: run <command...>   (prints "$ command", runs it, logs both)
run() {
  printf '\n$ %s\n' "$*" | tee -a "$LOG"
  bash -c "$*" 2>&1 | tee -a "$LOG"
}

# Usage: note "<text>"   (comment line, shown and logged)
note() {
  printf '\n# %s\n' "$*" | tee -a "$LOG"
}
