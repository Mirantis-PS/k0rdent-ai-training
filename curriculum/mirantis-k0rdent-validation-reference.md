# Mirantis k0rdent Enterprise — Curriculum Validation Reference

> **Purpose:** This is the canonical fact sheet for the k0rdent AI Infrastructure Training curriculum. Every lab in this curriculum must align with the facts below before it can be considered production-ready training material. If the curriculum says something that contradicts this file, **this file wins** — or the docs URL it cites does.
>
> **Source of truth:** [docs.mirantis.com/k0rdent-enterprise/latest](https://docs.mirantis.com/k0rdent-enterprise/latest/) (current released version: **v1.3.2** at time of writing).
>
> **Companion sources (allowed):**
> - NVIDIA official docs / GitHub repos (e.g., `github.com/NVIDIA/topograph`, `github.com/NVIDIA/k8s-dra-driver`, the v2.3 Requirements Guide) — for NCP-specific topics where Mirantis docs are silent
> - OSS alternatives only when k0rdent Enterprise doesn't cover the capability AND with an explicit `// OSS-ALTERNATIVE` callout in the lab text

## Version pinning

- **k0rdent Enterprise:** v1.3.2 (current released)
- **CRD API group:** `k0rdent.mirantis.com`
- **Stable CRD version:** `v1beta1`
- **Curriculum overview** lists validated component versions for k0s (`v1.32.4+k0s.0`), KubeVirt (`v1.6.3`), GPU Operator (`v25.10.0`), Cluster API (`v1.11`), Metal3 CAPM3 (`v1.8.0`), etc. — see `curriculum/overview/training-program-overview.md`.

## Architecture — three Mirantis-shipped components

| Component | Long name | Role | Built on |
|-----------|-----------|------|----------|
| **KCM** | k0rdent Cluster Manager | Orchestrates cluster provisioning + lifecycle | Cluster API (CAPI) + k0smotron |
| **KSM** | k0rdent State Manager | Service/addon lifecycle across clusters | Project Sveltos |
| **KOF** | k0rdent Observability & FinOps | Centralized metrics/logs/traces + cost — **unified OpenTelemetry-based architecture** | OpenTelemetry Collector + Victoria* + Promxy + OpenCost |

Three architectural layers:
- **Management cluster** — hosts KCM, KSM, KOF controllers
- **Regional clusters** (v1.4.0+, optional) — host workloads + provider infrastructure, controlled by Management
- **Child clusters** (`ClusterDeployment`) — tenant workload clusters

## k0rdent Enterprise CRDs (canonical list)

All `k0rdent.mirantis.com/v1beta1` unless noted. Always use this group/version in lab snippets.

| Kind | Scope | Purpose |
|------|-------|---------|
| `AccessManagement` | Namespaced | Object distribution to TargetNamespaces |
| `ClusterDeployment` | Namespaced | User-facing cluster request (references ClusterTemplate + Credential) |
| `ClusterIPAM` | Namespaced | IP address allocation for clusters |
| `ClusterIPAMClaim` | Namespaced | IPAM requirements declaration |
| `ClusterTemplate` | Namespaced | Cluster infrastructure template (Helm-based, immutable) |
| `ClusterTemplateChain` | Namespaced | Upgrade paths between ClusterTemplate versions |
| `Credential` | Namespaced | Cloud-provider auth secrets |
| `Management` | **Cluster** | Management-cluster configuration |
| `ManagementBackup` | Namespaced | Management cluster backup operations |
| `MultiClusterService` | Namespaced | Multi-cluster service deployment (KSM) |
| `ProviderTemplate` | Namespaced | CAPI provider deployment templates |
| `Region` | **Cluster** | Regional cluster deployments (v1.4.0+) |
| `Release` | **Cluster** | k0rdent release tracking |
| `ServiceSet` | Namespaced | Grouped service deployment |
| `ServiceTemplate` | Namespaced | Application/service deployment template (Helm/Kustomize/raw) |
| `ServiceTemplateChain` | Namespaced | Upgrade paths between ServiceTemplate versions |
| `StateManagementProvider` | Namespaced | Service deployment mechanism specifier |

**Reference:** [docs.mirantis.com/k0rdent-enterprise/latest/reference/crds/](https://docs.mirantis.com/k0rdent-enterprise/latest/reference/crds/)

## ClusterTemplate types

Three categories, each with a naming convention:

| Type | Pattern | What it does |
|------|---------|--------------|
| **Standalone** | `<provider>-standalone-cp-*` (e.g., `aws-standalone-cp-0-0-x`) | Provisions both control plane and worker nodes |
| **Managed Kubernetes** | `<provider>-managed-cp-*` | Uses cloud-native managed K8s (EKS, AKS, GKE) |
| **Hosted Control Plane** | `<provider>-hosted-cp-*` (e.g., `aws-hosted-cp-*`) | Control plane runs as pods on the management cluster (k0smotron) |

**Important:** ClusterTemplates are **immutable**. Upgrades happen via `ClusterTemplateChain`, not by editing.

Templates share a common `.spec.helm` shape:
```yaml
spec:
  helm:
    chartRef:          # reference an existing HelmChart object, OR
    chartSpec:         # inline chart definition
      chart: string
      version: string
      sourceRef: { kind, name }
  providers: [string]
  providerContracts: { provider: version }
  k8sVersion: string
  k8sConstraint: string
```

Sources are FluxCD: `HelmRepository`, `GitRepository`, `OCIRepository`, `Bucket` — or native `ConfigMap`/`Secret`.

**Reference:** [docs.mirantis.com/k0rdent-enterprise/latest/templatehowto/the-templating-system-common-threads/](https://docs.mirantis.com/k0rdent-enterprise/latest/templatehowto/the-templating-system-common-threads/)

## KOF components (use these exact names in labs)

KOF is **already an OpenTelemetry-based pipeline**. Labs must NOT recommend "deploying OpenTelemetry alongside KOF" — they must recommend **extending KOF's existing OTel pipeline**.

| Layer | Components |
|-------|-----------|
| **Collection** (child clusters) | OpenTelemetry Collector (via opentelemetry-operator), opentelemetry-kube-stack, OpenCost |
| **Storage** (regional clusters) | VictoriaMetrics, VictoriaLogs, VictoriaTraces, vmauth, vmcluster, vmselect, kof-storage chart |
| **Aggregation/Query** | Promxy (cross-cluster PromQL), kof-operator |
| **Visualization/Access** | Grafana, Dex (OIDC SSO), KOF UI |

**Do NOT use these in labs** (they are not part of KOF):
- ❌ Loki — KOF uses VictoriaLogs
- ❌ Elasticsearch — KOF uses VictoriaLogs
- ❌ Standalone Prometheus — KOF uses VictoriaMetrics + Promxy
- ❌ Cortex, Mimir, Thanos — KOF uses VictoriaMetrics + Promxy

KOF auto-configuration labels:
- `k0rdent.mirantis.com/kof-cluster-role: child` (or `regional`)
- `k0rdent.mirantis.com/kof-tenant-id: <tenant>`

Deployment via KSM: `MultiClusterServices` automatically install `kof-storage` to regional clusters and `kof-collectors` to child clusters.

KOF supported export targets (today):
- **AWS CloudWatch Logs** (explicitly documented)
- **Generic OTLP endpoints** via standard OpenTelemetry Collector exporters: `otlphttp/logs`, `otlphttp/traces`, `prometheusremotewrite`
- **In-cluster sinks** (Management ↔ Regional patterns, with optional Istio)

KOF tenancy isolation is via the `kof-tenant-id` label + Promxy/VictoriaMetrics tenant headers (multi-tenant docs referenced at [docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/) — see "Multi-tenancy in KOF" sub-page).

**References:**
- [KOF Architecture](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-architecture/)
- [Using KOF](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-using/)
- [Storing KOF Data](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-storing/)

## Supported infrastructure providers

AWS, Azure, GCP, OpenStack, VMware (vSphere), KubeVirt, Bare Metal (Metal3), SSH/edge.

Bare metal is via **Metal3** (CAPM3 + Baremetal Operator). The `BareMetalHost` CRD lives in `metal3.io/v1alpha1`. Cluster API integration uses CAPM3.

KubeVirt-based VM provisioning is via **Mirantis k0rdent Virtualization** (separate addon; URL path `/addons/mkvirt/`).

## Mirantis-shipped addons

| Addon | URL path | What it is |
|-------|----------|------------|
| **Mirantis k0rdent AI** | `/k0rdent_ai/` | "Enterprise-grade AI lifecycle management" — components not fully documented at intro page; labs that touch AI workloads should cite the latest k0rdent AI docs |
| **Mirantis k0rdent Virtualization** | `/addons/mkvirt/` | KubeVirt-based VM provisioning + HCO (Hyperconverged Cluster Operator) |
| **Mirantis k0rdent UI** | `/addons/ui/` | Web UI for k0rdent management |
| **Ceph** (k0rdent Catalog) | `/catalog/` | Pre-built Ceph offering via `CephDeployment` CRD family |

## Hosted Control Plane

- Supported providers: AWS, Azure, Bare Metal, OpenStack, VMware, GCP, KubeVirt
- Backed by **k0smotron** — control plane components run as pods on the management cluster
- Enables decoupling: "Kubernetes controller nodes and worker nodes to reside not only in different clusters, but even in different clouds"
- This **satisfies NCP requirement K8S14** (control plane isolation — separate from workers, outside tenant cluster/VPC)

**Reference:** [docs.mirantis.com/k0rdent-enterprise/latest/admin/hosted-control-plane/](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/hosted-control-plane/)

## Position language for labs (Mirantis-oriented voice)

When writing labs, use this language pattern:

| ❌ Generic | ✅ Mirantis-oriented |
|------------|----------------------|
| "k0rdent gives you..." | "k0rdent Enterprise's **KCM** provisions clusters via..." |
| "Install Prometheus and Loki" | "k0rdent Enterprise's **KOF** ships VictoriaMetrics + VictoriaLogs as the canonical storage; configure additional exporters via the KOF OpenTelemetry pipeline" |
| "Deploy OpenTelemetry" | "Extend the KOF OpenTelemetry Collector with an additional exporter targeting..." |
| "Use Cluster API to..." | "k0rdent Enterprise wraps Cluster API in **KCM**; configure via `ClusterDeployment` referencing the `aws-hosted-cp-*` `ClusterTemplate`" |
| "Service mesh choice X or Y" | "k0rdent Enterprise positions service mesh as a `ServiceTemplate` — the catalog ships..." |

When Mirantis does NOT cover a topic and OSS is the only path:
1. State explicitly: `> **OSS alternative — pending validation:** [tool] is used here because k0rdent Enterprise does not currently provide [capability]. Substitute with the Mirantis-supported option if/when one ships.`
2. Choose only well-known, vendor-neutral tools (CNCF graduated/incubating preferred)
3. Flag in the lab's "Architectural Decision Frame" so reviewers can challenge

## Specific approved OSS dependencies (already in the curriculum)

These are real OSS projects the curriculum already references; safe to keep using:

| Tool | Used in | Status |
|------|---------|--------|
| **GPU Operator** (NVIDIA) | Labs 4.3, 5.1, 5.11 | NVIDIA-shipped; canonical for k8s GPU drivers |
| **KAI Scheduler** (NVIDIA) | Lab 5.3 | NVIDIA-shipped; OSS |
| **Run:AI** (NVIDIA) | Lab 5.4 | NVIDIA commercial / partial OSS |
| **vLLM** | Lab 5.5 | OSS inference engine, NVIDIA-aligned |
| **Cilium** | Lab 4.4 | CNCF; widely used CNI; assumed approved (already in curriculum) |
| **Multus** | Lab 4.4 | OSS; secondary network CNI |
| **Metal3** (CAPM3 + BMO) | Week 2 | CNCF Incubating; the bare-metal provider k0rdent KCM uses |
| **k0smotron** | Lab 4.1 | OSS; k0rdent KCM depends on it for hosted CP |
| **Kyverno** | Lab 1.7 | CNCF; policy engine |
| **cert-manager** | Lab 1.7 | CNCF graduated; cert lifecycle |
| **topograph** (NVIDIA) | Lab 5.18 | NVIDIA-shipped; reference impl for NET01/NET02 |
| **k8s-dra-driver** (NVIDIA) | Lab 4.9 | NVIDIA-shipped; reference DRA driver for GPUs |
| **fwupd** | Lab 2.5 | OSS; firmware update daemon — only OSS option for some vendors |
| **tpm2-tools** | Lab 2.5 | OSS; TPM 2.0 utility suite |
| **OpenTelemetry Collector** | Labs 5.17, 1.9 (post-fix), and KOF itself | Already part of KOF — use the same instance |
| **VictoriaMetrics / VictoriaLogs / VictoriaTraces** | Lab 5.17 (post-fix), 1.9 (post-fix) | Part of KOF — canonical |
| **Promxy** | Lab 5.17 (post-fix) | Part of KOF — canonical |
| **OpenCost** | KOF FinOps | Part of KOF — canonical |
| **FRR** (BGP) | Lab 4.10 | Linux Foundation; canonical OSS BGP daemon |

## Dependencies pending approval (flag to user)

These have been used or proposed in labs but need explicit user approval before being relied on as the canonical pattern:

| Tool | Used in | Why it's flagged |
|------|---------|------------------|
| **Loki** | Lab 1.9 (pre-fix) | KOF uses VictoriaLogs instead; replace |
| **Elasticsearch** | Lab 1.9 (pre-fix) | KOF uses VictoriaLogs instead; replace |
| **Jaeger** | Lab 5.17 (pre-fix) — used as OTLP test target | KOF has VictoriaTraces; use that for in-cluster, Jaeger only as a test receiver |
| **Honeycomb / Grafana Cloud** | Lab 5.17 (pre-fix) — listed as OTLP test target | OK as external test target with `// OSS-ALTERNATIVE — test only` note |
| **MACsec on FRR** | Lab 4.10 | FRR doesn't do MACsec; use `iproute2 ip macsec` + `wpa_supplicant` MKA — already what the lab says |
| **Service mesh choice** (Istio vs Cilium ClusterMesh) | Lab 4.10 | Need Mirantis position; flag |
| **External SIEM** for audit | Lab 1.9 (post-fix) | Mirantis doesn't ship a SIEM; allowing customer-supplied is standard |

## How to use this reference when writing labs

Every lab — new or being revised — must:

1. **Reference real CRDs only.** Cross-check any `apiVersion: k0rdent.mirantis.com/*` snippet against the canonical CRD list above.
2. **Use real component names.** No "Prometheus" when you mean VictoriaMetrics; no "Loki" when you mean VictoriaLogs; no "OpenTelemetry alongside KOF" — KOF is OTel.
3. **Cite a Mirantis docs URL** for any non-obvious k0rdent claim, in a `> **Mirantis docs:** [link]` blockquote near the relevant section.
4. **Stamp OSS dependencies** explicitly when they're outside the Mirantis catalog. Use the `// OSS-ALTERNATIVE` callout pattern.
5. **Position k0rdent Enterprise as the answer**, not as one option. The lab is teaching engineers to deliver Mirantis, not generic Kubernetes.

When in doubt, prefer Mirantis docs; if Mirantis is silent, prefer NVIDIA docs (for NCP-specific topics); if both are silent, OSS alternative with an explicit flag.

## Version sync log

| Date | What changed | Source |
|------|--------------|--------|
| 2026-05-25 | Initial validation reference created against k0rdent Enterprise v1.3.2 docs | docs.mirantis.com/k0rdent-enterprise/latest/ |
