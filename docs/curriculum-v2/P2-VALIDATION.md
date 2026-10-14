# P2 validation and handover

Date: 2026-10-14. Branch: codex/curriculum-v2-pedagogy. Base: 314353e3010c6811e3811eea2ceff53a8b49d188. Content commit: f2fafb3. This report is committed separately from course authoring. **P2 educational draft complete; runtime compatibility/execution and independent reproduction are not claimed.**

## Delivered

Seven just-in-time lessons; nine stable-ID learner labs including the new capstone; a stateful learner path; separate instructor solutions; nine bounded fault designs; weighted assessment rubric; evidence/session/measurement templates; primary source ledger; forty introduction/practice/revisit/check mappings; and a small real-GPU NCCL/DDP candidate fixture with five CPU-only input-guard tests. Original labs and guides remain available through source bridges. Later product and hardware gates are scoped in each affected lab rather than replaced with invented commands.

The learner path connects first private response, memory/concurrency, queue/sharing decisions, real two-worker communication/training, storage/cache, measured performance, declarative release and incident recovery. Scaffolding decreases toward changed customer requirements and an unfamiliar capstone incident. Active-learning fraction, duration, assistance and actual cost remain pilot measurements, with a defined logging method rather than asserted results.

## Checks actually run

| Check | Result and scope |
|---|---|
| Python scripts/check-curriculum-migration.py | PASS: 144 original sources preserved, 1,569 original code fences checked; 1,820 tracked local links/images/anchors valid. Original content digests unchanged. |
| Validation-venv Python scripts/check-curriculum.py | PASS: 134 files, zero errors; YAML/Python and existing shell fixtures/local targets. No cluster/CRD execution. |
| Same checker on curriculum/instructor, curriculum/learning-paths, curriculum/references/pedagogy and P2-COVERAGE.md | PASS: 11 files, zero errors. |
| Python scripts/check-pedagogy.py | PASS: 9 unique labs, 7 lessons, 40 rows; required lab sections and new Bash fence syntax. Existence/syntax checks are not a pedagogy-quality or runtime certificate. |
| Node scripts/check-mermaid.mjs | PASS: 55 Mermaid blocks. |
| Python unittest discovery in curriculum/examples/pedagogical-v2/tests | PASS: 5 tests for world size, bounded steps and divisible/bounded batch. No PyTorch/CUDA/NCCL execution. |
| Validation-venv unittest discovery in curriculum/examples/tests and curriculum/examples/telemetry/tests | PASS: 7+7 existing regression tests. |
| git diff --check / staged diff check | PASS. |

The existing suites initially failed import under the system Python because PyYAML was absent; rerunning in the already configured /tmp/k0rdent-v2-validation-20261014 environment with PyYAML 6.0.2 passed. No project dependency or runtime pin was changed to fix that local harness issue. New fixture syntax was parsed by the curriculum checker; its input validation is importable without torch. Its actual collective, training, timeout and performance behavior still requires GPU qualification.

Manual review covered state/cleanup order, source bridges, actual coverage section anchors, learner/instructor separation, bounded faults, explicit output/evidence states, no new product schema claims, and the source baseline version transitions. Existing source bytes, infrastructure, workflows and existing example implementations were preserved. No remote resources were inspected or changed; ignored local notes/config/credentials were retained.

## Exact blockers and next evidence

| Gate | Missing input | Affected work | Required next evidence |
|---|---|---|---|
| P3-SOURCES | Target k0rdent AI distribution/version and authoritative installation, API/catalog/template, lifecycle, scheduling/device, identity and telemetry sources | Product-native commands/ownership, supported integration matrix and rollback | Versioned feature/source/owner matrix; replace only dependent unresolved steps with documented procedures |
| P4-GPU-1 | Authorized environment/budget and qualified small model/image/dtype/driver/GPU combination | First response, memory, queue, cache, benchmark, release and incident runtime proof | Exact environment card, actual logs/metrics/results, cost scope and cleanup; source four-A10G baseline stays intact |
| P4-GPU-2 | Two real single-GPU workers and approved private rendezvous/network | NCCL/DDP correctness, timing and actual cross-node transport | Both rank logs, node/device allocation, synchronized parameters, collective results, transport evidence and teardown |
| Specialized profiles | Verified MIG/vGPU/NVLink/RDMA/EFA/RoCE/GDR/GDS access and compatibility | Specialized execution/endorsements | Separate real hardware evidence; analytical exercises do not substitute |
| P5 pilot | Independent learner and agreed review | Reproduction, active-time target, duration, help and cost calibration | Independent replay and measured pilot record |

No GPU benchmark, cloud provision, product integration execution, push, PR or merge was performed. The next work is gated P3/P4 qualification, not an implicit instruction to incur costs. The complete V2 release remains unfinished until those gates and P5 are satisfied.
