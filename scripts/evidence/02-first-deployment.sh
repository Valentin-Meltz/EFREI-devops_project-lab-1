#!/usr/bin/env bash
# Evidence 02 (part 2): base manifests in dev, port-forward, self-healing, scaling.
# Prerequisite: ghcr-pull secret in dev (scripts/create_pull_secret.sh dev).
source "$(dirname "$0")/lib.sh"
start_log evidence/02-first-deployment/first-deployment.txt "02 - First deployment (base manifests in dev)"

note "ConfigMap and fake Secret created out of band (never committed); ghcr-pull already exists"
run kubectl create configmap myapp-config --from-literal=APP_ENV=dev -n dev
run "kubectl create secret generic myapp-secret --from-literal=API_KEY=changeme -n dev"
run kubectl get secret ghcr-pull -n dev

note "2.1 Apply the base Deployment and Service (kustomization.yaml is not a cluster resource)"
run kubectl apply -f k8s/base/deployment.yaml -f k8s/base/service.yaml -n dev
run kubectl rollout status deployment/myapp -n dev --timeout=420s

note "2.2 Pods, Deployment and Service"
run kubectl get all -n dev -o wide

note "2.3 Reach the application through kubectl port-forward"
kubectl port-forward svc/myapp 8080:80 -n dev >/dev/null 2>&1 &
PF_PID=$!
run "curl -s -i --retry 20 --retry-connrefused --retry-delay 1 http://localhost:8080/health"
run "curl -s http://localhost:8080/; echo"
kill "$PF_PID" 2>/dev/null; wait "$PF_PID" 2>/dev/null

note "2.4 Delete one pod and watch the ReplicaSet replace it"
VICTIM=$(kubectl get pods -n dev -l app=myapp -o jsonpath='{.items[0].metadata.name}')
run kubectl get pods -n dev -l app=myapp
run kubectl delete pod "$VICTIM" -n dev --wait=false
run kubectl get pods -n dev -l app=myapp
run "kubectl wait deployment/myapp -n dev --for=jsonpath='{.status.readyReplicas}'=3 --timeout=120s"
run kubectl get pods -n dev -l app=myapp
run "kubectl get events -n dev --field-selector involvedObject.kind=ReplicaSet --sort-by=.lastTimestamp | tail -n 5"

note "2.5 Scale to 5 replicas, then back to 3"
run kubectl scale deployment myapp --replicas=5 -n dev
run kubectl rollout status deployment/myapp -n dev --timeout=120s
run kubectl get deployment myapp -n dev
run kubectl get pods -n dev -l app=myapp
run kubectl scale deployment myapp --replicas=3 -n dev
run kubectl rollout status deployment/myapp -n dev --timeout=120s
run kubectl get deployment myapp -n dev
