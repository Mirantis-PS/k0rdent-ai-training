# Lab 6.2 — Breakfix API Design & Implementation

**Domain:** Multi-Tenancy / Operations / Lifecycle / API Design

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Multi-Tenancy / Day-2 Ops | Required | 3 hours |

| Previous | Current | Next |
|----------|---------|------|
| (Lab 6.1 — Tenancy model — TBD) | **Lab 6.2 — Breakfix API** | Lab 6.3 — Capacity & Fleet APIs |

---

**Duration:** 3 hours
**Type:** Design + Hands-on
**Environment:** k0rdent management cluster + at least one managed cluster with ≥3 GPU nodes + Metal3-managed bare metal (or simulated `BareMetalHost`)

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: The Breakfix surface NVIDIA expects](#part-1-the-breakfix-surface-nvidia-expects)
- [Part 2: Lifecycle actions](#part-2-lifecycle-actions)
- [Part 3: Maintenance event queries](#part-3-maintenance-event-queries)
- [Part 4: Diagnostics](#part-4-diagnostics)
- [Part 5: The NVLink reconfiguration safety rule](#part-5-the-nvlink-reconfiguration-safety-rule)
- [Part 6: Drill — full breakfix walkthrough](#part-6-drill--full-breakfix-walkthrough)
- [Part 7: Produce the compliance-pack artifacts](#part-7-produce-the-compliance-pack-artifacts)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

The v2.3 Breakfix section opens with a sentence engineers should memorize:

> *"Any node-level remediation must not impact other parts of the tenancy; specifically, NVLink must be re-configured properly to take a node out of the tenancy."*

Operating an AI fleet at scale means hardware failures are routine: a GPU throws uncorrectable ECC errors, a NIC's retransmit rate spikes, a power supply dies. Handling them by ticketing humans through runbooks doesn't scale, and unsafe sequencing (especially on NVLink-coupled GPUs) can corrupt in-flight tenant workloads. The mature pattern is an operational API surface — cordon, drain, GPU reset, replace, RMA event log — with safety invariants enforced in the controller, not in operator memory.

Today the curriculum has Lab 2.3 (BMC troubleshooting) and Lab 5.6 (GPU troubleshooting). Neither is the *API surface NVIDIA programs against*. This lab designs and implements that surface end-to-end.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Distinguish Breakfix (API contract) from troubleshooting (operator activity)
- [ ] Design the lifecycle API (power-cycle / GPU reset / cordon / replace) on top of k0rdent CRDs + Metal3
- [ ] Design the events API (current, retirement, history) with a comprehensive field set
- [ ] Design the diagnostics API (serial numbers, firmware versions)
- [ ] Explain why NVLink reconfiguration is a safety prerequisite for `replace` on GB200+
- [ ] Run a drill: take a "broken" node out of a tenancy via the API, confirm no tenant impact, return the node
- [ ] Produce a Breakfix runbook, OpenAPI spec, and diagnostics schema for your team's operations manual

---

## Prerequisites

- Week 2 BMaaS labs (Metal3, BMC) — required
- Week 4 KaaS labs (especially 4.1 hosted CP, 4.7 zero-downtime upgrade) — required
- Lab 5.18 (topograph) — required for NVLink domain awareness in Part 5
- Lab 5.17 (OTel) — recommended for event log forwarding in Part 3
- `kubectl`, `helm`, `jq`, `openapi-cli` (or `swagger-cli`) for spec validation

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| Lifecycle API layer | Native k0rdent CRDs (`Machine`, `BareMetalHost`) directly | A purpose-built `Breakfix` CRD | **Purpose-built CRD** — wraps Cluster API + Metal3 with a stable contract, decouples from upstream rename churn |
| Action transport | Synchronous (kubectl exec / direct call) | Asynchronous (work queue + status sub-resource) | **Async with status** — replace operations take minutes-to-hours; sync blocks the consumer |
| Event store | Embed in CRD `.status.history` | Separate audit DB (Loki, Postgres) | **Both** — CRD for current state, audit store for retention beyond resource lifetime |
| RMA workflow | Operator-driven only | Self-service tenant API | **Operator-driven, tenant-readable** — RMA touches a physical asset; tenants observe but don't trigger |
| NVLink re-config trigger | Manual runbook step | Automatic on `cordon` of NVLink-capable node | **Automatic** — too easy to miss; failure here violates the v2.3 opening sentence |

---

## Part 1: The Breakfix surface NVIDIA expects

A well-designed Breakfix surface has three layers:

**Lifecycle Actions.** API must enable:

| Verb | Scope | Effect |
|------|-------|--------|
| `power-cycle` | individual node | Hard reboot (BMC-driven) |
| `gpu-reset` | individual node | `nvidia-smi --gpu-reset` or DRA-managed equivalent |
| `cordon` | individual node | Mark unschedulable; let existing pods drain naturally |
| `report-maintenance` | node or rack | Hand resource back to the operator for repair |
| `replace` | individual node | Request host replacement when health thresholds breached |

**Event Queries.** API must answer:

- Upcoming/current maintenance events for a node or rack
- Retirement notices for a node/rack
- Historical / status info for repair tickets

Required fields per event:

- `ticket_open_date`, `ticket_update_date`, `ticket_close_date`
- Hardware Stable Identifier (e.g., node ID)
- Hardware category/type impacted (GPU, fan, interconnect)
- Maintenance/Error/fault short description
- Action category (e.g., "repaired faulty GPU")
- Provider Account ID
- `ticket_id`
- Node Handover Date (when node entered production)

**Diagnostics.** API must expose:

- Serial numbers of installed hardware (chassis, baseboard, NICs, CPU, GPU). Obfuscated-but-stable identifiers OK.
- Firmware versions of compute nodes and NVSwitch trays.

This is the contract surface. Everything in Parts 2-4 implements it.

---

## Part 2: Lifecycle actions

Define a `Breakfix` CRD that wraps the underlying primitives. Skeleton:

```yaml
apiVersion: ops.k0rdent.mirantis.com/v1alpha1
kind: BreakfixRequest
metadata:
  name: bf-gpu-node-01-replace
spec:
  target:
    nodeName: gpu-node-01
    nodeRef:                       # stable ID (see Lab 2.4)
      uid: nvr-7f2a-9c3b-2e8a
  action: replace                   # one of: power-cycle | gpu-reset | cordon | report-maintenance | replace
  reason: "GPU0 ECC errors > threshold for 24h"
  initiator: dgxc-bot@dgxc.nvidia.com
status:
  phase: InProgress                 # Pending | InProgress | Completed | Failed
  startedAt: 2026-05-25T10:00:00Z
  completedAt: null
  steps:
    - name: cordon
      status: Succeeded
      ts: 2026-05-25T10:00:05Z
    - name: drain
      status: Succeeded
      ts: 2026-05-25T10:08:12Z
    - name: nvlink-domain-detach    # see Part 5
      status: Succeeded
      ts: 2026-05-25T10:08:30Z
    - name: bmh-deprovision
      status: InProgress
  ticketId: RMA-2026-00482       # cross-link to the BreakfixEvent store
```

Implementation skeleton in your controller:

```go
// pseudocode
switch req.Spec.Action {
case "power-cycle":
    return bmcClient.Reboot(req.Spec.Target.NodeRef.UID, RedfishGracefulRestart)
case "gpu-reset":
    return nodeAgent.ResetGPUs(req.Spec.Target.NodeName)
case "cordon":
    return k8s.CordonAndDrain(req.Spec.Target.NodeName, drainOpts)
case "report-maintenance":
    return ticketing.Open(req)
case "replace":
    if isNVLinkCapable(req.Spec.Target.NodeName) {
        if err := nvlinkDetach(req); err != nil { return err }  // Part 5
    }
    return metal3.Deprovision(req.Spec.Target.NodeRef.UID, "RMA")
}
```

Expose as REST/gRPC for off-cluster consumers (mTLS per SEC13). The CRD is the source of truth; the REST API is a thin projection.

---

## Part 3: Maintenance event queries

The events surface needs **history** beyond the lifetime of a Node resource. Use:

- **CRD `BreakfixEvent`** — long-lived, never garbage-collected with the Node
- **Backing store** — Loki (logs) or Postgres (structured), populated by the controller

Required schema:

```yaml
apiVersion: ops.k0rdent.mirantis.com/v1alpha1
kind: BreakfixEvent
metadata:
  name: evt-2026-00482
spec:
  ticketId: RMA-2026-00482
  hardwareStableId: nvr-7f2a-9c3b-2e8a       # required for cross-referencing
  hardwareCategory: GPU                       # required
  faultDescription: "GPU0 ECC errors > threshold"
  action: "Replaced GPU0 module"
  providerAccountId: acct-mirantis-prod
  ticketOpenDate:  2026-05-25T10:00:00Z
  ticketUpdateDate: 2026-05-25T18:30:00Z
  ticketCloseDate:  2026-05-26T09:15:00Z
  nodeHandoverDate: 2026-04-12T00:00:00Z      # when this hardware entered production
status:
  phase: Closed
```

Query endpoints (REST):

```http
GET /v1alpha1/breakfix/events?nodeRef=nvr-7f2a-9c3b-2e8a&status=open
GET /v1alpha1/breakfix/events?rackId=rack-A-12&from=2026-04-01
GET /v1alpha1/breakfix/retirements?from=2026-06-01
```

Forward each event to OTel (Lab 5.17) for downstream ingestion within the agreed latency budget.

---

## Part 4: Diagnostics

Diagnostics queries are read-only and frequent. Cache aggressively.

```http
GET /v1alpha1/breakfix/diagnostics/{nodeRef}
{
  "nodeRef": "nvr-7f2a-9c3b-2e8a",
  "hardware": {
    "chassis":   { "serial": "OBF-CHAS-2A4F9C", "manufacturer": "Supermicro" },
    "baseboard": { "serial": "OBF-BB-7E2A93C", "model": "X13DAG" },
    "nics":      [ { "id": "ib0", "serial": "OBF-CX7-001", "fw": "28.39.2048" } ],
    "cpus":      [ { "model": "Grace", "fw_version": "1.2.3" } ],
    "gpus":      [ { "model": "B200", "serial": "OBF-GPU-001", "vbios": "92.00.45.00.05" } ],
    "nvswitch_trays": [ { "id": "tray-0", "fw": "1.04.0" } ]
  },
  "collected_at": "2026-05-25T09:45:00Z"
}
```

The "OBF-" prefix indicates obfuscated-but-stable IDs (the v2.3 guide allows obfuscation as long as identifiers are stable across reboots).

Collection mechanisms:

| Source | How to collect |
|--------|----------------|
| Chassis/baseboard | Redfish `/redfish/v1/Chassis/*` + `/Managers/*` |
| NIC firmware | `mlxfwmanager` (Mellanox/NVIDIA) or `ethtool -i` |
| GPU model/serial/VBIOS | `nvidia-smi -q` (or DCGM equivalent) |
| NVSwitch tray firmware | `nvidia-smi nvswitch -i 0 -q` + FM API |

Run as a periodic DaemonSet that updates a `NodeDiagnostics` CR; serve REST from a cached read of the CR.

---

## Part 5: The NVLink reconfiguration safety rule

This is the part of Breakfix where engineers most often make mistakes.

On a GB200/GB300 NVL72 rack:

- 72 GPUs share an NVLink Switch fabric (NVSwitch trays).
- If you `replace` a node *without* detaching it from the NVLink domain first, the remaining 63-71 GPUs **may experience NVLink topology changes mid-job**, causing in-flight collectives to error.
- The v2.3 opening sentence on Breakfix is specifically about this hazard.

**Safe sequence** for `replace` on an NVLink-capable node:

1. `cordon` → existing pods drain naturally (PDBs respected, per Lab 4.7 patterns).
2. **Detach from NVLink domain.** Use `nvidia-fabric-manager-cli` (or the FM API) to remove the node's GPUs from the active NVLink fabric. Wait for the FM to converge.
3. Confirm no active NCCL/RDMA tenant workload references the GPUs in question (query `nvidia-smi --query-compute-apps`).
4. Power-off via BMC.
5. Hand off to RMA (Metal3 `BareMetalHost` `provisioning.state: deprovisioning`).

**Reverse on return:**

1. Provision new/repaired hardware via Metal3.
2. Re-attach to NVLink domain (FM API).
3. Validate via `nvidia-smi nvlink --status` that all NVLinks come up.
4. Uncordon.

Encode this sequence as a finite-state machine in your controller — *not* a runbook humans follow. The Breakfix controller must refuse `replace` on an NVLink-capable node if it can't reach the FM API.

---

## Part 6: Drill — full breakfix walkthrough

End-to-end exercise:

```bash
# 0. Pick a "broken" node
NODE=gpu-node-01
NODE_REF=$(kubectl get node $NODE -o jsonpath='{.metadata.annotations.nvidia\.com/node-ref}')

# 1. Open a Breakfix request
cat <<EOF | kubectl apply -f -
apiVersion: ops.k0rdent.mirantis.com/v1alpha1
kind: BreakfixRequest
metadata: { name: drill-$NODE }
spec:
  target: { nodeName: $NODE, nodeRef: { uid: $NODE_REF } }
  action: replace
  reason: "Drill: simulated GPU failure"
  initiator: drill@training.local
EOF

# 2. Watch progression
kubectl get breakfixrequest drill-$NODE -w

# 3. Verify other tenants are unaffected — run a sentinel workload elsewhere
kubectl -n tenant-a logs -l app=nccl-sentinel -f

# 4. After "RMA" (simulate by manually reprovisioning the BMH)
# 5. Confirm node returns to Ready, uncordoned, NVLinks healthy
nvidia-smi nvlink --status
```

Capture:
- Time-to-cordon (`P1: drained without disruption`)
- Time-to-detach (NVLink)
- Time-to-RMA-handoff
- Sentinel workload throughput dip (target: 0%)

---

## Verification Checklist

- [ ] `BreakfixRequest` CRD installed and validated by an admission webhook
- [ ] All five lifecycle actions exercised end-to-end on at least one test node
- [ ] Event query endpoints return the full documented field set
- [ ] Diagnostics returns all required hardware categories (chassis, baseboard, NICs, CPU, GPU, NVSwitch tray)
- [ ] On NVLink-capable hardware: `replace` action refuses to proceed when FM API is unreachable
- [ ] Drill from Part 6 completes without sentinel workload throughput dip
- [ ] OpenAPI spec validates clean (`openapi-cli lint`)
- [ ] mTLS enforced on the REST endpoint
- [ ] All Breakfix events forwarded to OTel within the agreed latency budget (per Lab 5.17)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `replace` succeeds but sentinel workload errors mid-drill | NVLink detach skipped or raced | Make detach a hard precondition; ensure FM convergence wait is in-controller |
| BreakfixEvent count grows unbounded | No retention/archive on the CRD | Move closed events to backing store after N days; keep open events in CRD |
| Diagnostics returns stale firmware versions | Cache too long-lived | Drop diagnostics cache TTL to ≤1 h; invalidate on `power-cycle` completion |
| `cordon` action returns "ready" but pods linger | PDBs blocking drain | Don't force-evict — return `Pending` and surface the PDB(s) blocking |
| Sentinel workload sees brief throughput dip on RMA return | NVLinks didn't fully reconverge before uncordon | Add explicit FM-status gate in the controller before uncordon |

---

## Key Takeaways

- **Breakfix is an API, not a runbook.** If it requires a human to remember a step, you've designed it wrong.
- **NVLink detach is the safety rule.** The v2.3 guide's opening Breakfix sentence is about this; encode it as a precondition in the controller, not as documentation.
- **Events have a longer life than the Node.** Don't tie event retention to resource lifecycle.
- **Diagnostics can use obfuscated IDs.** Don't expose raw serials if not required; do keep them stable.

---

## Next Lab

Lab 6.3 — Capacity & Fleet Management APIs — once you can take resources *out* of service safely, the next concern is reporting which resources are *in* service and what state they're in.
