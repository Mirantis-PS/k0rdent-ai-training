# Memory and topology for an operator

Lesson ID: AI-CON-02. Read immediately before AI-LAB-02; revisit in AI-LAB-04 and AI-LAB-06.

## Inventory before tuning

CPU RAM feeds preprocessing, loading and orchestration. GPU memory holds tensors used by device kernels; free host RAM cannot simply substitute for device capacity. CUDA is the software execution environment; the host driver, container libraries and framework must work together. Tensor Cores accelerate particular matrix operations and supported formats. Their presence does not guarantee that a model or kernel uses them. Record GPU name, count, memory, driver, runtime and allocatable device resources independently.

HBM and GDDR describe memory technologies, not interchangeable performance promises. Capacity determines whether an allocation fits. Bandwidth is bytes transferred per second. FLOPs per second describe arithmetic rate under stated conditions. A workload can have low arithmetic utilization because it is waiting for memory, data, scheduling or communication. Compare workload phases and timings; a single utilization percentage cannot identify the bottleneck.

PCIe connects devices; SXM is a module form factor, not a transport benchmark. NUMA associates CPUs and memory with locality domains. GPU/NIC locality can change communication paths. NVLink provides GPU interconnects on supported systems; NVSwitch connects supported NVLink topologies. A cloud instance name is not evidence of the actual path. Capture topology and distinguish same-node peer access from cross-node network transport.

## Budget device memory

Use bytes throughout, then divide by 2^30 for GiB. Approximate weight storage as parameter count × bytes per parameter; include scales/metadata for quantized weights. Runtime workspace, activations, CUDA graphs and allocator reserves also consume memory. Training adds gradients and optimizer state; an inference budget cannot be reused as a training budget.

For a conventional full-attention KV cache, estimate bytes as 2 × layers × KV heads × head dimension × cached tokens × bytes per cache element × concurrent sequences. This is a reasoning model, not a universal allocator formula: grouped-query attention uses KV heads rather than query heads, sliding-window/hybrid models differ, and parallelism, padding and block allocation affect the actual footprint.

**Hypothetical arithmetic, not hardware measurements:** 3 billion parameters at two bytes occupy 6 billion bytes, about 5.59 GiB. With 32 layers, 8 KV heads, dimension 128 and two-byte cache elements, one cached token costs 131,072 bytes. A 4,096-token sequence uses about 0.5 GiB of KV; four use about 2 GiB. Add measured workspace and headroom before deciding whether the service fits. A server may preallocate a cache pool, so device-memory usage need not increase linearly as requests arrive.

## Precision is a compatibility choice

FP32, FP16 and BF16 have different precision/range tradeoffs; FP16 and BF16 both use two bytes but are not equivalent numerical formats. FP8/FP4 and integer quantization reduce representation size under particular algorithms. Weight format, activation format, KV dtype and accumulation dtype are separate choices. Smaller files alone do not prove faster execution or acceptable quality. Complete a matrix of model revision, quantization method, GPU, driver, runtime kernel support and quality check. Mark unsupported or unknown combinations rather than trying every flag.

## Decision exercise

Estimate the hypothetical budget above, then change context to 8,192 and concurrency to eight. Which term changes? Predict startup failure versus request-time pressure. Use a real inventory in AI-LAB-02 to replace assumptions; if hardware is unavailable, submit the arithmetic as analytical evidence only. Reject the assertion that doubling advertised time-sliced devices doubles memory.

## Source bridge

Derived from [GPU setup](../labs/gpu-cluster-setup.md), [topology](../labs/topograph-nvlink-topology.md), [vLLM memory background](../../inference-and-data/labs/vllm-inference.md) and [sources](../../../references/pedagogy/sources.md).
