# P0/P1 validation report

Date: 2026-10-14. Source SHA: 05b142690db65b79b0a48339568bc5d9df7c8269. Branch: refactor/curriculum-v2-structure.

## Commits and preservation

| Milestone | Commit | Evidence |
|---|---|---|
| P0 inventory and handoff | 7df48c77ce41749e8979317ee1ccb529701d87d8 | 144 tracked files, 42 labs, 28/28 historical Week 1/5 IDs; baseline clean |
| Pure relocation | 34aa897055b8ec1bd78383fd80a5ca95eb284612 | 64 100%-similar renames, zero line additions/deletions; all 144 source digests retained |
| Path repair | 606cc5d7dba9c14e85132400d23a5e1f6192b7db | Local/image/inline path corrections and historical entry points; [edit ledger](path-edits.json) |
| Navigation and coverage | 1be482b01491c03c04020a1c66df5733523c2374 | Eight modules, eight extension indexes, core path, all 40 requirements and 28 historical mappings; [anchor ledger](anchor-edits.json) |
| Final evidence | Commit containing this report | Current inventory digests, status and proposed PR description |

Every baseline source has one canonical destination in [source-inventory.json](source-inventory.json). All original Markdown was compared after normalizing only explicit path/link targets: no other content changes, except the maintenance guide's updated validator instructions. Original source guides, theory, assessments, images and optional content remain present, not only in Git history. The two handoff reference designs remain byte-for-byte copies.

## Checks actually run

Python checks used an isolated local environment at /tmp/k0rdent-v2-validation-20261014 with PyYAML 6.0.2. No repository runtime dependency was changed. Commands below use python3 as the equivalent environment executable.

| Check | Command | Result |
|---|---|---|
| Curriculum snippets and files | python3 scripts/check-curriculum.py | PASS; 111 local files, zero errors (includes local test bytecode files) |
| Source preservation and navigation | python3 scripts/check-curriculum-migration.py | PASS; 144 sources, 1,569 original code fences, 1,552 local links/images/anchors, zero errors |
| Mermaid | node scripts/check-mermaid.mjs | PASS; 55 blocks |
| Training helpers | python3 -m unittest discover -s curriculum/examples/tests -v | PASS; 7 tests |
| Telemetry helpers | python3 -m unittest discover -s curriculum/examples/telemetry/tests -v | PASS; 7 tests |
| Whitespace | git diff --check and git diff --cached --check | PASS |
| Scope | git diff SOURCE -- .github lab-infrastructure/scripts lab-infrastructure/terraform curriculum/examples | Empty |

The [baseline results](baseline-checks.json) include an overly broad early invocation that parsed Terraform-templated cloud-init as standalone YAML and failed. The correct existing default scope and all tracked curriculum files passed before relocation. This is not hidden as a successful test.

The custom migration check is read-only and requires source/relocation history. It audits tracked Markdown links, image paths and headings; archived handoff input remains unchanged and is excluded from current navigation checking. It does not contact GitHub or verify external URLs. No current same-repository blob/raw URL paths were found outside the archived design input; explicit checkout paths were inspected separately.

## Review findings and boundaries

- 30 pre-existing stale heading targets were repaired without changing procedures. In two older operations labs, references to missing compliance-pack sections now point to the available verification checklist; the absent procedures were not invented.
- Historical prerequisite-label mismatches, the multi-worker KAI gate and audit-before-teardown conflict are recorded in [PREREQUISITES.md](PREREQUISITES.md). The new path keeps prerequisite and resource state explicit; P2/P3 must resolve substantive source issues before claiming full V2 runtime readiness.
- Only the validation script's default directories and its documentation changed outside source/navigation material; infrastructure, workflows and example implementations have no diff.
- The complete-V2 backlog remains in [COVERAGE-MATRIX.md](../../docs/curriculum-v2/COVERAGE-MATRIX.md). P2–P5 are not complete.
- No live labs, product compatibility checks, cloud provisioning, pricing/availability checks, remote CI or independent pilot ran. No resource was created, destroyed or remotely inspected; existing user resources remain unassessed.
- No push, PR publication or merge. Existing ignored local credentials/notes/QA files and other worktrees were left in place.

## Reproduce the local checks

Run the commands above from the repository root with PyYAML installed for the existing curriculum checker and the existing scripts/package.json dependencies available for Mermaid. The migration checker itself uses only Python's standard library. Follow the [learning path](../learning-paths/core.md) for course navigation; these static checks are not evidence of live lab execution.
