#!/usr/bin/env bash
# Evidence 07 (part 6.4, bonus): API server audit log on the dedicated kind cluster
# created by scripts/create_audit_cluster.sh. Every command targets that cluster
# explicitly; the current context stays kind-devops-lab.
# Prerequisite (optional, so the pods can start): KUBE_CONTEXT=kind-devops-audit scripts/create_pull_secret.sh dev
source "$(dirname "$0")/lib.sh"
start_log evidence/07-api-audit/api-audit.txt "07 - API server audit (bonus, cluster kind-devops-audit)"
K="kubectl --context kind-devops-audit"
AUDIT_LOG=evidence/audit/audit.log   # raw log, git-ignored: only filtered entries are kept below

note "Audit flags on kube-apiserver and the audit policy in use (k8s/kind/audit-policy.yaml)"
run "docker exec devops-audit-control-plane grep -- '--audit' /etc/kubernetes/manifests/kube-apiserver.yaml"
run cat k8s/kind/audit-policy.yaml

note "Deploy the dev overlay with kubectl apply"
run "$K create namespace dev --dry-run=client -o yaml | $K apply -f -"
run "$K create secret generic myapp-secret --from-literal=API_KEY=changeme -n dev --dry-run=client -o yaml | $K apply -f -"
run "$K apply -k k8s/overlays/dev"
run "$K rollout status deployment/myapp -n dev --timeout=420s"

note "Audit entries written by that kubectl apply (ResponseComplete stage, kubectl user agent)"
run "jq -c 'select(.stage==\"ResponseComplete\" and .objectRef.namespace==\"dev\" and (.userAgent|startswith(\"kubectl\")) and (.verb==\"create\" or .verb==\"patch\")) | {time: .requestReceivedTimestamp, auditID, user: .user.username, verb, resource: .objectRef.resource, name: .objectRef.name, code: .responseStatus.code, userAgent}' $AUDIT_LOG"

note "Full audit event for the Deployment"
run "jq 'select(.stage==\"ResponseComplete\" and .objectRef.resource==\"deployments\" and .objectRef.namespace==\"dev\" and (.userAgent|startswith(\"kubectl\")))' $AUDIT_LOG | jq -s 'last'"

note "What happened next, from the controllers (same log, same Deployment)"
run "jq -c 'select(.stage==\"ResponseComplete\" and .objectRef.namespace==\"dev\" and (.user.username|startswith(\"system:serviceaccount:kube-system\"))) | {time: .requestReceivedTimestamp, user: .user.username, verb, resource: .objectRef.resource, name: .objectRef.name, code: .responseStatus.code}' $AUDIT_LOG | head -n 12"
