# Proposed PR title

Reorganize the curriculum into competency domains while preserving all source material

## Description

The existing week-based navigation obscures the intended k0rdent AI learning domains and makes optional infrastructure stages appear mandatory. This change adds eight competency modules, optional extension indexes and a separate prerequisite-aware learning path while retaining every original source file and all 42 labs.

The branch records source 05b142690db65b79b0a48339568bc5d9df7c8269, moves 64 files in a byte-identical commit, then repairs paths and heading links separately. Historical guides remain accessible through an original-course index and compatibility entry points. Operational scripts, Terraform, example code, workflow settings and runtime pins remain unchanged. The existing validator now follows the relocated directories; a separate read-only migration checker verifies preservation and navigation.

## Validation

- All 144 baseline files accounted for and byte-identical at relocation.
- Original Markdown content comparison: only path/navigation changes, apart from maintenance-check documentation.
- 1,569 original source code fences preserved apart from explicit repository paths.
- Curriculum snippet/local-link check and migration link/anchor/image check pass.
- 55 Mermaid blocks parse; 14 existing training/telemetry example tests pass.
- Git diff whitespace checks pass.

## Scope and limitations

P0/P1 only. All 40 complete-V2 requirements remain tracked. No new AI pedagogy, product APIs, runtime upgrades, one-GPU qualification, cloud execution or independent pilot is claimed. Existing prerequisite-label discrepancies and specialized hardware gates are documented in the learning path. This is a local description draft; it has not been published.
