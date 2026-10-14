# V2 status and decision record

**Initialized 2026-10-14. No repository work is claimed by this handoff.**

## Actual environment

- Repository path: not inspected in this session.
- Source SHA: not captured.
- Working-tree state: unknown.
- Branch created: no.
- Commits created in target repository: none.
- Push / PR / merge: none.
- Cloud resources provisioned: none.
- Labs executed: none.
- Product k0rdent AI sources: awaited from owner.

## Phases

| Phase | Scope | Authorization | Actual state | Evidence |
|---|---|---|---|---|
| P0 | Baseline and source inventory | Authorized | Pending | None |
| P1 | Conservative reorganization | Authorized | Pending | None |
| P2 | Full pedagogical enrichment | Requires explicit next-lot authorization | Pending, preserved in spec | None |
| P3 | Product integration | Authorization and product sources required | Blocked for source-dependent work | None |
| P4 | Affordable GPU qualification | Authorization, access and budget required | Blocked for live work | None |
| P5 | Independent pilot / review | Authorization and learner required | Pending | None |

## Decisions to preserve

The owner wants a k0rdent/k0rdent AI course, not generic AI training with product branding. No weeks or mandatory BMaaS/VMaaS/KaaS sequence. Keep all existing content, especially Weeks 1 and 5. Week 5 is the main foundation for practical work. Introduce initial AI-infrastructure subjects around the platform with majority active work. Hardware availability and cost are first-class constraints. Work directly on the checkout, not via a migration-script deliverable. Do not invent product functionality or imply runtime tests that have not happened.

## Deferred decisions

Study-hour budget, GPU spend ceiling/concurrency/regions, actual k0rdent AI version/sources, exact validated model/runtime/dtype, advanced hardware access and certification modality remain open. These do not block safe inventory, content moves, navigation or detailed backlog capture.

## Update format after each milestone

Record date, phase, source/current SHA, actual files/commits, requirements affected, checks actually run, failures, blockers, residual resources and next authorized action. Preserve a short chronological record. No “done” without an evidence reference.

## Current handoff verification

The handoff package itself includes the two prior design files copied byte-for-byte, a 28-row historical preservation map and 40 coverage requirements. This is document packaging, not a check of source-code conservation or GPU behavior. See the package manifest for file digests.

## Execution record — 2026-10-14, P0

Owner explicitly authorized P0/P1 and local commits only. Actual checkout: /Users/moustaphagueye/k0rdent-ai-training. Source SHA: 05b142690db65b79b0a48339568bc5d9df7c8269; clean tracked/untracked working tree on chore/remove-tooling-references. Created refactor/curriculum-v2-structure without replacing a branch. Origin matches Mirantis-PS; no fetch required. Ignored local files and other worktrees retained. No prior repository AGENTS file; inherited parent file contains only empty memory context. Installed the supplied section as AGENTS.md.

P0 complete: 144-file digest inventory, 42-lab contract inventory, 28/28 historical labs located, prerequisite/lifecycle record and passing baseline curriculum/Mermaid checks under curriculum/migration/. P1 pending. P2–P5 unchanged. No runtime, cloud, push, PR or merge actions.

Decision: work on the requested branch in the clean checkout. Preserve numbered labels inside source bodies as provenance; change canonical paths and navigation only.

### P1 relocation and path repair

P0 commit: 7df48c77ce41749e8979317ee1ccb529701d87d8. Pure relocation commit: 34aa897055b8ec1bd78383fd80a5ca95eb284612; 64 renames, 100% similarity, zero inserted/deleted lines. All 144 destination digests matched baseline before commit. Repaired local links/images, inline source paths and repository paths independently. The relocated-source checker passes (87 checked paths, zero errors); diff whitespace passes. Historical entry-point stubs and original-course index retain discoverability. Module navigation and final validation remain in progress. Existing source prerequisites and compatibility discrepancies are recorded in curriculum/migration/PREREQUISITES.md.
