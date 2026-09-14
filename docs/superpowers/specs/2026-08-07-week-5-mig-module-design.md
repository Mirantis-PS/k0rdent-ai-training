# Week 5 MIG Module — Design

**Date:** 2026-08-07
**Status:** Approved, pending live validation
**Scope:** Add hands-on NVIDIA Multi-Instance GPU (MIG) coverage to Week 5

---

## 1. Problem

Week 5 teaches every GPU-sharing mechanism *except* the one customers ask about
most in production: hardware partitioning. Time-slicing has a lab (5.1 Task 6),
KAI fractions have a lab (5.3), Run:ai fractions have a lab (5.4). MIG has only
prose.

The gap is not conceptual — `theory/5.1-gpu-scheduling.md` §5.4 already covers
MIG. The gap is that **no lab hardware in Week 5 can run MIG**. The standard
worker is `g5.12xlarge` (4× A10G); A10G is GA102-based and has no MIG support at
any driver version.

## 2. Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Real MIG on `p4d.24xlarge`, gated to the Advanced track | Matches the existing gate on Labs 5.13–5.16. No simulation; the week's labs are live-validated and this one will be too. |
| D2 | No new theory file — deepen `5.1` §5.4 instead | MIG theory already lives there. A new file would re-derive the profile diagram, the `mig-parted` ConfigMap, and the MIG-vs-time-slicing table, re-introducing the duplication commit `397e5aa` just removed. |
| D3 | DRA task is **required**, not optional | Week 4 Lab 4.9 motivates DRA with `"MIG slice 2g.20gb"`. Nothing in the curriculum exercises that claim today. |
| D4 | DCGM per-MIG metering stays **optional** | Real value, but additive; students opt in knowing the cost. |
| D5 | `p4d` (A100 40GB), not `p4de` (A100 80GB) | Cheaper ($32.77 vs $40.96/hr) and already the documented Advanced instance. The theory profile tables are wrong for *either* choice, so p4de buys no rewrite savings that justify the premium. |

## 3. Verified preconditions

Checked live against account `437775732836` on 2026-08-07:

| Check | Result |
|-------|--------|
| On-Demand P vCPU quota (`L-417A185B`), us-east-1 | 700 — p4d.24xlarge needs 96 |
| `p4d.24xlarge` availability | us-east-1 a, b, c, d |
| Pinned AMI `ami-00de3875b03809ec5` | Exists, `ubuntu-jammy-22.04-amd64-server-20260320` |
| Existing lab environment | None — validation requires `lab-provision.sh` first |

No quota increase or support ticket needed.

## 4. Deliverables

### 4.1 New file: `labs/lab-5.19-mig-partitioning.md` (~900 lines)

Structure mirrors Lab 5.11 exactly: Lab Navigation table → track ASCII diagram →
Prev/Current/Next → Duration/Type/Environment → TOC → Objective → Prerequisites →
k0rdent Context → Part 1 (concepts) → Tasks → Cleanup → Troubleshooting →
Verification Checklist → Key Takeaways → Next Lab.

**Required core — 190 min (~3.2h), ~$105/student**

| Task | Min | Content |
|------|-----|---------|
| 1 | 20 | Provision the p4d cluster; **re-install GPU Operator with `migManager.enabled=true`**. Lab 5.1's Helm values leave MIG manager off, so this cannot be a copy-paste. Stays on the validated `v25.3.0` pin. |
| 2 | 30 | Enable MIG via the `nvidia.com/mig.config` node label. Observe drain → GPU reset → driver daemonset restart. **Highest-risk task.** |
| 3 | 30 | `single` vs `mixed` strategy and how each renames device-plugin resources: `nvidia.com/gpu` vs `nvidia.com/mig-1g.5gb`. |
| 4 | 25 | Schedule workloads onto slices; confirm placement and per-slice UUIDs via `nvidia-smi -L`. |
| 5 | 25 | **Isolation proof:** deliberately OOM one slice, show its neighbour survives — the hardware guarantee time-slicing cannot make. Direct callback to Lab 5.3's "KAI does not enforce memory limits" warning. |
| 6 | 40 | **DRA.** Install `nvidia-dra-driver-gpu` with `gpuResourcesEnabledOverride=true`; write a `ResourceClaimTemplate` (`resource.k8s.io/v1`) against the `mig.nvidia.com` DeviceClass. Closes the Lab 4.9 loop. |
| *7* | *(30)* | *OPTIONAL — see below. Not counted in the 190 min.* |
| 8 | 20 | Live profile reconfiguration, revert to full GPUs, teardown. |

Required total: 20+30+30+25+25+40+20 = **190 min**.

**Optional — Task 7 (+30 min, ~$17):** DCGM per-MIG-device metric attribution,
wired to Lab 5.17's OTel export and the week's metering objective. Numbered 7 so
it sits *before* Task 8 in the document: it needs MIG still enabled, and Task 8
tears the partitioning down. Skipping it leaves task numbering contiguous for
everyone else.

### 4.2 Edit: `theory/5.1-gpu-scheduling.md` §5.4 (~+120 / −25 lines)

1. **Bug fix (load-bearing).** Lines 345–351 label a profile set "H100 MIG
   Profiles" (`7×1g.10gb`, `3×2g.20gb`, `2×3g.40gb`, `1×7g.80gb`). That is the
   generic **80GB-class** set. The lab runs on A100 **40GB**, where those
   profiles are invalid. Worse, the `mig-parted-config` example at lines 353–385
   hardcodes `"1g.10gb": 7`, which **cannot be satisfied on a 40GB A100** (max 4)
   and fails geometry validation.
2. **Add the A100-40GB profile table** the lab actually uses:

   | Profile | Compute slices | Memory | Max instances |
   |---------|---------------|--------|---------------|
   | `1g.5gb` | 1 | 5 GB | 7 |
   | `1g.10gb` | 1 | 10 GB | 4 |
   | `2g.10gb` | 2 | 10 GB | 3 |
   | `3g.20gb` | 3 | 20 GB | 2 |
   | `4g.20gb` | 4 | 20 GB | 1 |
   | `7g.40gb` | 7 | 40 GB | 1 |

3. **Add the GI/CI two-level model** — GPU Instance partitions memory + SMs;
   Compute Instance subdivides within a GI. This is what explains why `2g.10gb`
   exists and why profiles are not freely composable.
4. **Add placement/geometry rules** — why 7 slices cannot all be `1g.10gb`.
5. **Add reconfiguration semantics** — why changing profiles requires a GPU reset
   and is therefore a node-level operation, not a pod-level one.

### 4.3 Registration

| File | Change |
|------|--------|
| `week-5/README.md` | Learning objective; lab table row; Theory-to-Lab map (5.1 → +Lab 5.19); quiz topics |
| `labs/README.md` | Advanced-track table; ASCII track diagram; cost table; p4d gate note |
| `appendix/glossary.md` | MIG entry → link Lab 5.19, plus the MIG-vs-vGPU licensing correction in §4.4 |

**Pre-existing gap fixed in the same pass:** Labs **5.17** (`otel-telemetry-export`)
and **5.18** (`topograph-nvlink-topology`) exist on disk but appear in *neither*
README's lab table. Adding a 19th unlisted file would compound the drift; all
three get registered.

### 4.4 Licensing and entitlement

Every component in the required core is free to use — no licence, no NGC API key,
no entitlement. The only cost is AWS compute.

| Component | Licence | Entitlement |
|-----------|---------|-------------|
| MIG itself | Hardware/driver feature, included with the GPU | None |
| NVIDIA datacenter driver | Proprietary EULA, free to use | None |
| GPU Operator | Apache 2.0 | None |
| `nvidia-mig-manager` / `mig-parted` | Apache 2.0 | None |
| DCGM / `dcgm-exporter` | Apache 2.0 | None |
| `nvidia-dra-driver-gpu` | Apache 2.0 (donated to CNCF, KubeCon NA 2025) | None |
| `nvcr.io` images used | Public NGC catalog | No API key |

The lab states this explicitly, following the convention Lab 5.3 set with its
`| License | Apache 2.0 | NVIDIA Commercial |` row. It matters because the two
neighbouring labs are the opposite: Lab 5.4 needs a **Run:ai commercial licence**
and Lab 5.11 needs **NVIDIA AI Enterprise entitlement**. MIG is the only
hardware-isolated GPU sharing available at zero licence cost — a reader arriving
from 5.4 will assume otherwise unless told.

**MIG ≠ vGPU — correct both glossary entries.** vGPU *does* require a licence
(NVIDIA vGPU software / NVAIE), and **MIG-backed vGPU** (combining them) requires
the vGPU licence. Today the glossary's `MIG` entry omits that MIG is licence-free
and its `vGPU` entry omits that vGPU is licensed, so the page actively invites the
conflation. Both entries get one clarifying clause.

Attribution for upstream material is already handled by each lab's References
section; the config snippets quoted from NVIDIA docs are factual configuration,
not creative expression, and need no additional NOTICE.

## 5. Sequencing constraint (drives task order)

NVIDIA documents a known issue: *if the DRA kubelet plugin is deployed before a
MIG change, it must be manually restarted* — called out specifically for A100,
which is exactly p4d.

This dictates the ordering:

- Task 2 (enable MIG) runs **before** Task 6 (install DRA driver) → the issue is
  sidestepped by construction.
- Task 8 (reconfigure profiles) then **deliberately re-triggers** it. Students
  watch `ResourceSlice` objects go stale and must restart the kubelet plugin to
  see them republish.

The documented bug becomes the lab's clearest demonstration of why partitioning
is a node-level operation.

## 6. Risks

| # | Risk | Mitigation |
|---|------|------------|
| R1 | **Task 2 is where docs and reality diverge.** MIG enablement on k0s + GPU Operator 25.3.0 may not cleanly reset GPUs via the daemonset. | Live validation. If it fails, document a manual `nvidia-smi -mig 1` + node-reboot fallback as a first-class path, not a footnote. |
| R2 | **DRA GPU allocation is not officially supported.** The kubelet plugin is off by default (`gpuResourcesEnabledOverride=true`); NVIDIA officially supports only the ComputeDomain half. | State this plainly in Task 6 with a callout. If validation shows it unstable, demote Task 6 to optional — a one-line change to the required/optional split. |
| R3 | **Lab 4.9 is stale.** It targets `resource.k8s.io/v1beta1` and instructs enabling the `DynamicResourceAllocation` gate; DRA went GA in k8s 1.34 (`v1`, gate locked) and the driver needs v1.34.2+. | Lab 5.19 uses `resource.k8s.io/v1` and does **not** inherit 4.9's setup steps. Tracked separately as [issue #21](https://github.com/Mirantis-PS/k0rdent-ai-training/issues/21); when that lands, Lab 5.19's "do not follow Lab 4.9" warning can be deleted. |
| R4 | GPU Operator pin pressure. | Stay on `v25.3.0`. The week's warning against ≥25.10 on k0s (toolkit ignores `CONTAINERD_CONFIG`, drops `runc`, node goes NotReady) still applies. |
| R5 | Week 5 gains a 5th p4d-gated lab, raising the cost ceiling. | Explicit note in the `labs/README.md` cost table. |

## 7. Validation plan

Draft first, then validate in one focused pass so the p4d meter only runs during
confirmation, not authoring.

| Step | Wall time | Cost |
|------|-----------|------|
| `lab-provision.sh` — bastion + k0rdent mgmt (t3.2xlarge) + NAT | 30–45 min | ~$0.40/hr |
| GPU `ClusterDeployment`, p4d.24xlarge worker | ~15 min | $32.77/hr begins |
| Core run, Tasks 1–6, 8 | ~3.2h | |
| Iteration budget for Task 2 | ~1–1.5h | |
| **Total p4d exposure** | **~4.5–5h** | **~$150–165** |
| **All-in** | | **~$155–175**, up to ~$200 if R1 materialises |

Account `437775732836` is **shared** (other teams' instances are running).
Teardown discipline is mandatory: delete the `ClusterDeployment` before
destroying the management cluster, or CAPI-managed AWS resources orphan.

Every command and expected-output block is marked unverified until replaced with
a real capture. The lab does not merge carrying unverified blocks.

## 8. Success criteria

- [ ] A student on p4d can partition an A100, run isolated workloads on slices, allocate a slice through DRA, and revert — following only the lab text.
- [ ] Every expected-output block is a real capture from the validation run.
- [ ] Theory §5.4 profile tables are correct for the hardware the lab uses.
- [ ] Labs 5.17, 5.18, 5.19 all appear in both README lab tables.
- [ ] `scripts/check-mermaid.mjs` passes; lychee `--offline` resolves every internal link.
- [ ] Cost impact is stated where students will see it before provisioning.

## 9. Out of scope

- Refreshing Lab 4.9 for the DRA v1 API — tracked as [issue #21](https://github.com/Mirantis-PS/k0rdent-ai-training/issues/21).
- MIG on `p4de`/`p5`; vGPU; MPS.
- Any change to the `g5.12xlarge` standard lab path.
- Moving the 6-week curriculum file (pre-existing TODO in the week README).
- **Adding a repository `LICENSE`** — see §10. Needs a business decision, not a
  content decision.

## 10. Raised, not resolved: the repo has no LICENSE

Independent of this module, and worth a separate decision:

`git ls-files` shows exactly three tracked root-level files — `README.md`,
`.gitignore`, `.github/workflows/quality.yml`. There is no `LICENSE`, `NOTICE`,
`COPYRIGHT`, or `CONTRIBUTING` anywhere in the repository.

Meanwhile `README.md` opens with *"Fork this repository (or click 'Use this
template'), then clone YOUR copy."* With no licence declared, the default is **all
rights reserved**: forkers receive no grant of rights, which contradicts the
fork-first onboarding the README depends on. The remote is
`github.com/Mirantis-PS/k0rdent-ai-training`.

Choosing the licence is a Mirantis business/legal call — plausible options are
internal-proprietary with an explicit internal-use grant, `CC-BY-4.0` (common for
curriculum prose), or `Apache-2.0` (consistent with the tooling the curriculum
teaches, and simplest given the repo also ships Terraform and shell scripts). A
mixed approach — `CC-BY-4.0` for `curriculum/`, `Apache-2.0` for
`lab-infrastructure/` and `scripts/` — matches how the content actually splits.

No action taken here.
