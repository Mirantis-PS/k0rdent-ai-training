# Module 1.2 live QA — 2026-09-08

**Result: PASS for the core lab exercises after documentation corrections.** Production access patterns are reference material, not deployed or certified by this run.

Baseline: `51bd83beca7f9b0b2edd7984b2132254bad0dec0` (main, including merged PR #27). Scope: Theory 1.2 and Lab 1.2 only. Lab 1.3 has not started.

## Real execution evidence

The existing isolated AWS management environment was resumed in eu-west-1. Testing used workstation AWS/SSH commands, the Ubuntu management node, the real Enterprise 1.3.1 browser UI and the public service catalog.

| Exercise | Observed result |
|---|---|
| Resume and local connection helpers | SSH, `--ui-url` and `--show-gateway` succeeded |
| GatewayClass, Gateway, HTTPRoute, proxy pods and Service | Correct route to the UI; proxy became 2/2 Ready after restart |
| Dashboard and resource usage | Authenticated admin dashboard, zero clusters, 18 cluster templates; Metrics API recovered and `kubectl top nodes` succeeded |
| AWS template in UI and CLI | `aws-standalone-cp-1-0-26`, chart 1.0.26, source `kcm-templates`, valid |
| AWS chart defaults | k0s v1.35.1+k0s.1; control-plane instance type empty; Calico |
| External catalog | AI/Machine Learning category found; support tiers observed; Kyverno versions inspected |
| Exact lab HelmRepository manifest | `k0rdent-catalog` created against `oci://ghcr.io/k0rdent/catalog/charts` |
| Exact Kyverno manifest | `kyverno-3-8-1` created; HelmChart fetched 3.8.1; `status.valid=true`; matching UI details |
| Addons UI exercise | Actual Add Template → Create flow created `cert-manager-1-21-1`; HelmChart fetched 1.21.1; valid in CLI and refreshed UI |
| Configuration and credential exploration | Release and all 11 enabled provider components recorded; no k0rdent Credentials yet |
| CLI exploration and aliases | API/CRD/schema inspection passed; aliases passed in the remote login shell |
| Controller logs | KCM/Sveltos inspected; corrected ORC pod command returned actual ORC logs |
| Final health at 13:36:25 UTC | 50 pods, zero unhealthy pods |
| Service delivery distinction | No ClusterDeployments or MultiClusterServices; templates added no application workloads |

The final UI screenshot shows both templates Valid with matching chart versions. Template creation success was not used as a substitute for chart validation.

## Reproduced gaps and corrections

1. **Resume readiness:** the node and stored Management condition were Ready while Envoy and Metrics API were still recovering. Initial `kubectl top nodes` failed; the UI initially timed out. Both recovered without installation changes. Added bounded checks for the UI deployment, proxy pods and metrics APIService.
2. **UI drift:** there is no Templates parent menu or Install action in this release's observed flow. Cluster Templates and Service Templates are separate links; Addons uses Add Template and a creation form. Corrected the route and required checking validation after creation. A stale Creating label required refreshing the page.
3. **Dashboard mismatch:** the exercise asked for a management resource-utilization panel absent from this UI. CPU/memory measurement now explicitly uses kubectl; dashboard counts and warnings remain a separate UI exercise.
4. **Catalog expectations:** the live site displayed Mirantis Certified, Verified Partner and Community tiers rather than the requested Enterprise-only label. Replaced the uncompletable label search with a support-tier comparison. Kept the successfully fetched Kyverno 3.8.1 pin even though the website lists newer versions.
5. **OCI readiness:** HelmRepository READY/STATUS may be blank for OCI sources. Added the distinction and bounded ServiceTemplate validation, supported by the [Flux documentation](https://fluxcd.io/flux/components/source/helmrepositories/#helm-oci-repository).
6. **Configuration interpretation:** an empty AWS instance type is an input to supply, not a hidden default. Added explicit extraction of chart defaults. Management dumps may contain authentication values, so the configuration deliverable must omit them.
7. **Premature workload commands:** no ClusterDeployment exists in this module. Replaced impossible describe/status placeholder commands with schema inspection.
8. **Theory inspection defects:** `orc-system` does not exist here; ORC runs in kcm-system. Its broad deployment selector matched another provider, so the correction discovers the ORC pod by name. The `app.kubernetes.io/name=kcm` log selector matched nothing; the corrected KCM deployment target works.
9. **Theory examples:** corrected provider component names and chart source references to the installed release; clarified conceptual lifecycle stages versus actual condition fields and added applied diagnostic questions.

## Coherence and training value

The useful sequence is: verify the access path → inspect a cluster template → register and validate a service template → compare CLI and UI → explain why service delivery has not occurred. That gives experienced engineers evidence for troubleshooting rather than a tour of menus.

The original Part 2 interrupted this sequence with multiple mutually exclusive deployment designs. The existing production reference block now follows the core exercises and is explicitly non-sequential. Its content remains available for the scheduled design discussion. The session time distinguishes approximately 75 minutes of core exercises from discussion/reference work.

## Learner configuration summary

- Management: k0s v1.35.4+k0s.0, Enterprise 1.3.1, t3.2xlarge, eu-west-1.
- Enabled components: k0smotron, Azure, vSphere, AWS, OpenStack, Docker, GCP, in-cluster IPAM, Infoblox, KubeVirt and ProjectSveltos.
- Catalog: OCI HelmRepository `k0rdent-catalog`.
- Registered services: Kyverno 3.8.1 via YAML; cert-manager 1.21.1 via UI.
- Why no new application pods: ServiceTemplates describe available charts. No ClusterDeployment service configuration or MultiClusterService requested delivery.
- Production design discussion: TLS termination at Envoy would require a real DNS name, certificate Secret and HTTPS listener/route configuration; OIDC additionally requires IdP/client configuration appropriate to the installed release. Acceptance requires a trusted HTTPS request and an authenticated UI session, not only Gateway readiness. Those prerequisites were not supplied or fabricated.

## Verification and limits

The corrected resume, defaults, validation, schema and ORC commands were rerun successfully on the live cluster. The curriculum checker passed with PyYAML 6.0.2 (61 files, zero errors); Git whitespace checks passed. CI results are linked from the PR.

Open PRs #14–#20 were checked: their heads are unchanged from the reviews submitted during Module 1.1, so the existing approvals/requests for changes remain applicable. No PR was merged during this module.

Raw command JSON, redacted configuration output and UI evidence remain local in `docs/qa/week-1/module-1.2/live-20260908/` in the original checkout. Test-harness errors (a non-login shell alias attempt and two missing extracted-command selections) are retained separately from product findings; the corrected login-shell and saved-command executions passed. Credentials and raw infrastructure output are not committed.

The unlicensed UI banner is recorded separately from technical health. Optional cleanup was not used; the two valid templates are retained for review. Alternative MetalLB/NodePort/TLS/ACM/OIDC designs were not deployed: they require other environments, DNS, certificates or an IdP and are explicitly reference material. No managed workload cluster or policy deployment was performed in Module 1.2.
