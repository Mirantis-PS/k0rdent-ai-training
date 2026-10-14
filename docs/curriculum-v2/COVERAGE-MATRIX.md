# V2 coverage matrix

**Initial state: all rows are requirements, not verified implementation.** Existing source material is expected to cover parts of many rows, but Codex must inspect the actual SHA before crediting it. Update the implementation/evidence columns with real file sections and test artifacts. Preserve deferred requirements and their reasons.

This table covers the original AI-infrastructure learning recommendations plus the owner's final k0rdent-centric, hands-on and preservation constraints. Numeric performance targets, hardware support and exact software versions are intentionally not invented.

| ID | Required coverage | Destination | Required learning/evaluation evidence | Phase | Actual file / source | Status / execution evidence |
|---|---|---|---|---|---|---|
| C01 | k0rdent/k0rdent AI deployment and ownership | platform-bootstrap; ai-service-delivery | Trace a request and identify management/workload resources and ownership | P1/P2/P3 | To inventory | Pending; no new evidence |
| C02 | Training, fine-tuning/LoRA, inference, RAG, batch versus online | platform-bootstrap | Classify use cases and derive infrastructure questions | P2 | To inventory | Pending; no new evidence |
| C03 | Tokens, parameters, embeddings, attention/Transformer essentials, context | platform-bootstrap; gpu-systems | Explain only what is needed for memory, latency and data-path decisions | P2 | To inventory | Pending; no new evidence |
| C04 | CPU/RAM versus GPU memory; CUDA and Tensor Cores for operators | gpu-systems | Inventory a real system and distinguish host/device/runtime responsibilities | P2/P4 | To inventory | Pending; no new evidence |
| C05 | HBM/GDDR capacity/bandwidth; FLOPs; compute versus memory limits | gpu-systems | Explain an observed bottleneck without treating utilization as sufficient evidence | P2/P4 | To inventory | Pending; no new evidence |
| C06 | FP32/FP16/BF16/FP8/FP4 and integer quantization concepts | gpu-systems; inference-and-data | Select only supported model/kernel/hardware combinations; explain trade-offs | P2/P3/P4 | To inventory | Pending; no new evidence |
| C07 | Weight memory, runtime workspace, activations, KV-cache budget | gpu-systems | Memory experiment with units, estimates and measured results separated | P2/P4 | To inventory | Pending; no new evidence |
| C08 | PCIe/SXM, NUMA, GPU/NIC locality, NVLink/NVSwitch topology | gpu-systems; distributed-ai | Inspect local topology; interpret advanced captures without claiming execution | P2/P4 | To inventory | Pending; no new evidence |
| C09 | GPU Operator, toolkit/runtime, device plugin, discovery | gpu-systems; platform-bootstrap | Reproduce GPU publication and diagnose missing runtime/device | P1/P2/P3/P4 | To inventory | Pending; no new evidence |
| C10 | DRA, DeviceClass, claims/templates, selection and allocation | gpu-allocation | Sourced supported configuration; isolated execution or explicitly conceptual status | P2/P3/P4 | To inventory | Pending; no new evidence |
| C11 | Whole GPU, time-slicing, MIG, vGPU, sharing versus isolation | gpu-allocation | Bounded sharing experiment; MIG remains hardware-gated; restore baseline | P2/P4 | To inventory | Pending; no new evidence |
| C12 | Admission, quotas, borrowing/fairness, priorities, placement, gang/topology | gpu-allocation | Explain Pending state with queue/allocation/placement evidence | P2/P3/P4 | To inventory | Pending; no new evidence |
| C13 | KAI, Kueue/MultiKueue, Run:AI roles and alternatives | gpu-allocation; extensions | Compare roles; use only a validated product path, not an assumed stack | P2/P3 | To inventory | Pending; no new evidence |
| C14 | Data/tensor/pipeline/expert parallelism; MoE implications | distributed-ai | Choose an approach and explain communication and memory consequences | P2 | To inventory | Pending; no new evidence |
| C15 | NCCL AllReduce, AllGather, ReduceScatter, Broadcast | distributed-ai | Run real two-worker collectives; retain transport/log evidence | P2/P4 | To inventory | Pending; no new evidence |
| C16 | TCP, RDMA, InfiniBand, RoCE, EFA, GPUDirect RDMA distinctions | distributed-ai | Identify actual transport and separately gate hardware demonstrations | P2/P4 | To inventory | Pending; no new evidence |
| C17 | PFC/ECN, ECMP, congestion, leaf/spine, rails, oversubscription | distributed-ai | Explain fabric decisions and interpret real traces/reference examples | P2 | To inventory | Pending; no new evidence |
| C18 | PyTorch DDP/FSDP, ZeRO, DeepSpeed/Megatron and Ray/Kubeflow roles | distributed-ai; extensions | Miniature real distributed training; clear depth/core versus extension | P2/P4 | To inventory | Pending; no new evidence |
| C19 | vLLM first service, model revisions, lifecycle and serving config | platform-bootstrap; inference-and-data | Private working endpoint with version/config provenance | P1/P2/P3/P4 | To inventory | Pending; no new evidence |
| C20 | Prefill/decode, batching, continuous batching, PagedAttention | inference-and-data; gpu-systems | Predict and interpret controlled latency/throughput behavior | P2/P4 | To inventory | Pending; no new evidence |
| C21 | Prefix cache, KV cache, long context, concurrency | inference-and-data | Execute memory/concurrency workshop and explain queue/refusal/OOM distinctions | P2/P4 | To inventory | Pending; no new evidence |
| C22 | Replicas versus TP/PP/DP/EP; autoscaling and routing | inference-and-data | Separate one-GPU behavior from true multi-GPU scale-out; test signal suitability | P2/P3/P4 | To inventory | Pending; no new evidence |
| C23 | TTFT, TPOT/inter-token latency, percentiles, throughput, error rate | inference-and-data | Reproducible load protocol; token counts, warmup and sampling defined | P2/P4 | To inventory | Pending; no new evidence |
| C24 | Weights, datasets, checkpoints and model loading | inference-and-data | Map distinct I/O flows; no interchange of training and serving conclusions | P2 | To inventory | Pending; no new evidence |
| C25 | Object/S3, NVMe, NFS/shared/parallel filesystems, cache | inference-and-data | Cold/warm startup and a controlled storage-path comparison | P2/P4 | To inventory | Pending; no new evidence |
| C26 | CPU data loading, GPU starvation, checkpoint bursts, GDS | inference-and-data; operations | Diagnose a data bottleneck; qualify GDS only with actual support | P2/P4 | To inventory | Pending; no new evidence |
| C27 | Model/artifact registry, MLflow, Jupyter, vector DB, Kubeflow | ai-service-delivery; extensions | Explain platform roles; preserve full optional labs, not require every suite | P1/P2/P3 | To inventory | Pending; no new evidence |
| C28 | Service Catalog, ClusterTemplates, MultiClusterService, GitOps | ai-service-delivery | Versioned repeatable service and rollback through supported control mechanisms | P1/P2/P3/P4 | To inventory | Pending; no new evidence |
| C29 | Multi-cluster propagation versus simultaneous GPU services | ai-service-delivery | Label CPU policy proof, sequential reproduction and real GPU concurrency separately | P2/P3/P4 | To inventory | Pending; no new evidence |
| C30 | KOF/Prometheus/DCGM, GPU memory/SM/power, logs and telemetry | operations | Correlate hardware/runtime/service signals with an observed issue | P1/P2/P4 | To inventory | Pending; no new evidence |
| C31 | NCCL/network, queue time, model load and checkpoint metrics | operations | Use workload-appropriate evidence rather than a universal GPU utilization target | P2/P4 | To inventory | Pending; no new evidence |
| C32 | GPU-hours, tokens/sec/GPU, MFU scope, cost/useful-token, usage | operations; inference-and-data | Define accounting assumptions, measurement limits and pricing date | P2/P4 | To inventory | Pending; no new evidence |
| C33 | Identity, tenancy, RBAC, secrets, audit, upgrade/rollback | operations; platform-bootstrap | Access denial, audit and restoration evidence; no unintended public endpoints | P1/P2/P3/P4 | To inventory | Pending; no new evidence |
| C34 | Fault bank and progressive independent diagnosis | operations; all modules | Bounded reversible incidents with symptoms, evidence, repair and restoration | P2/P4 | To inventory | Pending; no new evidence |
| C35 | Customer capstone and knowledge transfer | capstone | Reproducible platform, architecture choices, measured SLOs and new incident | P2/P5 | To inventory | Pending; no new evidence |
| C36 | Stable names, no weeks, complete preservation and source mapping | all modules; migration | Every tracked source file accounted for; 28 historical labs checked against baseline | P0/P1 | To inventory | Pending; no new evidence |
| C37 | Majority hands-on and declining guidance | all modules | Explicit active/passive time and learner evidence; separate teacher solutions | P2/P5 | To inventory | Pending; no new evidence |
| C38 | GPU-1 majority; real GPU-2 distributed path; advanced gates | hardware profiles | Capabilities/versions and permitted costs checked; no abundance guarantee | P2/P4 | To inventory | Pending; no new evidence |
| C39 | Product truth: native/integrated/optional/unsupported | all modules | Every product claim maps to an authoritative versioned source | P3 | To inventory | Pending; no new evidence |
| C40 | Evidence, cleanup and independent reproduction | all modules; migration | Honest statuses, actual test artifacts, no leaks and independent pilot | P1/P4/P5 | To inventory | Pending; no new evidence |

## Completion rule

For each row distinguish first introduction, practical experience and final verification. Some specialized concepts are core while their hardware execution is optional; explicitly record that boundary. A row is not complete because a concept name appears in a README. Mark blocked product steps or hardware tests separately from completed writing.

Core and extension classification is a learning-path decision, not a reason to remove original documents. Source-file conservation is audited separately in `PRESERVATION-MAP.md` and the actual repository inventory.
