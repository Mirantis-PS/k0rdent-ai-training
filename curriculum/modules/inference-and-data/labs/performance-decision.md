# AI-LAB-06 — A measured performance decision

> **Course step 18 of 21.** [Previous step](storage-cache.md) · [Course checklist](../../../README.md) · [Next step](../../ai-service-delivery/labs/declarative-release.md)

**Status:** [draft](../../../README.md#check-runtime-readiness) · **Profile:** GPU-1 candidate; GPU-2 comparison reuses AI-LAB-04 · **Guidance:** low, protocol scaffold, your own conclusion

## Prerequisites and input state

- Known-good serving revision, matching benchmark client and private forwarded endpoint.
- Qualified model and tokenizer.
- Workload and SLO agreed with the instructor beforehand (there is no universal latency target).

## Objectives and problem

Recommend team A's serving configuration under latency, success-rate and cost limits; peak throughput alone isn't the goal.

## Concept capsule

Read the measurement and cost sections of [Data and service performance](../lessons/data-and-service-performance.md) and define TTFT, TPOT, ITL, throughput and allocated GPU-hours in your own words.

## Hypothesis

Pick one factor (concurrency, request rate, context length or a qualified cache setting), predict its effect on tail latency, throughput and errors, freeze the rest and write a rejection criterion first.

## Procedure and checkpoints

1. Save server, client, model and tokenizer revisions, desired-state hash, hardware, topology and cache state. Use the approved local tokenizer (no remote code) and fixed client placement, and note port-forward overhead.
2. Start from this bounded workload, not a customer traffic model ([vLLM 0.14.0 CLI](https://docs.vllm.ai/en/v0.14.0/cli/bench/serve/)). Set MODEL, TOKENIZER, RESULTS (a private directory), a unique RUN and a CONCURRENCY of 1, 2 or 4 within AI-LAB-02's safe limits. Stop at the time or budget cap or the first material error.

    ```bash
    : "${MODEL:?set served name}" "${TOKENIZER:?set pinned local tokenizer path}"
    : "${RESULTS:?set evidence directory}" "${RUN:?set unique run label}"
    : "${CONCURRENCY:?set approved concurrency}"
    vllm bench serve --backend vllm --host 127.0.0.1 --port 8000 --endpoint /v1/completions --model "$MODEL" --tokenizer "$TOKENIZER" --dataset-name random --random-input-len 128 --random-output-len 64 --seed 7 --num-prompts 100 --num-warmups 5 --request-rate inf --max-concurrency "$CONCURRENCY" --percentile-metrics ttft,tpot,itl,e2el --metric-percentiles 50,95,99 --save-result --save-detailed --result-dir "$RESULTS" --result-filename "$RUN.json"
    ```

3. Repeat each condition three times in alternating order. Record achieved token lengths (EOS may shorten output), successes and failures, elapsed time and raw per-request results; random-token throughput says nothing about answer quality.
4. Correlate with server queue and cache metrics and DCGM memory, activity and power where available, recording missing metrics as missing. Collect via the source [KOF](../../operations/labs/deploy-kof.md) and [telemetry](../../operations/labs/otel-telemetry-export.md) setup without changing shared exporters, and plot latency against achieved output tokens/s with errors, cache state and repeat spread.
5. On paper, compare replicas, TP/PP, DP and MoE EP for capacity, throughput, routing and autoscaling, using AI-LAB-04 evidence to reject unsupported cross-node assumptions.
6. Calculate allocated GPU-hours and output tokens/s/GPU. Define useful tokens and cost scope before cost per token, using billed amounts or labeled dated estimates. Why can't utilization alone give MFU?

## Interpretation

- Which configuration meets the SLO at the required workload?
- Does the higher-throughput result also raise failures or p95 TTFT?
- How much confidence do 100 requests give in p99?
- Which extra experiment would most improve the recommendation?

## Bounded incident or tradeoff

The instructor shows a result with higher throughput but fewer successes or shorter outputs. Reject the unfair comparison and specify a corrected run; don't overload the server for effect.

## Declarative delivery

Package the chosen configuration with workload, limits, rollout and rollback criteria and an alert proposal, or, without results, an explicitly unvalidated recommendation naming the missing measurements.

## Restoration and cleanup

Stop load and forwarding, restore any changed baseline configuration, verify the first response through a fresh private forward, then stop it and record remaining allocations.

## Evidence and acceptance

- Raw results, repeat table and plot.
- Workload, SLO and errors.
- Measured versus estimated cost.
- Decision and one rejected alternative.

No performance claim passes without measured equivalent-workload evidence.

## Provenance and instructor route

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-06)
