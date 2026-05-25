# Lab 4.10 — BYOIP, Private Cloud Interconnect, and MACsec

| Domain | Tag | NVIDIA Req IDs |
|--------|-----|----------------|
| KaaS / Networking / Transport / Security | 🟢 NCP | SDN01, NET03, NET04, NET05, NET06, SEC13, SEC18, DMS04, DMS05 |

> **Compliance pack artifact targets:** `artifacts/NET03-byoip-routing-policy.md`, `artifacts/NET04-corpit-bgp-session.md`, `artifacts/NET05-macsec-config.md`, `artifacts/NET06-static-egress-nat.md`, `artifacts/SEC13-mtls-coverage-map.md`

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Networking / Transport / Security | Required (NCP track) | 3 hours |

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
| [Lab 4.9 — Dynamic Resource Allocation](lab-4.9-dynamic-resource-allocation.md) | **Lab 4.10 — BYOIP, PCI, MACsec** | [Lab 4.11 — NFSv4 + Parallel FS](lab-4.11-nfsv4-parallel-fs.md) |

---

**Duration:** 3 hours
**Type:** Design + Hands-on configuration
**Environment:** k0rdent cluster + network admin access to perimeter routers/switches (or simulated lab with FRR + macsec-enabled NICs)

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: The NVIDIA networking pattern](#part-1-the-nvidia-networking-pattern)
- [Part 2: BYOIP including 7.0.0.0/8](#part-2-byoip-including-70008)
- [Part 3: Private Cloud Interconnect + VIF + BGP](#part-3-private-cloud-interconnect--vif--bgp)
- [Part 4: MACsec to DGXC storage](#part-4-macsec-to-dgxc-storage)
- [Part 5: Static egress NAT](#part-5-static-egress-nat)
- [Part 6: mTLS east-west and north-south](#part-6-mtls-east-west-and-north-south)
- [Part 7: Produce the compliance-pack artifacts](#part-7-produce-the-compliance-pack-artifacts)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

This is **the most NVIDIA-specific networking section in the curriculum**. The v2.3 Requirements Guide describes a transport stack engineers have almost certainly not seen at any other cloud provider, with four unusual elements stacked on top of each other:

1. **BYOIP including 7.0.0.0/8.** NVIDIA brings its own IP space into your fabric, and that space includes the `7.0.0.0/8` block. `7.0.0.0/8` is technically DoD-allocated address space and many enterprise firewalls drop it by default as "bogon" traffic. For DGXC, **`7.0.0.0/8` is treated as RFC1918-equivalent** — your routers, firewalls, and security groups must accept and route it. No engineer guesses this on their own. If your bogon filter eats `7.0.0.0/8`, the cluster is silently broken.
2. **Private Cloud Interconnect (PCI) with a Virtual Interface (VIF) and BGP.** DGXC connects to the NCP via a private interconnect that is **functionally equivalent to AWS Direct Connect, GCP Dedicated Interconnect, Azure ExpressRoute, or OCI FastConnect**. Provision the circuit, define a VIF, peer BGP with NVIDIA's POP, and advertise the BYOIP prefix. Sized to ~10 Gbps to NVIDIA CorpIT for command/control plane traffic.
3. **MACsec on the storage path.** End-to-end **IEEE 802.1AE MACsec encryption** is required on the links between your DGXC GPU clusters and NVIDIA's on-premises DGXC object storage POP. Fail-closed: if the MACsec session drops, the link drops. This is not optional and there is no software-only fallback that NVIDIA accepts.
4. **Static egress NAT.** Cluster Local Internet Access uses a **static NAT IP pool dedicated to NVIDIA's DGXC tenancy** — persistent IPs, exclusive to DGXC, never shared with other tenants. NVIDIA allowlists your egress IPs on the receiving side; if those IPs drift, services break.

You will configure all four in this lab, and produce the compliance-pack artifacts that NVIDIA auditors expect.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Explain why `7.0.0.0/8` must be treated as RFC1918-equivalent inside DGXC fabrics and how to keep it from being filtered as a bogon
- [ ] Allocate non-conflicting BYOIP ranges into Cilium pod, service, and node IPAM without collisions against NVIDIA-supplied prefixes
- [ ] Establish a redundant eBGP session over a Private Cloud Interconnect VIF and advertise the BYOIP prefix to NVIDIA CorpIT
- [ ] Configure IEEE 802.1AE MACsec on the NIC pair facing DGXC storage with key rotation and fail-closed behavior
- [ ] Deploy a static egress NAT pool dedicated to DGXC tenancy with HA
- [ ] Enforce mTLS for both east-west service-to-service and north-south ingress traffic (SEC13)
- [ ] Produce five Req-ID-stamped compliance artifacts covering NET03/04/05/06 and SEC13

---

## Prerequisites

- Lab 4.4 (Cilium + Multus) — **required**, you must already own pod/service CIDR layout
- Lab 4.5 (Storage tiers) — recommended, because Part 4 secures the storage path
- Network admin access to perimeter routers/switches (real or simulated)
- A simulated rack of FRR routers (`docker run -d quay.io/frrouting/frr:9.1.0`) or real edge gear
- NICs that support MACsec offload (Mellanox ConnectX-6/7, Intel E810) — or kernel-software MACsec for the lab
- `kubectl`, `cilium` CLI, `vtysh`/`frr`, `ip`, `wpa_supplicant`, `iproute2` ≥ 5.10

> All BGP examples use AS65000 (NCP side) and AS65001 (NVIDIA POP side) from RFC6996 private ASN ranges. All peer IPs use `203.0.113.0/24` from RFC5737 documentation space. **Do not copy these into production** — substitute the values NVIDIA provides during onboarding.

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| BYOIP plumbing into Cilium | `node-IPAM-controller` (per-node allocations from BYOIP pool) | Cilium `CiliumLoadBalancerIPPool` + `ClusterPool` IPAM mode | **Cilium ClusterPool** — native eBPF integration, single source of truth, plays cleanly with the Cilium BGP control plane in Part 3 |
| BGP speaker | FRR on a dedicated network-services node | Calico BGP | Cilium BGP control plane | **Cilium BGP control plane** for in-cluster prefix advertisement; **FRR on the edge** for the upstream peering to NVIDIA POP. Two speakers, one role each. |
| MACsec termination | NIC hardware offload (ConnectX-7 / E810) | Kernel software MACsec | Both layered | **NIC hardware offload** for the production fabric (line-rate, no CPU tax). Keep kernel-software MACsec available for emergency replacement nodes only — line rate will drop. |
| Egress NAT topology | Cloud-provider managed NAT GW with reserved EIPs | Self-hosted NAT instances on dedicated VMs with VRRP | **Cloud-provider NAT GW** when on a public cloud (simpler audit story, fewer moving parts). **Self-hosted with VRRP** on bare-metal sites. Either way: the IPs must be **dedicated to DGXC and never reused**. |
| mTLS east-west enforcement | Sidecar service mesh (Istio / Linkerd) | Sidecar-less SPIFFE/SPIRE | Cilium ClusterMesh mTLS | **Cilium ClusterMesh mTLS** — already runs on the eBPF data plane from Lab 4.4, no sidecar tax on GPU pods, identity comes from SPIFFE-compatible IDs. Use Istio only if you have a pre-existing investment. |
| BGP authentication | None | TCP-MD5 | TCP-AO (RFC 5925) | **TCP-MD5 minimum, TCP-AO preferred** — NVIDIA will tell you which they support at onboarding. Never run an unauthenticated session over a shared circuit. |

---

## Part 1: The NVIDIA networking pattern

Before you touch a config file, understand the topology you are wiring up.

```
   ┌─────────────────────────────────┐                ┌──────────────────────────┐
   │           NCP DATA CENTRE       │                │       NVIDIA POP         │
   │                                 │                │   (CorpIT + Storage)     │
   │   ┌─────────┐    ┌──────────┐   │                │                          │
   │   │ k0rdent │    │   GPU    │   │   PCI / VIF    │   ┌──────────────────┐   │
   │   │  mgmt   │───▶│ clusters │───┼────────────────┼──▶│  CorpIT command/ │   │
   │   │ cluster │    │ (DGXC)   │   │  eBGP, MACsec  │   │  control gateways │   │
   │   └─────────┘    └──────────┘   │                │   └──────────────────┘   │
   │        │              │         │                │            │             │
   │        │     BYOIP    │         │                │            │             │
   │        │  (incl. 7/8) │         │                │   ┌──────────────────┐   │
   │        ▼              ▼         │   MACsec only  │   │  DGXC on-prem    │   │
   │   ┌─────────────────────────┐   │   (fail-close) │   │  object storage  │   │
   │   │  Edge routers (FRR)     │───┼────────────────┼──▶│  POP             │   │
   │   │  - eBGP to NVIDIA POP   │   │                │   └──────────────────┘   │
   │   │  - MACsec on storage NIC│   │                │                          │
   │   │  - Static egress NAT    │───┼─── Internet ───┼──▶  Allowlisted services │
   │   └─────────────────────────┘   │  (DGXC NAT IPs)│   (registry, telemetry) │
   └─────────────────────────────────┘                └──────────────────────────┘
```

Three distinct paths leave the NCP perimeter, and **each has a different security contract**:

| Path | Carries | Security contract |
|------|---------|-------------------|
| PCI / VIF / BGP | Command-and-control, k0rdent ↔ DGXC orchestration | eBGP (MD5/AO), no MACsec required |
| Storage link | Bulk training data, checkpoints | **MACsec mandatory, fail-closed** |
| Cluster Local Internet | Outbound to allowlisted DGXC services | **Static NAT, dedicated EIPs**, never shared |

If you blur these paths — for example, by routing storage traffic over the CorpIT VIF — you violate NET05. Keep them physically and logically separate.

---

## Part 2: BYOIP including 7.0.0.0/8

NVIDIA hands you one or more prefixes during onboarding. In every documented v2.3 deployment, those prefixes include `7.0.0.0/8` (or a slice of it). Your job is to:

1. Carve non-conflicting sub-ranges for pods, services, nodes, and floating IPs.
2. Tell Cilium to allocate from those ranges.
3. Tell every router/firewall in the path that `7.0.0.0/8` is **not a bogon**.

### 2.1 Carve the BYOIP allocation

Assume NVIDIA assigns you `7.42.0.0/16` (illustrative — substitute the real assignment).

| Slice | CIDR | Role |
|-------|------|------|
| Nodes | `7.42.0.0/22` | k0s/k0rdent node IPs |
| Pod CIDR | `7.42.16.0/20` | Cilium pod pool (ClusterPool IPAM) |
| Service CIDR | `7.42.32.0/22` | ClusterIP range |
| Floating / LB | `7.42.36.0/24` | Cilium `LoadBalancerIPPool`, stable per-service |
| Reserved | `7.42.64.0/18` | Future expansion, do not allocate |

Document this allocation in `artifacts/NET03-byoip-routing-policy.md` — it is the source of truth for every downstream config.

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
  name: dgxc-stable-pool
spec:
  blocks:
    - start: "7.42.36.10"
      stop:  "7.42.36.250"
```

Stable LB IPs are what NVIDIA allowlists on their side. Once an IP is bound to a Service, it must not change. Add the annotation `io.cilium/lb-ipam-sharing-key: dgxc` if you reuse the pool across namespaces.

### 2.4 Stop firewalls from filtering `7.0.0.0/8` as a bogon

The most common silent failure. On every router/firewall/ACL/security-group in the path **from the NCP edge to the GPU nodes**, explicitly permit `7.0.0.0/8`:

```bash
# FRR / vtysh — remove the default bogon filter for 7/8
configure terminal
ip prefix-list NO-BOGONS seq 5 deny 0.0.0.0/8 le 32
ip prefix-list NO-BOGONS seq 10 permit 7.0.0.0/8 le 32   # NVIDIA BYOIP — RFC1918-equivalent for DGXC
ip prefix-list NO-BOGONS seq 15 deny 10.0.0.0/8 le 32
# ...
```

Equivalent rules on Linux nodes if they hold conntrack/iptables policy:

```bash
iptables -I FORWARD -s 7.0.0.0/8 -j ACCEPT
iptables -I FORWARD -d 7.0.0.0/8 -j ACCEPT
```

Add a one-line comment in your config: `# NVIDIA DGXC BYOIP — treat 7.0.0.0/8 as RFC1918-equivalent`. Future engineers will read that comment and not "fix" it.

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
| NCP local IP (A) | `203.0.113.1/30` |
| NVIDIA POP IP (A) | `203.0.113.2/30` |
| NCP local IP (B) | `203.0.113.5/30` |
| NVIDIA POP IP (B) | `203.0.113.6/30` |
| NCP ASN | AS65000 |
| NVIDIA POP ASN | AS65001 |

### 3.2 FRR config for the upstream peering

```
! /etc/frr/frr.conf — edge-a
!
router bgp 65000
 bgp router-id 7.42.0.1
 no bgp default ipv4-unicast
 neighbor NVIDIA-POP peer-group
 neighbor NVIDIA-POP remote-as 65001
 neighbor NVIDIA-POP password 7&dgxc-md5-shared-secret
 neighbor NVIDIA-POP timers 10 30
 neighbor NVIDIA-POP timers connect 10
 !
 neighbor 203.0.113.2 peer-group NVIDIA-POP
 neighbor 203.0.113.6 peer-group NVIDIA-POP
 !
 address-family ipv4 unicast
  network 7.42.0.0/16
  neighbor NVIDIA-POP activate
  neighbor NVIDIA-POP soft-reconfiguration inbound
  neighbor NVIDIA-POP route-map RM-TO-NVIDIA out
  neighbor NVIDIA-POP route-map RM-FROM-NVIDIA in
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

The Cilium BGP control plane advertises pod and LB IPs **to your own edge routers**, which re-advertise the aggregate `7.42.0.0/16` upstream to NVIDIA.

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: dgxc-cluster-bgp
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
          announce: "dgxc"
```

Verify with:

```bash
cilium bgp peers
cilium bgp routes advertised ipv4 unicast
vtysh -c 'show bgp ipv4 unicast summary'
vtysh -c 'show bgp ipv4 unicast 7.42.0.0/16'
```

You want one BGP session per edge router, ECMP across both upstream VIFs, and the `7.42.0.0/16` aggregate visible in NVIDIA's POP RIB.

---

## Part 4: MACsec to DGXC storage

MACsec is **IEEE 802.1AE**: Layer 2, frame-by-frame authenticated encryption between two adjacent Ethernet devices. It protects the link itself, not end-to-end across routed hops. NVIDIA mandates MACsec on the NIC pair that terminates each end of the storage link to the DGXC on-prem object storage POP (SEC18, NET05).

### 4.1 Topology and key model

```
[NCP storage edge NIC] ◀── MACsec SA (CAK/CKN) ──▶ [NVIDIA storage POP NIC]
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
    mka_ckn=11223344                             # CKN — exchanged with NVIDIA out-of-band
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
ip route add 7.42.250.0/24 dev macsec0    # DGXC storage POP subnet
# Do NOT add a fallback route over eno5.
```

In Cilium NetworkPolicy or host firewall, also drop any storage-subnet traffic that arrives on `eno5` directly:

```bash
iptables -I INPUT  -i eno5 -d 7.42.250.0/24 -j DROP
iptables -I OUTPUT -o eno5 -d 7.42.250.0/24 -j DROP
```

This is the fail-closed contract NET05 demands.

### 4.5 Key rotation runbook

| Action | Frequency | Owner |
|--------|-----------|-------|
| MKA SAK rotation (automatic) | Every ~30 minutes | MKA / wpa_supplicant |
| CAK rotation (manual, dual-control) | Quarterly | NCP NetOps + NVIDIA NetOps, coordinated change window |
| CKN rotation | With CAK | Same |
| Replay-window audit (`ip -s macsec`) | Weekly | NCP NetOps |

Record the rotation evidence in `artifacts/NET05-macsec-config.md`.

---

## Part 5: Static egress NAT

Cluster Local Internet Access (NET06) is for outbound calls to NVIDIA-allowlisted services — container registries, telemetry endpoints, license servers. NVIDIA pins their allowlist to **specific egress IPs**, so those IPs must be:

- Dedicated to DGXC tenancy
- Never shared with other workloads on the same NCP
- Stable across NAT-gateway failover (DMS05)

### 5.1 Cloud-provider NAT GW pattern (preferred where available)

Allocate **dedicated** Elastic IPs for the DGXC tenant only:

```bash
# AWS example — illustrative
aws ec2 allocate-address --domain vpc --tag-specifications \
  'ResourceType=elastic-ip,Tags=[{Key=tenant,Value=dgxc},{Key=purpose,Value=egress-nat}]'
aws ec2 create-nat-gateway --subnet-id subnet-DGXC-public --allocation-id eipalloc-...
```

Route table for the DGXC tenant subnets points `0.0.0.0/0` at the dedicated NAT GW only. **Never** attach these EIPs to a shared NAT GW that also serves other tenants — auditors will catch it and you will fail NET06.

### 5.2 Self-hosted NAT instances with VRRP (bare-metal pattern)

When you do not have a managed NAT GW, run two NAT instances and float a VIP between them via VRRP:

```conf
# /etc/keepalived/keepalived.conf — nat-a (primary)
vrrp_instance VI_DGXC_EGRESS {
    state MASTER
    interface eno1
    virtual_router_id 42
    priority 200
    advert_int 1
    authentication { auth_type PASS; auth_pass dgxc-nat-vrrp; }
    virtual_ipaddress {
        198.51.100.7/32 dev eno1     # dedicated DGXC egress VIP (RFC5737 example)
    }
}
```

On each NAT instance, MASQUERADE only DGXC pod traffic out of that single VIP:

```bash
iptables -t nat -A POSTROUTING -s 7.42.0.0/16 -o eno1 \
    -j SNAT --to-source 198.51.100.7
```

The VIP follows the active node. Egress IP is stable from NVIDIA's perspective even during NAT-instance failover.

### 5.3 Make the egress allocation explicit

Document in `artifacts/NET06-static-egress-nat.md`:

| Egress IP | Bound to | Tenant | Failover model | Rotation policy |
|-----------|----------|--------|----------------|-----------------|
| 198.51.100.7 | NAT-A / NAT-B VRRP | DGXC | VRRP (nat-b backup) | Never rotated without NVIDIA change ticket |

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
      trustDomain: dgxc.ncp.local
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

Verify with `cilium hubble observe --type policy-verdict` — you should see `auth_required` verdicts succeed only for SPIRE-issued identities in `dgxc.ncp.local`.

### 6.2 North-south: ingress with terminated mTLS

For inbound API traffic from DGXC orchestration plane, terminate mTLS at the ingress and forward authenticated identity downstream:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: dgxc-ingress
spec:
  gatewayClassName: cilium
  listeners:
    - name: https-mtls
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: dgxc-server-cert
        options:
          gateway.envoyproxy.io/client-certificate-mode: "Require"
          gateway.envoyproxy.io/client-ca-bundle-ref: "dgxc-client-ca-bundle"
```

The `client-ca-bundle` is the NVIDIA-issued client CA. Without a valid client cert chained to that CA, the TLS handshake fails — no anonymous access, ever.

### 6.3 Coverage map

Build `artifacts/SEC13-mtls-coverage-map.md` listing every service and whether it sits behind mTLS:

| Service | Plane | mTLS posture | Identity source |
|---------|-------|--------------|-----------------|
| storage-gw | East-west | Cilium auth `required` | SPIRE (`dgxc.ncp.local`) |
| training-scheduler | East-west | Cilium auth `required` | SPIRE |
| k0rdent-api | North-south | Gateway `Terminate` + client CA | NVIDIA-issued client cert |
| breakfix-api | North-south | Gateway `Terminate` + client CA | NVIDIA-issued client cert |

Anything left unchecked is an SEC13 audit finding.

---

## Part 7: Produce the compliance-pack artifacts

Five artifacts, one per Req ID, all sanitized of secrets and Req-ID-stamped.

```bash
mkdir -p artifacts

# NET03 — BYOIP and routing policy
cat > artifacts/NET03-byoip-routing-policy.md <<'EOF'
# NET03 — BYOIP routing policy

| Prefix | Slice | Allocator | Stable? |
|--------|-------|-----------|---------|
| 7.42.0.0/22  | Nodes        | k0rdent IPAM     | Yes |
| 7.42.16.0/20 | Pod CIDR     | Cilium ClusterPool | Yes |
| 7.42.32.0/22 | Service CIDR | kube-apiserver   | Yes |
| 7.42.36.0/24 | LB / floating | Cilium LBPool   | Yes |

Bogon filter exception: 7.0.0.0/8 explicitly permitted on edge-a, edge-b,
and all host iptables policies. See commit <sha> in net-config repo.
EOF

# NET04 — BGP session to CorpIT
vtysh -c 'show running-config' \
  | sed 's/password .*/password REDACTED/' \
  > artifacts/NET04-corpit-bgp-session.md

# NET05 — MACsec config (sanitized)
{
  echo '# NET05 — MACsec config'
  echo
  ip -d link show macsec0
  echo
  ip -s macsec show macsec0
} | sed -E 's/(key [0-9]+ )[0-9a-f]+/\1REDACTED/g' \
  > artifacts/NET05-macsec-config.md

# NET06 — Static egress NAT allocation
cat > artifacts/NET06-static-egress-nat.md <<'EOF'
# NET06 — Static egress NAT

| Egress IP | Tenant | NAT topology | Rotation policy |
|-----------|--------|--------------|-----------------|
| 198.51.100.7 | DGXC (exclusive) | VRRP nat-a/nat-b | Frozen — change only via NVIDIA ticket |
EOF

# SEC13 — mTLS coverage map (built in Part 6)
# kept in artifacts/SEC13-mtls-coverage-map.md
```

Push these to the `ncp-compliance-pack` repo with the matching Req IDs in the commit message.

---

## Verification Checklist

- [ ] `7.0.0.0/8` permitted on every edge router and host firewall, with an inline comment marking it as DGXC BYOIP
- [ ] Cilium ClusterPool IPAM allocates from the assigned BYOIP slice; no collisions with NVIDIA-side ranges
- [ ] `cilium bgp peers` shows ESTABLISHED on both upstream VIFs
- [ ] NVIDIA POP RIB shows the aggregate prefix via both circuits (verify via NOC ticket — you cannot view the POP RIB yourself)
- [ ] `ip -d link show macsec0` shows the MACsec link UP and `encrypt on`
- [ ] `ip -s macsec show macsec0` counters increment under load; no `InPktsNotValid` drops
- [ ] Pulling power on the MACsec NIC takes the storage route with it (fail-closed verified)
- [ ] Dedicated egress EIP / VIP shown in NVIDIA's allowlist (verify via NOC ticket)
- [ ] `cilium hubble observe --type policy-verdict` shows `auth-required` succeeded on east-west flows
- [ ] North-south Gateway rejects requests with no client cert (test via `curl` without `--cert`)
- [ ] All five compliance artifacts present, Req-ID-stamped, secrets redacted

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| BGP session flaps every few minutes | TCP-MD5 password mismatch or path MTU drop | Verify the shared secret matches both ends; set `neighbor ... ebgp-multihop 2` and lower `tcp-mss` to 1400 on the VIF |
| Pod cannot reach `7.x.x.x` even though Cilium says it should | Upstream bogon filter still drops 7/8 | Walk every hop with `mtr 7.42.0.10`; the first router that drops is the one missing the exception |
| MACsec link comes up but no traffic flows | CKN mismatch — MKA negotiated a session but the CAK is wrong on one side | Compare `wpa_cli -i eno5 status`; both ends must show identical CKN, matching CAK fingerprint |
| `ip -s macsec` shows growing `InPktsLate` | Clock skew between the two endpoints exceeds the replay window | Tighten NTP on both ends to a stratum-2 source; widen `replay-window` only as a last resort |
| NAT pool exhaustion under load | Single VIP, too many concurrent flows, port exhaustion (~64k flows per VIP) | Add a second VIP, SNAT round-robin, document the second IP in NET06 artifact and re-request NVIDIA allowlist update |
| mTLS handshake fails with `unknown ca` | Gateway is using the wrong client CA bundle, or NVIDIA rotated their client CA | Re-fetch the client CA bundle from NVIDIA, update the Gateway `client-ca-bundle-ref`, restart Envoy |
| `cilium bgp peers` ESTABLISHED but no routes advertised | `serviceSelector` / `exportPodCIDR` not matching the workloads | Confirm Service has the `announce: dgxc` label and `cilium bgp routes advertised ipv4 unicast` lists the prefix |

---

## Key Takeaways

- **`7.0.0.0/8` is DGXC's RFC1918.** Bogon filters that drop it will silently break the cluster. Whitelist it everywhere, comment the whitelist so future engineers do not "fix" it.
- **PCI / VIF / BGP is the AWS Direct Connect of NVIDIA.** Same primitives, redundant circuits, eBGP with authentication. Two VIFs, ECMP, MD5 minimum.
- **MACsec on the storage path is non-negotiable and must fail closed.** Run MKA, rotate CAK quarterly, never route storage traffic over the bare NIC even as a fallback.
- **Static egress NAT IPs are part of the DGXC contract.** Dedicated, never shared, never rotated without an NVIDIA change ticket.
- **mTLS sits on top of the transport.** Transport (MACsec, VIF) protects the wire; mTLS (Cilium + Gateway) proves identity. SEC13 needs both.

---

## Next Lab

[Lab 4.11 — NFSv4 + Parallel FS](lab-4.11-nfsv4-parallel-fs.md) — now that the storage link is MACsec-secured, the next lab presents NFSv4 and the parallel filesystems (Lustre / WEKA / VAST) that ride over it to the DGXC POP.
