# Curriculum Completion Plan — Weeks 1-6

**Date:** 2026-07-06
**Goal:** every week has a README, every promised lab exists, no lab teaches
what another lab already owns, and everything provisioning-shaped is
live-validated before merge.

---

## Current inventory (verified against the tree, 2026-07-06)

| Week | README | Labs present | Gaps |
|------|--------|--------------|------|
| 1 — Foundations | ✅ | 1.1-1.9 (validated live 2026-06-11; 1.9 already post-fix on VictoriaLogs) | none |
| 2 — BMaaS | ✅ | 2.1-2.5 | README schedule table appears to list only 2.1-2.3 (verify); labs never live-validated |
| 3 — VMaaS | ✅ | 3.3 only | **3.1 (KubeVirt deploy) and 3.2 (GPU passthrough) are listed as 3.3's prerequisites but don't exist** |
| 4 — KaaS | ❌ | 4.1 ✅validated, 4.4 ✅validated (PR #11), 4.9, 4.10 | README; day-2 ops labs (4.6/4.7 — Lab 6.2 cites "Lab 4.7 patterns"); 4.2/4.3/4.8 intentionally **not** written (redundant with 5.1/5.12 — see decision below) |
| 5 — AI Workloads | ✅ | 5.1-5.18 | content stable; GPU-path labs never live-validated |
| 6 — Multi-tenancy | ❌ | 6.2, 6.3, 6.4, 6.6 (capstone) | README; **6.1 (Tenancy Model) and 6.5 (OIDC Federation) are "TBD" in siblings' navigation** |
| overview/ | — | — | `training-program-overview.md` is stale (says k0rdent 1.2.2, "only 4.9/4.10 exist") |

## Standing decisions

1. **No redundant labs.** 4.2/4.3 ≈ Lab 5.1 (GPU cluster + operator), 4.8 ≈ Lab
   5.12 Task 7 + the 4.1/4.4 fork material. The Week 4 README maps these
   tracks to their canonical homes instead of duplicating them.
2. **Every new provisioning lab is validated live before merge**, using the
   Lab 4.4 process: research upstream docs → write → run every command on the
   `tapha` env → fold findings back → PR. Resume procedure: start instances →
   `lab-refresh-creds.sh tapha` (SSO creds expire!) → connect.
3. **Expensive hardware is batched.** GPU/metal validation happens in
   dedicated short windows (provision → validate → destroy same day), never
   left running.

## Phases

### Phase 0 — Housekeeping (no new content, ~half day)
- Merge **PR #11** (Lab 4.4 + Week 5 prereq scoping).
- `lab-resume.sh`: start instances + credential refresh + health check (one
  documented resume step; prevents the 2026-07-03 AuthFailure detour).
- Refresh `curriculum/overview/training-program-overview.md` (versions, Week 4
  status, hour totals).
- File upstream k0rdent issue: expose `cniIngressRules` in `aws-standalone-cp`
  (found in Lab 4.4 validation); optionally report the geneve/SG gap to the
  catalog repo.

### Phase 1 — Week 4 closure (README + 2 labs, ~2-3 days)
- **Week 4 README**: day-by-day schedule mapping FOUNDATION → 4.1 (+5.1/5.12
  pointers for GPU/templates), NETWORKING → 4.4, ADVANCED → 4.9/4.10,
  OPERATIONS → new 4.6/4.7. Fix dangling links (4.1's "Next: 4.2", 5.17's
  "Lab 4.3 once available" → point at the README map).
- **Lab 4.6 — Managed-cluster upgrades**: template-version bump on a
  `ClusterDeployment` → rolling machine replacement. Not covered anywhere
  (Lab 1.8 upgrades the *management* cluster only). Cheap to validate
  (t3.medium cluster).
- **Lab 4.7 — Node maintenance & disruption budgets**: cordon/drain/PDB on a
  managed cluster — the exact patterns Lab 6.2 already cites. Cheap to
  validate.
- **Lab 4.5 (storage)**: backlog. The template already deploys EBS CSI and no
  other lab depends on a storage lab. Revisit only if a customer/course need
  appears.

### Phase 2 — Week 3 completion (2 labs, ~2-3 days + 1 GPU window)
- **Lab 3.1 — Deploy KubeVirt on a managed cluster** (3.3's first prereq).
  KubeVirt needs `/dev/kvm` → AWS **metal** instance for the worker
  (c5n.metal), or emulation mode for a low-cost partial validation. Author
  against docs; validate flow on emulation, then confirm on metal in the
  Phase 5 hardware window.
- **Lab 3.2 — GPU passthrough configuration** (3.3's second prereq): VFIO
  binding, device plugin, KubeVirt `permittedHostDevices`. Requires a metal
  GPU instance (g4dn.metal); validate in the same hardware window as 3.3.
- Update Week 3 README schedule to list 3.1/3.2/3.3.

### Phase 3 — Week 6 completion (README + 2 labs, ~2-3 days)
- **Lab 6.1 — Tenancy model**: k0rdent AccessManagement, namespaces-as-tenant
  boundary, per-tenant credentials/templates chains. Cheap to validate on the
  mgmt cluster.
- **Lab 6.5 — OIDC federation** (promised by 6.4's navigation): tenant
  identity via OIDC — in-cluster Dex/Keycloak as IdP, k8s API OIDC args via
  the template's `k0s.api.extraArgs` (validated passthrough from Lab 4.4
  research). Cheap to validate.
- **Week 6 README**: schedule across 6.1-6.6 including capstone.

### Phase 4 — Week 2 polish (~1 day, optional validation extra)
- Verify/fix the README schedule table (2.4/2.5 rows).
- Live validation is the open question: BMaaS labs assume a sandbox with BMCs.
  Optional: an emulated-Redfish rig (sushy-tools on EC2) to validate 2.2/2.3
  command flows. Decide at phase start whether the effort (~1-2 days) is
  worth it vs. doc-verification only.

### Phase 5 — Hardware validation window (1 focused day, ~$50-100)
One provision-validate-destroy day covering everything that needs real GPUs
or metal:
- Week 5 core GPU path: 5.1 → 5.5 → 5.6 (g5.12xlarge, ~$5.7/h)
- Lab 3.1/3.2/3.3 on metal GPU (g4dn.metal, ~$7.8/h)
- Anything Phase 1-3 flagged as "confirm on real hardware"
Everything else in Week 5 stays doc-verified (18 labs × GPU-hours is not a
sane validation budget; prioritize the labs most-trafficked by students).

### Phase 6 — Consistency pass (~1 day)
- Cross-week link check (no dangling lab references), version-table alignment
  (each week README's authoritative table), `graphify update .`.
- Final read-through of the program overview; update hour totals with the new
  labs.
- Decide the `tapha` env's fate: destroy (`lab-destroy.sh tapha
  --auto-approve`) once Phase 5 is done, or keep paused if more validation is
  expected.

## Sequencing & effort

Phases 0-1 first (they close the Week 4/5 story the current PRs started),
then 3 (cheap, self-contained), then 2, with Phase 5 scheduled once all
hardware-dependent labs are authored. Total: **~10-13 working days** of
authoring/validation effort, one hardware-spend day, and the standing ~$2/day
paused-env cost until the Phase 6 destroy decision.

## Per-lab definition of done

1. Written in the house style (navigation, ToC, decision frame, verification
   checklist, troubleshooting, takeaways, references).
2. Every command executed against a live environment (or explicitly marked
   doc-verified where hardware makes that impossible).
3. Findings folded back into the lab (validation note names the exact
   versions/template revisions used).
4. Cross-references updated (prev/next links, prereq pointers, week README).
5. Validation report in `docs/plans/` for anything that surfaced defects.
