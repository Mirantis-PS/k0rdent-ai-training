# Draft — upstream issue for k0rdent/kcm

Status: **not yet filed** (needs k0rdent org SSO; file manually at
https://github.com/k0rdent/kcm/issues/new when ready, then replace this note
with the issue link).

---

**Title:** `aws-standalone-cp`: expose `AWSCluster` CNI ingress rules (`spec.network.cni.cniIngressRules`) as a chart value

## Summary

The `aws-standalone-cp` cluster template supports bringing a custom CNI via
`k0s.network.provider: custom` (values passthrough added in chart `1-0-14`),
but the chart's `awscluster.yaml` hardcodes the `spec.network` block. CAPA's
default CNI security-group ingress rules are Calico-oriented (TCP 179 BGP +
protocol 4 IP-in-IP), so any overlay CNI that isn't Calico — e.g. Cilium with
geneve (UDP 6081) or VXLAN (UDP 8472) — has its cross-node pod traffic
silently dropped by the node/control-plane security groups.

The failure mode is nasty to diagnose: nodes go `Ready`, same-node traffic
works, and only cross-node flows (e.g. pod → CoreDNS on the other node)
blackhole.

## What works today (workaround)

Patching the generated `AWSCluster` directly is honored and reconciled by
CAPA into both security groups (replacing the Calico defaults):

```bash
kubectl patch awscluster <cluster> -n kcm-system --type=merge -p '{
  "spec": {"network": {"cni": {"cniIngressRules": [
    {"description": "cilium geneve", "protocol": "udp", "fromPort": 6081, "toPort": 6081},
    {"description": "cilium health", "protocol": "tcp", "fromPort": 4240, "toPort": 4240},
    {"description": "cilium health ICMP", "protocol": "icmp", "fromPort": 8, "toPort": 0}
  ]}}}
}'
```

…but it lives outside the `ClusterDeployment`, so it isn't declarative,
templated, or preserved by GitOps flows around the ClusterDeployment.

## Proposal

Add a values passthrough in `templates/cluster/aws-standalone-cp` (and
`aws-hosted-cp`) mirroring the existing `k0s.network` passthrough, e.g.:

```yaml
# values.yaml
network:
  cniIngressRules: []  # @schema description: CNI ingress rules applied to node/CP security groups; item: object
```

rendered into `awscluster.yaml`'s existing `spec.network` block. This would
make the k0rdent catalog's own Cilium example (which uses `tunnelProtocol:
geneve` on AWS) work cross-node out of the box.

## Environment

- k0rdent Enterprise 1.3.2, `aws-standalone-cp-1-0-26` (also verified absent
  on community `main`, chart 1.0.37)
- CAPA v2.x, Cilium 1.19.0 via catalog ServiceTemplate
- Found during live validation of a training lab, 2026-07-03

---

Optional secondary report (k0rdent/catalog): the Cilium app's AWS example
(`apps/cilium/aws-cld.yaml` + `mcs.yaml`, geneve tunnel) presumably hits the
same cross-node drop; consider adding the `cniIngressRules` workaround to the
app docs until kcm exposes the value.
