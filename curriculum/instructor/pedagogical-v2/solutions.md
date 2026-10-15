# Instructor solutions and facilitation

Keep this page away from learners during first attempts. It gives expected reasoning and acceptance criteria, not run output. Use it with the [evidence contract](../../references/pedagogy/evidence-contract.md), [fault bank](fault-bank.md) and [rubric](rubric.md), check the actual environment card before teaching, and never ask learners to improvise a missing product interface or spend beyond an approved allocation.

## Facilitation and access alternatives

Start with the two-team scenario and check Kubernetes prerequisites through the foundation path. Supply a qualified working environment only once the P3/P4 gates are met. Until then, run a clearly labeled design and review session: calculations, source analysis, hypotheses and configuration review can be assessed, while deployment, benchmark and recovery stay blocked. Keep the real GPU-2 proof required even if the cohort finishes other work first.

Scaffold with commands in labs 1–2, ask for observation choices in 3–4, require learner-designed controls in 5–6 and offer only boundaries and hints in 7–8; the capstone has no recipe. Record every hint and its level. Measure active share and waiting with the session clock categories rather than estimating duration from page count. While a bounded provisioning or load operation runs, learners can analyze topology or prepare the next hypothesis, without double-counting time.

For each lab, ask for the hypothesis before results, raw evidence before the conclusion and restoration before completion. A reasonable prediction that proves false can earn full reasoning credit; a correct guess without evidence cannot. Keep failed runs in the packet. Where a source prerequisite conflicts with a historical label, use the canonical links and the [compatibility notes](../../references/compatibility.md), not the mistaken label.

## AI-LAB-01

Expected classification: an FAQ over approved documents is inference plus retrieval; nightly embeddings are batch inference; style adaptation may use fine-tuning or LoRA with evaluation; learning from scratch is training; large-scale summaries are batch inference. Ambiguous requests should prompt questions about data and quality, not automatic tool deployment.

A good trace separates management reconciliation from client traffic. The serving process uses tokenizer, model and GPU; k0rdent manages resources through documented controllers and doesn't generate the answer. Check actual model identity and response, private access, owner references and source revision; Running/Ready infrastructure is necessary but not sufficient. A wrong local Service name should fail forwarding while the server stays healthy, separating client routing from model execution.

If product ownership is unresolved, accept the annotated diagram and source request but withhold product-native deployment credit. Without GPU access, accept only the use-case and trace exercise. Don't let learners paste a source-lab response into the evidence packet.

Provenance: derived from [Lab 1.1](../../modules/platform-bootstrap/labs/provision-k0rdent.md), [Lab 1.5](../../modules/platform-bootstrap/labs/provision-managed-cluster.md), [Lab 5.1](../../modules/gpu-systems/labs/gpu-cluster-setup.md), [Lab 5.2](../../modules/ai-service-delivery/labs/service-catalog.md) and [Lab 5.5 Tasks 1–4](../../modules/inference-and-data/labs/vllm-inference.md); the original provisioning and serving bodies remain intact.

## AI-LAB-02

For the hypothetical example: weights ≈ 5.59 GiB; KV 128 KiB per token; 4,096 tokens ≈ 0.5 GiB per sequence; concurrency 4 ≈ 2 GiB. At 8,192 tokens and concurrency 8, KV ≈ 8 GiB, before workspace and headroom. Learners should tell decimal bytes from GiB and KV heads from query heads; spotting that a real architecture breaks the simplified formula is a strength.

A fixed preallocated GPU-memory footprint can coexist with changing cache occupancy, queueing and latency; accept that result with relevant cache and server evidence rather than demanding a rising nvidia-smi graph. A host cgroup OOMKilled event and a CUDA allocation error need different evidence. Lower precision needs model, kernel and GPU support plus a quality check, and weight quantization doesn't automatically quantize KV or optimizer state.

Check that the compatibility matrix includes unsupported and unknown entries, not only the executed format, and that the inventory separates advertised devices from physical capacity and shows actual CPU/GPU/NIC locality. Without device access, assess the arithmetic, hypothetical topology and proposed metrics, not a hardware inventory.

Provenance: derived from [Lab 5.5 memory background/benchmarking](../../modules/inference-and-data/labs/vllm-inference.md), [GPU setup](../../modules/gpu-systems/labs/gpu-cluster-setup.md) and [topology](../../modules/gpu-systems/labs/topograph-nvlink-topology.md).

## AI-LAB-03

With one allocatable whole GPU, two whole-device jobs should serialize in a valid setup. Learners must locate the actual waiting stage: a policy can keep a job unadmitted, while an admitted Pod can still be unschedulable. The impossible-selector fault is placement, so more quota is irrelevant. Read borrowing and priority semantics from the installed policy rather than assuming them.

A defensible two-team policy protects A's needed capacity and latency and lets B use explicitly interruptible spare capacity; other policies are valid if they state their customer trade-offs. Time-slicing isn't hardware memory partitioning, MIG needs supported hardware and profiles, and vGPU adds virtualization and licensing gates. A DRA diagram should separate class selection, workload claim, allocation and driver publication. Don't let learners conflate or stack KAI, Kueue and Run:ai roles without ownership evidence.

The GPU-1 path can't prove simultaneous whole-device or successful gang execution; mark those checkpoints separately, since an observed wait proves only the wait. Restore serving and queue policy before distributed work.

Provenance: derived from [Lab 5.3](../../modules/gpu-allocation/labs/kai-scheduler.md), [Lab 5.19](../../modules/gpu-allocation/labs/mig-partitioning.md), [Lab 5.1 Tasks 2–6](../../modules/gpu-systems/labs/gpu-cluster-setup.md) and the preserved [licensed orchestration elective](../../extensions/licensed-orchestration/labs/runai-gpu-orchestration.md).

## AI-LAB-04

Expected two-rank arithmetic: AllReduce([1],[2]) gives 3 on each; AllGather gives [1,2]; Broadcast gives 7 in the fixture; ReduceScatter of rank-constant two-element inputs gives 3 on each. The fixture compares full parameter vectors across ranks after DDP updates. The global batch stays 64 in both runs, so each of two ranks receives 32 examples. Training timing includes a per-step loss collective and excludes startup; it is deliberately not a production efficiency benchmark.

Require both rank logs, actual allocated devices and distinct hosts for cross-node credit; a world_size field alone doesn't prove allocation. The NCCL backend doesn't establish the transport, so inspect interface and provider logs and topology; TCP is an acceptable core result. A slower two-worker run is plausible for tiny compute and shouldn't be tuned until it looks faster. Compare equivalent data and steps and report repeat spread.

The missing-rank fault can hang before the process group exists, so enforce the outer deadline, then restore by stopping the incomplete launch and starting the full pair. Advanced fabric discussion should link oversubscription, locality and congestion to measurable symptoms, while withholding RDMA and fabric-operations credit without real evidence. Without GPU-2, keep runtime incomplete; two CPU processes are no substitute.

Provenance: derived from [Lab 5.16](../../modules/distributed-ai/labs/distributed-training.md), [Lab 5.15](../../modules/distributed-ai/labs/rdma-multi-cloud.md) and [training theory](../../modules/distributed-ai/theory/distributed-training.md). The miniature fixture keeps real NCCL and training with fewer dependencies; the original training examples and larger-framework routes are preserved.

## AI-LAB-05

A weight-file cache mainly affects downloading and loading; prefix reuse mainly affects eligible repeated prefill. Neither guarantees faster decode, and an empty dedicated model cache doesn't flush host or upstream caches. Valid comparisons document these limits, the fixed model and tokenizer, prompt token prefixes and cache state. Similar text may tokenize differently, and a restart may change allocator warmup and startup as well as cache state; learners should name that confounder.

The four-path table must separate durable weights, datasets and checkpoints from ephemeral KV. Local NVMe may need refill after replacement, shared storage may contend, and object access has different semantics from a mounted filesystem. An idle GPU during checkpoint bursts suggests IO contention but could also be synchronization or loader starvation; accept competing hypotheses with discriminating timestamps or metrics. GDS claims need supported-path evidence.

Expected tooling rationale: MLflow or a registry for experiment and artifact identity, notebooks for interactive work, vector storage for retrieval and a workflow platform for orchestration when needed. None is mandatory just because it is in the catalog. Don't require live checkpoint or GDS experiments on an unqualified environment; keep those gates.

Provenance: derived from [Lab 5.5](../../modules/inference-and-data/labs/vllm-inference.md), [Lab 5.16 checkpoint tasks](../../modules/distributed-ai/labs/distributed-training.md) and the [ML platform sources](../../extensions/ml-platforms/README.md).

## AI-LAB-06

Accept a recommendation that rejects higher concurrency because p95 or error behavior breaks the stated SLO. Check successful counts and actual lengths before comparing throughput, since early EOS or rejected requests make comparisons unfair. One hundred requests and three repetitions are an instructional protocol, not a reliable p99 guarantee; require repeat spread and limitations.

Allocated GPU-hours include idle and load time within the declared boundary. Cost per token uses defined useful output and scoped costs, never mixing estimates with billing. Tokens/s/GPU isn't model-independent efficiency, and MFU can't come from a utilization screenshot. Replicas add aggregate capacity only when each model fits and routing and readiness allow; TP/PP introduce communication; EP applies to supported MoE designs.

The command is a scaffold. If the service needs authentication or another approved client route, learners use its documented mechanism and record the difference rather than disabling authentication. Missing metrics stay missing, not zero. Without a GPU, evaluate the protocol and rejection criteria and withhold performance-result credit.

Provenance: derived from [Lab 5.5 benchmarking](../../modules/inference-and-data/labs/vllm-inference.md), [KOF](../../modules/operations/labs/deploy-kof.md), [telemetry](../../modules/operations/labs/otel-telemetry-export.md) and the [vLLM 0.14.0 CLI](https://docs.vllm.ai/en/v0.14.0/cli/bench/serve/).

## AI-LAB-07

The strongest release names which resource and revision owns each generated object, pins artifacts, references secrets and restores through the same owner; a manual change to a generated Pod isn't durable release management. A template supplies provisioning inputs, while catalog, service propagation and GitOps play separate roles. Learners should reject guessed product schemas.

Check candidate target selectors and secret references before apply. Review and rendering prove configuration intent; live status and response prove execution. Sequential use of one GPU cluster doesn't demonstrate simultaneous multi-cluster availability, and application rollback isn't a controller or driver downgrade. Identity and audit evidence should show who can change desired state without committing secrets or private request content.

Where P3 documentation is missing, accept a precise release skeleton built on known source interfaces plus a blocked product-integration table. Grant no k0rdent AI-native support credit until authoritative sources resolve it.

Provenance: derived from [Lab 5.2](../../modules/ai-service-delivery/labs/service-catalog.md), [Lab 5.12](../../modules/ai-service-delivery/labs/cluster-templates.md), [Lab 1.7](../../modules/ai-service-delivery/labs/multicluster-services.md), [upgrade](../../modules/operations/labs/upgrade-k0rdent.md) and [audit](../../modules/operations/labs/api-audit-logging.md).

## AI-LAB-08

Pick an unused fault layer, keep the hidden change and restore plan, and release only symptom, scope and deadline. Give hints in increasing order: ask which layer fails; suggest an observation; reveal a relevant event; reveal the change only after the attempt. Record all assistance.

A good investigation eliminates an alternative and uses a minimal owned change. Require original-operation success, settled reconciliation and restoration, not just a successful restart. If the fix needs shared configuration, an evidence-backed escalation is the correct action. Judge runbook clarity by whether a partner can identify the symptom, discriminator, fix and rollback without extra explanation.

Provenance: derived from [Lab 5.6](../../modules/operations/labs/troubleshooting-gpu.md), the [break/fix API](../../modules/operations/labs/breakfix-api.md), [KOF](../../modules/operations/labs/deploy-kof.md), [telemetry](../../modules/operations/labs/otel-telemetry-export.md) and [audit](../../modules/operations/labs/api-audit-logging.md).

## AI-CAP-01

Change demand within qualified limits and choose a root-cause layer different from the preceding incident, not a renamed earlier failure. Ask the learner to explain one rejected alternative and one unsupported claim, and score the integrated packet with the rubric, keeping analytical and execution states separate.

A passing handover ties memory, queue policy, data paths, measured SLO and declarative ownership to the changed requirement, includes the real GPU-2 proof, diagnoses and restores the new incident and closes resources. Missing hardware or product sources leave the matching runtime claims incomplete without invalidating sound analysis. Independent review helps but doesn't satisfy P5 independent reproduction. Record pilot findings, hints, active fraction and cost before suggesting release readiness.

Provenance: a new capstone derived from the continuous customer scenario and the [legacy capstone](../../modules/capstone/labs/capstone.md); all original broader-program material is retained. This AI-specific assessment does not replace specialized endorsements.
