# Data paths and service performance

Lesson ID: AI-CON-05. Read the relevant section before AI-LAB-05 or AI-LAB-06.

## Separate four data paths

Weights move from a registry/object store or mounted directory into host and device memory. Training datasets feed decoding, transforms and batches. Checkpoints write recoverable training state, often in bursts. Inference KV cache stores attention state while serving requests. A model file cache can shorten startup without changing steady-state token generation; a KV prefix cache can reduce repeated prefill without reducing weight download time.

S3-style object storage is accessed through object APIs, not automatically as a POSIX filesystem. Local NVMe can provide a fast disposable cache but needs explicit refill and capacity management. NFS/shared storage offers shared paths with its own contention/failure characteristics. Parallel filesystems target aggregate concurrent IO and require operational investment. Choose based on durability, access pattern, working set and measured contention. CPU preprocessing or a slow loader can starve an idle GPU. Checkpoint bursts can interfere with other tenants. GDS is a supported direct-storage data path to qualify separately, not a flag that makes arbitrary storage fast.

MLflow can track experiments/artifacts; a model registry tracks model versions and lifecycle metadata. Jupyter is an interactive workspace; a vector database serves retrieval; Kubeflow supplies workflow/platform components. Decide which customer need requires each integration. Preserve artifact identity across development and serving, rather than assuming that a notebook's latest file is a deployable release.

## Prefill and decode

Prefill processes the input sequence and builds state. Decode generates subsequent tokens using that state. Continuous batching allows work from different requests to share execution over time. PagedAttention manages cache blocks to reduce allocation waste; it does not remove the cache capacity limit. Prefix reuse helps when identical token prefixes are present and retained, with runtime-specific eligibility. It does not make unrelated prompts free or eliminate decode work. Routing across replicas can trade cache locality against load balance.

A serving replica loads its own model and handles requests independently unless a specific architecture says otherwise. TP/PP shard model execution; DP adds replicas; EP distributes experts for supported MoE serving. Autoscaling needs a meaningful signal, readiness policy and capacity. More replicas can increase memory consumption and duplicate caches before they improve latency.

## Measure what the customer experiences

TTFT measures time to the first output token at the chosen observation boundary. ITL describes gaps between streamed tokens. TPOT summarizes time per output token after the first, with handling for one-token outputs documented. End-to-end latency includes the whole request. Report percentiles, success/error counts and achieved input/output lengths; a median can hide the tail. Throughput is completed requests or tokens divided by elapsed time, with prompt/output tokens distinguished. Record queue time, startup/load time, GPU memory and activity on the same timeline.

Freeze model/tokenizer revisions, workload seed, request lengths, request rate, concurrency cap, warmup and repetitions. Change one factor at a time. Small samples cannot justify stable p99 claims. An apparent throughput gain from rejected requests is not an improvement. Compare latency at the required successful workload and disclose cache state.

## Cost and efficiency

Allocated GPU-hours = GPU count × allocation wall hours, including idle/load periods in the stated scope. Output tokens/second/GPU is only comparable for equivalent workload and quality. Cost per useful token divides scoped cost by accepted output tokens, excluding failures under a declared rule. MFU relates model arithmetic to peak device arithmetic under assumptions; do not infer it from DCGM utilization or invent a FLOP count for an unknown model. A faster benchmark can still cost more if capacity sits idle between jobs.

## Source bridge

Use [inference architecture](../theory/llm-inference-architecture.md), [vLLM lab](../labs/vllm-inference.md), the preserved [ML platform electives](../../../extensions/ml-platforms/README.md) and [sources](../../../references/pedagogy/sources.md).
