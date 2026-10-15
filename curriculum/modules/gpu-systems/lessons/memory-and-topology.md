# Memory and topology for an operator

Lesson ID: AI-CON-02 · Immediately before AI-LAB-02 · Revisit in AI-LAB-04 and AI-LAB-06.

## Inventory before tuning

CPU RAM feeds preprocessing, loading and orchestration; GPU memory holds the tensors device kernels use, and free host RAM can't stand in for it. CUDA is the execution environment, so host driver, container libraries and framework must line up. Tensor Cores accelerate certain matrix operations and formats, but their presence doesn't mean a model or kernel uses them. Record GPU name, count, memory, driver, runtime and allocatable device resources separately.

HBM and GDDR name memory technologies; check each GPU's actual capacity and bandwidth instead of inferring them from the label. Capacity decides whether an allocation fits; bandwidth is bytes moved per second; FLOP/s is arithmetic rate under stated conditions. Low arithmetic utilization can mean the workload is waiting on memory, data, scheduling or communication, so compare phases and timings: one utilization percentage can't identify the bottleneck.

PCIe connects devices; SXM names a module form factor, which says nothing about interconnect speed. NUMA ties CPUs and memory to locality domains, and GPU/NIC locality changes communication paths. NVLink links GPUs on supported systems and NVSwitch connects NVLink topologies. An instance name isn't evidence of the actual path: capture topology and tell same-node peer access from cross-node transport.

## Budget device memory

Work in bytes and divide by 2^30 for GiB. Weights take roughly parameter count × bytes per parameter, plus scales and metadata for quantized weights. Runtime workspace, activations, CUDA graphs and allocator reserves add more. Training adds gradients and optimizer state, so an inference budget isn't a training budget.

For conventional full-attention KV cache, estimate bytes as 2 × layers × KV heads × head dimension × cached tokens × bytes per element × concurrent sequences. The formula estimates scale; the runtime allocates differently. Grouped-query attention counts KV heads, not query heads; sliding-window and hybrid models differ; and parallelism, padding and block allocation change the real footprint.

**Hypothetical arithmetic, not hardware measurements:** 3 billion parameters at two bytes occupy 6 billion bytes, about 5.59 GiB. With 32 layers, 8 KV heads, dimension 128 and two-byte cache elements, one cached token costs 131,072 bytes. A 4,096-token sequence uses about 0.5 GiB of KV; four use about 2 GiB. Add measured workspace and headroom before deciding whether the service fits. A server may preallocate its cache pool, so device memory needn't grow linearly with requests.

## Precision is a compatibility choice

FP32, FP16 and BF16 trade precision against range; FP16 and BF16 both use two bytes but behave differently. FP8, FP4 and integer quantization shrink representation under specific algorithms. Weight, activation, KV and accumulation dtypes are separate choices, and a smaller file proves neither speed nor quality. Fill a matrix of model revision, quantization method, GPU, driver, kernel support and quality check, marking unsupported or unknown combinations instead of trying every flag.

## Decision exercise

Redo the hypothetical budget with context 8,192 and concurrency eight. Which term changes? Predict startup failure versus request-time pressure. Replace assumptions with a real inventory in AI-LAB-02; without hardware, the arithmetic counts as analytical evidence only. Reject the claim that doubling advertised time-sliced devices doubles memory.

## Source bridge

Derived from [GPU setup](../labs/gpu-cluster-setup.md), [topology](../labs/topograph-nvlink-topology.md), [vLLM memory background](../../inference-and-data/labs/vllm-inference.md) and [sources](../../../references/pedagogy/sources.md).
