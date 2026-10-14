# Admission, placement and isolation

Lesson ID: AI-CON-03. Read before AI-LAB-03; revisit in AI-LAB-07 and AI-CAP-01.

## Follow a pending workload

A request can wait for admission before any Pod is placed. After admission, placement still depends on devices, node constraints and topology. Device allocation and container runtime setup must then succeed. Finally the application must start. Distinguish these stages with queue status, Pod conditions/events, node allocatable resources and process logs. Adding nodes cannot fix an invalid image; changing a container memory limit cannot repair a queue policy.

Quota bounds an entitlement. Borrowing allows use of otherwise idle capacity under a policy. Fairness concerns allocation over time; priority and preemption select which work proceeds when resources conflict. Gang scheduling admits a set that must run together, useful when one stranded training worker cannot progress. Topology-aware placement seeks appropriate communication locality. None of these imply memory isolation between GPU processes.

## Sharing is not one mechanism

| Choice | Resource behavior to test | Boundary to verify |
|---|---|---|
| Whole device | One allocation reserves a device for the workload | Host access, runtime and tenant policy still matter |
| Time-slicing | Multiple processes compete for device time and memory | No MIG-style hardware memory partition; no proportional performance guarantee |
| MIG | Supported GPUs expose hardware partitions with profile constraints | Exact GPU/profile, reconfiguration and isolation behavior |
| vGPU | Virtualized GPU presentation under a supported stack | Hypervisor, guest driver, licensing and isolation contract |

Do not compare queue fairness and hardware isolation as if they were substitutes. A team may require both. Changing sharing modes can disrupt existing workloads, so the core exercise uses whole devices first; sharing changes require an isolated qualified profile.

## Separate the software roles

GPU Operator manages driver/runtime/device-related components according to its configuration. The toolkit connects containers to GPU execution; discovery labels capabilities; a device plugin advertises allocatable extended resources. DRA instead models requests and allocation through DeviceClass, ResourceClaim and ResourceClaimTemplate with a compatible driver. A claim template creates claims for workloads; a class selects eligible devices, but does not install drivers. Do not expose the same devices through competing allocation paths without a documented supported design.

KAI provides scheduling capabilities in the preserved course. Kueue handles workload admission and quotas; MultiKueue extends admission/dispatch across clusters in supported configurations. Run:ai is a distinct optional integration with its own prerequisites and licensing. These names are not proof of k0rdent AI product inclusion. Choose one documented policy path, identify its controllers and prove ownership before adding another scheduler.

## Decision exercise

Team A needs predictable interactive latency; team B wants idle capacity for interruptible experiments. Write a policy for nominal quotas, permitted borrowing, priority and recovery after preemption. Explain why one GPU cannot simultaneously prove two whole-device workloads run. Diagnose three cases separately: unadmitted workload, admitted Pod with impossible node selector, running process with GPU OOM. Map a DRA request/class/allocation on paper if a qualified driver is absent; do not label that deployment evidence.

## Source bridge

Use [scheduling theory](../theory/gpu-scheduling.md), [KAI lab](../labs/kai-scheduler.md), [MIG lab](../labs/mig-partitioning.md), and [sources](../../../references/pedagogy/sources.md).
