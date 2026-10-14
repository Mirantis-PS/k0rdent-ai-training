# V2 execution plan

## Authorization and sequencing

**Authorization update2026-10-14: P0/P1 completed; owner explicitly authorized P2 enrichment and local commits.** P3–P5 remain the intended complete V2, not silently authorized code/runtime/cloud changes. Each later lot requires explicit owner authorization; paid execution and publishing require separate permission. Keeping later lots pending does not remove them from scope.

Do not mix phase completion with overall project completion. Do not ask the owner to reconfirm already decided constraints. Work through independently achievable tasks and report blockers with exact evidence. Follow existing Git workflow/instructions; if an existing branch or user changes conflict, choose a non-destructive worktree approach where possible and report it rather than overwriting anything.

## P0 — Establish the real baseline

Actions: read repository instructions; inspect project path/remotes/status; capture the actual source SHA; inventory all tracked content, paths and digests; inspect Weeks 1/5 and all other content; record prerequisites, state transitions, known-good versions and validation notes. Create the dedicated branch safely. Establish the source of truth documents in this repository without clobbering existing files. Inspect the historical proposals only as design context, not proven repository state.

Deliverables: source inventory, source-to-target candidate mapping, prerequisite/state graph, baseline compatibility record, updated STATUS. Record actual filenames and any difference from the 28 historical IDs. No requirement to install tools or access AWS during inventory.

Exit: owner work intact, baseline traceable, every tracked source file accounted for, branch exists locally and differences are understood. Report exact network/authentication errors if a fetch is required; do not turn a failed network operation into a fictitious successful clone.

## P1 — Reorganize without functional changes

Actions: relocate using Git moves; preserve old guides and useful link entry points; correct references in separate changes; retain operational infrastructure/scripts in place unless a move is essential; build module navigation, the new learning path and original-course index; preserve executable prerequisite and cleanup order even when folder order changes. Keep each lab body whole in this lot. Carry all concepts and future adaptations into the coverage backlog with an explicit status.

Recommended commits:
1. Inventory, source SHA, mapping and V2 decision documents.
2. Pure content relocation with unchanged file contents.
3. Necessary path/link corrections and compatibility entry points.
4. Module pages and learning paths.
5. Validation evidence and status/report updates.

Checks: source-to-target completeness; digest preservation at the relocation commit; source assets and historical 28-lab mapping; source-guide conservation; duplicate content review; Markdown links/anchors/images; repository-root/raw GitHub links and checkout paths; shell/code-block/workflow references; `git diff --check`; clean and scoped final diff. Use existing checks and a small appropriate validator if needed; do not substitute a generic migration tool for the repository change.

Exit: no source loss; paths and navigation checked; functional versions/settings unchanged; uncertainties and unexecuted tests explicitly listed. Deliver actual local commits, source SHA, branch, diff summary, validation results and a proposed PR description. **Do not push or open the PR without permission.**

P1 is successful reorganization, not complete pedagogical or GPU validation.

## P2 — Implement the pedagogical V2

Authorization: owner approval for content enrichment beyond the reorganization.

Actions: inspect existing material against every coverage row; reuse and reshape before writing replacements; add missing just-in-time concepts and exercises; derive the first-response, memory/concurrency, sharing/queue, miniature distributed, storage/cache and measured-performance experiences; integrate them with declarative k0rdent delivery and operational incidents. Do not create generic filler text for an empty module. Preserve originals and provenance when splitting or deriving labs. Add learner/instructor separation, decreasing scaffolding, a fault bank, assessment rubric and capstone evidence requirements.

Deliverables: English modules/chapters/labs/solutions with stable IDs; a coherent stateful learner path; per-lab metadata, prerequisites, objectives, evidence and cleanup; explicit references to original content; relevant primary, versioned technical sources; coverage rows linked to actual sections and checks.

Checks: every initial AI topic is introduced, practiced at the appropriate level and revisited; no accidental generic AI or tool-catalog course; majority active-learning target made measurable; no unsupported product claims; hardware requirements explicit; output examples labeled as examples; draft-versus-executed status preserved. Concepts and proposed lab instructions can be drafted before hardware access; do not call them runtime-validated.

Exit: complete educational draft with traceable coverage, not an empty outline. Unknown product-specific steps remain scoped placeholders tied to P3, not plausible invented commands. No claims that learners are fabric experts without advanced hardware evidence.

## P3 — Integrate actual k0rdent AI product sources

Gate: target distribution/version and authoritative owner-provided sources.

Actions: classify native/integrated/optional/unsupported features; establish the exact installation and lifecycle route; identify resource ownership; map service catalog, model serving, templates, cluster management, identity, metering, scheduling and device allocation to actual supported interfaces; update relevant exercises with real commands and rollback; resolve compatibility with existing known-good configuration.

Deliverables: product-feature/source matrix and versioned compatibility matrix, updated labs, documented integration boundaries, tests or explicit runtime gates. Changes of product/runtime/driver must be separated from structural movement and justified.

Exit: product claims traceable to sources; procedures no longer invented or ambiguously branded. Missing sources block only dependent material; they do not justify claiming completion or stopping unrelated writing.

## P4 — Qualify affordable GPU profiles and real executions

Gates: explicit hardware budget, account/region/quota permission, runtime combinations and permission to incur costs.

Actions: qualify CPU/GPU-1/GPU-2 separately. Begin with a small supported model and one candidate GPU. Verify the bootstrap → first inference → memory → sharing → performance → cleanup chain. Add an alternative only after a real compatibility test. Recalibrate source assumptions about replicas/GPU count; preserve the original multi-GPU path. Execute a genuine two-worker NCCL/training path and verify its transport. Test specialized capabilities only on authorized compatible hardware. Record real provisioning outcomes; no preflight can be labeled a capacity guarantee.

Evidence: commit, lab ID, model/image/chart/driver/product versions, actual hardware, region/AZ, timestamp, commands, logs, metrics, pass/fail, cost scope, cleanup and retained resources. Distinguish pricing estimates from observed billed resource-hours.

Checks: no hidden expensive fallback; no resource leak; no simulator represented as GPU/RDMA practice; no public unauthenticated endpoint; no secrets in Git; bounded reversible fault injection; reproducible benchmark workload; required hardware capability demonstrated rather than inferred from a family name.

Exit: core runtime claims carry execution evidence. A second person independently reproducing is a distinct next state. Without authorized access, deliver documented candidates and exact test protocols, not invented pass results.

## P5 — Independent pilot and release review

Gates: independently participating engineer and agreed review process.

Actions: run the course with a learner who did not write it; measure active time, waiting, help needed, GPU-hours, failures and quality of explanations; run the new-incident capstone; fix findings and repeat affected checks. Reconcile all coverage and preservation rows. Define specialized endorsements separately from common-course completion.

Exit: independently reproduced core path; remaining limitations visible; sustainable cost and cleanup evidence; complete teacher/learner materials; final source/target mapping; owner review. Release/publishing still requires explicit permission.

## Scope accounting rules

Use: pending / in-progress / drafted / static-checked / documented-compatible / executed / independently-reproduced / blocked / deferred. Include evidence path or reason in every non-pending state. A source lab may be reported-tested historically without having been re-executed at the current SHA. Do not flatten those distinctions into a single green check.

At each stop report the actual phase and next authorized action. `P1 done; P2–P5 pending` is honest and useful. `V2 complete` after file moves is incorrect.
