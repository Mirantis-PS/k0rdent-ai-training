# Lab 5.18 — Network Topology + NVLink Domain Discovery API

| Domain | Tag | NVIDIA Req IDs |
|--------|-----|----------------|
| Network Fabric / Topology Awareness | 🟢 NCP | NET01 (Backend Switch Fabric API), NET02 (NVLink Domain API), CNP03 (NVLink-Aware Allocation), CAP04 (Atomic Topology Block) |

> **Compliance pack artifact target:** `artifacts/NET01-switch-fabric-topology.json`, `artifacts/NET02-nvlink-domain-map.json`

> **Reference implementation:** [`github.com/NVIDIA/topograph`](https://github.com/NVIDIA/topograph)

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Operations & Telemetry | Required (NCP track) | 2 hours |

### Week 5 Learning Paths

```
5.16 Dist Train ➔ 5.17 OTel ➔ [5.18] topograph (YOU ARE HERE)
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.17 — OTel Telemetry Export](lab-5.17-otel-telemetry-export.md) | **Lab 5.18 — topograph / NVLink Topology** | [Week 6 — Multi-Tenancy](../../week-6-multitenancy/) |

---

**Duration:** 2 hours
**Type:** Hands-on Technical
**Environment:** Multi-node GPU cluster (≥4 GPU nodes, ideally on real or simulated NVLink fabric)

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: What NVIDIA expects from NET01/NET02](#part-1-what-nvidia-expects-from-net01net02)
- [Part 2: Deploy topograph against your cluster](#part-2-deploy-topograph-against-your-cluster)
- [Part 3: Expose the Backend Switch Fabric API](#part-3-expose-the-backend-switch-fabric-api)
- [Part 4: Expose the NVLink Domain API](#part-4-expose-the-nvlink-domain-api)
- [Part 5: Integrate with the scheduler (KAI / Volcano)](#part-5-integrate-with-the-scheduler-kai--volcano)
- [Part 6: Validate topology-aware placement vs naive placement](#part-6-validate-topology-aware-placement-vs-naive-placement)
- [Part 7: Produce the compliance-pack artifacts](#part-7-produce-the-compliance-pack-artifacts)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

A modern AI cluster has **two networks that matter for multi-node training**:

1. **Backend switch fabric** — InfiniBand or RoCE leaf/spine/core, connecting nodes for RDMA traffic.
2. **NVLink domain** — for GB200/GB300/Vera Rubin systems, a set of nodes that share NVLink Switch tray connectivity (typically 72-GPU NVL72 racks).

A workload that *crosses* either boundary at the wrong granularity loses substantial throughput:

| Workload pattern | Crosses leaf | Crosses NVLink domain | Expected throughput loss |
|------------------|--------------|----------------------|--------------------------|
| All-reduce on 8 GPUs (1 node) | no | no | baseline |
| All-reduce on 16 GPUs (2 nodes, same leaf) | no | possibly | 5-15% |
| All-reduce on 72 GPUs (1 NVL72 rack) | yes | no | 10-20% vs in-domain |
| All-reduce on 144 GPUs (2 NVL72 racks) | yes | **yes** | 30-50% vs in-domain |

NVIDIA's solution is to **expose topology as data**, then let the scheduler use it. NET01 and NET02 are the API contract.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Explain the difference between the Backend Switch Fabric (NET01) and NVLink Domain (NET02) APIs
- [ ] Deploy NVIDIA's `topograph` reference implementation against a k0rdent-managed cluster
- [ ] Query the topology API and validate the response shape against the v2.3 guide
- [ ] Annotate K8s nodes with `network.nvidia.com/topology-layer-{leaf,spine,core}` and `nvlink-domain-id`
- [ ] Author a scheduler plugin or PodTopologySpread constraint that prefers in-domain placement
- [ ] Measure throughput uplift vs naive placement on a multi-node NCCL all-reduce
- [ ] Produce Req-ID-stamped artifacts for the compliance pack

---

## Prerequisites

- Lab 4.4 (Cilium + Multus) — required (you need the secondary network)
- Lab 5.3 (KAI Scheduler) **or** Lab 5.4 (Run:AI) — pick one; this lab integrates with whichever you ran
- Lab 5.17 (OTel) — recommended (topology stats flow through OTel)
- A working multi-node GPU cluster — ideally on real NVLink hardware; an InfiniBand / RoCE simulation works for the structure but not for performance validation in Part 6
- `kubectl`, `helm`, `jq`, `go ≥ 1.22` (for building/extending topograph if needed)

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| Topology discovery source | Static config (Terraform / IaC) | Dynamic discovery (LLDP, IB SM query, NVLink CLI) | **Dynamic discovery** — IaC drifts; topograph already implements LLDP + IB queries |
| API surface | Native CRD on k0rdent | REST / gRPC service | **CRD + projection to REST** — CRD for K8s consumers, REST proxy for off-cluster (DGXC) consumers |
| Node labeling strategy | k0rdent ClusterDeployment template | Operator that watches `Node` resources | **Operator** — handles add/remove/repair without redeploying |
| Update cadence | On every node change | Periodic full re-scan + on-demand | **Both** — event-driven for fast convergence + 1 h full re-scan for self-heal |
| Scheduler integration | `PodTopologySpread` + node selectors | Custom scheduler plugin | **Spread + selectors first** (works with stock kube-scheduler); plugin only if measured uplift demands it |

---

## Part 1: What NVIDIA expects from NET01/NET02

Direct from the v2.3 guide (paraphrased — see source for exact wording):

**NET01 — Backend Switch Fabric API**

For each compute node, the API must expose:

- A **stable unique identifier** for each switch the node connects to (physical switch or logical connectivity domain).
- The **topology**: leaf/spine/core hierarchy, returnable as an ordered array `[leaf, spine, core]` or separate fields per tier.
- A pagination-friendly response (multiple nodes per page).
- gRPC or REST (gRPC preferred for high node counts).

**NET02 — NVLink Domain API**

For NVLink-capable nodes (GB200, GB300, Vera Rubin):

- Return a **unique NVLink domain identifier** per node.
- May be a separate method or folded into NET01's response.

The two APIs together let DGXC's scheduler answer: *"give me 144 GPUs that share an NVLink domain AND a leaf switch."*

---

## Part 2: Deploy topograph against your cluster

NVIDIA's [`topograph`](https://github.com/NVIDIA/topograph) implements the discovery side. Deploy it as a DaemonSet that scans on each node and a controller that aggregates.

```bash
# Clone the latest stable tag
git clone --depth 1 https://github.com/NVIDIA/topograph.git
cd topograph

# Inspect the reference deploy manifests
ls deploy/kubernetes/

# Apply (adjust namespace as needed)
kubectl create namespace topograph-system
kubectl apply -n topograph-system -f deploy/kubernetes/
```

> **Note:** topograph evolves. Check the latest release notes; the manifest paths may differ. If the upstream repo lacks Kubernetes manifests at your time of reading, use the binary in a `DaemonSet` of your own with the discovery flags appropriate for your fabric (IB / RoCE / synthetic).

Validate the DaemonSet is healthy:

```bash
kubectl -n topograph-system get pods -o wide
kubectl -n topograph-system logs -l app=topograph-agent --tail=50
```

You should see per-node discovery output: detected NICs, IB GIDs, switch IDs (from LLDP or IB SM), and NVLink domain probes.

---

## Part 3: Expose the Backend Switch Fabric API

topograph emits a JSON document like:

```json
{
  "nodes": [
    {
      "name": "gpu-node-01",
      "switches": [
        { "tier": "leaf",  "id": "leaf-01" },
        { "tier": "spine", "id": "spine-01" },
        { "tier": "core",  "id": "core-01" }
      ],
      "nvlink_domain_id": "nvl72-rack-A"
    },
    ...
  ]
}
```

Two ways to expose this:

**Option A — via CRD (in-cluster consumers).** topograph publishes a `TopologyView` CR. Inspect:

```bash
kubectl get topologyviews.topology.nvidia.com -o yaml
```

**Option B — via REST (DGXC consumers).** Stand up a tiny REST proxy that translates the CR into the JSON shape NET01 expects:

```bash
# Example: a 30-line Go service or even a kubectl-proxy + jq pipeline for first-pass validation
kubectl get topologyviews.topology.nvidia.com -o json \
  | jq '{ nodes: [ .items[].spec.nodes[] | { name, switches, nvlink_domain_id } ] }' \
  > NET01-switch-fabric-topology.json
```

For production, build a proper REST service with:

- TLS (mTLS for DGXC)
- Pagination (`?page=2&limit=100`)
- ETags / cache headers
- Auth (OIDC token validation per SEC01)

---

## Part 4: Expose the NVLink Domain API

If your hardware is GB200+, the NVLink Domain ID comes from `nvidia-fabric-manager` on each node:

```bash
# Per node, NVLink domain ID is derivable from FM topology dump
nvidia-smi nvlink --status
sudo nvidia-fabric-manager-cli -d -t
```

topograph normalizes this into the `nvlink_domain_id` field. For non-NVLink hardware, omit the field; consumers must tolerate its absence (per the v2.3 wording).

Project an NVLink-domain-aware Node label so the K8s scheduler can use it:

```bash
# Driven by the topograph controller — example of the final state:
kubectl get nodes -L network.nvidia.com/nvlink-domain
# NAME           STATUS   ROLES    NVLINK-DOMAIN
# gpu-node-01    Ready    worker   nvl72-rack-A
# gpu-node-02    Ready    worker   nvl72-rack-A
# gpu-node-09    Ready    worker   nvl72-rack-B
```

---

## Part 5: Integrate with the scheduler (KAI / Volcano)

The simplest integration uses Kubernetes-native `PodTopologySpread` + node-label affinity. Example: a 16-GPU job that must stay inside one NVLink domain:

```yaml
apiVersion: scheduling.run.ai/v1   # or v1 for KAI / Volcano equivalent
kind: TrainingWorkload
metadata:
  name: nccl-allreduce-16gpu
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - { key: network.nvidia.com/nvlink-domain, operator: Exists }
      topologySpreadConstraints:
      - maxSkew: 0
        topologyKey: network.nvidia.com/nvlink-domain
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels: { app: nccl-allreduce-16gpu }
      containers:
      - name: trainer
        image: nvcr.io/nvidia/pytorch:24.10-py3
        resources:
          limits:
            nvidia.com/gpu: 4   # 4 GPUs/pod × 4 pods = 16
```

For larger jobs that intentionally *span* domains, drop `maxSkew: 0` to allow spread.

For KAI / Run:AI specifically, configure topology-aware queue policies — refer back to Lab 5.3 / 5.4 for queue setup.

---

## Part 6: Validate topology-aware placement vs naive placement

Run the same NCCL all-reduce benchmark twice:

```bash
# Naive: no topology constraints
kubectl apply -f benchmark-naive.yaml
kubectl logs -l job-name=nccl-allreduce-naive -f | tee naive.log

# Topology-aware: nodeAffinity + spread constraints from Part 5
kubectl apply -f benchmark-topology.yaml
kubectl logs -l job-name=nccl-allreduce-topo -f | tee topo.log
```

Extract the busbw reported by `all_reduce_perf`:

```bash
grep "size .* GB/s" naive.log topo.log
```

**Expected (real NVLink hardware):**

| Job size | Naive busbw | Topology-aware busbw | Uplift |
|----------|------------|----------------------|--------|
| 16 GPU (2 nodes) | varies by leaf alignment | ≥10% higher in domain | 5-15% |
| 72 GPU (full NVL72) | 30-50% lower if it crossed | full NVLink rate | 30-50% |
| 144 GPU (2× NVL72) | depends on spine | matches single-domain rate × 2 | substantial |

Record actual numbers in `NET01-perf-evidence.md`.

On synthetic / non-NVLink hardware, you won't see the perf uplift but you can still validate that:

- placement respected the constraints
- pods landed where the labels said they would
- the scheduler rejected impossible placements

---

## Part 7: Produce the compliance-pack artifacts

```bash
# 1. Switch fabric topology snapshot (NET01)
kubectl get topologyviews.topology.nvidia.com -o json \
  | jq '{ nodes: [ .items[].spec.nodes[] | { name, switches, nvlink_domain_id } ] }' \
  > NET01-switch-fabric-topology.json

# 2. NVLink domain map (NET02)
kubectl get nodes -o json \
  | jq '{ domains: ( [ .items[] | { node: .metadata.name,
        domain: .metadata.labels["network.nvidia.com/nvlink-domain"] } ]
        | group_by(.domain) | map({ domain: .[0].domain, nodes: [.[].node] }) ) }' \
  > NET02-nvlink-domain-map.json

# 3. Perf evidence (from Part 6)
cp naive.log topo.log NET01-perf-evidence/
```

---

## Verification Checklist

- [ ] topograph DaemonSet healthy on every node
- [ ] `TopologyView` CR populated with non-empty `nodes` list
- [ ] Every node carries `network.nvidia.com/topology-layer-leaf` (and spine/core where applicable)
- [ ] NVLink-capable nodes carry `network.nvidia.com/nvlink-domain`
- [ ] REST projection returns NET01-shaped JSON (validated against v2.3 wording)
- [ ] PodTopologySpread + nodeAffinity successfully pins a job to one NVLink domain
- [ ] Perf evidence captured (where hardware allows)
- [ ] `NET01-*.json` and `NET02-*.json` artifacts produced

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| topograph agent crashes on non-IB nodes | Discovery method not auto-detected | Set discovery flags explicitly (e.g., `--discovery=ethernet-lldp`) |
| NVLink domain ID empty on GB200 | `nvidia-fabric-manager` not running or not exposing FM API | Check FM systemd unit + ensure topograph has socket access |
| Pod stuck Pending despite a domain having free GPUs | Other workloads spread across domains, blocking spread constraint | Either drop `maxSkew: 0` or evict the spreader |
| Naive job outperforms topology-aware (suspicious) | The naive job got lucky and landed in-domain | Re-run with more replicas to wash out noise |
| Switch IDs all collapse to one value | LLDP not configured on switches | Enable LLDP on every switch port; verify with `lldpctl` from a host |

---

## Key Takeaways

- **Topology is data — the scheduler is the consumer.** Half this lab is wiring data flow.
- **NET01 and NET02 are the contract DGXC will program against.** Your job is to make the response shape exactly what they expect.
- **Topology-aware placement is not a micro-optimization on GB200+** — it's the difference between healthy training throughput and a job that costs 50% more to finish.
- **The compliance pack artifact for this lab is the API response itself.** A sanitized JSON snapshot, timestamped, is what an audit asks for.

---

## Next Lab

[Week 6 — Multi-Tenancy](../../week-6-multitenancy/) — once your single-tenant fabric is observable and steerable, the next layer is making it safe to share across tenants.
