# Verification and evidence checklist

Run the following against the cluster after configuring a real published image tag.

1. `kubectl get nodes -o wide` and `kubectl get namespaces` — cluster and namespace context.
2. `kubectl get all -n dev`, `kubectl get all -n staging`, `kubectl get all -n prod` — required environment outputs.
3. `kubectl get deploy -A -l app=myapp` — replica comparison.
4. `kubectl port-forward svc/myapp 8080:80 -n dev` and `curl -i http://localhost:8080/health` — HTTP response.
5. Delete one pod; record replacement pod appearing and eventual Ready status.
6. Scale to 5 and back to 3; record desired/ready counts.
7. Break the probe path; record `kubectl describe pod` events, then restore it.
8. Perform a successful update with a real second image and record `kubectl rollout status` and response change.
9. Apply an invalid image tag; record `ImagePullBackOff`/failed rollout; undo and record successful recovery plus history.
10. Apply `k8s/rbac`; capture both `kubectl auth can-i` results.
11. Record production Deployment annotations, pod image reference, relevant events and corresponding GitHub PR and Actions URL.
12. Optional: collect API server audit event from the configured kind audit cluster.

Store screenshots or terminal output in `evidence/` with meaningful filenames. Do not submit example output as measured output.
