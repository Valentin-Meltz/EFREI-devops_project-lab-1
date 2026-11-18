#!/usr/bin/env bash
# Evidence 03 (part 3): probes, resources, ConfigMap/Secret injection, broken probe drill.
source "$(dirname "$0")/lib.sh"
start_log evidence/03-probes-config/probes-config.txt "03 - Probes, resources and configuration"

POD=$(kubectl get pods -n dev -l app=myapp -o jsonpath='{.items[0].metadata.name}')

note "3.1 / 3.2 Probes and resources as seen by the cluster"
run "kubectl describe pod $POD -n dev | sed -n '/^Containers:/,/^Conditions:/p'"

note "3.3 / 3.4 APP_ENV from the ConfigMap, API_KEY from the Secret (the app only reports whether it is set)"
run "kubectl exec $POD -n dev -- printenv APP_ENV"
run "kubectl exec $POD -n dev -- sh -c 'test -n \"\$API_KEY\" && echo \"API_KEY is set (\${#API_KEY} chars)\"'"
run "kubectl exec $POD -n dev -- wget -qO- http://127.0.0.1:3000/; echo"
note "Q4: Secret data is only base64-encoded; anyone allowed to read the Secret can decode it (fake demo key)"
run "kubectl get secret myapp-secret -n dev -o jsonpath='{.type} {.data}'; echo"
run "kubectl get secret myapp-secret -n dev -o jsonpath='{.data.API_KEY}' | base64 -d; echo"

note "3.5 Drill: same app with both probes on /broken (k8s/experiments/broken-probe)"
run kubectl apply -k k8s/experiments/broken-probe
note "Waiting for the liveness probe to restart the container at least once"
run "kubectl wait pod -l app=myapp-broken-probe -n dev --for=jsonpath='{.status.containerStatuses[0].restartCount}'=1 --timeout=420s"
BROKEN=$(kubectl get pods -n dev -l app=myapp-broken-probe -o jsonpath='{.items[0].metadata.name}')
run kubectl get pods -n dev -l app=myapp-broken-probe
run "kubectl describe pod $BROKEN -n dev | sed -n '/^Conditions:/,\$p'"
note "Readiness fails: the pod is listed in the EndpointSlice but marked not ready, so it gets no traffic"
EP_READY='{range .items[*].endpoints[*]}{.addresses[0]} {.targetRef.name} ready={.conditions.ready}{"\n"}{end}'
run "kubectl get endpointslices -n dev -l kubernetes.io/service-name=myapp-broken-probe -o jsonpath='$EP_READY'"
run "kubectl exec deploy/myapp -n dev -- wget -qO- -T 3 http://myapp-broken-probe/health; echo"
note "The real app is untouched: its three pods are ready and answer through its Service"
run "kubectl get endpointslices -n dev -l kubernetes.io/service-name=myapp -o jsonpath='$EP_READY'"
run "kubectl exec deploy/myapp -n dev -- wget -qO- -T 3 http://myapp/health; echo"
run kubectl delete -k k8s/experiments/broken-probe
