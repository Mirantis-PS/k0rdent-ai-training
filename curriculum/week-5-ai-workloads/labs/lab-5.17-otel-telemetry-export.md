# Lab 5.17 — Extending KOF's OTel Pipeline for External Telemetry Export

**Domain:** Telemetry / Observability / KOF

> **Mirantis docs:** [KOF Architecture](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-architecture/) · [Storing KOF Data](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-storing/) · [Using KOF](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-using/)

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Operations & Telemetry | Required | 2.5 hours |

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
| Buffering on the producer side | None | Persistent queue at the Collector (default `sending_queue`) | **Persistent queue with 1 h `max_elapsed_time`** — survives short external-ingest outages without breaching the 120-s SLA on the next event |
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

## Part 3: Add an OTLP exporter to KOF for the external receiver

The Mirantis-supported pattern is to feed extra collector values into KOF's existing
`MultiClusterService`, which KSM then reconciles to every child cluster.

> **How the `kof-collectors` values actually reach the child (KOF 1.6, validated live).**
> On this release there is **one** KOF child `MultiClusterService` — `kof-child-cluster`
> in `kcm-system` (Helm-managed by the `kof-child` release) — and it bundles three
> services: `cert-manager`, `kof-operators`, and `kof-collectors`. You do **not** edit
> that MCS directly (it is Helm-owned and its `kof-collectors` values are a Go template).
> Instead, the template reads a per-cluster override from an annotation and deep-merges it
> over KOF's stock config with Helm's `mergeOverwrite`:
>
> ```
> mergeOverwrite (dict) $globalValuesFromHelm $collectorsValuesHere $collectorsValuesFromHelm $collectorsValuesFromAnnotation
> ```
>
> The last argument (highest precedence) is `index .Cluster.metadata.annotations "k0rdent.mirantis.com/kof-collectors-values"`.
> Two consequences you must get right:
> - **Annotate the CAPI `Cluster` object, not the `ClusterDeployment`.** The template's
>   `.Cluster` is the CAPI `Cluster` (`kubectl get cluster <name> -n kcm-system`). A
>   `ClusterDeployment` annotation does **not** propagate and has no effect (verified: the
>   exporter never appeared until the annotation was moved onto the `Cluster`).
> - Because it is `mergeOverwrite`, your override **extends** KOF's config — stock
>   exporters (`otlphttp/logs`, `otlphttp/traces`, `prometheusremotewrite`) and pipelines
>   survive alongside anything you add. This is the "extend, don't replace" guarantee, and
>   it is a deep merge of maps (new *keys* add; a key you also set is overwritten).
>
> Set the override (the YAML below is the annotation value):

```yaml
# Value of the k0rdent.mirantis.com/kof-collectors-values annotation on the CAPI Cluster.
# kof-collectors wraps the opentelemetry-kube-stack subchart, so per-collector
# config is set under opentelemetry-kube-stack.collectors.<name>.config — here the
# per-node `daemon` collector (renders as the kof-collectors-daemon CR).
opentelemetry-kube-stack:
  collectors:
    daemon:
      config:
        exporters:
          otlphttp/external:
            endpoint: ${env:EXTERNAL_OTLP_ENDPOINT}
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
          batch/external:
            timeout: 5s
            send_batch_size: 16384
        service:
          pipelines:
            metrics/external:
              receivers:  [prometheus, kubeletstats]   # adjust to KOF's receiver names on your version
              processors: [transform/external, batch/external]
              exporters:  [otlphttp/external]
            logs/external:
              receivers:  [filelog/syslog, filelog/fabric-manager, filelog/subnet-manager, journald, syslog]
              processors: [transform/external, batch/external]
              exporters:  [otlphttp/external]
            traces/external:
              receivers:  [otlp]
              processors: [batch/external]
              exporters:  [otlphttp/external]
```

> **Note on naming:** KOF's actual receiver and pipeline names are set by the `opentelemetry-kube-stack` subchart. Inspect `kubectl -n kof get opentelemetrycollector kof-collectors-daemon -o yaml` for the canonical names on your version before copy-pasting. `filelog/fabric-manager` and `filelog/subnet-manager` are receivers you add in Part 5 — they are not present in a default KOF install. The `daemon` collector already ships stock `metrics`, `logs`, and `traces` pipelines (verified: `traces` = `[otlp] → [otlphttp/traces]`); adding new `*/external` pipeline keys as above leaves those stock pipelines untouched.

> **Transport adaptation (test receiver).** The `tls:` block above is the production mTLS
> path. For a plain-HTTP in-cluster receiver (e.g. a throwaway Jaeger all-in-one), drop the
> `cert_file`/`key_file`/`ca_file` stanza and use `tls: {insecure: true}` with an `http://`
> endpoint — that is what was validated live against `http://jaeger.ext-otlp.svc.cluster.local:4318`.

Apply the override by annotating the **CAPI `Cluster`** object (not the `ClusterDeployment` —
see the box above), then verify KSM reconciles the merged config to the child cluster:

```bash
# collectors-values.yaml holds the opentelemetry-kube-stack:... block from above
kubectl annotate cluster <child-cluster> -n kcm-system \
  "k0rdent.mirantis.com/kof-collectors-values=$(cat collectors-values.yaml)" --overwrite

# On the child cluster (reconciles in ~30-60 s)
kubectl -n kof get opentelemetrycollector kof-collectors-daemon -o yaml \
  | yq '.spec.config.exporters | keys'
# Expected: KOF's stock exporters (otlphttp/logs, otlphttp/traces, prometheusremotewrite,
# debug, nop) AND 'otlphttp/external' — proof the values MERGE, not replace.
```

---

## Part 4: Cover the 5 network-telemetry domains via KOF labelling

The canonical telemetry surface for AI infrastructure spans **five** network domains. Stamp each metric/log with a `net.domain` resource attribute so downstream consumers can filter:

| Domain | KOF source | Resource attribute |
|--------|------------|---------------------|
| **North-South (Front-End)** | KOF scrapes ingress (`ingress-nginx`) metrics; promxy aggregates | `net.domain=north-south` |
| **East-West (Back-end)** | `node_exporter` InfiniBand counters; DCGM PCIe/NVLink counters; UFM REST polling | `net.domain=east-west` |
| **Management** | KOF's apiserver/kcm metrics (already in collection) | `net.domain=mgmt` |
| **NVSwitch Fabric** (GB200+) | `nvidia-fabric-manager` exposed metrics + Subnet Manager logs | `net.domain=nvswitch` |
| **Host Network** | `prometheus`/`kubeletstats` host metrics (already in kof-collectors-daemon) | `net.domain=host` |

Use a `transform` processor in the kof-collectors values patch to stamp the right label by source. Example for east-west:

```yaml
processors:
  transform/external:
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

## Part 5: Cover the 9 standard log sources

The standard scope for AI infrastructure observability includes the following log sources. Map each to a KOF receiver:

| Log source | KOF receiver | Notes |
|------------|--------------|-------|
| Fabric Manager logs (NVLink) | `filelog/fabric-manager` on `/var/log/fabricmanager.log` (GB200+ nodes only) | Present when `nvidia-fabric-manager` runs |
| Subnet Manager logs (NVLink) | `filelog/subnet-manager` on `/var/log/opensm.log` | Where the operator runs SM |
| VPC Flow logs | Cloud-provider receiver — KOF doesn't ship a VPC Flow scraper out of box; add `awss3` (or equivalent cloud receiver) per region | One config per region |
| UFM Event logs | `httpcheck` + `filelog` against UFM REST `/ufmRest/app/events` (poll every 10 s) | KOF-friendly |
| General Switch Logs / Switch syslogs / Switch kernel logs | `syslog` receiver on the kof-collectors Collector, TCP/6514 with TLS | Configure switches to forward via TLS for transport encryption |
| BMC SEL logs | `filelog` against a BMC-polling sidecar (Redfish or `ipmitool sel list`) on a scheduled basis | Pairs with Lab 2.4 (BMC hardening) |
| Host syslogs | Already covered by KOF's default `filelog/syslog` | Out of the box |

Sample syslog receiver patch (added to kof-collectors values):

```yaml
opentelemetry-kube-stack:
  collectors:
    daemon:
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

Configure each switch to forward syslog over TLS to the Collector's syslog endpoint — production-grade transport encryption.

---

## Part 6: Validate end-to-end latency ≤ 120 s

Inject a synthetic event and time it from emission to OTLP receiver.

**Test 1 — synthetic log.**

```bash
# On a child-cluster GPU node
ssh gpu-node-1 'logger -t otel-latency-test "PROBE_$(date +%s%N)"'

# In the external OTLP receiver, find the line, subtract the nanosecond timestamp from the receive time
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

Record all three results in a latency-evidence log.

---

## Verification Checklist

- [ ] Child cluster carries `k0rdent.mirantis.com/kof-cluster-role: child` label
- [ ] KOF `OpenTelemetryCollector` CR present on every child cluster and Healthy
- [ ] `otlphttp/external` (or `otlp/external`) exporter visible in the rendered Collector config
- [ ] `MultiClusterService` reconciles the patched values to all child clusters (no drift)
- [ ] All 5 network domains have at least one metric flowing with the correct `net.domain` resource attribute
- [ ] All 9 log sources (where applicable) appear at the external OTLP receiver
- [ ] mTLS configured on the Collector → external receiver hop
- [ ] Synthetic probe latency measured ≤ 120 s in all three test conditions
- [ ] Buffered queue tested (1-hour `max_elapsed_time`) survives ≥ 30 s egress outage
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
