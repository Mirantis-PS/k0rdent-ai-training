# AI-LAB-07 — Declarative release and rollback

> **Course step 19 of 21.** [Previous step](../../inference-and-data/labs/performance-decision.md) · [Course checklist](../../../README.md) · [Next step](../../operations/labs/diagnose-restore.md). Follow this sequence when older lab-number references differ.


**Status:** educational draft; no GPU execution claimed. **Profile:** CPU review; GPU-1 candidate for service proof. **Guidance:** low; choose and justify a delivery route.

## Prerequisites and input state

AI-LAB-06 decision and known-good service revision. Read-only access to actual catalog/template schemas and ownership. P3-SOURCES blocks any unknown k0rdent AI interface; continue source-based design review without inventing resources.

## Objectives and problem

Turn team A’s working service into a versioned release another engineer can reproduce. Demonstrate drift ownership, a bounded change and rollback through the same owner.

## Concept capsule

Read [A reconcilable AI service](../lessons/reconcilable-ai-service.md). Identify what catalog, cluster template, service propagation and GitOps each own.

## Hypothesis

Predict which object/status changes when the owning desired state changes, and what happens to a manual edit of a generated object. Define readiness and rollback acceptance before deployment.

## Procedure and checkpoints

1. Inspect the preserved catalog, ClusterTemplate and MultiClusterService examples and the installed schemas read-only. Create a release folder in your evidence workspace with sanitized desired state, version manifest, source references, ownership diagram and README. Reuse the approved source route; do not combine independent controllers just to include every tool.
2. Record model/image revisions, resource requests, scheduler selection, storage references, private access, secret references, telemetry and limits from the performance decision. Mark each product capability native/integrated/optional/unsupported/unresolved with evidence. Unresolved entries block only their executable product steps.
3. Compare known-good and candidate revisions. Choose a small reversible serving change already qualified in earlier labs. Review the rendered diff and schema before using the approved owner’s deployment procedure. Observe reconciliation status, workload readiness and first response; repeat the agreed short workload check.
4. Restore the previous revision through the same owner and prove the old configuration and response are back. If the integration route is unavailable, conduct a peer review of the release/rollback plan and record runtime blocked. Do not claim a manual kubectl edit proves product rollback.
5. Design propagation to a second cluster: identify selectors, versions, secrets, status and failure boundaries. Review/render against a CPU target or reuse one GPU target sequentially if authorized. Label this propagation or sequential reuse evidence. Simultaneous multi-cluster GPU operation needs separate capacity and live evidence.
6. Write operator/tenant RBAC and audit requirements, secret lifecycle, service rollback versus management upgrade distinction, and the preserved management upgrade/KAI sequence. Resolve source 5.12 status.config inputs from the installed template, not a guessed schema.

## Interpretation

Where is the source of truth? Which controller would revert drift? What survives an application rollback? What evidence distinguishes propagation from simultaneous capacity? Which exact P3 source is still needed?

## Bounded incident or tradeoff

Review a candidate with a missing secret reference or wrong cluster selector before apply. Find it through rendered configuration and intended-target inspection. Only an isolated, instructor-approved disposable release may execute the failure; do not route it to unrelated clusters.

## Declarative delivery

The release folder is the deliverable: reviewed configuration, version/source matrix, ownership, validation, rollout, rollback and cleanup. Keep product-specific unresolved fields explicit and non-executable.

## Restoration and cleanup

Restore the original service revision and verify response. Remove only learner-created propagation targets/releases after checking ownership. Retain management resources for incident work; record any secondary cluster or volume still allocated.

## Evidence and acceptance

Release folder, actual schema/source references, before/after/rollback observations or exact blockers, identity/audit rationale and propagation claim boundary. A rendered manifest alone passes review, not deployment.

## Provenance and instructor route

Derived from [Lab 5.2](service-catalog.md), [Lab 5.12](cluster-templates.md), [Lab 1.7](multicluster-services.md), [upgrade](../../operations/labs/upgrade-k0rdent.md) and [audit](../../operations/labs/api-audit-logging.md).

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Learner path](../../../README.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-07)
