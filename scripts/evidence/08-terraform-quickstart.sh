#!/usr/bin/env bash
# Evidence 08 (Lab 3, part 1): first Terraform configuration with the Docker provider.
# Runs 1.1 to 1.5 from an empty state: init/fmt/validate/plan, apply + curl,
# port change 8081 -> 8082, show/state, then a container deleted by hand.
# Applies use -auto-approve so the run is not interactive.
NO_KUBE=1
source "$(dirname "$0")/lib.sh"
TF="terraform -chdir=infra/quickstart"
CURL="curl -si --retry 5 --retry-connrefused --retry-delay 1"

# Reset: empty state and external = 8081, so every run starts from the same point.
$TF destroy -auto-approve -no-color >/dev/null 2>&1
perl -pi -e 's/external = 8082/external = 8081/' infra/quickstart/main.tf

start_log evidence/08-terraform-quickstart/quickstart.txt "08 - Terraform quickstart (Docker provider)"
note "Reset before this run: previous resources destroyed, main.tf back to external = 8081"
run cat infra/quickstart/main.tf

note "1.1 init, fmt, validate, plan"
run $TF init -no-color -input=false
run "$TF fmt -check -diff && echo 'fmt: already formatted'"
run $TF validate -no-color
run $TF plan -no-color -input=false

note "1.2 Apply, then check the container"
run $TF apply -auto-approve -no-color -input=false
run "docker ps --filter name=tf-web --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
run "$CURL http://localhost:8081 | grep -E '^HTTP|^Server|<title>'"

note "1.3 Change the external port to 8082 and read the plan"
run "perl -pi -e 's/external = 8081/external = 8082/' infra/quickstart/main.tf"
run grep -n external infra/quickstart/main.tf
note "Expected: the container is replaced (-/+), because a port mapping cannot change on a running container"
run $TF plan -no-color -input=false

note "1.4 Apply, then inspect the state"
run $TF apply -auto-approve -no-color -input=false
run "docker ps --filter name=tf-web --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
run "$CURL http://localhost:8082 | grep -E '^HTTP|^Server|<title>'"
note "Expected: nothing listens on 8081 any more (curl error 7)"
run curl -sS --max-time 3 http://localhost:8081
run $TF state list
run $TF show -no-color

note "1.5 Delete the container outside Terraform, then plan"
run docker rm -f tf-web
run "docker ps -a --filter name=tf-web --format '{{.Names}}' | grep . || echo 'no container named tf-web'"
note "Expected: Terraform sees the container is gone and plans to create it again"
run $TF plan -no-color -input=false
note "-detailed-exitcode: 0 = no changes, 2 = changes pending (what a drift check in CI looks for)"
run "$TF plan -detailed-exitcode -no-color -input=false >/dev/null; echo \"exit code: \$?\""

note "Back to the desired state"
run $TF apply -auto-approve -no-color -input=false
run "$CURL http://localhost:8082 | grep -E '^HTTP|^Server|<title>'"
run "$TF plan -detailed-exitcode -no-color -input=false >/dev/null; echo \"exit code: \$?\""

note "Q2: what the local state holds, and why it stays out of Git"
run ls -a infra/quickstart
run "grep -E '\"(serial|lineage|hostname|ip_address|gateway|mac_address|repo_digest)\"' infra/quickstart/terraform.tfstate"
run git check-ignore -v infra/quickstart/terraform.tfstate infra/quickstart/terraform.tfstate.backup infra/quickstart/.terraform
