# Instructor solutions and facilitation

Keep this separate from the learner path during first attempts. These are expected reasoning and acceptance criteria, not fabricated run output. Use the [evidence contract](../../references/pedagogy/evidence-contract.md), [fault bank](fault-bank.md) and [rubric](rubric.md). Check the actual environment card before teaching. Never ask learners to improvise a missing product interface or spend beyond an approved allocation.

## Facilitation and access alternatives

Start with the continuous two-team scenario and verify Kubernetes prerequisites through the preserved foundation path. Supply a working qualified environment only after P3/P4 gates are satisfied. Before then, run a clearly labeled design/review session: calculations, source analysis, hypotheses and configuration review can be assessed; deployment, benchmark and recovery remain blocked. Preserve the required real GPU-2 proof even if the cohort completes other work first.

Begin with command-level scaffolding in labs1–2, ask for observation choices in3–4, require learner-designed controls in5–6, and offer only boundaries/hints in7–8. The capstone gives no recipe. Record every hint and its level. Use the session clock categories to measure active share and waiting; do not estimate a polished duration from page count. While a bounded provisioning/load operation runs, learners can analyze topology or prepare the next hypothesis, without double-counting time.

For each lab, ask for the hypothesis before results, raw evidence before the conclusion, and restoration before completion. A reasonable prediction that proves false can earn full scientific reasoning credit. A correct guess with no evidence cannot. Retain failed runs in the packet. If a source prerequisite conflicts with a historical label, use the canonical links and migration prerequisite record, not the mistaken label.

## AI-LAB-01

Expected classification: FAQ over approved documents is inference plus retrieval; nightly embeddings are batch inference; style adaptation may use fine-tuning/LoRA with evaluation; from-scratch learning is training; large-scale summaries are batch inference. Ambiguous requests should trigger questions about data and quality, not automatic tool deployment.

A good trace separates management reconciliation from client traffic. The serving process uses tokenizer/model/GPU; k0rdent manages resources through documented controllers rather than generating the answer itself. Check actual model identity and response, private access, owner references and source revision. Running/Ready infrastructure is necessary but insufficient. A wrong local Service name should fail forwarding while the server remains healthy, separating client routing from model execution.

If product ownership is unresolved, accept the annotated diagram and source request, but withhold product-native deployment credit. If GPU access is missing, accept the use-case/trace exercise only. Do not paste a response from the source lab into the evidence packet.

## AI-LAB-02

For the hypothetical example: weights≈5.59GiB; KV128KiB/token;4096 tokens≈0.5GiB per sequence; concurrency4≈2GiB. At8192 and concurrency8, KV≈8GiB. Workspace/headroom still must be added. Learners should distinguish decimal bytes from GiB and KV heads from query heads. Real architectures may invalidate the simplified formula; identifying that is a strength.

A fixed preallocated GPU-memory footprint can coexist with changing cache occupancy, queueing and latency. Accept such a result with relevant cache/server evidence; do not demand a rising nvidia-smi graph. A host cgroup OOMKilled event and CUDA allocation error require different evidence. Lower precision needs model/kernel/GPU support and a quality check; weight quantization does not automatically quantize KV or optimizer state.

Check the compatibility matrix includes unsupported/unknown entries, not only the executed format. Inventory should distinguish advertised devices from physical capacity and show actual CPU/GPU/NIC locality. No device access: assess arithmetic, hypothetical topology and proposed metrics, not hardware inventory.

## AI-LAB-03

With one allocatable whole GPU, two whole-device jobs should serialize under a valid setup. Learners must locate the actual waiting stage; a policy can keep a job unadmitted, while a Pod may be admitted yet unschedulable. The impossible selector fault is placement, so quota increases are irrelevant. Borrowing and priority semantics must be read from the installed policy, not assumed.

A defensible two-team policy protects A’s needed capacity/latency and lets B use explicitly interruptible spare capacity. Other policies may be valid if their customer tradeoffs are stated. Time-slicing is not hardware memory partitioning. MIG requires supported hardware/profiles; vGPU adds virtualization/licensing gates. A DRA diagram should distinguish class selection, workload claim, allocation and driver publication. KAI/Kueue/Run:ai roles must not be conflated or stacked without ownership evidence.

The GPU-1 path cannot prove simultaneous whole-device or successful gang execution. Mark those checkpoints separately; an observed wait proves only that wait. Restore serving and queue policy before distributed work.

## AI-LAB-04

Expected two-rank arithmetic: AllReduce([1],[2]) gives3 on each; AllGather gives[1,2]; Broadcast gives7 in the fixture; ReduceScatter of rank-constant two-element inputs gives3 on each. The fixture checks full parameter vectors across ranks after DDP updates. Global batch stays64 in both runs, so two ranks each receive32 examples. Training timing includes a loss collective each step and excludes startup; it is intentionally not a production efficiency benchmark.

Require both rank logs, actual allocated devices and distinct hosts for cross-node credit. A world_size field alone is insufficient evidence of allocation. NCCL backend does not establish transport; inspect interface/provider logs and topology. TCP is an acceptable core result. A slower two-worker run is plausible for tiny compute and should not be tuned until it appears faster. Compare equivalent data/steps and report repeat spread.

The missing-rank fault can hang before the process group exists, so enforce the outer deadline. Restore by stopping the incomplete launch and starting the complete pair. Advanced fabric discussion should connect oversubscription/locality/congestion to measurable symptoms, while withholding RDMA/fabric-operations credit without actual evidence. No GPU-2: keep runtime incomplete; do not use two CPU processes as a substitute.

## AI-LAB-05

A weight-file cache primarily affects downloading/loading phases; prefix reuse primarily affects eligible repeated prefill. Neither guarantees faster decode. Empty dedicated model cache does not flush host or upstream caches. Valid comparisons document these limits, fixed model/tokenizer, prompt token prefixes and cache state. Similar text may tokenize differently. A restart may change allocator warmup and startup as well as cache state; learners should name that confounder.

The four-path table must distinguish durable weights/datasets/checkpoints from ephemeral KV. Local NVMe may need refill after replacement; shared storage may contend; object access has different semantics from a mounted filesystem. An idle GPU during checkpoint bursts suggests IO contention but could also reflect synchronization or loader starvation. Accept competing hypotheses with discriminating timestamps/metrics. GDS claims require supported-path evidence.

Expected tooling rationale: MLflow/registry for experiment/artifact identity, notebooks for interactive work, vector storage for retrieval, workflow platform for orchestration when needed. None is mandatory merely because it appears in the catalog. Do not require live checkpoint or GDS experiments on an unqualified environment; retain those specific gates.

## AI-LAB-06

Accept a recommendation that rejects higher concurrency because p95/error behavior violates the stated SLO. Check successful counts and actual lengths before comparing throughput. Early EOS or rejected requests can make comparisons unfair. One hundred requests and three repetitions are an instructional protocol, not a reliable p99 service guarantee. Require repeat spread and limitations.

Allocated GPU-hours include idle/load time within the declared boundary. Cost/token uses defined useful output and scoped costs; estimates and billing cannot be mixed. Tokens/s/GPU is not model-independent efficiency. MFU cannot be calculated from a utilization screenshot. Replicas help aggregate capacity only when each model fits and routing/readiness permit; TP/PP introduce communication; EP applies to supported MoE designs.

The command is a scaffold. If authenticated serving or a different approved client route is required, use its documented mechanism and record the difference rather than disabling authentication. Missing metrics remain missing, not zero. No GPU: evaluate the protocol and rejection criteria, withhold performance-result credit.

## AI-LAB-07

The strongest release identifies exactly which resource/revision owns each generated object, pins artifacts, references secrets, and restores through the same owner. A manual generated-Pod change is not durable release management. A template supplies provisioning inputs; catalog/service propagation and GitOps have separate roles. The learner should reject guessed product schemas.

Check candidate target selectors and secret references before apply. Review/rendering proves configuration intent, while live status and response prove execution. Sequential use of one GPU cluster does not demonstrate simultaneous multi-cluster service availability. Application rollback is not equivalent to controller/driver downgrade. Identity/audit evidence should explain who can change desired state without committing secrets or private request content.

For missing P3 documentation, accept a precise release skeleton based on known source interfaces plus a blocked product integration table. Do not grant k0rdent AI-native support credit until authoritative sources resolve it.

## AI-LAB-08

Pick an unused fault layer and retain the hidden change/restore plan. Release only symptom, scope and deadline. Give hints in increasing order: ask which layer fails; suggest an observation; reveal a relevant event; reveal the change only after the attempt. Record assistance.

A good investigation eliminates an alternative and uses a minimal owned change. Require original-operation success, settled reconciliation and restoration, not just restart success. If the fix would require shared configuration, an evidence-backed escalation is the correct action. Evaluate runbook clarity by having a partner identify the symptom, discriminator, fix and rollback without extra explanation.

## AI-CAP-01

Change demand within qualified limits and choose a different root-cause layer from the preceding incident. Do not simply rename the previous failure. Ask the learner to explain one rejected alternative and one unsupported claim. Score the integrated evidence packet using the rubric, with separate analytical and execution states.

A passing customer handover ties memory, queue policy, data paths, measured SLO and declarative ownership to the changed requirement, includes the real GPU-2 proof, diagnoses/restores the new incident and closes resources. Missing hardware or product sources keep the corresponding runtime claims incomplete; they need not invalidate sound analysis. Independent review is useful but does not satisfy P5 independent reproduction. Record pilot findings, hints, active fraction and cost before suggesting release readiness.
