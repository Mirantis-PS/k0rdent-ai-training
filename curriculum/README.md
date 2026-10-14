# Course guide

**Start here and work down the tables.** Tick a step only when its checks pass and its changes are restored. When you return to an environment, check the previous step's exit state instead of provisioning a new one.

Team A needs a private interactive assistant over approved documents; team B needs batch experiments and occasional training. You deliver a repeatable service, explain its resource needs, share scarce GPUs and recover from a new incident.

## Prepare

- Check the [Kubernetes and Linux prerequisites](overview/prerequisites.md); its cost figures are historical estimates, not a quote.
- Use macOS, Linux or WSL2 with Bash, Git, SSH, AWS CLI v2, Terraform >=1.8.0 and jq. The labs install cluster tools on the instances. Run workstation commands from the repository root unless a lab says otherwise.
- Get a dedicated AWS account or approved lab scope that can create the documented IAM, network and compute resources. Fix your region, quotas, spending ceiling, cleanup deadline and a unique lab ID. No hosted environment is provided.
- Read the [architecture](modules/platform-bootstrap/theory/k0rdent-architecture.md), then follow [Provision the management cluster](modules/platform-bootstrap/labs/provision-k0rdent.md) for setup, not the infrastructure reference's generic GPU flag.

Check your tools before provisioning anything:

```bash
git --version
aws --version
terraform version
jq --version
ssh -V
```

## Build the platform

Keep the management cluster for the whole course and the first managed cluster until step 9's audit is saved. Follow this order, not the folder layout.

| Step | Open this lab | Verify before continuing |
|---|---|---|
| 1 | [Provision management](modules/platform-bootstrap/labs/provision-k0rdent.md) | Management cluster, connection and UI checks pass. |
| 2 | [Explore the UI](modules/platform-bootstrap/labs/explore-k0rdent-ui.md) | You can identify management resources and components. |
| 3 | [Configure AWS provider](modules/platform-bootstrap/labs/configure-aws-provider.md) | Provider identity and Credential are ready. |
| 4 | [Production configuration](modules/operations/labs/production-configuration.md) | Security and RBAC foundations are in place. |
| 5 | [Provision a managed cluster](modules/platform-bootstrap/labs/provision-managed-cluster.md) | The child cluster is reachable. Keep it for steps 6–9. |
| 6 | [Deploy KOF](modules/operations/labs/deploy-kof.md) | Child ingest works. Keep KOF 1.6.0. |
| 7 | [Deliver multicluster services](modules/ai-service-delivery/labs/multicluster-services.md) | Service and route continuity checks pass. |
| 8 | [Upgrade management](modules/operations/labs/upgrade-k0rdent.md) | The documented 1.3.1→1.3.2 transition is complete. Don't tear down yet. |
| 9 | [Capture API audit evidence](modules/operations/labs/api-audit-logging.md) | Audit evidence is saved before child cleanup; management stays up. |

Test yourself with the [foundation assessment](references/assessments/foundations-quiz.md). Lab pages keep historical IDs; follow this table's order.

## Check runtime readiness

Do this before you allocate a GPU or start load. Workshop pages marked **draft** are written and statically checked but have not run on GPU hardware: treat their expected results as predictions, and don't mark a blocked step executed.

| Part | Required input | Current limitation |
|---|---|---|
| Platform setup | Authorized AWS account, tools, quotas, budget and deadline | Procedures unchanged; not re-run for this revision. |
| Existing GPU baseline | [GPU lab contract](modules/gpu-systems/resources/lab-contract.md), its compatible runtime and hardware | One g5.12xlarge worker with four A10G GPUs. |
| Single-GPU workshops | Instructor-qualified model, image, dtype, GPU and bounded workload | GPU-1 profile not qualified yet. Don't cut source GPU counts blindly. |
| Distributed proof | Two real single-GPU workers, qualified image, private rendezvous and network | GPU-2 execution pending; CPU analysis can't replace it. |
| Product-native k0rdent AI delivery | Versioned product sources and documented resource ownership | Distribution, version and interfaces unresolved. Use no invented APIs. |
| Specialized exercises | Matching MIG/vGPU/NVLink/RDMA/GDS hardware, software and access | Optional; not part of the baseline. |

Before runtime work, fill in an [environment and evidence card](references/pedagogy/evidence-contract.md). Without hardware you can still do calculations and design reviews; label them *analytical*.

## Run the AI workshops

Set up the GPU environment first, in this order:

1. [GPU cluster setup](modules/gpu-systems/labs/gpu-cluster-setup.md): keep the documented GPU Operator 25.3.0, Ubuntu 22.04 and k0s runtime configuration.
2. [Service catalog](modules/ai-service-delivery/labs/service-catalog.md): verify management and workload contexts and ownership.
3. [KAI scheduling setup](modules/gpu-allocation/labs/kai-scheduler.md): complete its 0.12.10→0.14.0 transition and queue checks. Its multi-worker sections need extra nodes. Run:ai is an optional licensed alternative to KAI.

Then run the workshops in order, reading each concept capsule just before its exercise. The first workshop reuses [vLLM inference](modules/inference-and-data/labs/vllm-inference.md) deployment details through its private-service route; that lab's four-GPU manifest is not a qualified one-GPU shortcut.

| Order | Workshop | Retain for the next step |
|---|---|---|
| 1 | [First private response](modules/platform-bootstrap/labs/first-private-response.md) | Working private endpoint, model identity and ownership map. |
| 2 | [Memory and concurrency](modules/gpu-systems/labs/memory-concurrency.md) | Memory budget, bounded workload and known-good service revision. |
| 3 | [Two teams and a queue](modules/gpu-allocation/labs/two-team-queue.md) | Queue evidence. Restore team A's service after the jobs finish. |
| 4 | [Two-worker proof](modules/distributed-ai/labs/two-worker-proof.md) | Rank logs from both real GPUs and transport evidence. Release the workers and restore serving. |
| 5 | [Storage and cache](modules/inference-and-data/labs/storage-cache.md) | Separate loading and KV-cache observations. Restore the storage configuration. |
| 6 | [Performance decision](modules/inference-and-data/labs/performance-decision.md) | Equivalent-workload measurements and a justified service configuration. |
| 7 | [Declarative release](modules/ai-service-delivery/labs/declarative-release.md) | Reusable release, version/source matrix and rollback evidence. |
| 8 | [Diagnose and restore](modules/operations/labs/diagnose-restore.md) | Incident timeline, restored service and runbook. |
| 9 | [Customer handover capstone](modules/capstone/labs/customer-handover.md) | Changed-requirement decision, unfamiliar-incident recovery and complete handover packet. |

Without GPU-2 access, continue the other workshops and record the distributed proof as incomplete; full course execution requires it.

## Evidence and completion

Keep one decision log for both teams, starting from the [session template](references/pedagogy/session-template.yaml) and [measurement table](references/pedagogy/measurements.csv). Log your time as the evidence card describes, and keep secrets, kubeconfigs and private prompts out of shared evidence. Grading follows the [assessment rubric](instructor/pedagogical-v2/rubric.md).

## Finish or pause

Save evidence before deleting temporary workloads. Between workshops, restore sharing, queue and serving configuration rather than tearing down the cluster. At the end, follow each lab's cleanup; capture the foundation audit before child teardown, and keep management only if a planned lab needs it.

Inventory GPU and CPU nodes, clusters, volumes, caches, load balancers and networking: deleting a Pod doesn't release its GPU node. Give anything you keep an owner and an expiry date. Use the [infrastructure cleanup reference](../lab-infrastructure/README.md#lab-destroysh) and [troubleshooting guide](../lab-infrastructure/docs/troubleshooting.md), and check resource scope before any destroy command.

## Optional material

Use [extensions](extensions/README.md) when a customer requirement calls for one; no bare-metal → virtualization → Kubernetes chain is needed first. For lookup and review: [module indexes](modules/README.md), [glossary](appendix/glossary.md), [AI assessment](references/assessments/ai-workloads-quiz.md).

### Check retained infrastructure

After saving audit evidence and following [Finish or pause](#finish-or-pause), run the [report-only resource scan](../lab-infrastructure/README.md#lab-reapsh) for tagged leftovers. A paused management environment still incurs non-compute charges; before a long break, decide whether to keep state or redo setup later.
