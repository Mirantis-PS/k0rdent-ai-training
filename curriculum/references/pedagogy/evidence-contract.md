# P2 evidence and execution contract

## Status and authority

P2 is an educational draft. Procedures and candidate fixtures have not been executed on GPUs for this revision. An analytical exercise is useful evidence of reasoning, not proof of deployment. Use drafted → static-checked → documented-compatible → executed → independently-reproduced as separate states. A failed or blocked attempt retains its evidence and is not counted as a pass.

## Entry gate for every runtime lab

The instructor must provide an approved environment card before a learner runs commands. Record repository SHA; lab ID; management/workload contexts; namespace and resource owner; product distribution/version and authoritative source; controller/chart/image versions and image digest; Kubernetes/k0s; GPU model/count/memory/topology; driver/CUDA/framework/NCCL; model/tokenizer revision, dtype/quantization and license/access; storage/cache; admission policy; private endpoint; region/AZ; budget and maximum allocation duration. Explicitly record unknown and stop only the dependent step. No production tenants, public unauthenticated endpoints or credentials in committed evidence.

**P3-SOURCES:** Missing authoritative k0rdent AI distribution, supported interfaces, feature boundaries and ownership. Needed: versioned install/lifecycle documentation, supported catalog/template schemas, scheduling/device integration, identity and telemetry documentation. Until supplied, source k0rdent procedures remain historical routes, and k0rdent AI-specific deployment/rollback is blocked. Do not invent commands or imply that upstream support equals product support.

**P4-GPU:** No authorized GPU environment or cost ceiling is supplied for this revision. GPU-1 is a candidate one-device profile, not a qualified replacement for the source four-A10G g5.12xlarge baseline. GPU-2 requires two actual single-GPU workers; use different nodes for cross-node transport evidence. One machine with two devices can demonstrate local NCCL but cannot satisfy cross-node evidence. CPU mode allows analysis, configuration review and calculations only. Specialized MIG, vGPU, NVLink/NVSwitch, RDMA/EFA, RoCE, GPUDirect RDMA and GDS need independently verified hardware/software/access gates.

Preserve source pins: k0rdent Enterprise 1.3.1→1.3.2 via the existing upgrade lab; k0s 1.35.4+k0s.0; KOF 1.6.0; GPU Operator 25.3.0 with source Ubuntu22.04/k0s runtime settings; KAI 0.12.10→0.14.0 in its scheduler lab; vLLM v0.14.0. These are recorded source baselines, not fresh compatibility certifications. Preserve the source warning about GPU Operator25.10/runc and TensorRT's distinct driver prerequisite. Qualifying a small model/runtime or changing any pin belongs to P3/P4.

## Submission packet

Create a private local evidence directory outside tracked course content. Start from [session template](session-template.yaml) and [measurements template](measurements.csv). Add:

1. Hypothesis before the experiment, intended single changed variable and stop condition.
2. Sanitized desired-state diff, exact commands, configuration hashes and timestamps.
3. Raw logs/results and a table separating estimates from measured values; include errors, not just successful samples.
4. Interpretation, alternative explanation, next discriminating test, and product ownership/source decisions.
5. Before/after resource inventory, restoration check, retained resource owner and expiry, GPU allocation hours and cost scope.

Never fill missing measurements with the hypothetical numbers in the lessons. Keep credentials, kubeconfigs, model access tokens, private prompts and cloud account identifiers out of Git. Check evidence manually before sharing; a redacted log may still contain a secret in a URL.

## Common operating rules

All shell examples run from the repository root unless stated otherwise. Variables in angle brackets or environment-card fields must be resolved before execution. Use explicit workload context and namespace in every Kubernetes mutation. Stop at the instructor's deadline or on unbounded retries, unexpected provisioning, loss of tenant isolation or unrelated workload impact. Preserve a known-good declarative revision and identify its reconciler before changing anything.

Runtime acceptance requires both observable checkpoints and restored state. Keep the management cluster for subsequent labs. Do not run whole-source cleanup after each derived exercise: use only the scoped cleanup below, then the original end-of-path teardown after evidence is saved. Foundation audit follows the management upgrade and precedes child-cluster teardown. See [prerequisite record](../../migration/PREREQUISITES.md).

## Time and cost measurement

For each activity log start/end and one category: active manipulation, active diagnosis/analysis, passive reading, waiting, or instructor assistance. Do not double-count concurrent waiting and analysis. Compute active fraction = (manipulation + diagnosis/analysis) / all course activity time; also report waiting separately and a second fraction excluding unavoidable waiting. The 70–80% target applies to the measured pilot, not an assertion about this draft. Record help level (command supplied, hint, independent), attempts and abandoned paths. Use pilot evidence to shorten reading or move analysis into waiting periods.

Report allocated GPU-hours with count × wall time, including idle periods, plus other retained infrastructure. Price estimates require dated rates and assumptions; observed billing is separate. No default spend authorization is implied by a lab.
