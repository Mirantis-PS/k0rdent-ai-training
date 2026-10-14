# k0rdent AI Training V2 — Master specification

**Status:** consolidated design and execution contract, not an implemented or validated course release.
**Target repository:** `Mirantis-PS/k0rdent-ai-training`.
**Prepared:** 2026-10-14 from the conversation and its two attached design documents.
**Repository baseline:** UNKNOWN until inspected in Codex; record the actual source commit before editing.

## 1. Decision authority and interpretation

Latest explicit owner instructions take precedence over earlier proposals. Follow repository instructions and preserve unrelated work. This master specification resolves the historical design changes. The two reference documents provide depth, but do not override the decisions below. Exact source-file names, counts, prerequisites and runtime compatibility must be checked against the checkout rather than inferred from the conversation.

The initial task was a conservative repository reorganization. The owner subsequently authorized P2 educational enrichment and local commits on2026-10-14; P3 product integration, P4 GPU execution and P5 independent pilot remain separately gated. The complete V2 is the destination, not permission to mix all future changes into its structural commit. Read `IMPLEMENTATION-PLAN.md` for the current execution boundary and `COVERAGE-MATRIX.md` for obligations that must not disappear when deferred.

### Accepted owner constraints

- Train Mirantis engineers who have infrastructure/Kubernetes prerequisites but no AI infrastructure knowledge. Do not turn the course into a generic introductory Kubernetes course or a research-level machine-learning programme.
- Keep k0rdent and k0rdent AI as the continuous deployment, orchestration and operations thread. Explain the AI infrastructure being orchestrated; do not produce a generic AI course followed by a disconnected product appendix.
- Abandon weeks and imposed calendar blocks. Organize by coherent competencies and an executable learning path.
- Preserve all existing source content, not merely its Git history. Week 1 is retained in full and eventually reframed around k0rdent AI. Week 5 is the main technical investment to reuse; selective replacement in the mandatory path does not mean deleting its labs.
- Make active practice the majority. A design target of roughly 70–80% active manipulation, experiment analysis and diagnosis is a proposal to measure, not a verified current property.
- Minimize dependency on expensive or difficult-to-provision AWS GPUs. Preserve advanced features as learning topics while separating specialized hardware practice.
- Work directly on the repository in Codex and produce real local changes and commits. Do not deliver another migration script instead of doing the work.
- Preserve English as the language of learner-facing repository material. Owner-facing conversation may stay French.
- Product-specific k0rdent AI sources will be supplied later. Do not fabricate product APIs, support statements, licensing or control-plane capabilities.

### Superseded proposals — do not reintroduce

A rigid six-week schedule; a fixed 100-hour promise; a large vendor-neutral foundation course before any product use; mandatory BMaaS → VMaaS → KaaS installation stages; requiring every learner to provision H100/A100/NVLink/MIG/RDMA; automatically stacking Kueue, KAI and Run:AI; arbitrary GPU utilization targets as a definition of success; treating a renamed Week 5 as the complete V2.

The eight domain names below are the current reorganization target, not an eternal constraint on the number of pedagogical modules. Stable identifiers and a separate learning path allow later regrouping.

## 2. Professional outcome and scenario

An engineer should be able to design a reference service, deploy its platform with k0rdent AI, explain its resource decisions, measure behavior, troubleshoot an unfamiliar issue, and transfer a reproducible configuration and runbook.

Use one evolving platform: team A needs private interactive inference; team B needs experiments and a small batch/training workload; GPU capacity is limited. Start with a first response, introduce longer contexts and concurrent requests, allocate scarce capacity, run a distributed experiment, investigate model-loading/storage issues, reproduce the service, handle incidents, and deliver the result.

For every lab state explicitly:
1. The user/operator problem.
2. The capacity k0rdent/k0rdent AI provisions, configures, distributes or maintains.
3. The responsibility of Kubernetes, the GPU runtime, the model server, the scheduler, networking and hardware.
4. The observed evidence and persistent configuration that prove success.

Diagnostic commands may be direct. Persistent fixes must return to the documented declarative authority. Do not give two controllers conflicting ownership over the same resources. Verify native versus integrated versus optional functionality against actual product sources.

## 3. Pedagogical contract

Use the loop **predict → manipulate → observe → explain → correct → industrialize**. A successful install or a Running Pod alone does not prove understanding.

Each practical sequence must contain: client/operator brief; prerequisites and input environment state; just-in-time concept capsule; hypothesis; reproducible manipulation; observable checkpoints; interpretation questions; a bounded incident or design trade-off when useful; declarative delivery; restoration/cleanup; learner evidence; instructor notes and acceptable alternatives.

Provide commands with explanations early, incomplete decisions later, and a brief without a recipe at capstone. Separate instructor solutions from learner instructions. Revisit key concepts: KV cache is introduced with a model, investigated through memory, used during performance work and tested again in troubleshooting.

Count active learning separately from waiting for provisioning, image downloads and driver compilation. Do not invent the total course duration; record pilot measurements. A static diagram is a conceptual aid, not evidence of a successful GPU lab.

## 4. Modules and full V2 outcomes

### platform-bootstrap — From k0rdent AI to a first response

Reuse the relevant Week 1 foundations and the GPU/bootstrap and minimal-serving portions of Week 5. Teach training versus fine-tuning versus inference versus RAG, tokens, parameters, context, CPU/RAM/GPU memory, and management/workload-plane roles as needed.

Deliver an actual restricted/private first inference endpoint, its deployment identity and a request-to-GPU trace. Diagnose runtime-versus-device-publication failures. In P1 keep source labs whole and their validated prerequisite sequence intact; a later shorter path requires explicit qualification. Moving upgrade material to operations must not postpone an upgrade that is a prerequisite of the current runtime.

### gpu-systems — Explain and provision model resources

Cover GPU architecture, CUDA from an operator perspective, Tensor Cores, GPU memory capacity and bandwidth, HBM versus GDDR, supported numeric formats and quantization, PCIe/SXM, NUMA, NVLink and NVSwitch. Inspect actual hardware and record what cannot be demonstrated on the small profile.

Teach weight-memory estimates, runtime workspace, activations where relevant, KV cache, prefill/decode, and compute-bound versus memory-bound reasoning. Add the detailed memory/concurrency experiment in the reference example. Distinguish decimal/binary units and estimates from measured consumption; weights fitting is not a serving-capacity guarantee. No advanced CUDA programming or deep mathematical prerequisite.

### gpu-allocation — Allocate, share and admit scarce resources

Explain whole-device allocation, GPU Operator components, discovery/device plugin, CDI/runtime boundaries as applicable, DRA claims and selectors, admission/queues/quotas, placement, priorities, gang scheduling, topology, time-slicing, MIG and isolation. Distinguish scheduler, admission controller and device allocator.

Reuse the existing KAI path where valid. Compare Kueue and alternatives without implying a validated integration. DRA requires a separately documented compatible product/runtime/driver/Kubernetes combination; never silently replace the baseline or expose one physical GPU through competing allocators. Diagnose Pending workloads, demonstrate a bounded sharing experiment, then restore an exclusive baseline for benchmarks.

### distributed-ai — Make GPUs cooperate and explain the transport

Cover data, tensor, pipeline and expert parallelism; NCCL collectives (AllReduce, AllGather, ReduceScatter, Broadcast); PCIe and GPU/NIC/NUMA locality; NVLink/NVSwitch; TCP/ordinary networking; RDMA, InfiniBand, RoCE, EFA and GPUDirect RDMA as distinct capabilities.

Explain PFC/ECN, congestion, ECMP, leaf/spine, rails and oversubscription at architecture depth, rather than forcing a datacenter build in the core lab. Retain vendor components as examples, not new prerequisites. Cover PyTorch DDP/FSDP, ZeRO and the roles of DeepSpeed/Megatron/Ray/Kubeflow at appropriate depth.

Add a real small two-worker, one-GPU-per-worker NCCL and distributed-training path using synthetic data. Verify the actual transport; distinguish fixed-global-batch and fixed-per-GPU-batch comparisons. A slow two-GPU result can be educational. Use bounded, reversible rendezvous/interface faults. Retain hardware-specific RDMA/NVLink exercises as separately gated options. A simulated trace does not count as executing those hardware features.

### inference-and-data — Serve effectively and feed the workload

Reuse vLLM for the first service, memory understanding and controlled performance work. Teach batching, continuous batching, paged KV management/PagedAttention, prefix caching, parallelism choices, replicas versus model partitioning, queueing, and realistic autoscaling signals.

Define TTFT, inter-token latency/TPOT, end-to-end latency, request and token throughput, percentiles, warmup, load model and error rate. Change one dimension at a time and record actual input/output token counts. Non-streaming request time is not TTFT. Do not assert a universal utilization or throughput target.

Add AI storage: weights, datasets, checkpoints, model startup, persistent storage, object/S3, shared filesystem/NFS, local NVMe/cache, parallel filesystems, model/dataset loading, checkpoint bursts, CPU data loaders, and GPU starvation. Treat GDS as separately qualified. Vendor systems such as WEKA/VAST/DDN/Lustre are architecture examples, not measured by an unrelated local microbenchmark.

Measure cold versus warm startup and at least one controlled data-path bottleneck. Keep inference-serving and training-I/O conclusions distinct. Estimate GPU-hours and cost per useful unit with scope and pricing date; do not confuse allocation accounting with chargeback or lower latency with comparable quality/model behavior.

### ai-service-delivery — Turn a working workload into a reusable service

Promote Service Catalog, Cluster Templates and multi-cluster services. Cover management resources, templates/values, GitOps/declarative ownership, model and image revisions, registry/artifact roles, identity/secrets, propagation, rollback and fleet operations.

Map product-specific paths only after authoritative sources are supplied. Do not equate k0rdent AI to an invented bundle. Reproduce the measured service, change one versioned policy and recover the prior state. Distinguish sequential reuse of one GPU, CPU-only policy propagation and genuinely simultaneous GPU serving on two clusters.

### operations — Operate, secure, measure and recover

Reuse Week 1 production/RBAC/KOF/upgrade/audit and Week 5 troubleshooting/telemetry. Include DCGM/system/application signals, KOF/Prometheus, logs/events, GPU/HBM/SM/power signals where supported, scheduler wait, NCCL/network behavior, model-load and checkpoint times.

Teach workload-dependent metric interpretation and the limits of per-tenant attribution. Cover access denial tests, identity, isolation, audit evidence, upgrades/rollback, quota and capacity, usage/economics, resource lifecycle and cleanup.

Build a fault bank: unavailable device, broken runtime, Pending jobs, inaccessible model, cold/missing cache, data-loader limits, incorrect NCCL configuration, misleading autoscaling and wrong service target. Each fault needs safe scope, entry state, observable symptoms, timeout, diagnosis clues, minimal fix and restoration. No faults on shared resources without exclusive authorized scope.

### capstone — Deliver a customer engagement without a recipe

Use the same modest hardware principles: two teams, an interactive service and a batch workload, limited GPUs, measured service objectives, access controls and reproducible deployment. Require workload assumptions, resource choices, topology/transport explanation, templates/configuration, measurements, cost scope, runbook, recovery proof, limitations and handover.

Introduce a new incident or changed requirement. Evaluate build, explanation, diagnosis, measurement and transfer. A large AI-factory architecture can be an extrapolation/design extension, not a mandatory expensive lab or a claim that small-lab results scale linearly.

## 5. Source-content conservation and layout

P1 layout: `curriculum/modules/{eight names above}`, `learning-paths/`, existing `overview/`, `extensions/`, `references/` as needed and `migration/`. Keep operational infrastructure/scripts in place. Use semantic lab names and preserve historical IDs in mapping metadata. One canonical copy per lab; navigation may refer to it multiple times.

Keep Week 1 and Week 5 contents in full, including theory, READMEs, assessments, images, resources, notes and known-good compatibility decisions. Retain all other repository content; optional does not mean deleted. Preserve historical guides as references and useful entry points as redirection documents, without duplicating lab bodies.

Inventory every tracked source file and its digest at the captured SHA. A source-to-target map must cover each one, not only known labs. Use separate relocation and link-edit commits. Preserve content hashes in the relocation commit. Later required path changes must have a reviewable diff; do not blanket-replace week numbers inside resource names or runtime configuration.

Refer to `PRESERVATION-MAP.md` for the historical 28-lab candidate mapping. Discrepancies with the actual checkout must be recorded, not forced into that list.

## 6. Hardware qualification, cost and availability

Course profiles are proposed course metadata, not presumed native k0rdent APIs:
- CPU: management, catalog/policy/audit and CPU-compatible propagation only.
- GPU-1: most active labs on one modest whole GPU.
- GPU-2: temporary or shared access to two real mono-GPU workers for distributed proof and genuine scale-out.
- Specialized: explicit MIG, NVLink/NVSwitch, RDMA/GDR/GDS or other hardware capabilities.

G4dn/T4, G5/A10G and G6/L4 are historical candidate families to verify, not certified interchangeable profiles. Do not promise abundance, compatibility, a price ceiling or quota availability. Record offered type, quota, capacity outcome and successful provisioning separately. A dry run or placement score is not a capacity guarantee.

For each feature verify exact SKU/capability, model/license/revision/precision, OS/AMI, k0s/Kubernetes, container runtime, GPU driver/operator, device allocation, scheduler and serving/training image. Recheck current official, preferably versioned, documentation before operational changes. Historical numerical version claims in the reference documents are not current prescriptions.

Keep the existing multi-GPU baseline while deriving a lightweight one; a one-GPU variant cannot claim four-replica or hardware-topology tests. Preserve specialized labs as options without removing concepts from core learning. Understand/executed/independently mastered are different levels of evidence.

No cloud provisioning, paid tests, new subscriptions or license acceptance without explicit authorization and budget. Prohibit silent fallback to an expensive instance. Document region/AZ/type alternatives and controller behavior rather than inventing a native capability resolver. Cleanup must cover compute, disks/snapshots as applicable, load balancers, public/network resources and retained data, with clear next-lab dependencies.

## 7. Validation and done criteria

Track separate statuses: source-preserved; drafted; statically-checked; documented-compatible; executed with evidence; independently reproduced; blocked; deferred. Do not equate documentation presence or a linter pass to runtime compatibility or learner mastery.

Every coverage requirement needs source, destination, phase, learning evidence and verification state. A requirements row is not done because its heading exists. New lab readiness requires reproducible prerequisites, exact configuration, safe commands, observable checkpoints, conceptual questions, expected invariants rather than fabricated outputs, restoration and cleanup.

The complete V2 is not done until product integration is sourced, core GPU profiles are tested, distributed claims are actually exercised, preservation is verified and at least one independent learner has completed a pilot. Record omissions and unresolved gates instead of claiming a complete release.

## 8. Open questions that must not block safe reorganization

Still open: active study time, budget per learner/cohort, permitted regions/quotas and concurrency, target k0rdent AI distribution/version/docs, exact model/runtime/dtype, access to specialized hardware, certification modality.

Do not ask again whether the owner wants k0rdent AI, hands-on, preservation, no weeks or direct repository work: those are decided. Continue unblocked work and record questions narrowly; never fill missing product details with invented behavior.
