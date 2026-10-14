# k0rdent AI curriculum

**P2 educational draft available:** [guided learner path](learning-paths/pedagogical-v2.md), with new labs, concept lessons and separate instructor guidance. Product-source integration, GPU execution and independent pilot remain gated.

The course is organized by competency. Start with the [core learning path](learning-paths/core.md), which preserves the source prerequisite and cleanup sequence across these folders.

**Current release state:** P0/P1 reorganize existing material. P2 adds an educational draft; product integration, affordable GPU qualification and independent pilot remain P3–P5. Historical lab bodies retain their labels and validation limitations. There is no fixed weekly schedule or newly validated course-duration promise.

| Domain | Preserved focus |
|---|---|
| [Platform bootstrap](modules/platform-bootstrap/README.md) | Provision k0rdent, configure the provider and establish management/workload foundations. |
| [GPU systems](modules/gpu-systems/README.md) | Inspect and configure the GPU runtime and topology using the preserved source labs. |
| [GPU allocation](modules/gpu-allocation/README.md) | Study scheduling, admission, sharing and hardware partitioning. |
| [Distributed AI](modules/distributed-ai/README.md) | Study communication and training, with the original advanced labs retained. |
| [Inference and data](modules/inference-and-data/README.md) | Reuse the existing vLLM service and inference architecture material. |
| [AI service delivery](modules/ai-service-delivery/README.md) | Use the preserved catalog, multi-cluster service and cluster-template labs. |
| [Operations](modules/operations/README.md) | Retain security, KOF, upgrade, audit, troubleshooting, telemetry and fleet operations. |
| [Capstone](modules/capstone/README.md) | Preserve the original end-to-end project and its broader prerequisites. |

- [Infrastructure prerequisites](overview/prerequisites.md)
- [Optional extensions](extensions/README.md)
- [Original course and all historical labs](references/original-course.md)
- [Preservation and validation evidence](migration/README.md)
- [Complete V2 requirements](../docs/curriculum-v2/MASTER-SPEC.md) and [phase status](../docs/curriculum-v2/STATUS.md)

The future design targets majority active practice and mostly one-GPU exercises. The preserved current GPU contract still uses a four-GPU worker and specialized exercises retain their hardware requirements.
