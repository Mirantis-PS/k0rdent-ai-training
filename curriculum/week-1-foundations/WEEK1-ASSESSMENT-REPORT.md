# Week 1 Training Lab Assessment Report
## k0rdent Enterprise Installation & Configuration

**Assessed by:** Engineer simulating production readiness training
**Date:** 2026-02-06
**Scope:** All Week 1 content (3 theory modules + 7 labs) + infrastructure automation
**Cross-referenced against:** Official k0rdent docs (`/k0rdent/docs` via Context7)

---

## Executive Summary

The Week 1 training curriculum is **well-structured and comprehensive**, covering k0rdent architecture through production-ready deployment. The lab automation (Terraform + scripts) is solid and genuinely multi-tenant capable. However, I found **5 critical issues**, **12 moderate issues**, and **8 UX improvements** that should be addressed before production training delivery.

**Overall Rating:** 7.5/10 - Good foundation with notable gaps in accuracy and completeness.

> **Status:** All 5 critical issues (C1-C5) have been **fixed**. See Priority 1 items below.

---

## 1. CRITICAL ISSUES (Must Fix)

### C1. Week 1 README is Incomplete - Missing Labs 1.5-1.7

**File:** `curriculum/week-1-foundations/README.md`
**Lines:** 19-29, 38-43

The README schedule only covers Days 1-5 with Labs 1.1-1.4, but the actual curriculum has **7 labs** (1.1-1.7). Labs 1.5 (Provision Managed Cluster), 1.6 (Deploy KOF), and 1.7 (Multi-Cluster Services) are not listed in the schedule or the Lab Exercises section.

This is arguably the most user-facing issue. An engineer opening the Week 1 README would think there are only 4 labs. Labs 1.5-1.7 contain the most critical learning (actually deploying clusters and observability), yet they're invisible from the index.

**Proposed fix:** Update the README schedule to include all 7 labs across the full week, and add Lab Exercises links for 1.5, 1.6, 1.7. Adjust the time allocation (currently 15h total but 7 labs need more).

---

### C2. Theory Content Contradicts Actual KOF Architecture

**Files:** `theory/1.1-k0rdent-architecture.md` (lines 213-216), `theory/1.2-k0rdent-components.md` (lines 273-310)

The theory documents describe KOF as using:
- **Prometheus/Thanos** for metrics
- **Loki** for log aggregation
- **Promtail** for log collection

But Lab 1.6 (correctly) shows the actual KOF stack uses:
- **VictoriaMetrics** for metrics (vmcluster, vminsert, vmselect)
- **VictoriaLogs** for log aggregation
- **OpenTelemetry** for collection (not Promtail)
- **Jaeger** for tracing

This is confirmed by official k0rdent docs which describe the KOF architecture with VictoriaMetrics, VictoriaLogs, and Jaeger.

**Proposed fix:** Update theory 1.1 and 1.2 to accurately reflect the VictoriaMetrics-based stack. The diagrams in both theory files need to be updated:

Theory 1.1 (lines 273-286) should change:
```
# FROM:
Metrics Pipeline:  Prometheus -> Thanos -> Grafana
Logging Pipeline:  Promtail -> Loki -> Grafana

# TO:
Metrics Pipeline:  OpenTelemetry -> VictoriaMetrics -> Grafana
Logging Pipeline:  OpenTelemetry -> VictoriaLogs -> Grafana
Tracing Pipeline:  OpenTelemetry -> Jaeger -> Grafana
```

Theory 1.2 (lines 289-310) similarly needs updating.

---

### C3. Lab 1.4 RBAC Role References Non-Existent Resource

**File:** `labs/lab-1.4-production-configuration.md` (lines 114-128)

The `k0rdent-project-admin` Role includes:
```yaml
resources: ["managedclusters", "clusterdeployments"]
```

The resource `managedclusters` does not exist in k0rdent Enterprise v1.2.1. The correct resources are `clusterdeployments` (which is already listed) and possibly `multiclusterservices`. An engineer applying this RBAC role would get no errors but the `managedclusters` permission would be useless, creating a false sense of security coverage.

**Proposed fix:** Remove `managedclusters` and replace with relevant k0rdent CRD resources like `multiclusterservices`, `credentials`, or `servicetemplates` depending on the access intent.

---

### C4. Lab 1.3 Credential Naming Differs from Official Docs

**File:** `labs/lab-1.3-configure-aws-provider.md` (lines 176-190)

The lab names the Credential `aws-credential`, but the official k0rdent documentation consistently uses `aws-cluster-identity-cred`:

```yaml
# Lab uses:
name: aws-credential

# Official docs use:
name: aws-cluster-identity-cred
```

Lab 1.5 correctly references `aws-credential` (matching Lab 1.3), so the labs are **internally consistent**. However, engineers cross-referencing with official docs will be confused. More importantly, the official ClusterDeployment examples reference `aws-cluster-identity-cred`.

**Proposed fix:** Align credential naming with official docs (`aws-cluster-identity-cred`) across Labs 1.3, 1.5, and any other references.

---

### C5. Lab 1.1 Broken Markdown in Troubleshooting Section

**File:** `labs/lab-1.1-provision-k0rdent.md` (lines 319-327)

There's a malformed code block structure:
```
```bash
# Check environment status
./scripts/lab-status.sh k0rdent your-name

**Error: Terraform version too old**
```bash
```

The `**Error: Terraform version too old**` text appears inside the first code block instead of as a heading between two code blocks. This renders incorrectly in any markdown viewer.

**Proposed fix:** Close the first code block before the error heading, then open the new one:
```markdown
```bash
# Check environment status
./scripts/lab-status.sh k0rdent your-name
```

**Error: Terraform version too old**

```bash
# Install newer Terraform
```

---

## 2. MODERATE ISSUES

### M1. Lab 1.5 Returns Wrong Kubeconfig Path for Management Cluster

**File:** `labs/lab-1.5-provision-managed-cluster.md` (line 339)

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
```

k0s does not use this path. The cloud-init script sets up the kubeconfig at `/home/ubuntu/.kube/config`. An engineer following this instruction would get an error.

**Proposed fix:** Change to `export KUBECONFIG=/home/ubuntu/.kube/config` or simply `unset KUBECONFIG` (which the previous line already suggests).

---

### M2. Lab Infrastructure README Claims Spot Instances as Default

**File:** `lab-infrastructure/README.md` (line 180)

> "All labs use spot instances by default for ~60-70% cost savings."

But `lab-provision.sh` line 524 sets `USE_SPOT="false"`. The k0rdent management cluster intentionally uses on-demand for reliability. This creates confusion about actual costs.

**Proposed fix:** Clarify that the k0rdent management cluster uses on-demand by default for reliability, while other lab types support `--spot`.

---

### M3. Lab 1.4 Audit Logging Section is a Dead End

**File:** `labs/lab-1.4-production-configuration.md` (lines 146-196)

The audit policy file is created at `/var/lib/k0s/audit-policy.yaml`, but the section ends with:
> "Note: This requires k0s configuration update"

And then just shows `sudo k0s config create` without actually configuring k0s to use the policy. An engineer would create the file but it would never be used.

**Proposed fix:** Either complete the configuration showing how to reference the audit policy in k0s.yaml, or explicitly mark this as "reference only" with a note that k0s configuration changes require a service restart and are beyond this lab's scope.

---

### M4. Lab 1.6 Storage Values May Create Conflicts

**File:** `labs/lab-1.6-deploy-kof.md` (lines 147-162)

The `storage-values.yaml` includes `promxy: enabled: true`, but the promxy PromxyServerGroup CRD is deployed by kof-storage, while the promxy deployment is part of kof-mothership. Including this in storage values could create confusion about which chart owns promxy.

---

### M5. Lab 1.3 IAM Policy Has Wildcards That Won't Work in Enterprise

**File:** `labs/lab-1.3-configure-aws-provider.md` (lines 62-94)

The policy uses `"ec2:*"` and `"elasticloadbalancing:*"` which is excessively broad. While noted as "for training," an engineer learning for production would internalize this pattern. Meanwhile, theory 1.3 shows a much more restrictive policy. The two conflict.

**Proposed fix:** Standardize on a single recommended policy, or explicitly label Lab 1.3 as "quick-start for training" and theory 1.3 as "production reference."

---

### M6. Lab 1.5 Azure Section Uses Potentially Wrong API Version

**File:** `labs/lab-1.5-provision-managed-cluster.md` (line 399)

The `AzureClusterIdentity` uses `apiVersion: infrastructure.cluster.x-k8s.io/v1beta1`, but k0rdent 1.2.1 with CAPZ should be verified for the correct API version. The AWS identity uses `v1beta2` while Azure uses `v1beta1` - this inconsistency may or may not be correct.

---

### M7. Version Pinning Fragility Across Labs

Multiple hardcoded versions that could break:
- KOF charts: `1.5.0` (Lab 1.6)
- cert-manager template: `1.16.2` (Lab 1.7)
- ingress-nginx template: `4.11.0` (Labs 1.2, 1.7)
- kyverno template: `3.2.6` (Lab 1.7)
- clusterctl: `v1.9.0` (cloud-init)
- k0sctl: `v0.19.4` (cloud-init)

If any of these are unavailable from their OCI registries, the lab breaks silently.

**Proposed fix:** Add a version compatibility table at the start of Week 1 or in the lab-infrastructure README that maps k0rdent Enterprise versions to compatible component versions. Consider adding version discovery commands before install steps.

---

### M8. Lab 1.3 AWSClusterStaticIdentity `allowedNamespaces` May Be Over-Permissive

**File:** `labs/lab-1.3-configure-aws-provider.md` (lines 157-169)

The lab uses both `list: ["kcm-system"]` AND `selector: matchLabels: {}`. The `matchLabels: {}` selector matches ALL namespaces, making the `list` restriction meaningless. Official docs use ONLY `selector: matchLabels: {}`.

**Proposed fix:** Use either `list` OR `selector`, not both. For training, `selector: matchLabels: {}` (match all) is fine, but explain what it means.

---

### M9. Lab 1.6 Child Cluster ConfigMap Endpoints Are Internal-Only

**File:** `labs/lab-1.6-deploy-kof.md` (lines 307-332)

The ConfigMap uses internal Kubernetes service DNS names (e.g., `vminsert-cluster.kof.svc.cluster.local`). These are only resolvable within the management cluster. While the lab later explains this limitation, the ConfigMap is presented as a "Step 2" without caveat, which could lead engineers to create it and expect it to work.

The lab does have a good "Training Environment Limitation" section (lines 571-587) explaining this, but it comes AFTER the configuration steps.

**Proposed fix:** Move the limitation callout BEFORE the configuration steps, or restructure the flow so engineers understand the networking challenge before creating resources.

---

### M10. Lab 1.2 Template Name Hardcoded

**File:** `labs/lab-1.2-explore-k0rdent-ui.md` (line 101)

```bash
kubectl get clustertemplate aws-standalone-cp-1-0-20 -n kcm-system -o yaml | head -100
```

The template name `aws-standalone-cp-1-0-20` is version-specific. The lab has a note about this, but the hardcoded command will fail for different k0rdent versions. Lab 1.5 handles this better by first listing templates and then using a variable.

**Proposed fix:** Replace with a dynamic approach like Lab 1.5 uses, or show the `kubectl get clustertemplates` output first and let engineers pick.

---

### M11. Lab 1.4 Network Policy Warning Could Be Stronger

The warning about network policies (lines 248-289) is well-written but uses "Skip this section" language. In practice, an eager engineer might still apply the policies and then spend hours debugging why Lab 1.5 fails with webhook timeout errors.

**Proposed fix:** Use a more prominent callout style (e.g., a boxed WARNING) and explain the specific failure mode: "Applying these policies WILL break cluster provisioning in Lab 1.5 by blocking webhook traffic on port 9443."

---

### M12. No Lab Validates Cloud-Init Completion Before Proceeding

Lab 1.1 mentions checking `/opt/k0rdent-lab/.init-complete` and tailing logs, but doesn't provide a blocking wait command. Engineers might proceed to Lab 1.2 before installation completes.

**Proposed fix:** Add a blocking wait snippet:
```bash
echo "Waiting for k0rdent installation to complete..."
while [ ! -f /opt/k0rdent-lab/.init-complete ]; do sleep 10; echo -n "."; done
echo " Done!"
```

---

## 3. UX IMPROVEMENTS

### U1. Missing Total Cost Estimate for Week 1

Engineers need to know upfront what Week 1 will cost. Based on the infrastructure:
- **Management cluster**: ~$0.17/hr (t3.xlarge on-demand)
- **NAT Gateway**: ~$0.045/hr
- **Managed cluster** (Lab 1.5): ~$0.15/hr (2x t3.medium)
- **Running 8hrs/day x 5 days**: ~$15-25 total

This should be stated in the Week 1 README.

### U2. Lab Duration vs Active Time Not Distinguished

Lab 1.1 says "3 hours" but ~25 minutes is just waiting for provisioning. Labs should distinguish between "elapsed time" and "active time" so engineers can plan their day.

### U3. Missing "Keep Running" Warning Between Labs 1.5-1.7

Labs 1.5, 1.6, and 1.7 all require a running managed cluster. Lab 1.5's cleanup section says "only destroy if done with ALL Week 1 labs" but this needs to be more prominent - perhaps a banner at the top of Labs 1.6 and 1.7 stating: "Requires managed cluster from Lab 1.5 to be running."

### U4. Theory-to-Lab Knowledge Bridge

There's no explicit bridge between theory modules and lab exercises. Theory 1.1 ends with "Knowledge Check" questions, but there's no answer key or self-assessment scoring. Engineers can't verify their understanding before starting labs.

### U5. Lab 1.6 is Too Dense (32KB)

Lab 1.6 covers KOF operators, mothership, storage, collectors, child cluster deployment (4 options), Grafana access, telemetry verification, custom dashboards, and troubleshooting. This should be split or have a clear "core path vs advanced path" structure.

### U6. No Diagram of Full Lab Architecture

There's no single diagram showing how the training infrastructure maps to what k0rdent manages. A diagram showing:
```
Local Machine --> Bastion --> Management Cluster --> Managed Cluster
                                    |
                              KOF Stack --> Grafana
```
Would greatly help engineers understand the full topology before they start.

### U7. Lab 1.7 MultiClusterService Validation is Weak

Lab 1.7 creates a MultiClusterService but the validation steps rely on the managed cluster being accessible and services deploying successfully, which requires successful completion of Labs 1.5 and 1.6. If any earlier lab had issues, Lab 1.7 becomes unrunnable with no fallback.

### U8. No Checkpoint/Resume Capability

If an engineer's SSH session drops or they need to resume the next day, there's no guidance on how to reconnect and verify state. A "Resuming the Lab" section in each lab would help, something like:
```bash
# Reconnect to your environment
./scripts/lab-connect.sh k0rdent <your-id>

# Verify cluster is still running
kubectl get nodes
kubectl get pods -n kcm-system
```

---

## 4. CROSS-REFERENCE WITH OFFICIAL DOCS - Accuracy Verification

| Topic | Training Content | Official Docs | Match? |
|-------|-----------------|---------------|--------|
| ClusterDeployment API | `k0rdent.mirantis.com/v1beta1` | `k0rdent.mirantis.com/v1beta1` | Yes |
| AWSClusterStaticIdentity API | `infrastructure.cluster.x-k8s.io/v1beta2` | `infrastructure.cluster.x-k8s.io/v1beta2` | Yes |
| Secret field names | `AccessKeyID`, `SecretAccessKey` | `AccessKeyID`, `SecretAccessKey` | Yes |
| Credential name | `aws-credential` | `aws-cluster-identity-cred` | **No** |
| KCM namespace | `kcm-system` | `kcm-system` | Yes |
| ClusterDeployment fields | `template`, `credential`, `config` | `template`, `credential`, `config` | Yes |
| KOF chart names | `kof-operators`, `kof-mothership`, `kof-storage`, `kof-collectors` | Same names | Yes |
| KOF chart registry | `oci://ghcr.io/k0rdent/kof/charts/` | Same registry | Yes |
| ServiceTemplate install method | `helm install` from `oci://ghcr.io/k0rdent/catalog/charts/` | Same method | Yes |
| KOF metrics stack | Theory says Prometheus/Thanos, Lab says VictoriaMetrics | VictoriaMetrics | **Lab correct, Theory wrong** |
| KOF logs stack | Theory says Loki/Promtail, Lab says VictoriaLogs/OTel | VictoriaLogs/OpenTelemetry | **Lab correct, Theory wrong** |
| Management object name | `kcm` | `kcm` | Yes |
| k0s as bootstrap/CP provider | Correctly described | Confirmed | Yes |
| Helm install for k0rdent | `oci://registry.mirantis.com/k0rdent-enterprise/charts/k0rdent-enterprise` | Plausible (registry path) | Needs verification |
| MultiClusterService CRD | Correctly described | Confirmed in docs | Yes |
| serviceSpec structure in MCS | Correctly described | Matches official examples | Yes |
| Beach-head services | Uses separate MCS | Docs show inline `serviceSpec` in ClusterDeployment | Different approach (both valid) |

---

## 5. INFRASTRUCTURE AUTOMATION REVIEW

### Strengths
- **Multi-tenant isolation** is well-designed: separate Terraform state per engineer
- **Auto-provisioning** of shared infra on first run is excellent UX
- **SSH key management** is automated and secure (ED25519, S3-backed)
- **lab-connect.sh** auto-detects bastion for private IPs - smart design
- **Cloud-init** bootstrap is comprehensive (6-stage pipeline)
- **Security groups** are properly scoped (bastion-only SSH, VPC-internal)
- **EBS encryption** is enabled by default
- **Artifact lifecycle** (30-day S3 expiry) prevents cost accumulation
- **CloudWatch log group** created per engineer for centralized logging
- **Welcome message** on SSH login shows cluster status and quick commands

### Weaknesses
- `lab-provision.sh` uses `cd "$env_dir"` and never returns to original directory (minor)
- `k0sctl` version `v0.19.4` is pinned in cloud-init but not validated against k0rdent 1.2.1
- Cloud-init runs `init-lab.sh` via nohup from root context but scripts assume ubuntu user KUBECONFIG
- No health check in `lab-provision.sh` after Terraform completes - just waits for instance running state, not for k0rdent to be ready
- The `--show-password` flag in lab-connect.sh reads from S3 state directly, which is smart but couples to Terraform state format
- node_count variable defaults to 3 in Terraform module but lab-provision.sh passes 1 - internally consistent but documentation says "3-node cluster" in module comments

---

## 6. SUMMARY OF PROPOSED CHANGES

### Priority 1 (Must fix before training delivery):
1. Update Week 1 README to include Labs 1.5-1.7 in schedule and links
2. Fix theory 1.1 and 1.2 KOF descriptions (VictoriaMetrics, not Prometheus/Thanos)
3. Fix Lab 1.4 RBAC `managedclusters` -> valid resource names
4. Fix Lab 1.1 broken markdown in troubleshooting section
5. Fix Lab 1.5 kubeconfig path (`/home/ubuntu/.kube/config`, not `/etc/kubernetes/admin.conf`)

### Priority 2 (Should fix):
6. Align credential naming with official docs across Labs 1.3 and 1.5
7. Fix `allowedNamespaces` dual selector/list in Lab 1.3
8. Add cost estimate to Week 1 README
9. Clarify Lab 1.6 child cluster networking limitations earlier in the flow
10. Add blocking wait snippet for cloud-init completion in Lab 1.1
11. Clarify spot vs on-demand defaults in infrastructure README

### Priority 3 (Nice to have):
12. Add answer keys for theory Knowledge Check questions
13. Add "Resuming the Lab" guidance to each lab
14. Add architecture topology diagram
15. Split Lab 1.6 into core and advanced paths
16. Add version compatibility table mapping k0rdent versions to component versions
17. Strengthen Lab 1.4 network policy warning with explicit failure description
