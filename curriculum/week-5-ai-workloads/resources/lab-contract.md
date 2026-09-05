# Week 5 lab contract and validation evidence

Use the [Week 5 index](../README.md) as the single duration/track table. The core
path is 5.1 → 5.2 → 5.3 → 5.5 → 5.6; choose electives based on available hardware.
Run:AI is a licensed alternative/elective, not a prerequisite for the open KAI path.

## Common environment

Use a Bash session on the administration host. Set these once, then use explicit
kubeconfig arguments for management/workload mutations:

```bash
export CLUSTER_NAME=gpu-cluster
export CLUSTER_NAMESPACE=kcm-system
export MGMT_KUBECONFIG=$HOME/.kube/config
export WORKLOAD_KUBECONFIG=$HOME/.kube/gpu-cluster.conf
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n "$CLUSTER_NAMESPACE" get clusterdeployment "$CLUSTER_NAME"
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" get nodes -o wide
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" get nodes -o json | jq '
  [.items[] | {name:.metadata.name,gpus:(.status.allocatable["nvidia.com/gpu"] // "0"),
  ready:([.status.conditions[] | select(.type=="Ready")][0].status)}]'
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" get storageclass
```

Templates and Credentials must exist in the ClusterDeployment's namespace. If an
elective creates another namespace, distribute the required objects before use.
Do not infer SSH user or keys from the instance family; use the deployed AMI and
configured access path. Preserve management resources needed by later weeks.

## Compatibility contract

| Component | Baseline / decision |
|---|---|
| Management | Enterprise 1.3.1, upgraded to 1.3.2 in Lab 1.8 |
| AWS template | Discover the installed template and supported chain; management patch versions do not imply a template transition |
| KOF | 1.6.0 manual chart flow; upgrade requires a separately tested migration |
| GPU Operator | 25.3.0 on Ubuntu 22.04 with the documented k0s runtime paths |
| TensorRT lab | Separate driver ≥575 path and runtime compatibility check in Lab 5.13 |
| KAI | 0.12.10 in 5.1; explicitly upgrade to 0.14.0 for 5.3 and recheck queues/PodGroups |
| Legacy Training Operator | v1.8.1 provides PyTorchJob; Trainer v2 and MPI Operator have separate CRDs/installations |
| Namespace/context | Management `kcm-system`; workload kubeconfig explicitly selected |

## Hardware and access gates

| Track | Required before provisioning/running |
|---|---|
| Core | One g5.12xlarge worker, four A10G GPUs; Ubuntu 22.04; GPU quota; working management cluster |
| Run:AI | Instructor-provided licensed control plane, permissions and dedicated/configured scheduler environment |
| Jupyter / Milvus / MLflow | Bound persistent storage and enough free CPU/RAM after management and GPU services; use standalone Milvus baseline |
| FIPS | Qualified OS/kernel and configured crypto modules in the actual workload image; an Ubuntu/A10G smoke run is not compliance evidence |
| TensorRT | Driver/container/GPU/precision combination supported by the pinned TensorRT version |
| Slurm | Real RWX storage plus host mount support, cgroup v2, and the node count required by affinity rules |
| Distributed training | Two suitably sized GPU workers for the multi-node examples; bound RWX checkpoints; model/data access or explicit mock data |
| RDMA | Actual EFA/IB devices, interfaces, placement and device-plugin resources; the stock AWS template is only a negative control |
| External telemetry | Working child ingest, trusted TLS credentials, a receiver accepting metrics and logs, and synchronized clocks |
| Topology | Two free GPUs for label simulation; actual multi-node NVLink domains for performance claims |

An EBS RWO StorageClass does not satisfy an RWX PVC. Use a provisioned EFS/NFS/Ceph
service and compatible CSI driver, verify a two-node read/write test, then set its
actual StorageClass in the exercise. Do not start billable multi-node jobs while
required PVCs are Pending. Data sizes in examples are not a substitute for sizing.

Check current regional prices and quotas before allocating GPUs. Budget includes
control planes, workers, disks, load balancers, object/network storage and transfer;
record a teardown time. Hourly examples elsewhere are historical estimates.

## Validation status

The repository includes previous live observations and known failures. The review
corrections have static/chart checks; those checks do not establish live acceptance.
Every lab must carry evidence for the **exact revision** used by a cohort. Until
that evidence is collected, corrected execution paths remain pending live validation.

| Labs | Evidence needed before claiming end-to-end completion |
|---|---|
| 5.1–5.3 | GPU pod succeeds; queue behavior matches the pin; true gang capacity test, not concurrent plain Jobs |
| 5.4 | Licensed cluster connects; project quota and preemption demonstrated |
| 5.5–5.8 | Inference request, documented incident recovery, notebook persistence, vector insert/search/restart |
| 5.9–5.10 | Installed CRDs match APIs; pipeline/run succeeds; MLflow run metadata and artifacts survive restart |
| 5.11–5.12 | FIPS checks reject missing dependencies; correct template/chart version and healthy node replacement |
| 5.13–5.16 | Supported quantization, Slurm job, real RDMA transport, distributed checkpoint save/resume on required hardware |
| 5.17–5.18 | Metric/log arrival and buffered restart recovery; actual node/domain placement and qualified benchmark comparison |

For each run record: commit, date, executor, region/hardware/node count, OS/driver,
chart and image versions/digests, prerequisite checks, commands, expected/actual
assertions, sanitized logs, cleanup result, and one status: **end-to-end passed**,
**smoke only**, **reference only**, or **blocked**. Never include credentials.

A failed prerequisite is a useful diagnostic result but does not pass the intended
workload objective. Re-run affected acceptance checks after changing pins or code.
