# Week 1 Improvements Design

**Date:** 2026-03-17
**Scope:** k0rdent Enterprise Training — Week 1 Foundations
**Target:** k0rdent Enterprise v1.2.2 (N-1), upgrade exercise to v1.2.3
**Branding:** Exclusive k0rdent Enterprise (k0rdent AI deferred to Week 5)

---

## Context

Comprehensive audit of the Week 1 training material against official k0rdent Enterprise documentation revealed accuracy issues, missing content, broken references, and internal inconsistencies. This plan addresses all findings, prioritized by impact on training quality.

## Sources Used for Verification

- https://docs.mirantis.com/k0rdent-enterprise/latest/
- https://docs.k0rdent.io/latest/concepts/k0rdent-architecture/
- https://docs.k0rdent.io/latest/admin/kof/kof-architecture/
- https://docs.k0rdent.io/latest/reference/crds/
- https://github.com/k0rdent/kcm
- https://github.com/k0rdent/docs
- https://catalog.k0rdent.io/

---

## Section 1: Critical Accuracy Fixes

### 1.1 Replace ServiceDeployment with correct CRDs (Theory 1.2)

**Problem:** Theory 1.2 defines a `ServiceDeployment` CRD (lines 225-241) that does not exist in k0rdent. The official API uses `MultiClusterService` for fleet-wide service deployment and `ClusterDeployment.spec.serviceSpec` for per-cluster services.

**Fix:**
- Remove the `ServiceDeployment` CRD example and section entirely
- Replace with `MultiClusterService` CRD example showing `spec.clusterSelector` and `spec.serviceSpec.services`
- Add a brief note about `ClusterDeployment.spec.serviceSpec` for per-cluster use
- Update the KSM architecture diagram to show MultiClusterService instead of ServiceDeployment
- Update Knowledge Check Q7 answer to reference MultiClusterService

**Files:** `curriculum/week-1-foundations/theory/1.2-k0rdent-components.md`

### 1.2 Fix credential model in Theory 1.3

**Problem:** Theory 1.3 (lines 367-396) shows a simplified credential model where `Credential.spec.identityRef` points directly to a `Secret`. For AWS, the correct model is: `Secret` → `AWSClusterStaticIdentity` → `Credential`. This contradicts Theory 1.2's answer key which correctly describes the three-layer model.

**Fix:**
- Replace the Theory 1.3 AWS credential example with the correct three-layer model
- Keep the simplified (Secret-based) model but label it as "for RemoteMachine provider only"
- Add a comparison table showing credential chains per provider:
  - AWS: Secret → AWSClusterStaticIdentity → Credential
  - Azure: Secret → AzureClusterIdentity → Credential
  - vSphere: Secret → VSphereClusterIdentity → Credential
  - Remote: Secret → Credential (direct)

**Files:** `curriculum/week-1-foundations/theory/1.3-infrastructure-providers.md`

### 1.3 Remove spec.description from Credential CRD examples

**Problem:** Theory 1.2 (line 158) shows `spec.description` on the Credential CRD. This field does not exist in the official API.

**Fix:** Remove the `description` field from the Credential YAML example.

**Files:** `curriculum/week-1-foundations/theory/1.2-k0rdent-components.md`

### 1.4 Fix "150+" to "~100" services

**Problem:** Multiple files claim "150+ validated services" in the catalog. Actual count is approximately 100.

**Fix:** Global find-and-replace "150+" with "100+" across all curriculum files.

**Files:** All files referencing the service catalog count (Lab 1.2, Lab 1.7, Theory 1.2)

### 1.5 Pin versions to k0rdent Enterprise v1.2.2

**Problem:** README pins to v1.2.1. Training should use N-1 (v1.2.2) with upgrade exercise to v1.2.3.

**Fix:**
- Update Week 1 README version table: `1.2.1` → `1.2.2`
- Update training-program-overview.md if it references a specific version
- Update cloud-init templates and provisioning scripts that reference k0rdent version
- Add note: "Lab 1.8 will upgrade to v1.2.3"

**Files:**
- `curriculum/week-1-foundations/README.md`
- `curriculum/overview/training-program-overview.md`
- `lab-infrastructure/terraform/modules/k0rdent-mgmt/templates/mgmt-cloud-init.yaml`

### 1.6 Explicit k0rdent Enterprise branding

**Problem:** Training mixes OSS docs (docs.k0rdent.io) and Enterprise docs (docs.mirantis.com/k0rdent-enterprise). Should be Enterprise-exclusive.

**Fix:**
- Audit all doc links; replace `docs.k0rdent.io` references with `docs.mirantis.com/k0rdent-enterprise/latest/` equivalents where enterprise docs exist
- Keep OSS links only where enterprise equivalent doesn't exist (e.g., KOF architecture details)
- Add clarifying note to overview: "This training covers k0rdent Enterprise exclusively. k0rdent AI is introduced in Week 5."

**Files:** All theory and lab files in week-1-foundations/

---

## Section 2: Missing Content Additions

### 2.1 Add k0smotron section to Theory 1.2

**Rationale:** k0smotron is a critical component. Official docs describe it as extending CAPI with k0s bootstrap/control-plane providers and hosted control plane support. Engineers will encounter it in logs and debugging.

**Content to add (new section between KCM and KSM):**
- What k0smotron is and why it exists
- Four capabilities: bootstrap provider, control plane provider, hosted CP, RemoteMachine provider
- How it fits in the KCM architecture (k0smotron controller runs alongside CAPI controllers)
- Diagram showing k0smotron's position in the stack

**Files:** `curriculum/week-1-foundations/theory/1.2-k0rdent-components.md`

### 2.2 Add ProviderTemplate CRD to Theory 1.2

**Rationale:** ProviderTemplate is how infrastructure providers are registered with k0rdent. Currently not covered at all.

**Content to add:**
- Add to the CRD table in Theory 1.2
- Brief YAML example showing a ProviderTemplate
- Explain: ProviderTemplates ship with k0rdent; custom ones can be created for new CAPI providers

**Files:** `curriculum/week-1-foundations/theory/1.2-k0rdent-components.md`

### 2.3 Add ClusterTemplateChain / ServiceTemplateChain explanation

**Rationale:** Mentioned in Lab 1.7 without context. These control template upgrade paths.

**Content to add:**
- Short subsection in Theory 1.2 or Theory 1.3
- Explain: chains define which template versions can upgrade to which
- Brief YAML example
- Why it matters: prevents incompatible upgrades

**Files:** `curriculum/week-1-foundations/theory/1.2-k0rdent-components.md`

### 2.4 Add Hosted Control Planes explanation

**Rationale:** Listed as a template type in Theory 1.2 with zero explanation. Major k0rdent capability.

**Content to add (1-2 paragraphs in Theory 1.1 or 1.2):**
- What: Control plane runs as pods on management cluster (not on dedicated VMs)
- When: Edge deployments, cost savings, fast provisioning
- Trade-offs: Shared failure domain, management cluster sizing
- How: Enabled via k0smotron + hosted-cp templates

**Files:** `curriculum/week-1-foundations/theory/1.1-k0rdent-architecture.md` or `1.2-k0rdent-components.md`

### 2.5 New Lab 1.8: Upgrade Exercise

**Duration:** ~1.5h
**Placement:** Day 5, after Lab 1.7 (before quiz)

**Lab structure:**
1. Verify current k0rdent Enterprise v1.2.2 version (helm list, Management CRD)
2. Review v1.2.3 release notes (what changed, any breaking changes)
3. Pre-upgrade checklist (etcd backup from Lab 1.4, verify all clusters healthy)
4. Perform helm upgrade to v1.2.3
5. Verify upgrade success (pods restarted, CRDs updated, controllers healthy)
6. Validate existing ClusterDeployments still healthy
7. Verify KOF stack still collecting telemetry
8. Document rollback procedure (helm rollback steps)

**Files:** `curriculum/week-1-foundations/labs/lab-1.8-upgrade-k0rdent.md`

### 2.6 Fix Terraform version inconsistency

**Problem:** Prerequisites says `>= 1.8.0`, Lab 1.1 says `v1.5.0+`.

**Fix:** Align to `>= 1.8.0` everywhere (the higher requirement from prerequisites).

**Files:** `curriculum/week-1-foundations/labs/lab-1.1-provision-k0rdent.md`, `curriculum/overview/prerequisites.md`

---

## Section 3: Broken References & Polish

### 3.1 Create week-1-quiz.md

**Content:**
- 15-20 questions (mix of multiple choice and short answer)
- Topics: architecture, CAPI, credential model, ClusterDeployment lifecycle, KOF, MultiClusterService, upgrade process
- Answer key with explanations
- 80% pass, 30min limit

**Files:** `curriculum/week-1-foundations/week-1-quiz.md`

### 3.2 Create resources/reference-links.md

**Content:**
- Organized links to k0rdent Enterprise docs, CAPI book, k0s docs, Flux, Helm
- Grouped by topic
- Enterprise docs only (docs.mirantis.com/k0rdent-enterprise)

**Files:** `curriculum/week-1-foundations/resources/reference-links.md`

### 3.3 Create resources/cheat-sheets.md

**Content:**
- kubectl aliases from Lab 1.1
- Common k0rdent commands grouped by task
- Troubleshooting decision tree

**Files:** `curriculum/week-1-foundations/resources/cheat-sheets.md`

### 3.4 Fix network policy trap in Lab 1.4

**Problem:** Provides copyable network policy YAML that breaks Labs 1.5-1.7, marked "DO NOT APPLY".

**Fix:**
- Move unsafe policies to "Production Reference" appendix section
- Provide a safe policy that includes webhook port 9443 exception
- Clear separation between "apply in this lab" and "reference only"

**Files:** `curriculum/week-1-foundations/labs/lab-1.4-production-configuration.md`

### 3.5 Standardize template name patterns

**Fix:**
- Theory examples use base name without version: `aws-standalone-cp`
- Add callout: "Template names include version suffixes. Use `kubectl get clustertemplates` to discover exact names."
- Labs use discovery commands (already correct)

**Files:** Theory 1.2, Theory 1.3

### 3.6 Fix Lab 1.2 duration and update totals

**Fix:**
- Align Lab 1.2 to 2.5h in README schedule
- Update Week 1 total: 25h (was 24.5h) + 1.5h (Lab 1.8) = 26.5h
- Adjust Day 5 schedule or redistribute

**Files:** `curriculum/week-1-foundations/README.md`

---

## Implementation Order

**Phase 1 — Critical accuracy (do first, blocks everything):**
1. Fix ServiceDeployment → MultiClusterService (1.1)
2. Fix credential model (1.2)
3. Remove spec.description (1.3)
4. Fix 150+ → ~100 (1.4)
5. Pin to v1.2.2 (1.5)
6. Enterprise branding audit (1.6)

**Phase 2 — Missing content (adds depth):**
7. k0smotron section (2.1)
8. ProviderTemplate CRD (2.2)
9. TemplateChains (2.3)
10. Hosted Control Planes (2.4)
11. Lab 1.8 Upgrade Exercise (2.5)
12. Terraform version fix (2.6)

**Phase 3 — Broken references & polish:**
13. Week 1 quiz (3.1)
14. Reference links (3.2)
15. Cheat sheets (3.3)
16. Network policy fix (3.4)
17. Template name standardization (3.5)
18. Duration fixes (3.6)

---

## Estimated Effort

| Phase | Items | Estimate |
|-------|-------|----------|
| Phase 1 | 6 items | ~2-3 hours |
| Phase 2 | 6 items | ~4-6 hours |
| Phase 3 | 6 items | ~3-4 hours |
| **Total** | **18 items** | **~9-13 hours** |
