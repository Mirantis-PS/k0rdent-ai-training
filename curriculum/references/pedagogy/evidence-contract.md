# Evidence and execution contract

## Status and authority

This revision is an educational draft: no procedure or candidate fixture has run on a GPU. Analytical work shows reasoning, not deployment. Track drafted → static-checked → documented-compatible → executed → independently-reproduced as separate states. A failed or blocked attempt keeps its evidence and doesn't count as a pass.

## Entry gate for every runtime lab

The instructor provides an approved environment card before a learner runs commands. It records: repository SHA; lab ID; management and workload contexts; namespace and resource owner; product distribution, version and authoritative source; controller, chart and image versions and image digest; Kubernetes/k0s; GPU model, count, memory and topology; driver, CUDA, framework and NCCL; model and tokenizer revision, dtype/quantization and license/access; storage and cache; admission policy; private endpoint; region/AZ; budget and maximum allocation duration. Record unknowns explicitly and stop only the dependent step. No production tenants, public unauthenticated endpoints or credentials in committed evidence.

**P3-SOURCES:** the authoritative k0rdent AI distribution, interfaces, feature boundaries and ownership are missing; the [product-source request](sources.md#product-source-requests-for-p3) lists what is needed. Until then, source k0rdent procedures remain historical routes and k0rdent AI-specific deployment and rollback are blocked. Don't invent commands or treat upstream support as product support.

**P4-GPU:** no authorized GPU environment or cost ceiling exists for this revision. GPU-1 is a candidate one-device profile, not a qualified replacement for the source four-A10G g5.12xlarge baseline. GPU-2 needs two real single-GPU workers on different nodes for cross-node transport evidence; one machine with two devices shows local NCCL only. CPU mode allows analysis, configuration review and calculations. Specialized MIG, vGPU, NVLink/NVSwitch, RDMA/EFA, RoCE, GPUDirect RDMA and GDS each need independently verified hardware, software and access.

Keep the source pins and warnings in the [compatibility notes](../compatibility.md). They are recorded baselines, not fresh certifications; qualifying a small model or runtime, or changing any pin, belongs to P3/P4.

## Submission packet

Create a private local evidence directory outside tracked course content, starting from the [session template](session-template.yaml) and [measurements template](measurements.csv). Add:

1. The hypothesis, the single variable you will change and the stop condition, written before the experiment.
2. Sanitized desired-state diff, exact commands, configuration hashes and timestamps.
3. Raw logs and results, with estimates and measured values kept apart; include errors, not just successes.
4. Interpretation, an alternative explanation, the next discriminating test, and product ownership and source decisions.
5. Before/after resource inventory, restoration check, retained-resource owner and expiry, GPU allocation hours and cost scope.

Never fill missing measurements with the lessons' hypothetical numbers. Keep credentials, kubeconfigs, model access tokens, private prompts and cloud account identifiers out of Git, and check evidence by hand before sharing: a redacted log can still hold a secret in a URL.

## Common operating rules

Run shell examples from the repository root unless stated otherwise, and resolve angle-bracket variables and environment-card fields first. Give every Kubernetes mutation an explicit workload context and namespace. Stop at the instructor's deadline, or on unbounded retries, unexpected provisioning, loss of tenant isolation or impact on unrelated workloads. Keep a known-good declarative revision and know its reconciler before changing anything.

Runtime acceptance needs both observable checkpoints and restored state. Keep the management cluster for later labs. Use only the scoped cleanup after each exercise, and the original end-of-path teardown once evidence is saved. Foundation audit follows the management upgrade and precedes child-cluster teardown; see the [compatibility and lifecycle notes](../compatibility.md).

## Time and cost measurement

Log start, end and one category per activity (active manipulation, active diagnosis/analysis, passive reading, waiting or instructor assistance) without double-counting concurrent waiting and analysis. Active fraction = (manipulation + diagnosis/analysis) / all course activity time; report waiting separately, plus a second fraction excluding unavoidable waiting. The 70–80% target applies to the measured pilot, not to this draft. Record help level (command supplied, hint, independent), attempts and abandoned paths; pilot evidence decides where to shorten reading or move analysis into waiting time.

Report allocated GPU-hours as count × wall time, idle periods included, plus other retained infrastructure. Price estimates need dated rates and assumptions, kept apart from observed billing. No lab implies spending authorization.
