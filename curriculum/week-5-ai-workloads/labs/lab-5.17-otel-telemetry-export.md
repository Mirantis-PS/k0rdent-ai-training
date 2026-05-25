# Lab 5.17 — Extending KOF's OTel Pipeline for DGXC Telemetry Export

| Domain | Tag | NVIDIA Req IDs |
|--------|-----|----------------|
| Telemetry / Observability / KOF | 🟢 NCP | Telemetry §1 (Delivery Method), Telemetry §3 (Network Telemetry), Telemetry §4 (Logs), SDN09 |

> **Compliance pack artifact targets:** `artifacts/TEL01-kof-otel-exporter-config.yaml`, `artifacts/TEL02-network-telemetry-coverage.md`, `artifacts/TEL02-latency-evidence.md`

> **Mirantis docs:** [KOF Architecture](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-architecture/) · [Storing KOF Data](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-storing/) · [Using KOF](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-using/)

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Operations & Telemetry | Required (NCP track) | 2.5 hours |

### Week 5 Learning Paths

```
FOUNDATION ➔ … ➔ 5.15 RDMA ➔ 5.16 Dist Train
                                  ↓
                          [5.17] KOF → DGXC OTLP export
                                  ↓
                          [5.18] topograph
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.16 — Distributed Training](lab-5.16-distributed-training.md) | **Lab 5.17 — KOF → DGXC OTel Export** | [Lab 5.18 — topograph / NVLink Topology API](lab-5.18-topograph-nvlink-topology.md) |

---

**Duration:** 2.5 hours
**Type:** Hands-on Technical
**Environment:** k0rdent Enterprise management cluster with KOF installed (Lab 1.6) + at least one child cluster with `k0rdent.mirantis.com/kof-cluster-role: child` + an external OTLP receiver as the DGXC stand-in (Jaeger/Tempo/Honeycomb/Grafana Cloud)

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [What you should NOT do — and why](#what-you-should-not-do--and-why)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: The 120-second SLA — what it actually means](#part-1-the-120-second-sla--what-it-actually-means)
- [Part 2: Locate KOF's OpenTelemetry Collector and understand the existing pipeline](#part-2-locate-kofs-opentelemetry-collector-and-understand-the-existing-pipeline)
- [Part 3: Add an OTLP exporter to KOF for DGXC](#part-3-add-an-otlp-exporter-to-kof-for-dgxc)
- [Part 4: Cover the 5 network-telemetry domains via KOF labelling](#part-4-cover-the-5-network-telemetry-domains-via-kof-labelling)
- [Part 5: Cover the 9 required log sources](#part-5-cover-the-9-required-log-sources)
- [Part 6: Validate end-to-end latency ≤ 120 s](#part-6-validate-end-to-end-latency--120-s)
- [Part 7: Produce the compliance-pack artifacts](#part-7-produce-the-compliance-pack-artifacts)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

The NVIDIA Requirements Guide v2.3 is explicit:

> *"NCP shall deliver all required telemetry, including metrics and logs, in a manner that allows for ingestion into DGX Cloud systems. The preferred methodology is natively via the OpenTelemetry Protocol with a latency of no longer than 120 seconds."*

Mirantis k0rdent Enterprise already meets the *collection* side of this requirement: **KOF is a unified OpenTelemetry-based architecture** (see the [KOF Architecture docs](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-architecture/)). Its collection layer is the OpenTelemetry Collector (managed by `opentelemetry-operator`), with `opentelemetry-kube-stack` providing host/OS/Kubernetes metrics and OpenCost providing FinOps signals. Storage is VictoriaMetrics, VictoriaLogs, and VictoriaTraces. Aggregation across clusters is Promxy.

What this lab does is **extend KOF's existing OTel pipeline to forward the v2.3-mandated subset of telemetry to an external DGXC endpoint**, with the 120-second end-to-end SLA verified.

## What you should NOT do — and why

A common (wrong) instinct is to deploy a parallel OpenTelemetry Collector "for DGXC" alongside KOF. **Don't.** Two pipelines means:

- Two scrape topologies to maintain
- Two memory limiter/batcher tunings that can drift
- Duplicate telemetry volume on every node (≈ 2× CPU and network on the host agent)
- KOF's auto-configuration via `k0rdent.mirantis.com/kof-cluster-role` labels and `MultiClusterServices` no longer covers your second pipeline
- One additional path to certify in an audit

KOF's OTel Collector already runs on every child cluster. The right move is to **add an exporter to KOF's existing Collector** and use KOF's own service discovery for everything you want shipped to DGXC.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Locate the OpenTelemetry Collector instance KOF deploys to a child cluster
- [ ] Add an `otlphttp/dgxc` (or `otlp/dgxc`) exporter to KOF's Collector via the kof-collectors Helm values that flow through the `MultiClusterService` KSM uses
- [ ] Stamp the five NVIDIA network-telemetry domains as resource attributes using a `transform` processor inside KOF
- [ ] Forward the nine required log sources via KOF (Fabric Manager, Subnet Manager, VPC Flow, UFM, Switch syslog/kernel, BMC SEL, host syslog)
- [ ] Measure end-to-end probe → DGXC latency and prove ≤ 120 s
- [ ] Produce a Req-ID-stamped artifact (`TEL01-kof-otel-exporter-config.yaml`) suitable for the compliance pack

---

## Prerequisites

- **Lab 1.6 — KOF deployed** (required). The collection layer must already exist on every cluster that has the `k0rdent.mirantis.com/kof-cluster-role: child` label.
- **Lab 4.3 — GPU Operator installed** (required). DCGM metrics flow through KOF.
- An external OTLP receiver as the DGXC stand-in. Acceptable test targets:
  - Local Jaeger (`jaegertracing/all-in-one`, OTLP receiver enabled)
  - Honeycomb free tier (OTLP endpoint + API key)
  - Grafana Cloud OTLP endpoint
  - Mirantis-validated path: **AWS CloudWatch Logs** is the only third-party target Mirantis explicitly documents for KOF; see [Storing KOF Data](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-storing/). Generic OTLP works via the standard OpenTelemetry Collector exporters that KOF embeds.
- `kubectl`, `helm`, `jq`, `curl`, access to the KOF Helm values for the `kof-collectors` chart

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| Where to add the DGXC exporter | Edit the `OpenTelemetryCollector` CR KOF created directly | Patch the `kof-collectors` Helm values via the `MultiClusterService` that KSM uses to install KOF | **Helm values via `MultiClusterService`** — survives KOF upgrades, propagates to all child clusters consistently, and is the Mirantis-supported path |
| OTLP transport to DGXC | gRPC (`otlp/dgxc`) | HTTP (`otlphttp/dgxc`) | **gRPC** — lower overhead at fleet scale; HTTP is the test fallback. NVIDIA accepts both per v2.3. |
| Exporter authentication | API key (`X-API-Key` header) | mTLS | **mTLS** — pairs with SEC13 (east-west + north-south encryption) and survives an NCP audit; API key is the test-only path |
| Sampling | Always-on full rate | Tail-sampled traces | **Always-on for metrics + logs**; traces only may be tail-sampled — telemetry is contractual under v2.3, sampling traces is the only safe place to do it |
| Buffering on the NCP side | None | Persistent queue at the Collector (default `sending_queue`) | **Persistent queue with 1 h `max_elapsed_time`** — survives short DGXC ingest outages without breaching the 120-s SLA on the next event |
| Whether to ship via Regional cluster first | Direct from child → DGXC | child → Regional KOF storage → DGXC | **Child → Regional → DGXC** when Regional clusters exist (v1.4.0+); direct from child only when there is no Regional layer. Matches KOF's documented three-layer flow. |

---

## Part 1: The 120-second SLA — what it actually means

`≤ 120 s` is **end-to-end**:

```
event on NCP infra  →  scraped/received by KOF kof-collectors (child)  →
  forwarded to KOF kof-storage (regional, if present)  →
  exported via OTLP to DGXC  →  acknowledged by DGXC receiver
                                                    (must be within 120 s of step 1)
```

This rules out a few common anti-patterns:

| Pattern | Why it fails |
|---------|--------------|
| 5-min Prometheus scrape interval | Latency floor is 300 s before any export hop |
| Batch S3 dump every 10 min | S3 lifecycle is not push; latency unbounded |
| Pull-based query model (DGXC queries NCP) | DGXC poll cadence dominates latency — v2.3 specifies push |
| Default OTel `batch` processor with 5-min timeout | Default is too coarse — tune `timeout: 5s` |

A defensible per-hop latency budget:

| Hop | Budget |
|-----|--------|
| Event → kof-collectors scrape | 5 s |
| kof-collectors → kof-storage (regional) | 10 s |
| Storage processor/batch | 10 s |
| OTLP wire to DGXC | 5 s |
| DGXC ingest ack | 10 s |
| **Headroom** | **80 s** |

Spend the headroom on routing reconvergence, OTLP retries, and intermittent blips — not on baseline.

---

## Part 2: Locate KOF's OpenTelemetry Collector and understand the existing pipeline

KOF deploys collectors via `MultiClusterServices` driven by KSM. On a child cluster:

```bash
# Confirm the cluster carries the KOF child label
kubectl get cluster <child-cluster> -o jsonpath='{.metadata.labels.k0rdent\.mirantis\.com/kof-cluster-role}'
# Expected: "child"

# Find the OpenTelemetryCollector CR KOF created
kubectl get opentelemetrycollectors.opentelemetry.io -A
# Expected: at least one CR in the kof namespace, e.g., kof-collectors

# Inspect the existing pipeline
kubectl -n kof get opentelemetrycollector kof-collectors -o yaml | yq '.spec.config'
```

You should see KOF's existing receivers (`hostmetrics`, `prometheus`, `filelog`, etc.), processors (`batch`, `memory_limiter`, `resourcedetection`), and exporters pointing at the regional `kof-storage` cluster's `vmauth` proxy (for metrics → VictoriaMetrics) plus VictoriaLogs and VictoriaTraces endpoints.

This is the pipeline you will extend — not replace.

---

## Part 3: Add an OTLP exporter to KOF for DGXC

The Mirantis-supported pattern is to patch the `kof-collectors` Helm values, which KSM then reconciles to every child cluster via its `MultiClusterService`.

Find the `MultiClusterService` KSM uses for kof-collectors:

```bash
kubectl -n kcm-system get multiclusterservice -l k0rdent.mirantis.com/component=kof-collectors -o yaml
```

Locate the `spec.serviceSpec.services[].values` block. Add a values override that introduces a new exporter and wires it into the metrics + logs + traces pipelines. Pattern (adjust to the chart version you have):

```yaml
# values-patch for kof-collectors MultiClusterService
opentelemetry-collector:
  config:
    exporters:
      otlphttp/dgxc:
        endpoint: ${env:DGXC_OTLP_ENDPOINT}
        tls:
          cert_file: /etc/otel/tls/tls.crt
          key_file:  /etc/otel/tls/tls.key
          ca_file:   /etc/otel/tls/ca.crt
        sending_queue:
          enabled: true
          num_consumers: 4
          queue_size: 5000
        retry_on_failure:
          enabled: true
          initial_interval: 1s
          max_interval: 30s
          max_elapsed_time: 3600s   # 1-hour buffer
    processors:
      batch/dgxc:
        timeout: 5s
        send_batch_size: 16384
    service:
      pipelines:
        metrics/dgxc:
          receivers:  [hostmetrics, prometheus, prometheus/dcgm]   # adjust to KOF's receiver names on your version
          processors: [memory_limiter, transform/dgxc, batch/dgxc]
          exporters:  [otlphttp/dgxc]
        logs/dgxc:
          receivers:  [filelog/syslog, filelog/kernel, filelog/fabric-manager, filelog/subnet-manager, syslog]
          processors: [memory_limiter, transform/dgxc, batch/dgxc]
          exporters:  [otlphttp/dgxc]
        traces/dgxc:
          receivers:  [otlp]
          processors: [memory_limiter, batch/dgxc]
          exporters:  [otlphttp/dgxc]
```

> **Note on naming:** KOF's actual receiver and pipeline names are set by the `kof-collectors` chart. Inspect `kubectl -n kof get opentelemetrycollector kof-collectors -o yaml` for the canonical names on your version before copy-pasting.

Apply the patched `MultiClusterService` and verify KSM reconciles to the child cluster:

```bash
kubectl apply -f mcs-kof-collectors-with-dgxc.yaml
kubectl -n kcm-system describe multiclusterservice kof-collectors | grep -A 5 'Status'

# On the child cluster
kubectl --context child-1 -n kof get opentelemetrycollector kof-collectors -o yaml \
  | yq '.spec.config.exporters | keys'
# Expected: includes 'otlphttp/dgxc'
```

---

## Part 4: Cover the 5 network-telemetry domains via KOF labelling

NVIDIA requires telemetry across **five** network domains. Stamp each metric/log with a `net.domain` resource attribute so DGXC can filter:

| Domain | KOF source | Resource attribute |
|--------|------------|---------------------|
| **North-South (Front-End)** | KOF scrapes ingress (`ingress-nginx`) metrics; promxy aggregates | `net.domain=north-south` |
| **East-West (Back-end)** | `node_exporter` InfiniBand counters; DCGM PCIe/NVLink counters; UFM REST polling | `net.domain=east-west` |
| **Management** | KOF's apiserver/kcm metrics (already in collection) | `net.domain=mgmt` |
| **NVSwitch Fabric** (GB200+) | `nvidia-fabric-manager` exposed metrics + Subnet Manager logs | `net.domain=nvswitch` |
| **Host Network** | `hostmetrics` receiver (already in kof-collectors) | `net.domain=host` |

Use a `transform` processor in the kof-collectors values patch to stamp the right label by source. Example for east-west:

```yaml
processors:
  transform/dgxc:
    metric_statements:
      - context: datapoint
        statements:
          - set(resource.attributes["net.domain"], "east-west") where IsMatch(metric.name, "^node_infiniband_.*|^DCGM_FI_PROF_NVLINK_.*")
          - set(resource.attributes["net.domain"], "host")      where IsMatch(metric.name, "^system_network_.*")
          - set(resource.attributes["net.domain"], "north-south") where resource.attributes["k8s.namespace.name"] == "ingress-nginx"
          - set(resource.attributes["net.domain"], "mgmt")       where IsMatch(metric.name, "^apiserver_.*|^kcm_.*")
          - set(resource.attributes["net.domain"], "nvswitch")   where IsMatch(metric.name, "^nvidia_fabric_manager_.*")
```

For UFM REST data, KOF can scrape via a `prometheus` receiver pointing at a UFM exporter sidecar (or you can convert UFM events to logs via a small forwarder if you don't run a UFM Prometheus exporter).

---

## Part 5: Cover the 9 required log sources

NVIDIA requires the following log sources. Map each to a KOF receiver:

| Log source | KOF receiver | Notes |
|------------|--------------|-------|
| Fabric Manager logs (NVLink) | `filelog/fabric-manager` on `/var/log/fabricmanager.log` (GB200+ nodes only) | Present when `nvidia-fabric-manager` runs |
| Subnet Manager logs (NVLink) | `filelog/subnet-manager` on `/var/log/opensm.log` | Where NCP runs SM |
| VPC Flow logs | Cloud-provider receiver — KOF doesn't ship a VPC Flow scraper out of box; add `awss3` (or equivalent cloud receiver) per region | One config per region |
| UFM Event logs | `httpcheck` + `filelog` against UFM REST `/ufmRest/app/events` (poll every 10 s) | KOF-friendly |
| General Switch Logs / Switch syslogs / Switch kernel logs | `syslog` receiver on the kof-collectors Collector, TCP/6514 with TLS | Configure switches to forward via TLS — pairs with SEC13 |
| BMC SEL logs | `filelog` against a BMC-polling sidecar (Redfish or `ipmitool sel list`) on a scheduled basis | Pairs with Lab 2.4 (BMC hardening) |
| Host syslogs | Already covered by KOF's default `filelog/syslog` | Out of the box |

Sample syslog receiver patch (added to kof-collectors values):

```yaml
opentelemetry-collector:
  config:
    receivers:
      syslog:
        tcp:
          listen_address: 0.0.0.0:6514
          tls:
            cert_file: /etc/otel/syslog-tls/tls.crt
            key_file:  /etc/otel/syslog-tls/tls.key
        protocol: rfc5424
        location: UTC
```

Configure each switch to forward syslog over TLS to the Collector's syslog endpoint — required for SEC13 compliance.

---

## Part 6: Validate end-to-end latency ≤ 120 s

Inject a synthetic event and time it from emission to OTLP receiver.

**Test 1 — synthetic log.**

```bash
# On a child-cluster GPU node
ssh gpu-node-1 'logger -t otel-latency-test "PROBE_$(date +%s%N)"'

# In the DGXC stand-in receiver, find the line, subtract the nanosecond timestamp from the receive time
# Target: ≤ 120 s; expect ≤ 30 s with this config
```

**Test 2 — synthetic metric.** Push a custom counter via the kof-collectors local OTLP HTTP endpoint:

```bash
curl -X POST -H 'Content-Type: application/json' \
  http://localhost:4318/v1/metrics \
  -d @- <<EOF
{ "resourceMetrics": [ { "resource": { "attributes": [{"key":"net.domain","value":{"stringValue":"mgmt"}}] },
  "scopeMetrics": [ { "metrics": [ { "name": "otel.latency.probe", "gauge": {
  "dataPoints": [{ "asDouble": 1.0, "timeUnixNano": "$(date +%s%N)" }] } } ] } ] } ] }
EOF
```

**Test 3 — buffered-recovery test.** Use a `NetworkPolicy` to block the kof-collectors egress for 30 s; re-enable. Confirm the `sending_queue` catches up *without* breaching the 120-s window for events generated *after* recovery.

Record all three results in `TEL02-latency-evidence.md`.

---

## Part 7: Produce the compliance-pack artifacts

```bash
# 1. Sanitized Collector config (the actual rendered state on a child cluster)
kubectl --context child-1 -n kof get opentelemetrycollector kof-collectors -o yaml \
  | yq 'del(.metadata.managedFields, .metadata.resourceVersion, .metadata.uid)' \
  > TEL01-kof-otel-exporter-config.yaml

# 2. Domain coverage map
cat > TEL02-network-telemetry-coverage.md <<'EOF'
| Domain | Status | KOF source | Sample metric |
|--------|--------|------------|---------------|
| North-South | ✅ | prometheus(ingress-nginx) | ingress_nginx_request_duration_seconds |
| East-West   | ✅ | prometheus(node_exporter + DCGM + UFM) | node_infiniband_port_data_received_bytes_total |
| Mgmt        | ✅ | prometheus(apiserver, kcm) | apiserver_request_duration_seconds |
| NVSwitch    | ⏭️ | (GB200+ only — N/A this cluster) | nvidia_fabric_manager_* |
| Host        | ✅ | hostmetrics | system_network_io |
EOF

# 3. Latency evidence
cp /tmp/latency-test-runs.log TEL02-latency-evidence.md
```

These artifacts are what an NVIDIA NCP audit will ask for. Keep them Req-ID-stamped, sanitized of secrets, and dated.

---

## Verification Checklist

- [ ] Child cluster carries `k0rdent.mirantis.com/kof-cluster-role: child` label
- [ ] KOF `OpenTelemetryCollector` CR present on every child cluster and Healthy
- [ ] `otlphttp/dgxc` (or `otlp/dgxc`) exporter visible in the rendered Collector config
- [ ] `MultiClusterService` reconciles the patched values to all child clusters (no drift)
- [ ] All 5 network domains have at least one metric flowing with the correct `net.domain` resource attribute
- [ ] All 9 log sources (where applicable) appear at the DGXC stand-in
- [ ] mTLS configured on the Collector → DGXC hop
- [ ] Synthetic probe latency measured ≤ 120 s in all three test conditions
- [ ] `TEL01-kof-otel-exporter-config.yaml` and `TEL02-*` artifacts produced
- [ ] Buffered queue tested (1-hour `max_elapsed_time`) survives ≥ 30 s egress outage
- [ ] No parallel "shadow" OpenTelemetry Collector deployed alongside KOF

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Latency > 120 s in steady state | `batch` processor `timeout` too high in the new pipeline | Set `batch/dgxc.timeout: 5s` |
| Patch reverts after a KOF upgrade | Edited the Collector CR directly instead of the `MultiClusterService` values | Move the change into the kof-collectors values patch; let KSM reconcile |
| Metrics missing the `net.domain` label | `transform/dgxc` selector didn't match metric name | Inspect raw metric name on the receiver, adjust the `IsMatch(...)` regex |
| OTLP retries failing with `permission denied` | mTLS cert SAN doesn't match the DGXC endpoint hostname | Re-issue cert with the correct SAN |
| Switch syslogs missing | Switch not configured for TLS, falling back to UDP/514 | Accept UDP only with explicit SEC13 exception, or fix switch TLS config |
| `MultiClusterService` Status shows Conflict | Two values overrides modifying the same key | Consolidate into a single layered values block |

---

## Key Takeaways

- **KOF is already OpenTelemetry.** Don't deploy a parallel Collector — extend the one KOF runs.
- **Patch via `MultiClusterService` values**, not by editing the `OpenTelemetryCollector` CR directly. That's the Mirantis-supported path that survives upgrades.
- **The 120-second SLA is end-to-end** and easy to blow with the wrong batch settings. Per-hop budget matters.
- **The 5 network domains and 9 log sources are non-negotiable** under v2.3. Stamp them with `net.domain` resource attributes so DGXC can filter cleanly.
- **The compliance-pack artifact is the rendered Collector YAML + a latency log.** Both are easy to produce; both are what the audit reads first.

---

## Next Lab

[Lab 5.18 — topograph + NVLink Domain API](lab-5.18-topograph-nvlink-topology.md) — once you can *report* fabric state via KOF, you need to *expose* fabric topology via an API so DGXC's scheduler can use it.
