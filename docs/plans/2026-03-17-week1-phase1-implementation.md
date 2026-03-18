# Week 1 Phase 1: Critical Accuracy Fixes — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all accuracy errors in Week 1 training material verified against official k0rdent Enterprise docs.

**Architecture:** Pure content edits to markdown and Terraform variable files. No infrastructure changes. Each task is independent and can be parallelized.

**Tech Stack:** Markdown, Terraform HCL, k0rdent Enterprise v1.2.2 docs

---

## Task 1: Replace ServiceDeployment with MultiClusterService (Theory 1.2)

**Files:**
- Modify: `curriculum/week-1-foundations/theory/1.2-k0rdent-components.md:175-257`

**Step 1: Update KSM architecture diagram (line 175-193)**

Replace the existing KSM architecture diagram with one that shows the correct CRDs:

```
OLD (line 181-182):
│  │  - ServiceDeploy │  │  │ Source │ │  Helm   │  │

NEW:
│  │  - MultiCluster  │  │  │ Source │ │  Helm   │  │
```

Full replacement for lines 175-193:
```
┌────────────────────────────────────────────────────────┐
│                        KSM                              │
│  ┌──────────────────┐  ┌──────────────────────────┐    │
│  │  ksm-controller  │  │    Flux Controllers       │    │
│  │                  │  │  ┌────────┐ ┌─────────┐  │    │
│  │  - ServiceTemp   │  │  │ Source │ │  Helm   │  │    │
│  │  - MultiCluster  │  │  │  Ctrl  │ │  Ctrl   │  │    │
│  │    Service       │  │  └────────┘ └─────────┘  │    │
│  └──────────────────┘  └──────────────────────────┘    │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │             Service Catalog                       │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐ │  │
│  │  │Ingress  │ │Monitoring│ │GPU Op  │ │ vLLM   │ │  │
│  │  └─────────┘ └─────────┘ └─────────┘ └────────┘ │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

**Step 2: Replace ServiceDeployment section with MultiClusterService (lines 221-241)**

Remove the entire `#### ServiceDeployment` section (lines 221-241) and replace with:

```markdown
#### MultiClusterService

Deploys services to clusters matching a label selector. This is the primary mechanism for fleet-wide service deployment.

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: monitoring-stack
  namespace: kcm-system
spec:
  clusterSelector:
    matchLabels:
      environment: production
  serviceSpec:
    services:
    - template: kube-prometheus-stack
      name: monitoring
      namespace: monitoring
      values: |
        prometheus:
          retention: 30d
        grafana:
          enabled: true
    priority: 100
```

> **Note:** Services can also be deployed to a single cluster directly via `ClusterDeployment.spec.serviceSpec`. MultiClusterService is for fleet-wide deployment across clusters matching labels.
```

**Step 3: Update Helm integration section (lines 243-249)**

Replace lines 245-249:

```markdown
KSM uses Flux's Helm Controller under the hood:
1. ServiceTemplates define which Helm chart to use
2. MultiClusterServices specify target clusters (via label selectors) and service values
3. KSM creates HelmRelease objects on target clusters via Sveltos
4. Flux reconciles the HelmRelease to install/upgrade the chart
```

**Step 4: Verify knowledge check answers are already correct**

Lines 488-490 already reference MultiClusterService correctly — no change needed.

**Step 5: Commit**

```bash
git add curriculum/week-1-foundations/theory/1.2-k0rdent-components.md
git commit -m "fix(week1): replace non-existent ServiceDeployment CRD with MultiClusterService

ServiceDeployment is not a real k0rdent CRD. The correct API for fleet-wide
service deployment is MultiClusterService. Updated Theory 1.2 KSM section
with correct CRD name, YAML example, and Helm integration description."
```

---

## Task 2: Fix Credential Model in Theory 1.3

**Files:**
- Modify: `curriculum/week-1-foundations/theory/1.3-infrastructure-providers.md:351-396`

**Step 1: Update the credential flow diagram (lines 357-362)**

Replace:
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Credential    │────▶│     Secret      │────▶│ Cloud Provider  │
│   (CRD)         │     │ (actual creds)  │     │ API             │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

With:
```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Credential    │────▶│  Provider Identity   │────▶│     Secret      │────▶│ Cloud Provider  │
│   (CRD)         │     │  (e.g. AWSCluster-   │     │ (actual creds)  │     │ API             │
│                 │     │   StaticIdentity)    │     │                 │     │                 │
└─────────────────┘     └──────────────────────┘     └─────────────────┘     └─────────────────┘
```

**Step 2: Replace the simplified credential example (lines 364-396)**

Replace the entire "Creating Credentials" section (lines 364-396) with:

```markdown
### Creating Credentials (AWS Example)

k0rdent uses a three-layer credential model for cloud providers:

| Layer | Resource | Purpose |
|-------|----------|---------|
| 1 | Kubernetes `Secret` | Stores actual cloud credentials |
| 2 | Provider Identity CRD | Provider-specific identity configuration |
| 3 | k0rdent `Credential` | References the identity, used by ClusterDeployments |

#### Step 1: Create the Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-cluster-identity-secret
  namespace: kcm-system
type: Opaque
stringData:
  AccessKeyID: "AKIA..."
  SecretAccessKey: "..."
```

#### Step 2: Create the Provider Identity

Each provider has its own identity CRD:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSClusterStaticIdentity
metadata:
  name: aws-cluster-identity
  namespace: kcm-system
spec:
  secretRef: aws-cluster-identity-secret
  allowedNamespaces:
    selector:
      matchLabels: {}
```

#### Step 3: Create the k0rdent Credential

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: aws-cluster-identity-cred
  namespace: kcm-system
spec:
  identityRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSClusterStaticIdentity
    name: aws-cluster-identity
    namespace: kcm-system
```

**Provider Identity CRDs by Provider:**

| Provider | Identity CRD | Secret Keys |
|----------|-------------|-------------|
| AWS | `AWSClusterStaticIdentity` | `AccessKeyID`, `SecretAccessKey` |
| Azure | `AzureClusterIdentity` | `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, etc. |
| vSphere | `VSphereClusterIdentity` | `username`, `password` |
| Remote | *(none — Credential references Secret directly)* | SSH private key |

> **Note:** The RemoteMachine provider is the exception — its Credential references a Secret directly without an intermediate identity CRD.
```

**Step 3: Commit**

```bash
git add curriculum/week-1-foundations/theory/1.3-infrastructure-providers.md
git commit -m "fix(week1): correct credential model in Theory 1.3 to three-layer pattern

Theory 1.3 showed Credential referencing Secret directly for AWS, which is
wrong. AWS requires: Secret → AWSClusterStaticIdentity → Credential.
Updated with correct three-layer model, provider comparison table, and
note about RemoteMachine exception."
```

---

## Task 3: Remove spec.description from Credential CRD (Theory 1.2)

**Files:**
- Modify: `curriculum/week-1-foundations/theory/1.2-k0rdent-components.md:151-163`

**Step 1: Remove the description field (line 158)**

Replace lines 151-163:
```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: aws-creds
  namespace: kcm-system
spec:
  description: "AWS credentials for production"
  identityRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSClusterStaticIdentity
    name: aws-cluster-identity
```

With:
```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: aws-cluster-identity-cred
  namespace: kcm-system
spec:
  identityRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSClusterStaticIdentity
    name: aws-cluster-identity
    namespace: kcm-system
```

**Step 2: Commit**

```bash
git add curriculum/week-1-foundations/theory/1.2-k0rdent-components.md
git commit -m "fix(week1): remove non-existent spec.description from Credential CRD example

The Credential CRD does not have a spec.description field. Also added
namespace to identityRef and aligned naming with Lab 1.3 conventions."
```

---

## Task 4: Fix "150+" to "100+" Services Count

**Files:**
- Modify: `curriculum/week-1-foundations/labs/lab-1.2-explore-k0rdent-ui.md` (lines 422, 487)
- Modify: `curriculum/week-1-foundations/labs/lab-1.7-multicluster-services.md` (lines 79, 661)

**Step 1: Fix lab-1.2 line 422**

Replace: `The catalog provides **150+ validated services** across categories:`
With: `The catalog provides **100+ validated services** across categories:`

**Step 2: Fix lab-1.2 line 487**

Replace: `| **Selection** | Limited set | 150+ services |`
With: `| **Selection** | Limited set | 100+ services |`

**Step 3: Fix lab-1.7 line 79**

Replace: `The catalog organizes 150+ services into categories:`
With: `The catalog organizes 100+ services into categories:`

**Step 4: Fix lab-1.7 line 661**

Replace: `- Explored the k0rdent Service Catalog (150+ services)`
With: `- Explored the k0rdent Service Catalog (100+ services)`

**Step 5: Commit**

```bash
git add curriculum/week-1-foundations/labs/lab-1.2-explore-k0rdent-ui.md \
       curriculum/week-1-foundations/labs/lab-1.7-multicluster-services.md
git commit -m "fix(week1): correct service catalog count from 150+ to 100+"
```

---

## Task 5: Pin Versions to k0rdent Enterprise v1.2.2

**Files:**
- Modify: `README.md` (lines 70, 83, 119)
- Modify: `curriculum/week-1-foundations/README.md` (line 56)
- Modify: `curriculum/week-1-foundations/labs/lab-1.1-provision-k0rdent.md` (line 127)
- Modify: `curriculum/week-1-foundations/labs/lab-1.2-explore-k0rdent-ui.md` (line 637)
- Modify: `lab-infrastructure/terraform/environments/student-lab/variables.tf` (line 72)
- Modify: `lab-infrastructure/terraform/modules/k0rdent-mgmt/variables.tf` (line 90)

**Step 1: Update root README.md**

Line 70: Replace `| k0rdent Enterprise | v1.2.1 | Management platform |`
With: `| k0rdent Enterprise | v1.2.2 | Management platform (N-1; upgrade to v1.2.3 in Lab 1.8) |`

Line 83: Replace `| Terraform | >= 1.5.0 |`
With: `| Terraform | >= 1.8.0 |`

Line 119: Replace `- **k0rdent Enterprise** (v1.2.1)`
With: `- **k0rdent Enterprise** (v1.2.2)`

**Step 2: Update Week 1 README**

Line 56: Replace `| k0rdent Enterprise | 1.2.1 | Lab 1.1 (auto-installed) |`
With: `| k0rdent Enterprise | 1.2.2 | Lab 1.1 (auto-installed); upgrade to 1.2.3 in Lab 1.8 |`

**Step 3: Update Lab 1.1**

Line 127: Replace `| k0rdent | Enterprise v1.2.1 |`
With: `| k0rdent | Enterprise v1.2.2 |`

**Step 4: Update Lab 1.2**

Line 637: Replace `- **k0rdent Version:** 1.2.1`
With: `- **k0rdent Version:** 1.2.2`

**Step 5: Update Terraform variables**

`lab-infrastructure/terraform/environments/student-lab/variables.tf` line 72:
Replace: `default     = "1.2.1"`
With: `default     = "1.2.2"`

`lab-infrastructure/terraform/modules/k0rdent-mgmt/variables.tf` line 90:
Replace: `default     = "1.2.1"`
With: `default     = "1.2.2"`

**Step 6: Commit**

```bash
git add README.md \
       curriculum/week-1-foundations/README.md \
       curriculum/week-1-foundations/labs/lab-1.1-provision-k0rdent.md \
       curriculum/week-1-foundations/labs/lab-1.2-explore-k0rdent-ui.md \
       lab-infrastructure/terraform/environments/student-lab/variables.tf \
       lab-infrastructure/terraform/modules/k0rdent-mgmt/variables.tf
git commit -m "fix(week1): pin k0rdent Enterprise to v1.2.2 (N-1 strategy)

Updated all version references from 1.2.1 to 1.2.2. Lab 1.8 will
cover upgrading to v1.2.3. Also fixed Terraform version inconsistency
in root README (was >= 1.5.0, should be >= 1.8.0)."
```

---

## Task 6: Audit and Fix k0rdent Enterprise Branding

**Files:**
- Modify: `curriculum/week-1-foundations/labs/lab-1.2-explore-k0rdent-ui.md` (line 276)
- Modify: `curriculum/overview/training-program-overview.md` (add branding note)

Note: The `docs.k0rdent.io` references in Week 5 files are OUT OF SCOPE for this phase — they'll be addressed when we review Week 5.

**Step 1: Fix Lab 1.2 OSS doc link (line 276)**

Replace:
`see the [k0rdent Authentication documentation](https://docs.k0rdent.io/latest/admin/installation/auth/)`

With:
`see the [k0rdent Enterprise Authentication documentation](https://docs.mirantis.com/k0rdent-enterprise/latest/admin/installation/auth/)`

**Step 2: Add branding clarification to training-program-overview.md**

After the Executive Summary paragraph (line 5), add:

```markdown
> **Scope:** This training covers **k0rdent Enterprise** exclusively (Mirantis commercial distribution). Open-source k0rdent documentation (`docs.k0rdent.io`) may differ in features and CRD versions. **k0rdent AI** is introduced in Week 5.
```

**Step 3: Commit**

```bash
git add curriculum/week-1-foundations/labs/lab-1.2-explore-k0rdent-ui.md \
       curriculum/overview/training-program-overview.md
git commit -m "fix(week1): clarify k0rdent Enterprise branding and fix OSS doc link

Added scope note to training overview clarifying Enterprise-exclusive focus.
Fixed Lab 1.2 auth docs link to point to Enterprise docs instead of OSS.
Week 5 OSS links deferred to Week 5 review."
```

---

## Verification Checklist

After all tasks, run these checks:

```bash
# No more ServiceDeployment references in Week 1
grep -r "ServiceDeployment" curriculum/week-1-foundations/ && echo "FAIL" || echo "PASS"

# No more 150+ references in curriculum (except plans/tasks)
grep -r "150+" curriculum/week-1-foundations/ && echo "FAIL" || echo "PASS"

# No more 1.2.1 in version-critical files
grep -r "1\.2\.1" curriculum/week-1-foundations/ lab-infrastructure/terraform/ README.md && echo "FAIL" || echo "PASS"

# No spec.description in Credential examples
grep -r "spec:" -A2 curriculum/week-1-foundations/theory/1.2-k0rdent-components.md | grep "description:" && echo "FAIL" || echo "PASS"

# Credential in Theory 1.3 references AWSClusterStaticIdentity, not Secret
grep -A5 "identityRef:" curriculum/week-1-foundations/theory/1.3-infrastructure-providers.md | grep "kind: Secret" && echo "FAIL" || echo "PASS"
```

All should show PASS.
