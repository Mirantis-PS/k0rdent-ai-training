# Week 5 Labs 5.2-5.16 Validation Findings

Tracking file for the end-to-end Lab 5.2-5.16 validation plan (see
`docs/plans/2026-04-14-week-5-labs-5.2-5.16-validation.md`).

---

## Lab 5.2: Service Catalog Blueprints

**Status:** 🟡 PASS with fixes

**Execution time:** ~1h 20m wall clock (vs 2h stated, vs ~1h plan-calibrated). Higher than calibration because of
the live debugging + recovery cycles for the empirical bugs.

**Cluster state at start:** Fresh provision + Lab 5.1 Pre-Lab Steps 2-4 (gpu-cluster READY with GPU Operator, 4
GPUs allocatable on worker).

### Empirical bug fixes committed

- `450861f` **fix(lab-5.2): add missing gpu-operator-25-10-0 install in Task 2** — Task 3's MCS referenced
  a ServiceTemplate that Task 2 never installed, so MCS validation failed with
  `ServiceTemplate "gpu-operator-25-10-0" not found`. Root cause of the install failure was the OCI version tag:
  the catalog publishes as `gpu-operator:25.10.0` (no `v` prefix) — using `v25.10.0` trips the kgst pre-install
  `verify-job` with `ghcr.io/k0rdent/catalog/charts/gpu-operator:v25.10.0: not found`. Added an explanation
  note covering when to use `v` vs not.
- `7cdd583` **fix(lab-5.2): add workload-type label step in Task 3** — Lab 5.1 provisions `gpu-cluster`
  with `environment=training, gpu-enabled=true`; Lab 5.2's MCS uses `workload-type: ml-training`. Labels don't
  overlap, so the MCS matches zero clusters and `status.conditions[]` stays empty forever. Added an explicit
  `kubectl label clusterdeployment ... workload-type=ml-training` step to bridge the gap, with a note explaining
  why the label belongs in Lab 5.2 rather than Lab 5.1 (Lab 5.1 labels describe physical characteristics;
  workload-type describes the service profile, which can change over the cluster's lifetime).
- `0e1655c` **fix(lab-5.2): add cert-manager-1-17-2 install in Task 2 (KServe depends on it)** — The `kserve`
  chart renders `cert-manager.io/v1/Certificate` + `Issuer` for its webhook. On a fresh workload cluster without
  cert-manager, Sveltos logs `resource mapping not found for name: "serving-cert"... no matches for kind
  "Certificate" in version "cert-manager.io/v1"`. KServe never deploys. Added the cert-manager install step at
  the top of Task 2.
- `4442e2c` **fix(lab-5.2): remove gpu-operator from Task 3 MCS, add cert-manager** — Empirically, Sveltos
  adopts the gpu-operator Helm release previously installed by Lab 5.1's Pre-Lab Step 4 and runs a helm upgrade
  with the ServiceTemplate's default chart values, which lack the k0s-specific `toolkit.env` overrides
  (`CONTAINERD_CONFIG=/etc/k0s/containerd.d/nvidia.toml`, `CONTAINERD_SOCKET=/run/k0s/containerd.sock`,
  `CONTAINERD_RUNTIME_CLASS=nvidia`). After the upgrade, the nvidia container toolkit daemonset flaps with
  `FailedCreatePodSandBox: no runtime for "nvidia" is configured` and the GPU allocatable count on the worker
  drops to 0. Removed gpu-operator from the MCS with a note; the ServiceTemplate stays installed in Task 2 for
  Lab 5.6 / Lab 5.11 references. Added cert-manager to the MCS so KServe actually deploys.

### Known traps encountered

- **TRAP 4 (transient states):** Observed twice on this lab.
  - ServiceTemplates briefly show `VALID=false` or `<none>` for 30-60s after helm install while FluxCD pulls
    the chart from OCI. A note was added to Task 2 Step 2 so students don't panic.
  - `ClusterSummary.status.featureSummaries[].failureMessage` contains `feature is still being provisioned`
    during active reconciliation — this is an in-progress state from the addon-controller, not a failure.

### New findings (not pre-anticipated)

- **Plan assumes `lab-provision.sh` creates the full k0rdent credential chain.** Empirically it doesn't:
  `05-configure-providers.sh` only creates a *placeholder* `aws-credentials` secret with the literal string
  `REPLACE_WITH_YOUR_ACCESS_KEY`. The actual credential chain (`Secret/aws-cluster-identity-secret`,
  `AWSClusterStaticIdentity/aws-cluster-identity`, ConfigMap
  `aws-cluster-identity-resource-template`, `Credential/aws-cluster-identity-cred`) must be created separately
  — done in Week 1 Lab 1.3 if the student ran through it. This validation session had to apply all four
  resources manually after provisioning. Consider updating `lab-provision.sh` to create the full chain if
  `AWS_ACCESS_KEY_ID` / `AWS_SESSION_TOKEN` are present at provision time, so Lab 5.2+ students who skip
  Week 1 aren't blocked. (Separate, non-Lab-5.2 fix.)
- **`lab-provision.sh` creates a literal `{config,scripts,examples,manifests}` directory** on the mgmt node
  at `/opt/k0rdent-lab/{config,scripts,examples,manifests}` — shell brace-expansion failure in the
  cloud-init `mkdir -p` command. Empty and unused, but worth a cleanup fix when touching that code.
- **Lab 5.2 Task 1 Step 2 chicken-and-egg (minor).** Tells students to run
  `kubectl get servicetemplate gpu-operator-25-10-0 -n kcm-system -o yaml` before Task 2 installs any
  templates. Returns `NotFound` on a fresh cluster. Low priority — students can move on, but a "after Task 2"
  hint would be cleaner. Not fixed (kept out of scope to avoid bundling with the substantive bug fixes).
- **Lab 5.2 Task 5 pre-step `kserve:v0.14.1` does not exist in the catalog.** The verify-job rejects with
  `ghcr.io/k0rdent/catalog/charts/kserve:v0.14.1: not found`. Confirmed `v0.14.0` also absent. The catalog
  appears to only host the current KServe release. The lab's alternative instruction ("modify the chain below
  to only reference templates you already installed") handles this adequately, but the primary install
  command as written cannot succeed. Worth a doc polish note that the catalog may only host the latest
  version of each chart. Not fixed (out of scope for this pass).
- **Lab 5.2 Task 7 expected outcome is incorrect for current kgst.** `helm uninstall mlflow -n kcm-system`
  does NOT remove the `mlflow-1-8-1` ServiceTemplate CRD (it remained `VALID=true` post-uninstall). The lab
  states "Expected: Error from server (NotFound)". The current kgst meta-chart (2.0.2) apparently applies
  `helm.sh/resource-policy: keep` to generated ServiceTemplates. Worth a doc polish note. Not fixed in this
  pass.
- **`kubectl get clusterprofile` is empty; k0rdent uses `Profile` (namespaced), not `ClusterProfile`
  (cluster-scoped).** Lab 5.2's Troubleshooting section suggests `kubectl get clusterprofiles -A` to verify
  Sveltos orchestration, but this always returns empty on k0rdent deployments. The correct resource is
  `kubectl get profiles.config.projectsveltos.io -A`. Worth a doc polish fix to the troubleshooting section.
  Not fixed in this pass.

### Expected-output deviations

- Task 2 Step 2 listing — lab expected 4 templates, actual 5 (after cert-manager fix) or 6 (if gpu-operator
  template also installed per fix `450861f`). Updated expected output in the doc.
- Task 3 MCS — with the original selector `workload-type: ml-training` and the original `gpu-operator-25-10-0`
  reference, the MCS stayed at `ServicesReferencesValidation: False` forever. After both fixes, it progresses
  to `ServicesReferencesValidation=True,ServicesDependencyValidation=True,MultiClusterServiceDependencyValidation=True`
  and begins deploying to `gpu-cluster` via Sveltos.

### Cleanup

All test resources removed per the lab's Cleanup section:
- 3 MultiClusterServices deleted (`ml-platform`, `mlflow-custom`, `kserve-stack`)
- 1 ServiceTemplateChain deleted (`kserve-chain`)
- `gpu-cluster` `spec.serviceSpec` patch reverted
- `mlflow-db-values` test Secret deleted

ServiceTemplates intentionally preserved on the mgmt cluster (Labs 5.3+ will reuse them):
`cert-manager-1-17-2`, `gpu-operator-25-10-0`, `kserve-crd-v0-15-0`, `kserve-v0-15-0`,
`kuberay-operator-1-5-1`, `mlflow-1-8-1`.

### gpu-cluster state at end of lab

- `gpu-cluster` `READY=True`, labels restored to pre-patch state
- Worker `nvidia.com/gpu: 4` allocatable
- GPU Operator helm release present (Lab 5.1 Pre-Lab install; NOT the Sveltos-adopted version — see fix `4442e2c`)
- `cert-manager` namespace on gpu-cluster has leftover pods from Sveltos deployment cycle; they are functional
  but orphaned (no longer managed by any active MCS). Left in place for Lab 5.3+ to consume if needed; can be
  `helm uninstall`-ed at any time.

