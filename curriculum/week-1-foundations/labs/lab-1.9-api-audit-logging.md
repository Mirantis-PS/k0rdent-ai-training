# Lab 1.9 — Kubernetes API Audit Logging

**Track:** Foundations / Production · **Tier:** Recommended · **Duration:** 1.5 hours

[Previous: Lab 1.8](lab-1.8-upgrade-k0rdent.md) · [Week 1](../README.md)

## Objective and prerequisites

Record API access without storing returned credentials, and find the events in
VictoriaLogs. Keep the management and managed clusters until this lab is complete.
Complete Lab 1.6's cross-cluster ingest path first. You need administrator access
to each control-plane host, working KOF **1.6.0**, and a successful backup/recovery
path before changing the API server. Record the live acceptance evidence below on your lab cluster.

## Part 1: Audit policy design

Use the committed [audit-policy.yaml](../../examples/telemetry/audit-policy.yaml).
Secrets and ConfigMaps are recorded at Metadata; RBAC changes include their bodies;
service-account token issuance is Metadata. `RequestResponse` on
`serviceaccounts/token` would include `responseObject.status.token`.
`omitManagedFields` is not token redaction. Policy rules are first-match-wins.

See [Kubernetes audit levels](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/).


### AWS controller access

An imported SSH key does not open port 22. CAPA also reconciles its security-group
rules, so a manual AWS rule may disappear. For this disposable lab, inspect the
AWSCluster and append a rule scoped to your current public IP. Run on management;
replace the example address before applying:

```bash
kubectl get awscluster managed-cluster-01 -n kcm-system -o yaml
kubectl explain awscluster.spec.network.additionalControlPlaneIngressRules --recursive
kubectl patch awscluster managed-cluster-01 -n kcm-system --type=json -p='[
  {"op":"add","path":"/spec/network/additionalControlPlaneIngressRules/-",
   "value":{"description":"Audit lab SSH","protocol":"tcp","fromPort":22,"toPort":22,
            "cidrBlocks":["203.0.113.10/32"]}}
]'
```

This appends to the pinned template's existing join-API rule. It is a temporary
provider-object change; Helm reconciliation can replace it. For persistent access,
configure the corresponding template or a supported bastion/SSM path. Use the
private key imported in Lab 1.5 and the AMI's SSH user (ec2-user for this AWS image).
Remove the added rule after host access is no longer needed.

## Part 2: Configure the control-plane host

Run from the repository checkout on each controller, or securely copy the policy there first. Inspect `sudo systemctl show k0scontroller --property=ExecStart` to find the active config path: the Terraform management host uses `/etc/k0s/k0s.yaml`, while the pinned AWS child uses `/etc/k0s.yaml`. Set `K0S_CONFIG` accordingly. Save the active configuration before editing. k0s runs the API server as an unprivileged user; root-only files prevent startup. The process uses its user ID with group root, so group-only read permission for the named account is insufficient.

```bash
K0S_CONFIG=/etc/k0s/k0s.yaml  # use /etc/k0s.yaml on the AWS child
sudo cp -p "$K0S_CONFIG" "$K0S_CONFIG.before-audit"
sudo install -d -m 0750 -o kube-apiserver -g kube-apiserver /var/log/kubernetes
sudo install -m 0600 -o kube-apiserver -g kube-apiserver \
  curriculum/examples/telemetry/audit-policy.yaml /etc/k0s/audit-policy.yaml
```

Merge these entries into the existing `spec.api.extraArgs` in the file identified by `$K0S_CONFIG`.
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
(`sudo /usr/local/bin/k0s config validate --config "$K0S_CONFIG"`) before restarting. Audit
Policy is a local API-server configuration format, not a Kubernetes resource:
`kubectl apply --dry-run=server` cannot validate that policy file. Check its YAML
and policy fields separately; API-server startup performs semantic validation.

```bash
sudo systemctl restart k0scontroller
kubectl get --raw=/readyz  # retry during startup; require ok before continuing
sudo journalctl -u k0scontroller --since '5 minutes ago' --no-pager
```

If startup fails, use the existing SSH session/console to restore
`$K0S_CONFIG.before-audit`, restart k0s, and inspect the reported invalid field.
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


### Ensure collectors cover controller nodes

KOF 1.6.0 defaults tolerate the old **node-role.kubernetes.io/master** taint.
The AWS child uses **node-role.kubernetes.io/control-plane**. Without an additional
toleration, its audit daemon and k0s component collector miss the controller even
though their DaemonSets report ready.

On the management host, preserve the existing CAPI Cluster values annotation
(including Lab 1.6's mTLS settings) and add this toleration:

```bash
kubectl -n kcm-system get cluster managed-cluster-01 -o json | jq -r \
  '.metadata.annotations["k0rdent.mirantis.com/kof-collectors-values"] // "{}"' > /tmp/kof-audit-values.yaml
python3 - <<'PY'
import yaml
p = '/tmp/kof-audit-values.yaml'
values = yaml.safe_load(open(p)) or {}
collectors = values.setdefault('opentelemetry-kube-stack', {}).setdefault('collectors', {})
for name in ['daemon', 'target-allocator', 'controller-k0s']:
    tolerations = collectors.setdefault(name, {}).setdefault('tolerations', [
        {'key': 'node-role.kubernetes.io/master', 'operator': 'Exists', 'effect': 'NoSchedule'}
    ])
    if not any(t.get('key') == 'node-role.kubernetes.io/control-plane' for t in tolerations):
        tolerations.append({
            'key': 'node-role.kubernetes.io/control-plane',
            'operator': 'Exists', 'effect': 'NoSchedule'
        })
with open(p, 'w') as f:
    yaml.safe_dump(values, f, sort_keys=False)
PY
kubectl -n kcm-system annotate cluster managed-cluster-01 \
  k0rdent.mirantis.com/kof-collectors-values="$(cat /tmp/kof-audit-values.yaml)" --overwrite
kubectl --kubeconfig=/tmp/managed-cluster-01.kubeconfig -n kof get pods -o wide
```

Wait for the annotation to reconcile, then verify an audit daemon on **each**
controller. A newly installed filelog receiver can start at the end of a file:
generate the acceptance probes after collection is ready.

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
