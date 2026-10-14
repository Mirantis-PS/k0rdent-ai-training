# Source preservation and candidate mapping

**Not an inventory of the current checkout.** These 28 historical lab identifiers come from the earlier design. Verify actual source paths, titles, existence and additional files at the chosen SHA. All files are to be preserved, even when not listed here. Resolve mismatches explicitly rather than silently manufacturing or dropping labs.

## P1: preserve each lab whole

Canonical destination is independent of learning-path order. Read the actual lab contract and lifecycle dependencies before introducing a new executable order. In particular, preserve any necessary management upgrade, KAI version transition and cleanup sequence. Specialized labs may reside in a core domain while remaining elective.

| Historical ID | Historical subject | Candidate canonical destination | P1 treatment | Verified source → target / evidence |
|---|---|---|---|---|
| 1.1 | Provision k0rdent | `curriculum/modules/platform-bootstrap/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 1.2 | Explore UI | `curriculum/modules/platform-bootstrap/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 1.3 | AWS provider | `curriculum/modules/platform-bootstrap/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 1.4 | Production configuration / RBAC | `curriculum/modules/operations/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 1.5 | Managed cluster | `curriculum/modules/platform-bootstrap/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 1.6 | KOF | `curriculum/modules/operations/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 1.7 | Multi-cluster services | `curriculum/modules/ai-service-delivery/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 1.8 | Upgrade | `curriculum/modules/operations/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 1.9 | API audit | `curriculum/modules/operations/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.1 | GPU cluster setup | `curriculum/modules/gpu-systems/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.2 | Service Catalog | `curriculum/modules/ai-service-delivery/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.3 | KAI Scheduler | `curriculum/modules/gpu-allocation/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.4 | Run:AI | `curriculum/extensions/licensed-orchestration/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.5 | vLLM inference | `curriculum/modules/inference-and-data/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.6 | GPU troubleshooting | `curriculum/modules/operations/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.7 | Jupyter | `curriculum/extensions/ml-platforms/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.8 | Vector database | `curriculum/extensions/ml-platforms/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.9 | Kubeflow | `curriculum/extensions/ml-platforms/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.10 | MLflow | `curriculum/extensions/ml-platforms/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.11 | FIPS | `curriculum/extensions/compliance/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.12 | Cluster Templates | `curriculum/modules/ai-service-delivery/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.13 | TensorRT-LLM | `curriculum/extensions/advanced-inference/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.14 | Slurm | `curriculum/extensions/hpc/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.15 | RDMA multi-cloud | `curriculum/modules/distributed-ai/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.16 | Distributed training | `curriculum/modules/distributed-ai/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.17 | Telemetry export | `curriculum/modules/operations/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.18 | Topology/NVLink | `curriculum/modules/gpu-systems/` | Preserve whole; links only as necessary | Pending baseline inspection |
| 5.19 | MIG | `curriculum/modules/gpu-allocation/` | Preserve whole; links only as necessary | Pending baseline inspection |

## Other mandatory preservation

Inventory and retain every source README, overview, prerequisite, theory, assessment, image, manifest, chart, script, resource, compatibility note, source guide and historical validation artifact. Retain all content outside Weeks 1 and 5 too. There is no blanket authorization to delete “irrelevant” content or retain it only through Git history.

| Source domain | Target intent | Rule |
|---|---|---|
| BMaaS / bare-metal content | extensions/bare-metal | Not a mandatory stage; preserve complete content. |
| VMaaS / KubeVirt / virtualization | extensions/virtualization | Keep GPU passthrough/NUMA depth as a gated extension. |
| KaaS / advanced Kubernetes / networking | extensions/advanced-kubernetes and relevant domain references | Classify by actual content; no forced installation stage. |
| Week 6 operations, identity, tenancy and capacity | operations | Preserve incomplete status and prerequisites. |
| Existing final project | capstone | Preserve original; new assessment is a later phase. |
| Existing root/weekly guides | references/source-guides and original-course index | Preserve historical content and provenance. |
| lab-infrastructure, scripts, workflows | Existing location by default | No incidental runtime change; review necessary path edits. |

## Required real inventory columns

`source_commit`, `source_path`, `source_digest`, `destination_path`, `content_type`, `historical_id`, `treatment`, `reason`, `relocation_commit`, `link_edit_commit`, `verification_result`.

At pure relocation, file contents must match the baseline digests. At later link/navigation edits, retain a scoped reviewed diff. Track non-canonical compatibility stubs as new files, not as preservation replacements for lost original contents.

## Later derivatives

P2 may derive smaller experiences from 5.1, 5.5, 5.15 and 5.16 while preserving originals and provenance. A low-cost variant is new behavior, not a validated rename. Record which original sections each new lab reuses and what has changed.
