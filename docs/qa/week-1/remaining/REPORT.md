# Week 1 remaining labs: live QA, 8 September 2026

## Result

The primary AWS path through Labs 1.3–1.9 was executed against real infrastructure.
Failures were reproduced, corrected and retested. Labs 1.1–1.2 were covered by the
earlier QA work merged in PRs #27 and #28. This report does not claim execution of
every optional provider, topology or disaster-recovery alternative.

Environment: eu-west-1; Enterprise 1.3.1 upgraded to 1.3.2; KOF 1.6.0; workload
template aws-standalone-cp-1-0-26; one control-plane and one worker node, both
t3.medium. The retained management node is t3.2xlarge. Git changes use the configured
user identity without co-author trailers.

## Executed acceptance

| Lab | Result and evidence |
|---|---|
| 1.3 AWS provider | Real SSO credential refresh; Secret → AWS identity → Credential readiness; unique workload SSH key imported. The corrected refresh script completed against live AWS again in evidence 171. |
| 1.4 Production configuration | Six RBAC allow/deny checks matched expectations. Velero AWS storage became Available; backup completed and S3 objects were verified. Namespace policy/quota steps applied. Corrected readiness script reported eight passes, zero failures. |
| 1.5 Managed cluster | CAPA provisioned a separate VPC, two nodes, API ELB and three NAT gateways. Both nodes became Ready; a two-replica nginx deployment ran and was deleted. The management role's missing DescribeInstanceTypes permission was reproduced and repaired. |
| 1.6 Observability | Installed all five charts; child metrics and workload log reached management across VPCs using mTLS. Unauthenticated requests were rejected. Fixed OpenCost's read path and cluster filter; allocation API returned only the two child nodes (159). CPU recording rules yielded data from both clusters (109,159); Grafana CPU/memory, etcd and k0rdent state were inspected. |
| 1.7 Services | Kyverno deployed through MCS; certificate issued; policy reported fail then pass after remediation (87–89,93). Retested the rewritten namespace-scoped exercise (161,163,164). MCS replica update reached two available replicas; selector opt-out removed Kyverno and opt-in restored it. Envoy Gateway 1.8.4 served nginx over an AWS load balancer (153). |
| 1.8 Upgrade | Pre-upgrade backup completed with all 235 objects (111). Published 1.3.2 Release validated and became Ready. Management upgrade completed, all components healthy (121); workload nodes, HTTP route and S3 backup access remained functional (123). No supported AWS template-chain target was discovered; no fictitious workload-version upgrade was performed. |
| 1.9 Audit | Enabled audit on both real controllers. Reproduced API startup failure from policy permissions, repaired ownership, and verified both readyz endpoints. Local token events had Metadata level and zero response bodies (147,148,155,162). Exact workload token and RBAC audit IDs appeared centrally after collector restart (156). Storage arguments confirm 35d retention (149). |

The principal post-restart workload audit IDs are
63f37367-4759-45e3-8276-51ae8978902a (token) and
c623c30b-eeba-415b-90dd-44345e832ce4 (RBAC patch). Evidence 156 asserts the correct
cluster/controller labels and absence of a token response body.

## Reproduced gaps and corrections

1. **Credential verification falsely reports an error on clean logs.** grep -c
   already prints zero; its fallback printed a second zero. Fix counting, fail
   incomplete log verification, and return nonzero on authentication failures.
2. **Discovery and template examples use incorrect fields.** The AWS template
   selector returned no matches; node status selected an unrelated final
   condition. Use actual template names/values and filter the Ready condition.
3. **Readiness and backup output overstate completion.** Default backup columns
   hide phase. Check backup completion, storage availability and actual provider
   rollout instead of inferring readiness from resource existence.
4. **The lab IAM role lacks ec2:DescribeInstanceTypes.** CAPA's machine-capacity
   lookup uses this role even when cluster provisioning uses SSO credentials.
   Add the permission to Terraform's existing policy; the live call then passed.
5. **Cross-VPC TLS certificate generation fails.** NLB names can exceed the
   certificate Common Name limit. Use a short CN with the actual hostname in SAN.
6. **The empty OTLP JSON probe fails on the pinned backend.** Use an empty protobuf
   export request, then separately prove delivery of a real workload log.
7. **Child OpenCost points at management-only DNS.** Add a child-local mTLS query
   proxy through the existing NLB. Configure OpenCost's cluster label/filter;
   HTTP 200 initially hid management resources attributed to the child.
8. **CPU dashboards have no recording rules to execute.** The local storage
   installation needs the generated ConfigMap values passed to its Helm chart.
   Installing those VMRule resources populated the Grafana panels.
9. **Manual child endpoints lack a discoverable source.** Provide the explicitly
   selected management endpoint ConfigMap so the operator stops reporting missing
   regional discovery.
10. **Audit instructions break the API server.** k0s runs kube-apiserver with an
    unprivileged UID; root-owned mode-0600 policy files are unreadable. Make the
    policy and log directory accessible to that UID. Discover the active config
    path; management and CAPA child paths differ.
11. **Collectors miss the modern control-plane taint.** Preserve existing TLS
    overrides and add the control-plane toleration. The audit daemon and k0s
    component collector then ran on the child controller.
12. **Cleanup precedes the audit lab and omits new cloud resources.** Keep both
    clusters through 1.9. Delete application LoadBalancers before CAPA teardown,
    remove the ingest NLB, and inspect surviving AWS resources.

Not every initial failure was a curriculum defect. Early CNI readiness and ELB DNS
propagation recovered naturally. One QA-generated JSON patch contained folded
newlines; it was corrected before verifying the documented file-based patch.
The original kubectl-run policy example does create a violation: its label is
run=test-pod, not app=test-pod. The revised exercise improves scope, assertions and
remediation rather than claiming that command was defective.

## Learning value and structure

Week 1 has a coherent progression: provider identity, operational controls,
provisioning, telemetry, services, upgrades and audit. The main weaknesses were
acceptance criteria and conflicting branches, rather than a need to reorder the
whole week.

Lab 1.7 is now a single baseline: inspect the catalog, deploy Kyverno through MCS,
prove certificate and policy behavior, change values, observe selector removal and
restoration, and test a Gateway route. It replaces the dominant retired
ingress-nginx recipe and placeholder application with executed, observable tasks.
For experienced engineers, the useful questions concern reconciliation ownership,
selector blast radius, failure diagnosis and actual application behavior.

Lab 1.6 now distinguishes successful installation from usable telemetry and correct
cost attribution. Lab 1.9 distinguishes local recording, central delivery and
replacement-node persistence. Keep the latter as a separate advanced exercise;
editing an existing host does not validate replacement of that host.

## Boundaries

- Static long-lived IAM keys, cross-account role assumption, Azure, HA topologies,
  legacy ingress-nginx, Istio, traces and multi-region production deployment were
  not run.
- Management and service upgrade-path discovery was run. No unsupported template
  transition or Kubernetes downgrade was attempted.
- No destructive full-management rollback or controller replacement was performed.
  A ConfigMap-only S3 restore test is recorded separately below; it does not prove
  full disaster recovery or restoration of application volumes.
- OpenCost reports modeled allocation; no AWS billing-export reconciliation was
  performed. The template selected Amazon Linux 2; a supported replacement image
  requires separate template qualification.
- The primary API and CLI paths passed. This is not a fleet-scale load or endurance
  test.

## Open PR review

Rechecked the unchanged open heads and existing review findings. #14, #17 and #20
remain approved; #20 depends on the scanner workflow being available and corrected.
#15, #16, #18 and #19 still need changes:

- #15: missing Owner tags cannot prove a CAPA resource belongs to someone else.
- #16: failed inventory and pending/stopping instances can cause unsafe orphan
  classification.
- #18: scanner exit zero does not prove no billable resources remain.
- #19: macOS-only nc flags fail on the supported Ubuntu path.

No PR was merged. Full heads, review bodies and fetched diffs are retained in the
local evidence directory; existing reviews were not duplicated.

## Evidence and checks

Numbered JSON files in [live-20260908](live-20260908/) contain commands, timestamps,
outputs and exit codes. Some early diagnostic commands used pipelines without
pipefail; their output, not their top-level exit alone, identifies the failure.
Final acceptance commands include explicit assertions.

Local checks: curriculum checker (62 files, zero errors), credential-log regression,
provisioning preflight regression, Terraform formatting and validation. CI results,
restore result and final environment state are appended after verification.

## Final recovery and cleanup evidence

The post-upgrade ConfigMap-only restore completed and recovered the exact expected value (178). Workload EC2, NAT, VPC, tagged volumes/EIPs, Classic ELBs and the ingest NLB all returned empty in AWS inventory (175). Both workload nodes are terminated. Temporary child integration resources and the imported workload key were removed. Management remains preserved for the later course.
