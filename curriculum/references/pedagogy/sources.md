# Technical sources and derivation ledger

Consulted 2026-10-14. These primary references inform concepts and API syntax; they do not qualify the course runtime or establish k0rdent AI support. Original course labs remain the deployment provenance. Each new lesson/lab links its source bridge; preserved historical labels may differ from canonical paths.

| Source | Used for | Boundary |
|---|---|---|
| [vLLM v0.14.0 benchmark CLI](https://docs.vllm.ai/en/v0.14.0/cli/bench/serve/) | AI-LAB-02/06 benchmark options and output contract | Match client/server version; measured results still required |
| [vLLM v0.14.0 prefix caching](https://docs.vllm.ai/en/v0.14.0/features/automatic_prefix_caching/) | AI-CON-05 and AI-LAB-05 cache comparison | Cache eligibility/configuration depends on actual model/runtime |
| [vLLM v0.14.0 parallelism](https://docs.vllm.ai/en/v0.14.0/serving/parallelism_scaling/) | AI-CON-04/05 scaling decisions | No new GPU-count or topology support promise |
| [GPU Operator25.3 sharing](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/25.3.0/gpu-sharing.html) | AI-CON-03 time-slicing versus isolation | Operator configuration and metrics attribution require qualification |
| [Kubernetes1.35 DRA](https://v1-35.docs.kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/) | AI-CON-03 device request/allocation model | Versioned Kubernetes feature documentation, not proof of a product driver |
| [PyTorch2.5.1 distributed source documentation](https://github.com/pytorch/pytorch/blob/v2.5.1/docs/source/distributed.rst) | AI-LAB-04 process group/collective API | API reference version; does not change source course image pins |
| [PyTorch2.5.1 DDP API source](https://github.com/pytorch/pytorch/blob/v2.5.1/torch/nn/parallel/distributed.py) | AI-LAB-04 gradient synchronization and device binding | Candidate fixture requires selected image/GPU qualification |
| [NCCL collective semantics](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/usage/collectives.html) | AI-CON-04 rank arithmetic | Living page displayed2.32.3; not a required runtime version |

## Product-source requests for P3

Supply the target k0rdent AI distribution and version, installation/upgrade guide, API/schema and catalog references, controller ownership/lifecycle diagrams, supported model-serving and GPU allocation integrations, identity/tenancy boundaries, telemetry/metering capabilities and rollback procedures. For each feature record native/integrated/optional/unsupported with a source; unresolved remains a valid state until evidence exists. Existing k0rdent Enterprise source labs cannot establish all these claims.

## Advanced study without false runtime credit

Use preserved [communication theory](../../modules/distributed-ai/theory/gpu-communication.md), [RDMA](../../modules/distributed-ai/labs/rdma-multi-cloud.md), [MIG](../../modules/gpu-allocation/labs/mig-partitioning.md), [topology](../../modules/gpu-systems/labs/topograph-nvlink-topology.md), [TensorRT](../../extensions/advanced-inference/labs/tensorrt-llm.md), [Run:ai](../../extensions/licensed-orchestration/labs/runai-gpu-orchestration.md) and [ML platforms](../../extensions/ml-platforms/README.md). They retain original prerequisites and validation history. Analyze their manifests and expected observations now; specialized execution and vendor claims need their own versioned source and hardware evidence.
