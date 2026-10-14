# Admission, placement and isolation

Lesson ID: AI-CON-03 · Before AI-LAB-03 · Revisit in AI-LAB-07 and AI-CAP-01.

## Follow a pending workload

A request can wait for admission before any Pod exists. After admission, placement depends on devices, node constraints and topology; then device allocation and container runtime setup must succeed, and finally the application must start. Tell the stages apart with queue status, Pod conditions and events, node allocatable resources and process logs. More nodes can't fix an invalid image, and a container memory limit can't repair a queue policy.

Quota bounds an entitlement; borrowing uses otherwise idle capacity under a policy. Fairness concerns allocation over time, while priority and preemption decide which work proceeds in a conflict. Gang scheduling admits a set that must run together, so no training worker starts stranded without its peers. Topology-aware placement seeks communication locality. None of these isolate memory between GPU processes.

## Sharing is not one mechanism

| Choice | Resource behavior to test | Boundary to verify |
|---|---|---|
| Whole device | One allocation reserves a device for the workload | Host access, runtime and tenant policy still matter |
| Time-slicing | Multiple processes compete for device time and memory | No MIG-style hardware memory partition; no proportional performance guarantee |
| MIG | Supported GPUs expose hardware partitions with profile constraints | Exact GPU/profile, reconfiguration and isolation behavior |
| vGPU | Virtualized GPU presentation under a supported stack | Hypervisor, guest driver, licensing and isolation contract |

Queue fairness and hardware isolation aren't substitutes; a team may need both. Changing sharing modes can disrupt running workloads, so the core exercise starts with whole devices and needs an isolated qualified profile for sharing changes.

## Separate the software roles

GPU Operator manages driver, runtime and device components per its configuration. The toolkit connects containers to GPU execution, discovery labels capabilities and a device plugin advertises allocatable extended resources. DRA instead models requests and allocation through DeviceClass, ResourceClaim and ResourceClaimTemplate with a compatible driver: a template creates claims for workloads, and a class selects eligible devices without installing drivers. Don't expose the same devices through competing allocation paths without a documented supported design.

KAI provides scheduling in the preserved course. Kueue handles admission and quotas, and MultiKueue extends admission and dispatch across clusters where supported. Run:ai is a separate optional integration with its own prerequisites and licensing. None of these names proves inclusion in k0rdent AI. Choose one documented policy path, identify its controllers and prove ownership before adding another scheduler.

## Decision exercise

Team A needs predictable interactive latency; team B wants idle capacity for interruptible experiments. Write a policy for nominal quotas, borrowing, priority and recovery after preemption, and explain why one GPU can't prove two whole-device workloads run at once. Diagnose three cases separately: an unadmitted workload, an admitted Pod with an impossible node selector and a running process with GPU OOM. Without a qualified driver, map a DRA request, class and allocation on paper, and don't label it deployment evidence.

## Source bridge

Use [scheduling theory](../theory/gpu-scheduling.md), the [KAI lab](../labs/kai-scheduler.md), the [MIG lab](../labs/mig-partitioning.md) and [sources](../../../references/pedagogy/sources.md).
