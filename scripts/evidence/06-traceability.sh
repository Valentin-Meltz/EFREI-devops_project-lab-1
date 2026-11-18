#!/usr/bin/env bash
# Evidence 06 (part 6): release annotations, pod -> commit -> PR/reviewer -> CI run,
# events, RBAC viewer account. Run it right after 05: events expire after one hour.
source "$(dirname "$0")/lib.sh"
start_log evidence/06-traceability/traceability.txt "06 - Audit and traceability"
REPO=Valentin-Meltz/EFREI-devops_project-lab-1
VIEWER=system:serviceaccount:dev:viewer
ANNOT='{{range $k, $v := .metadata.annotations}}{{$k}}={{$v}}{{"\n"}}{{end}}'

note "6.1 Release annotations on the prod Deployment. They come from k8s/base/deployment.yaml"
note "(declarative, reviewed in a PR), not from a manual kubectl annotate on the live object"
run "kubectl get deploy myapp -n prod -o go-template='$ANNOT' | grep -v last-applied-configuration"

note "Q7: from a running production pod back to the image, commit, PR, reviewer and pipeline run"
POD=$(kubectl get pods -n prod -l app=myapp -o jsonpath='{.items[0].metadata.name}')
RS=$(kubectl get pod "$POD" -n prod -o jsonpath='{.metadata.ownerReferences[0].name}')
COMMIT=$(kubectl get pod "$POD" -n prod -o jsonpath='{.metadata.annotations.lab\.efrei\.io/git-commit}')
run "kubectl get pod $POD -n prod -o custom-columns='POD:.metadata.name,OWNER:.metadata.ownerReferences[0].name,IMAGE:.spec.containers[0].image'"
run "kubectl get pod $POD -n prod -o jsonpath='{.status.containerStatuses[0].imageID}'; echo"
run "kubectl get rs $RS -n prod -o custom-columns='REPLICASET:.metadata.name,OWNER:.metadata.ownerReferences[0].name,REVISION:.metadata.annotations.deployment\.kubernetes\.io/revision'"
run "kubectl get pod $POD -n prod -o go-template='$ANNOT'"
note "The image itself reports the commit it was built from"
run "kubectl exec $POD -n prod -- wget -qO- http://127.0.0.1:3000/; echo"
note "GitHub: pull request and reviews for that commit, then the CI run that published the image"
run "gh api repos/$REPO/commits/$COMMIT/pulls --jq '.[] | \"PR #\\(.number) \\(.title) (\\(.html_url))\"'"
PR=$(gh api "repos/$REPO/commits/$COMMIT/pulls" --jq '.[0].number')
run "gh pr view $PR -R $REPO --json author,reviews,mergedBy,mergedAt,mergeCommit --jq '\"author=\\(.author.login) merged_by=\\(.mergedBy.login) merged_at=\\(.mergedAt) merge_commit=\\(.mergeCommit.oid)\", (.reviews[] | \"review: \\(.author.login) \\(.state) \\(.submittedAt)\")'"
run "gh run list -R $REPO --commit $COMMIT --json databaseId,workflowName,event,conclusion,url --jq '.[] | \"\\(.workflowName) \\(.event) \\(.conclusion) \\(.url)\"'"
RUN_ID=$(gh run list -R "$REPO" --commit "$COMMIT" --json databaseId,event --jq '[.[] | select(.event=="push")][0].databaseId')
run "gh run view $RUN_ID -R $REPO --json jobs --jq '.jobs[] | \"job \\(.name): \\(.conclusion)\"'"

note "6.2 Reconstruct recent changes from events and describe"
run kubectl get events -n prod --sort-by=.metadata.creationTimestamp
run "kubectl get events -n dev --sort-by=.metadata.creationTimestamp --field-selector involvedObject.kind=Deployment"
run "kubectl describe deployment myapp -n dev | sed -n '/^Annotations:/,/^Selector:/p;/^OldReplicaSets:/,\$p'"
run kubectl rollout history deployment/myapp -n dev
run "kubectl get rs -n dev -l app=myapp -o custom-columns='REPLICASET:.metadata.name,REVISION:.metadata.annotations.deployment\.kubernetes\.io/revision,DESIRED:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image,CHANGE-CAUSE:.metadata.annotations.kubernetes\.io/change-cause'"

note "6.3 Read-only viewer service account (k8s/rbac)"
run kubectl apply -k k8s/rbac
run kubectl get serviceaccount,role,rolebinding -n dev
for check in "list pods" "get pods" "watch pods" "delete pods" "create pods" "get pods --subresource=log" "get secrets" "list deployments" "patch deployments"; do
  run "kubectl auth can-i $check -n dev --as=$VIEWER"
done
run "kubectl auth can-i list pods -n prod --as=$VIEWER"
note "Real requests made as the viewer (server-side dry-run for the delete)"
run kubectl get pods -n dev --as="$VIEWER"
DEV_POD=$(kubectl get pods -n dev -l app=myapp -o jsonpath='{.items[0].metadata.name}')
run kubectl delete pod "$DEV_POD" -n dev --dry-run=server --as="$VIEWER"
run kubectl get secrets -n dev --as="$VIEWER"
run kubectl get pods -n prod --as="$VIEWER"
