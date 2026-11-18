#!/usr/bin/env bash
# Evidence 04 (part 4): base + overlays deployed to dev, staging and prod.
# Prerequisite: ghcr-pull secret in the three namespaces (scripts/create_pull_secret.sh).
source "$(dirname "$0")/lib.sh"
start_log evidence/04-kustomize/kustomize.txt "04 - Multi-environment with Kustomize"

note "Remove the part 2 objects from dev: from now on dev is managed only by its overlay"
run kubectl delete -f k8s/base/deployment.yaml -f k8s/base/service.yaml -n dev --ignore-not-found
run kubectl delete configmap myapp-config -n dev --ignore-not-found

note "Fake API key in staging and prod, created out of band (dev already has one)"
for ns in staging prod; do
  run "kubectl create secret generic myapp-secret --from-literal=API_KEY=changeme -n $ns --dry-run=client -o yaml | kubectl apply -f -"
done
run kubectl get secrets -A --field-selector metadata.name=ghcr-pull

note "4.2 Rendered prod overlay"
run kubectl kustomize k8s/overlays/prod
note "What changes between environments (rendered dev vs prod)"
run "diff <(kubectl kustomize k8s/overlays/dev) <(kubectl kustomize k8s/overlays/prod)"

note "4.3 Deploy each overlay to its namespace"
for env in dev staging prod; do
  run kubectl apply -k "k8s/overlays/$env"
done
for env in dev staging prod; do
  run kubectl rollout status deployment/myapp -n "$env" --timeout=420s
done

note "Deliverable: kubectl get all in each namespace"
for env in dev staging prod; do
  run kubectl get all -n "$env"
done

note "4.4 Differences between environments"
run kubectl get deploy -A -l app=myapp -L env
run "kubectl get configmap -A -l env -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,APP_ENV:.data.APP_ENV"
for env in dev staging prod; do
  run "kubectl exec deploy/myapp -n $env -- wget -qO- http://127.0.0.1:3000/; echo"
done
