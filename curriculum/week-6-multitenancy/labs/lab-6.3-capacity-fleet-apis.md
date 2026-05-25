# Lab 6.3 — Capacity & Fleet Management APIs

| Domain | Tag | NVIDIA Req IDs |
|--------|-----|----------------|
| Multi-Tenancy / Fleet Governance | 🟢 NCP | CAP01 (Governance metrics), CAP02 (Resource Governance API), CAP03 (Resource Discovery API), CAP04 (Logical Compartmentalization + Atomic Topology Block), CAP05 (Unified Health & Lifecycle APIs) |

> **Compliance pack artifact targets:** `artifacts/CAP01-governance-metrics.json`, `artifacts/CAP02-resource-governance-api.yaml`, `artifacts/CAP03-discovery-api.yaml`, `artifacts/CAP04-reservation-spec.yaml`, `artifacts/CAP05-unified-health.yaml`

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Multi-Tenancy / Day-2 Ops | Required (NCP track) | 2.5 hours |

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
- [Part 1: The four governance metrics (CAP01)](#part-1-the-four-governance-metrics-cap01)
- [Part 2: Resource Governance API (CAP02)](#part-2-resource-governance-api-cap02)
- [Part 3: Resource Discovery API (CAP03)](#part-3-resource-discovery-api-cap03)
- [Part 4: Atomic Topology Block reservation (CAP04)](#part-4-atomic-topology-block-reservation-cap04)
- [Part 5: Unified Health & Lifecycle (CAP05)](#part-5-unified-health--lifecycle-cap05)
- [Part 6: Produce the compliance-pack artifacts](#part-6-produce-the-compliance-pack-artifacts)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

A standout sentence from the v2.3 guide, under CAP03:

> *"It is not acceptable to have capacity be 'handed' to DGXC through a phone, Slack or email message."*

NVIDIA wants **programmatic** capacity awareness — they will poll, you will publish, the contract is the API. This lab builds that surface.

You already have node lifecycle (Week 4), telemetry export (Lab 5.17), topology (Lab 5.18), and breakfix (Lab 6.2). What's missing is the **fleet view**: which resources exist, which tenant they belong to, what state they're in, and how to reserve them atomically.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Define and emit the four CAP01 governance metrics with correct semantics
- [ ] Design a CAP02-conformant Resource Governance API returning the required per-node field set
- [ ] Stand up a CAP03 Resource Discovery API that DGXC can poll for new/changed capacity
- [ ] Implement CAP04 atomic topology-block reservations (single-unit grouping of compute + network + storage)
- [ ] Provide CAP05 unified per-host + aggregate health
- [ ] Produce Req-ID-stamped artifacts for the compliance pack

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
| API surface | REST | gRPC | **gRPC primary, REST projection** — DGXC will poll at scale; gRPC streaming reduces overhead |
| Reservation semantics | Soft (advisory labels) | Hard (admission webhook rejects conflicts) | **Hard** — CAP04 specifies *atomic* allocation; soft will let workloads sneak in |
| Health aggregation | On every read | Pre-computed in a controller | **Pre-computed** — per-cluster aggregations can touch hundreds of nodes; recompute on event |
| Update push to DGXC | Webhook | DGXC polls | **DGXC polls** — the v2.3 wording is explicit; webhook can be added as an enhancement |

---

## Part 1: The four governance metrics (CAP01)

Define each precisely. Engineers often conflate them; CAP01 won't pass review if the semantics are mushy.

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

## Part 2: Resource Governance API (CAP02)

For each node, the API must return:

```yaml
nodeId: nvr-7f2a-9c3b-2e8a       # stable, persistent (per CNP08)
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
# CAP02-resource-governance-api.yaml (excerpt)
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

## Part 3: Resource Discovery API (CAP03)

This is the API that **replaces phone/Slack handoff**. When new capacity comes online (new rack delivered, RMA returned, etc.), it must appear here within the polling SLA agreed with DGXC.

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

The `watermark` field is what makes this safe for DGXC to poll incrementally without missing events. Persist it in the read-side projection.

---

## Part 4: Atomic Topology Block reservation (CAP04)

A **topology block** = a coherent unit of compute + network + storage that shares performance characteristics and security boundaries. Examples:

- 1 × NVL72 rack (72 GPUs sharing one NVLink domain, one leaf-spine, one storage rail)
- 1 × half-rack (36 GPUs, smaller domain)
- N × node group on the same leaf switch

CAP04 says the API must support reserving such a block **atomically** — either all members reserved or none.

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
    nvlinkDomain: nvl72-rack-A      # from Lab 5.18 / NET02
    leafSwitch:   leaf-01            # from Lab 5.18 / NET01
  resources:
    - nvr-7f2a-9c3b-2e8a
    - nvr-7f2a-9c3b-2e8b
    - nvr-7f2a-9c3b-2e8c
    # ... full set
  atomic: true                       # required: true (CAP04 hard requirement)
status:
  phase: Reserved                    # Pending | Reserved | Released | Failed
  reservedAt: 2026-05-25T10:00:00Z
  conflicts: []                      # populated only if Failed
```

The admission webhook MUST reject the CR if any member is already reserved or has a `BreakfixRequest.spec.phase != Completed`. Failure mode: refuse the whole reservation; do not partial-allocate.

---

## Part 5: Unified Health & Lifecycle (CAP05)

CAP05 has two halves:

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

## Part 6: Produce the compliance-pack artifacts

```bash
# 1. CAP01 metric snapshot
curl -s http://localhost:9090/api/v1/query?query=ncp_fleet_delivered_gpus \
  | jq . > CAP01-governance-metrics.json

# 2. CAP02 OpenAPI spec
openapi-cli bundle api/fleet/openapi.yaml -o CAP02-resource-governance-api.yaml

# 3. CAP03 OpenAPI spec
openapi-cli bundle api/discovery/openapi.yaml -o CAP03-discovery-api.yaml

# 4. CAP04 reservation example + admission policy
kubectl get topologyblockreservations.fleet.k0rdent.mirantis.com -o yaml > CAP04-reservation-examples.yaml
kubectl get validatingwebhookconfigurations -l app=fleet-controller -o yaml > CAP04-admission-policy.yaml

# 5. CAP05 OpenAPI spec + sample health response
openapi-cli bundle api/health/openapi.yaml -o CAP05-unified-health.yaml
```

---

## Verification Checklist

- [ ] The four CAP01 metrics emitted with exact naming and labels
- [ ] CAP01 invariants enforced (alert on violation)
- [ ] CAP02 endpoint returns all required fields for every node
- [ ] CAP02 supports pagination
- [ ] CAP03 endpoint returns watermark for delta polls
- [ ] CAP04 atomic reservation: admission webhook rejects any conflict
- [ ] CAP04 reservation succeeds only when *all* members are free
- [ ] CAP05 per-host health endpoint responds < 100 ms for cached reads
- [ ] CAP05 aggregate health is pre-computed (controller-driven, not on-demand)
- [ ] All endpoints use mTLS (per SEC13)
- [ ] All endpoints emit access logs to OTel (per Lab 5.17)
- [ ] Artifacts CAP01–CAP05 produced and Req-ID-stamped

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `delivered > reserved` violation alert | Controller race: new node admitted before its account label was set | Add a delay before counting; require the account label to be present |
| CAP02 list paginates inconsistently | Page tokens not stable (e.g., based on offset) | Switch to opaque resumable tokens (cursor over a stable order) |
| CAP04 partial reservation observed | Atomic check happens after some members locked | Move the conflict check inside the admission webhook *before* any mutation |
| CAP05 aggregate health drifts from per-host | Controller-recompute cadence too slow | Trigger recompute on every per-host state change, not on a timer |
| CAP03 misses new nodes for hours | Discovery controller polls cloud APIs too slowly | Drive discovery from Metal3 / Cluster API events instead of polling |

---

## Key Takeaways

- **The four governance metrics are contractual names.** Don't paraphrase them.
- **CAP04 atomic** means refuse-the-whole-thing on any conflict; never partial-allocate.
- **CAP03 watermarking** is what makes incremental polling safe. Without it, DGXC has to full-scan.
- **Aggregate health is a controller's job**, not a request-time aggregation. Pre-compute on event.
- **CAP01-05 together replace the phone-and-Slack handoff** with a programmatic contract. That contract is also the surface a compliance audit reads first.

---

## Next Lab

Lab 6.4 — Data sanitization + at-rest crypto (planned). Once fleet capacity is observable and reservable, the next concern is what happens to a tenant's data when the resource leaves the tenancy.
