# Week 5 assessment

**Time:** 45 minutes · **Score:** 20 points · **Pass:** 16/20 (80%).
Questions 1–10 are one point each. Questions 11–15 are two points each. For short
answers award one point per required element in the answer key. Attempt before
opening the key. Elective hardware tasks have separate practical evidence and do
not prevent completion of the core assessment.

## Questions

1. Which cluster should receive a ClusterDeployment: management or workload?
2. Does seeing two plain Job pods run concurrently prove gang scheduling?
3. What does KSM service priority resolve?
4. What should express dependencies between MultiClusterServices?
5. Why must catalog GPU Operator values have a `gpu-operator:` parent?
6. Does an EBS RWO StorageClass fulfill an RWX claim across nodes?
7. How much memory do FP16 weights alone need for 70 billion parameters (decimal GB)?
8. Must all ranks call DeepSpeed `save_checkpoint`, or only rank zero?
9. Is `maxSkew: 0` valid for Kubernetes topology spread?
10. Does `NCCL NET/Socket` identify TCP network transport or prove broken NVLink?
11. Describe a two-phase test that proves gang admission under resource pressure.
12. State two requirements for a valid persistent MLflow deployment test.
13. Describe how to constrain a distributed job to one topology domain, and why
    a spread constraint alone does not achieve that.
14. Explain the difference between a persistent exporter queue and its retry limit.
15. State two facts required before a FIPS crypto rejection test can report success.

<details>
<summary>Answer key and scoring</summary>

1. Management cluster.
2. No; capacity and PodGroup membership/minMember must be checked.
3. Competing ownership of the same service release on a target cluster.
4. MCS `spec.dependsOn`, with prerequisite readiness verified.
5. The catalog uses an umbrella chart; direct Helm values omit that extra parent.
6. No.
7. About 140 GB, excluding gradients, optimizer and activations.
8. Every rank, with a consistent checkpoint tag.
9. No; maxSkew must be positive.
10. TCP network transport; it is distinct from intra-node GPU connectivity.
11. One point: request more GPUs than available in a supported gang and prove no
    members start. One point: supply sufficient capacity and prove the full gang runs.
12. One point: a real in-cluster client logs a run/artifact successfully. One point:
    run metadata and artifact retrieval survive a server restart.
13. One point: required affinity selects one explicit domain value for every worker.
    One point: topology spread balances across eligible domains rather than selecting one.
14. One point: file-backed storage can preserve queued data across the covered restart
    scenario. One point: max_elapsed_time limits retry duration, not durable capacity.
15. One point: required tools/provider are installed and configured. One point: a
    known allowed algorithm succeeds and rejection is the expected policy error,
    rather than a missing binary, network failure or unrelated operational error.

</details>

## Practical core rubric

Submit sanitized evidence for all five outcomes: a successful GPU workload, a
supported gang-capacity test, an inference request with latency/throughput settings,
a service configuration verified in the live manifest, and a diagnosed/recovered
GPU failure. Record the commit, versions, hardware and cleanup using the
[lab contract](resources/lab-contract.md). The quiz score and practical completion
are separate: an 80% quiz result does not certify an unexecuted workload.
