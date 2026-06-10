# Lab 4.9 — Dynamic Resource Allocation (DRA) for GPUs

**Domain:** KaaS / GPU Scheduling / Resource API

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| KaaS / GPU Scheduling | Required | 2 hours |

### Week 4 Learning Paths

```
FOUNDATION       NETWORKING   STORAGE   OPERATIONS         TEMPLATES        SCHEDULING
4.1 -> 4.2 -> 4.3   4.4         4.5       4.6 -> 4.7         4.8              [4.9] DRA
                                                                                ↓
                                                                              [4.10] BYOIP
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 4.8 — ClusterTemplate Flavors](lab-4.8-clustertemplate-flavors.md) | **Lab 4.9 — Dynamic Resource Allocation (DRA)** | [Lab 4.10 — BYOIP / PCI / MACsec](lab-4.10-byoip-pci-macsec.md) |

---

**Duration:** 2 hours
**Type:** Hands-on Technical
**Environment:** k0rdent management cluster + a managed cluster with at least 2 GPU nodes

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: DRA vs device-plugin — when each wins](#part-1-dra-vs-device-plugin--when-each-wins)
- [Part 2: Enable DRA feature gates on the k0s control plane](#part-2-enable-dra-feature-gates-on-the-k0s-control-plane)
- [Part 3: Install the NVIDIA DRA driver](#part-3-install-the-nvidia-dra-driver)
- [Part 4: Run a workload backed by a ResourceClaim](#part-4-run-a-workload-backed-by-a-resourceclaim)
- [Part 5: Failure modes — unsatisfiable claims, debug, recovery](#part-5-failure-modes--unsatisfiable-claims-debug-recovery)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

Dynamic Resource Allocation (DRA) is the next-generation Kubernetes mechanism for allocating specialized hardware — GPUs, FPGAs, NICs with specific topology constraints. It replaces the legacy device-plugin model with parameterized resource requests (e.g., "give me a GPU with ≥40 GB memory AND NVLink to this other GPU"), ResourceClaim CRDs, and vendor-provided drivers. NVIDIA ships the k8s-dra-driver as the reference DRA driver for GPUs.

This lab teaches how to enable DRA feature gates on k0rdent Enterprise managed clusters, install the NVIDIA DRA driver, and write workloads that consume ResourceClaims.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Explain DRA vs the legacy device-plugin model and identify which use cases each handles
- [ ] Enable the required DRA feature gates on the k0s apiserver, controller-manager, scheduler, and kubelet without downtime
- [ ] Install the NVIDIA DRA driver and verify `DeviceClass` objects appear cluster-wide
- [ ] Write a `ResourceClaimTemplate` plus a Pod spec that consumes it
- [ ] Debug an unsatisfiable claim through `kubectl describe resourceclaim` + driver logs

---

## Prerequisites

- Lab 4.3 (NVIDIA GPU Operator installed) — **required**, DRA driver coexists with but does not replace the GPU Operator's driver/toolkit components
- Lab 4.4 (Cilium + Multus networking) — recommended, makes the multi-GPU NVLink topology examples meaningful
- A managed cluster with **at least 2 GPU nodes** (so allocation is non-trivial)
- `kubectl` (matching cluster minor version), `helm` v3.12+, cluster-admin on the managed cluster
- k0s ≥ v1.31 on the managed cluster (DRA v1beta1 API requires it)

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| Where to enable DRA feature gates | Per-ClusterTemplate (only for GPU flavors) | Default-on for every managed cluster | **Default-on for every cluster** — DRA should be available regardless of upstream feature status; per-template gating creates silent capability drift between clusters and is operationally fragile |
| GPU DRA driver source | NVIDIA's `k8s-dra-driver` | A custom in-house driver | **NVIDIA `k8s-dra-driver`** ([repo](https://github.com/NVIDIA/k8s-dra-driver)) — it's the reference implementation NVIDIA itself ships; custom drivers are hard to justify unless you can show feature parity |
| Claim binding style | Inline `ResourceClaim` per pod | `ResourceClaimTemplate` referenced by pod spec | **`ResourceClaimTemplate`** for any workload with `replicas > 1` or Job-style retries — the template generates a fresh claim per pod, so claims are garbage-collected with the pod and don't pile up |
| Admission policy for misconfigured claims | Let scheduler keep retrying (`Pending` forever) | Reject at admission via ValidatingAdmissionPolicy | **Reject at admission** — fail-fast on impossible selectors (e.g., asking for a GPU SKU you don't have) gives tenants an immediate error instead of a stuck pod the on-call has to triage |
| Coexistence with device-plugin GPU requests | Migrate everything to DRA immediately | Run both side-by-side during transition | **Run both side-by-side** for ≥1 release cycle — tenants on legacy `nvidia.com/gpu: 1` keep working while new tenants opt into DRA; both models can target the same physical GPU pool through the NVIDIA driver |

---

## Part 1: DRA vs device-plugin — when each wins

The legacy device-plugin model treats a GPU as an opaque counter (`nvidia.com/gpu: 1`). That single integer cannot express *"GPU with ≥40 GB"*, *"2 GPUs sharing an NVLink domain"*, *"MIG slice 2g.20gb"*, or *"time-sliced GPU"*. DRA replaces the counter with a **claim**, resolved by the driver against `ResourceSlice` objects published by each node:

```yaml
# DRA-style request — parameterized
apiVersion: resource.k8s.io/v1beta1
kind: ResourceClaimTemplate
metadata:
  name: a100-40gb
spec:
  spec:
    devices:
      requests:
      - name: gpu
        deviceClassName: gpu.nvidia.com
        selectors:
        - cel:
            expression: |
              device.attributes["gpu.nvidia.com"].productName.contains("A100") &&
              device.attributes["gpu.nvidia.com"].memoryGB >= 40
```

**Decision rule:**

| Workload pattern | Use |
|------------------|-----|
| "I just need a GPU, any GPU" | Either — device-plugin is simpler |
| "I need a specific SKU / memory size / MIG profile" | **DRA** |
| "I need N GPUs with NVLink topology constraints" | **DRA** |
| "Tenant is on Kubeflow / Slurm-on-K8s / Ray that emits ResourceClaims" | **DRA** (no choice) |
| Multi-vendor heterogeneous fleet (NVIDIA + AMD + Intel GPUs) | **DRA** — each vendor ships its own DRA driver |

The operational rule is: **DRA must be available**. Whether your tenants use it today or not, the capability must be on.

---

## Part 2: Enable DRA feature gates on the k0s control plane

DRA is graduating across versions; on k0s v1.31+ the core API is `v1beta1`. You enable it by passing feature gates and the API-group to every control-plane component **and** the kubelet.

**Required feature gates (k0s v1.31, K8s v1.31):**

| Component | Feature gate(s) |
|-----------|-----------------|
| kube-apiserver | `DynamicResourceAllocation=true`, `DRAResourceClaimDeviceStatus=true` |
| kube-controller-manager | `DynamicResourceAllocation=true` |
| kube-scheduler | `DynamicResourceAllocation=true` |
| kubelet (per node) | `DynamicResourceAllocation=true` |

Additionally enable the API group on the apiserver:

```
--runtime-config=resource.k8s.io/v1beta1=true
```

### k0s config patch

In your k0rdent `ClusterTemplate` for the GPU flavor (or the `k0s.yaml` of an existing managed cluster), patch `spec.k0s.config`:

```yaml
# k0s.yaml (snippet — applies to managed cluster control plane)
spec:
  api:
    extraArgs:
      feature-gates: "DynamicResourceAllocation=true,DRAResourceClaimDeviceStatus=true"
      runtime-config: "resource.k8s.io/v1beta1=true"
  controllerManager:
    extraArgs:
      feature-gates: "DynamicResourceAllocation=true"
  scheduler:
    extraArgs:
      feature-gates: "DynamicResourceAllocation=true"
  workerProfiles:
  - name: gpu-worker
    values:
      featureGates:
        DynamicResourceAllocation: true
```

Apply the patch through k0rdent's `ClusterDeployment` update flow — do **not** edit the live cluster's k0s config out-of-band; the next reconcile would revert it.

### Rolling out without downtime

```bash
# 1. Patch the ClusterDeployment (or ClusterTemplate) and let k0rdent reconcile
kubectl -n <namespace> patch clusterdeployment <name> --type merge --patch-file dra-patch.yaml

# 2. Watch the rollout — control plane first, workers second
kubectl -n <namespace> get clusterdeployment <name> -w

# 3. Once control plane is upgraded, verify the API group is live
kubectl --context <managed> api-resources | grep resource.k8s.io
# Expect: deviceclasses, resourceclaims, resourceclaimtemplates, resourceslices
```

Because the API server restarts one replica at a time (HA control plane from Lab 4.1), and the kubelet restart is benign for running pods, the rollout is zero-downtime.

### Confirm feature gates are active

```bash
kubectl --context <managed> get --raw /metrics | grep kubernetes_feature_enabled | grep -i dynamic
# Expect: kubernetes_feature_enabled{name="DynamicResourceAllocation",stage="BETA"} 1
```

---

## Part 3: Install the NVIDIA DRA driver

The driver source and helm chart live at [github.com/NVIDIA/k8s-dra-driver](https://github.com/NVIDIA/k8s-dra-driver). It runs as a DaemonSet on each GPU node and a Deployment for the controller.

```bash
# 1. Add the helm repo (per upstream README at the repo above)
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# 2. Install in a dedicated namespace
kubectl create namespace nvidia-dra-driver

helm upgrade --install nvidia-dra-driver nvidia/nvidia-dra-driver-gpu \
  --namespace nvidia-dra-driver \
  --set nvidiaDriverRoot=/run/nvidia/driver \
  --set deviceClasses="{gpu,mig}" \
  --wait
```

> **Heads-up:** the chart name and value keys track upstream. Pin the chart version (`--version`) once you've validated a release — don't float `latest` on a managed cluster.

### Verify driver health and DeviceClass registration

```bash
kubectl -n nvidia-dra-driver get pods
# Expect: nvidia-dra-driver-controller-* Running
#         nvidia-dra-driver-kubelet-plugin-* Running on every GPU node

kubectl get deviceclasses
# Expect at least:
#   gpu.nvidia.com
#   mig.nvidia.com
```

Each GPU node should publish a `ResourceSlice` advertising its devices:

```bash
kubectl get resourceslices -o wide
kubectl describe resourceslice <one-of-them>
# Inspect the spec.devices[] — each entry has attributes like
# productName, memoryGB, computeCapability, driverVersion
```

If `ResourceSlice` objects don't appear within ~60 s of the kubelet-plugin pod being Ready, jump to [Troubleshooting](#troubleshooting).

### Define a ResourceClaimTemplate

```yaml
# rct-a100-40gb.yaml
apiVersion: resource.k8s.io/v1beta1
kind: ResourceClaimTemplate
metadata:
  name: a100-40gb
  namespace: tenant-a
spec:
  spec:
    devices:
      requests:
      - name: gpu
        deviceClassName: gpu.nvidia.com
        selectors:
        - cel:
            expression: |
              device.attributes["gpu.nvidia.com"].productName.contains("A100") &&
              device.attributes["gpu.nvidia.com"].memoryGB >= 40
```

```bash
kubectl apply -f rct-a100-40gb.yaml
kubectl -n tenant-a get resourceclaimtemplates
```

---

## Part 4: Run a workload backed by a ResourceClaim

A pod consumes a template through the `resourceClaims` block and references it from a container's `resources.claims`:

```yaml
# pod-cuda-vectoradd.yaml
apiVersion: v1
kind: Pod
metadata:
  name: cuda-vectoradd
  namespace: tenant-a
spec:
  restartPolicy: Never
  resourceClaims:
  - name: my-gpu
    resourceClaimTemplateName: a100-40gb
  containers:
  - name: cuda-vectoradd
    image: nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda11.7.1
    resources:
      claims:
      - name: my-gpu
```

```bash
kubectl apply -f pod-cuda-vectoradd.yaml

# Watch the lifecycle
kubectl -n tenant-a get pod cuda-vectoradd -w

# The scheduler creates a ResourceClaim from the template
kubectl -n tenant-a get resourceclaims
# Expect: cuda-vectoradd-my-gpu-<random>  Allocated  <node>

# Pod should reach Completed
kubectl -n tenant-a logs cuda-vectoradd
# Expect CUDA vectoradd "Test PASSED" output
```

### Multi-GPU claim (illustrative)

For two GPUs in the same NVLink domain, request a count and constrain them with a matchAttribute:

```yaml
spec:
  devices:
    requests:
    - name: pair
      deviceClassName: gpu.nvidia.com
      count: 2
      selectors:
      - cel:
          expression: device.attributes["gpu.nvidia.com"].productName.contains("A100")
    constraints:
    - matchAttribute: "gpu.nvidia.com/nvlinkDomain"
      requests: ["pair"]
```

The `matchAttribute` constraint forces both allocated devices to share the same NVLink-domain attribute value — the scheduler will not split the pair across NVLink islands.

---

## Part 5: Failure modes — unsatisfiable claims, debug, recovery

DRA introduces failure modes operators rarely see with device-plugin. Know each one.

### Failure mode 1: claim that can never be satisfied

A claim that asks for `memoryGB >= 200` on a fleet of 80 GB H100s. The pod sits `Pending` indefinitely:

```bash
kubectl -n tenant-a describe pod cuda-vectoradd
# Events:
#   FailedScheduling  ... no suitable devices: 0/N nodes have devices matching <claim>
```

Investigation path:

```bash
# 1. See what the claim is asking for
kubectl -n tenant-a get resourceclaim <name> -o yaml | yq .spec

# 2. See what the cluster actually has
kubectl get resourceslices -o json | jq '.items[].spec.devices[].attributes'

# 3. Compare — does any device match the selector?
```

**Mitigation:** add a `ValidatingAdmissionPolicy` that rejects claims whose CEL selector matches zero `ResourceSlice` devices at admit time.

### Failure mode 2: driver crash mid-allocation

Kubelet-plugin pod restarts while holding allocations. On restart the driver reconciles state from `ResourceClaim.status.allocation` — but if you upgraded across an incompatible spec version, claims may show `Allocated` with no actual device backing them. Mitigation: pin driver chart version; test upgrades in a non-prod managed cluster first.

```bash
kubectl -n nvidia-dra-driver logs ds/nvidia-dra-driver-kubelet-plugin --previous
```

### Failure mode 3: claim leaks (only with inline `ResourceClaim`, not Template)

If a tenant creates a standalone `ResourceClaim` (not via Template) and the consuming pod never schedules, the claim holds the allocation forever. With `ResourceClaimTemplate`, the generated claim has an owner reference to the pod and is garbage-collected on pod deletion.

```bash
# Find orphaned claims (no owner references, not Allocated to any pod)
kubectl get resourceclaims -A -o json | \
  jq '.items[] | select(.metadata.ownerReferences == null) | .metadata.name'
```

**Mitigation:** the Architectural Decision Frame recommendation — default to `ResourceClaimTemplate`.

### Failure mode 4: feature gate drift after k0s upgrade

A k0s upgrade resets `extraArgs` if the new `ClusterTemplate` doesn't carry them forward. The apiserver loses `resource.k8s.io/v1beta1` and every existing `ResourceClaim` becomes invisible. Mitigation: CI smoke test running `kubectl api-resources | grep resource.k8s.io` after every cluster upgrade.

---

## Verification Checklist

- [ ] `kubernetes_feature_enabled{name="DynamicResourceAllocation"} 1` on the apiserver `/metrics` endpoint
- [ ] `kubectl api-resources` shows `deviceclasses`, `resourceclaims`, `resourceclaimtemplates`, `resourceslices`
- [ ] NVIDIA DRA driver controller + kubelet-plugin pods Running on every GPU node
- [ ] `kubectl get deviceclasses` returns at least `gpu.nvidia.com`
- [ ] Each GPU node publishes a `ResourceSlice` with device attributes populated
- [ ] Sample `cuda-vectoradd` pod with a `ResourceClaimTemplate`-backed GPU completes successfully
- [ ] Multi-GPU NVLink-domain `matchAttribute` constraint correctly fails when topology can't be satisfied

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `error: the server doesn't have a resource type "resourceclaims"` | API group `resource.k8s.io/v1beta1` not in `--runtime-config` | Patch `ClusterDeployment` to add the runtime-config arg; reconcile |
| Driver pods Running but no `ResourceSlice` objects appear | Kubelet feature gate `DynamicResourceAllocation` not enabled on the worker | Patch `workerProfiles.featureGates`; restart kubelet via k0s reconcile |
| Pod stuck `Pending` with `FailedScheduling: no suitable devices` | Claim selector matches zero device attributes in any `ResourceSlice` | Compare claim CEL vs actual device attributes; loosen selector or fix GPU labels |
| `ResourceClaim` shows `Allocated` but pod stuck `ContainerCreating` | Kubelet-plugin crashed after allocation; container runtime can't get device handle | `kubectl -n nvidia-dra-driver logs ds/nvidia-dra-driver-kubelet-plugin --previous`; pin chart version |
| All claims invisible after a cluster upgrade | k0s upgrade dropped `extraArgs` because the new `ClusterTemplate` doesn't carry them | Re-patch the `ClusterTemplate` to carry feature gates forward; add CI smoke test |

---

## Key Takeaways

- **DRA is a forward-looking contract, not a feature flag.** Enable it on every managed cluster, not just GPU-flavored ones, because tenants choose the API — you can't pre-guess who needs it.
- **Feature gates must survive upgrades.** The single most common DRA outage is a `ClusterTemplate` change that silently drops `extraArgs`. Make "API group still registered" a CI smoke test on every upgrade.
- **Prefer `ResourceClaimTemplate` over inline `ResourceClaim`.** Owner references mean claims are GC'd with their pods — no leaks, no orphaned allocations after a tenant cleanup script forgets a resource.

---

## Next Lab

[Lab 4.10 — Case Study: AI Cloud Provider Interconnect Patterns](lab-4.10-byoip-pci-macsec.md) — once tenants can claim GPUs by capability, the next layer is **how those GPUs reach external networks**: BYOIP allocations, dedicated interconnect with BGP, and MACsec link encryption.
