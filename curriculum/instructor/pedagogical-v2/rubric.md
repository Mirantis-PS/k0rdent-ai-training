# Assessment and pilot rubric

This proposed assessment contract is not a certification. Record analytical, static, runtime and independent-reproduction states separately. Agree the customer SLO and qualified resource envelope before assessment; no speed or performance number is universal.

| Dimension | Weight | Evidence |
|---|---|---|
| Causal reasoning and decisions | 25% | Hypotheses, memory units, alternatives, model/data/communication paths, changed capstone requirement |
| Repeatable declarative delivery | 20% | Version/source/owner matrix, private service, reviewed release and same-owner rollback |
| Experiments and diagnosis | 25% | Controlled workload, raw errors/results, real GPU-2 collectives/training, new fault discrimination and recovery |
| Operations and resource stewardship | 15% | Tenant boundaries, secret handling, telemetry timeline, cost scope, cleanup/retention ownership |
| Handover and transfer | 15% | Clear runbook, evidence links, unsupported-claim boundaries, response to changed demand |

Score each dimension 0–4: **0** no usable evidence; **1** assertion or copied recipe with major unexplained gaps; **2** partially correct with substantial hints or missing controls; **3** correct, traceable and repeatable within stated scope with minor hints; **4** independent reasoning that tests alternatives, explains limitations and adapts to new demand. Weighted score = sum(weight × score/4). The proposed analytical threshold of 75/100 needs pilot calibration and must not hide missing execution.

## Required runtime gates

Full core runtime completion also requires: a private model response and identity; controlled memory and performance evidence, errors included; queue/placement discrimination; two real GPU workers with NCCL, synchronized training and actual transport; a versioned release and rollback through its owner; unfamiliar-incident recovery; and resource cleanup or explicit retention. Missing P3 interfaces or P4 access block the dependent gate whatever the numerical score. Advanced MIG, RDMA, GDS, vGPU or fabric operation earns a separate endorsement only with specialized evidence.

Fabricated measurements, concealed failed runs, unsafe cross-tenant changes or committed credentials require remediation and reassessment, with no completion award until resolved. Honest blocked evidence isn't fabrication and can still earn analytical credit; don't push learners toward simulation as proof when authorized hardware is unavailable.

## Pilot record for P5

For each learner and lab, capture elapsed activity by category, hints by level, failed attempts, unresolved prerequisites, observed allocation time and cost, and cleanup. Measure active fraction with the evidence-contract formula and report waiting separately, comparing early command assistance with late independent choices. Have an engineer who didn't author the course reproduce the service and runbook, recording their commit, environment and any intervention. Revise only the affected material and repeat the affected checks; a document review or static checker can't satisfy independent execution.
