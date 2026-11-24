#!/usr/bin/env bash
# Evidence 11 (Lab 3, part 4): one preview namespace per Pull Request on the kind
# cluster, one state file per PR. PR 42 runs release v1.1.0, PR 43 release v1.0.0;
# both are deployed, checked, then PR 42 is destroyed.
# Applies and destroys use -auto-approve so the run is not interactive.
source "$(dirname "$0")/lib.sh"
P="terraform -chdir=infra/preview"
K="kubectl --context kind-devops-lab"
REPO=ghcr.io/valentin-meltz/efrei-devops_project-lab-1
IMG_42=$REPO:982483e48711ca36531464c164ad73718640ee22   # v1.1.0
IMG_43=$REPO:ba33ff148f57ad68f209a683faeb358a1389c4df   # v1.0.0

# The GHCR token reaches Terraform through the environment only (ephemeral
# variable ghcr_token); it is never printed or passed on a command line.
TOKEN_FILE="${GHCR_TOKEN_FILE:-$HOME/.config/ghcr-pull-token}"
[ -s "$TOKEN_FILE" ] || { echo "Missing token file: $TOKEN_FILE" >&2; exit 1; }
TF_VAR_ghcr_token="$(tr -d '[:space:]' < "$TOKEN_FILE")"
export TF_VAR_ghcr_token

vars() { echo "-var pr_number=$1 -var image=$2 -var owner=Valentin-Meltz -no-color -input=false"; }
use_pr() { run $P init -reconfigure -backend-config=path=state/pr-$1.tfstate -no-color -input=false; }
pf_curl() {  # pf_curl <namespace> <local port>: port-forward the Service, call / and /health
  note "port-forward svc/myapp in $1 to localhost:$2 (background)"
  $K port-forward -n "$1" svc/myapp "$2:80" >/dev/null 2>&1 &
  local pf=$!
  run "curl -s --retry 10 --retry-connrefused --retry-delay 1 http://localhost:$2/; echo"
  run "curl -si http://localhost:$2/health | sed -n '1p;\$p'; echo"
  kill "$pf"; wait "$pf" 2>/dev/null
}

# Reset: no preview left from a previous run.
for pr in 42 43; do
  $P init -reconfigure -backend-config=path=state/pr-$pr.tfstate -no-color -input=false >/dev/null
  $P destroy $(vars $pr "$IMG_42") -auto-approve >/dev/null 2>&1
done

start_log evidence/11-terraform-preview/preview.txt "11 - Ephemeral preview environments per Pull Request"
note "Reset before this run: previews pr-42 and pr-43 of a previous run destroyed"

note "Code (4.1: Service added; 4.5: owner and expires labels)"
run "tail -n +1 infra/preview/main.tf infra/preview/variables.tf infra/preview/outputs.tf"
run "terraform fmt -check -recursive infra/preview && echo 'fmt: all files formatted'"

note "4.2 PR 42 (release v1.1.0), with its own state file state/pr-42.tfstate"
use_pr 42
run $P validate -no-color
run $P apply $(vars 42 "$IMG_42") -auto-approve
note "A second plan is empty (exit code 0): the expiry date stays as stamped at creation"
run "$P plan $(vars 42 "$IMG_42") -detailed-exitcode >/dev/null; echo \"exit code: \$?\""
run $K get all -n pr-42
run $K get secret ghcr-pull -n pr-42
pf_curl pr-42 18042

note "Switching PR without -reconfigure: init refuses, because the other path would mean migrating pr-42's state into pr-43's"
run $P init -backend-config=path=state/pr-43.tfstate -no-color -input=false

note "4.3 PR 43 (release v1.0.0), with its own state file state/pr-43.tfstate"
use_pr 43
run $P apply $(vars 43 "$IMG_43") -auto-approve
run $K get all -n pr-43
pf_curl pr-43 18043

note "4.3 Isolation: one namespace and one state file per PR, same resource names, different releases"
run $K get namespaces -l purpose=preview -L pr,owner,expires
run "$K get deployments -A -l app=myapp -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image"
run "ls -lan infra/preview/state"
run $P state list
run $P output -no-color
note "The GHCR token is a write-only value: in both states the secret has no data, and the token appears 0 times (raw or base64 in the docker config)"
run 'jq ".resources[] | select(.type==\"kubernetes_secret\") | .instances[0].attributes | {type, data, data_wo, data_wo_revision}" infra/preview/state/pr-43.tfstate'
run 'grep -cF -- "$TF_VAR_ghcr_token" infra/preview/state/pr-42.tfstate infra/preview/state/pr-43.tfstate'
run 'grep -cF -- "$(printf "%s:%s" Valentin-Meltz "$TF_VAR_ghcr_token" | base64)" infra/preview/state/pr-42.tfstate infra/preview/state/pr-43.tfstate'

note "4.4 Destroy PR 42: select its state, then destroy"
use_pr 42
run $P output -no-color namespace
run $P destroy $(vars 42 "$IMG_42") -auto-approve
run $K get namespace pr-42
run $K get all,secrets -n pr-42
run "jq '.resources | length' infra/preview/state/pr-42.tfstate"
note "PR 43 is untouched"
run $K get all -n pr-43
pf_curl pr-43 18043
run $K get namespaces -l purpose=preview -L pr,owner,expires

note "4.5 / Q6: the labels let a scheduled cleanup job find expired previews (today, then a simulated later date)"
JANITOR="$K get namespaces -l purpose=preview -o json | jq -r --arg today"
FILTER="'.items[] | select(.metadata.labels.expires < \$today) | \"\\(.metadata.name) owner=\\(.metadata.labels.owner) expired=\\(.metadata.labels.expires)\"'"
run "$JANITOR \"\$(date -u +%F)\" $FILTER | grep . || echo 'no expired preview'"
run "$JANITOR 2026-12-31 $FILTER | grep . || echo 'no expired preview'"
