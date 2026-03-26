# Lab 1.8: Upgrade k0rdent Enterprise

**Duration:** 1.5 hours (active: ~45min, waiting for rollout: ~45min)
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Understand the three upgrade layers in k0rdent (management plane, managed clusters, services)
- Perform a pre-upgrade backup using ManagementBackup
- Upgrade k0rdent Enterprise via the Release CRD
- Upgrade a managed cluster's Kubernetes version via ClusterTemplateChain
- Verify all upgrades completed successfully
- Document rollback procedures for each layer

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

## Understanding k0rdent Upgrades

k0rdent has **three independent upgrade layers**. Each uses a different mechanism:

| Layer | What Changes | How to Upgrade | Controlled By |
|-------|-------------|----------------|---------------|
| **Management plane** | KCM controllers, CAPI providers, Flux, Sveltos | `Release` CRD → patch `Management` object | Platform admin |
| **Managed clusters** | Kubernetes version, node OS, cluster topology | Change `template` in `ClusterDeployment` | Platform admin / team lead |
| **Services** | Helm chart versions on managed clusters | Change `template` in service spec | Application team |

> **Key insight:** Upgrading the management plane does NOT automatically upgrade managed clusters or their services. Each layer is independent — managed clusters keep running even if the management plane is upgraded or temporarily down.

---

## Part 1: Pre-Upgrade Assessment

> **Important:** All commands in this lab run against the **management cluster**. If you previously set `KUBECONFIG` to a managed cluster's kubeconfig (e.g., in Lab 1.5), reset it first:
> ```bash
> export KUBECONFIG=/home/ubuntu/.kube/config
> ```

### Step 1: Verify Current Version

```bash
# Check the current Release
kubectl get releases.k0rdent.mirantis.com
# Expected: k0rdent-enterprise-1-2-2 (for Enterprise v1.2.2)
# Note: use the fully qualified name because "releases" conflicts with Flux HelmReleases

# Check the Management object's release reference
kubectl get management kcm -o jsonpath='{.spec.release}' && echo ""

# Verify all controllers are healthy
kubectl get pods -n kcm-system | grep -v Running
# No output = all pods are Running (good)
```

### Step 2: Document Current State

```bash
# Save current state for comparison
kubectl get crds | grep k0rdent.mirantis.com > /tmp/pre-upgrade-crds.txt
kubectl get clusterdeployments -A -o wide > /tmp/pre-upgrade-clusters.txt
kubectl get clustertemplates -n kcm-system > /tmp/pre-upgrade-clustertemplates.txt

# Count resources
echo "CRDs: $(kubectl get crds | grep k0rdent | wc -l)"
echo "ClusterTemplates: $(kubectl get clustertemplates -n kcm-system --no-headers | wc -l)"
echo "Releases: $(kubectl get releases.k0rdent.mirantis.com --no-headers | wc -l)"
```

### Step 3: Pre-Upgrade Backup

```bash
# Create an on-demand backup
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ManagementBackup
metadata:
  name: pre-upgrade-$(date +%Y%m%d)
spec:
  storageLocation: aws-s3
EOF

# Wait for completion
kubectl get backup -n kcm-system --watch
# Wait until phase shows "Completed", then Ctrl+C
```

> **If Velero isn't configured (skipped Lab 1.4 backup):** Take a manual etcd snapshot:
> ```bash
> sudo k0s etcd snapshot save /tmp/etcd-pre-upgrade.db
> ```

### Step 4: Review Release Notes

```bash
# Check what releases are available
kubectl get releases.k0rdent.mirantis.com

# In a real scenario, review release notes at:
# https://docs.k0rdent.io/latest/admin/upgrade/
#
# Key things to look for:
# - Breaking API changes (CRD field removals/renames)
# - New provider versions
# - Changed default values
# - Deprecated features
```

> **Checkpoint:** Before proceeding, verify:
> - [ ] All pods in kcm-system are Running
> - [ ] ManagementBackup completed (or etcd snapshot taken)
> - [ ] Pre-upgrade state documented
> - [ ] Release notes reviewed

---

## Part 2: Upgrade the Management Plane

k0rdent upgrades are **CRD-driven**. The process has three steps:
1. **Download** the new Release YAML from the k0rdent releases page
2. **Apply** it to create the Release object in your cluster
3. **Patch** the Management object to point to the new Release

The Release object is a manifest that pins the exact version of every component — KCM, CAPI, and all provider controllers. You don't write it manually; it's published as part of each k0rdent release.

### Step 1: View the Current Release

```bash
# See what release is currently active
kubectl get releases.k0rdent.mirantis.com
# Expected: k0rdent-enterprise-1-2-2 with READY=true

# Inspect the current release to see what it contains
kubectl get releases.k0rdent.mirantis.com k0rdent-enterprise-1-2-2 -o yaml
```

The Release object pins versions for every component:

```yaml
spec:
  version: 1.2.2                              # k0rdent version
  kcm:
    template: kcm-1-2-2                        # KCM controller template
  capi:
    template: cluster-api-1-0-7                # CAPI core template
  providers:
    - name: cluster-api-provider-aws
      template: cluster-api-provider-aws-1-0-9 # CAPA template
    - name: cluster-api-provider-k0sproject-k0smotron
      template: ...                            # k0smotron template
    # ... all other providers
```

### Step 2: Download and Apply the New Release

Each k0rdent version publishes a `release.yaml` file on the [k0rdent GitHub releases page](https://github.com/k0rdent/kcm/releases). This file contains the Release object with all provider versions pre-configured.

```bash
# Browse available versions at: https://github.com/k0rdent/kcm/releases
# Available versions include: v1.2.0, v1.3.0, v1.4.0, v1.5.0, etc.

# Set the target version
TARGET_VERSION="v1.3.0"

# Download and apply the new Release object
kubectl create -f "https://github.com/k0rdent/kcm/releases/download/${TARGET_VERSION}/release.yaml"

# Verify it was created
kubectl get releases.k0rdent.mirantis.com
# You should now see BOTH the old and new release:
#   k0rdent-enterprise-1-2-2   true    (current)
#   kcm-1-3-0                  false   (new, not yet active)
```

> **Enterprise vs OSS naming:** Your current release is `k0rdent-enterprise-1-2-2` (installed by the Enterprise Helm chart). The OSS release.yaml creates releases named `kcm-X-Y-Z`. Both work with the same Management object — the name is just a reference.

> **What just happened:** A new Release object now exists in your cluster, but it's not active yet. The Management object still points to the old release. Nothing has changed in the running system.

### Step 3: Understand the Release Contents

```bash
# Compare old vs new release to see what's changing
echo "=== Current release providers ==="
kubectl get releases.k0rdent.mirantis.com k0rdent-enterprise-1-2-2 \
  -o jsonpath='{range .spec.providers[*]}{.name}: {.template}{"\n"}{end}'

echo ""
echo "=== New release providers ==="
# Replace kcm-1-3-0 with your actual new release name
kubectl get releases.k0rdent.mirantis.com kcm-1-3-0 \
  -o jsonpath='{range .spec.providers[*]}{.name}: {.template}{"\n"}{end}'
```

This shows you exactly which provider versions will change. Review these against the [release notes](https://github.com/k0rdent/kcm/releases).

### Step 4: Trigger the Upgrade

Point the Management object to the new Release:

```bash
# Get the new release name (the one that's not the current active release)
RELEASE_NAME=$(kubectl get releases.k0rdent.mirantis.com --no-headers | grep -v "enterprise-1-2-2" | awk '{print $1}')
echo "Upgrading to: $RELEASE_NAME"

# Patch the Management object to trigger the upgrade
kubectl patch managements.k0rdent.mirantis.com kcm \
  --patch "{\"spec\":{\"release\":\"${RELEASE_NAME}\"}}" \
  --type=merge
```

> **What happens now:** The KCM controller detects the release change and begins reconciling — upgrading controllers, CAPI providers, and templates to match the new Release spec. This is a rolling update; components restart one by one.

### Step 5: Monitor the Upgrade

```bash
# Watch the Management object status
kubectl get management kcm --watch
# Wait for READY to become True (may take 5-10 minutes)

# In a second terminal, watch pods restart
kubectl get pods -n kcm-system -w
# Controllers restart one by one (rolling update)
# Press Ctrl+C once all pods show Running

# Verify the new Release is ready
kubectl wait --for=jsonpath='{.status.ready}=true' \
  releases.k0rdent.mirantis.com/${RELEASE_NAME} --timeout=600s

# Verify cert-manager is healthy
kubectl wait --for=condition=Available deployment \
  -l app.kubernetes.io/instance=kcm,app.kubernetes.io/name=cert-manager \
  -n kcm-system --timeout=300s

# Verify KCM controller is healthy
kubectl wait --for=condition=Available deployment \
  kcm-k0rdent-enterprise-controller-manager \
  -n kcm-system --timeout=300s
```

### Step 5: Verify Upgrade Success

```bash
# Confirm the Management object points to the new release
kubectl get management kcm -o jsonpath='{.spec.release}' && echo ""

# Check Management readiness
kubectl get management kcm
# READY should be True

# Verify all controllers are healthy
kubectl get pods -n kcm-system | grep -v Running
# No output = all pods Running

# Check for new ClusterTemplates (upgrades often ship new template versions)
kubectl get clustertemplates -n kcm-system
echo "Before: $(cat /tmp/pre-upgrade-clustertemplates.txt | wc -l) templates"
echo "After: $(kubectl get clustertemplates -n kcm-system --no-headers | wc -l) templates"

# Verify existing ClusterDeployments are unaffected
kubectl get clusterdeployments -A -o wide
```

---

## Part 3: Upgrade a Managed Cluster (Conceptual)

Upgrading a managed cluster's Kubernetes version is done by changing the `template` field in the ClusterDeployment. The `ClusterTemplateChain` controls which upgrade paths are allowed.

### Step 1: View Available Upgrade Paths

```bash
# List ClusterTemplateChains
kubectl get clustertemplatechains -n kcm-system

# View a chain's upgrade paths
kubectl get clustertemplatechain -n kcm-system -o yaml | grep -A 10 "supportedTemplates"
```

A chain defines which template versions can upgrade to which:

```yaml
# Example: aws-standalone-cp chain
spec:
  supportedTemplates:
    - name: aws-standalone-cp-1-0-20      # Current version
      availableUpgrades:
        - name: aws-standalone-cp-1-0-21   # Can upgrade to this
    - name: aws-standalone-cp-1-0-21       # Latest (no further upgrades)
```

### Step 2: Upgrade a ClusterDeployment (if you have one)

If you have a managed cluster from Lab 1.5 and a newer template is available:

```bash
# Check what template your cluster uses
kubectl get clusterdeployment managed-cluster-01 -n kcm-system \
  -o jsonpath='{.spec.template}' && echo ""

# Check if an upgrade is available in the chain
kubectl get clustertemplatechain -n kcm-system -o yaml | \
  grep -A 5 "$(kubectl get clusterdeployment managed-cluster-01 -n kcm-system -o jsonpath='{.spec.template}')"
```

To upgrade, change the template reference:

```bash
# Example: upgrade from 1-0-20 to 1-0-21
kubectl patch clusterdeployment managed-cluster-01 -n kcm-system \
  --patch '{"spec":{"template":"aws-standalone-cp-1-0-21"}}' \
  --type=merge
```

CAPI performs a **rolling update** — new nodes are created with the updated template, workloads are drained and migrated, old nodes are removed. This takes 10-20 minutes depending on cluster size.

```bash
# Monitor the upgrade
clusterctl describe cluster managed-cluster-01 -n kcm-system
```

> **Important:** The ClusterTemplateChain prevents invalid upgrade jumps. If you try to set a template that isn't listed in `availableUpgrades`, the ClusterDeployment will be rejected.

### Step 3: Upgrade Services on a Managed Cluster

Services deployed via ServiceTemplates follow the same pattern using `ServiceTemplateChain`:

```yaml
# Change the service template version in the ClusterDeployment
spec:
  serviceSpec:
    services:
      - template: kyverno-3-2-7          # Upgraded from kyverno-3-2-6
        templateChain: kyverno-chain      # Chain validates the upgrade path
        name: kyverno
        namespace: kyverno
```

> **Note:** Service upgrades are covered in detail in Week 2.

---

## Part 4: Rollback Procedures

### Layer 1: Management Plane Rollback

**Option A: Revert the Release** (preferred)

```bash
# Point Management back to the previous release
kubectl patch managements.k0rdent.mirantis.com kcm \
  --patch '{"spec":{"release":"<previous-release-name>"}}' \
  --type=merge

# Wait for rollback
kubectl get management kcm --watch
```

**Option B: Velero Restore** (if CRDs are corrupted)

```bash
# Disable webhooks to prevent conflicts
kubectl patch managements kcm --type=merge \
  --patch='{"spec":{"core":{"kcm":{"config":{"admissionWebhook":{"enabled": false}}}}}}'
kubectl wait management kcm --for=condition=Ready=True --timeout=10m

# Restore from pre-upgrade backup
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

kubectl -n kcm-system wait restores.velero.io restore-pre-upgrade \
  --for=jsonpath='{.status.phase}'='Completed' --timeout=10m

# Re-enable webhooks
kubectl patch managements kcm --type=merge \
  --patch='{"spec":{"core":{"kcm":{"config":{"admissionWebhook":{"enabled": true}}}}}}'
```

**Option C: etcd Restore** (last resort)

```bash
sudo k0s stop
sudo k0s etcd restore /tmp/etcd-pre-upgrade.db
sudo k0s start
```

> **Warning:** etcd restore reverts ALL cluster state, not just k0rdent.

### Layer 2: Managed Cluster Rollback

```bash
# Revert the ClusterDeployment to the previous template
kubectl patch clusterdeployment managed-cluster-01 -n kcm-system \
  --patch '{"spec":{"template":"aws-standalone-cp-1-0-20"}}' \
  --type=merge
```

CAPI performs another rolling update back to the original version.

---

## Production Upgrade Best Practices

| Practice | Description |
|----------|-------------|
| **Staging first** | Always test upgrades in a non-production environment |
| **Backup before upgrade** | ManagementBackup before management plane changes |
| **Review release notes** | Check for breaking changes and deprecations |
| **Upgrade management plane first** | Then templates, then managed clusters, then services |
| **One cluster at a time** | Don't upgrade all managed clusters simultaneously |
| **Monitor after upgrade** | Watch controller logs and ClusterDeployment status for 30+ minutes |
| **Verify managed clusters** | Ensure all workload clusters remain healthy |
| **Plan rollback** | Know which Release to revert to before you start |

---

## Troubleshooting

### Management object stuck in not-ready state

```bash
# Check Management conditions
kubectl get management kcm -o jsonpath='{range .status.conditions[*]}{.type}: {.status} - {.message}{"\n"}{end}'

# Check controller logs
kubectl logs -n kcm-system deployment/kcm-k0rdent-enterprise-controller-manager --tail=50
```

### Provider controllers not upgrading

```bash
# Check if the Release has the correct provider templates
kubectl get release.k0rdent.mirantis.com <release-name> -o yaml | grep -A 2 "providers"

# Check individual provider deployments
kubectl get deployments -n kcm-system | grep -E "capa|capz|capv|capo"
```

### Managed cluster upgrade stuck

```bash
# Check the ClusterDeployment status
kubectl describe clusterdeployment <name> -n <namespace> | grep -A 10 "Conditions"

# Check if the template chain allows the upgrade
kubectl get clustertemplatechain -n kcm-system -o yaml | grep -B 2 -A 5 "<template-name>"

# Monitor CAPI machine rollout
clusterctl describe cluster <name> -n <namespace>
```

---

## Knowledge Check

1. What is the difference between upgrading the management plane and upgrading a managed cluster?
2. How does the `Release` CRD drive the management plane upgrade?
3. What role does `ClusterTemplateChain` play in managed cluster upgrades?
4. Why do we create a ManagementBackup before upgrading?
5. What are the three rollback options for the management plane, in order of preference?

<details>
<summary><strong>Answer Key</strong> (click to expand)</summary>

1. The management plane upgrade updates KCM controllers, CAPI providers, and supporting infrastructure (via `Release` + `Management` patch). Managed cluster upgrades change the Kubernetes version and node configuration on workload clusters (via `ClusterDeployment` template change). They are independent — upgrading the management plane does NOT upgrade managed clusters.
2. The `Release` CRD defines the target k0rdent version and all provider template versions. When you patch the `Management` object's `.spec.release` to point to a new Release, the KCM controller reconciles the difference — upgrading controllers, CAPI providers, and templates to match the Release spec.
3. `ClusterTemplateChain` defines allowed upgrade paths between ClusterTemplate versions (e.g., `1-0-20` can upgrade to `1-0-21` but not to `1-0-25`). This prevents invalid version jumps and ensures managed clusters follow validated upgrade paths. If you try to set a template not in the chain's `availableUpgrades`, the change is rejected.
4. ManagementBackup (via Velero) captures all k0rdent CRDs, CAPI resources, and secrets to S3. If the upgrade corrupts the management plane, you can restore to the exact pre-upgrade state and reconnect to managed clusters that kept running independently.
5. (a) Revert the `Management` object to the previous Release — fastest, just changes the desired state; (b) Velero restore — restores CRDs and resources from the S3 backup; (c) etcd restore — last resort, reverts ALL cluster state.

</details>

---

## Summary

In this lab, you:

- Understood the three upgrade layers: management plane, managed clusters, services
- Created a pre-upgrade ManagementBackup
- Learned how to upgrade k0rdent Enterprise via the `Release` CRD and `Management` patch
- Understood managed cluster upgrades via `ClusterTemplateChain` and template changes
- Learned rollback procedures for each layer
- Reviewed production upgrade best practices

---

## Next

Complete the [Week 1 Quiz](../week-1-quiz.md) to finish Week 1.
