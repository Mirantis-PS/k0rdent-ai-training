# Lab 4.4: Custom CNI — Cilium as Primary CNI + Multus Secondary Networks

**Duration:** 2 hours (~60 min active, ~25-30 min waiting for provisioning)
**Type:** Hands-on Lab

> **Validation note:** Validated end-to-end on **k0rdent Enterprise 1.3.2**
> (template `aws-standalone-cp-1-0-26`, Cilium 1.19.0, Multus v4.3.0,
> whereabouts v0.9.4, CNI plugins v1.9.1) in eu-west-2 on **2026-07-03**:
> custom-provider cluster `Ready`, kube-proxy replaced (eBPF), and a
> two-interface pod passing traffic over the ipvlan secondary network.
> Three findings from that run are baked into the steps below — the
> `cni.exclusive: false` value (Part 3), the **mandatory** `cniIngressRules`
> patch for tunnel traffic (Part 3b), and the CNI reference-plugins install
> (Part 5).

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Networking | Required | 2 hours |

### Week 4 Learning Paths

```
FOUNDATION (start here)        NETWORKING       STORAGE         OPERATIONS              TEMPLATES
4.1 -> 4.2 -> 4.3              4.4              4.5             4.6 -> 4.7              4.8
                               ^
                               YOU ARE HERE
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 4.1 — Hosted Control Plane](lab-4.1-hosted-control-plane.md) (4.2/4.3 in development) | **Lab 4.4 — Cilium + Multus** | [Lab 4.9 — Dynamic Resource Allocation](lab-4.9-dynamic-resource-allocation.md) (4.5-4.8 in development) |

> **Downstream consumer:** [Lab 5.18 — topograph / NVLink Topology](../../week-5-ai-workloads/labs/lab-5.18-topograph-nvlink-topology.md)
> lists this lab as a required prerequisite — the secondary network you build
> in Parts 5-7 is the pattern AI clusters use to separate RDMA/storage traffic
> from the primary pod network.

---

## Table of Contents

- [Overview](#overview)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Cost Considerations](#cost-considerations)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: Pre-flight — Does Your Template Support `k0s.network`? (~10 min)](#part-1-pre-flight--does-your-template-support-k0snetwork-10-min)
- [Part 2: Create the ClusterDeployment with `provider: custom` (~10 min)](#part-2-create-the-clusterdeployment-with-provider-custom-10-min)
- [Part 3: Deliver Cilium via MultiClusterService (~10 min)](#part-3-deliver-cilium-via-multiclusterservice-10-min)
- [Part 3b: Open the Tunnel Ports — Mandatory (~5 min)](#part-3b-open-the-tunnel-ports--mandatory-5-min)
- [Part 4: Watch the Cluster Come Alive (~25 min, mostly waiting)](#part-4-watch-the-cluster-come-alive-25-min-mostly-waiting)
- [Part 5: Install Multus (~10 min)](#part-5-install-multus-10-min)
- [Part 6: Define a Secondary Network (~10 min)](#part-6-define-a-secondary-network-10-min)
- [Part 7: Validate the Two-Interface Pod (~15 min)](#part-7-validate-the-two-interface-pod-15-min)
- [Cleanup (~5 min)](#cleanup-5-min)
- [Verification Checklist](#verification-checklist)
- [Deliverable](#deliverable)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)
- [References](#references)

---

## Overview

Every managed cluster you have provisioned so far (Labs 1.5, 4.1) came up with
**Calico** — because the `aws-standalone-cp` chart's k0s `ClusterConfig`
defaults to it. This lab replaces the default with a CNI *you* choose, then
adds a second network on top:

1. **Primary CNI swap:** provision a cluster with `k0s.network.provider: custom`
   (k0s installs *no* CNI), and deliver **Cilium** through the same
   `MultiClusterService` machinery you learned in Lab 1.7. Cilium runs in
   **kube-proxy replacement** mode — the cluster boots without kube-proxy at
   all, and eBPF handles service load-balancing.
2. **Secondary networks:** install **Multus**, a meta-CNI that lets a pod
   attach to *additional* networks beyond the primary CNI, and validate a pod
   with two interfaces (`eth0` from Cilium, `net1` from an ipvlan
   `NetworkAttachmentDefinition`).

The pedagogical core is the **delivery model**: the CNI is not "part of the
cluster" — it is a *service* delivered declaratively from the management
cluster, versioned in the catalog, and swappable per-cluster via labels. That
is what "bring your preferred CNI" means in a KaaS product.

> **Why AI platforms care:** multi-node training separates traffic classes —
> the primary CNI carries control/API traffic while RDMA (EFA, InfiniBand)
> rides dedicated interfaces injected by Multus (usually via the NVIDIA
> network operator). Lab 5.18's topology-aware scheduling assumes this
> secondary-network layout exists.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Determine whether a `ClusterTemplate` revision exposes the k0s network config (`k0s.network` passthrough)
- [ ] Provision a managed cluster with **no built-in CNI** (`provider: custom`) and **no kube-proxy**
- [ ] Deliver Cilium as the primary CNI via a catalog `ServiceTemplate` + `MultiClusterService`
- [ ] Explain the bootstrap sequence: why nodes sit `NotReady` until the CNI arrives, and why that is safe
- [ ] Install Multus and author a `NetworkAttachmentDefinition` for a secondary interface
- [ ] Validate a two-interface pod and articulate the AWS-specific constraints (MAC filtering, src/dst checks) on secondary networks

---

## Prerequisites

**Required from earlier weeks:**

- Labs 1.1-1.5 complete (management cluster + `aws-cluster-identity-cred` in `kcm-system`)
- Lab 1.7 complete (you know `ServiceTemplate` / `MultiClusterService` and the `k0rdent-catalog` HelmRepository)
- `kubectl` pointed at the **management cluster**

**Tools and configuration:**

- `kubectl` v1.32+, `helm` v3.14+, `jq`
- AWS CLI v2, `AWS_REGION` exported and matching your management cluster's region

**Versions used in this lab:**

| Component | Version | Source |
|-----------|---------|--------|
| Cilium | 1.19.0 | k0rdent catalog ServiceTemplate `cilium-1-19-0` |
| Multus CNI | v4.3.0 | upstream `k8snetworkplumbingwg/multus-cni` (thick plugin) |
| whereabouts IPAM | v0.9.4 | upstream `k8snetworkplumbingwg/whereabouts` |

---

## Cost Considerations

> **Important:** This lab provisions real AWS infrastructure that incurs costs.
>
> - **Estimated AWS cost during the lab:** ~$0.15/hour (2× t3.medium: 1 control plane + 1 worker)
> - No load balancer is provisioned by this lab beyond the CP API NLB the template always creates
> - Clean up the cluster at the end of the lab — nothing later in Week 4 needs it

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| Primary CNI delivery | k0s built-in (`provider: calico`) | `provider: custom` + CNI as a k0rdent service | **Custom + service** for products — the CNI becomes versionable, upgradeable, and swappable fleet-wide; built-in only for quick disposable clusters |
| kube-proxy | Keep (Cilium coexists) | Disable (`kubeProxy.disabled: true`, Cilium eBPF replaces it) | **Disable at cluster creation** — kube-proxy replacement is Cilium's headline value; retrofitting it later means draining iptables state |
| Cilium install mechanism | `MultiClusterService` (label-selected fleet) | Inline `spec.serviceSpec` on one `ClusterDeployment` | **MultiClusterService** — "every cluster labeled `cni=cilium` gets Cilium" is the fleet story; inline is fine for one-offs |
| Secondary-network CNI on AWS | macvlan | ipvlan | **ipvlan** — macvlan generates new MACs per pod and AWS drops frames from unknown MACs; ipvlan shares the parent NIC's MAC |
| Secondary-network IPAM | static (per-pod) | whereabouts (cluster-wide ranges) | **whereabouts** — same pattern the NVIDIA network operator uses; static only for two-pod demos |

---

## Part 1: Pre-flight — Does Your Template Support `k0s.network`? (~10 min)

The k0s `ClusterConfig` that `aws-standalone-cp` renders **hardcoded**
`provider: calico` up to chart revision `1-0-13`. The `k0s.network`
passthrough (added upstream in k0rdent 1.4.0, chart `1-0-14`) is what lets a
`ClusterDeployment` choose the provider. Check what you have:

```bash
# What aws-standalone-cp revisions does your install ship?
kubectl get clustertemplates -n kcm-system | grep aws-standalone-cp
```

Expected (k0rdent Enterprise 1.3.2):

```
aws-standalone-cp-1-0-26   true
```

Set the template name for the rest of the lab:

```bash
export TEMPLATE_NAME="aws-standalone-cp-1-0-26"   # adjust to your newest revision
```

Now verify the passthrough exists in that chart. Pull the chart the template
references and grep its control-plane template:

```bash
# Where does the template's chart come from?
CHART_NAME=$(kubectl get clustertemplate $TEMPLATE_NAME -n kcm-system \
  -o jsonpath='{.status.chartRef.name}')

# The artifact URL uses cluster-internal DNS (source-controller.kcm-system.svc...),
# which does not resolve from the mgmt node — substitute the service's ClusterIP:
CHART_URL=$(kubectl get helmchart -n kcm-system "$CHART_NAME" \
  -o jsonpath='{.status.artifact.url}')
SVC_IP=$(kubectl get svc source-controller -n kcm-system -o jsonpath='{.spec.clusterIP}')
curl -sL "${CHART_URL/source-controller.kcm-system.svc.cluster.local./$SVC_IP}" \
  | tar -xzO --wildcards '*/templates/k0scontrolplane.yaml' \
  | grep -c 'Values.k0s.network'
```

- **Output `1` (or more):** your template supports `k0s.network` — continue to Part 2.
- **Output `0`:** your revision predates the passthrough. Fork the template
  the same way Lab 4.1 forked `aws-hosted-cp`
  (see `lab-infrastructure/scripts/lab-4.1-fork-hosted-cp-template.sh` for the
  pattern): copy the chart, replace the hardcoded `network:` block in
  `templates/k0scontrolplane.yaml` with the upstream `{{- with .Values.k0s.network }}`
  passthrough, bump the chart version, republish, and register. Lab 4.8
  generalizes this workflow.

> **Why a passthrough and not a patch?** `ClusterTemplate` objects are
> immutable, and the k0s network provider is immutable *per cluster* — k0s
> docs are explicit that changing providers requires full cluster
> redeployment. The decision must be expressible at `ClusterDeployment`
> creation time, which is exactly what the values passthrough enables.

---

## Part 2: Create the ClusterDeployment with `provider: custom` (~10 min)

Two things differ from Lab 1.5's manifest: the `k0s.network` block, and a
`clusterLabels` entry that Part 3's `MultiClusterService` will select on.

First, find an Ubuntu 22.04 AMI for your region (same convention as Lab 4.1 —
the default Amazon Linux image lookup is not what we want):

```bash
export UBUNTU_AMI=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*' \
            'Name=state,Values=available' \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
echo "$UBUNTU_AMI"
```

Create the deployment:

```bash
export CLUSTER_NAME=managed-cluster-04

cat <<EOF > /tmp/${CLUSTER_NAME}.yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: ${CLUSTER_NAME}
  namespace: kcm-system
  labels:
    cni: cilium
spec:
  template: ${TEMPLATE_NAME}
  credential: aws-cluster-identity-cred
  dryRun: false
  cleanupOnDeletion: true
  config:
    region: ${AWS_REGION}
    publicIP: true
    controlPlaneNumber: 1
    controlPlane:
      instanceType: t3.medium
      rootVolumeSize: 50
      amiID: ${UBUNTU_AMI}
    workersNumber: 1
    worker:
      instanceType: t3.medium
      rootVolumeSize: 50
      amiID: ${UBUNTU_AMI}
    clusterIdentity:
      name: aws-cluster-identity
      kind: AWSClusterStaticIdentity
    k0s:
      network:
        provider: custom
        calico: null
        kubeProxy:
          disabled: true
EOF

kubectl apply -f /tmp/${CLUSTER_NAME}.yaml
```

Dissecting the `k0s.network` block:

- `provider: custom` — k0s installs **no CNI**. Nodes will register and then
  wait, `NotReady`, for someone to bring networking.
- `calico: null` — follows the k0rdent catalog's reference manifest. Note:
  k0rdent's values merge does *not* actually prune the chart's default
  `calico: {mode: ipip}` sub-block (you will still see it in the rendered
  `K0sControlPlane`) — it is simply inert once `provider` isn't `calico`.
- `kubeProxy.disabled: true` — no kube-proxy DaemonSet. Cilium (Part 3) runs
  with `kubeProxyReplacement: "true"` and takes over service load-balancing
  in eBPF. This mirrors Cilium's official k0s installation guide.

> **`metadata.labels` vs `config.clusterLabels`:** `MultiClusterService`
> selectors match the **`ClusterDeployment`'s metadata labels** (as Lab 1.7
> documents), which is why `cni: cilium` sits under `metadata.labels` above.
> `config.clusterLabels` does something different — it propagates labels to
> the underlying CAPI `Cluster` object — and is **not** used for MCS
> targeting. (Confirmed live: a cluster labeled only via `clusterLabels` is
> silently ignored by the MCS — no error anywhere, just no deployment.)

---

## Part 3: Deliver Cilium via MultiClusterService (~10 min)

While CAPA builds the EC2 instances, set up the delivery. Ensure the catalog
`HelmRepository` exists (created in Lab 1.2/1.7):

```bash
kubectl get helmrepositories -n kcm-system | grep k0rdent-catalog || \
cat <<EOF | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: k0rdent-catalog
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/managed: "true"
spec:
  type: oci
  url: oci://ghcr.io/k0rdent/catalog/charts
  interval: 10m0s
  provider: generic
EOF
```

Register the Cilium `ServiceTemplate`:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ServiceTemplate
metadata:
  name: cilium-1-19-0
  namespace: kcm-system
spec:
  helm:
    chartSpec:
      chart: cilium
      version: 1.19.0
      interval: 10m0s
      sourceRef:
        kind: HelmRepository
        name: k0rdent-catalog
EOF

kubectl get servicetemplate cilium-1-19-0 -n kcm-system   # VALID column must be true
# (VALID shows false for the first ~30-60s while the chart is pulled from ghcr — re-check)
```

Create the `MultiClusterService`. The values below follow the k0rdent
catalog's reference configuration for Cilium on AWS:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: cilium-cni
spec:
  clusterSelector:
    matchLabels:
      cni: cilium
  serviceSpec:
    services:
    - template: cilium-1-19-0
      name: cilium
      namespace: cilium
      values: |
        cilium:
          cluster:
            name: ${CLUSTER_NAME}
          cni:
            exclusive: false
          kubeProxyReplacement: "true"
          k8sServiceHost: "{{ .Cluster.spec.controlPlaneEndpoint.host }}"
          k8sServicePort: "{{ .Cluster.spec.controlPlaneEndpoint.port }}"
          ipam:
            mode: cluster-pool
            operator:
              clusterPoolIPv4PodCIDRList:
              - "10.244.0.0/16"
          tunnelProtocol: geneve
          ipv4:
            enabled: true
          ipv6:
            enabled: false
          envoy:
            enabled: false
          hubble:
            relay:
              enabled: false
            ui:
              enabled: false
            tls:
              enabled: false
EOF
```

Four values deserve attention:

- **`cni.exclusive: false`** — **required for Part 5.** By default (`true`)
  the Cilium agent takes exclusive ownership of `/etc/cni/net.d` and renames
  any other CNI config it finds to `*.cilium_bak` — which silently evicts
  Multus minutes after you install it (confirmed live: pods requesting a
  secondary network come up with only `eth0`, no error anywhere). Setting it
  here, at install time, is much cleaner than discovering it in Part 7.

- **`k8sServiceHost` / `k8sServicePort`** — with kube-proxy disabled there is
  no `kubernetes.default` ClusterIP plumbing at bootstrap; Cilium must be
  told the API endpoint directly. The `{{ .Cluster.spec.controlPlaneEndpoint.* }}`
  expressions are Sveltos templating, resolved per-cluster at apply time —
  this one `MultiClusterService` works unmodified for every cluster it selects.
- **`clusterPoolIPv4PodCIDRList: 10.244.0.0/16`** — matches the template's
  `clusterNetwork.pods` default, which is also what the AWS cloud controller
  manager receives as `--cluster-cidr`. Keeping them aligned avoids
  hard-to-debug IPAM mismatches.
- **`tunnelProtocol: geneve`** — overlay mode; no VPC route-table
  programming or ENI IPAM required, so it works with the stock CAPA IAM
  policy. (Cilium's ENI-native mode exists but needs extra IAM and is out of
  scope here.)

---

## Part 3b: Open the Tunnel Ports — Mandatory (~5 min)

CAPA creates the node/control-plane security groups with **Calico-oriented
CNI rules only** (TCP 179 for BGP, protocol 4 for IP-in-IP). Cilium's geneve
tunnel (UDP 6081) is **not** among them, so without this step every
*cross-node* pod packet silently blackholes — same-node traffic works, nodes
go `Ready`, and the failure only surfaces later as flaky DNS or unreachable
pods (confirmed live; it is a miserable thing to debug after the fact).

The CAPA-native mechanism is `AWSCluster.spec.network.cni.cniIngressRules` —
CAPA reconciles these into both security groups (note: they **replace** the
Calico defaults, which is what you want here). The `aws-standalone-cp` chart
does not currently expose this as a value (not even on upstream `main`), so
patch the generated `AWSCluster` once it exists (~1 min after Part 2):

```bash
kubectl patch awscluster ${CLUSTER_NAME} -n kcm-system --type=merge -p '{
  "spec": {"network": {"cni": {"cniIngressRules": [
    {"description": "cilium geneve tunnel", "protocol": "udp",  "fromPort": 6081, "toPort": 6081},
    {"description": "cilium health checks", "protocol": "tcp",  "fromPort": 4240, "toPort": 4240},
    {"description": "cilium health ICMP",   "protocol": "icmp", "fromPort": 8,    "toPort": 0}
  ]}}}
}'
```

Verify the rules landed (CAPA reconciles within ~1 minute):

```bash
aws ec2 describe-security-groups \
  --filters "Name=tag:sigs.k8s.io/cluster-api-provider-aws/cluster/${CLUSTER_NAME},Values=owned" \
  --query 'SecurityGroups[].[GroupName,IpPermissions[].{proto:IpProtocol,port:FromPort}]'
# Expect udp/6081, tcp/4240, icmp on both the -node and -controlplane groups
```

> **Why a patch and not template values?** This is a genuine gap in the
> template family: `awscluster.yaml` hardcodes its `network` block. The patch
> is the CAPA-documented mechanism and survives reconciliation (CAPA owns the
> SGs and converges them to this spec). If you fork templates in Lab 4.8,
> exposing `cniIngressRules` as a chart value is a prime candidate — as is an
> upstream k0rdent PR.

---

## Part 4: Watch the Cluster Come Alive (~25 min, mostly waiting)

The bootstrap sequence is the lesson. Watch it in two terminals.

**Terminal 1 — deployment status:**

```bash
watch kubectl get clusterdeployment ${CLUSTER_NAME} -n kcm-system
```

**Terminal 2 — the story on the workload cluster.** Once the control plane
answers, fetch the kubeconfig:

```bash
kubectl get secret ${CLUSTER_NAME}-kubeconfig -n kcm-system \
  -o jsonpath='{.data.value}' | base64 -d > /tmp/${CLUSTER_NAME}.kubeconfig
export KC="--kubeconfig=/tmp/${CLUSTER_NAME}.kubeconfig"

kubectl $KC get nodes
```

You will see the **CNI-less phase** — this is expected, not a failure:

```
NAME                                        STATUS     ROLES           AGE   VERSION
managed-cluster-04-cp-0                     NotReady   control-plane   3m    v1.32.x+k0s
managed-cluster-04-md-xxxxx-yyyyy           NotReady   <none>          1m    v1.32.x+k0s
```

`kubectl $KC describe node <node> | grep -A2 Ready` shows the reason:
`container runtime network not ready: cni plugin not initialized`. The
API server, etcd, and kubelets are all fine — kubelets simply refuse to run
non-host-network pods until a CNI config appears in `/etc/cni/net.d`.

Meanwhile k0rdent's Sveltos machinery applies the `MultiClusterService`.
Track it from the management cluster:

```bash
kubectl get clustersummaries -A | grep ${CLUSTER_NAME}
kubectl get clusterdeployment ${CLUSTER_NAME} -n kcm-system \
  -o jsonpath='{.status.services}' | jq
```

When the Cilium release deploys, nodes flip `Ready` within a minute or two:

```bash
kubectl $KC -n cilium get pods -o wide
kubectl $KC get nodes
```

Validate the dataplane:

```bash
# 1. kube-proxy really is absent
kubectl $KC -n kube-system get ds kube-proxy 2>&1   # expect NotFound

# 2. Cilium confirms eBPF kube-proxy replacement
CILIUM_POD=$(kubectl $KC -n cilium get pod -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
kubectl $KC -n cilium exec $CILIUM_POD -c cilium-agent -- cilium-dbg status | grep KubeProxyReplacement

# 3. Service load-balancing works end-to-end (DNS resolves via ClusterIP)
kubectl $KC run dns-check --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup kubernetes.default.svc.cluster.local
```

Expected: `KubeProxyReplacement: True` and a successful DNS answer.

---

## Part 5: Install Multus (~10 min)

Multus is a *meta*-CNI: it becomes the first CNI invoked by the kubelet,
delegates the primary interface to Cilium untouched, then attaches extra
interfaces per the pod's `k8s.v1.cni.cncf.io/networks` annotation.

Install the **thick** plugin (v4.3.0) on the workload cluster:

```bash
kubectl $KC apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v4.3.0/deployments/multus-daemonset-thick.yml
```

> **k0s path note:** k0s uses the standard CNI paths (`/etc/cni/net.d`,
> `/opt/cni/bin`), so Multus's defaults work. The thick plugin's daemon also
> reads the kubelet pod-resources socket from `/var/lib/kubelet` — on k0s
> that directory lives at `/var/lib/k0s/kubelet`. If the `kube-multus-ds`
> pods crashloop citing `pod-resources`, patch the DaemonSet hostPath:
>
> ```bash
> kubectl $KC -n kube-system patch ds kube-multus-ds --type=json -p='[
>   {"op":"replace","path":"/spec/template/spec/volumes/3/hostPath/path","value":"/var/lib/k0s/kubelet"}]'
> ```
>
> (Check `kubectl $KC -n kube-system get ds kube-multus-ds -o yaml` for the
> actual volume index — verify before patching.)

Multus delegates secondary interfaces to the **CNI reference plugins**
(`ipvlan`, `macvlan`, `static`, …) — and on a `provider: custom` cluster
**`/opt/cni/bin` contains none of them** (only what Cilium and Multus
installed; confirmed live — pods requesting the NAD fail with
`failed to find plugin "ipvlan" in path [/opt/cni/bin]`). Install the
official release (pinned v1.9.1) with a small DaemonSet:

```bash
cat <<EOF | kubectl $KC apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cni-plugins-installer
  namespace: kube-system
spec:
  selector:
    matchLabels: {app: cni-plugins-installer}
  template:
    metadata:
      labels: {app: cni-plugins-installer}
    spec:
      tolerations:
      - operator: Exists
      initContainers:
      - name: install
        image: curlimages/curl:8.14.1
        command: ["sh", "-c"]
        args:
        - |
          set -e
          curl -fsSL --retry 5 --retry-delay 3 \
            https://github.com/containernetworking/plugins/releases/download/v1.9.1/cni-plugins-linux-amd64-v1.9.1.tgz \
            -o /tmp/cni.tgz
          tar -xzf /tmp/cni.tgz -C /host-cni-bin
          echo INSTALLED:; ls /host-cni-bin
        volumeMounts:
        - {name: cni-bin, mountPath: /host-cni-bin}
        securityContext:
          runAsUser: 0
      containers:
      - name: pause
        image: busybox:1.36
        command: ["sleep", "infinity"]
      volumes:
      - name: cni-bin
        hostPath: {path: /opt/cni/bin, type: Directory}
EOF
kubectl $KC -n kube-system rollout status ds/cni-plugins-installer --timeout=120s
```

Then confirm the Multus daemon itself is healthy:

```bash
kubectl $KC -n kube-system get pods -l app=multus -o wide
kubectl $KC -n kube-system logs -l app=multus --tail=20
```

You should see `multus-daemon started` and a copy of the Cilium conflist
promoted to `00-multus.conf` — meaning: primary network unchanged, Multus now
in front.

Install **whereabouts** for cluster-wide secondary-network IPAM:

```bash
kubectl $KC apply \
  -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/v0.9.4/doc/crds/daemonset-install.yaml \
  -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/v0.9.4/doc/crds/whereabouts.cni.cncf.io_ippools.yaml \
  -f https://raw.githubusercontent.com/k8snetworkplumbingwg/whereabouts/v0.9.4/doc/crds/whereabouts.cni.cncf.io_overlappingrangeipreservations.yaml
```

---

## Part 6: Define a Secondary Network (~10 min)

A `NetworkAttachmentDefinition` (NAD) is a named, namespaced CNI config.
Pods reference it by name in an annotation.

First discover the parent interface name on the nodes (Ubuntu on Nitro
instances typically names it `ens5`):

```bash
NODE=$(kubectl $KC get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
kubectl $KC debug node/$NODE -it --image=busybox:1.36 -- sh -c 'ip -o link show | grep -v veth'
```

Create the NAD — **ipvlan** over the node's primary NIC, whereabouts IPAM
from a range that exists only inside this network:

```bash
cat <<EOF | kubectl $KC apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: secondary-ipvlan
  namespace: default
spec:
  config: |-
    {
      "cniVersion": "0.3.1",
      "name": "secondary-ipvlan",
      "type": "ipvlan",
      "master": "ens5",
      "mode": "l2",
      "ipam": {
        "type": "whereabouts",
        "range": "192.168.100.0/24"
      }
    }
EOF
```

> **Why ipvlan and not macvlan on AWS:** macvlan gives each pod interface a
> new MAC address, and the EC2 network **drops frames whose source MAC it
> doesn't recognize** — macvlan secondary networks silently blackhole on AWS.
> ipvlan reuses the parent NIC's MAC, so same-node (and, with source/dest
> checks disabled and VPC-valid IPs, cross-node) traffic flows.
>
> **Scope of this demo:** `192.168.100.0/24` is not a VPC range, so this
> secondary network is **node-local** — exactly enough to prove the Multus
> mechanics. Real deployments attach dedicated ENIs/EFA devices per node and
> use host-device or SR-IOV CNIs (that is the NVIDIA network operator's job
> in Week 5).

---

## Part 7: Validate the Two-Interface Pod (~15 min)

Launch two pods on the **same worker node** (the secondary network is
node-local — see the scope note above), both attached to the NAD:

```bash
for i in a b; do
cat <<EOF | kubectl $KC apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: multinet-$i
  namespace: default
  annotations:
    k8s.v1.cni.cncf.io/networks: secondary-ipvlan
spec:
  nodeName: ${NODE}
  containers:
  - name: net-tools
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
done

kubectl $KC wait --for=condition=Ready pod/multinet-a pod/multinet-b --timeout=120s
```

**Check 1 — two interfaces per pod:**

```bash
kubectl $KC exec multinet-a -- ip -o addr show | grep -v 'lo '
```

Expected shape:

```
2: eth0@...  inet 10.244.x.y/32 ...      <- Cilium (primary)
3: net1@...  inet 192.168.100.1/24 ...   <- ipvlan via Multus (secondary)
```

**Check 2 — the network-status annotation** (what schedulers/operators read):

```bash
kubectl $KC get pod multinet-a \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' | jq
```

Both networks appear, with `"default": true` on the Cilium entry.

**Check 3 — traffic over the secondary network:**

```bash
NET1_B=$(kubectl $KC exec multinet-b -- ip -4 -o addr show net1 | awk '{print $4}' | cut -d/ -f1)
kubectl $KC exec multinet-a -- ping -c3 -I net1 "$NET1_B"
```

**Check 4 — primary network is untouched:**

```bash
kubectl $KC exec multinet-a -- nslookup kubernetes.default.svc.cluster.local
```

If all four pass, you have reproduced — at demo scale — the dual-network
layout that Lab 5.18 assumes: primary CNI for cluster traffic, named
secondary attachments for the fabric.

---

## Cleanup (~5 min)

```bash
# Pods + NAD (workload cluster objects die with the cluster anyway)
kubectl $KC delete pod multinet-a multinet-b --ignore-not-found
kubectl $KC delete network-attachment-definitions.k8s.cni.cncf.io secondary-ipvlan --ignore-not-found

# The cluster itself
kubectl delete clusterdeployment ${CLUSTER_NAME} -n kcm-system
# Wait for full teardown (EC2, NLB, volumes) before closing the terminal:
kubectl get clusterdeployment ${CLUSTER_NAME} -n kcm-system -w

# Keep or remove the fleet-level objects as you prefer:
kubectl delete multiclusterservice cilium-cni            # optional
kubectl delete servicetemplate cilium-1-19-0 -n kcm-system  # optional
```

---

## Verification Checklist

- [ ] Template revision confirmed to render `k0s.network` (Part 1 grep returned ≥1)
- [ ] Cluster provisioned with `provider: custom`, `kubeProxy.disabled: true`
- [ ] Nodes observed `NotReady` with `cni plugin not initialized`, then `Ready` after Cilium landed
- [ ] `kube-proxy` DaemonSet absent; `cilium-dbg status` shows `KubeProxyReplacement: True`
- [ ] `ClusterDeployment.status.services` shows the `cilium` service deployed
- [ ] `cniIngressRules` patch applied; `udp/6081` + `tcp/4240` visible on both CAPA security groups
- [ ] `cni-plugins-installer` DaemonSet rolled out (`ipvlan` present in `/opt/cni/bin`)
- [ ] Multus DaemonSet healthy; `00-multus.conf` present in `/etc/cni/net.d` (and **not** renamed to `*.cilium_bak`)
- [ ] Pod shows `eth0` (Cilium) + `net1` (ipvlan) with a whereabouts-assigned IP
- [ ] Ping over `net1` between two same-node pods succeeds
- [ ] Cluster deleted; no orphaned EC2/NLB/EBS resources

---

## Deliverable

A **1-paragraph written rationale** answering:

> "Your KaaS product offers customers a choice of CNI per cluster. Defend the
> decision to implement this as `provider: custom` + catalog
> `ServiceTemplate`s, rather than maintaining one forked `ClusterTemplate`
> per CNI. Then name one customer requirement that would force you back to
> the forked-template approach anyway."

Strong answers cite the immutability of the k0s network provider, the
version-skew story (CNI upgrades without cluster redeploys), and recognize
that anything the chart hardcodes *before* the passthrough existed (or that
must run before the API server answers) still requires a template fork.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Deployment stuck at `InfrastructureReady: 0 of 8`; `AWSCluster` shows `VpcReconciliationFailed` / `AuthFailure: AWS was not able to validate the provided access credentials` | The AWS credentials in `aws-cluster-identity-secret` expired — guaranteed after any long pause if you used Lab 1.3's SSO option (session tokens live 1-12h) | Re-run the documented refresh: `aws sso login --profile <p>`, `eval "$(aws configure export-credentials --format env --profile <p>)"`, then `./scripts/lab-refresh-creds.sh <your-name>` (validated live 2026-07-03) |
| Nodes `NotReady`, `cni plugin not initialized`, and **no Cilium pods appear** (MCS `status.services` empty, no reconcile errors anywhere) | `MultiClusterService` selector doesn't match — `cni: cilium` is missing from the `ClusterDeployment`'s **metadata** labels (e.g. it was put in `config.clusterLabels` instead) | `kubectl get clusterdeployments -n kcm-system --show-labels`; fix with `kubectl label clusterdeployment ${CLUSTER_NAME} -n kcm-system cni=cilium` |
| Cluster stays Calico despite `k0s.network` in config | Template revision predates the passthrough (chart ≤ `1-0-13`) — the value validated against the schema but the chart never rendered it | Part 1 gate; fork the template per the Lab 4.1 pattern |
| Cilium pods `CrashLoopBackOff`, logs show API connect timeouts | `k8sServiceHost`/`k8sServicePort` missing or wrong — with kube-proxy disabled Cilium cannot bootstrap via ClusterIP | Confirm the Sveltos-templated endpoint rendered: `kubectl $KC -n cilium get cm cilium-config -o yaml \| grep k8s-service` |
| `cilium-operator` `Pending` forever | Single-node clusters: operator replica anti-affinity | Scale expectation: with 1 CP + 1 worker it schedules; if you shrank to 0 workers set `cilium.operator.replicas: 1` |
| `kube-multus-ds` crashloops mentioning `pod-resources` | k0s kubelet root is `/var/lib/k0s/kubelet`, not `/var/lib/kubelet` | Patch the DaemonSet hostPath (Part 5 note) |
| Pods with the `networks` annotation come up **with only `eth0`** — no `net1`, no `network-status` annotation, no error | Cilium's `cni.exclusive: true` (default) renamed Multus's config to `00-multus.conf.cilium_bak` in `/etc/cni/net.d` | Set `cni.exclusive: false` in the Cilium values (Part 3). **If changing it on a live cluster:** the Helm upgrade only updates the ConfigMap — `kubectl rollout restart ds/cilium -n cilium` is required for agents to pick it up (confirmed live), then `kubectl rollout restart ds/kube-multus-ds -n kube-system`, then recreate the pods |
| Pod stuck `ContainerCreating`, events show `failed to find plugin "ipvlan" in path [/opt/cni/bin]` | Reference CNI plugins missing — on a `provider: custom` cluster `/opt/cni/bin` holds only Cilium's and Multus's own binaries (confirmed live) | Deploy the `cni-plugins-installer` DaemonSet from Part 5; already-stuck pods recover on the next sandbox retry, no recreate needed |
| Pods on the **control-plane node** can't resolve DNS / reach cross-node pods, while worker-node pods work | Cilium tunnel traffic blocked — the CAPA security groups lack UDP 6081 (geneve); defaults cover Calico only | Apply the Part 3b `cniIngressRules` patch and wait ~1 min for CAPA to reconcile the security groups |
| Pod events show `error at storage engine: ... IPPool` | whereabouts CRDs missing (only the DaemonSet was applied) | Apply both CRD manifests from Part 5 |
| Ping over `net1` fails **cross-node** | Expected with a non-VPC range: AWS won't deliver L2 for IPs/MACs it doesn't know | Same-node demo only, or disable src/dst check on the ENIs *and* use VPC-valid addressing |
| Ping over `net1` fails same-node | ipvlan `master` name wrong (not `ens5` on your AMI/instance type) | Re-run the interface discovery in Part 6 and fix `master` |
| `ServiceTemplate` `VALID: false` | Chart pull failed from ghcr | `kubectl describe servicetemplate cilium-1-19-0 -n kcm-system`; check the HelmRepository URL and egress |

---

## Key Takeaways

1. **The CNI is a delivery decision, not a cluster property.** `provider: custom`
   turns "which CNI" into data (`clusterLabels` + a `MultiClusterService`
   selector) — the same mechanism that delivers any other fleet service.
2. **The `NotReady` window is by design.** Kubelets hold workloads until a CNI
   config exists; host-network pods (and the API server) are unaffected. The
   race between "cluster registers with Sveltos" and "CNI arrives" resolves
   itself — DaemonSets tolerate `NotReady` nodes.
3. **kube-proxy is optional infrastructure.** Disabling it at creation and
   letting Cilium's eBPF dataplane own service load-balancing is the
   documented k0s + Cilium path — but only if Cilium is told the API endpoint
   explicitly.
4. **Values passthroughs age better than forks — when they exist.** The
   hardcoded-Calico → `k0s.network` history in the upstream chart is the
   template-evolution story in miniature: check what your revision renders,
   not just what the schema accepts.
5. **Multus adds networks, it doesn't replace one.** The primary CNI still
   owns `eth0`, default routes, and NetworkPolicy; secondary attachments are
   named, per-pod, and (on AWS) constrained by what the underlay will forward.
6. **The platform's defaults are shaped like its default CNI.** CAPA's
   security-group rules, the chart's hardcoded `network` block, Cilium's
   exclusive ownership of `/etc/cni/net.d` — three independent layers each
   quietly assumed there would only ever be one, Calico-shaped CNI. Swapping
   a "pluggable" component means finding every layer that baked in the
   default.

---

## Next Lab

[Lab 4.9 — Dynamic Resource Allocation](lab-4.9-dynamic-resource-allocation.md)
(Labs 4.5-4.8 are in development.) If you are following the Week 5 AI track,
this lab's secondary-network pattern is consumed by
[Lab 5.18 — topograph / NVLink Topology](../../week-5-ai-workloads/labs/lab-5.18-topograph-nvlink-topology.md).

---

## References

- k0rdent catalog — [Cilium app](https://catalog.k0rdent.io/latest/apps/cilium/) (reference `ClusterDeployment` + `MultiClusterService` values this lab follows)
- k0s — [Networking / custom CNI](https://docs.k0sproject.io/stable/networking/) (`provider: custom`; provider immutable post-init)
- Cilium — [k0s installation guide](https://docs.cilium.io/en/stable/installation/k0s/) (provider custom + kube-proxy disabled)
- k0rdent kcm — [`aws-standalone-cp` chart source](https://github.com/k0rdent/kcm/tree/main/templates/cluster/aws-standalone-cp) (`k0s.network` passthrough, added in chart `1-0-14`)
- Multus CNI — [quickstart (thick plugin)](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/quickstart.md)
- whereabouts — [IPAM CNI](https://github.com/k8snetworkplumbingwg/whereabouts)
- Lab 1.7 — [Multi-Cluster Services](../../week-1-foundations/labs/lab-1.7-multicluster-services.md) (ServiceTemplate/MCS mechanics reused here)
- Lab 4.1 — [Hosted Control Plane](lab-4.1-hosted-control-plane.md) (template-fork pattern referenced in Part 1)
