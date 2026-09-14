# Lab 5.18 — Network Topology + NVLink Domain Discovery

**Domain:** Network Fabric / Topology Awareness / GPU Scheduling

> **Reference implementation:** [`github.com/NVIDIA/topograph`](https://github.com/NVIDIA/topograph)

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Operations & Telemetry | Elective | 2 hours |

### Week 5 Learning Paths

```
5.16 Dist Train ➔ 5.17 OTel ➔ [5.18] topograph (YOU ARE HERE) ➔ 5.19 MIG
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.17 — OTel Telemetry Export](lab-5.17-otel-telemetry-export.md) | **Lab 5.18 — topograph / NVLink Topology** | [Lab 5.19 — MIG Partitioning](lab-5.19-mig-partitioning.md) |

---

**Duration:** 2 hours
**Type:** Hands-on Technical
**Environment:** Two free GPUs for the simulated placement baseline; qualified multi-node NVLink hardware for a performance comparison

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: The topology APIs you want to expose](#part-1-the-topology-apis-you-want-to-expose)
- [Part 2: Deploy topograph against your cluster](#part-2-deploy-topograph-against-your-cluster)
- [Part 3: Expose the Backend Switch Fabric API](#part-3-expose-the-backend-switch-fabric-api)
- [Part 4: Expose the NVLink Domain API](#part-4-expose-the-nvlink-domain-api)
- [Part 5: Integrate with the scheduler (KAI / Volcano)](#part-5-integrate-with-the-scheduler-kai--volcano)
- [Part 6: Validate topology-aware placement vs naive placement](#part-6-validate-topology-aware-placement-vs-naive-placement)
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

The only defense is to **expose topology as data**, then let the scheduler use it. This lab teaches the two API surfaces — a Backend Switch Fabric API (leaf/spine/core hierarchy) and an NVLink Domain API (which nodes share NVSwitch trays) — that let your scheduler answer questions like *"give me 144 GPUs that share an NVLink domain AND a leaf switch."*

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Explain the difference between a Backend Switch Fabric API and an NVLink Domain API
- [ ] Deploy NVIDIA's `topograph` reference implementation against a k0rdent-managed cluster
- [ ] Query the topology API and validate the response shape
- [ ] Read the K8s node labels topograph applies: `network.topology.nvidia.com/{leaf,spine,core}` for switch tiers and `network.topology.nvidia.com/accelerator` for the NVLink domain
- [ ] Select a single domain using required node affinity; distinguish colocation from topology spread
- [ ] Measure throughput uplift vs naive placement on a multi-node NCCL all-reduce

---

## Prerequisites

- Lab 4.4 (Cilium + Multus) is needed only for the optional secondary-network/RDMA path; ordinary label placement does not require it
- Lab 5.3 (KAI Scheduler) **or** Lab 5.4 (Run:AI) — pick one; this lab integrates with whichever you ran
- Lab 5.17 (OTel) — recommended (topology stats flow through OTel)
- A working multi-node GPU cluster — ideally on real NVLink hardware; an InfiniBand / RoCE simulation works for the structure but not for performance validation in Part 6
- `kubectl`, `helm`, `jq`, `go ≥ 1.22` (for building/extending topograph if needed)

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| Topology discovery source | Static config (Terraform / IaC) | Dynamic discovery (cloud provider topology API, IB SM / NetQ query) | **Dynamic discovery** — IaC drifts; topograph already implements CSP-API + InfiniBand discovery |
| API surface | Native CRD on k0rdent | REST / gRPC service | **CRD + projection to REST** — CRD for K8s consumers, REST proxy for off-cluster consumers |
| Node labeling strategy | k0rdent ClusterDeployment template | Operator that watches `Node` resources | **Operator** — handles add/remove/repair without redeploying |
| Update cadence | On every node change | Periodic full re-scan + on-demand | **Both** — event-driven for fast convergence + 1 h full re-scan for self-heal |
| Scheduler integration | `PodTopologySpread` + node selectors | Custom scheduler plugin | **Spread + selectors first** (works with stock kube-scheduler); plugin only if measured uplift demands it |

---

## Part 1: The topology APIs you want to expose

You want two API surfaces. They can be a single service with two methods, or two separate services — but the schemas need to be distinct.

**Backend Switch Fabric API**

For each compute node, the API must expose:

- A **stable unique identifier** for each switch the node connects to (physical switch or logical connectivity domain).
- The **topology**: leaf/spine/core hierarchy, returnable as an ordered array `[leaf, spine, core]` or separate fields per tier.
- A pagination-friendly response (multiple nodes per page).
- gRPC or REST (gRPC preferred for high node counts).

**NVLink Domain API**

For NVLink-capable nodes (GB200, GB300, Vera Rubin):

- Return a **unique NVLink domain identifier** per node.
- May be a separate method or folded into the Backend Switch Fabric API response.

Together they let the scheduler answer: *"give me 144 GPUs that share an NVLink domain AND a leaf switch."*

---

## Part 2: Deploy topograph against your cluster

NVIDIA's [`topograph`](https://github.com/NVIDIA/topograph) implements the discovery side. On
Kubernetes (chart v0.5.0) a single Helm release installs **three** workloads (verified live):
an **API server** (`Deployment/topograph`), a **Node Observer** (`Deployment/topograph-node-observer`)
that watches `Node` changes, and a **per-node `node-data-broker` DaemonSet**
(`DaemonSet/topograph-node-data-broker`). The broker runs on every node to read instance metadata
(via IMDS) and annotate the node with `topograph.nvidia.com/instance`; the API server then reads
the provider topology (on AWS, `ec2:DescribeInstanceTopology`) and writes the result back as
**node labels**. So there *is* a per-node component in v0.5.0 — the broker must become Ready before
any topology can be generated (see Troubleshooting).

The chart is published to a **classic Helm repository on GitHub Pages**, not an OCI registry
(`oci://ghcr.io/nvidia/topograph/...` returns `403 denied` — only the container *image* lives on
ghcr). Add the repo, then install:

```bash
# Add the classic Helm repo and install the pinned chart (v0.5.0). provider = aws, engine = k8s.
helm repo add topograph https://NVIDIA.github.io/topograph
helm repo update topograph
helm install topograph topograph/topograph \
  --version 0.5.0 \
  --namespace topograph --create-namespace \
  --set global.provider.name=aws \
  --set global.engine.name=k8s
```

> **Note:** topograph moves fast (v0.5.0 is the pin validated for this lab). Confirm the current
> chart with `helm search repo topograph/topograph --versions`, and pick the provider
> that matches your cluster — valid values include `aws`, `gcp`, `oci`, `nebius`, `nscale`, `cw`,
> `netq`, `infiniband-k8s`, `dra`. The AWS provider needs `ec2:DescribeInstanceTopology`
> (the `AmazonEC2ReadOnlyAccess` managed policy covers it). On the g5 lab cluster there is no
> real switch fabric to discover, so drive the labeling path with a static/simulated config.

Validate the release is healthy:

```bash
kubectl -n topograph get pods -o wide
kubectl -n topograph logs -l app.kubernetes.io/instance=topograph --tail=50
```

The API server listens on port `49021` (endpoints `/v1/generate`, `/v1/topology`, `/healthz`, `/metrics`). When a node's status changes, the Node Observer asks the API server to regenerate the topology and re-label nodes.

> **`/v1/topology` is asynchronous in v0.5.0.** A bare `GET /v1/topology` returns
> `400 must specify request uid` — it is *not* a one-shot dump. The flow is: `POST /v1/generate`
> (body `{"provider":{"name":"aws"},"engine":{"name":"k8s"}}`) returns a request **uid**; then
> `GET /v1/topology?uid=<uid>` returns `202` (`request ID ... has been created`) while the job runs
> and the topology once complete. `/healthz` returns `200 OK`.

---

## Part 3: Expose the Backend Switch Fabric API

The *target* downstream schema (from Part 1) looks like this — it is the shape you want, not a verbatim topograph dump:

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

topograph does **not** publish a CRD. It surfaces the fabric two ways:

**Option A — node labels (in-cluster consumers).** topograph writes the switch path onto each node as labels; read them directly:

```bash
kubectl get nodes -L \
  network.topology.nvidia.com/leaf \
  network.topology.nvidia.com/spine \
  network.topology.nvidia.com/core \
  network.topology.nvidia.com/accelerator
```

**Option B — the REST API (off-cluster consumers).** The API server exposes the generated topology on port 49021. Port-forward and query it, then reshape to the schema above:

```bash
# The Service is named after the release: `topograph` (NOT topograph-topograph); confirm with
# `kubectl -n topograph get svc`.
kubectl -n topograph port-forward svc/topograph 49021:49021 &
curl -s http://localhost:49021/healthz    # -> OK
# From the repository root. The script checks HTTP 202/200 and polls with a deadline.
bash curriculum/examples/topology/query-topology.sh http://localhost:49021 topology-result.txt
# The k8s engine applies node labels; its result is not promised to be JSON.
kubectl get nodes -L network.topology.nvidia.com/accelerator
```

For production, front the REST endpoint with a proper service that adds:

- TLS (mTLS for off-cluster consumers)
- Pagination (`?page=2&limit=100`)
- ETags / cache headers
- Auth (OIDC token validation)

---

## Part 4: Expose the NVLink Domain API

topograph exposes the NVLink / accelerated domain as the `network.topology.nvidia.com/accelerator` label. On AWS it derives this from the `CapacityBlockId` returned by `ec2:DescribeInstanceTopology` — you do **not** query `nvidia-fabric-manager` yourself; the provider does the work. (On a node you can still cross-check the NVLink wiring with `nvidia-smi topo -m` or `nvidia-smi nvlink -s`, but that is not topograph's source of truth.)

Nodes in the same NVLink domain share the label value:

```bash
kubectl get nodes -L network.topology.nvidia.com/accelerator
# NAME           STATUS   ROLES    ACCELERATOR
# gpu-node-01    Ready    worker   nvl72-rack-A
# gpu-node-02    Ready    worker   nvl72-rack-A
# gpu-node-09    Ready    worker   nvl72-rack-B
```

For non-NVLink hardware (e.g. the g5 / A10G lab cluster) the accelerator label is simply absent; consumers must tolerate its absence.

> **Validated-live caveat (k0rdent/CAPA nodes).** On the standalone-cp lab cluster *none* of the
> topology labels appear — not even `leaf`/`spine` — and the cause is upstream of provider
> topology: the `node-data-broker` DaemonSet cannot reach the instance-metadata service
> (`Put http://169.254.169.254/latest/api/token ... connection reset by peer`), so it never
> annotates nodes with `topograph.nvidia.com/instance`. The API server then logs
> `Extracted topology for 0 instances` and the Node Observer sits on
> `Waiting for node-data-broker pods to become ready`. Root cause: CAPA launches nodes with the
> IMDSv2 **hop limit = 1**, which blocks IMDS from pod-network pods. Fix in the AWSMachineTemplate
> (`spec.template.spec.instanceMetadataOptions.httpPutResponseHopLimit: 2`) or run the broker with
> `hostNetwork: true`. The API-server's AWS credentials themselves are fine — this is *not* an
> `ec2:DescribeInstanceTopology` IAM failure.

---

## Part 5: Integrate with the scheduler (KAI / Volcano)

Choose a domain first, then constrain **all worker replicas** to that value with
required node affinity (`operator: In`). `Exists` permits any domain. Topology
spread balances pods across eligible domains, so it does not enforce colocation;
`maxSkew` must be positive and zero is invalid. When needed, add hostname spreading
*within* the selected domain and use the installed scheduler's supported gang API.

The committed fixtures use the installed MPI Operator `MPIJob` API: two workers
with one GPU each. They include the MPI startup/rank adapters and a real all-reduce
benchmark. Install MPI Operator as in Lab 5.16, then create its namespace/adapters:

```bash
kubectl create namespace distributed-training --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f curriculum/examples/distributed-training/mpi-adapters.yaml
```

**Standard A10G path: simulated placement only.** Label a GPU worker with a separate
training label; do not fake NVIDIA-discovered labels:

```bash
kubectl get nodes -l nvidia.com/gpu.present=true
kubectl label node <gpu-worker-name> training.k0rdent.io/accelerator-domain=training-domain-a
```

The [topology fixture](../../examples/topology/benchmark-topology.yaml) selects this
value. Two pods can run on the single four-GPU worker. This proves the affinity
wiring, not NVLink availability or a bandwidth improvement.

**Real NVLink path:** copy that fixture and replace the training label key/value
with `network.topology.nvidia.com/accelerator` and a domain actually reported by
topograph. Set worker replicas, slotsPerWorker, GPU requests/limits, and the
launcher's `-np`/`-npernode` consistently. Require sufficient free GPUs in that domain
before starting; otherwise the example can partially allocate and wait. To teach
gang admission, use Lab 5.3's capacity test with the configured scheduler. This
MPI fixture demonstrates placement and communication, not atomic admission.

## Part 6: Validate topology-aware placement vs naive placement

Run the fixtures sequentially so one does not consume the other's GPU capacity.
Use the committed paths from the repository root:

```bash
kubectl apply -f curriculum/examples/topology/benchmark-naive.yaml
kubectl -n distributed-training wait mpijob/nccl-allreduce-naive --for=condition=Succeeded --timeout=15m
kubectl -n distributed-training logs job/nccl-allreduce-naive-launcher > naive.log
kubectl -n distributed-training get pods -o wide
kubectl -n distributed-training delete mpijob/nccl-allreduce-naive --wait=true

kubectl apply -f curriculum/examples/topology/benchmark-topology.yaml
kubectl -n distributed-training wait mpijob/nccl-allreduce-topo --for=condition=Succeeded --timeout=15m
kubectl -n distributed-training logs job/nccl-allreduce-topo-launcher > topo.log
kubectl -n distributed-training get pods -o wide
```

On a failed/timed-out run inspect the MPIJob conditions and launcher/worker logs;
do not report a speedup. Record each worker's actual node and domain, GPU model,
NCCL transport, rank count, tensor sizes and reported BusBW. Compare several runs
on identical hardware with identical settings. Do not promise a particular uplift:
if naive placement already uses the same domain, no placement benefit is expected.
The simulated-label path has **no NVLink performance acceptance claim**.

```bash
kubectl -n distributed-training delete mpijob/nccl-allreduce-topo --wait=true
kubectl label node <gpu-worker-name> training.k0rdent.io/accelerator-domain-
```

---

## Verification Checklist

- [ ] topograph release healthy (API server + Node Observer pods `Running`)
- [ ] `GET /v1/topology` (via port-forward) returns a non-empty topology
- [ ] Every node carries `network.topology.nvidia.com/leaf` (and spine/core where applicable)
- [ ] NVLink-capable nodes carry `network.topology.nvidia.com/accelerator`
- [ ] REST projection returns the documented Backend Switch Fabric API shape
- [ ] PodTopologySpread + nodeAffinity successfully pins a job to one NVLink domain
- [ ] Perf evidence captured (where hardware allows)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| topograph pod errors talking to the cloud API | Wrong `global.provider.name` or missing IAM permission | Match the provider to your cluster and grant `ec2:DescribeInstanceTopology` (`AmazonEC2ReadOnlyAccess`) |
| No labels applied; Node Observer logs `Waiting for node-data-broker pods to become ready`; API logs `Extracted topology for 0 instances` | `node-data-broker` DaemonSet stuck `0/1` — it can't reach IMDS (`169.254.169.254 ... connection reset`) because CAPA nodes launch with IMDSv2 hop limit = 1 | Set `httpPutResponseHopLimit: 2` in the AWSMachineTemplate's `instanceMetadataOptions`, or run the broker `hostNetwork: true`. (Distinct from an IAM failure — the API server's AWS creds work.) |
| `network.topology.nvidia.com/accelerator` label empty | Instances not in a capacity block, or provider returned no `CapacityBlockId` | Confirm the nodes launched in a capacity block / NVLink domain the provider can see |
| Pod stuck Pending despite a domain having free GPUs | Other workloads spread across domains, using the selected domain's capacity | Check the selected domain and available GPU capacity; do not bypass required affinity or evict unrelated jobs |
| Naive job outperforms topology-aware | Placement, contention or measurement variance may explain the result | Record actual placement and repeat the same workload; no uplift is guaranteed |
| Switch IDs all collapse to one value | LLDP not configured on switches | Enable LLDP on every switch port; verify with `lldpctl` from a host |

---

## Key Takeaways

- **Topology is data — the scheduler is the consumer.** Half this lab is wiring data flow.
- **Two distinct API surfaces matter:** Backend Switch Fabric (leaf/spine/core) and NVLink Domain. They can share a service, but the schemas are distinct because the consumers may differ.
- **Measure topology effects on the target fabric.** Record placement and repeated benchmark results before claiming a throughput or cost improvement.

---

## Next Lab

[Week 6 — Multi-Tenancy](../../week-6-multitenancy/) — once your single-tenant fabric is observable and steerable, the next layer is making it safe to share across tenants.
