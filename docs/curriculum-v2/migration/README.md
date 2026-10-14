# Curriculum reorganization evidence

Baseline: 05b142690db65b79b0a48339568bc5d9df7c8269, local source branch chore/remove-tooling-references.

- [Source inventory](source-inventory.json): all 144 tracked files, digests and destinations; 64 relocations and 80 retained paths.
- [Prerequisites and compatibility](PREREQUISITES.md): state transitions and source discrepancies.
- [Lab contract inventory](lab-contract-inventory.json): source sections for all 42 labs.
- [Baseline checks](baseline-checks.json): actual pre-relocation results.
- [V2 status](../STATUS.md): phase/evidence record.

All 9 foundation and 19 AI-workload labs exist; the other 14 labs are retained too. Original guides become source references. Infrastructure, examples, workflows and scripts stay in place except necessary validation/path changes. Ignored notes, credentials, QA material and other worktrees remain untouched.

An overly broad initial checker invocation included Terraform-templated cloud-init YAML, which is not standalone YAML. That parser error is recorded as an out-of-scope invocation. Existing default and all-tracked-curriculum checks pass, as does Mermaid parsing.

- [Final validation report](VALIDATION.md)
- [Local proposed PR description](PR-DESCRIPTION.md)
- [Path-edit ledger](path-edits.json) and [heading-link corrections](anchor-edits.json)
