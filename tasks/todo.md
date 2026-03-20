# Week 1 Improvements — Task Tracker

**Plan:** [docs/plans/2026-03-17-week1-improvements-design.md](../docs/plans/2026-03-17-week1-improvements-design.md)

## Phase 1: Critical Accuracy Fixes ✅ COMPLETE

- [x] 1.1 Replace ServiceDeployment with MultiClusterService in Theory 1.2
- [x] 1.2 Fix credential model contradiction in Theory 1.3
- [x] 1.3 Remove spec.description from Credential CRD example in Theory 1.2
- [x] 1.4 Fix "150+" → "100+" services across all files
- [x] 1.5 Pin versions to k0rdent Enterprise v1.2.2 (+ Terraform >= 1.8.0 fix)
- [x] 1.6 Audit and fix k0rdent Enterprise branding (Enterprise docs, not OSS)

## Phase 2: Missing Content Additions ✅ COMPLETE

- [x] 2.1 Add k0smotron section to Theory 1.2
- [x] 2.2 Add ProviderTemplate CRD coverage to Theory 1.2
- [x] 2.3 Add ClusterTemplateChain / ServiceTemplateChain explanation
- [x] 2.4 Add Hosted Control Planes explanation (cross-ref in Theory 1.1)
- [x] 2.5 Create Lab 1.8: Upgrade Exercise (v1.2.2 → v1.2.3)
- [x] 2.6 Fix Terraform version inconsistency (align to >= 1.8.0 in Lab 1.1 + schedule update)

## Phase 3: Broken References & Polish ✅ COMPLETE

- [x] 3.1 Create week-1-quiz.md (18 questions: 12 MC + 6 short answer)
- [x] 3.2 Create resources/reference-links.md
- [x] 3.3 Create resources/cheat-sheets.md
- [x] 3.4 Fix network policy trap in Lab 1.4 (removed heredoc apply, added safe reference)
- [x] 3.5 Standardize template name patterns across theory files
- [x] 3.6 Fix Lab 1.2 duration and update Week 1 totals (done in Phase 2 commit)

## Envoy Gateway UI Exposure ✅ COMPLETE

**Plan:** [docs/plans/2026-03-18-envoy-gateway-ui-exposure-design.md](../docs/plans/2026-03-18-envoy-gateway-ui-exposure-design.md)

- [x] 1. Remove NLB resources from k0rdent-mgmt Terraform module
- [x] 2. Add Gateway API and Envoy Gateway version variables
- [x] 3. Replace NodePort with Envoy Gateway in cloud-init
- [x] 4. Update lab-provision.sh to wait for Gateway LB URL
- [x] 5. Add --ui-url and --show-gateway flags to lab-connect.sh
- [x] 6. Add Gateway API & Envoy Gateway theory section
- [x] 7. Update Lab 1.1 provisioning docs
- [x] 8. Rewrite Lab 1.2 access architecture section
- [x] 9. Update Week 1 README and Quiz

10 commits on main (`6c94b65..6643051`).

## Review

Week 1 Improvements: 3 commits on main:
- `78197e0` Phase 1: Critical accuracy fixes (10 files)
- `4ba5920` Phase 2: Missing content additions (5 files, 1 new lab)
- `a580820` Phase 3: Broken references and polish (5 files, 3 new files)

Envoy Gateway: 10 commits on main:
- Terraform: NLB removed, NodePort range opened, Gateway version vars
- Cloud-init: Envoy Gateway Helm install + Gateway API resources
- Scripts: lab-provision waits for LB URL, lab-connect gets --ui-url/--show-gateway
- Docs: Theory, Lab 1.1, Lab 1.2 rewrite, README, Quiz updated
