# AI-LAB-07 — Declarative release and rollback

> **Course step 19 of 21.** [Previous step](../../inference-and-data/labs/performance-decision.md) · [Course checklist](../../../README.md) · [Next step](../../operations/labs/diagnose-restore.md)

**Status:** [draft](../../../README.md#check-runtime-readiness) · **Profile:** CPU review; GPU-1 candidate for service proof · **Guidance:** low, you choose and justify the delivery route

## Prerequisites and input state

- AI-LAB-06 decision and known-good service revision.
- Read-only access to installed catalog and template schemas and their ownership.

Where a k0rdent AI interface is unknown (P3-SOURCES), continue the design review from sources and invent no resources.

## Objectives and problem

Turn team A's service into a versioned release another engineer can reproduce, showing drift ownership, a bounded change and rollback through one owner.

## Concept capsule

Read [A reconcilable AI service](../lessons/reconcilable-ai-service.md) and note what catalog, cluster template, service propagation and GitOps each own.

## Hypothesis

Predict which object and status change when the owning desired state changes, and what happens to a manual edit of a generated object. Define readiness and rollback acceptance first.

## Procedure and checkpoints

1. Inspect the preserved [catalog](service-catalog.md), [ClusterTemplate](cluster-templates.md) and [MultiClusterService](multicluster-services.md) examples and installed schemas read-only, and build a release folder: sanitized desired state, version manifest, source references, ownership diagram, README. Reuse the approved source route rather than chaining controllers.
2. Record model and image revisions, requests, scheduler, storage, private access, secret references, telemetry and limits from AI-LAB-06. Classify each product capability (native, integrated, optional, unsupported, unresolved) with evidence; unresolved entries block only their own steps.
3. Pick a small reversible serving change qualified in earlier labs. Review its rendered diff and schema, deploy through the approved owner, then check reconciliation, readiness, first response and the short workload.
4. Roll back through the same owner and prove the old configuration and response are back; if the integration route is unavailable, peer-review the plan and record runtime blocked. A manual kubectl edit doesn't prove product rollback.
5. Design propagation to a second cluster (selectors, versions, secrets, status, failure boundaries). Render against a CPU target, or reuse one GPU target sequentially if authorized, and label the evidence; simultaneous multi-cluster GPU serving needs separate capacity and live proof.
6. Write operator and tenant RBAC and [audit](../../operations/labs/api-audit-logging.md) requirements, the secret lifecycle, and how service rollback differs from a management [upgrade](../../operations/labs/upgrade-k0rdent.md), keeping the preserved upgrade and KAI sequence. Take source 5.12 status.config inputs from the installed template, not a guessed schema.

## Interpretation

- Where is the source of truth, and which controller reverts drift?
- What survives an application rollback?
- What separates propagation evidence from simultaneous capacity?
- Which exact P3 source do you still need?

## Bounded incident or tradeoff

Before apply, find the missing secret reference or wrong cluster selector in a candidate by inspecting its rendered configuration and targets. Execute the failure only in an isolated, instructor-approved disposable release.

## Declarative delivery

The release folder is the deliverable: reviewed configuration, version/source matrix, ownership, validation, rollout, rollback and cleanup, with unresolved product fields explicit and non-executable.

## Restoration and cleanup

Restore the original revision and verify the response, remove only your propagation targets and releases after checking ownership, and record any secondary cluster or volume still allocated. Keep management for the incident lab.

## Evidence and acceptance

- Release folder with actual schema and source references.
- Before, after and rollback observations, or exact blockers.
- Identity and audit rationale.
- Propagation claim boundary.

A rendered manifest passes review, not deployment.

## Provenance and instructor route

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-07)
