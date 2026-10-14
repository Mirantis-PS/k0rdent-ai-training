# Course guide

**Start here and work down the tables.** Check off a step only when its validation and restoration requirements pass. If returning to an existing environment, verify the previous step's exit state before continuing; do not provision a second environment just to restart a lesson.

Team A needs a private interactive assistant over approved documents. Team B needs batch experiments and occasional training. Your job is to deliver a repeatable service, explain its resource needs, share scarce GPUs and recover from a new incident.

## Prepare

- Confirm [Kubernetes and Linux prerequisites](overview/prerequisites.md). The historical cost figures there are estimates, not a current quote or spending authorization.
- Use macOS, Linux or WSL2 with Bash, Git, SSH, AWS CLI v2, Terraform >=1.8.0 and jq. Cluster tools are installed on the lab instances by the existing setup. Run workstation commands from the repository root unless the lab explicitly changes directory or connects to a host.
- Arrange a dedicated AWS account or approved lab scope, permissions to create the documented IAM/network/compute resources, a chosen region, quotas, a spending ceiling and a cleanup deadline. Each learner uses a unique lab ID. There is no shared hosted environment supplied by this repository.
- Read [architecture](modules/platform-bootstrap/theory/k0rdent-architecture.md), then open [Provision the management cluster](modules/platform-bootstrap/labs/provision-k0rdent.md). Its credential, tool-check and provisioning sections are the executable setup procedure. Do not start from a generic GPU flag in the infrastructure reference.

Read-only local tool checks, before any provisioning:

```bash
git --version
aws --version
terraform version
jq --version
ssh -V
```

## Build the platform

Keep the management cluster throughout the course. Keep the first managed cluster through observability, services, upgrade and audit; audit comes before its teardown. Directory order does not determine execution order.

| Step | Open this lab | Verify before continuing |
|---|---|---|
| 1 | [Provision management](modules/platform-bootstrap/labs/provision-k0rdent.md) | Management cluster, connection and UI checks pass. |
| 2 | [Explore the UI](modules/platform-bootstrap/labs/explore-k0rdent-ui.md) | Identify management resources and components. |
| 3 | [Configure AWS provider](modules/platform-bootstrap/labs/configure-aws-provider.md) | Provider identity and Credential are ready. |
| 4 | [Production configuration](modules/operations/labs/production-configuration.md) | Security/RBAC foundations are in place. |
| 5 | [Provision a managed cluster](modules/platform-bootstrap/labs/provision-managed-cluster.md) | The child cluster is reachable; retain it for steps 6–9. |
| 6 | [Deploy KOF](modules/operations/labs/deploy-kof.md) | Child ingest works; retain KOF 1.6.0. |
| 7 | [Deliver multicluster services](modules/ai-service-delivery/labs/multicluster-services.md) | Service and route continuity checks pass. |
| 8 | [Upgrade management](modules/operations/labs/upgrade-k0rdent.md) | Complete the documented 1.3.1→1.3.2 transition; defer final teardown until audit. |
| 9 | [Capture API audit evidence](modules/operations/labs/api-audit-logging.md) | Audit evidence is saved before child cleanup; management remains available. |

Use the [foundation assessment](references/assessments/foundations-quiz.md) to check understanding. Historical lab IDs inside the documents remain for provenance; follow the order above.

## Check runtime readiness

Do this before allocating a GPU or starting load. A blocked runtime step can be studied and reviewed, but cannot be marked executed.

| Part | Required input | Current limitation |
|---|---|---|
| Platform setup | Authorized AWS account, tools, quotas, budget and deadline | Existing procedures retained; not re-executed for this revision. |
| Existing GPU baseline | [GPU lab contract](modules/gpu-systems/resources/lab-contract.md), its compatible runtime and hardware | Source baseline is one g5.12xlarge worker with four A10G GPUs. |
| Single-GPU workshops | Instructor-qualified model, image, dtype, GPU and bounded workload | Cheaper GPU-1 profile is not yet qualified. Do not reduce source GPU counts blindly. |
| Distributed proof | Two real single-GPU workers, qualified image, private rendezvous and network | GPU-2 execution is pending; CPU analysis cannot replace it. |
| Product-native k0rdent AI delivery | Versioned product sources and documented resource ownership | Distribution/version and supported interfaces remain unresolved. Use no invented APIs. |
| Specialized exercises | Matching MIG/vGPU/NVLink/RDMA/GDS hardware, software and access | Optional; not implied by the baseline. |

Complete an [environment/evidence card](references/pedagogy/evidence-contract.md) before runtime work. It defines private access, versions, limits, raw results and resource retention. Missing hardware does not prevent calculations or design review; label those activities analytical.

## Run the AI workshops

First establish the GPU environment in this order, following each source lab's exact hardware gates:

1. [GPU cluster setup](modules/gpu-systems/labs/gpu-cluster-setup.md): retain the documented GPU Operator 25.3.0, Ubuntu 22.04 and k0s runtime configuration.
2. [Service catalog](modules/ai-service-delivery/labs/service-catalog.md): verify management/workload contexts and ownership.
3. [KAI scheduling setup](modules/gpu-allocation/labs/kai-scheduler.md): complete its explicit 0.12.10→0.14.0 transition and queue checks. Its multi-worker sections need extra nodes. Run:ai is an optional licensed alternative, not an additional required scheduler.

Then follow the workshops below. Read each linked concept capsule just before the exercise, predict the outcome, collect evidence, interpret it and restore state. Serving deployment details are reused from [vLLM inference](modules/inference-and-data/labs/vllm-inference.md) within the first workshop's approved private-service route; the original four-GPU manifest is not a qualified one-GPU shortcut.

| Order | Workshop | Retain for the next step |
|---|---|---|
| 1 | [First private response](modules/platform-bootstrap/labs/first-private-response.md) | Working private endpoint, model identity and ownership map. |
| 2 | [Memory and concurrency](modules/gpu-systems/labs/memory-concurrency.md) | Memory budget, bounded workload and known-good service revision. |
| 3 | [Two teams and a queue](modules/gpu-allocation/labs/two-team-queue.md) | Queue evidence; restore team A's service after the jobs finish. |
| 4 | [Two-worker proof](modules/distributed-ai/labs/two-worker-proof.md) | Both real GPU rank logs and transport evidence; release workers and restore serving. |
| 5 | [Storage and cache](modules/inference-and-data/labs/storage-cache.md) | Separate loading and KV-cache observations; restore storage configuration. |
| 6 | [Performance decision](modules/inference-and-data/labs/performance-decision.md) | Equivalent-workload measurements and a justified service configuration. |
| 7 | [Declarative release](modules/ai-service-delivery/labs/declarative-release.md) | Reusable release, version/source matrix and rollback evidence. |
| 8 | [Diagnose and restore](modules/operations/labs/diagnose-restore.md) | Incident timeline, restored service and runbook. |
| 9 | [Customer handover capstone](modules/capstone/labs/customer-handover.md) | Changed-requirement decision, unfamiliar-incident recovery and complete handover packet. |

If GPU-2 access is missing, continue independent storage/performance/release preparation while retaining the missing distributed proof as an incomplete runtime requirement. Do not claim full course execution without it.

## Evidence and completion

Keep one decision log for both teams. Start from the [session template](references/pedagogy/session-template.yaml) and [measurement table](references/pedagogy/measurements.csv). Each lab lists its acceptance checks, scoped incident, declarative deliverable and cleanup. Keep secrets, kubeconfigs and private prompts out of shared evidence.

Early workshops provide commands; later ones require your own experiment and diagnosis choices. Record active work, reading, waiting and hints using the evidence contract. The 70–80% active-learning target and course duration must be measured in a pilot; they are not established results. The [assessment rubric](instructor/pedagogical-v2/rubric.md) separates reasoning, static review, live execution and independent reproduction.

## Finish or pause

Save evidence before deleting temporary workloads. Restore sharing, queue and serving configuration between workshops; do not run whole-cluster teardown after every exercise. Follow the existing lab cleanup procedures when finished. Capture foundation audit before child teardown, and retain management only if another planned lab needs it.

Inventory GPU/CPU nodes, clusters, volumes, caches, load balancers and networking. A deleted Pod does not release a provisioned GPU node. Assign an owner and expiry to anything intentionally retained. Use the [infrastructure cleanup reference](../lab-infrastructure/README.md#lab-destroysh) and [troubleshooting guide](../lab-infrastructure/docs/troubleshooting.md) alongside the lab-specific instructions; check resource scope before running a destroy command.

## Optional material

Use [extensions](extensions/README.md) only when a customer requirement and the prerequisites justify them. You do not need a bare-metal → virtualization → Kubernetes chain before the AI course. The [module indexes](modules/README.md) provide topic lookup; [glossary](appendix/glossary.md) and [AI assessment](references/assessments/ai-workloads-quiz.md) support review.

### Check retained infrastructure

After saving audit evidence and following the finish/pause sequence above, use the [report-only resource scan](../lab-infrastructure/README.md#lab-reapsh) to check tagged leftovers. A paused management environment still incurs non-compute charges. For a longer gap, decide explicitly whether to retain state or repeat platform setup later; do not destroy prerequisites needed by your next lab.
