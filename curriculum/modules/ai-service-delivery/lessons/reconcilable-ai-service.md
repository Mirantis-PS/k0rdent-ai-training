# A service another engineer can reproduce

Lesson ID: AI-CON-06 · Before AI-LAB-07 · Revisit in AI-CAP-01.

## Find the owner before changing the object

Reconciliation can overwrite a live edit, so trace the workload's owner references and the management configuration that generated it. A service catalog entry packages a deployable service; a ClusterTemplate describes cluster provisioning inputs; MultiClusterService propagates service configuration to selected clusters; GitOps reconciles declared state from an identified source. The preserved k0rdent labs show particular versions; P3 must map the actual k0rdent AI distribution to supported interfaces and lifecycle owners.

Record model revision, immutable image identity, serving arguments, resource requests, scheduling policy, storage references, private access and observability, with credentials as references to separately managed secrets. A declarative submission is complete when an engineer can tell where to change it, what reconciles it, how readiness shows and how to restore the previous state.

## Two clusters do not imply two GPU services

You can check propagation through rendered configuration and status on a CPU cluster, or sequentially on one qualified GPU cluster. That proves propagation or sequential reuse, not simultaneous GPU capacity, cross-zone availability or cross-cluster scheduling. A template can't guarantee provider quota or GPU stock; require bounded provisioning and an explicit no-capacity result, never an expensive automatic fallback.

## Release and rollback

Diff the previous and proposed desired state, and check the model/dtype/kernel compatibility record and secret references before applying. Observe reconciliation, readiness, a private response and the selected SLO. Roll back through the same owning mechanism (reversing a Pod edit may not stick) and confirm the old version serves again. Reverting application configuration differs from downgrading a controller, cluster or driver, which need their own documented procedures.

Match identity and RBAC to operator and tenant roles, and audit who changed desired state without logging tokens or private prompts. Upgrade only through the preserved supported sequence and an approved compatibility gate; the management upgrade and KAI transition stay explicit dependencies.

## Design exercise

Compare a copied Deployment, a catalog-backed service and a template plus propagated service. For each, identify version pin, controller, drift repair, rollback, secrets and evidence, and produce a diagram and decision record for both teams. Mark unknown product support as unresolved and name the exact source that would settle it; don't create a plausible-looking k0rdent AI CRD to fill the gap.

## Source bridge

Reuse [catalog](../labs/service-catalog.md), [templates](../labs/cluster-templates.md), [multicluster services](../labs/multicluster-services.md) and the [compatibility and lifecycle notes](../../../references/compatibility.md).
