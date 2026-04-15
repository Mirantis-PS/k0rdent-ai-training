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

---

## Lab 5.3: KAI Scheduler

**Status:** 🟡 PASS with fixes

**Execution time:** ~1h 30m wall clock (vs 2.5h stated, vs ~1h 15m plan-calibrated). Most of the overage was the two
systematic-debugging investigations (stale SA token, cluster-root quota) plus 8 atomic fix commits.

**Cluster state at start:** gpu-cluster torn down at end of Lab 5.2 session; mgmt cluster + credential chain still alive.
Re-provisioned gpu-cluster in ~6 min, installed GPU Operator in ~3 min post-helm-exit, 4 GPUs allocatable on worker.

### Empirical bug fixes committed

- `91d7388` **fix(lab-5.3): correct KAI v0.14.0 pod names and scheduler selector in Task 1** — KAI v0.14.0 drops the
  `kai-scheduler-` prefix on most component pods (`pod-grouper`, `queue-controller`, `binder`, `admission`,
  `podgroup-controller`, `kai-operator`), and the scheduler Deployment is named `kai-scheduler-default` because v0.14
  introduced multi-shard scheduling via the `SchedulingShard` CRD — `default` is the name of the built-in shard.
  Verification selector `-l app=kai-scheduler-scheduler` returned zero results; fixed to `-l app=kai-scheduler-default`.
  Also noted that the `nodescaleadjuster` component listed in the lab is optional and not installed by default.
- `18dc811` **fix(lab-5.3): add schedulingshards + topologies CRDs to Task 1 Step 4** — Lab listed 4 expected CRDs;
  v0.14.0 registers 6. The two missing (`schedulingshards.kai.scheduler`, `topologies.kai.scheduler`) are referenced
  implicitly by other tasks (shard naming for Task 7 metrics, topology for Task 5 placement) so worth surfacing.
- `1da7b35` **fix(lab-5.3): correct KAI service names in Task 7 metrics port-forwards** — Functional break: Task 7
  referenced `svc/kai-scheduler-scheduler` and `svc/kai-scheduler-queue-controller` neither of which exist in v0.14.0.
  Actual names: `kai-scheduler-default`, `queue-controller`. Without the fix the port-forward fails immediately and
  blocks the entire metrics task.
- `9ea56d8` **fix(lab-5.3): fix remaining stale kai-scheduler-* selectors** — Three more instances of the same
  stale-selector bug: Task 4 Step 1 rollout-status (hangs forever), Troubleshooting scheduler-logs command (returns
  "No resources found"), Troubleshooting podgrouper-logs command (same).
- `71a4f47` **fix(lab-5.3): force scheduler rollover after enabling gpuSharing in Task 4** — Substantive new finding
  (see "New findings" below): `helm upgrade --set global.gpuSharing=true` deletes+recreates every ServiceAccount in
  the `kai-scheduler` namespace, but does NOT modify the scheduler Deployment's pod-template. Six of seven component
  pods roll over naturally and pick up the new SA UID's token; the scheduler pod stays running with a token for the
  now-deleted SA UID and the API server rejects all its `PodGroup.status` writes with `Unauthorized`. Every fractional
  pod stays `Pending` forever. Added an explicit `kubectl rollout restart deployment/kai-scheduler-default` step and
  a lengthy inline note explaining the root cause.
- `68d0b55` **fix(lab-5.3): give cluster-root non-zero quota so Task 6 preemption works** — Substantive new finding
  (see "New findings" below): Task 2's `cluster-root` spec had `gpu.quota: 0` with a comment claiming "distributed to
  children". Empirically KAI enforces the non-preemptible quota check at every ancestor level, so `inference-critical`
  (priority=125, non-preemptible) is rejected with `NonPreemptibleOverQuota: ... cluster-root quota is 0 GPUs` even
  though its own `inference-queue.quota` is 1. Fixed `cluster-root` to `gpu: 4, cpu: 32000, memory: 128000` (sum of
  children) and added a sixth bullet to the Queue Quota Rules callout.
- `ca5ee73` **fix(lab-5.3): correct Task 5 gang-scheduling claim for KAI v0.14.0** — Lab's Step 1 pod-owner → PodGroup
  mapping table was wrong for v0.14.0. `batch/v1` Jobs do NOT gang-schedule in KAI: PodGrouper's BatchJob plugin
  emits one "legacy" `PodGroup` per pod with `minMember: 1` (confirmed via `pod-grouper` DEBUG log `Using legacy pod-group`).
  Gang semantics only apply to Kubeflow (`PyTorchJob`, `TFJob`, `MPIJob`, `XGBoostJob`), KubeRay (`RayCluster`,
  `RayJob`), or manually pre-created `PodGroup` resources referenced via `pod-group-name` annotation. Rewrote Step 1's
  mapping table + Step 2 heading + disclaimer sentence.
- `06fd547` **fix(lab-5.3): correct fractional-sharing verification in Task 4 Step 4** — Lab instructed students to
  verify sharing by checking `kubectl get pods -n kai-resource-reservation`. Empirically that namespace stays empty
  even with two actively-sharing `gpu-fraction: 0.5` pods. v0.14.0's default fractional mechanism is env-var injection
  (`NVIDIA_VISIBLE_DEVICES=<shared-uuid>`, `RUNAI_NUM_OF_GPUS=0.50`) sourced from an auto-generated ConfigMap, not
  reservation pods. Updated Step 4 to use the env-var match as the primary verification signal.

### Known traps encountered

- **TRAP 1 (STS credential expiration):** At session start, `/tmp/aws-session.env` from the prior Lab 5.2 session
  still existed but its STS token had expired (~13h old). Refreshed via `lab-refresh-creds.sh e2e-val`; the script's
  trailing health check falsely reported CAPA errors (TRAP 8), but direct `kubectl logs` showed CAPA Running and
  Ready with no auth errors — confirmed TRAP 8 is still a bug in the script's post-restart polling race.
- **TRAP 4 (transient states):** ClusterDeployment provisioning showed `NetworkPluginNotReady` for ~30s while Calico
  CNI came up on the control-plane Machine — auto-healed as expected.
- **TRAP 5 (pessimistic timing):** gpu-cluster READY at 6 min (lab says 15), 4 GPUs allocatable 3 min after `helm install --wait`
  exit (driver compile). Continues the pattern from Lab 5.1 session — lab estimates are ~2× pessimistic.
- **TRAP 6 (image pull cost):** N/A for Lab 5.3 — all workload containers use `nvcr.io/nvidia/cuda:12.6.0-base-ubi9`
  which is only ~140 MB and pulled in ~8s. Saving TRAP 6 anticipation for Labs 5.5 / 5.9 where multi-GB images arrive.
- **TRAP 8 (lab-refresh-creds.sh false-positive):** Reproduced. Trailing health check emitted `[ERROR] CAPA still
  has credential errors in capa-controller-manager-b68645687-w5m85`, but the pod was Running/Ready with no
  error/expired/auth log lines at all. The `d06b56e` fix from the Lab 5.1 session only partially addressed the race.
  Worth a follow-up to revisit the script's post-restart polling logic (out of scope for this pass).
- **TRAP 9 (credential chain gap):** Did NOT recur this session — the 4-resource chain from Lab 5.2's workaround
  (`Secret/aws-cluster-identity-secret`, `AWSClusterStaticIdentity`, ConfigMap, `Credential/aws-cluster-identity-cred`)
  was still on the mgmt cluster from the prior session. Only the Secret's stale STS credentials needed refreshing.

### New findings (not pre-anticipated)

- **[HIGH] Stale ServiceAccount token after `helm upgrade --set global.gpuSharing=true`.** Fully documented in commit
  `71a4f47`. Cause: chart deletes+recreates every SA in `kai-scheduler`; pods whose Deployment template doesn't change
  with the flag (the scheduler) don't roll over and keep running on tokens for dead SA UIDs. Symptom: `Unauthorized`
  errors in scheduler logs even though `auth can-i` passes; fractional pods stay `Pending` forever. Fix: explicit
  `kubectl rollout restart deployment/kai-scheduler-default`. **Candidate for promotion to a named TRAP** — future
  labs that `helm upgrade` KAI with feature flags will hit the same issue.
- **[HIGH] `cluster-root.quota = 0` blocks non-preemptible workloads even within leaf quota.** Fully documented in
  commit `68d0b55`. KAI enforces the non-preemptible quota check at every ancestor queue; setting parent quota to 0
  (a common "distribute to children" pattern) makes non-preemptible scheduling fail with `NonPreemptibleOverQuota`
  regardless of leaf quotas. Fix: parent queue quota must be ≥ sum of children's quotas if any child will host
  non-preemptible pods. **This is a different manifestation of TRAP 3** — not the K8s-priority-≥-100 default, but
  a queue-hierarchy quota design gotcha.
- **[HIGH] `batch/v1` Jobs do NOT gang-schedule in KAI v0.14.0.** Fully documented in commit `ca5ee73`. PodGrouper's
  BatchJob plugin emits one "legacy" `PodGroup` per pod with `minMember: 1`. Lab's Task 5 Step 2 example therefore
  demonstrates parallel scheduling, not gang scheduling. Real gang scheduling requires a workload CRD
  (PyTorchJob / TFJob / RayCluster) or a manually pre-created `PodGroup`.
- **[MEDIUM] KAI v0.14.0 component naming diverges from earlier releases.** Pod names drop the `kai-scheduler-`
  prefix for most components; scheduler is named after its `SchedulingShard` (`kai-scheduler-default`). Service
  names follow the pod name convention. Two additional CRDs exist: `schedulingshards.kai.scheduler` and
  `topologies.kai.scheduler`. Covered by commits `91d7388` + `18dc811` + `1da7b35` + `9ea56d8`.
- **[MEDIUM] Fractional GPU sharing uses env-var injection, not reservation pods, by default.** Covered by commit
  `06fd547`. The `kai-resource-reservation` namespace is created but stays empty in the common case; reservation
  pods are only used for staged allocation.
- **[MINOR] `kai_total_preemption_attempts` metric stayed at 0 after Task 6 preemption.** The evict+rebind flow in
  Task 6 (non-preemptible inference pod reclaims quota from research-queue's over-quota fill pods) appears to be
  counted as "reclaim" rather than "preemption" in KAI's metric taxonomy. Worth a doc note for students running
  Task 7 metrics checks, but not blocking and not fixed in this pass.

### Expected-output deviations

- **Task 1 Step 2** pod listing: lab expected 8 pods with `kai-scheduler-` prefix; actual 7 pods with heterogeneous
  names (see commit `91d7388`). `nodescaleadjuster` absent.
- **Task 1 Step 4** CRD listing: lab expected 4 CRDs; actual 6 (see commit `18dc811`).
- **Task 4 Step 4** reservation-pods check: lab expected pods to exist; actual namespace is empty (commit `06fd547`).
- **Task 5 Step 2** `kubectl get pods -l job-name=gang-training -w` output: lab's commentary "Watch all 4 pods get
  scheduled together" is wrong; pods appear one-by-one as GPUs free up. `kubectl get podgroup -l job-name=gang-training
  -o yaml` returns 0 matches (v0.14.0 doesn't propagate `job-name` to PodGroups). Task 5 rewrite (commit `ca5ee73`)
  sets correct expectations.
- **Task 6 Step 3** preemption: lab implies immediate success; actual requires the cluster-root quota fix (commit
  `68d0b55`) before preemption will even be attempted.

### Deferred polish (not fixed in this pass)

- **Task 7 Step 2 metric names.** Lab shows `queue_allocated_gpus`, `queue_deserved_gpus`, `e2e_scheduling_latency`,
  `total_preemption_attempts`. Actual metrics in v0.14.0 are prefixed `kai_*` (e.g. `kai_queue_allocated_gpus`). The
  lab commands still work because `grep queue_allocated_gpus` substring-matches `kai_queue_allocated_gpus`, but the
  expected-name comments are misleading. Worth a doc polish later.
- **Task 5 Step 2 post-apply commands** still suggest `kubectl get podgroup -l job-name=gang-training -o yaml` — this
  returns 0 results in v0.14.0 because `job-name` isn't propagated to PodGroups. The Step 2 rewrite sets expectations
  correctly but doesn't remove the broken command. Fix next pass by substituting `kubectl get podgroups | grep gang-training`.
- **Task 7 `kai_total_preemption_attempts` staying at 0.** Add a note that preemption-via-reclaim may not increment
  this counter; students should verify preemption via `kubectl get events | grep preempt` instead.

### Cleanup

All Lab 5.3 test workloads removed:
- Task 3 pods (`training-job-1`) and Job (`research-experiment`) deleted
- Task 4 pods (`frac-gpu-1`, `frac-gpu-2`, `frac-gpu-memory`) deleted; `kai-resource-reservation` namespace empty
- Task 5 Job (`gang-training`) deleted; completed cleanly (4/4 in 101s)
- Task 6 Job (`low-priority-fill`) and Pod (`inference-critical`) deleted; preemption event archived in cluster events

Resources intentionally preserved for Lab 5.4+ consumption:
- KAI Scheduler v0.14.0 install on `gpu-cluster` (7 pods Running in `kai-scheduler` ns)
- Custom queue hierarchy: `cluster-root` (quota 4) + `training-queue` + `inference-queue` + `research-queue`
- KAI PriorityClasses: `kai-train` (50), `kai-build` (100), `kai-inference` (125)
- Default queues auto-created by KAI: `default-parent-queue`, `default-queue`

### gpu-cluster state at end of lab

- `gpu-cluster` `READY=True`
- Worker `nvidia.com/gpu: 4` allocatable
- GPU Operator v25.3.0 helm release present (Task 0 install)
- KAI Scheduler v0.14.0 in `kai-scheduler` ns (admission, binder, pod-grouper, podgroup-controller,
  queue-controller, kai-operator, kai-scheduler-default — 7 pods total)
- `cert-manager` namespace still present (orphaned Lab 5.2 pods, unchanged)

### gpuSharing state

After the Task 4 upgrade `helm get values kai-scheduler -n kai-scheduler --all` shows `global.gpuSharing: true`;
the setting persists for Lab 5.4+ if those labs use `gpu-fraction` annotations without re-upgrading. If a later lab
toggles gpuSharing off, the SA-recreate-without-scheduler-rollover issue from commit `71a4f47` will recur in reverse.

---

## Lab 5.4: NVIDIA Run:ai (Commercial)

**Status:** ⏭️ SKIPPED (no commercial license available at session time) — **conceptual review only**

**Why skipped:** Run:ai is a NVIDIA commercial product requiring a license + control-plane credentials that the user
did not have in hand at this session. Per the validation plan: "If license unavailable: SKIP with a finding note,
move to Lab 5.5."

**Conceptual review outcome:** Lab reads cleanly against the Run:ai v2.24 docs. No obvious syntax errors, broken
cross-references, or logical inconsistencies. The lab's mental model (control plane + per-cluster agent, Departments
→ Projects, fair-share with over-quota preemption, gang-scheduled PyTorch via `runai training pytorch submit`) is
consistent with NVIDIA's published Run:ai architecture.

### Conceptual flags for next-pass validation (when a license is available)

- **[MEDIUM] Task 1 Step 2 prerequisite grep** — `grep -E 'ingress-nginx|haproxy'` will return 0 matches on clusters
  using Envoy Gateway (our gpu-cluster after the Week 1 refactor uses Envoy). Run:ai's supported-ingress list in
  v2.24 needs verification against the lab's assumption. If Envoy is not supported, the lab needs to install
  ingress-nginx as an additional prerequisite; if Envoy IS supported (via Gateway API), the grep should include it.
- **[MEDIUM] Prometheus prerequisite** — Line 178 lists Prometheus as required, but k0rdent-managed GPU clusters
  do not install it by default. The lab does not tell students how to satisfy this prerequisite. Candidate fix: add
  an install note (e.g., `kube-prometheus-stack` via helm) or cross-reference Lab 5.9 (Kubeflow also uses Prometheus).
- **[LOW-MEDIUM] Task 1 Step 4 scheduler selector** `-l app=runai-scheduler` — unverified. Given the KAI v0.14.0
  naming-divergence pattern documented in Lab 5.3 (commits 91d7388 + 1da7b35 + 9ea56d8), v2.24's Run:ai scheduler
  pod/service labels may diverge from the lab's expected values. Empirical verification against a live install needed.
- **[LOW] Task 8 Deliverables item #4** — "CLI output demonstrating fractional GPU allocation (two 0.5 workloads on
  one GPU)" implies runai CLI output, but Task 5 Step 4 instructs `kubectl get pods -n runai-research-dev -o wide`
  to verify co-location. Inconsistency between deliverable phrasing and task instruction; low priority.

### Cross-lab considerations verified during review

- **TRAP 3 (K8s priority ≥ 100 default non-preemptible):** Does NOT apply to Run:ai — Run:ai uses Department Rank +
  Project quota, not K8s PriorityClass, for preemption decisions. Lab 5.4 Task 7's preemption test is self-consistent
  within Run:ai's own model.
- **TRAP 13 (stale SA token after helm upgrade):** Potential risk if `runai-cluster` chart upgrades trigger the same
  SA delete-recreate pattern KAI's chart does. Unverified.
- **TRAP 14 (parent quota ≥ Σ children for non-preemptible):** Does NOT apply — Run:ai's Department/Project model
  treats Department quota as the parent allocation; the web UI's "Total allocated quota" field reflects this.
- **TRAP 15 (batch/v1 Job does not gang-schedule):** Does NOT apply to Task 6 — `runai training pytorch submit`
  creates a Run:ai-specific `TrainingWorkload` CRD (not a `batch/v1 Job` nor Kubeflow's `PyTorchJob`), and Run:ai's
  built-in scheduler gang-schedules all pods of the TrainingWorkload atomically.

### Recommended follow-up

When a Run:ai trial license becomes available, re-run this lab end-to-end against a fresh k0rdent-managed cluster
that has ingress-nginx (or verified-Envoy) and Prometheus installed. Use the atomic-commit / findings-entry pattern
established in Labs 5.1–5.3 to capture empirical learnings.

