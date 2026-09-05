# Lab 1.9 — Kubernetes API Audit Logging

**Track:** Foundations / Production · **Tier:** Recommended · **Duration:** 1.5 hours

[Previous: Lab 1.8](lab-1.8-upgrade-k0rdent.md) · [Week 1](../README.md)

## Objective and prerequisites

Record API access without storing returned credentials, and find the events in
VictoriaLogs. Keep the management and managed clusters until this lab is complete.
Complete Lab 1.6's cross-cluster ingest path first. You need administrator access
to each control-plane host, working KOF **1.6.0**, and a successful backup/recovery
path before changing the API server. This revision has static/chart verification;
record the live acceptance evidence below on your lab cluster.

## Part 1: Audit policy design

Use the committed [audit-policy.yaml](../../examples/telemetry/audit-policy.yaml).
Secrets and ConfigMaps are recorded at Metadata; RBAC changes include their bodies;
service-account token issuance is Metadata. `RequestResponse` on
`serviceaccounts/token` would include `responseObject.status.token`.
`omitManagedFields` is not token redaction. Policy rules are first-match-wins.

See [Kubernetes audit levels](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/).

## Part 2: Configure the control-plane host

Run from the repository checkout on each controller, or securely copy the policy
there first. Save the existing k0s configuration and create the log directory:

```bash
sudo cp -p /etc/k0s/k0s.yaml /etc/k0s/k0s.yaml.before-audit
sudo install -d -m 0750 /var/log/kubernetes
sudo install -m 0600 curriculum/examples/telemetry/audit-policy.yaml /etc/k0s/audit-policy.yaml
```

Merge these entries into the existing `spec.api.extraArgs` in `/etc/k0s/k0s.yaml`.
Preserve all other configuration. **Do not replace the full file with this excerpt.**

```yaml
spec:
  api:
    extraArgs:
      audit-policy-file: /etc/k0s/audit-policy.yaml
      audit-log-path: /var/log/kubernetes/audit.log
      audit-log-maxage: "30"
      audit-log-maxbackup: "10"
      audit-log-maxsize: "200"
```

No audit webhook is needed. KOF 1.6 already reads `/var/log/kubernetes/*.log` using
`filelog/k8s_audit`, mounts that host path into its daemon collector, persists the
read offset, and includes the receiver in its logs pipeline. Kubernetes audit
webhooks send `EventList`; they cannot send directly to an OTLP `/v1/logs` receiver.

Validate the k0s configuration with the installed k0s version's validation command
(`sudo k0s config validate --config /etc/k0s/k0s.yaml`) before restarting. Audit
Policy is a local API-server configuration format, not a Kubernetes resource:
`kubectl apply --dry-run=server` cannot validate that policy file. Check its YAML
and policy fields separately; API-server startup performs semantic validation.

```bash
sudo systemctl restart k0scontroller
kubectl get --raw=/readyz
sudo journalctl -u k0scontroller --since '5 minutes ago' --no-pager
```

If startup fails, use the existing SSH session/console to restore
`/etc/k0s/k0s.yaml.before-audit`, restart k0s, and inspect the reported invalid field.
On HA clusters change one controller at a time and recheck API readiness.

## Part 3: Managed clusters and replacement nodes

Apply the same policy/file path and API arguments on every managed-cluster
controller for this exercise. For replacement-node persistence, package the policy
file and API arguments in the **actual** bootstrap/control-plane resources rendered
by your pinned ClusterTemplate. Inspect those resources and their installed CRDs
before changing the chart. The stock template does not promise arbitrary
`spec.config.k0s.apiServerArgs` or `extraManifests` fields; a ConfigMap alone does
not create a host file. Publish the modified chart as a new immutable template and
validate replacement of one controller in a disposable cluster before fleet rollout.

## Part 4: Verify collection and configure retention

On the cluster that produced the event, inspect the installed KOF collector:

```bash
kubectl -n kof get opentelemetrycollector kof-collectors-daemon -o json | jq '
  {receiver: .spec.config.receivers["filelog/k8s_audit"],
   logs: .spec.config.service.pipelines.logs,
   mounts: .spec.volumeMounts}'
```

Confirm the audit path, receiver and logs exporter are present. Do not replace
KOF's pipelines or add a parallel collector. To extend forwarding externally, use
[Lab 5.17](../../week-5-ai-workloads/labs/lab-5.17-otel-telemetry-export.md).

On the **storage** cluster, retain the current Helm values and add the checked
[retention override](../../examples/telemetry/retention-values.yaml):

```bash
helm get values kof-storage -n kof -o yaml > /tmp/kof-storage-current.yaml
helm upgrade kof-storage oci://ghcr.io/k0rdent/kof/charts/kof-storage \
  --version 1.6.0 -n kof -f /tmp/kof-storage-current.yaml \
  -f curriculum/examples/telemetry/retention-values.yaml --wait --timeout 10m
kubectl -n kof get statefulsets -o json | jq '
  .items[] | select(.metadata.name | contains("vlstorage")) |
  .spec.template.spec.containers[].args'
```

Verify `retentionPeriod=35d` in the storage process arguments and provision capacity
for the observed ingest rate. Local max-age is a ceiling: size and backup-count
limits can rotate files sooner. It is not a guaranteed 30-day local retention floor.

## Part 5: Acceptance evidence

Use disposable names and query the **workload** cluster for the following events:

```bash
kubectl create serviceaccount audit-probe
kubectl create token audit-probe --duration=10m >/dev/null
kubectl create rolebinding audit-probe --clusterrole=view --user=audit-probe
sudo tail -n 50 /var/log/kubernetes/audit.log | jq -c '
  select(.objectRef.name == "audit-probe") |
  {auditID,level,verb,objectRef,responseStatus}'
# This must print zero. Do not print any token content to a terminal or CI log.
sudo cat /var/log/kubernetes/audit.log | jq -s '
  [.[] | select(.objectRef.resource == "serviceaccounts" and
                .objectRef.subresource == "token") |
   select(.responseObject.status.token != null)] | length'
```

Find the same audit IDs in Grafana's VictoriaLogs source. KOF's transform can flatten
fields: inspect one record before writing field-specific queries. For interactive
access, `objectRef.name` identifies the **pod**, not its node; correlate pod metadata
to find the node. Filter HTTP 401/403 for authentication/authorization investigation;
not every 4xx response is an authentication failure.

Acceptance requires a token issuance event at Metadata without a response body,
an RBAC event visible centrally, healthy exporters, confirmed retention arguments,
and a repeated probe after a collector restart. Record timestamps, cluster name,
chart version, and audit IDs; never include credentials in the evidence.

```bash
kubectl delete rolebinding audit-probe
kubectl delete serviceaccount audit-probe
```

## Cleanup and recovery

Keep audit logging enabled while continuing the course. If deliberately reverting,
restore the previous configuration and restart controllers one at a time. Retain
central audit data according to the environment's retention policy. Complete final
cluster teardown only after the acceptance evidence has been captured.
