# Lab 5.17 — Extending KOF's OTel Pipeline for External Telemetry Export

**Domain:** Telemetry / Observability / KOF

> **Mirantis docs:** [KOF Architecture](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-architecture/) · [Storing KOF Data](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-storing/) · [Using KOF](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-using/)

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Operations & Telemetry | Elective | 2.5 hours |

### Week 5 Learning Paths

```
FOUNDATION ➔ … ➔ 5.15 RDMA ➔ 5.16 Dist Train
                                  ↓
                          [5.17] KOF → external OTLP export
                                  ↓
                          [5.18] topograph
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.16 — Distributed Training](lab-5.16-distributed-training.md) | **Lab 5.17 — KOF → External OTel Export** | [Lab 5.18 — topograph / NVLink Topology API](lab-5.18-topograph-nvlink-topology.md) |

---

**Duration:** 2.5 hours
**Type:** Hands-on Technical
**Environment:** k0rdent Enterprise management cluster with KOF installed (Lab 1.6) + at least one child cluster with `k0rdent.mirantis.com/kof-cluster-role: child` + an external OTLP receiver (Jaeger/Tempo/Honeycomb/Grafana Cloud)

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [What you should NOT do — and why](#what-you-should-not-do--and-why)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: The 120-second SLA — what it actually means](#part-1-the-120-second-sla--what-it-actually-means)
- [Part 2: Locate KOF's OpenTelemetry Collector and understand the existing pipeline](#part-2-locate-kofs-opentelemetry-collector-and-understand-the-existing-pipeline)
- [Part 3: Add an OTLP exporter to KOF for the external receiver](#part-3-add-an-otlp-exporter-to-kof-for-the-external-receiver)
- [Part 4: Cover the 5 network-telemetry domains via KOF labelling](#part-4-cover-the-5-network-telemetry-domains-via-kof-labelling)
- [Part 5: Cover the 9 standard log sources](#part-5-cover-the-9-standard-log-sources)
- [Part 6: Validate end-to-end latency ≤ 120 s](#part-6-validate-end-to-end-latency--120-s)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

Real-time observability at fleet scale requires push-based, low-latency telemetry — pull-based Prometheus scrapes at 5-minute intervals can't meet sub-2-minute requirements that any modern AI-cloud consumer (DR site, multi-region aggregator, downstream SaaS APM) expects. Mirantis k0rdent Enterprise already meets the *collection* side: **KOF is a unified OpenTelemetry-based architecture** (see the [KOF Architecture docs](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-architecture/)). Its collection layer is the OpenTelemetry Collector (managed by `opentelemetry-operator`), with `opentelemetry-kube-stack` providing host/OS/Kubernetes metrics and OpenCost providing FinOps signals. Storage is VictoriaMetrics (metrics), VictoriaLogs (logs), and Jaeger (traces). Aggregation across clusters is Promxy.

What this lab does is **extend KOF's existing OTel pipeline to forward telemetry to an external OTLP-compatible endpoint**, with an end-to-end latency budget you can defend. The pattern works for any external consumer.

## What you should NOT do — and why

A common (wrong) instinct is to deploy a parallel OpenTelemetry Collector "for the external receiver" alongside KOF. **Don't.** Two pipelines means:

- Two scrape topologies to maintain
- Two memory limiter/batcher tunings that can drift
- Duplicate telemetry volume on every node (≈ 2× CPU and network on the host agent)
- KOF's auto-configuration via `k0rdent.mirantis.com/kof-cluster-role` labels and `MultiClusterServices` no longer covers your second pipeline
- One additional path to operate and monitor

KOF's OTel Collector already runs on every child cluster. The right move is to **add an exporter to KOF's existing Collector** and use KOF's own service discovery for everything you want shipped externally.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Locate the OpenTelemetry Collector instance KOF deploys to a child cluster
- [ ] Add an `otlphttp/external` (or `otlp/external`) exporter to KOF's Collector via the kof-collectors Helm values that flow through the `MultiClusterService` KSM uses
- [ ] Stamp the five canonical network-telemetry domains as resource attributes using a `transform` processor inside KOF
- [ ] Forward the nine standard log sources via KOF (Fabric Manager, Subnet Manager, VPC Flow, UFM, Switch syslog/kernel, BMC SEL, host syslog)
- [ ] Measure end-to-end probe → external receiver latency and prove ≤ 120 s
- [ ] Produce a rendered Collector YAML + latency log as the deliverable for external telemetry export

---

## Prerequisites

- **Lab 1.6 — KOF deployed** (required). The collection layer must already exist on every cluster that has the `k0rdent.mirantis.com/kof-cluster-role: child` label.
- **[Lab 5.1 — GPU Cluster Setup](lab-5.1-gpu-cluster-setup.md)** (required). Installs the NVIDIA GPU Operator with `dcgm`/`dcgmExporter` enabled; DCGM metrics then flow through KOF.
- An external OTLP receiver. Acceptable test targets:
  - Local Jaeger (`jaegertracing/all-in-one`, OTLP receiver enabled)
  - Honeycomb free tier (OTLP endpoint + API key)
  - Grafana Cloud OTLP endpoint
  - Mirantis-validated path: **AWS CloudWatch Logs** is the only third-party target Mirantis explicitly documents for KOF; see [Storing KOF Data](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-storing/). Generic OTLP works via the standard OpenTelemetry Collector exporters that KOF embeds.
- `kubectl`, `helm`, `jq`, `curl`, access to the KOF Helm values for the `kof-collectors` chart

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| Where to add the external exporter | Edit the `OpenTelemetryCollector` CR KOF created directly | Feed values into KOF's `kof-child-cluster` MCS via the `k0rdent.mirantis.com/kof-collectors-values` annotation on the CAPI `Cluster` | **Annotation on the CAPI `Cluster`** — KOF `mergeOverwrite`s it over stock config, survives KOF upgrades, propagates to all child clusters, and is the Mirantis-supported path (the MCS itself is Helm-owned; don't edit it) |
| OTLP transport to the external receiver | gRPC (`otlp/external`) | HTTP (`otlphttp/external`) | **gRPC** — lower overhead at fleet scale; HTTP is the test fallback. Both are valid OTLP transports. |
| Exporter authentication | API key (`X-API-Key` header) | mTLS | **mTLS** — pairs with east-west + north-south encryption practices and is the production-grade default; API key is the test-only path |
| Sampling | Always-on full rate | Tail-sampled traces | **Always-on for metrics + logs**; traces only may be tail-sampled — metrics and logs are the contractual signals for downstream consumers, so sampling traces is the only safe place to do it |
| Buffering on the producer side | None | In-memory sending queue (default) | **File-backed queue plus a 1 h retry limit** — survives short external-ingest outages without breaching the 120-s SLA on the next event |
| Whether to ship via Regional cluster first | Direct from child → external receiver | child → Regional KOF storage → external receiver | **Child → Regional → external** when Regional clusters exist (v1.4.0+); direct from child only when there is no Regional layer. Matches KOF's documented three-layer flow. |

---

## Part 1: The 120-second SLA — what it actually means

The 120-second target is **end-to-end** (a generic engineering target for push-based AI-infrastructure telemetry):

```
event on infra  →  scraped/received by KOF kof-collectors (child)  →
  forwarded to KOF kof-storage (regional, if present)  →
  exported via OTLP to external receiver  →  acknowledged by receiver
                                                    (must be within 120 s of step 1)
```

This rules out a few common anti-patterns:

| Pattern | Why it fails |
|---------|--------------|
| 5-min Prometheus scrape interval | Latency floor is 300 s before any export hop |
| Batch S3 dump every 10 min | S3 lifecycle is not push; latency unbounded |
| Pull-based query model (consumer queries producer) | Consumer poll cadence dominates latency — a 120-s SLA requires push |
| Default OTel `batch` processor with 5-min timeout | Default is too coarse — tune `timeout: 5s` |

A defensible per-hop latency budget:

| Hop | Budget |
|-----|--------|
| Event → kof-collectors scrape | 5 s |
| kof-collectors → kof-storage (regional) | 10 s |
| Storage processor/batch | 10 s |
| OTLP wire to external receiver | 5 s |
| External receiver ingest ack | 10 s |
| **Headroom** | **80 s** |

Spend the headroom on routing reconvergence, OTLP retries, and intermittent blips — not on baseline.

---

## Part 2: Locate KOF's OpenTelemetry Collector and understand the existing pipeline

KOF deploys collectors via `MultiClusterServices` driven by KSM. On a child cluster:

```bash
# Confirm the cluster carries the KOF child label
kubectl get cluster <child-cluster> -o jsonpath='{.metadata.labels.k0rdent\.mirantis\.com/kof-cluster-role}'
# Expected: "child"

# Find the OpenTelemetryCollector CRs KOF created (kof-collectors is a Helm
# release wrapping the opentelemetry-kube-stack subchart — it renders several
# collector CRs, not one)
kubectl get opentelemetrycollectors.opentelemetry.io -A
# Expected (namespace kof): kof-collectors-daemon (per-node daemonset — hostmetrics,
# filelog, journald), kof-collectors-cluster-stats (cluster-scoped), plus
# kof-collectors-controller-k0s-daemon and kof-collectors-ta-daemon (target allocator)

# Inspect the per-node collector pipeline you will extend
kubectl -n kof get opentelemetrycollector kof-collectors-daemon -o yaml | yq '.spec.config'
```

You should see KOF's existing receivers (`prometheus`, `kubeletstats`, `filelog/syslog`, `journald`, `otlp`, etc.), processors (`batch`, `resourcedetection`, and the `transform/*` set), and exporters pointing at the regional `kof-storage` cluster's `vmauth` proxy (for metrics → VictoriaMetrics) plus the VictoriaLogs and Jaeger (traces) endpoints.

This is the pipeline you will extend — not replace.

---

## Part 3: Generate an external exporter from the installed collector

Use the committed [values generator](../../examples/telemetry/prepare-kof-values.py).
It reads the **actual daemon CR** to reuse existing receivers/processors, adds
separate external pipelines, and preserves chart-input mount lists. It refuses an
undefined receiver or an endpoint without HTTPS. A deep merge preserves unrelated
maps; lists are replaced, so the generator deliberately retains existing list items.

Run from the repository root. Set explicit management/workload kubeconfigs and the
actual cluster name (Lab 5.1 uses `gpu-cluster`). The external receiver must accept
**both metrics and logs** over OTLP/HTTP and have a certificate whose SAN matches
its DNS name. A trace-only Jaeger receiver cannot validate this exercise. Obtain a
CA and client certificate/key trusted by that receiver, then install them without
putting private keys in values or annotations:

```bash
export MGMT_KUBECONFIG=$HOME/.kube/config
export WORKLOAD_KUBECONFIG=$HOME/.kube/gpu-cluster.conf
export CLUSTER_NAME=gpu-cluster
export EXTERNAL_OTLP_ENDPOINT=https://otel.example.com:4318
# Replace the three local file paths with receiver-issued credentials.
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kof create secret generic kof-external-client \
  --from-file=ca.crt=/secure/external-ca.crt --from-file=tls.crt=/secure/client.crt \
  --from-file=tls.key=/secure/client.key --dry-run=client -o yaml | \
  kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" apply -f -
helm --kubeconfig "$WORKLOAD_KUBECONFIG" -n kof get values kof-collectors --all -o json > /tmp/kof-values.json
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kof get opentelemetrycollector kof-collectors-daemon -o json > /tmp/kof-daemon.json
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system get cluster "$CLUSTER_NAME" -o json | \
  jq -r '.metadata.annotations["k0rdent.mirantis.com/kof-collectors-values"] // "{}"' > /tmp/kof-before.yaml
python3 curriculum/examples/telemetry/prepare-kof-values.py --mode external \
  --values /tmp/kof-values.json --collector /tmp/kof-daemon.json \
  --existing /tmp/kof-before.yaml --endpoint "$EXTERNAL_OTLP_ENDPOINT" > /tmp/kof-external.yaml
```

The separate `kof-external-client` Secret and `/etc/otel/external` mount preserve
any Week 1 ingest credentials. Do not replace the storage-ingest client Secret.

Inspect the generated YAML and render with the pinned chart and current values:

```bash
helm template kof-collectors oci://ghcr.io/k0rdent/kof/charts/kof-collectors \
  --version 1.6.0 -n kof -f /tmp/kof-values.json -f /tmp/kof-external.yaml > /tmp/kof-rendered.yaml
# Apply the values through the owning KOF MCS's CAPI Cluster annotation.
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system annotate cluster "$CLUSTER_NAME" \
  k0rdent.mirantis.com/kof-collectors-values="$(cat /tmp/kof-external.yaml)" --overwrite
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kof get opentelemetrycollector kof-collectors-daemon -o yaml
```

Do not edit the Helm-owned MCS or the resulting collector CR. Confirm the rendered
receivers/exporters exist and the operator rolls out healthy pods. Validate the
complete rendered config with the exact collector image's `validate --config=...`
command before accepting a change. Re-generate after a KOF upgrade instead of
blindly carrying old pipeline names forward.

## Part 4: Buffering and labels

The generated daemon configuration uses `file_storage/external` and a node-local
hostPath queue. It survives a collector pod/process restart on the **same node**;
it does not survive node/disk loss and is not a replicated queue. `max_elapsed_time`
is the retry limit, not retention capacity. Watch queue size, capacity and failed
exports. Resource attributes from KOF's existing pipelines are preserved.

For additional network-domain attributes, classify each receiver/source explicitly.
Do not infer a whole resource's domain from one metric name: multiple metrics can
share that resource. Use separate source pipelines/resource processors where needed.

## Part 5: Extend the source inventory deliberately

The baseline exports sources already configured in KOF, including audit logs when
Lab 1.9 is complete. Fabric-manager files, subnet-manager files and switch syslog
are hardware-specific extensions. For each, provide the exact file/mount or TLS
listener, parsing rules and receiver definition before adding its name to a
pipeline. Re-render and validate with the installed collector image. Unsupported
or absent hardware sources are N/A, not evidence that all network domains were
observed. Record a source-to-receiver-to-backend table with the exercise evidence.

## Part 6: End-to-end latency and recovery acceptance

Synchronize clocks on source and receiver. Identify the daemon collector pod on a
GPU node and port-forward its enabled OTLP HTTP port (verify `spec.config.receivers.otlp`
first). This avoids assuming port 4318 is available on the administration machine:

```bash
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kof get pods -o wide
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kof port-forward pod/<daemon-pod-name> 4318:4318
```

In a second terminal, generate a portable nanosecond timestamp and submit probes:

```bash
PROBE_NS=$(python3 -c 'import time; print(time.time_ns())')
PROBE_ID="kof-latency-$PROBE_NS"
jq -n --arg ts "$PROBE_NS" --arg id "$PROBE_ID" \
  '{resourceLogs:[{scopeLogs:[{logRecords:[{timeUnixNano:$ts,body:{stringValue:$id}}]}]}]}' | \
  curl --fail-with-body -H 'Content-Type: application/json' --data-binary @- http://localhost:4318/v1/logs
jq -n --arg ts "$PROBE_NS" \
  '{resourceMetrics:[{scopeMetrics:[{metrics:[{name:"otel.latency.probe",gauge:{dataPoints:[{asDouble:1,timeUnixNano:$ts}]}}]}]}]}' | \
  curl --fail-with-body -H 'Content-Type: application/json' --data-binary @- http://localhost:4318/v1/metrics
```

Find both probes at the external receiver and calculate arrival time minus emission
time; the target is ≤120 seconds. Then interrupt only that receiver's connectivity
for 30 seconds using your test receiver's firewall/NetworkPolicy (verify it really
blocks traffic). Submit probes during the outage, restart the daemon pod on the
same node, restore connectivity, and confirm buffered probes arrive. Record loss,
duplicates and delay of the buffered probes as well as new probes after recovery.
A retry timeout or queue saturation is a failed resilience test, not an SLA pass.

Restore the previous annotation from `/tmp/kof-before.yaml` to revert. Remove the
external client Secret only after no collector uses it. Keep live evidence separate
from static/chart validation; this revised recipe still needs a qualified endpoint
and cluster to establish end-to-end acceptance.

---

## Verification Checklist

- [ ] Child cluster carries `k0rdent.mirantis.com/kof-cluster-role: child` label
- [ ] KOF `OpenTelemetryCollector` CR present on every child cluster and Healthy
- [ ] `otlphttp/external` (or `otlp/external`) exporter visible in the rendered Collector config
- [ ] `MultiClusterService` reconciles the patched values to all child clusters (no drift)
- [ ] Every applicable source is mapped to its receiver and verified at the external endpoint; absent hardware domains are marked N/A
- [ ] Existing KOF log sources and each configured extension appear at the external receiver
- [ ] mTLS configured on the Collector → external receiver hop
- [ ] Synthetic probe latency measured ≤ 120 s in all three test conditions
- [ ] Buffered probes survive a 30-second outage and same-node collector restart; retry limit and disk capacity are recorded
- [ ] No parallel "shadow" OpenTelemetry Collector deployed alongside KOF

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Latency > 120 s in steady state | `batch` processor `timeout` too high in the new pipeline | Set `batch/external.timeout: 5s` |
| Patch reverts after a KOF upgrade | Edited the Collector CR directly instead of using the annotation | Move the change into the `k0rdent.mirantis.com/kof-collectors-values` annotation on the CAPI `Cluster`; let KSM reconcile |
| Override annotation has no effect | Annotated the `ClusterDeployment` instead of the CAPI `Cluster` | The MCS template reads `.Cluster.metadata.annotations`; annotate `kubectl get cluster <name> -n kcm-system`, not the ClusterDeployment |
| Metrics missing the `net.domain` label | `transform/external` selector didn't match metric name | Inspect raw metric name on the receiver, adjust the `IsMatch(...)` regex |
| OTLP retries failing with `permission denied` | mTLS cert SAN doesn't match the external endpoint hostname | Re-issue cert with the correct SAN |
| Switch syslogs missing | Switch not configured for TLS, falling back to UDP/514 | Accept UDP only with an explicit transport-encryption exception, or fix switch TLS config |
| `MultiClusterService` Status shows Conflict | Two values overrides modifying the same key | Consolidate into a single layered values block |

---

## Key Takeaways

- **KOF is already OpenTelemetry.** Don't deploy a parallel Collector — extend the one KOF runs.
- **Patch via `MultiClusterService` values**, not by editing the `OpenTelemetryCollector` CR directly. That's the Mirantis-supported path that survives upgrades.
- **The 120-second SLA is end-to-end** and easy to blow with the wrong batch settings. Per-hop budget matters.
- **The 5 network domains and 9 log sources are the canonical telemetry surface** for AI infrastructure. Stamp them with `net.domain` resource attributes so downstream consumers can filter cleanly.
- **The deliverable for external telemetry export is the rendered Collector YAML + a latency log proving the SLA.** Both are easy to produce; both are what an operator or downstream consumer asks for first.

---

## Next Lab

[Lab 5.18 — topograph + NVLink Domain API](lab-5.18-topograph-nvlink-topology.md) — once you can *report* fabric state via KOF, you need to *expose* fabric topology via an API so an external scheduler can use it.
