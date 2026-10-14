# Data paths and service performance

Lesson ID: AI-CON-05 · Read the relevant section before AI-LAB-05 or AI-LAB-06.

## Separate four data paths

Weights move from a registry, object store or mounted directory into host and device memory. Training datasets feed decoding, transforms and batches. Checkpoints write recoverable training state, often in bursts. Inference KV cache holds attention state while serving. A model file cache can shorten startup without changing steady-state generation; a KV prefix cache can cut repeated prefill without shortening weight downloads.

S3-style object storage speaks object APIs, not POSIX by default. Local NVMe makes a fast disposable cache but needs explicit refill and capacity management. NFS and shared storage give shared paths with their own contention and failure modes. Parallel filesystems target aggregate concurrent IO and need operational investment. Choose by durability, access pattern, working set and measured contention. Slow CPU preprocessing or loaders can starve a GPU, and checkpoint bursts can hit other tenants. GDS is a supported direct-storage path to qualify separately, not a flag that speeds up any storage.

MLflow tracks experiments and artifacts; a model registry tracks versions and lifecycle metadata. Jupyter is an interactive workspace, a vector database serves retrieval and Kubeflow supplies workflow components. Decide which customer need justifies each, and keep artifact identity from development to serving: a notebook's latest file isn't a release.

## Prefill and decode

Prefill processes the input and builds state; decode generates further tokens from it. Continuous batching lets different requests share execution over time. PagedAttention manages cache blocks to cut allocation waste but doesn't lift the cache capacity limit. Prefix reuse helps when identical token prefixes are present and retained, under runtime-specific eligibility; it doesn't make unrelated prompts free or remove decode work. Routing across replicas trades cache locality against load balance.

A serving replica loads its own model and handles requests independently unless the architecture says otherwise. TP/PP shard model execution, DP adds replicas and EP spreads experts for supported MoE serving. Autoscaling needs a meaningful signal, readiness policy and capacity, and more replicas can raise memory use and duplicate caches before latency improves.

## Measure what the customer experiences

TTFT is time to the first output token at your chosen observation boundary. ITL describes gaps between streamed tokens. TPOT is time per output token after the first, with one-token outputs handled as documented. End-to-end latency covers the whole request. Report percentiles, success and error counts, and achieved input and output lengths, since a median can hide the tail. Throughput is completed requests or tokens over elapsed time, with prompt and output tokens kept apart. Put queue time, startup and load time, GPU memory and activity on one timeline.

Freeze model and tokenizer revisions, workload seed, request lengths, rate, concurrency cap, warmup and repetitions, and change one factor at a time. Small samples can't support stable p99 claims, and a throughput gain from rejected requests isn't an improvement. Compare latency at the required successful workload and disclose cache state.

## Cost and efficiency

Allocated GPU-hours = GPU count × allocation wall hours, idle and load periods included within the stated scope. Output tokens/second/GPU compares only across equivalent workload and quality. Cost per useful token divides scoped cost by accepted output tokens, excluding failures under a declared rule. MFU relates model arithmetic to peak device arithmetic under assumptions; don't infer it from DCGM utilization or invent a FLOP count for an unknown model. A faster benchmark can still cost more if capacity idles between jobs.

## Source bridge

Use [inference architecture](../theory/llm-inference-architecture.md), the [vLLM lab](../labs/vllm-inference.md), the [ML platform electives](../../../extensions/ml-platforms/README.md) and [sources](../../../references/pedagogy/sources.md).
