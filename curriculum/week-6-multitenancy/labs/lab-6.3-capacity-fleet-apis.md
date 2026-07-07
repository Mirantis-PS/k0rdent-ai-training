# Lab 6.3 — Capacity & Fleet Management APIs

**Domain:** Multi-Tenancy / Fleet Governance / API Design

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Multi-Tenancy / Day-2 Ops | Required | 2.5 hours |

| Previous | Current | Next |
|----------|---------|------|
| [Lab 6.2 — Breakfix API](lab-6.2-breakfix-api.md) | **Lab 6.3 — Capacity & Fleet APIs** | (Lab 6.4 — Data sanitization + at-rest crypto — TBD) |

---

**Duration:** 2.5 hours
**Type:** Design + Hands-on
**Environment:** k0rdent management cluster with at least 2 managed clusters and multiple tenant projects

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: The four governance metrics](#part-1-the-four-governance-metrics)
- [Part 2: Resource Governance API](#part-2-resource-governance-api)
- [Part 3: Resource Discovery API](#part-3-resource-discovery-api)
- [Part 4: Atomic Topology Block reservation](#part-4-atomic-topology-block-reservation)
- [Part 5: Unified Health & Lifecycle](#part-5-unified-health--lifecycle)
- [Part 6: Produce the compliance-pack artifacts](#part-6-produce-the-compliance-pack-artifacts)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

At fleet scale, capacity awareness has to be **programmatic**. Handing off resources via Slack, email, or spreadsheets stops working the day a single cluster handoff happens more than once a week — which is every day on a growing AI fleet.

NVIDIA wants **programmatic** capacity awareness — they will poll, you will publish, the contract is the API. This lab builds that surface.

You already have node lifecycle (Week 4), telemetry export (Lab 5.17), topology (Lab 5.18), and breakfix (Lab 6.2). What's missing is the **fleet view**: which resources exist, which tenant they belong to, what state they're in, and how to reserve them atomically.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Define and emit the four governance metrics with correct semantics
- [ ] Design a Resource Governance API returning the documented per-node field set
- [ ] Stand up a Resource Discovery API that downstream consumers can poll for new/changed capacity
- [ ] Implement atomic topology-block reservations (single-unit grouping of compute + network + storage)
- [ ] Provide unified per-host + aggregate health
- [ ] Produce reference OpenAPI specs and a metric snapshot for your team's documentation

---

## Prerequisites

- Week 4 (KaaS) complete — required for node-pool semantics
- Lab 5.18 (topograph) — required for topology-aware reservation
- Lab 6.2 (Breakfix API) — required (health states overlap)
- `kubectl`, `helm`, `jq`, `openapi-cli`

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| State store | k0rdent CRDs only | CRDs + materialized view in a DB | **CRDs + read-side projection** — CRDs are the source of truth; projection gives sub-second list queries at scale |
| API surface | REST | gRPC | **gRPC primary, REST projection** — downstream consumers will poll at scale; gRPC streaming reduces overhead |
| Reservation semantics | Soft (advisory labels) | Hard (admission webhook rejects conflicts) | **Hard** — atomic allocation is the goal; soft will let workloads sneak in |
| Health aggregation | On every read | Pre-computed in a controller | **Pre-computed** — per-cluster aggregations can touch hundreds of nodes; recompute on event |
| Update push to downstream consumers | Webhook | Consumers poll | **Consumers poll** — simplest contract; webhook can be added as an enhancement |

---

## Part 1: The four governance metrics

Define each precisely. Engineers often conflate them; the metric set won't pass review if the semantics are mushy.

| Metric | Definition | Counts toward |
|--------|------------|---------------|
| **Delivered** | Nodes/GPUs provisioned and *available to NVIDIA*, allocated to a specific account/project/tenant | Capacity NVIDIA has access to right now |
| **Healthy** | Subset of Delivered: functioning and meeting SLA | What NVIDIA can actually use |
| **Reserved** | Resources *allocated to* a specific account/project/tenant (whether or not they're currently in use) | Footprint, billing baseline |
| **In-Use** | Subset of Reserved: currently running a workload | Real-time utilization |

These are not Prometheus metrics with arbitrary names — they're contractually labeled.

Expose them as Prometheus metrics (so KOF + OTel can scrape) with **exact** naming:

```promql
# HELP ncp_fleet_delivered_gpus  GPUs provisioned and available to the account
# TYPE ncp_fleet_delivered_gpus  gauge
ncp_fleet_delivered_gpus{account="nvidia-dgxc-acct-1",project="proj-A",region="us-east-2"} 144

ncp_fleet_healthy_gpus{account="nvidia-dgxc-acct-1",project="proj-A",region="us-east-2"}   142
ncp_fleet_reserved_gpus{account="nvidia-dgxc-acct-1",project="proj-A",region="us-east-2"}  144
ncp_fleet_inuse_gpus{account="nvidia-dgxc-acct-1",project="proj-A",region="us-east-2"}     128
```

Same set with `_nodes` suffix for node-level counts.

Validate invariants in the controller:

```
in_use   ≤ reserved
healthy  ≤ delivered
delivered ≤ reserved   (delivered is what is actually accessible; reserved is the allocation footprint)
```

When invariants break, fire an alert. They break = bug in your fleet controller, not a real condition.

---

## Part 2: Resource Governance API

For each node, the API must return:

```yaml
nodeId: nvr-7f2a-9c3b-2e8a       # stable, persistent (see Lab 2.4)
healthState: Healthy              # Healthy | Unhealthy | Maintenance | Unknown
instanceId: vm-or-bm-instance-7   # virtual workload identifier; null for bare metal
creationTimestamp: 2026-04-12T00:00:00Z
hardwareType: GB200-NVL72-node    # vendor descriptor
gpuCount: 8                       # GPUs on this node (not in NVL domain)
account: nvidia-dgxc-acct-1
project: proj-A
inUse: true                       # true if the node is currently scheduled with a workload
region: us-east-2
```

OpenAPI shape:

```yaml
# resource-governance-api.yaml (excerpt)
paths:
  /v1alpha1/fleet/nodes:
    get:
      parameters:
        - { in: query, name: account, schema: { type: string }, required: false }
        - { in: query, name: project, schema: { type: string }, required: false }
        - { in: query, name: pageToken, schema: { type: string } }
        - { in: query, name: pageSize, schema: { type: integer, default: 100, maximum: 1000 } }
      responses:
        '200':
          content:
            application/json:
              schema:
                type: object
                required: [nodes]
                properties:
                  nodes:
                    type: array
                    items: { $ref: '#/components/schemas/FleetNode' }
                  nextPageToken: { type: string }
components:
  schemas:
    FleetNode:
      type: object
      required: [nodeId, healthState, creationTimestamp, hardwareType, gpuCount, account, region]
      properties:
        nodeId:            { type: string }
        healthState:       { type: string, enum: [Healthy, Unhealthy, Maintenance, Unknown] }
        instanceId:        { type: string, nullable: true }
        creationTimestamp: { type: string, format: date-time }
        hardwareType:      { type: string }
        gpuCount:          { type: integer, minimum: 0 }
        account:           { type: string }
        project:           { type: string, nullable: true }
        inUse:             { type: boolean }
        region:            { type: string }
```

Build the controller as a watch over `Node`, `Cluster` (CAPI), `Machine`, and your own `BreakfixRequest`/`BreakfixEvent` CRs.

---

## Part 3: Resource Discovery API

This is the API that **replaces phone/Slack handoff**. When new capacity comes online (new rack delivered, RMA returned, etc.), it must appear here within the polling SLA agreed with downstream consumers.

Required response fields:

```yaml
resourceId: nvr-7f2a-9c3b-2e8a      # stable
status: available                    # available | reserved | quarantined
reason: gb300-project-fulfillment    # why this capacity is being provided
                                     # examples: gb300-project-fulfillment,
                                     #           breakfix-rma-return-to-cluster,
                                     #           dev-capacity-pre-stage
firstSeen: 2026-05-25T08:00:00Z      # when this resource entered the index
lastChanged: 2026-05-25T10:15:00Z    # last state transition
```

REST shape:

```http
GET /v1alpha1/fleet/discovery?since=2026-05-25T00:00:00Z
{
  "resources": [
    { "resourceId": "nvr-...", "status": "available", "reason": "gb300-project-fulfillment", ... }
  ],
  "nextPageToken": "...",
  "watermark": "2026-05-25T10:15:00Z"   # safe-to-resume cursor for delta polls
}
```

The `watermark` field is what makes this safe for downstream consumers to poll incrementally without missing events. Persist it in the read-side projection.

---

## Part 4: Atomic Topology Block reservation

A **topology block** = a coherent unit of compute + network + storage that shares performance characteristics and security boundaries. Examples:

- 1 × NVL72 rack (72 GPUs sharing one NVLink domain, one leaf-spine, one storage rail)
- 1 × half-rack (36 GPUs, smaller domain)
- N × node group on the same leaf switch

The API must support reserving such a block **atomically** — either all members reserved or none.

Define a CRD:

```yaml
apiVersion: fleet.k0rdent.mirantis.com/v1alpha1
kind: TopologyBlockReservation
metadata:
  name: dgxc-acct1-projA-block-1
spec:
  account: nvidia-dgxc-acct-1
  project: proj-A
  topologyConstraint:
    nvlinkDomain: nvl72-rack-A      # from Lab 5.18 (NVLink Domain API)
    leafSwitch:   leaf-01            # from Lab 5.18 (Backend Switch Fabric API)
  resources:
    - nvr-7f2a-9c3b-2e8a
    - nvr-7f2a-9c3b-2e8b
    - nvr-7f2a-9c3b-2e8c
    # ... full set
  atomic: true                       # required: true (atomic allocation is the contract)
status:
  phase: Reserved                    # Pending | Reserved | Released | Failed
  reservedAt: 2026-05-25T10:00:00Z
  conflicts: []                      # populated only if Failed
```

The admission webhook MUST reject the CR if any member is already reserved or has a `BreakfixRequest.spec.phase != Completed`. Failure mode: refuse the whole reservation; do not partial-allocate.

---

## Part 5: Unified Health & Lifecycle

The health surface has two halves:

**Per-host health (P0)** — real-time API per node:

```http
GET /v1alpha1/fleet/health/{nodeId}
{
  "nodeId": "nvr-7f2a-9c3b-2e8a",
  "overall": "Healthy",
  "components": {
    "gpu":     { "state": "Healthy", "details": "ECC errors: 0" },
    "memory":  { "state": "Healthy" },
    "thermal": { "state": "Healthy", "details": "max 62°C" },
    "nvlink":  { "state": "Healthy", "details": "all 18 links up" },
    "network": { "state": "Degraded", "details": "ib0 retransmit rate elevated" }
  },
  "lastUpdated": "2026-05-25T10:14:50Z"
}
```

**Aggregate health (P2)** — at cluster, node-group, reservation level:

```http
GET /v1alpha1/fleet/health/reservation/dgxc-acct1-projA-block-1
{
  "reservation": "dgxc-acct1-projA-block-1",
  "overall": "Degraded",
  "summary": { "healthy": 70, "unhealthy": 0, "degraded": 2, "total": 72 },
  "incidents": [ { "type": "spine-switch", "id": "spine-02", "impact": "2 nodes degraded path" } ],
  "lastUpdated": "2026-05-25T10:14:55Z"
}
```

Aggregate state is **pre-computed** by a controller, not synthesized on every request — too expensive at fleet scale.

Health sources to fuse:

| Source | Component coverage |
|--------|-------------------|
| DCGM | GPU compute, memory, thermal, NVLink |
| node_exporter | CPU, host memory, disk |
| BMC (Redfish) | Power, fans, baseboard sensors |
| node-problem-detector | Kernel-level signals |
| fabric-manager | NVLink domain health |
| switch telemetry (OTel) | Network path health |

---

## Verification Checklist

- [ ] The four governance metrics emitted with canonical naming and labels
- [ ] Metric invariants enforced (alert on violation)
- [ ] Resource Governance endpoint returns all required fields for every node
- [ ] Resource Governance endpoint supports pagination
- [ ] Resource Discovery endpoint returns a watermark for delta polls
- [ ] Atomic reservation: admission webhook rejects any conflict
- [ ] Reservation succeeds only when *all* members are free
- [ ] Per-host health endpoint responds < 100 ms for cached reads
- [ ] Aggregate health is pre-computed (controller-driven, not on-demand)
- [ ] All endpoints use mTLS
- [ ] All endpoints emit access logs to OTel (per Lab 5.17)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `delivered > reserved` violation alert | Controller race: new node admitted before its account label was set | Add a delay before counting; require the account label to be present |
| Resource Governance list paginates inconsistently | Page tokens not stable (e.g., based on offset) | Switch to opaque resumable tokens (cursor over a stable order) |
| Partial reservation observed | Atomic check happens after some members locked | Move the conflict check inside the admission webhook *before* any mutation |
| Aggregate health drifts from per-host | Controller-recompute cadence too slow | Trigger recompute on every per-host state change, not on a timer |
| Resource Discovery misses new nodes for hours | Discovery controller polls cloud APIs too slowly | Drive discovery from Metal3 / Cluster API events instead of polling |

---

## Key Takeaways

- **The four governance metrics are canonical names.** Don't paraphrase them — downstream tooling will hardcode them.
- **Atomic reservation** means refuse-the-whole-thing on any conflict; never partial-allocate.
- **Watermarking** is what makes incremental polling safe. Without it, consumers have to full-scan.
- **Aggregate health is a controller's job**, not a request-time aggregation. Pre-compute on event.
- **Together these five APIs replace the phone-and-Slack handoff** with a programmatic contract — the foundation of any serious fleet-management story.

---

## Next Lab

Lab 6.4 — Data sanitization + at-rest crypto (planned). Once fleet capacity is observable and reservable, the next concern is what happens to a tenant's data when the resource leaves the tenancy.
