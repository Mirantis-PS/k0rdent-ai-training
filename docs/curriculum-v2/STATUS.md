# V2 status and decision record

Updated 2026-10-14. **P0 and P1 complete with local static evidence. P2–P5 are not complete.** This record distinguishes reorganization from pedagogical enrichment and runtime qualification.

## Actual environment

- Repository: /Users/moustaphagueye/k0rdent-ai-training
- Source branch: chore/remove-tooling-references
- Source SHA: 05b142690db65b79b0a48339568bc5d9df7c8269
- Work branch: refactor/curriculum-v2-structure
- Source working tree: clean; no pre-existing tracked/untracked edits. Ignored local notes, credential/config files, QA material and other worktrees preserved.
- P0 commit: 7df48c77ce41749e8979317ee1ccb529701d87d8
- Pure relocation commit: 34aa897055b8ec1bd78383fd80a5ca95eb284612
- Path repair commit: 606cc5d7dba9c14e85132400d23a5e1f6192b7db
- Navigation/coverage commit: 1be482b01491c03c04020a1c66df5733523c2374
- Final reporting commit: the commit containing this update; resolve with git log -1 -- docs/curriculum-v2/STATUS.md.
- Push / PR / merge: none.
- Cloud resources provisioned or changed: none. Existing remote resources were not inspected.
- Labs executed: none; local static checks and example unit tests only.
- Product k0rdent AI sources: still awaited from owner.

## Phases

| Phase | Scope | Authorization | Actual state | Evidence |
|---|---|---|---|---|
| P0 | Baseline and source inventory | Authorized | Complete | [144-file inventory](../../curriculum/migration/source-inventory.json), [42-lab contracts](../../curriculum/migration/lab-contract-inventory.json), [prerequisites](../../curriculum/migration/PREREQUISITES.md) |
| P1 | Conservative reorganization | Authorized | Complete; static-checked | [Validation report](../../curriculum/migration/VALIDATION.md), [learning path](../../curriculum/learning-paths/core.md), four milestone commits above and final reporting commit |
| P2 | Full pedagogical enrichment | Requires next-lot authorization | Pending | All 40 [coverage requirements](COVERAGE-MATRIX.md) retained; source candidates identified, new exercises not implemented |
| P3 | Product integration | Authorization and authoritative sources required | Source-dependent work blocked | Distribution/version, native/integrated/optional boundaries and interfaces remain unsourced |
| P4 | Affordable GPU qualification | Authorization, hardware access and budget required | Live work blocked | GPU-1/GPU-2 candidates and test obligations retained; current four-GPU source baseline unchanged |
| P5 | Independent pilot/review | Authorization and independent learner required | Pending | New capstone, measured active time/cost and independent reproduction remain required |

## Decisions and remaining questions

Keep the course centered on k0rdent/k0rdent AI, preserve all source material, organize by competency, retain English learning material and aim for majority active learning. Current module folders do not alter lab lifecycle. The source management upgrade and KAI version transition remain in order. No mandatory BMaaS → VMaaS → KaaS chain is added.

P1 preserves historical labels and claims inside source bodies, with path and heading-link repairs only. Original schedules and broader capstone are source references, not new course promises. The learning path records older prerequisite-label conflicts and the audit-before-teardown rule. Scope and rationale are in [PREREQUISITES.md](../../curriculum/migration/PREREQUISITES.md).

Open for later phases: active study-hour budget; GPU spending ceiling, regions/quotas/concurrency; exact k0rdent AI distribution/docs; supported model/runtime/dtype; specialized hardware access; certification modality and pilot learner. None prevented the completed structural work. Current operational compatibility, external web links, remote CI and live GPU behavior have not been revalidated.

## Next action

Owner review of the local branch. P2 can begin after explicit authorization. Publishing, paid execution and merging remain unrequested. A proposed PR description is saved locally at [PR-DESCRIPTION.md](../../curriculum/migration/PR-DESCRIPTION.md); no PR was opened.

## Historical milestone log

The entries below describe status at each milestone, not the current phase table.

## Execution record — 2026-10-14, P0

Owner explicitly authorized P0/P1 and local commits only. Actual checkout: /Users/moustaphagueye/k0rdent-ai-training. Source SHA: 05b142690db65b79b0a48339568bc5d9df7c8269; clean tracked/untracked working tree on chore/remove-tooling-references. Created refactor/curriculum-v2-structure without replacing a branch. Origin matches Mirantis-PS; no fetch required. Ignored local files and other worktrees retained. No prior repository AGENTS file; inherited parent file contains only empty memory context. Installed the supplied section as AGENTS.md.

P0 complete: 144-file digest inventory, 42-lab contract inventory, 28/28 historical labs located, prerequisite/lifecycle record and passing baseline curriculum/Mermaid checks under curriculum/migration/. P1 pending. P2–P5 unchanged. No runtime, cloud, push, PR or merge actions.

Decision: work on the requested branch in the clean checkout. Preserve numbered labels inside source bodies as provenance; change canonical paths and navigation only.

### P1 relocation and path repair

P0 commit: 7df48c77ce41749e8979317ee1ccb529701d87d8. Pure relocation commit: 34aa897055b8ec1bd78383fd80a5ca95eb284612; 64 renames, 100% similarity, zero inserted/deleted lines. All 144 destination digests matched baseline before commit. Repaired local links/images, inline source paths and repository paths independently. The relocated-source checker passes (87 checked paths, zero errors); diff whitespace passes. Historical entry-point stubs and original-course index retain discoverability. Module navigation and final validation remain in progress. Existing source prerequisites and compatibility discrepancies are recorded in curriculum/migration/PREREQUISITES.md.

### P1 navigation milestone

Created eight module indexes, eight extension indexes, curriculum/root entry points and a prerequisite-aware core path. All 40 coverage rows now point to preserved source candidates or explicit new-work obligations; none is credited with new runtime validation. Reconciled all 28 historical IDs with canonical paths. Repaired 30 pre-existing heading links (see anchor-edits.json); missing compliance-pack headings point to the existing verification checklists without adding procedures.

Checks passed: 144 preserved sources; 1,569 unchanged source code fences apart from explicit repository paths; 1,533 local links/images/anchors; 55 Mermaid blocks; 14 existing example unit tests; diff whitespace. Normalized original Markdown comparison found no non-path content changes, excluding the maintenance guide whose checker instructions were updated. Workflows, infrastructure scripts/Terraform and example code have no diff from baseline. Final evidence/status report remains to be committed.
