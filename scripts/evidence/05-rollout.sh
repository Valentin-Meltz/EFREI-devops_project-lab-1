#!/usr/bin/env bash
# Evidence 05 (part 5): rolling update v1.0.0 -> v1.1.0 under traffic, failed rollout, rollback.
# Prerequisite: part 4 deployed, and k8s/overlays/dev pins the v1.1.0 image.
source "$(dirname "$0")/lib.sh"
start_log evidence/05-rollout/rollout.txt "05 - Rolling update and rollback (dev)"
DIR=evidence/05-rollout
BROKEN_IMAGE=ghcr.io/valentin-meltz/efrei-devops_project-lab-1:does-not-exist

summary() {  # summary <first line> <traffic log>: counts of the traffic log from that line
  run "tail -n +$1 $2 | awk '{n++} /HTTP 200/{ok++} /\"version\":\"1.0.0\"/{v0++} /\"version\":\"1.1.0\"/{v1++} END{printf \"requests=%d ok=%d failed=%d served_by_v1.0.0=%d served_by_v1.1.0=%d\\n\", n, ok, n-ok, v0, v1}'"
}

note "State before the update"
run kubectl rollout history deployment/myapp -n dev
run "kubectl get deploy myapp -n dev -o jsonpath='{.spec.template.spec.containers[0].image}'; echo"
OLD_HASH=$(kubectl get pods -n dev -l app=myapp -o jsonpath='{.items[0].metadata.labels.pod-template-hash}')

note "Start the in-cluster traffic generator (k8s/experiments/traffic-generator.yaml)"
run kubectl apply -f k8s/experiments/traffic-generator.yaml
run kubectl wait --for=condition=Ready pod/traffic -n dev --timeout=120s

note "5.1 The dev overlay now pins v1.1.0: what will change"
run kubectl diff -k k8s/overlays/dev
run kubectl apply -k k8s/overlays/dev

note "5.2 Watch the rollout, then wait until the old pods are fully gone"
run kubectl rollout status deployment/myapp -n dev --timeout=420s
run kubectl wait --for=delete pod -l "app=myapp,pod-template-hash=$OLD_HASH" -n dev --timeout=120s
run kubectl get rs -n dev -l app=myapp -o wide
run kubectl get pods -n dev -l app=myapp
kubectl logs traffic -n dev > "$DIR/traffic.log"
PHASE2_START=$(( $(wc -l < "$DIR/traffic.log") + 1 ))
note "Traffic during the rolling update (full log: $DIR/traffic.log)"
summary 1 "$DIR/traffic.log"
run "grep -n -m1 '\"version\":\"1.1.0\"' $DIR/traffic.log"

note "5.3 Drill: deploy an image tag that does not exist"
run kubectl set image deployment/myapp "myapp=$BROKEN_IMAGE" -n dev
run "kubectl annotate deployment myapp -n dev 'kubernetes.io/change-cause=drill: broken image tag does-not-exist' --overwrite"
note "Expected: the rollout stalls and this command times out"
run kubectl rollout status deployment/myapp -n dev --timeout=60s
run kubectl get pods -n dev -l app=myapp
BAD_POD=$(kubectl get pods -n dev -l app=myapp -o jsonpath="{.items[?(@.spec.containers[0].image==\"$BROKEN_IMAGE\")].metadata.name}" | awk '{print $1}')
run "kubectl get events -n dev --field-selector involvedObject.name=$BAD_POD --sort-by=.lastTimestamp"
run "kubectl describe deployment myapp -n dev | sed -n '/^Replicas:/p;/^Conditions:/,/^OldReplicaSets:/p'"
note "The three v1.1.0 pods stay Ready behind the Service"
run kubectl get endpointslices -n dev -l kubernetes.io/service-name=myapp

note "5.4 Roll back and check the revision history"
run kubectl rollout history deployment/myapp -n dev
run kubectl rollout undo deployment/myapp -n dev
run kubectl rollout status deployment/myapp -n dev --timeout=120s
run kubectl rollout history deployment/myapp -n dev
run "kubectl get deploy myapp -n dev -o jsonpath='{.spec.template.spec.containers[0].image}'; echo"
run kubectl get pods -n dev -l app=myapp
note "Live state matches Git again (no output from kubectl diff means no drift)"
run "kubectl diff -k k8s/overlays/dev && echo 'no drift between k8s/overlays/dev and the cluster'"

kubectl logs traffic -n dev > "$DIR/traffic.log"
note "Traffic during the failed rollout and the rollback"
summary "$PHASE2_START" "$DIR/traffic.log"
note "Whole run"
summary 1 "$DIR/traffic.log"
run kubectl delete pod traffic -n dev --wait=false
