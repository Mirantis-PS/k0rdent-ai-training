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

```bash
# Backup etcd (from Lab 1.4)
# On the management cluster node:
k0s etcd backup /tmp/etcd-pre-upgrade-backup.tar.gz

# Export k0rdent resources
kubectl get management,credentials,clustertemplates,servicetemplates -n kcm-system -o yaml > /tmp/k0rdent-resources-backup.yaml

# If you have managed clusters, backup their definitions too
kubectl get clusterdeployments -A -o yaml > /tmp/clusterdeployments-backup.yaml
```

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
> - [ ] etcd backup completed successfully
> - [ ] Resource exports saved
> - [ ] Release notes reviewed (no blocking changes)

---

## Part 2: Perform the Upgrade

### Step 1: Run the Helm Upgrade

```bash
# Upgrade k0rdent Enterprise to v1.2.3
helm upgrade kcm oci://ghcr.io/k0rdent/kcm/charts/kcm \
  --version 1.2.3 \
  -n kcm-system \
  --wait \
  --timeout 10m

# Expected output:
# Release "kcm" has been upgraded. Happy Helming!
```

> **Note:** The `--wait` flag ensures Helm waits for all pods to become ready before reporting success. The `--timeout 10m` prevents hanging on slow rollouts.

### Step 2: Monitor the Rollout

```bash
# Watch pods restart with new version
kubectl get pods -n kcm-system -w

# Wait for all pods to reach Running state
# Controllers will restart one by one (rolling update)
# This typically takes 2-5 minutes

# Press Ctrl+C once all pods show Running and READY
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

If an upgrade fails or causes issues, you can roll back:

### Option A: Helm Rollback

```bash
# List Helm release history
helm history kcm -n kcm-system

# Roll back to previous revision
helm rollback kcm <PREVIOUS_REVISION> -n kcm-system --wait --timeout 10m

# Verify rollback
helm list -n kcm-system
kubectl get pods -n kcm-system
```

### Option B: etcd Restore (Last Resort)

If Helm rollback fails and CRDs are corrupted:

```bash
# Stop k0s
sudo k0s stop

# Restore etcd from backup
sudo k0s etcd restore /tmp/etcd-pre-upgrade-backup.tar.gz

# Start k0s
sudo k0s start

# Verify cluster is healthy
kubectl get nodes
kubectl get pods -n kcm-system
```

> **Warning:** etcd restore is destructive — it reverts ALL cluster state to the backup point, not just k0rdent. Only use as a last resort.

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

1. Why should you back up etcd before upgrading k0rdent?
2. What Helm flag ensures the upgrade waits for pods to be ready?
3. How would you roll back a failed upgrade?
4. What should you check after upgrading to confirm managed clusters are unaffected?
5. Why is reviewing release notes important before upgrading?

<details>
<summary><strong>Answer Key</strong> (click to expand)</summary>

1. etcd contains all Kubernetes state including k0rdent CRDs and configurations. A backup ensures you can restore to a known-good state if the upgrade corrupts data or fails catastrophically.
2. The `--wait` flag. Combined with `--timeout`, it ensures Helm doesn't report success until all pods are ready (or fails if they don't become ready in time).
3. Use `helm rollback kcm <PREVIOUS_REVISION> -n kcm-system --wait`. If that fails, restore from etcd backup as a last resort.
4. Check that ClusterDeployments still show Ready status, managed cluster nodes are Ready, and system pods on managed clusters are Running. The management cluster upgrade should not affect running workload clusters.
5. Release notes document breaking changes, deprecated features, new required permissions, and changed defaults. Skipping this step can lead to unexpected behavior or failed upgrades.

</details>

---

## Summary

In this lab, you:

- Assessed the current k0rdent Enterprise version and cluster health
- Created pre-upgrade backups (etcd + resource exports)
- Upgraded k0rdent Enterprise from v1.2.2 to v1.2.3 via Helm
- Verified the upgrade succeeded and existing resources were unaffected
- Learned the rollback procedure for failed upgrades
- Reviewed production upgrade best practices

---

## Next

Complete the [Week 1 Quiz](../week-1-quiz.md) to finish Week 1.
