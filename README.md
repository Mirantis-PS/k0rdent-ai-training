# k0rdent AI Infrastructure Training

A hands-on curriculum for infrastructure engineers learning to deploy, understand and operate AI services with k0rdent. The material is organized into competency domains, with a separate learning path that preserves lab prerequisites and resource lifecycle.

**Start with the [learning path](curriculum/learning-paths/core.md)** after reviewing the [infrastructure prerequisites](curriculum/overview/prerequisites.md). Browse the [eight curriculum domains](curriculum/README.md) or [optional extensions](curriculum/extensions/README.md).

## Current scope

This branch completes the P0/P1 structural work for V2: inventory, preservation, relocation and navigation. Existing lab bodies and known-good settings are retained. New learning experiences, authoritative k0rdent AI product integration, affordable GPU profiles and an independent pilot remain future phases. No live lab validation is implied by the reorganization.

The preserved GPU baseline uses one four-GPU worker; a cheaper one-GPU variant is not yet qualified. Follow each lab’s compatibility, access and cleanup requirements. Course duration and active-learning percentage will be measured during the pilot.

## Find material

- [Curriculum modules](curriculum/README.md) and [core learning path](curriculum/learning-paths/core.md)
- [Original course index](curriculum/references/original-course.md), including all 42 historical labs
- [Original root guide](curriculum/references/source-guides/original-root.md), preserving its full syllabus and reference information
- [Infrastructure scripts and Terraform](lab-infrastructure/README.md)
- [Troubleshooting reference](lab-infrastructure/docs/troubleshooting.md)
- [Migration evidence](curriculum/migration/README.md), [coverage matrix](docs/curriculum-v2/COVERAGE-MATRIX.md), and [execution status](docs/curriculum-v2/STATUS.md)

## Repository layout

- curriculum/modules/: eight competency domains
- curriculum/learning-paths/: prerequisite-aware navigation
- curriculum/extensions/: optional preserved specializations
- curriculum/references/: historical source guides and assessments
- curriculum/migration/: inventory, provenance and validation evidence
- lab-infrastructure/: existing operational scripts and Terraform
- docs/curriculum-v2/: specification, backlog and execution record

Historical week entry points redirect to the preserved guides and current navigation. Each lab has one canonical body.
