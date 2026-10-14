# Bounded fault bank

Instructor only during diagnosis. Before injection record lab namespace, owner, known-good revision, exact changed field/file, deadline and restoration check in a private fault card. Use one fault at a time. No shared operator/driver/fabric mutation, secret exposure, capacity provisioning or deliberate unbounded OOM. Stop immediately if another tenant is affected. If a safe isolated route is absent, use a clearly labeled hypothetical case for analysis only.

| ID | Entry state and isolated injection | Symptoms and useful discriminator | Minimum correction and restoration | Bound |
|---|---|---|---|---|
| F01 | Healthy private service; wrong Service name in learner’s local forward command | Forward fails; real Service/Pod remains healthy | Correct only local name; prove response; close forward | One attempt,2min |
| F02 | Saved learner serving config; request exceeds approved context limit | Input rejection versus CUDA allocation error; inspect response and server log | Reduce input within configured limit; replay valid request | One invalid request; no load burst |
| F03 | Disposable finite job; impossible node selector in copied template | Pod scheduling event, allocatable GPU exists, queue may already admit | Restore template selector; replace only disposable job; verify finish/delete | Pending2min; job deadline5min |
| F04 | Isolated test queue with saved policy; request exceeds learner entitlement | Admission wait/status before placement, unlike F03 | Restore/request valid entitlement through owner; verify finite job and policy restoration |2min wait; no shared quota change |
| F05 | Disposable serving copy; nonexistent model/cache path, no real credentials changed | Mount or model-load error before readiness; distinguish image pull | Restore approved path through owner; response check; remove disposable copy/cache | Readiness5min |
| F06 | Two-worker disposable job; start rank 0 only | Missing peer/rendezvous stall, no complete rank set | Stop incomplete run; launch both; collect valid NCCL/DDP evidence; release workers | Outer5min deadline mandatory |
| F07 | Private benchmark result review; compare runs with unequal successful output tokens | Higher throughput claim conflicts with lengths/errors | Reject comparison; rerun equivalent workload if authorized | Analysis first; one bounded repeat |
| F08 | Learner-owned release review; wrong target selector or missing secret reference in candidate | Rendered targets/reference differ from intended release | Correct desired state before apply; if safely executed, restore previous release and response | Pre-apply default;5min if disposable |
| F09 | Dedicated disposable cache only; restart once with empty model cache | Slow startup/download, steady-state response later normal | Restore retained approved cache reference; verify phase timings and response; remove only disposable storage | One restart; agreed startup deadline |

## Fault card and debrief

Record: ID, learner lab, symptom to reveal, exact scope, precondition checks, injected delta, expected observation, maximum duration, stop trigger, restore revision/command and acceptance. The table is a design, not evidence that any fault was injected. Use actual source-owned procedures for runtime changes; no invented product API.

After diagnosis reveal the card. Compare the learner’s hypotheses with the actual fault, explain what evidence was decisive, and identify an alternative cause with similar symptoms. Save sanitized before/during/after evidence and the final resource inventory. For capstone choose a different layer (client, admission, placement, loading, distributed startup, measurement or release) than the learner previously diagnosed. Do not score speed over safe scope and causal reasoning.
