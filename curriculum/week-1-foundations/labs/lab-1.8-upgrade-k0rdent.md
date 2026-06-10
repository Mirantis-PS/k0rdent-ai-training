# Lab 1.8: Upgrade k0rdent Enterprise

**Duration:** 1.5 hours (active: ~45min, waiting on upgrade rollout + end-of-week teardown: ~45min)
**Type:** Hands-on Lab

## Table of Contents

- [Objectives](#objectives)
- [Prerequisites](#prerequisites)
- [Resuming This Lab](#resuming-this-lab)
- [Understanding k0rdent Upgrades](#understanding-k0rdent-upgrades)
- [Part 1: Pre-Upgrade Assessment (~15 min)](#part-1-pre-upgrade-assessment-15-min)
  - [Step 1: Verify Current Version](#step-1-verify-current-version)
  - [Step 2: Document Current State](#step-2-document-current-state)
  - [Step 3: Pre-Upgrade Backup](#step-3-pre-upgrade-backup)
  - [Step 4: Review Release Notes](#step-4-review-release-notes)
- [Part 2: Upgrade the Management Plane (~20 min active, ~30 min waiting)](#part-2-upgrade-the-management-plane-20-min-active-30-min-waiting)
  - [Step 1: View the Current Release](#step-1-view-the-current-release)
  - [Step 2: Apply the New Release](#step-2-apply-the-new-release)
  - [Step 3: Wait for the New Release to Become Ready](#step-3-wait-for-the-new-release-to-become-ready)
  - [Step 4: Compare Provider Versions](#step-4-compare-provider-versions)
  - [Step 5: Activate the Upgrade](#step-5-activate-the-upgrade)
  - [Step 6: Monitor the Upgrade](#step-6-monitor-the-upgrade)
  - [Step 7: Verify Upgrade Success](#step-7-verify-upgrade-success)
- [Part 3: Managed Cluster Upgrades (~15 min)](#part-3-managed-cluster-upgrades-15-min)
  - [Step 1: Check for New Templates](#step-1-check-for-new-templates)
  - [Step 2: Check Upgrade Paths](#step-2-check-upgrade-paths)
  - [Step 3: The Upgrade Pattern (Walkthrough)](#step-3-the-upgrade-pattern-walkthrough)
  - [Step 4: What the Rolling Update Looks Like](#step-4-what-the-rolling-update-looks-like)
  - [Step 5: Upgrade Services on a Managed Cluster](#step-5-upgrade-services-on-a-managed-cluster)
- [Part 4: Rollback Procedures (~5 min)](#part-4-rollback-procedures-5-min)
  - [Layer 1: Management Plane Rollback](#layer-1-management-plane-rollback)
  - [Layer 2: Managed Cluster Rollback](#layer-2-managed-cluster-rollback)
- [Production Upgrade Best Practices](#production-upgrade-best-practices)
- [Troubleshooting](#troubleshooting)
  - [Management object stuck in not-ready state](#management-object-stuck-in-not-ready-state)
  - [Provider controllers not upgrading](#provider-controllers-not-upgrading)
  - [Managed cluster upgrade stuck](#managed-cluster-upgrade-stuck)
- [Knowledge Check](#knowledge-check)
- [Summary](#summary)
- [End of Week 1: Tear Down Managed Clusters](#end-of-week-1-tear-down-managed-clusters)
- [Preserving Your Environment](#preserving-your-environment)
- [Week 1 Complete!](#week-1-complete)
- [Next](#next)

## Objectives

In this lab, you will:
- Understand the three upgrade layers in k0rdent (management plane, managed clusters, services)
- Perform a pre-upgrade backup using ManagementBackup
- Upgrade k0rdent Enterprise via the Release CRD
- Understand the managed-cluster upgrade flow and verify available upgrade paths via ClusterTemplateChain
- Verify the management plane upgrade completed successfully
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

# On the management node: re-export the lab environment variables
source /opt/k0rdent-lab/config/lab-info.env
kubectl get nodes && kubectl get pods -n kcm-system
```

> **If you use AWS SSO:** Session credentials expire daily — refresh them before reconnecting. On your **local machine**, run `aws sso login --profile <your-profile>`, then `./scripts/lab-refresh-creds.sh <your-engineer-id>` (from `lab-infrastructure/`). The teardown section at the end of this lab makes AWS calls — if you see `ExpiredTokenException`, re-run these refresh steps.

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

## Part 1: Pre-Upgrade Assessment (~15 min)

> **Important:** All commands in this lab run against the **management cluster**. If you previously set `KUBECONFIG` to a managed cluster's kubeconfig (e.g., in Lab 1.5), reset it first:
> ```bash
> export KUBECONFIG=/home/ubuntu/.kube/config
> ```

### Step 1: Verify Current Version

```bash
# Check the current Release
kubectl get releases.k0rdent.mirantis.com
# Expected: k0rdent-enterprise-1-2-2 (for Enterprise v1.2.2)
# Note: use the fully qualified resource name to avoid short-name ambiguity

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

> **If Velero isn't configured (skipped Lab 1.4 backup):** Stop here and configure backup storage first. In this single-node training lab, you may also take a manual k0s backup (which captures etcd state and k0s configuration) as an extra platform safeguard, but that is outside the standard k0rdent management-backup workflow:
> ```bash
> sudo k0s backup --save-path=/tmp
> # Produces /tmp/k0s_backup_<timestamp>.tar.gz — note the exact filename,
> # you'll need it for the Part 4 rollback procedure
> ```

### Step 4: Review Release Notes

```bash
# Check what releases are available
kubectl get releases.k0rdent.mirantis.com

# In a real scenario, review release notes and upgrade notes at:
# https://docs.mirantis.com/k0rdent-enterprise/latest/admin/upgrade/
#
# Key things to look for:
# - Breaking API changes (CRD field removals/renames)
# - New provider versions
# - Changed default values
# - Deprecated features
```

> **Checkpoint:** Before proceeding, verify:
> - [ ] All pods in kcm-system are Running
> - [ ] ManagementBackup completed successfully
> - [ ] Pre-upgrade state documented
> - [ ] Release notes reviewed

---

## Part 2: Upgrade the Management Plane (~20 min active, ~30 min waiting)

k0rdent Enterprise upgrades are **CRD-driven** — you apply a new `Release` object, then patch the `Management` object to point to it. The KCM controller handles the rest.

The process has three steps:
1. **Apply** the new Release YAML (published by Mirantis for each version)
2. **Patch** the Management object to activate the new Release
3. **Verify** the upgrade completed

> **Prerequisite:** You must have the `Global Admin` role to perform upgrades.

### Step 1: View the Current Release

```bash
# See what release is currently active
kubectl get releases.k0rdent.mirantis.com
# Expected: k0rdent-enterprise-1-2-2 with READY=true

# Inspect what it pins
kubectl get releases.k0rdent.mirantis.com k0rdent-enterprise-1-2-2 \
  -o jsonpath='{range .spec.providers[*]}{.name}: {.template}{"\n"}{end}'
```

The Release pins versions for every component:

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

### Step 2: Apply the New Release

Each Enterprise version publishes a `release.yaml` at `get.mirantis.com`. This file creates the new Release object with all correct provider template versions:

```bash
# Set the target version
TARGET_VERSION="1.2.3"

# Download and apply the new Release object
kubectl create -f "https://get.mirantis.com/k0rdent-enterprise/${TARGET_VERSION}/release.yaml"
```

```bash
# Verify it was created
kubectl get releases.k0rdent.mirantis.com
# You should see BOTH releases:
#   k0rdent-enterprise-1-2-2   true    (current)
#   k0rdent-enterprise-1-2-3   false   (new, not yet active)
```

> **What just happened:** A new Release object exists in your cluster, but it's not active yet. The Management object still points to the old release. Nothing has changed in the running system.

### Step 3: Wait for the New Release to Become Ready

The Release needs all its templates to be fetched and validated before it can be activated:

```bash
# Wait for the new release to be ready
kubectl wait --for=jsonpath='{.status.ready}=true' \
  releases.k0rdent.mirantis.com/k0rdent-enterprise-${TARGET_VERSION//./-} \
  --timeout=600s
```

> **If the Release stays not-ready:** Check its conditions:
> ```bash
> kubectl get releases.k0rdent.mirantis.com k0rdent-enterprise-${TARGET_VERSION//./-} -o yaml | grep -A 5 conditions
> ```

### Step 4: Compare Provider Versions

Before activating, review what will change:

```bash
echo "=== Current providers ==="
kubectl get releases.k0rdent.mirantis.com k0rdent-enterprise-1-2-2 \
  -o jsonpath='{range .spec.providers[*]}{.name}: {.template}{"\n"}{end}'

echo ""
echo "=== New providers ==="
kubectl get releases.k0rdent.mirantis.com k0rdent-enterprise-1-2-3 \
  -o jsonpath='{range .spec.providers[*]}{.name}: {.template}{"\n"}{end}'
```

### Step 5: Activate the Upgrade

Patch the Management object to point to the new Release:

```bash
RELEASE_NAME="k0rdent-enterprise-1-2-3"

kubectl patch managements.k0rdent.mirantis.com kcm \
  --patch "{\"spec\":{\"release\":\"${RELEASE_NAME}\"}}" \
  --type=merge
```

> **What happens now:** The KCM controller detects the release change and begins reconciling — upgrading controllers, CAPI providers, and templates to match the new Release spec. Components restart one by one (rolling update).

### Step 6: Monitor the Upgrade

```bash
# Watch the Management object status
kubectl get management kcm --watch
# Wait for READY to become True (may take 5-10 minutes)

# In a second terminal, watch pods restart
kubectl get pods -n kcm-system -w
# Controllers restart one by one (rolling update)
# Press Ctrl+C once all pods show Running

# Verify cert-manager is healthy
kubectl wait --for=condition=Available deployment \
  -l app.kubernetes.io/instance=kcm,app.kubernetes.io/name=cert-manager \
  -n kcm-system --timeout=300s

# Verify KCM controller is healthy
kubectl wait --for=condition=Available deployment \
  kcm-k0rdent-enterprise-controller-manager \
  -n kcm-system --timeout=300s
```

### Step 7: Verify Upgrade Success

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

## Part 3: Managed Cluster Upgrades (~15 min)

Upgrading a managed cluster's Kubernetes version is done by changing the `template` field in the ClusterDeployment. The `ClusterTemplateChain` CRD controls which upgrade paths are allowed.

> **Heads up — nothing to upgrade on this path:** The 1.2.2 → 1.2.3 upgrade you just performed is a **patch release**. It ships no new `aws-standalone-cp` ClusterTemplate version, so there is genuinely no managed-cluster upgrade to perform in this environment. That's the realistic outcome of a patch upgrade. Steps 1-2 below are **real discovery steps** — run them and confirm there's no upgrade target. Steps 3-4 are a **pattern walkthrough** of exactly what you'd do when a new template version IS available (typically after a minor release like 1.2.x → 1.3.x).

### Step 1: Check for New Templates

After upgrading the management plane (Part 2), check if new ClusterTemplate versions were shipped:

```bash
# List all AWS standalone templates
kubectl get clustertemplates -n kcm-system | grep aws-standalone

# Compare with what your cluster currently uses
kubectl get clusterdeployment -n kcm-system \
  -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.template}{"\n"}{end}'
```

> **Expected result here:** a single `aws-standalone-cp` version — the same one your cluster already uses. **Patch releases (e.g., 1.2.2 → 1.2.3)** don't ship new templates; **minor releases (e.g., 1.2.x → 1.3.x)** typically do. Seeing only one version is the correct outcome for this lab, not an error.

### Step 2: Check Upgrade Paths

```bash
# List ClusterTemplateChains
kubectl get clustertemplatechains -n kcm-system

# If chains exist, view the allowed upgrade paths
kubectl get clustertemplatechains -n kcm-system -o yaml | grep -A 5 "supportedTemplates"
```

A `ClusterTemplateChain` defines which template version can upgrade to which:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ClusterTemplateChain
metadata:
  name: aws-standalone-cp
  namespace: kcm-system
spec:
  supportedTemplates:
    - name: aws-standalone-cp-1-0-20      # Current version
      availableUpgrades:
        - name: aws-standalone-cp-1-0-26   # Allowed upgrade target
    - name: aws-standalone-cp-1-0-26       # Latest (no further upgrades)
```

> **If no chains exist:** You can still upgrade by patching the template directly. Chains are guardrails, not requirements. Without a chain, k0rdent won't validate the upgrade path — you're responsible for ensuring compatibility.

### Step 3: The Upgrade Pattern (Walkthrough)

> **Pattern walkthrough — do not run this against your cluster.** There is no new template version in this environment (see the note at the top of Part 3), so the patch below has no valid value to substitute. When a new template version IS available — after a minor-release management plane upgrade — this is the exact procedure you'd follow:

```bash
# Check current template
CLUSTER_NAME="<your-cluster-name>"  # e.g., managed-cluster-01
CURRENT=$(kubectl get clusterdeployment $CLUSTER_NAME -n kcm-system \
  -o jsonpath='{.spec.template}')
echo "Current template: $CURRENT"

# List available templates to find the upgrade target
kubectl get clustertemplates -n kcm-system | grep aws-standalone

# Upgrade to the new template — the entire upgrade is this one patch
NEW_TEMPLATE="<new-template-name>"  # e.g., aws-standalone-cp-1-0-26 after a minor release
kubectl patch clusterdeployment $CLUSTER_NAME -n kcm-system \
  --patch "{\"spec\":{\"template\":\"$NEW_TEMPLATE\"}}" \
  --type=merge
```

### Step 4: What the Rolling Update Looks Like

After that patch, CAPI performs a **rolling update** — new nodes are created with the updated template, workloads are drained and migrated, old nodes are removed. These are the commands you'd use to monitor it:

```bash
# Watch the rolling update progress
clusterctl describe cluster $CLUSTER_NAME -n kcm-system

# Watch machines being replaced
kubectl get machines -n kcm-system -w

# Check ClusterDeployment status
kubectl get clusterdeployment $CLUSTER_NAME -n kcm-system
```

**Expected duration:** 10-20 minutes depending on cluster size. You'd see:
1. New control plane machine created alongside the old one
2. New worker machine(s) created
3. Workloads drained from old nodes
4. Old machines deleted

```bash
# Once complete, verify the managed cluster is healthy
kubectl get secret ${CLUSTER_NAME}-kubeconfig -n kcm-system \
  -o jsonpath='{.data.value}' | base64 -d > /tmp/managed.kubeconfig
kubectl --kubeconfig=/tmp/managed.kubeconfig get nodes
# Nodes would show the new Kubernetes version

# Return to management cluster
export KUBECONFIG=/home/ubuntu/.kube/config
```

> **Safety guardrail:** If a ClusterTemplateChain exists, it prevents invalid version jumps. Setting a template not listed in `availableUpgrades` will be rejected.

### Step 5: Upgrade Services on a Managed Cluster

Services deployed via MultiClusterService or ClusterDeployment can be upgraded by changing the template reference. The `ServiceTemplateChain` controls allowed upgrade paths.

```bash
# Check available service upgrade paths on a ClusterDeployment
kubectl get clusterdeployment $CLUSTER_NAME -n kcm-system \
  -o jsonpath='{.status.servicesUpgradePaths}' | python3 -m json.tool 2>/dev/null
```

To upgrade a service, update the template in the MultiClusterService or ClusterDeployment:

```yaml
# In MultiClusterService or ClusterDeployment serviceSpec
serviceSpec:
  services:
    - template: kyverno-3-2-7          # New version
      templateChain: kyverno-chain      # Validates the upgrade path
      name: kyverno
      namespace: kyverno
```

The `ServiceTemplateChain` works identically to ClusterTemplateChain:

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ServiceTemplateChain
metadata:
  name: kyverno-chain
  namespace: kcm-system
spec:
  supportedTemplates:
    - name: kyverno-3-2-6
      availableUpgrades:
        - name: kyverno-3-2-7
    - name: kyverno-3-2-7
```

> **Note:** Service upgrades and template chains are covered in detail in Week 2.

---

## Part 4: Rollback Procedures (~5 min)

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

**Option B: Velero Restore** (documented rollback path if a release revert is not enough)

```bash
# Restore from a clean k0rdent installation and patch the Management
# object back to the pre-upgrade release during restore.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: patch-mgmt-spec-release
  namespace: kcm-system
data:
  patch-mgmt-spec-release: |
    version: v1
    resourceModifierRules:
    - conditions:
        groupResource: managements.k0rdent.mirantis.com
      patches:
      - operation: replace
        path: "/spec/release"
        value: "<version-before-upgrade>"
---
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-pre-upgrade
  namespace: kcm-system
spec:
  backupName: <pre-upgrade-backup-name>
  existingResourcePolicy: update
  includedNamespaces:
  - '*'
  resourceModifier:
    kind: ConfigMap
    name: patch-mgmt-spec-release
EOF

kubectl -n kcm-system wait restores.velero.io restore-pre-upgrade \
  --for=jsonpath='{.status.phase}'='Completed' --timeout=10m
```

**Option C: k0s Restore** (single-node lab / platform-level last resort)

```bash
sudo k0s stop
# Use the actual filename produced by `k0s backup` in Part 1 Step 3
sudo k0s restore /tmp/k0s_backup_<timestamp>.tar.gz
sudo k0s start
```

> **Warning:** A k0s restore reverts ALL cluster state (etcd included), not just k0rdent, takes the single-node management plane offline while it runs, and is not the primary rollback workflow described in the k0rdent docs.

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
kubectl get releases.k0rdent.mirantis.com <release-name> -o yaml | grep -A 2 "providers"

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
2. The `Release` CRD defines the target k0rdent version and all provider template versions. For Enterprise, you download the Release YAML from `get.mirantis.com` and apply it with `kubectl create`. Then you patch the Management object's `.spec.release` to point to the new Release. The KCM controller reconciles the difference -- upgrading controllers, CAPI providers, and templates to match the new Release spec.
3. `ClusterTemplateChain` defines allowed upgrade paths between ClusterTemplate versions (e.g., `1-0-20` can upgrade to `1-0-21` but not to `1-0-25`). This prevents invalid version jumps and ensures managed clusters follow validated upgrade paths. If you try to set a template not in the chain's `availableUpgrades`, the change is rejected.
4. ManagementBackup (via Velero) captures all k0rdent CRDs, CAPI resources, and secrets to S3. If the upgrade corrupts the management plane, you can restore to the exact pre-upgrade state and reconnect to managed clusters that kept running independently.
5. (a) Revert the `Management` object to the previous Release — fastest, just changes the desired state; (b) Velero restore — restores CRDs and resources from the S3 backup; (c) k0s restore from a `k0s backup` archive — last resort, reverts ALL cluster state.

</details>

---

## Summary

In this lab, you:

- Understood the three upgrade layers: management plane, managed clusters, services
- Created a pre-upgrade ManagementBackup
- Learned how to upgrade k0rdent Enterprise via the `Release` CRD (from `get.mirantis.com`) and `Management` patch
- Verified available managed-cluster upgrade paths and walked through the upgrade pattern (`ClusterTemplateChain` + template change) — confirming that a patch release ships no new template version to upgrade to
- Learned rollback procedures for each layer
- Reviewed production upgrade best practices

---

## End of Week 1: Tear Down Managed Clusters

Week 1 is done with the managed clusters — delete them now, **before** disconnecting.

> **Why this matters:** Every managed cluster runs in its **own VPC** that CAPA created — EC2 instances, a NAT gateway, a load balancer, and EBS volumes. `lab-destroy.sh` only knows about the Terraform-managed management VPC; it **cannot see or delete** managed-cluster resources. A forgotten managed cluster bills indefinitely and can cost more than the entire quoted week.

### Step 0: Delete the Lab 1.7 MultiClusterServices First

The ingress-nginx LoadBalancer service from Lab 1.7 created a Classic ELB on the managed cluster via the cloud controller manager. Delete the services first so CCM removes its load balancer — deleting the ClusterDeployment alone can orphan it:

```bash
# Make sure you're on the management cluster
export KUBECONFIG=/home/ubuntu/.kube/config

# Delete the MultiClusterServices from Lab 1.7
# (your baseline-services may be the kyverno-only variant from Lab 1.7 Part 8 — delete it either way)
kubectl delete multiclusterservice ingress-services baseline-services

# Wait ~2 minutes for CCM to remove the ingress load balancer before proceeding
```

### Step 1: Delete the ClusterDeployments

```bash
# Delete all managed clusters (managed-cluster-01 and the optional Azure cluster, if created)
kubectl delete clusterdeployment --all -n kcm-system

# Watch until the list is empty — CAPA deprovisions the cloud resources first,
# so deletion takes 10-15 minutes. Do NOT interrupt it.
kubectl get clusterdeployments -A --watch
# When no ClusterDeployments remain, press Ctrl+C
```

> **Stuck deletion?** If a ClusterDeployment hangs in `Deleting` for more than ~20 minutes (commonly expired AWS SSO credentials — CAPA can't deprovision without valid credentials), refresh credentials as described in [Resuming This Lab](#resuming-this-lab) and the deletion will resume.

### Step 2: Verify Nothing Was Orphaned in AWS

CAPA and the cloud controller manager tag everything they create with per-cluster tags. Confirm AWS shows no leftovers — **every command below should print nothing**:

```bash
# EC2 instances — should be empty
aws ec2 describe-instances --region "$AWS_REGION" \
  --filters "Name=tag-key,Values=sigs.k8s.io/cluster-api-provider-aws/cluster/managed-cluster-01" \
            "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text

# NAT gateways — should be empty
aws ec2 describe-nat-gateways --region "$AWS_REGION" \
  --filter "Name=tag-key,Values=sigs.k8s.io/cluster-api-provider-aws/cluster/managed-cluster-01" \
           "Name=state,Values=pending,available" \
  --query 'NatGateways[].NatGatewayId' --output text

# Classic ELBs — checks tags, not names, because the CCM-created ingress ELB
# has a random hex name. Should print nothing.
for lb in $(aws elb describe-load-balancers --region "$AWS_REGION" \
    --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text); do
  aws elb describe-tags --region "$AWS_REGION" --load-balancer-names "$lb" \
    --query 'TagDescriptions[?Tags[?contains(Key, `cluster/managed-cluster-01`)]].LoadBalancerName' \
    --output text
done
```

If any command returns IDs, deletion is still in progress — wait a few minutes and re-run. If IDs persist after the ClusterDeployment is gone, those resources are orphaned and billing: delete them manually in the AWS console before moving on.

If you created the optional Azure cluster in Lab 1.5, verify its resource group is gone too: `az group list --query "[?contains(name, 'azure-cluster')].name" -o tsv` should print nothing.

## Preserving Your Environment

The **management cluster stays** — it is reused later in the program (Week 5 GPU labs create GPU clusters via `ClusterDeployment` on this same management cluster).

> **If you're continuing the program: do NOT run `lab-destroy.sh`.** Pause the environment instead by stopping its EC2 instances — this is the supported way to pause between weeks:
>
> ```bash
> # From your local machine: find the management node and bastion instance IDs
> aws ec2 describe-instances \
>   --filters "Name=tag:Name,Values=k0rdent-training-mgmt-<your-engineer-id>,k0rdent-training-<your-engineer-id>-bastion" \
>             "Name=instance-state-name,Values=running" \
>   --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]' --output table
>
> # Stop both (state is preserved on their EBS volumes)
> aws ec2 stop-instances --instance-ids <mgmt-instance-id> <bastion-instance-id>
> ```
>
> Stopping the instances removes the dominant compute cost. The NAT gateway (~$0.045/hr), Classic ELB, Elastic IP, and EBS volumes still bill while stopped — roughly **$2/day idle** instead of ~$6/day running.
>
> To resume: `aws ec2 start-instances --instance-ids <mgmt-instance-id> <bastion-instance-id>`, wait a couple of minutes, then reconnect with `./scripts/lab-connect.sh <your-engineer-id>`. The k0s cluster comes back up on its own — the management node keeps its stable private IP and the bastion keeps its Elastic IP, so your kubeconfig and SSH access still work.

> **If you're NOT continuing the program:** once the managed-cluster teardown above is complete and the AWS orphan checks come back empty, run `./scripts/lab-destroy.sh` to remove the management environment.

## Week 1 Complete!

Congratulations on completing Week 1! You have:

1. **Lab 1.1**: Provisioned a k0rdent Enterprise management cluster
2. **Lab 1.2**: Explored the k0rdent UI and Service Catalog
3. **Lab 1.3**: Configured AWS infrastructure provider credentials
4. **Lab 1.4**: Hardened the setup for production use
5. **Lab 1.5**: Provisioned a managed Kubernetes cluster
6. **Lab 1.6**: Deployed KOF for observability and FinOps
7. **Lab 1.7**: Deployed services across clusters with MultiClusterService
8. **Lab 1.8**: Upgraded the management plane and learned the rollback procedures for every layer

You now have a solid foundation in k0rdent Enterprise for managing multi-cluster Kubernetes infrastructure.

## Next

Complete the [Week 1 Quiz](../week-1-quiz.md) to finish Week 1.

Then proceed to [Week 2: Bare Metal as a Service](../../week-2-bmaas/README.md) to learn how to manage bare metal infrastructure with k0rdent.
