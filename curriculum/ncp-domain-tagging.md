# NCP Domain Tagging Guide

> Companion reference for the k0rdent AI Infrastructure Training curriculum.
> Maps every lab and theory section to either **Core Kubernetes/Infrastructure concepts**, **NCP-specific NVIDIA Requirements**, or **Both** — and stamps each item with the exact Req IDs from the **NVIDIA Requirements Guide for AI Clouds v2.3 (Apr 2026)**.

## Why this exists

This curriculum has two audiences:

1. **Engineers learning core k0rdent / Kubernetes / AI-infrastructure concepts** — they need transferable skills they can apply on any platform.
2. **Engineers preparing to implement k0rdent on an NVIDIA DGX Cloud (DGXC) NCP engagement** — they need to know exactly which NVIDIA requirement each capability satisfies, and how to demonstrate compliance.

A single curriculum can serve both audiences if every learning unit is **tagged**: core, NCP-specific, or both.

## Tags

Every lab and major theory section in this curriculum carries one of three tags in a block immediately after the title:

| Tag | Meaning | When to read it |
|-----|---------|-----------------|
| 🌐 **CORE** | Core K8s / k0rdent / AI-infra concept. Transferable to any platform. Not specific to NVIDIA DGXC. | Always — these are the foundations. |
| 🟢 **NCP** | Specifically required by NVIDIA's Requirements Guide for AI Clouds. Maps to one or more Req IDs. | If you're preparing for an NCP engagement or working on the [compliance pack](https://github.com/mgueye01/ncp-compliance-pack). |
| 🔵 **BOTH** | A core concept AND a specific NCP requirement. The lab teaches transferable skill while satisfying a Req ID. | Always — these are double-duty. |

## How a tag block looks in a lab

Immediately after the lab title, look for:

```markdown
# Lab 5.17 — OpenTelemetry Telemetry Export

| Domain | Tag | NVIDIA Req IDs |
|--------|-----|----------------|
| Telemetry / Observability | 🟢 NCP | Telemetry §1 (Delivery Method), Telemetry §3 (Network), CAP01 |
```

The **NVIDIA Req IDs** column points to the specific requirement(s) from the v2.3 guide. Read the v2.3 guide PDF for the canonical wording of each Req ID.

## Req ID → Lab map

This is the master table. Use it to answer "which lab teaches the skill I need to satisfy Req X?"

### Compute & Network Provisioning (CNP)

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| CNP01 | API/CLI Access | 🔵 BOTH | Lab 1.1, Lab 1.3, Lab 1.5 |
| CNP02 | Declarative Resource Interfaces (Terraform) | 🔵 BOTH | Lab 1.3, Lab 1.4 |
| CNP03 | NVLink-Aware Allocation | 🟢 NCP | Lab 5.18 (new) |
| CNP04 | Resource States | 🌐 CORE | Lab 1.5, Lab 2.2 |
| CNP05 | Tagging / Cloud-Init Metadata | 🌐 CORE | Lab 1.5, Lab 3.3 |
| CNP06 | Console Access (Serial + 1-month logs) | 🟢 NCP | Lab 2.4 (new) — callout |
| CNP07 | VMs/Node ratio | 🌐 CORE | Lab 3.3 |
| CNP08 | Stable Identifiers | 🟢 NCP | Lab 2.4 (new) — callout |
| CNP09 | Firmware (signed + attested) | 🟢 NCP | Lab 2.5 (new — theory) |
| CNP10 | Remote Management (Redfish over TLS, disable IPMI) | 🟢 NCP | Lab 2.4 (new) |

### Boot Process & Disks (BOOT)

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| BOOT01 | Image Deployment & Updates | 🔵 BOTH | Lab 2.1, Lab 2.2 |
| BOOT02 | Cloud-Init / Metadata | 🌐 CORE | Lab 3.3 |
| BOOT03 | Custom Disk Images | 🔵 BOTH | Lab 4.8 |
| BOOT04 | Node Local Storage | 🌐 CORE | Lab 4.5 |

### SDN & Virtual Networking (SDN)

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| SDN01 | Virtual Networking + BYOIP (incl. 7.0.0.0/8) | 🟢 NCP | Lab 4.10 (new) |
| SDN02 | Security Groups | 🔵 BOTH | Lab 4.4 |
| SDN03 | Security Operations (CRUD audit) | 🔵 BOTH | Lab 4.4, Lab 1.9 (new) |
| SDN04 | Tenant Isolation | 🔵 BOTH | Lab 4.4, Lab 6.1 (capstone setup) |
| SDN05 | Floating / Movable IP | 🌐 CORE | Lab 4.4 |
| SDN06 | Localized DNS | 🌐 CORE | Lab 4.4 |
| SDN07 | VPC Peering | 🌐 CORE | Lab 4.4 |
| SDN08 | Storage Mesh L3 Connectivity | 🌐 CORE | Lab 4.5 |
| SDN09 | Network Observability | 🔵 BOTH | Lab 1.6 (KOF), Lab 5.17 (new — OTel) |

### Kubernetes (K8S)

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| K8S01 | CNCF-Certified Versions | 🔵 BOTH | Lab 1.1, Lab 4.1 |
| K8S02 | Version Updates (latest 3 minor) | 🌐 CORE | Lab 1.8, Lab 4.7 |
| K8S03 | EOL Policy | 🟢 NCP | Theory only (curriculum overview) |
| K8S04 | K8s Security Response Committee Participation | 🟢 NCP | Theory only |
| K8S05 | Lifecycle Mgmt — Control Plane | 🔵 BOTH | Lab 1.5, Lab 4.1 |
| K8S06 | Lifecycle Mgmt — Node Pool | 🔵 BOTH | Lab 4.6, Lab 4.8 |
| K8S07 | API Server Metrics (Prometheus) | 🔵 BOTH | Lab 1.6 |
| K8S08 | Provider-managed CP Upgrades | 🌐 CORE | Lab 4.7 |
| K8S09 | Zero-Downtime Upgrades | 🌐 CORE | Lab 4.7 |
| K8S10 | Node Upgrades (rolling, PDB) | 🌐 CORE | Lab 4.7 |
| K8S11 | HA Control Plane (etcd separation) | 🌐 CORE | Lab 4.1 |
| K8S12 | Backup & DR | 🌐 CORE | Lab 4.7 |
| K8S13 | K8s Security Response | 🟢 NCP | Theory only |
| K8S14 | Control Plane Isolation (separate from workers) | 🔵 BOTH | Lab 4.1 (hosted CP) |
| K8S15 | Access Controls (cluster endpoint) | 🔵 BOTH | Lab 1.4 |
| K8S16 | IAM Integration (SA → platform identity) | 🟢 NCP | Lab 6.5 (new) |
| K8S17 | Service Accounts + projected tokens | 🔵 BOTH | Lab 6.5 (new) |
| K8S18 | Public OIDC Endpoint (per-cluster Issuer) | 🟢 NCP | Lab 6.5 (new) |
| K8S19 | Encryption at rest (etcd + secrets) | 🔵 BOTH | Lab 6.4 (new) |
| K8S20 | Audit Logs (apiserver, kcm) | 🔵 BOTH | Lab 1.9 (new) |
| K8S21 | CRDs + Admission Controllers | 🌐 CORE | Lab 1.7 (kyverno) |
| K8S22 | CNI (NetworkPolicies, dual-stack desired) | 🌐 CORE | Lab 4.4 |
| K8S23 | CSI (block, FS, NFS) | 🔵 BOTH | Lab 4.5 |
| K8S24 | Dynamic Resource Allocation (DRA) | 🟢 NCP | Lab 4.9 (new) |
| K8S25 | Operator Support (replaceable accelerator operators) | 🌐 CORE | Lab 4.3 |
| K8S26 | Multiple clusters per tenancy / VPC | 🔵 BOTH | Lab 4.2 |
| K8S27 | Managed CP Pinning (pre-scaled capacity) | 🟢 NCP | Lab 4.1 (callout) |
| K8S28 | Performance up to 5000 nodes | 🌐 CORE | Theory only |

### Security & Identity (SEC)

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| SEC01 | Authentication (OIDC) | 🔵 BOTH | Lab 6.5 (new), Lab 6.6 (capstone) |
| SEC02 | In-Cluster Workload/Node Identity | 🌐 CORE | Lab 6.5 (new) |
| SEC03 | External Service Authentication | 🌐 CORE | Lab 6.5 (new) |
| SEC04 | Authorization (RBAC, least-privilege) | 🔵 BOTH | Lab 1.4, Lab 6.6 |
| SEC05 | NVIDIA LDAP / RFC2307bis Directory | 🟢 NCP | Lab 6.5 (new) |
| SEC06 | Workload/Service Identity (OIDC federation) | 🔵 BOTH | Lab 6.5 (new) |
| SEC07 | Admin MFA | 🌐 CORE | Lab 1.4 |
| SEC08 | Audit Logs (30-day min) | 🔵 BOTH | Lab 1.9 (new) |
| SEC09 | Key & Certificate Lifecycle | 🔵 BOTH | Lab 1.7 (cert-manager) |
| SEC10 | Key Usage across services | 🌐 CORE | Lab 1.7 |
| SEC11 | Tenancy Model (hard isolation) | 🟢 NCP | Lab 6.6, Lab 6.4 (new) |
| SEC12 | BMC Security (dedicated network, jumphost) | 🟢 NCP | Lab 2.4 (new) |
| SEC13 | Network Traffic Encryption (mTLS east-west + north-south) | 🟢 NCP | Lab 4.10 (new) |
| SEC14 | Private Access (no default public Internet) | 🟢 NCP | Lab 4.10 (new) |
| SEC15 | Edge Network Security Policy (5-tuple) | 🟢 NCP | Lab 4.4 |
| SEC16 | Enforcement (HW firewalls / SDN / DPU) | 🟢 NCP | Theory only |
| SEC17 | Threat Intelligence & Scale | 🟢 NCP | Theory only |
| SEC18 | MACsec link encryption (NCP↔NVIDIA POP) | 🟢 NCP | Lab 4.10 (new) |
| SEC19 | SOC 2 Type 1+ | 🟢 NCP | Theory only |
| SEC20 | At-Rest Data Protection (SED) | 🟢 NCP | Lab 6.4 (new) |
| SEC21 | Data Sanitization between tenants (crypto erase) | 🟢 NCP | Lab 6.4 (new) |
| SEC22 | Hardware Root of Trust + TPM 2.0 + Secure Boot | 🟢 NCP | Lab 2.5 (new — theory) |

### Breakfix (BFX)

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| BFX01 | Breakfix lifecycle (power-cycle, GPU reset, cordon, replace) | 🟢 NCP | Lab 6.2 (new) |
| BFX02 | Breakfix Events (query, history, ticket data) | 🟢 NCP | Lab 6.2 (new) |
| BFX03 | Diagnostics (serial numbers, firmware versions) | 🟢 NCP | Lab 6.2 (new) |

### Telemetry

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| Telemetry §1 | Delivery Method (OTLP ≤120s) | 🟢 NCP | Lab 5.17 (new) |
| Telemetry §2 | Telemetry Scope (per spec doc) | 🟢 NCP | Lab 5.17 (new) |
| Telemetry §3 | Network Telemetry (5 domains) | 🟢 NCP | Lab 5.17 (new) |
| Telemetry §4 | Logs (Fabric Mgr, Subnet Mgr, VPC Flow, UFM, switch, BMC SEL) | 🟢 NCP | Lab 5.17 (new) |

### Storage (DIR + HSS + DMS + STG)

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| DIR01 | Home Directory uid/gid Quota | 🟢 NCP | Lab 4.11 (new) |
| DIR02 | NFSv4 Storage | 🟢 NCP | Lab 4.11 (new) |
| HSS01 | Storage Provisioning APIs | 🔵 BOTH | Lab 4.5 |
| HSS02 | Storage Performance / QoS | 🟢 NCP | Lab 4.5, Lab 5.15 |
| HSS03 | K8s CSI Integration | 🌐 CORE | Lab 4.5 |
| HSS04 | Quota Support per workload | 🔵 BOTH | Lab 4.5 |
| HSS05-18 | Parallel FS, HA, RDMA, multipathing, audit | 🟢 NCP | Lab 4.11 (new), Lab 5.15 |
| DMS01 | Dedicated K8s cluster for Data Mover | 🟢 NCP | Lab 3.4 (new — reframed VMaaS) |
| DMS02 | Data Mover Nodes (CPU + high-perf network) | 🟢 NCP | Lab 3.4 (new) |
| DMS03 | Shared filesystem with GPU storage | 🟢 NCP | Lab 3.4 (new) |
| DMS04 | Access to NVIDIA corp net | 🟢 NCP | Lab 4.10 (new) |
| DMS05 | Stable egress IP | 🟢 NCP | Lab 4.10 (new) |
| STG01-06 | DGXC-Managed Storage Host Provisioning | 🟢 NCP | Theory + Lab 4.11 (new) |

### Network Transport & Fabric (NET)

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| NET01 | Backend Switch Fabric API (leaf/spine/core) | 🟢 NCP | Lab 5.18 (new) |
| NET02 | NVLink Domain API | 🟢 NCP | Lab 5.18 (new) |
| NET03 | BYOIP + 7.0.0.0/8 + Stable IP | 🟢 NCP | Lab 4.10 (new) |
| NET04 | Connection to NVIDIA CorpIT (PCI + VIF + BGP) | 🟢 NCP | Lab 4.10 (new) |
| NET05 | Connection to DGXC Storage (MACsec) | 🟢 NCP | Lab 4.10 (new) |
| NET06 | Cluster Local Internet Access (static egress NAT) | 🟢 NCP | Lab 4.10 (new) |

### Capacity & Fleet Management (CAP)

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| CAP01 | Governance metrics (Delivered/Healthy/Reserved/In-Use) | 🟢 NCP | Lab 6.3 (new) |
| CAP02 | Resource Governance API (per-node metadata) | 🟢 NCP | Lab 6.3 (new) |
| CAP03 | Resource Discovery API (programmatic capacity handoff) | 🟢 NCP | Lab 6.3 (new) |
| CAP04 | Logical Compartmentalization + Atomic Topology Block | 🟢 NCP | Lab 6.3 (new), Lab 5.18 (new) |
| CAP05 | Unified Health & Lifecycle APIs | 🟢 NCP | Lab 6.3 (new) |

### Exemplar Cloud / Benchmarking

| Req ID | Requirement Area | Tag | Lab(s) |
|--------|------------------|-----|--------|
| BM01 | dgxc-benchmarking (within 5% of NVIDIA target on 512-GPU cluster) | 🟢 NCP | Lab 5.16 (callout) |

## Compliance pack alignment

The companion repository **[`ncp-compliance-pack`](https://github.com/mgueye01/ncp-compliance-pack)** (work-in-progress) is intended to hold the *evidence artifacts* for an NCP audit — API specs, runbook snapshots, telemetry samples, attestation outputs, and so on.

This curriculum's job is to give engineers the **conceptual + hands-on skill** to produce those artifacts. The bridge is the **Req ID**:

```
NVIDIA Requirements Guide v2.3      curriculum lab              compliance pack artifact
       (Req ID: NET02)        →     Lab 5.18 (topograph)   →    artifacts/NET02-nvlink-topology-api.json
       (Req ID: BFX01)        →     Lab 6.2 (breakfix)     →    artifacts/BFX01-breakfix-runbook.md
       (Req ID: Telemetry §1) →     Lab 5.17 (OTel)        →    artifacts/TEL01-otel-collector-config.yaml
```

When the compliance pack matures, every artifact filename should start with its Req ID. Engineers who complete this curriculum should be able to read a Req ID in the pack and immediately know which lab teaches the skill behind it.

## How to use this for NCP cert prep

If you're studying for an NCP engagement:

1. **Start with all 🟢 NCP and 🔵 BOTH labs.** These are the direct hits.
2. **Read the Req ID column** of every lab you complete and verify you understand each cited requirement's wording in the v2.3 guide.
3. **For each lab, identify what the "evidence" looks like** — what would you put in the compliance pack to prove the requirement is satisfied? (config file, API response, runbook, screenshot.)
4. **Use the [Capstone (Lab 6.6)](week-6-multitenancy/labs/lab-6.6-capstone.md) as a dry run** for the end-to-end story you'd tell during an NCP audit.

If you're learning core concepts:

1. **All labs marked 🌐 CORE or 🔵 BOTH are transferable.** Skip the 🟢 NCP labs on first pass — come back to them if NCP work is in your future.
2. The week structure (Foundations → BMaaS → VMaaS → KaaS → AI Workloads → Multi-Tenancy) is the recommended learning path independent of NCP focus.

## Version sync

This guide tracks **NVIDIA Requirements Guide for AI Clouds v2.3 (Apr 13, 2026)**. When the upstream guide bumps (v2.4 etc.), re-validate the Req IDs in this file. The mapping convention (🌐/🟢/🔵 + Req ID column in each lab) is stable across versions.

## Glossary

- **NCP** — NVIDIA Cloud Partner. A provider delivering NVIDIA-aligned AI infrastructure to NVIDIA DGX Cloud (DGXC).
- **DGXC** — NVIDIA DGX Cloud. NVIDIA's hosted AI cloud, consuming NCP-delivered infrastructure.
- **Req ID** — Stable identifier from the NVIDIA Requirements Guide (e.g., CNP01, NET02, BFX01).
- **Compliance Pack** — Evidence repository ([`ncp-compliance-pack`](https://github.com/mgueye01/ncp-compliance-pack)) where Req-ID-tagged artifacts live.
