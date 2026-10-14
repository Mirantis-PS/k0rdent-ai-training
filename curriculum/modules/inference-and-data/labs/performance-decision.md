# AI-LAB-06 — A measured performance decision

**Status:** educational draft; no GPU execution claimed. **Profile:** GPU-1 candidate; GPU-2 comparison reuses AI-LAB-04. **Guidance:** low; protocol scaffold, independent conclusion.

## Prerequisites and input state

Known-good serving revision, matching benchmark client, private forwarded endpoint and qualified model/tokenizer. Agree a workload/SLO with the instructor before measuring; no universal latency target is provided.

## Objectives and problem

Recommend a serving configuration for team A under latency, success-rate and cost constraints. Explain why maximum throughput is not the only objective.

## Concept capsule

Read measurement and cost sections of [Data and service performance](../lessons/data-and-service-performance.md). Define TTFT, TPOT, ITL, throughput and allocated GPU-hours in your own words.

## Hypothesis

Choose one factor (concurrency, request rate, context length or qualified cache setting). Predict its effects on tail latency, throughput and errors. Freeze the rest and write a rejection criterion before running.

## Procedure and checkpoints

1. Save server/client versions, model/tokenizer revisions, desired-state hash, hardware, topology and cache state. Use local approved tokenizer files matching the model; no remote-code execution is enabled by this command. Keep the client placement unchanged and note port-forward overhead.
2. Use this bounded workload as a starting protocol, not a customer traffic model. Set MODEL to the exact server model name, TOKENIZER to the approved local path and RESULTS to a private writable evidence directory. Choose a unique RUN label and approved CONCURRENCY. The initial matrix is1,2,4 only where AI-LAB-02 established safe limits. Stop at the instructor's time/budget cap or first material error.

```bash
: "${MODEL:?set served name}" "${TOKENIZER:?set pinned local tokenizer path}"
: "${RESULTS:?set evidence directory}" "${RUN:?set unique run label}"
: "${CONCURRENCY:?set approved concurrency}"
vllm bench serve --backend vllm --host 127.0.0.1 --port 8000 --endpoint /v1/completions --model "$MODEL" --tokenizer "$TOKENIZER" --dataset-name random --random-input-len 128 --random-output-len 64 --seed 7 --num-prompts 100 --num-warmups 5 --request-rate inf --max-concurrency "$CONCURRENCY" --percentile-metrics ttft,tpot,itl,e2el --metric-percentiles 50,95,99 --save-result --save-detailed --result-dir "$RESULTS" --result-filename "$RUN.json"
```

3. Repeat each condition three times and alternate order to expose drift. Record achieved token lengths (EOS may shorten output), successful/failed requests, elapsed time and raw per-request results. Keep random input workload and quality checks distinct; random-token throughput does not establish useful-answer quality.
4. Correlate with server queue/cache metrics and DCGM memory/activity/power where actually available. Record missing metrics instead of assuming a metric name exists. Use source KOF/telemetry guidance for collection, without changing shared exporters. Plot latency against achieved output tokens/s, annotate errors and cache state, and show repeat spread.
5. Compare scaling choices on paper: independent replicas, TP/PP, DP and MoE EP; identify which solves capacity and which throughput, plus routing/autoscaling implications. Use AI-LAB-04 communication evidence to reject unsupported cross-node assumptions.
6. Calculate allocated GPU-hours and output tokens/s/GPU. Define useful tokens and cost scope before computing cost/token; use actual billed amounts only if available, otherwise dated estimates clearly labeled. Explain why MFU cannot be inferred from utilization alone.

## Interpretation

Which configuration satisfies the stated SLO at the required workload? Does a higher throughput result also increase failed requests or p95 TTFT? How much confidence does100 requests give in p99? Which one additional experiment would most improve the recommendation?

## Bounded incident or tradeoff

Instructor presents a candidate result with higher throughput but fewer successful requests or shorter outputs. Reject the unfair comparison and specify a corrected run. Do not overwhelm the server to create a dramatic graph.

## Declarative delivery

Package the winning configuration plus workload, limits, rollout/rollback criteria and alert proposal. If results are unavailable, submit an explicitly unvalidated recommendation and exact missing measurements.

## Restoration and cleanup

Stop load generation and local forwarding, restore baseline configuration if changed, verify first response through a fresh private forward, then stop it. Record all remaining allocations.

## Evidence and acceptance

Raw results, repeat table/plot, workload/SLO, errors, measured versus estimated cost, decision and rejected alternative. No performance improvement claim passes without measured equivalent-workload evidence.

## Provenance and instructor route

Derived from [Lab 5.5 benchmarking](vllm-inference.md), [KOF](../../operations/labs/deploy-kof.md), [telemetry](../../operations/labs/otel-telemetry-export.md), and [vLLM0.14.0 CLI](https://docs.vllm.ai/en/v0.14.0/cli/bench/serve/).

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Learner path](../../../learning-paths/pedagogical-v2.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-06)
