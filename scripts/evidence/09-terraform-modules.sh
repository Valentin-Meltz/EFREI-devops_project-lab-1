#!/usr/bin/env bash
# Evidence 09 (Lab 3, part 2): webapp module, dev and staging applied separately
# (one folder and one state each) and running side by side.
# Applies use -auto-approve so the run is not interactive.
NO_KUBE=1
source "$(dirname "$0")/lib.sh"
DEV="terraform -chdir=infra/envs/dev"
STG="terraform -chdir=infra/envs/staging"
CURL="curl -si --retry 5 --retry-connrefused --retry-delay 1"
PS="docker ps --filter name=tf-web --filter name=webapp- --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"

# Reset: remove the environments of a previous run of this script.
$DEV destroy -var-file=dev.tfvars -auto-approve -no-color >/dev/null 2>&1
$STG destroy -var-file=staging.tfvars -auto-approve -no-color >/dev/null 2>&1

start_log evidence/09-terraform-modules/modules.txt "09 - Terraform module, dev and staging environments"
note "Reset before this run: dev and staging of a previous run destroyed"

note "Layout and code"
run "find infra -name .terraform -prune -o \( -name '*.tf' -o -name '*.tfvars' \) -print | sort"
run "tail -n +1 infra/modules/webapp/*.tf infra/envs/dev/main.tf infra/envs/dev/dev.tfvars infra/envs/staging/staging.tfvars"
run "diff infra/envs/dev/main.tf infra/envs/staging/main.tf && echo 'dev and staging root modules are identical: only the folder, the state and the tfvars differ'"

note "Part 1's quickstart (tf-web) is replaced by the module: destroy it first"
run "terraform -chdir=infra/quickstart destroy -auto-approve -no-color -input=false | grep -E 'Destroying|Destruction complete|Destroy complete'"

note "Formatting of the whole infra/ tree"
run "terraform fmt -check -recursive infra && echo 'fmt: all files formatted'"

note "2.3 dev: init, validate, apply with dev.tfvars"
run $DEV init -no-color -input=false
run $DEV validate -no-color
run $DEV apply -var-file=dev.tfvars -auto-approve -no-color -input=false

note "2.3 staging: init, validate, apply with staging.tfvars"
run $STG init -no-color -input=false
run $STG validate -no-color
run $STG apply -var-file=staging.tfvars -auto-approve -no-color -input=false

note "2.4 Both containers run side by side with different names and ports"
run "$PS"
run "$CURL http://localhost:8083 | grep -E '^HTTP|<title>'"
run "$CURL http://localhost:8084 | grep -E '^HTTP|<title>'"
run $DEV output -no-color
run $STG output -no-color

note "Q3: one folder = one state; each state only knows its own resources"
run "ls -a infra/envs/dev infra/envs/staging"
run $DEV state list
run $STG state list
note "Applying staging changed nothing for dev: its plan is empty (exit code 0)"
run "$DEV plan -var-file=dev.tfvars -detailed-exitcode -no-color -input=false >/dev/null; echo \"exit code: \$?\""

note "The module rejects invalid inputs (variable validation)"
run "$DEV plan -no-color -input=false -var env_name=Dev_1 -var image=nginx:1.27 -var external_port=80 2>&1 | grep -E 'Error:|must'"
