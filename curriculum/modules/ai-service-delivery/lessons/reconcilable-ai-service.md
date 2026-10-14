# A service another engineer can reproduce

Lesson ID: AI-CON-06. Read before AI-LAB-07; revisit in AI-CAP-01.

## Find the owner before changing the object

A live edit can be overwritten by reconciliation. Trace workload object owner references and the management configuration that generated them. A service catalog entry packages a deployable service; a ClusterTemplate describes cluster provisioning inputs; MultiClusterService propagates service configuration to selected clusters. GitOps reconciles declared desired state from an identified source. These are complementary roles, not synonyms. The preserved k0rdent labs demonstrate particular versions; P3 must map the actual k0rdent AI distribution to supported interfaces and lifecycle ownership.

Record model revision, immutable image identity, serving arguments, resource requests, scheduling policy, storage references, private access and observability. Credentials remain references to separately managed secrets. A declarative submission is complete only when an engineer can identify where to change it, what reconciles it, how readiness is observed and how the previous state is restored.

## Two clusters do not imply two GPU services

Propagation can be checked through rendered configuration and status on a CPU cluster, or sequentially on one qualified GPU cluster. That proves propagation or sequential reuse, not simultaneous GPU capacity, availability across zones or cross-cluster scheduling. Separate those evidence claims. A template cannot guarantee provider quota or GPU stock. Require bounded provisioning and an explicit no-capacity result rather than an expensive automatic fallback.

## Release and rollback

Diff the previous and proposed desired state. Check the model/dtype/kernel compatibility record and secret references before applying. Observe reconciliation, readiness, a private response and the selected service SLO. Roll back through the same owning mechanism; reversing a Pod edit may be temporary. Validate that the old version serves again. Distinguish reverting application configuration from downgrading a controller, cluster or driver; the latter need their own documented procedures and are outside a routine service experiment.

Identity and RBAC should match operator and tenant roles. Audit who changed desired state without logging tokens or private prompts. Upgrade only through the preserved supported sequence and a separately approved compatibility gate. The course's management upgrade and KAI transition remain explicit dependencies, not hidden side effects of the new labs.

## Design exercise

Compare a copied Deployment, a catalog-backed service, and a template plus propagated service. For each, identify version pin, controller, drift repair, rollback, secrets and evidence. Produce a diagram and decision record for team A and team B. Mark unknown product support as unresolved and specify exactly which source would settle it. Do not create a plausible-looking k0rdent AI CRD to fill that gap.

## Source bridge

Reuse [catalog](../labs/service-catalog.md), [templates](../labs/cluster-templates.md), [multicluster services](../labs/multicluster-services.md), and the [prerequisite record](../../../../docs/curriculum-v2/migration/PREREQUISITES.md).
