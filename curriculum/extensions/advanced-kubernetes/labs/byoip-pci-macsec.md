# Lab 4.10 — Case Study: AI Cloud Provider Interconnect Patterns

**Domain:** KaaS / Networking / Transport / Security

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Networking / Transport / Security | Required | 3 hours |

### Week 4 Learning Paths

```
FOUNDATION ➔ 4.1 ➔ 4.2 ➔ 4.3 ➔ 4.4 Cilium+Multus ➔ 4.5 Storage ➔ 4.6 ➔ 4.7 ➔ 4.8 ➔ 4.9 DRA
                                                                                            ↓
                                                                            [4.10] BYOIP / PCI / MACsec
                                                                                            ↓
                                                                              [4.11] NFSv4 + Parallel FS
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 4.9 — Dynamic Resource Allocation](lab-4.9-dynamic-resource-allocation.md) | **Lab 4.10 — BYOIP, PCI, MACsec** | Lab 4.11 — NFSv4 + Parallel FS *(planned)* |

---

**Duration:** 3 hours
**Type:** Design + Hands-on configuration
**Environment:** k0rdent cluster + network admin access to perimeter routers/switches (or simulated lab with FRR + macsec-enabled NICs)

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: The AI cloud provider networking pattern](#part-1-the-ai-cloud-provider-networking-pattern)
- [Part 2: BYOIP — including unusual prefixes](#part-2-byoip--including-unusual-prefixes)
- [Part 3: Dedicated Interconnect + VIF + BGP](#part-3-dedicated-interconnect--vif--bgp)
- [Part 4: MACsec on the storage path](#part-4-macsec-on-the-storage-path)
- [Part 5: Static egress NAT](#part-5-static-egress-nat)
- [Part 6: mTLS east-west and north-south](#part-6-mtls-east-west-and-north-south)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

This lab is a case study of how a real AI cloud provider connects to a customer site. The provider needs three things from the on-prem operator: routable IP space (often **BYOIP** — including prefixes that aren't strictly RFC1918), an **encrypted high-bandwidth link** to the provider's storage and corporate networks (a dedicated interconnect with BGP + MACsec), and a **stable egress NAT pool** that's exclusively the provider's traffic. None of these patterns are unique to one vendor — they appear in every AI/HPC engagement where the customer's compute must securely reach a remote provider's resources.

Four elements stack together:

1. **BYOIP — possibly including non-RFC1918 prefixes.** Some providers allocate unusual address space (e.g., DoD-assigned blocks like `7.0.0.0/8`) and ask the on-prem operator to route it as private space. Many enterprise firewalls drop these as "bogon" traffic by default. Always verify the prefix policy with your provider; if your bogon filter eats it, the cluster is silently broken.
2. **Dedicated Interconnect + Virtual Interface (VIF) + BGP.** Functionally equivalent to AWS Direct Connect, GCP Dedicated Interconnect, Azure ExpressRoute, or OCI FastConnect. Provision the circuit, define a VIF, peer BGP with the provider's POP, and advertise the BYOIP prefix. Typical sizing is ~10 Gbps for control-plane traffic.
3. **MACsec on the storage path.** End-to-end **IEEE 802.1AE MACsec** encryption on the links between tenant GPU clusters and the provider's on-premises storage POP. Fail-closed: if the MACsec session drops, the link drops.
4. **Static egress NAT.** Cluster local Internet access uses a **static NAT IP pool dedicated to the provider's tenancy** — persistent IPs, never shared with other tenants. The provider allowlists these IPs on the receiving side; if they drift, services break.

By the end of this lab you'll have configured BGP-routed BYOIP, enabled MACsec link encryption between the on-prem site and a stand-in provider POP, and stood up a static egress NAT pool. The patterns transfer to any similar interconnect engagement.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Explain why `7.0.0.0/8` must be treated as RFC1918-equivalent inside the provider fabrics and how to keep it from being filtered as a bogon
- [ ] Allocate non-conflicting BYOIP ranges into Cilium pod, service, and node IPAM without collisions against the provider-supplied prefixes
- [ ] Establish a redundant eBGP session over a Private Cloud Interconnect VIF and advertise the BYOIP prefix to the provider's corp network
- [ ] Configure IEEE 802.1AE MACsec on the NIC pair facing the provider storage with key rotation and fail-closed behavior
- [ ] Deploy a static egress NAT pool dedicated to the provider tenancy with HA
- [ ] Enforce mTLS for both east-west service-to-service and north-south ingress traffic (SEC13)

---

## Prerequisites

- Lab 4.4 (Cilium + Multus) — **required**, you must already own pod/service CIDR layout
- Lab 4.5 (Storage tiers) — recommended, because Part 4 secures the storage path
- Network admin access to perimeter routers/switches (real or simulated)
- A simulated rack of FRR routers (`docker run -d quay.io/frrouting/frr:9.1.0`) or real edge gear
- NICs that support MACsec offload (Mellanox ConnectX-6/7, Intel E810) — or kernel-software MACsec for the lab
- `kubectl`, `cilium` CLI, `vtysh`/`frr`, `ip`, `wpa_supplicant`, `iproute2` ≥ 5.10

> All BGP examples use AS65000 (operator side) and AS65001 (the provider POP side) from RFC6996 private ASN ranges. All peer IPs use `203.0.113.0/24` from RFC5737 documentation space. **Do not copy these into production** — substitute the values the provider provides during onboarding.

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| BYOIP plumbing into Cilium | `node-IPAM-controller` (per-node allocations from BYOIP pool) | Cilium `CiliumLoadBalancerIPPool` + `ClusterPool` IPAM mode | **Cilium ClusterPool** — native eBPF integration, single source of truth, plays cleanly with the Cilium BGP control plane in Part 3 |
| BGP speaker | FRR on a dedicated network-services node | Calico BGP | Cilium BGP control plane | **Cilium BGP control plane** for in-cluster prefix advertisement; **FRR on the edge** for the upstream peering to the provider POP. Two speakers, one role each. |
| MACsec termination | NIC hardware offload (ConnectX-7 / E810) | Kernel software MACsec | Both layered | **NIC hardware offload** for the production fabric (line-rate, no CPU tax). Keep kernel-software MACsec available for emergency replacement nodes only — line rate will drop. |
| Egress NAT topology | Cloud-provider managed NAT GW with reserved EIPs | Self-hosted NAT instances on dedicated VMs with VRRP | **Cloud-provider NAT GW** when on a public cloud (simpler audit story, fewer moving parts). **Self-hosted with VRRP** on bare-metal sites. Either way: the IPs must be **dedicated to the provider and never reused**. |
| mTLS east-west enforcement | Sidecar service mesh (Istio / Linkerd) | Sidecar-less SPIFFE/SPIRE | Cilium ClusterMesh mTLS | **Cilium ClusterMesh mTLS** — already runs on the eBPF data plane from Lab 4.4, no sidecar tax on GPU pods, identity comes from SPIFFE-compatible IDs. Use Istio only if you have a pre-existing investment. |
| BGP authentication | None | TCP-MD5 | TCP-AO (RFC 5925) | **TCP-MD5 minimum, TCP-AO preferred** — the provider will tell you which they support at onboarding. Never run an unauthenticated session over a shared circuit. |

---

## Part 1: The the provider networking pattern

Before you touch a config file, understand the topology you are wiring up.

```
   ┌─────────────────────────────────┐                ┌──────────────────────────┐
   │           operator DATA CENTRE       │                │       the provider POP         │
   │                                 │                │   (CorpIT + Storage)     │
   │   ┌─────────┐    ┌──────────┐   │                │                          │
   │   │ k0rdent │    │   GPU    │   │   PCI / VIF    │   ┌──────────────────┐   │
   │   │  mgmt   │───▶│ clusters │───┼────────────────┼──▶│  CorpIT command/ │   │
   │   │ cluster │    │ (the provider)   │   │  eBGP, MACsec  │   │  control gateways │   │
   │   └─────────┘    └──────────┘   │                │   └──────────────────┘   │
   │        │              │         │                │            │             │
   │        │     BYOIP    │         │                │            │             │
   │        │  (incl. 7/8) │         │                │   ┌──────────────────┐   │
   │        ▼              ▼         │   MACsec only  │   │  the provider on-prem    │   │
   │   ┌─────────────────────────┐   │   (fail-close) │   │  object storage  │   │
   │   │  Edge routers (FRR)     │───┼────────────────┼──▶│  POP             │   │
   │   │  - eBGP to the provider POP   │   │                │   └──────────────────┘   │
   │   │  - MACsec on storage NIC│   │                │                          │
   │   │  - Static egress NAT    │───┼─── Internet ───┼──▶  Allowlisted services │
   │   └─────────────────────────┘   │  (the provider NAT IPs)│   (registry, telemetry) │
   └─────────────────────────────────┘                └──────────────────────────┘
```

Three distinct paths leave the operator perimeter, and **each has a different security contract**:

| Path | Carries | Security contract |
|------|---------|-------------------|
| PCI / VIF / BGP | Command-and-control, k0rdent ↔ the provider orchestration | eBGP (MD5/AO), no MACsec required |
| Storage link | Bulk training data, checkpoints | **MACsec mandatory, fail-closed** |
| Cluster Local Internet | Outbound to allowlisted the provider services | **Static NAT, dedicated EIPs**, never shared |

If you blur these paths — for example, by routing storage traffic over the CorpIT VIF — you break the storage-path integrity model. Keep them physically and logically separate.

---

## Part 2: BYOIP including 7.0.0.0/8

NVIDIA hands you one or more prefixes during onboarding. In every documented v2.3 deployment, those prefixes include `7.0.0.0/8` (or a slice of it). Your job is to:

1. Carve non-conflicting sub-ranges for pods, services, nodes, and floating IPs.
2. Tell Cilium to allocate from those ranges.
3. Tell every router/firewall in the path that `7.0.0.0/8` is **not a bogon**.

### 2.1 Carve the BYOIP allocation

Assume the provider assigns you `7.42.0.0/16` (illustrative — substitute the real assignment).

| Slice | CIDR | Role |
|-------|------|------|
| Nodes | `7.42.0.0/22` | k0s/k0rdent node IPs |
| Pod CIDR | `7.42.16.0/20` | Cilium pod pool (ClusterPool IPAM) |
| Service CIDR | `7.42.32.0/22` | ClusterIP range |
| Floating / LB | `7.42.36.0/24` | Cilium `LoadBalancerIPPool`, stable per-service |
| Reserved | `7.42.64.0/18` | Future expansion, do not allocate |

Document this allocation in a routing-policy note — it is the source of truth for every downstream config.

### 2.2 Configure Cilium ClusterPool

```yaml
# cilium-byoip-values.yaml — fragment passed via Helm or k0rdent ClusterTemplate
ipam:
  mode: cluster-pool
  operator:
    clusterPoolIPv4PodCIDRList:
      - "7.42.16.0/20"
    clusterPoolIPv4MaskSize: 24
k8sServiceHost: "7.42.0.10"
bgpControlPlane:
  enabled: true
```

Apply via the k0rdent ClusterTemplate flavor you built in Lab 4.8 — do not hand-edit live clusters.

### 2.3 Define a `CiliumLoadBalancerIPPool` for stable IPs (DMS05)

```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: provider-stable-pool
spec:
  blocks:
    - start: "7.42.36.10"
      stop:  "7.42.36.250"
```

Stable LB IPs are what the provider allowlists on their side. Once an IP is bound to a Service, it must not change. Add the annotation `io.cilium/lb-ipam-sharing-key: provider` if you reuse the pool across namespaces.

### 2.4 Stop firewalls from filtering `7.0.0.0/8` as a bogon

The most common silent failure. On every router/firewall/ACL/security-group in the path **from the operator edge to the GPU nodes**, explicitly permit `7.0.0.0/8`:

```bash
# FRR / vtysh — remove the default bogon filter for 7/8
configure terminal
ip prefix-list NO-BOGONS seq 5 deny 0.0.0.0/8 le 32
ip prefix-list NO-BOGONS seq 10 permit 7.0.0.0/8 le 32   # the provider BYOIP — RFC1918-equivalent for the provider
ip prefix-list NO-BOGONS seq 15 deny 10.0.0.0/8 le 32
# ...
```

Equivalent rules on Linux nodes if they hold conntrack/iptables policy:

```bash
iptables -I FORWARD -s 7.0.0.0/8 -j ACCEPT
iptables -I FORWARD -d 7.0.0.0/8 -j ACCEPT
```

Add a one-line comment in your config: `# the provider the provider BYOIP — treat 7.0.0.0/8 as RFC1918-equivalent`. Future engineers will read that comment and not "fix" it.

---

## Part 3: Private Cloud Interconnect + VIF + BGP

The Private Cloud Interconnect is **functionally equivalent to AWS Direct Connect / GCP Dedicated Interconnect / Azure ExpressRoute / OCI FastConnect**. Same primitives: a physical circuit (or LAG), one or more VIFs (VLAN-tagged sub-interfaces), and eBGP on each VIF.

NVIDIA sizes the CorpIT path at roughly 10 Gbps. Provision **two VIFs over two diverse circuits** for HA — single-circuit failure must not isolate the cluster from CorpIT.

### 3.1 Physical / VIF layout

| Element | Value (illustrative) |
|---------|----------------------|
| Circuit A | `xe-0/0/0` on edge router `edge-a` |
| Circuit B | `xe-0/0/0` on edge router `edge-b` |
| VIF A VLAN | 4040 |
| VIF B VLAN | 4041 |
| operator local IP (A) | `203.0.113.1/30` |
| the provider POP IP (A) | `203.0.113.2/30` |
| operator local IP (B) | `203.0.113.5/30` |
| the provider POP IP (B) | `203.0.113.6/30` |
| operator ASN | AS65000 |
| the provider POP ASN | AS65001 |

### 3.2 FRR config for the upstream peering

```
! /etc/frr/frr.conf — edge-a
!
router bgp 65000
 bgp router-id 7.42.0.1
 no bgp default ipv4-unicast
 neighbor the provider-POP peer-group
 neighbor the provider-POP remote-as 65001
 neighbor the provider-POP password 7&provider-md5-shared-secret
 neighbor the provider-POP timers 10 30
 neighbor the provider-POP timers connect 10
 !
 neighbor 203.0.113.2 peer-group the provider-POP
 neighbor 203.0.113.6 peer-group the provider-POP
 !
 address-family ipv4 unicast
  network 7.42.0.0/16
  neighbor the provider-POP activate
  neighbor the provider-POP soft-reconfiguration inbound
  neighbor the provider-POP route-map RM-TO-NVIDIA out
  neighbor the provider-POP route-map RM-FROM-NVIDIA in
  maximum-paths 2
 exit-address-family
!
ip prefix-list PL-BYOIP-OUT seq 10 permit 7.42.0.0/16
!
route-map RM-TO-NVIDIA permit 10
 match ip address prefix-list PL-BYOIP-OUT
!
route-map RM-FROM-NVIDIA permit 10
 set local-preference 200
!
```

Mirror this on `edge-b` with the `203.0.113.5/30` peer and a slightly lower `local-preference` so traffic prefers the primary path. ECMP across both via `maximum-paths 2`.

### 3.3 Cilium BGP control plane (in-cluster)

The Cilium BGP control plane advertises pod and LB IPs **to your own edge routers**, which re-advertise the aggregate `7.42.0.0/16` upstream to the provider.

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: provider-cluster-bgp
spec:
  nodeSelector:
    matchLabels:
      bgp-speaker: "true"
  virtualRouters:
    - localASN: 65000
      exportPodCIDR: true
      neighbors:
        - peerAddress: "7.42.0.254/32"   # edge-a loopback inside the BYOIP space
          peerASN: 65000
          eBGPMultihopTTL: 4
      serviceSelector:
        matchLabels:
          announce: "provider"
```

Verify with:

```bash
cilium bgp peers
cilium bgp routes advertised ipv4 unicast
vtysh -c 'show bgp ipv4 unicast summary'
vtysh -c 'show bgp ipv4 unicast 7.42.0.0/16'
```

You want one BGP session per edge router, ECMP across both upstream VIFs, and the `7.42.0.0/16` aggregate visible in the provider's POP RIB.

---

## Part 4: MACsec to the provider storage

MACsec is **IEEE 802.1AE**: Layer 2, frame-by-frame authenticated encryption between two adjacent Ethernet devices. It protects the link itself, not end-to-end across routed hops. the provider mandates MACsec on the NIC pair that terminates each end of the storage link to the the provider on-prem object storage POP (the storage link encryption requirement).

### 4.1 Topology and key model

```
[operator storage edge NIC] ◀── MACsec SA (CAK/CKN) ──▶ [NVIDIA storage POP NIC]
       eno5/eno6 LAG                                       (peer interfaces)
```

- **CAK** (Connectivity Association Key) — long-lived, shared between the two ends, rotated quarterly minimum.
- **CKN** (Connectivity Association Key Name) — public identifier for the CAK.
- **MKA** (MACsec Key Agreement) — IEEE 802.1X-2010 protocol that uses the CAK to derive short-lived **SAK**s and rotate them every few minutes automatically.

Always run MKA. Static SAKs without MKA are not acceptable for the production fabric — rotation is the point.

### 4.2 Sample `wpa_supplicant` config for MACsec MKA

```ini
# /etc/wpa_supplicant/wpa_supplicant-macsec-eno5.conf
ctrl_interface=/var/run/wpa_supplicant
eapol_version=3
ap_scan=0
fast_reauth=1

network={
    key_mgmt=NONE
    eapol_flags=0
    macsec_policy=1
    macsec_integ_only=0       # 0 = encrypt + integrity (recommended). 1 = integrity only.
    mka_cak=0123456789abcdef0123456789abcdef    # 256-bit CAK — pull from sealed Vault, do NOT commit
    mka_ckn=11223344                             # CKN — exchanged with the provider out-of-band
    mka_priority=128
}
```

Start the supplicant against the physical NIC:

```bash
systemctl enable --now wpa_supplicant-macsec@eno5.service
# unit calls: wpa_supplicant -i eno5 -Dmacsec_linux \
#   -c /etc/wpa_supplicant/wpa_supplicant-macsec-eno5.conf
```

When the MKA session establishes, the kernel creates a logical `macsec0` interface stacked on `eno5`. All your routing for the storage subnet then runs over `macsec0`, never over the bare `eno5`.

### 4.3 Alternative: static SAK via `ip macsec` (lab / bring-up only)

For initial bring-up or when MKA is not yet possible:

```bash
ip link add link eno5 macsec0 type macsec encrypt on
ip macsec add macsec0 tx sa 0 pn 1 on key 01 \
    00112233445566778899aabbccddeeff
ip macsec add macsec0 rx address aa:bb:cc:dd:ee:ff port 1
ip macsec add macsec0 rx address aa:bb:cc:dd:ee:ff port 1 sa 0 pn 1 on key 02 \
    ffeeddccbbaa99887766554433221100
ip link set macsec0 up
ip addr add 7.42.200.1/30 dev macsec0
```

Verify the link and counters:

```bash
ip -d link show macsec0
ip macsec show
ip -s macsec show macsec0     # encrypted/decrypted packet counters, replay drops
```

Healthy output shows non-zero `OutOctetsEncrypted` and `InOctetsDecrypted`, zero `InPktsNotValid` / `InPktsLate`.

### 4.4 Fail-closed behaviour

Configure the storage subnet to route **only** over `macsec0`. If the MKA session drops, `macsec0` goes down and the route disappears — traffic is **not** silently delivered in the clear over `eno5`:

```bash
ip route add 7.42.250.0/24 dev macsec0    # the provider storage POP subnet
# Do NOT add a fallback route over eno5.
```

In Cilium NetworkPolicy or host firewall, also drop any storage-subnet traffic that arrives on `eno5` directly:

```bash
iptables -I INPUT  -i eno5 -d 7.42.250.0/24 -j DROP
iptables -I OUTPUT -o eno5 -d 7.42.250.0/24 -j DROP
```

This is the fail-closed contract the storage path demands.

### 4.5 Key rotation runbook

| Action | Frequency | Owner |
|--------|-----------|-------|
| MKA SAK rotation (automatic) | Every ~30 minutes | MKA / wpa_supplicant |
| CAK rotation (manual, dual-control) | Quarterly | operator NetOps + the provider NetOps, coordinated change window |
| CKN rotation | With CAK | Same |
| Replay-window audit (`ip -s macsec`) | Weekly | operator NetOps |

Record the rotation evidence in a MACsec rotation log.

---

## Part 5: Static egress NAT

Cluster Local Internet Access is for outbound calls to the provider-allowlisted services — container registries, telemetry endpoints, license servers. the provider pins their allowlist to **specific egress IPs**, so those IPs must be:

- Dedicated to the provider tenancy
- Never shared with other workloads on the same operator
- Stable across NAT-gateway failover (DMS05)

### 5.1 Cloud-provider NAT GW pattern (preferred where available)

Allocate **dedicated** Elastic IPs for the the provider tenant only:

```bash
# AWS example — illustrative
aws ec2 allocate-address --domain vpc --tag-specifications \
  'ResourceType=elastic-ip,Tags=[{Key=tenant,Value=provider},{Key=purpose,Value=egress-nat}]'
aws ec2 create-nat-gateway --subnet-id subnet-the provider-public --allocation-id eipalloc-...
```

Route table for the the provider tenant subnets points `0.0.0.0/0` at the dedicated NAT GW only. **Never** attach these EIPs to a shared NAT GW that also serves other tenants — auditors will catch it and you will break the egress-pool isolation contract.

### 5.2 Self-hosted NAT instances with VRRP (bare-metal pattern)

When you do not have a managed NAT GW, run two NAT instances and float a VIP between them via VRRP:

```conf
# /etc/keepalived/keepalived.conf — nat-a (primary)
vrrp_instance VI_the provider_EGRESS {
    state MASTER
    interface eno1
    virtual_router_id 42
    priority 200
    advert_int 1
    authentication { auth_type PASS; auth_pass provider-nat-vrrp; }
    virtual_ipaddress {
        198.51.100.7/32 dev eno1     # dedicated the provider egress VIP (RFC5737 example)
    }
}
```

On each NAT instance, MASQUERADE only the provider pod traffic out of that single VIP:

```bash
iptables -t nat -A POSTROUTING -s 7.42.0.0/16 -o eno1 \
    -j SNAT --to-source 198.51.100.7
```

The VIP follows the active node. Egress IP is stable from the provider's perspective even during NAT-instance failover.

### 5.3 Make the egress allocation explicit

Document in your egress-NAT runbook:

| Egress IP | Bound to | Tenant | Failover model | Rotation policy |
|-----------|----------|--------|----------------|-----------------|
| 198.51.100.7 | NAT-A / NAT-B VRRP | the provider | VRRP (nat-b backup) | Never rotated without the provider change ticket |

NVIDIA will reference this artifact when verifying their allowlist.

---

## Part 6: mTLS east-west and north-south

SEC13 demands mTLS for **all** sensitive traffic: pod ↔ pod (east-west) inside the cluster, and ingress (north-south) into the cluster. The transport (MACsec, VIF) protects the wire; mTLS protects the application identity.

### 6.1 East-west: Cilium ClusterMesh mTLS

Lab 4.4 already deployed Cilium. Enable mTLS authentication in the eBPF data plane:

```yaml
# cilium-mtls-values.yaml — Helm fragment
authentication:
  mutual:
    spire:
      enabled: true
      install:
        enabled: true
      trustDomain: provider.cluster.local
encryption:
  enabled: true
  type: wireguard          # optional: bulk in-cluster encryption complementing mTLS auth
  nodeEncryption: true
```

Annotate a workload to require mTLS-authenticated peers:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: require-mtls-storage-gw
spec:
  endpointSelector:
    matchLabels:
      app: storage-gw
  ingress:
    - fromEndpoints:
        - matchLabels:
            tier: training
      authentication:
        mode: required
```

Verify with `cilium hubble observe --type policy-verdict` — you should see `auth_required` verdicts succeed only for SPIRE-issued identities in `provider.cluster.local`.

### 6.2 North-south: ingress with terminated mTLS

For inbound API traffic from the provider orchestration plane, terminate mTLS at the ingress and forward authenticated identity downstream:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: provider-ingress
spec:
  gatewayClassName: cilium
  listeners:
    - name: https-mtls
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: provider-server-cert
        options:
          gateway.envoyproxy.io/client-certificate-mode: "Require"
          gateway.envoyproxy.io/client-ca-bundle-ref: "provider-client-ca-bundle"
```

The `client-ca-bundle` is the the provider-issued client CA. Without a valid client cert chained to that CA, the TLS handshake fails — no anonymous access, ever.

### 6.3 Coverage map

Build `artifacts/SEC13-mtls-coverage-map.md` listing every service and whether it sits behind mTLS:

| Service | Plane | mTLS posture | Identity source |
|---------|-------|--------------|-----------------|
| storage-gw | East-west | Cilium auth `required` | SPIRE (`provider.cluster.local`) |
| training-scheduler | East-west | Cilium auth `required` | SPIRE |
| k0rdent-api | North-south | Gateway `Terminate` + client CA | the provider-issued client cert |
| breakfix-api | North-south | Gateway `Terminate` + client CA | the provider-issued client cert |

Anything left unchecked is a gap in the east-west / north-south encryption posture.

---

## Verification Checklist

- [ ] `7.0.0.0/8` permitted on every edge router and host firewall, with an inline comment marking it as the provider BYOIP
- [ ] Cilium ClusterPool IPAM allocates from the assigned BYOIP slice; no collisions with the provider-side ranges
- [ ] `cilium bgp peers` shows ESTABLISHED on both upstream VIFs
- [ ] the provider POP RIB shows the aggregate prefix via both circuits (verify via NOC ticket — you cannot view the POP RIB yourself)
- [ ] `ip -d link show macsec0` shows the MACsec link UP and `encrypt on`
- [ ] `ip -s macsec show macsec0` counters increment under load; no `InPktsNotValid` drops
- [ ] Pulling power on the MACsec NIC takes the storage route with it (fail-closed verified)
- [ ] Dedicated egress EIP / VIP shown in the provider's allowlist (verify via NOC ticket)
- [ ] `cilium hubble observe --type policy-verdict` shows `auth-required` succeeded on east-west flows
- [ ] North-south Gateway rejects requests with no client cert (test via `curl` without `--cert`)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| BGP session flaps every few minutes | TCP-MD5 password mismatch or path MTU drop | Verify the shared secret matches both ends; set `neighbor ... ebgp-multihop 2` and lower `tcp-mss` to 1400 on the VIF |
| Pod cannot reach `7.x.x.x` even though Cilium says it should | Upstream bogon filter still drops 7/8 | Walk every hop with `mtr 7.42.0.10`; the first router that drops is the one missing the exception |
| MACsec link comes up but no traffic flows | CKN mismatch — MKA negotiated a session but the CAK is wrong on one side | Compare `wpa_cli -i eno5 status`; both ends must show identical CKN, matching CAK fingerprint |
| `ip -s macsec` shows growing `InPktsLate` | Clock skew between the two endpoints exceeds the replay window | Tighten NTP on both ends to a stratum-2 source; widen `replay-window` only as a last resort |
| NAT pool exhaustion under load | Single VIP, too many concurrent flows, port exhaustion (~64k flows per VIP) | Add a second VIP, SNAT round-robin, document the second IP and re-request the provider allowlist update |
| mTLS handshake fails with `unknown ca` | Gateway is using the wrong client CA bundle, or the provider rotated their client CA | Re-fetch the client CA bundle from the provider, update the Gateway `client-ca-bundle-ref`, restart Envoy |
| `cilium bgp peers` ESTABLISHED but no routes advertised | `serviceSelector` / `exportPodCIDR` not matching the workloads | Confirm Service has the agreed advertise label and `cilium bgp routes advertised ipv4 unicast` lists the prefix |

---

## Key Takeaways

- **`7.0.0.0/8` is the provider's RFC1918.** Bogon filters that drop it will silently break the cluster. Whitelist it everywhere, comment the whitelist so future engineers do not "fix" it.
- **PCI / VIF / BGP is the AWS Direct Connect of the provider.** Same primitives, redundant circuits, eBGP with authentication. Two VIFs, ECMP, MD5 minimum.
- **MACsec on the storage path is non-negotiable and must fail closed.** Run MKA, rotate CAK quarterly, never route storage traffic over the bare NIC even as a fallback.
- **Static egress NAT IPs are part of the the provider contract.** Dedicated, never shared, never rotated without an the provider change ticket.
- **mTLS sits on top of the transport.** Transport (MACsec, VIF) protects the wire; mTLS (Cilium + Gateway) proves identity. SEC13 needs both.

---

## Next Lab

Lab 4.11 — NFSv4 + Parallel FS *(planned)* — now that the storage link is MACsec-secured, the next lab presents NFSv4 and the parallel filesystems (Lustre / WEKA / VAST) that ride over it to the the provider POP.
