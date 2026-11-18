#!/usr/bin/env bash
# Evidence 01: kind cluster devops-lab, Ready node, dev/staging/prod namespaces.
source "$(dirname "$0")/lib.sh"
start_log evidence/01-cluster/cluster-setup.txt "01 - Cluster setup"

run kind get clusters
run kubectl cluster-info --context kind-devops-lab
run kubectl get nodes -o wide
run kubectl get namespaces dev staging prod
