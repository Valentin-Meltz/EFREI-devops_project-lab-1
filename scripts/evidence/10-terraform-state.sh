#!/usr/bin/env bash
# Evidence 10 (Lab 3, part 3): .gitignore and lock files, dev state migrated to a
# shared folder, state list/show, drift made by hand with Docker and detected by
# plan, state locking (Q4) and what the shared state exposes (Q5).
# Applies use -auto-approve and init uses -force-copy so the run is not interactive.
NO_KUBE=1
source "$(dirname "$0")/lib.sh"
DEV="terraform -chdir=infra/envs/dev"
VARS="-var-file=dev.tfvars -no-color -input=false"
SHARED=/Users/Shared/terraform-state/efrei-devops-lab/dev   # path in infra/envs/dev/shared.backend.hcl
CURL="curl -si --retry 5 --retry-connrefused --retry-delay 1"
PS="docker ps --filter name=webapp- --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
EXIT="echo \"exit code: \$?\""
# Lock metadata names the local user and machine: masked in this log, and ls uses
# numeric owner IDs (-n) for the same reason.
MASK="sed -E 's/(Who: +).*/\\1<user>@<host>/; s/(\"Who\":\")[^\"]*/\\1<user>@<host>/'"

# Reset: dev back to its end state of part 2 (state in infra/envs/dev, container on
# 8083, no hand-made container, nothing in the shared folder).
docker rm -f webapp-dev >/dev/null 2>&1
$DEV init -migrate-state -force-copy -backend-config=path=terraform.tfstate -no-color -input=false >/dev/null
rm -rf "$SHARED"
$DEV apply $VARS -auto-approve >/dev/null

start_log evidence/10-terraform-state/state.txt "10 - Terraform state: backend, drift, locking"
note "Reset before this run: dev state back in infra/envs/dev, webapp-dev on 8083, shared folder empty"

note "3.1 .gitignore: state, plans, provider cache and secret or auto-loaded tfvars are ignored"
run "sed -n '/# Lab 3/,\$p' .gitignore"
run git check-ignore -v --non-matching infra/envs/dev/terraform.tfstate infra/envs/dev/terraform.tfstate.backup infra/envs/dev/.terraform.tfstate.lock.info infra/envs/dev/.terraform infra/envs/dev/tfplan infra/envs/dev/db.secret.tfvars infra/envs/dev/terraform.tfvars infra/envs/dev/local.auto.tfvars infra/envs/dev/dev.tfvars infra/envs/dev/.terraform.lock.hcl infra/envs/dev/shared.backend.hcl
note "'::' = not ignored: dev.tfvars, the lock file and the backend config are committed"

note "3.2 The dependency lock files are committed"
run "git ls-files '*.terraform.lock.hcl'"
run cat infra/envs/dev/.terraform.lock.hcl

note "3.3 Before: the dev state is a local file next to the code"
run "sed -n '1,9p' infra/envs/dev/main.tf"
run cat infra/envs/dev/shared.backend.hcl
run "ls -lan infra/envs/dev"
run "ls -lan $SHARED"
note "Migrate. Run interactively, init asks 'Do you want to copy existing state to the new backend?'; -force-copy answers yes"
run $DEV init -migrate-state -force-copy -backend-config=shared.backend.hcl -no-color -input=false
run "ls -lan $SHARED"
run "jq '.backend | {type, path: .config.path}' infra/envs/dev/.terraform/terraform.tfstate"
note "init copied the state but left the old local copy, which would go stale: remove it, the shared state is now the only one"
run "rm infra/envs/dev/terraform.tfstate infra/envs/dev/terraform.tfstate.backup && ls -a infra/envs/dev"
note "The migrated state still matches the infrastructure (exit code 0 = no changes)"
run "$DEV plan $VARS -detailed-exitcode >/dev/null; $EXIT"

note "3.4 List the resources of the state and inspect the container"
run $DEV state list
run $DEV state show -no-color module.webapp.docker_container.web

note "3.5 Drift: webapp-dev is recreated by hand with Docker, on port 8085 instead of 8083"
run docker rm -f webapp-dev
run docker run -d --name webapp-dev -p 8085:80 nginx:1.27
run "$PS"
run "$CURL http://localhost:8085 | grep -E '^HTTP|<title>'"
run curl -sS --max-time 3 http://localhost:8083
note "plan -refresh-only: what changed outside Terraform, without proposing any action"
run $DEV plan -refresh-only $VARS
note "plan: the drift, and what Terraform would do to go back to the code"
run $DEV plan $VARS
run "$DEV plan $VARS -detailed-exitcode >/dev/null; $EXIT"
note "Terraform tracks the container by ID: the new one (new ID) is invisible to it, but it holds the name webapp-dev, so apply fails"
run "$DEV apply $VARS -auto-approve 2>&1 | grep -A3 'Error:'"
note "Back to the code: remove the hand-made container and apply"
run docker rm -f webapp-dev
run $DEV apply $VARS -auto-approve
run "$PS"
run "$CURL http://localhost:8083 | grep -E '^HTTP|<title>'"
run "$DEV plan $VARS -detailed-exitcode >/dev/null; $EXIT"

note "Q4: the backend locks the state while an operation runs"
note "A first apply (pending change: port 8099) holds the lock while it waits at its approval prompt; it is answered 'no' after 15 s"
BG_LOG=$(mktemp)
( { sleep 15; echo no; } | $DEV apply -var-file=dev.tfvars -var external_port=8099 -no-color >"$BG_LOG" 2>&1 ) &
BG_PID=$!
for _ in $(seq 1 60); do [ -f "$SHARED/.terraform.tfstate.lock.info" ] && break; sleep 0.25; done
run "ls -lan $SHARED"
run "$MASK $SHARED/.terraform.tfstate.lock.info; echo"
note "A second command on the same state, meanwhile"
run "$DEV plan $VARS -lock-timeout=3s 2>&1 | $MASK"
wait "$BG_PID"
note "The first apply, once answered"
run "grep -E 'Do you want|Enter a value|Apply cancelled' $BG_LOG"
rm -f "$BG_LOG"
run "ls -lan $SHARED"
run "$DEV plan $VARS -detailed-exitcode >/dev/null; $EXIT"

note "Q5: the shared state is plain JSON, readable by every user of this Mac (-rw-r--r--)"
run "ls -ln $SHARED/terraform.tfstate"
run "jq '{version, terraform_version, serial, lineage, resources: [.resources[] | {module, type, name, attributes: (.instances[0].attributes | keys | length)}]}' $SHARED/terraform.tfstate"
