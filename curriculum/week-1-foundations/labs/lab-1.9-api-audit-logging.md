# Lab 1.9 — Kubernetes API Audit Logging

**Domain:** Foundations / Security / Observability

> **Mirantis docs:** [KOF Architecture](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-architecture/) · [Using KOF](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/kof/kof-using/) · [k0rdent CRD reference](https://docs.mirantis.com/k0rdent-enterprise/latest/reference/crds/)

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundations / Production | Recommended | 1.5 hours |

| Previous | Current | Next |
|----------|---------|------|
| [Lab 1.8 — Upgrade k0rdent](lab-1.8-upgrade-k0rdent.md) | **Lab 1.9 — API Audit Logging** | [Week 2 — BMaaS](../../week-2-bmaas/) |

---

**Duration:** 1.5 hours
**Type:** Configuration + Verification
**Environment:** k0rdent management cluster + at least one managed cluster

## Table of Contents

- [Why this lab exists](#why-this-lab-exists)
- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Architectural Decision Frame](#architectural-decision-frame)
- [Part 1: Audit policy design — what to capture, what to drop](#part-1-audit-policy-design--what-to-capture-what-to-drop)
- [Part 2: Configure k0s audit policy on the management cluster](#part-2-configure-k0s-audit-policy-on-the-management-cluster)
- [Part 3: Configure audit on managed clusters via k0rdent](#part-3-configure-audit-on-managed-clusters-via-k0rdent)
- [Part 4: Forward to an OTel pipeline with ≥30-day retention](#part-4-forward-to-an-otel-pipeline-with-30-day-retention)
- [Part 5: Sample queries — what an audit will ask you to answer](#part-5-sample-queries--what-an-audit-will-ask-you-to-answer)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

---

## Why this lab exists

Audit logging is a foundational security and operational discipline for any Kubernetes cluster. Most engineers ship clusters with audit either off, or at a default policy that captures too little (no auth events, no RBAC changes) — or too much (verbose RequestResponse on everything, blowing log volume 100×).

This lab teaches a right-sized audit policy, configures k0s + KCM to enforce it, routes events through KOF's existing OTel pipeline into VictoriaLogs, and verifies the retention guarantee with LogsQL.

---

## Learning Objectives

By completing this lab, you will be able to:

- [ ] Justify the four audit policy levels (None, Metadata, Request, RequestResponse) for specific resource classes
- [ ] Configure a k0s audit policy on a k0rdent Enterprise management cluster
- [ ] Propagate that policy to managed clusters via a `ClusterTemplate` (referenced from `ClusterDeployment`) and ship cross-cluster via a `ServiceTemplate` in a `MultiClusterService`
- [ ] Route audit events through the existing KOF kof-collectors OTel Collector into VictoriaLogs (≥30-day retention)
- [ ] Write and run LogsQL queries against VictoriaLogs for the five canonical audit questions

---

## Prerequisites

- Lab 1.4 (Production configuration) — required
- Lab 1.5 (Provision managed cluster) — required
- Lab 1.6 (KOF) — **required** (KOF's VictoriaLogs is the canonical log store; you need the kof-collectors OTel Collector deployed on each cluster)
- Lab 5.17 (KOF → external OTel export) — recommended; without it you'll only retain logs locally in KOF VictoriaLogs and not forward them to any external consumer
- `kubectl`, `yq`, `jq`, `helm` (for adjusting kof-collectors values)

---

## Architectural Decision Frame

| Choice | Option A | Option B | Recommendation |
|--------|----------|----------|----------------|
| Capture level for `secrets` | Metadata (filename only) | RequestResponse (full value) | **Metadata** — never log secret payloads; you'd be writing them to your audit store |
| Capture level for `events` | Drop entirely (None) | Metadata | **None** — events are noise at audit scale; aggregate them via Kubernetes events to KOF instead |
| Hot log store | KOF VictoriaLogs (Mirantis-shipped) | External SIEM (Splunk / Sentinel / Chronicle, customer-provided) | **KOF VictoriaLogs** — already shipped by Mirantis as part of k0rdent Enterprise, OTel-native, no extra licensing. External SIEM is the addition when the customer mandates one — both can run in parallel via a second OTel exporter |
| Retention enforcement | At ingestor (VictoriaLogs retention via Helm values) | At cold-storage tier (S3 lifecycle) | **Both** — VictoriaLogs for hot queries (≥30 days, configured via the kof-storage chart), S3 lifecycle for cold tier (90+ days) for long-term recoverability |
| Audit log path | File on disk | Webhook to kof-collectors | **Webhook + file fallback** — webhook to the KOF OTel Collector avoids disk pressure; file remains as a panic-mode fallback when KOF is unreachable |

---

## Part 1: Audit policy design — what to capture, what to drop

Naive policies fail audits in one of two ways:

1. **Too little.** Auth failures, token issuance, RBAC binding changes — missing.
2. **Too much.** Every list / watch logged at RequestResponse, blowing log volume by 100×.

Right-sized policy (excerpt; full file in Part 2):

| Resource class | Verb pattern | Level | Why |
|----------------|--------------|-------|-----|
| `secrets`, `configmaps` (sensitive ns) | get, list, create, update, patch, delete | Metadata | Track access without exposing payload |
| `secrets`, `configmaps` (other ns) | create, update, patch, delete | Metadata | Mutations only |
| `roles`, `rolebindings`, `clusterroles`, `clusterrolebindings` | create, update, patch, delete | RequestResponse | RBAC changes are audit gold |
| `serviceaccounts/token` | create | RequestResponse (drop request body) | Token issuance event |
| `pods/exec`, `pods/attach`, `pods/portforward` | create | RequestResponse | Interactive access is highest-risk |
| `events` | * | None | Noise; capture aggregated elsewhere |
| `leases`, `endpoints`, `endpointslices` | get, list, watch | None | Control-plane chatter |
| Default | * | Metadata | Cover the unknown-unknown |

---

## Part 2: Configure k0s audit policy on the management cluster

Create the policy file. k0s supports the upstream Kubernetes audit policy format.

```yaml
# /etc/k0s/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: ["RequestReceived"]
rules:
  # Drop control-plane chatter
  - level: None
    resources:
      - group: ""
        resources: ["events", "endpoints"]
      - group: "coordination.k8s.io"
        resources: ["leases"]
      - group: "discovery.k8s.io"
        resources: ["endpointslices"]

  # Sensitive: log mutations, hide payloads
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]

  # RBAC: log everything
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]

  # Token issuance
  - level: RequestResponse
    verbs: ["create"]
    resources:
      - group: ""
        resources: ["serviceaccounts/token"]
    omitManagedFields: true

  # Interactive pod access
  - level: RequestResponse
    verbs: ["create"]
    resources:
      - group: ""
        resources: ["pods/exec", "pods/attach", "pods/portforward"]

  # Default
  - level: Metadata
```

Configure k0s to load the policy and write to file + webhook:

```yaml
# /etc/k0s/k0s.yaml (excerpt)
spec:
  api:
    extraArgs:
      audit-log-path: /var/log/k0s/audit.log
      audit-log-maxage: "30"             # 30 days on-disk
      audit-log-maxbackup: "10"
      audit-log-maxsize: "200"           # MB per file
      audit-policy-file: /etc/k0s/audit-policy.yaml
      audit-webhook-config-file: /etc/k0s/audit-webhook.yaml
      audit-webhook-batch-max-size: "400"
      audit-webhook-batch-max-wait: "5s"
```

Webhook config (forwards to the kof-collectors OTel Collector — the same one KOF already runs):

```yaml
# /etc/k0s/audit-webhook.yaml
apiVersion: v1
kind: Config
clusters:
- name: audit-kof
  cluster:
    server: https://kof-collectors-collector.kof.svc:4318/v1/logs
    certificate-authority: /etc/k0s/kof-ca.crt
contexts:
- name: audit-kof
  context:
    cluster: audit-kof
    user: audit
current-context: audit-kof
users:
- name: audit
  user:
    client-certificate: /etc/k0s/audit-client.crt
    client-key: /etc/k0s/audit-client.key
```

> The service name `kof-collectors-collector` is the default emitted by the `opentelemetry-operator` for the OpenTelemetry Collector CR KOF deploys; verify on your cluster with `kubectl -n kof get svc -l app.kubernetes.io/component=opentelemetry-collector`.

Restart k0s and verify the apiserver is using the policy:

```bash
sudo systemctl restart k0scontroller
ps aux | grep kube-apiserver | tr ' ' '\n' | grep audit
# Expected: --audit-policy-file, --audit-webhook-config-file, --audit-log-path all set

# Generate a known event
kubectl get secret -A | head -1
kubectl create rolebinding test-rb --clusterrole=view --user=alice -n default

# Confirm both events appear in the log
sudo tail -n 5 /var/log/k0s/audit.log | jq '{user: .user.username, verb, resource: .objectRef.resource, level}'
```

---

## Part 3: Configure audit on managed clusters via k0rdent

For each managed cluster, the audit config flows via the `ClusterDeployment` referencing the `ClusterTemplate`. Pattern:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterDeployment
metadata:
  name: tenant-a-gpu
  namespace: tenant-a
spec:
  template: aws-standalone-cp-0-0-x        # immutable ClusterTemplate — use a Chain to upgrade
  credential: aws-credentials
  config:
    k0s:
      apiServerArgs:
        audit-log-path: /var/log/k0s/audit.log
        audit-policy-file: /etc/k0s/audit-policy.yaml
        audit-log-maxage: "30"
      extraManifests:
        - name: audit-policy
          configMap: audit-policy-cm
```

Bundle the audit policy ConfigMap into the `ClusterTemplate`'s rendered manifests so every cluster instantiated from that template ships with it. For fleet-wide propagation across many templates, ship the audit policy via a `ServiceTemplate` referenced from a `MultiClusterService` so KSM reconciles it everywhere; that's the Mirantis-supported path to avoid per-cluster drift.

---

## Part 4: Route audit events through KOF to VictoriaLogs (≥30-day retention)

The webhook from Part 2 already targets the kof-collectors OTel Collector. KOF then routes logs to **VictoriaLogs** in the regional `kof-storage` chart — that's the canonical log store. No Loki, no Elasticsearch.

Patch the `kof-collectors` Helm values via the `MultiClusterService` KSM uses, adding an audit-specific pipeline that tags the events and forwards to VictoriaLogs plus (optionally) an external receiver:

```yaml
# values-patch for the kof-collectors MultiClusterService
opentelemetry-collector:
  config:
    receivers:
      otlp:
        protocols:
          http: { endpoint: 0.0.0.0:4318 }
    processors:
      attributes/audit:
        actions:
          - key: log.source
            value: k8s.audit
            action: insert
      batch/audit:
        timeout: 5s
        send_batch_size: 8192
    exporters:
      otlphttp/victorialogs:
        # vmauth fronts VictoriaLogs in kof-storage (Regional cluster)
        endpoint: https://vmauth.${REGIONAL_DOMAIN}/vls/insert/opentelemetry
        auth:
          authenticator: basicauth/victorialogs
      # Optional: also fan out externally via the exporter from Lab 5.17
      otlphttp/external:
        endpoint: ${env:EXTERNAL_OTLP_ENDPOINT}
        tls: { cert_file: /etc/otel/tls/tls.crt, key_file: /etc/otel/tls/tls.key, ca_file: /etc/otel/tls/ca.crt }
    extensions:
      basicauth/victorialogs:
        client_auth:
          username: ${env:VM_USER}
          password: ${env:VM_PASS}
    service:
      extensions: [basicauth/victorialogs]
      pipelines:
        logs/audit:
          receivers:  [otlp]
          processors: [memory_limiter, attributes/audit, batch/audit]
          exporters:  [otlphttp/victorialogs, otlphttp/dgxc]
```

VictoriaLogs retention is configured on the regional cluster via the kof-storage chart values. The relevant override sits under the VictoriaLogs sub-chart values:

```yaml
# kof-storage values override (regional cluster)
victoria-logs-single:
  server:
    retentionPeriod: 35d   # 30-day floor + headroom; storage usage scales linearly
```

For cold tier beyond 30 days: VictoriaLogs supports streaming to object storage via its own `vlbackup` workflow, or you can add a second OTel pipeline that writes to S3 directly with `awss3` exporter. Either gets you ≥7 years of cold archive when long-term retention is required.

---

## Part 5: Sample queries — what an audit will ask you to answer

VictoriaLogs uses **LogsQL** (not LogQL — different query language). The KOF docs cover how to reach the VictoriaLogs UI / API: port-forward `kof-storage-victoria-logs-cluster-vlselect` on the Regional cluster, or query via `vmauth` from outside the cluster.

```bash
# Port-forward (admin path)
KUBECONFIG=regional-kubeconfig kubectl port-forward -n kof svc/kof-storage-victoria-logs-cluster-vlselect 9471:9471
# Then UI at http://127.0.0.1:9471/select/vmui/  or HTTP API at /select/logsql/query

# Programmatic (vmauth fronted; credentials in storage-vmuser-credentials Secret)
VM_USER=$(kubectl -n kof get secret storage-vmuser-credentials -o jsonpath='{.data.username}' | base64 -d)
VM_PASS=$(kubectl -n kof get secret storage-vmuser-credentials -o jsonpath='{.data.password}' | base64 -d)
QUERY_URL="https://vmauth.${REGIONAL_DOMAIN}/vls/select/logsql/query"
```

These are the questions a security incident (or any operational investigation) will ask. Be able to answer all five within minutes.

**1. Who deleted `secret/tenant-a-prod` last Tuesday?**

```logsql
log.source:k8s.audit AND cluster:"tenant-a-gpu" AND objectRef.resource:secrets AND verb:delete AND objectRef.name:"tenant-a-prod"
```

**2. Which ServiceAccounts in `tenant-b` requested tokens in the last 24 h?**

```logsql
_time:24h AND log.source:k8s.audit AND objectRef.subresource:token AND objectRef.namespace:"tenant-b"
  | fields _time, objectRef.name, user.username
```

**3. List all RBAC changes across all clusters in the last 7 days.**

```logsql
_time:7d AND log.source:k8s.audit AND objectRef.apiGroup:"rbac.authorization.k8s.io" AND verb:(create OR update OR patch OR delete)
```

**4. Show every interactive pod exec into a GPU node.**

```logsql
log.source:k8s.audit AND objectRef.subresource:exec AND objectRef.name:~"gpu-node-.*"
  | fields _time, user.username, objectRef.namespace, objectRef.name
```

**5. Authentication failures (4xx from apiserver) in the last hour.**

```logsql
_time:1h AND log.source:k8s.audit AND responseStatus.code:[400 TO 499]
  | fields _time, user.username, responseStatus.code, responseStatus.message
```

Capture these as saved LogsQL queries in your runbook; they're the muscle memory you want before an incident.

> **LogsQL reference:** [VictoriaLogs LogsQL syntax](https://docs.victoriametrics.com/victorialogs/logsql/) (canonical upstream — Mirantis ships VictoriaLogs unmodified in KOF).

---

## Verification Checklist

- [ ] k0s apiserver running with `--audit-policy-file`, `--audit-log-path`, `--audit-webhook-config-file` flags
- [ ] `/var/log/k0s/audit.log` populating with expected event mix
- [ ] Webhook forwarding to the kof-collectors OTel Collector succeeds
- [ ] VictoriaLogs ingesting audit events with `log.source=k8s.audit` attribute
- [ ] VictoriaLogs `retentionPeriod` configured to ≥30 days in kof-storage values
- [ ] LogsQL query against a 30+ day-old event returns results (or you have a documented bootstrap date)
- [ ] All five sample queries from Part 5 succeed
- [ ] `ClusterDeployment` references a `ClusterTemplate` that ships the audit policy
- [ ] Secret/configmap audit captures Metadata only — no payloads visible in logs

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| apiserver fails to start after enabling audit | Policy file YAML invalid or path wrong | `kubectl apply --dry-run=server -f` policy in a manifest form first; check k0s logs |
| Audit log grows multiple GB/hour | Default policy too verbose, or `events`/`leases` not dropped | Add explicit `None` rules for noisy resources (see Part 1) |
| Webhook can't reach kof-collectors | mTLS cert SAN doesn't match service DNS or kof-collectors not yet rolled out by KSM | Re-issue cert with `kof-collectors-collector.kof.svc` SAN; check `MultiClusterService` reconcile status |
| Secret payloads visible in audit log | Policy uses RequestResponse on secrets | Demote to Metadata; rotate any exposed secrets |
| LogsQL query returns no data | Attribute name mismatch (`log.source` vs `_msg.log_source`) | Inspect a raw event: `_time:5m | head 1`; adjust the field path |
| KOF patch reverts after upgrade | Edited the OpenTelemetryCollector CR directly | Move the override into the `kof-collectors` `MultiClusterService` Helm values |

---

## Key Takeaways

- **Audit policy is design, not defaults.** The right policy captures the *security-relevant* events and drops the noise — that's a deliberate authoring exercise.
- **KOF VictoriaLogs is the canonical log store for k0rdent Enterprise.** No Loki, no Elasticsearch — those are not what Mirantis ships.
- **Never log secret payloads.** Metadata level is the rule; RequestResponse on secrets is a finding waiting to happen.
- **30 days is the floor, not the target.** Pick something with headroom (35 d hot, 7 years cold).
- **The deliverable is a documented audit policy + a saved LogsQL query that proves the retention guarantee.** Both are short; both are what an operator or auditor will read.

---

## Next Lab

[Week 2 — BMaaS](../../week-2-bmaas/) — control plane audit is in place; next, the physical layer.
