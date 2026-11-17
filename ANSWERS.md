# Lab 2 — Answers (Session 2)

## Q1 — What is the role of a namespace? Does it provide strong security isolation by itself?
A namespace logically groups namespaced Kubernetes resources and scopes resource names, RBAC permissions, quotas, and policies. It is useful for separating `dev`, `staging`, and `prod` within one cluster. It is **not** a strong security boundary by itself: workloads may still share nodes, the kernel, and networking. For stronger separation, apply least-privilege RBAC, NetworkPolicies with a compatible CNI, Pod Security Admission, resource quotas, and separate clusters for sensitive trust boundaries.

## Q2 — Why does Kubernetes recreate the deleted pod? Which component is responsible?
The Deployment specifies a desired replica count. Its ReplicaSet continuously compares desired and actual pods. When a pod is deleted, the **ReplicaSet controller** creates a replacement to restore the desired count; the scheduler assigns it to a node and the kubelet starts its containers. The Deployment controller manages ReplicaSets and rollouts, rather than directly recreating each pod.

## Q3 — Readiness versus liveness; what happens to traffic when readiness fails?
A **readiness probe** determines whether a pod should receive traffic. If it fails, Kubernetes marks the pod unready and removes it from the Service's ready endpoints (after endpoint propagation); the container need not restart. A **liveness probe** determines whether the container should be restarted when it is unhealthy. A failed liveness probe eventually causes kubelet to restart the container, according to probe thresholds and restart policy. Both use `/health` in this lab, but production applications may need separate checks.

## Q4 — Is a Kubernetes Secret encrypted by default? How would you improve this?
A Secret manifest's `data` field is base64-encoded, **not encrypted**. Kubernetes API access is normally protected with TLS, but Secret data in etcd is not guaranteed to be encrypted at rest unless encryption at rest is configured. Improve protection using encryption at rest with a KMS provider, restricted RBAC, external secret management (for example a CSI driver or external-secrets integration), rotation, and avoiding plaintext secrets in Git or command history. This lab's fake key is only a demonstration.

## Q5 — How does Kustomize help hybrid/multi-cloud deployments? What differs in real clusters?
A reusable `base` defines the application once; `overlays` specify environment-dependent namespaces, replica counts, labels, image versions and configuration. This reduces duplication and configuration drift across on-premises and cloud deployments. Real clusters may differ in ingress/load-balancer controllers, storage classes, networking/CNI, DNS, IAM/workload identity, secret backends, node architectures, security policies, quotas, and observability. Kustomize provides portable manifests, but does not itself provision or secure cloud infrastructure.

## Q6 — Why did the broken rollout not take down the application?
The Deployment uses RollingUpdate with `maxUnavailable: 0` and `maxSurge: 1`. A new pod with an invalid image cannot become Ready, so the Deployment does not intentionally terminate healthy old replicas to make room for it. The Service continues routing to Ready old pods. The rollout stalls and can eventually report `ProgressDeadlineExceeded`; the rollback restores the previous pod template. This behavior assumes existing pods and cluster capacity remain healthy and is not a universal zero-downtime guarantee.

## Q7 — From a production pod, how do you find its commit, reviewer and pipeline run?
First inspect the pod's image reference (`kubectl get pod ... -o jsonpath=...`) and trace its ReplicaSet/Deployment ownership. Read the Deployment annotations for the commit SHA, pipeline URL, owner and ticket, and confirm the image tag or digest. Open that commit in GitHub, find the associated Pull Request and its review/approval history, then follow its GitHub Actions run to the published GHCR image. A reliable chain is **pod → image digest/tag → commit → Pull Request/reviewer → CI run → registry artifact**. Annotations must be populated by the release process; they are not independently trustworthy proof.

## Q8 — Why is manual `kubectl edit` in production a traceability risk?
`kubectl edit` changes live cluster state without necessarily updating Git, creating configuration drift and bypassing normal Pull Request reviews, CI checks, and deployment approvals. The change may later be overwritten by a declarative deployment, and the reason or reviewer can be hard to reconstruct. Prefer Git-reviewed manifests, automated deployment pipelines, protected environments, and audit logging. Emergency changes should be recorded and reconciled back to Git immediately.
