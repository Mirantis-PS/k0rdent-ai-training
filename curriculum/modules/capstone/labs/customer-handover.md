# AI-CAP-01 — Customer handover under changed demand

> **Course step 21 of 21.** [Previous step](../../operations/labs/diagnose-restore.md) · [Course checklist](../../../README.md) · [Finish or pause](../../../README.md#finish-or-pause)

**Status:** [draft](../../../README.md#check-runtime-readiness) · **Profile:** GPU-1 candidate plus the linked GPU-2 proof · **Guidance:** independent, no command recipe

## Prerequisites and input state

- AI-LAB-01–08 evidence, versioned release and known-good state.
- A new requirement and an unseen incident from the instructor, with scope, budget and deadline.

A missing GPU-2 proof leaves the core runtime requirement incomplete.

## Objectives and problem

Deliver a repeatable two-team service, defend an infrastructure decision under changed demand and restore an unfamiliar failure without a command recipe.

## Concept capsule

Revisit the seven capsules as needed, and explain memory, scheduling, data and communication paths, performance and ownership in the customer's terms.

## Hypothesis

Before changing anything, predict the limiting resource under the new demand and a measurement that could overturn your recommendation, and log the prediction.

## Procedure and checkpoints

Team A now needs longer approved-document context; team B wants a predictable batch window. The instructor sets input, concurrency and SLO values within the qualified profile, a storage or queue constraint and one unfamiliar fault. You get a requirement card, not a solution.

Plan and execute, within bounds:

- request and desired-state trace;
- memory calculation with explicit assumptions;
- admission and isolation policy;
- cold loading versus KV reuse;
- equivalent successful-work measurement;
- replicas or sharding, justified by communication evidence;
- release and rollback through the owner;
- diagnosis of the new incident;
- resource accounting and cleanup.

Recheck earlier artifacts against the new requirements before reusing them. Include the two-worker NCCL/DDP evidence with its actual transport and limits; without GPU-2 access, show the pending proof and don't claim full runtime completion. Compare one advanced option (MIG, DRA, RDMA/GDS or MoE parallelism) with the simpler baseline, naming its hardware and product gates rather than deploying it.

Hand the release and runbook to another engineer for review; the instructor may ask you to defend a rejected option or spot an unsupported product claim.

## Interpretation

- Which earlier assumption changed?
- What did you refuse to conclude?
- Why does your configuration suffice for both teams?
- What is still unknown about k0rdent AI support or hardware, and how will you hand over a blocked requirement honestly?

## Bounded incident or tradeoff

The instructor picks a fault at a different root-cause layer from AI-LAB-08, within the fault bank's limits. Diagnose without the hidden solution and restore within scope; a source-example log never counts as live evidence.

## Declarative delivery

A customer packet, scored with the [rubric](../../../instructor/pedagogical-v2/rubric.md): requirement and SLO, architecture and ownership map, immutable version/source matrix, memory and capacity decision, workload and results, queue and storage rationale, release and rollback, incident runbook, GPU-2 proof, blockers, costs and resource inventory.

## Restoration and cleanup

After review, restore or tear down learner resources with the original lifecycle procedures. Check GPU nodes, volumes, Services/load balancers and secondary clusters as well as Pods, keep only owned resources with an expiry, and capture audit evidence before child teardown.

## Evidence and acceptance

Reasoning and execution score separately. Full runtime completion needs a private working service, a valid measured comparison, real two-worker proof, durable recovery and cleanup; missing access or P3 sources show as blocked evidence, never substitutes.

## Provenance and instructor route

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-cap-01)
