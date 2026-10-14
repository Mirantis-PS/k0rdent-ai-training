# Assessment and pilot rubric

This is the proposed P2 assessment contract, not a certification claim. Record analytical, static, runtime and independent-reproduction states separately. The instructor agrees the customer SLO and qualified resource envelope before assessment. No speed or performance number is universal.

| Dimension | Weight | Evidence |
|---|---|---|
| Causal reasoning and decisions |25%| Hypotheses, memory units, alternatives, model/data/communication paths, changed capstone requirement |
| Repeatable declarative delivery |20%| Version/source/owner matrix, private service, reviewed release and same-owner rollback |
| Experiments and diagnosis |25%| Controlled workload, raw errors/results, real GPU-2 collectives/training, new fault discrimination and recovery |
| Operations and resource stewardship |15%| Tenant boundaries, secret handling, telemetry timeline, cost scope, cleanup/retention ownership |
| Handover and transfer |15%| Clear runbook, evidence links, unsupported-claim boundaries, response to changed demand |

Score each dimension0–4: **0** no usable evidence; **1** assertion or copied recipe with major unexplained gaps; **2** partially correct with substantial hints or missing controls; **3** correct, traceable and repeatable within stated scope with minor hints; **4** independent reasoning that tests alternatives, explains limitations and adapts to new demand. Weighted score = sum(weight × score/4). Proposed analytical threshold75/100 must be calibrated by the pilot; do not use it to conceal missing execution.

## Required runtime gates

Full core runtime completion additionally requires: private model response and identity; controlled memory/performance evidence with errors included; queue/placement discrimination; two real GPU workers with NCCL and synchronized training plus actual transport; versioned release and rollback through owner; unfamiliar incident recovery; resource cleanup/explicit retention. Missing P3 interfaces or P4 access makes the dependent gate blocked, regardless of numerical score. Advanced MIG/RDMA/GDS/vGPU/fabric operation earns separate endorsement only with specialized evidence.

Fabricated measurements, concealed failed runs, unsafe cross-tenant mutation or committed credentials require remediation and reassessment; no completion award while unresolved. Honest blocked evidence is not fabrication and can still receive analytical credit. Do not punish a learner for unavailable authorized hardware by encouraging simulation as proof.

## Pilot record for P5

For each learner/lab capture elapsed activity by category, hints by level, failed attempts, unresolved prerequisites, observed allocation time/cost and cleanup. Measure active fraction with the evidence-contract formula and report waiting separately. Compare early command assistance with late independent choices. Have an engineer who did not author the course reproduce the service and runbook; record their commit/environment and any intervention. Revise only the affected material and repeat affected checks. A document review or static checker cannot satisfy independent execution.
