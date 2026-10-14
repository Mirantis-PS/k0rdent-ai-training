# AI-CAP-01 — Customer handover under changed demand

**Status:** educational draft; no GPU execution claimed. **Profile:** GPU-1 candidate plus required linked GPU-2 proof. **Guidance:** independent; no command recipe.

## Prerequisites and input state

AI-LAB-01–08 evidence, versioned service release and known-good state. Missing GPU-2 proof remains an incomplete core runtime requirement. Instructor supplies a new requirement and incident not used in the learner’s previous lab, plus explicit scope, budget and deadline.

## Objectives and problem

Deliver a repeatable service for two teams, defend an infrastructure decision under changed demand, and restore an unfamiliar failure. Demonstrate transfer rather than replaying a command sequence.

## Concept capsule

Revisit the seven capsules only as needed. Explain model memory, scheduling, data/communication paths, service performance and ownership in the customer’s terms.

## Hypothesis

Before changing the service, predict the limiting resource under the new demand and identify a measurement that could overturn your recommendation. Commit the prediction to your evidence log.

## Procedure and checkpoints

The customer now needs longer approved-document context for team A while team B requests a predictable batch window. The instructor selects actual input/concurrency/SLO values inside the qualified profile, a storage/queue constraint and one unfamiliar fault. You receive a requirement card, not a solution.

Produce and execute a bounded plan that: traces the request and desired state; calculates memory with explicit assumptions; chooses admission/isolation policy; distinguishes cold loading from KV reuse; measures equivalent successful work; selects replicas versus sharding with communication evidence; releases and rolls back through the owner; diagnoses the new incident; and accounts for resources and cleanup. Reuse earlier artifacts only after checking them against the changed requirements.

Include the two-worker NCCL/DDP evidence and explain its actual transport and limitations. If GPU-2 access is absent, present the exact pending proof and do not claim full runtime completion. Compare an advanced option (MIG, DRA, RDMA/GDS or MoE parallelism) with the simpler baseline, identifying hardware/product gates instead of deploying it by name.

Hand the release and runbook to another engineer for review. Independent execution is a P5 gate; a review in this draft is not an independently reproduced course. The instructor may ask you to defend one rejected option or identify an unsupported product claim.

## Interpretation

Which earlier assumption changed? What did you refuse to conclude from the evidence? Why is the chosen configuration sufficient for both teams? What remains unknown about k0rdent AI support or hardware behavior? How would you hand over a blocked requirement honestly?

## Bounded incident or tradeoff

Instructor chooses a fault with a different root-cause layer from AI-LAB-08, within the fault bank’s boundaries. The learner must diagnose without the hidden solution and restore within the agreed scope. A source-example log is never presented as live evidence.

## Declarative delivery

Customer packet: requirement/SLO, architecture and ownership map, immutable version/source matrix, memory and capacity decision, workload/results, queue/storage rationale, release/rollback, incident runbook, GPU-2 proof, blockers, costs and resource inventory. Use the [rubric](../../../instructor/pedagogical-v2/rubric.md).

## Restoration and cleanup

After evidence review, restore or tear down learner resources using the original lifecycle procedures and ownership boundaries. Verify GPU nodes, volumes, Services/load balancers and secondary clusters as well as Pods. Keep only explicitly assigned resources with owner/expiry. Audit work must precede child teardown.

## Evidence and acceptance

Score reasoning and actual execution separately. Full runtime completion needs private successful service, valid measured comparison, real two-worker proof, durable recovery and cleanup. Any missing access or P3 source appears as blocked evidence, not a substitute result.

## Provenance and instructor route

New capstone derived from the continuous customer scenario and [legacy capstone](capstone.md), with all original broader-program material retained. This AI-specific assessment does not replace specialized endorsements.

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Learner path](../../../learning-paths/pedagogical-v2.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-cap-01)
