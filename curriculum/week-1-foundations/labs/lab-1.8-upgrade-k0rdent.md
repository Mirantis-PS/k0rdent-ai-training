# Lab 1.8: Upgrade k0rdent Enterprise

**Duration:** 1.5 hours (active: ~45min, waiting for upgrade rollout: ~45min)
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Verify the current k0rdent Enterprise version and cluster health
- Perform a pre-upgrade backup of critical state
- Upgrade k0rdent Enterprise from v1.2.2 to v1.2.3 via Helm
- Verify the upgrade completed successfully
- Confirm existing ClusterDeployments and services are unaffected
- Document a rollback procedure

## Prerequisites

- Completed Labs 1.1-1.7
- Management cluster running with k0rdent Enterprise v1.2.2
- (Optional) Managed cluster from Lab 1.5 still running

## Resuming This Lab

If your SSH session dropped or you're returning the next day:

```bash
cd lab-infrastructure
./scripts/lab-connect.sh <your-engineer-id>
kubectl get nodes && kubectl get pods -n kcm-system
```

---

## Why Upgrades Matter

In production, k0rdent Enterprise receives regular updates with bug fixes, security patches, and new features. Engineers must be comfortable with the upgrade process because:

- **Security:** Patches address CVEs in controllers and dependencies
- **Compatibility:** New Kubernetes versions may require updated CAPI providers
- **Features:** New ClusterTemplate and ServiceTemplate versions ship with upgrades
- **Stability:** Bug fixes improve reconciliation reliability

> **Production Best Practice:** Always upgrade in a staging environment first. Use the N-1 strategy (stay one patch behind latest) to benefit from community testing.

---

## Part 1: Pre-Upgrade Assessment

### Step 1: Verify Current Version

```bash
# Check the installed k0rdent Helm release
helm list -n kcm-system

# Note the current chart version and app version
# Expected: kcm-<version> with APP VERSION 1.2.2

# Check the Management object
kubectl get management kcm -n kcm-system -o jsonpath='{.spec.release}' && echo

# Verify all controllers are healthy
kubectl get pods -n kcm-system
# All pods should be Running with READY x/x
```

### Step 2: Document Current State

Before upgrading, capture the current state for comparison:

```bash
# Save current CRD versions
kubectl get crds | grep k0rdent.mirantis.com > /tmp/pre-upgrade-crds.txt

# Save current cluster deployments status
kubectl get clusterdeployments -A -o wide > /tmp/pre-upgrade-clusters.txt

# Save current service templates
kubectl get servicetemplates -n kcm-system > /tmp/pre-upgrade-servicetemplates.txt

# Save current cluster templates
kubectl get clustertemplates -n kcm-system > /tmp/pre-upgrade-clustertemplates.txt

# Count current resources for post-upgrade comparison
echo "CRDs: $(kubectl get crds | grep k0rdent | wc -l)"
echo "ClusterTemplates: $(kubectl get clustertemplates -n kcm-system --no-headers | wc -l)"
echo "ServiceTemplates: $(kubectl get servicetemplates -n kcm-system --no-headers | wc -l)"
```

### Step 3: Pre-Upgrade Backup

Create an on-demand backup using the ManagementBackup CRD (configured in Lab 1.4):

```bash
# Trigger an on-demand backup before upgrading
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ManagementBackup
metadata:
  name: pre-upgrade-$(date +%Y%m%d)
spec:
  storageLocation: aws-s3
EOF

# Wait for backup to complete
kubectl get backup -n kcm-system --watch
# Wait until phase shows "Completed", then press Ctrl+C

# Verify the backup exists
kubectl get backup -n kcm-system | grep pre-upgrade
```

> **If you skipped Lab 1.4 backup setup:** You can still take a manual etcd snapshot as a fallback:
> ```bash
> sudo k0s etcd snapshot save /tmp/etcd-pre-upgrade.db
> ```

### Step 4: Review Release Notes

Before upgrading, always review the release notes for breaking changes:

```bash
# In a real scenario, you would check:
# https://docs.mirantis.com/k0rdent-enterprise/latest/release-notes/

# Key things to look for:
# - Breaking API changes (CRD field removals/renames)
# - Deprecated features
# - New required permissions
# - Changed default values
# - Provider version updates
```

> **Checkpoint:** Before proceeding, verify:
> - [ ] All pods in kcm-system are Running
> - [ ] ManagementBackup completed successfully
> - [ ] Pre-upgrade state documented
> - [ ] Release notes reviewed (no blocking changes)

---

## Part 2: Perform the Upgrade

### Step 1: Run the Helm Upgrade

```bash
# Upgrade k0rdent Enterprise to v1.2.3
helm upgrade kcm oci://registry.mirantis.com/k0rdent-enterprise/charts/k0rdent-enterprise \
  --version 1.2.3 \
  -n kcm-system \
  --timeout 15m
```

> **Note:** We intentionally omit `--wait` because the cert-manager startupapicheck post-install job can time out and cause Helm to report failure even though the upgrade succeeded. We verify readiness explicitly in the next steps instead.

### Step 2: Monitor the Rollout

```bash
# Verify cert-manager is healthy (may report Helm error due to startupapicheck)
kubectl wait --for=condition=Available deployment \
  -l app.kubernetes.io/instance=kcm,app.kubernetes.io/name=cert-manager \
  -n kcm-system --timeout=300s

# Watch pods restart with new version
kubectl get pods -n kcm-system -w
# Controllers will restart one by one (rolling update)
# This typically takes 2-5 minutes
# Press Ctrl+C once all pods show Running and READY

# Verify the KCM controller is ready
kubectl wait --for=condition=Available deployment \
  kcm-k0rdent-enterprise-controller-manager \
  -n kcm-system --timeout=300s
```

### Step 3: Verify Upgrade Success

```bash
# Confirm new version
helm list -n kcm-system
# APP VERSION should now show 1.2.3

# Verify Management object updated
kubectl get management kcm -n kcm-system -o jsonpath='{.spec.release}' && echo

# Check all controllers are healthy
kubectl get pods -n kcm-system
# All pods should be Running — no CrashLoopBackOff or Error states

# Verify CRDs were updated
kubectl get crds | grep k0rdent.mirantis.com > /tmp/post-upgrade-crds.txt
diff /tmp/pre-upgrade-crds.txt /tmp/post-upgrade-crds.txt
# Review any new or changed CRDs
```

---

## Part 3: Post-Upgrade Validation

### Step 1: Verify Existing Resources

```bash
# Check cluster deployments are still healthy
kubectl get clusterdeployments -A -o wide
# Status should still show Ready for all clusters

# Compare with pre-upgrade state
diff /tmp/pre-upgrade-clusters.txt <(kubectl get clusterdeployments -A -o wide)
# Differences should only be in AGE or minor status updates

# Check cluster templates — new versions may be available
kubectl get clustertemplates -n kcm-system
echo "ClusterTemplates before: $(cat /tmp/pre-upgrade-clustertemplates.txt | wc -l)"
echo "ClusterTemplates after: $(kubectl get clustertemplates -n kcm-system --no-headers | wc -l)"

# Check service templates — new versions may be available
kubectl get servicetemplates -n kcm-system
echo "ServiceTemplates before: $(cat /tmp/pre-upgrade-servicetemplates.txt | wc -l)"
echo "ServiceTemplates after: $(kubectl get servicetemplates -n kcm-system --no-headers | wc -l)"
```

### Step 2: Verify Managed Cluster Connectivity (if running)

If you still have the managed cluster from Lab 1.5:

```bash
# Get kubeconfig for managed cluster
kubectl get secret -n kcm-system managed-cluster-01-kubeconfig -o jsonpath='{.data.value}' | base64 -d > /tmp/managed-kubeconfig

# Test connectivity
kubectl --kubeconfig /tmp/managed-kubeconfig get nodes
# Nodes should be Ready

kubectl --kubeconfig /tmp/managed-kubeconfig get pods -A
# System pods should be Running
```

### Step 3: Verify KOF Stack (if deployed)

If you deployed KOF in Lab 1.6:

```bash
# Check KOF pods
kubectl get pods -n kof
# All should be Running

# Verify Grafana is accessible
kubectl get svc -n kof | grep grafana
```

---

## Part 4: Rollback Procedure (Reference)

If an upgrade fails or causes issues, you have three options in order of preference:

### Option A: Helm Rollback (First Response)

```bash
# List Helm release history
helm history kcm -n kcm-system

# Roll back to previous revision
helm rollback kcm <PREVIOUS_REVISION> -n kcm-system --timeout 10m

# Verify rollback
helm list -n kcm-system
kubectl get pods -n kcm-system
```

Helm rollback reverts the release and restarts controllers. This is fast and non-destructive.

### Option B: Velero Restore (If CRDs Are Corrupted)

If Helm rollback doesn't fix the issue (e.g., CRD schema changes broke resources):

```bash
# Disable admission webhooks to prevent conflicts during restore
kubectl patch managements kcm --type=merge \
  --patch='{"spec":{"core":{"kcm":{"config":{"admissionWebhook":{"enabled": false}}}}}}'
kubectl wait management kcm --for=condition=Ready=True --timeout=10m

# List available backups
kubectl get backup -n kcm-system

# Restore from the pre-upgrade backup
cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-pre-upgrade
  namespace: kcm-system
spec:
  backupName: pre-upgrade-$(date +%Y%m%d)
  existingResourcePolicy: update
  includedNamespaces:
  - '*'
EOF

# Wait for restore to complete
kubectl -n kcm-system wait restores.velero.io restore-pre-upgrade \
  --for=jsonpath='{.status.phase}'='Completed' --timeout=10m

# Re-enable admission webhooks
kubectl patch managements kcm --type=merge \
  --patch='{"spec":{"core":{"kcm":{"config":{"admissionWebhook":{"enabled": true}}}}}}'
```

### Option C: etcd Restore (Last Resort)

If both Helm rollback and Velero restore fail:

```bash
# Stop k0s
sudo k0s stop

# Restore etcd from snapshot (if you took one in Step 3)
sudo k0s etcd restore /tmp/etcd-pre-upgrade.db

# Start k0s
sudo k0s start

# Verify cluster is healthy
kubectl get nodes
kubectl get pods -n kcm-system
```

> **Warning:** etcd restore is destructive — it reverts ALL cluster state (not just k0rdent) to the backup point. Use only as a last resort.

---

## Production Upgrade Best Practices

| Practice | Description |
|----------|-------------|
| **Staging first** | Always test upgrades in a non-production environment |
| **Backup before upgrade** | etcd backup + resource exports (as done in Part 1) |
| **Review release notes** | Check for breaking changes and deprecations |
| **Monitor after upgrade** | Watch controller logs for errors for 30+ minutes |
| **Verify managed clusters** | Ensure all workload clusters remain healthy |
| **Document the process** | Record version, timestamp, any issues encountered |
| **Plan rollback** | Know the rollback steps before you start |
| **Maintenance window** | Schedule upgrades during low-activity periods |

---

## Troubleshooting

### Helm upgrade times out

```bash
# Check which pods are not ready
kubectl get pods -n kcm-system | grep -v Running

# Check events for failing pods
kubectl describe pod <pod-name> -n kcm-system

# Common cause: image pull failures (check registry access)
kubectl logs <pod-name> -n kcm-system
```

### CRD conflicts after upgrade

```bash
# Check if CRDs were updated
kubectl get crds | grep k0rdent

# If CRDs are stuck, they may need manual update
# (This is rare with Helm-managed upgrades)
kubectl describe crd clusterdeployments.k0rdent.mirantis.com | grep -A5 "Stored Versions"
```

### Managed clusters show degraded status

```bash
# Check if the provider controllers restarted correctly
kubectl get pods -n kcm-system | grep capa

# Check ClusterDeployment conditions
kubectl describe clusterdeployment <name> -n <namespace> | grep -A10 "Conditions"

# Usually resolves within a few minutes as controllers reconcile
```

---

## Knowledge Check

1. Why should you create a ManagementBackup before upgrading k0rdent?
2. Why do we omit the `--wait` flag from the Helm upgrade command?
3. What are the three rollback options, in order of preference?
4. What should you check after upgrading to confirm managed clusters are unaffected?
5. Why is reviewing release notes important before upgrading?

<details>
<summary><strong>Answer Key</strong> (click to expand)</summary>

1. ManagementBackup (via Velero) captures all k0rdent CRDs, CAPI resources, Flux sources, and secrets to S3. If the upgrade corrupts CRDs or breaks the management plane, you can restore to the exact pre-upgrade state — including reconnecting to managed clusters that kept running independently.
2. The cert-manager startupapicheck post-install job can exceed its backoff limit and cause Helm to report failure even though all pods are running fine. We verify readiness explicitly with `kubectl wait` instead.
3. (a) Helm rollback — fast, reverts the release; (b) Velero restore — restores CRDs and resources from backup; (c) etcd restore — last resort, reverts ALL cluster state.
4. Check that ClusterDeployments still show Ready status, managed cluster nodes are Ready, and system pods on managed clusters are Running. The management cluster upgrade should not affect running workload clusters.
5. Release notes document breaking changes, deprecated features, new required permissions, and changed defaults. Skipping this step can lead to unexpected behavior or failed upgrades.

</details>

---

## Summary

In this lab, you:

- Assessed the current k0rdent Enterprise version and cluster health
- Created a pre-upgrade ManagementBackup via Velero
- Upgraded k0rdent Enterprise from v1.2.2 to v1.2.3 via Helm (Enterprise registry)
- Verified the upgrade with explicit readiness checks (not `--wait`)
- Learned three rollback options: Helm rollback, Velero restore, etcd restore
- Reviewed production upgrade best practices

---

## Next

Complete the [Week 1 Quiz](../week-1-quiz.md) to finish Week 1.
