# Strip NCP Validation Framing from Curriculum Implementation Plan

**Goal:** Refocus the curriculum repo on *learning k0rdent + AI infrastructure concepts*. Strip the NCP certification/validation framing — that work belongs in the separate `ncp-compliance-pack` repo. Keep the technical content from the 10 new labs (it's pedagogically valuable); rewrite the framing so a learner who has never heard of "NCP" or "DGXC" can still understand why each concept matters.

**Architecture:** Three-phase cleanup. (1) Remove or repurpose the two NCP cross-reference docs at the curriculum root. (2) Mechanically edit each of the 10 new labs to strip NCP-specific framing while preserving the technical body. (3) Reset the pending task list to reflect the concept-driven framing.

**Tech stack:** Markdown editing. No code. No tests. Verification = visual review + verifying `grep`-able patterns disappear from labs.

**Assumptions made (since the user said "execute"):**
1. Keep a single `Domain:` tag in the tag block (1-column, no Req IDs) for navigation
2. Delete `ncp-domain-tagging.md` outright — no stub
3. Keep Mirantis product-name references (Mirantis k0rdent AI, KCM, KSM, KOF, etc.) — they are legitimate product naming, not compliance positioning
4. Lab 4.10 BYOIP/PCI/MACsec: reframe as **"Case Study: AI cloud provider interconnect patterns"** — keep the technical content (BGP, MACsec, BYOIP, static egress NAT) which is generally educational

---

## File Structure — What changes where

### Files being **deleted**
- `curriculum/ncp-domain-tagging.md` — pure NCP cross-reference, belongs in `ncp-compliance-pack`

### Files being **renamed + edited**
- `curriculum/mirantis-k0rdent-validation-reference.md` → `curriculum/mirantis-k0rdent-enterprise-reference.md` — strip NCP-specific sections, keep Mirantis product facts

### Files being **edited in place**
- `curriculum/overview/training-program-overview.md` — replace "Two audiences, one curriculum" section with simple learning-focused framing
- Ten lab files (Phase 2 below) — strip NCP framing, keep technical body

### Task list (in-memory) being **reset**
- Delete pending Wave C retroactive-tagging tasks (#17–#22) — no NCP tags, no retroactive tagging
- Update pending Wave B tasks (#13–#16) to reflect concept-driven framing
- Keep Wave A completed tasks as-is (they're history)

---

## Phase 1 — Cross-reference doc cleanup

### Task 1: Delete the NCP domain tagging guide

**Files:**
- Delete: `curriculum/ncp-domain-tagging.md`

- [ ] **Step 1: Delete the file**

```bash
cd /Users/moustaphagueye/ghq/github.com/mgueye01/k0rdent-ai-training
git rm curriculum/ncp-domain-tagging.md
```

- [ ] **Step 2: Verify the file is gone**

```bash
ls curriculum/ncp-domain-tagging.md 2>&1
# Expected: "No such file or directory"
git status --short curriculum/ncp-domain-tagging.md
# Expected: "D  curriculum/ncp-domain-tagging.md"
```

---

### Task 2: Rename + strip the Mirantis reference doc

**Files:**
- Rename: `curriculum/mirantis-k0rdent-validation-reference.md` → `curriculum/mirantis-k0rdent-enterprise-reference.md`
- Edit: remove "Compliance pack alignment" section, remove "NCP cert prep" guidance, remove Req-ID-specific guidance from the body. Keep: version pinning, architecture (KCM/KSM/KOF), CRD list, ClusterTemplate naming, KOF components, approved OSS deps table.

- [ ] **Step 1: Rename the file**

```bash
cd /Users/moustaphagueye/ghq/github.com/mgueye01/k0rdent-ai-training
git mv curriculum/mirantis-k0rdent-validation-reference.md curriculum/mirantis-k0rdent-enterprise-reference.md
```

- [ ] **Step 2: Edit the file to strip NCP-specific sections**

Sections to **remove**:
- The `> Purpose:` blockquote line "validate against the NVIDIA Requirements Guide" — rewrite as general Mirantis fact sheet purpose
- The "Compliance pack alignment" section (if present) — gone
- Any per-Req-ID mappings in the OSS deps table — replace with general usage notes
- The "How to use this reference when writing labs" section's NCP-specific guidance points

Sections to **keep**:
- Version pinning
- Architecture (KCM/KSM/KOF)
- k0rdent Enterprise CRDs canonical list
- ClusterTemplate types & naming
- KOF components (use these exact names)
- Supported providers
- Mirantis-shipped addons
- Hosted Control Plane
- Position language for labs (Mirantis-oriented voice patterns)
- Approved OSS dependencies (rephrase to drop the Req-ID column if present)

- [ ] **Step 3: Verify no NCP framing remains**

```bash
cd /Users/moustaphagueye/ghq/github.com/mgueye01/k0rdent-ai-training
grep -i 'NCP\|NVIDIA Cloud Partner\|DGXC\|Req ID\|compliance pack' curriculum/mirantis-k0rdent-enterprise-reference.md || echo "OK — no NCP framing"
# Expected: "OK — no NCP framing" (or only incidental mentions in approved-OSS context)
```

---

### Task 3: Update training program overview

**Files:**
- Modify: `curriculum/overview/training-program-overview.md`

- [ ] **Step 1: Remove the "Two audiences, one curriculum" section**

Find the section that starts with `## Two audiences, one curriculum` (introduced in commit `de41277`) and delete it entirely. The section between that heading and the next `## Program Structure` heading should be removed.

- [ ] **Step 2: Verify**

```bash
grep -A 2 'Two audiences' curriculum/overview/training-program-overview.md || echo "OK — section removed"
# Expected: "OK — section removed"
```

---

### Task 4: Commit Phase 1

- [ ] **Step 1: Stage and commit**

```bash
cd /Users/moustaphagueye/ghq/github.com/mgueye01/k0rdent-ai-training
git add curriculum/ncp-domain-tagging.md curriculum/mirantis-k0rdent-validation-reference.md curriculum/mirantis-k0rdent-enterprise-reference.md curriculum/overview/training-program-overview.md
git status --short
git commit -m "docs(curriculum): remove NCP validation framing from cross-reference docs

Refocuses the curriculum repo on learning concepts; NCP/DGXC certification
mapping moves to the separate ncp-compliance-pack repo.

- Delete curriculum/ncp-domain-tagging.md (Req ID → lab cross-reference belongs elsewhere)
- Rename mirantis-k0rdent-validation-reference.md → mirantis-k0rdent-enterprise-reference.md
  and strip NCP-specific sections; keep the Mirantis product facts (CRDs,
  KCM/KSM/KOF components, ClusterTemplate naming, version pins, OSS deps)
- Remove the 'Two audiences, one curriculum' section from the training
  overview; the curriculum has one audience: engineers learning k0rdent +
  AI infrastructure"
```

---

## Phase 2 — Strip NCP framing from the 10 new labs

### Pattern to apply (same for every lab)

For each of the 10 new labs, apply these edits:

**Edit A — Tag block (right after the title)**

Before (current shape):
```markdown
| Domain | Tag | NVIDIA Req IDs |
|--------|-----|----------------|
| Telemetry / Observability / KOF | 🟢 NCP | Telemetry §1, §3, §4, SDN09 |
```

After:
```markdown
**Domain:** Telemetry / Observability / KOF
```

(One-line `**Domain:**` is sufficient for navigation; no tag-emoji, no Req IDs.)

**Edit B — Compliance pack artifact callout (the blockquote right below the tag block)**

Before:
```markdown
> **Compliance pack artifact targets:** `artifacts/TEL01-...`, `artifacts/TEL02-...`
```

After:
- **Delete the line entirely.** Keep the `> **Mirantis docs:** ...` line if it exists (those are useful learning references).

**Edit C — "Why this lab exists" section**

Find any direct quote of NVIDIA v2.3 wording (paragraph starting with phrases like *"The NVIDIA Requirements Guide v2.3..."* or quoted text like *"NCP shall deliver..."*) and **replace** with concept-driven motivation. The replacement must answer: *why does an engineer need this skill, in general terms?*

Specific quote-replacement patterns per lab:
- **5.17 OTel export**: Replace "NCP shall deliver telemetry via OTLP" with reasoning about *push-vs-pull telemetry at fleet scale, sub-2-minute observability, why OTLP is the modern OSS-native solution*
- **5.18 topograph**: Replace "NVIDIA requires NET01/NET02" with reasoning about *topology-aware scheduling and the throughput cost of crossing NVLink/leaf boundaries*
- **6.2 Breakfix API**: Replace the v2.3 opening sentence with *why operational APIs (not runbooks) are the way to handle hardware failure at scale*
- **6.3 Capacity & Fleet**: Replace "It is not acceptable to have capacity handed over via Slack" with reasoning about *programmatic capacity awareness as a foundation for fleet management*
- **6.4 sanitization**: Replace SEC21 quote with *what "tenancy ends" means operationally, and why the four data locations matter*
- **1.9 audit**: Replace SEC08/K8S20 quotes with *audit logging as a security and operational discipline*
- **2.4 BMC hardening**: Replace SEC12/CNP10 quotes with *why the BMC is the highest-privilege surface in the stack*
- **2.5 Secure Boot + TPM**: Replace SEC22 quote with *the chain of trust as a stack of cryptographic guarantees*
- **4.9 DRA**: Replace K8S24 quote with *DRA as the next-generation resource allocation model and what it enables*
- **4.10 BYOIP/PCI/MACsec**: **Special**: reframe the entire lab as **"Case Study: AI cloud provider interconnect patterns"**. Keep technical content. Update title and "Why this lab exists" to position it as a case study of how a real AI cloud provider connects to a customer, with the engineering patterns (BGP, MACsec, BYOIP, static egress NAT) called out as the transferable skills.

**Edit D — Compliance pack production section (usually Part N at the end)**

Look for sections titled `## Part N: Produce the compliance-pack artifacts` (where N is 6, 7, etc.) and either:
- **Delete the section entirely**, OR
- **Rewrite** as `## Part N: Producing your own evidence` with the bash commands kept but the artifact filenames de-stamped (drop `NET01-`, `BFX02-`, `TEL01-` prefixes from filenames)

For most labs, **delete is the cleaner choice** — the bash blocks are largely about producing evidence files, which isn't pedagogically useful in a learning context.

**Edit E — Verification Checklist**

Find any checklist items mentioning "Req-ID-stamped artifacts," "compliance pack," "artifact produced" — **delete those bullets**. Keep all technical-verification bullets.

**Edit F — Key Takeaways**

If a "Key Takeaways" bullet mentions "compliance artifact" or "audit asks for X" — rewrite to drop the audit framing while keeping the conceptual point. Example:
- Before: *"The compliance-pack artifact is the policy + a query that proves retention."*
- After: *"The deliverable is a documented audit policy + a saved query that proves the retention guarantee."*

---

### Tasks 5–14: Per-lab strip pass

Each of these tasks applies Edits A–F to one lab file. They're independent and can be done in parallel by subagents.

### Task 5: Strip NCP framing from Lab 1.9 (audit logging)

**Files:**
- Modify: `curriculum/week-1-foundations/labs/lab-1.9-api-audit-logging.md`

- [ ] **Step 1: Apply Edits A–F**

Specific items to grep-find for this lab:
- Tag block with `🔵 BOTH | SEC08...`
- Compliance pack callout
- "Two requirements pull this lab into Week 1's 'production hardening' arc" — replace this opening with concept-driven framing about audit hygiene
- v2.3 SEC08 + K8S20 direct quotes — drop
- "Produce the compliance-pack artifacts" Part 6 — delete
- Verification: "Artifacts SEC08-*, K8S20-* produced and Req-ID-stamped" — drop

- [ ] **Step 2: Verify**

```bash
grep -i 'NCP\|Req ID\|compliance pack\|SEC08\|K8S20\|SDN03' curriculum/week-1-foundations/labs/lab-1.9-api-audit-logging.md
# Expected: empty output (or only incidental matches)
```

---

### Task 6: Strip NCP framing from Lab 2.4 (BMC hardening)

**Files:**
- Modify: `curriculum/week-2-bmaas/labs/lab-2.4-bmc-hardening.md`

- [ ] **Step 1: Apply Edits A–F**
- [ ] **Step 2: Verify**

```bash
grep -i 'NCP\|Req ID\|compliance pack\|SEC12\|CNP10\|CNP06\|CNP08' curriculum/week-2-bmaas/labs/lab-2.4-bmc-hardening.md
# Expected: empty output
```

---

### Task 7: Strip NCP framing from Lab 2.5 (Secure Boot + TPM)

**Files:**
- Modify: `curriculum/week-2-bmaas/labs/lab-2.5-secure-boot-tpm.md`

- [ ] **Step 1: Apply Edits A–F**
- [ ] **Step 2: Verify**

```bash
grep -i 'NCP\|Req ID\|compliance pack\|SEC22\|CNP09' curriculum/week-2-bmaas/labs/lab-2.5-secure-boot-tpm.md
# Expected: empty output
```

---

### Task 8: Strip NCP framing from Lab 4.9 (DRA)

**Files:**
- Modify: `curriculum/week-4-kaas/labs/lab-4.9-dynamic-resource-allocation.md`

- [ ] **Step 1: Apply Edits A–F**
- [ ] **Step 2: Verify**

```bash
grep -i 'NCP\|Req ID\|compliance pack\|K8S24' curriculum/week-4-kaas/labs/lab-4.9-dynamic-resource-allocation.md
# Expected: empty output
```

---

### Task 9: Strip + reframe Lab 4.10 (BYOIP/PCI/MACsec) as case study

**Files:**
- Modify: `curriculum/week-4-kaas/labs/lab-4.10-byoip-pci-macsec.md`

- [ ] **Step 1: Apply Edits A–F + retitle**

Special handling:
- Title becomes: `# Lab 4.10 — Case Study: AI Cloud Provider Interconnect Patterns`
- "Why this lab exists" becomes: position this as a case study of how a real AI cloud provider connects to a customer site (BGP + VIF + BYOIP + MACsec + static egress NAT), with these patterns called out as transferable to any similar AI/HPC engagement
- Keep the technical content (FRR BGP config, MACsec via `ip macsec` + `wpa_supplicant`, NAT pool design)
- Drop direct references to "DGXC," "NVIDIA POP," "NVIDIA CorpIT" — replace with generic "the upstream AI cloud," "the provider's POP," "the provider's corp network"

- [ ] **Step 2: Verify**

```bash
grep -i 'NCP\|Req ID\|DGXC\|NVIDIA POP\|NVIDIA CorpIT\|NET03\|SDN01\|SEC13\|SEC18\|DMS0' curriculum/week-4-kaas/labs/lab-4.10-byoip-pci-macsec.md
# Expected: empty output (NVIDIA may still appear in other technical contexts like NVLink — that's fine, it's just NCP/DGXC mentions we want gone)
```

---

### Task 10: Strip NCP framing from Lab 5.17 (OTel telemetry export)

**Files:**
- Modify: `curriculum/week-5-ai-workloads/labs/lab-5.17-otel-telemetry-export.md`

- [ ] **Step 1: Apply Edits A–F**

Special handling for this lab:
- Title can stay as "Lab 5.17 — Extending KOF's OTel Pipeline for External Export" (drop "for DGXC")
- "Why this lab exists" rewritten around *real-time observability at fleet scale, push-vs-pull, 120-s SLAs as a general engineering target (not specifically NVIDIA's)*
- External target examples (Jaeger, Honeycomb, etc.) stay
- DGXC stand-in test target framing → "an external OTLP-compatible receiver (your DR cluster, a SaaS APM, etc.)"

- [ ] **Step 2: Verify**

```bash
grep -i 'NCP\|Req ID\|compliance pack\|DGXC\|Telemetry §\|SDN09' curriculum/week-5-ai-workloads/labs/lab-5.17-otel-telemetry-export.md
# Expected: empty output
```

---

### Task 11: Strip NCP framing from Lab 5.18 (topograph + NVLink)

**Files:**
- Modify: `curriculum/week-5-ai-workloads/labs/lab-5.18-topograph-nvlink-topology.md`

- [ ] **Step 1: Apply Edits A–F**

Special handling:
- Title: "Lab 5.18 — Network Topology + NVLink Domain Discovery"
- "Why this lab exists" rewritten around *topology-aware GPU scheduling, the throughput cost of crossing NVLink/leaf boundaries — keep the throughput table, it's a teaching highlight*
- DGXC scheduler integration → generic "the scheduler" / "your job orchestrator"

- [ ] **Step 2: Verify**

```bash
grep -i 'NCP\|Req ID\|compliance pack\|NET01\|NET02\|CNP03\|CAP04\|DGXC' curriculum/week-5-ai-workloads/labs/lab-5.18-topograph-nvlink-topology.md
# Expected: empty output
```

---

### Task 12: Strip NCP framing from Lab 6.2 (Breakfix API)

**Files:**
- Modify: `curriculum/week-6-multitenancy/labs/lab-6.2-breakfix-api.md`

- [ ] **Step 1: Apply Edits A–F**

Special handling:
- "Why this lab exists" rewritten around *operational APIs vs runbooks at fleet scale, the NVLink-detach safety pattern as a teaching example*
- "References" section pointing to NVIDIA Lazarus docs — keep if they're publicly accessible, or drop if they're Google Docs that require auth
- DGXC framing → "consumers of the breakfix API," "downstream operators"

- [ ] **Step 2: Verify**

```bash
grep -i 'NCP\|Req ID\|compliance pack\|BFX01\|BFX02\|BFX03\|DGXC' curriculum/week-6-multitenancy/labs/lab-6.2-breakfix-api.md
# Expected: empty output
```

---

### Task 13: Strip NCP framing from Lab 6.3 (Capacity & Fleet APIs)

**Files:**
- Modify: `curriculum/week-6-multitenancy/labs/lab-6.3-capacity-fleet-apis.md`

- [ ] **Step 1: Apply Edits A–F**

Special handling:
- The "It is not acceptable to have capacity handed over via Slack" quote — replace with the general engineering principle (programmatic capacity awareness as a foundation for fleet management)
- The four governance metrics (Delivered/Healthy/Reserved/In-Use) — keep as a useful taxonomy; reframe from "contractual" to "canonical"

- [ ] **Step 2: Verify**

```bash
grep -i 'NCP\|Req ID\|compliance pack\|CAP0\|DGXC' curriculum/week-6-multitenancy/labs/lab-6.3-capacity-fleet-apis.md
# Expected: empty output
```

---

### Task 14: Strip NCP framing from Lab 6.4 (sanitization + at-rest crypto)

**Files:**
- Modify: `curriculum/week-6-multitenancy/labs/lab-6.4-sanitization-at-rest-crypto.md`

- [ ] **Step 1: Apply Edits A–F**

Special handling:
- "Why this lab exists" rewritten around *what "tenancy ends" means operationally + the four data locations + NIST SP 800-88 as the standard reference*
- Keep NIST SP 800-88 references — that's a legitimate engineering standard, not NCP framing

- [ ] **Step 2: Verify**

```bash
grep -i 'NCP\|Req ID\|compliance pack\|SEC11\|SEC19\|SEC20\|SEC21\|K8S19\|STG02\|DGXC' curriculum/week-6-multitenancy/labs/lab-6.4-sanitization-at-rest-crypto.md
# Expected: empty output
```

---

### Task 15: Commit Phase 2

- [ ] **Step 1: Stage all 10 modified labs**

```bash
cd /Users/moustaphagueye/ghq/github.com/mgueye01/k0rdent-ai-training
git add curriculum/week-1-foundations/labs/lab-1.9-api-audit-logging.md \
        curriculum/week-2-bmaas/labs/lab-2.4-bmc-hardening.md \
        curriculum/week-2-bmaas/labs/lab-2.5-secure-boot-tpm.md \
        curriculum/week-4-kaas/labs/lab-4.9-dynamic-resource-allocation.md \
        curriculum/week-4-kaas/labs/lab-4.10-byoip-pci-macsec.md \
        curriculum/week-5-ai-workloads/labs/lab-5.17-otel-telemetry-export.md \
        curriculum/week-5-ai-workloads/labs/lab-5.18-topograph-nvlink-topology.md \
        curriculum/week-6-multitenancy/labs/lab-6.2-breakfix-api.md \
        curriculum/week-6-multitenancy/labs/lab-6.3-capacity-fleet-apis.md \
        curriculum/week-6-multitenancy/labs/lab-6.4-sanitization-at-rest-crypto.md
```

- [ ] **Step 2: Verify staged + commit**

```bash
git status --short
git commit -m "docs(curriculum): strip NCP certification framing from 10 new labs

Concept-driven framing — each lab teaches its engineering subject directly.
NVIDIA Req ID references and compliance-pack artifact targets move to the
separate ncp-compliance-pack repo. All technical content preserved.

- Tag blocks reduced to a single 'Domain:' line (no Req IDs)
- 'Why this lab exists' rewritten around the engineering motivation
- 'Produce the compliance-pack artifacts' sections removed
- Verification checklists keep technical items, drop artifact-stamping items
- Lab 4.10 (BYOIP/PCI/MACsec) reframed as 'Case Study: AI Cloud Provider
  Interconnect Patterns' — same technical content, generic positioning"
```

---

## Phase 3 — Reset the in-memory task list + final push

### Task 16: Clean up stale Wave B/C tasks

- [ ] **Step 1: Delete Wave C tasks (no longer needed — no NCP tagging axis)**

Delete tasks #17, #18, #19, #20, #21, #22 (`Wave C: Tag Week N existing labs`).

- [ ] **Step 2: Reframe Wave B tasks**

Update tasks #13, #14, #15, #16 with new concept-driven titles:
- #13: `Lab 3.4 — CPU-only VMaaS for data pre-staging`
- #14: `Lab 4.11 — Shared storage architectures for AI workloads (NFSv4 + parallel FS)`
- #15: `Lab 6.5 — OIDC federation for multi-tenant K8s`
- #16: **Delete** — dgxc-benchmarking callout was NCP-specific, drop or replace with a general benchmarking lab later

---

### Task 17: Final push

- [ ] **Step 1: Push both phase commits**

```bash
cd /Users/moustaphagueye/ghq/github.com/mgueye01/k0rdent-ai-training
git log --oneline -3
git push origin main
```

- [ ] **Step 2: Verify**

```bash
git log -2 --oneline
# Expected: two new commits ahead of the previous HEAD
```

---

## Definition of Done

- [ ] `curriculum/ncp-domain-tagging.md` no longer exists
- [ ] `curriculum/mirantis-k0rdent-enterprise-reference.md` exists; no NCP framing
- [ ] `curriculum/overview/training-program-overview.md` no longer has "Two audiences, one curriculum" section
- [ ] All 10 new labs have:
  - Single `**Domain:**` line (no Req IDs)
  - No `> **Compliance pack artifact targets:**` callout
  - No direct v2.3 quotes in "Why this lab exists"
  - No "Produce the compliance-pack artifacts" Part section
  - No "Req-ID-stamped artifacts" verification items
- [ ] Lab 4.10 retitled and reframed as case study
- [ ] All changes committed and pushed
- [ ] Task list reflects new concept-driven Wave B (Wave C dropped)
- [ ] `grep -ri "NCP\|Req ID\|compliance pack" curriculum/` returns no matches in lab files (incidental matches in `mirantis-k0rdent-enterprise-reference.md` are OK if any remain)

---

## Execution approach

Given that Tasks 5–14 (the 10 per-lab strip passes) all apply the same pattern, they're highly parallel. I'll:

1. **Phase 1 inline** (Tasks 1–4) — small structural edits I'll do directly
2. **Phase 2 via parallel subagents** (Tasks 5–14) — dispatch one subagent per lab with the pattern brief, then Task 15 (commit) inline
3. **Phase 3 inline** (Tasks 16–17) — task cleanup + push

That's ~6 inline steps + 10 parallel agents.
