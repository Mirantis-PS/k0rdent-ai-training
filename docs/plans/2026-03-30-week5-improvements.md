# Week 5 AI Workloads Improvements Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix broken commands, improve UX, and add missing context to Week 5 curriculum based on three-agent assessment (UX flow, theory accuracy, known issues audit).

**Architecture:** Parallel fixes grouped by priority. Priority 1 fixes broken labs. Priority 2 improves UX. Priority 3 adds polish.

**Tech Stack:** Markdown editing, k0rdent catalog knowledge from Week 1 fixes.

---

## Task 1: Fix Lab 5.1 Broken Catalog Install

**Files:**
- Modify: `curriculum/week-5-ai-workloads/labs/lab-5.1-gpu-scheduler.md`

**What:** Lines 134-137 use the broken `helm install gpu-operator-service-template oci://ghcr.io/k0rdent/catalog/charts/gpu-operator-service-template` pattern. This fails on Enterprise because the chart creates a ServiceTemplate with apiVersion v1alpha1.

**Fix:** Replace with the `kgst` meta-chart pattern used in Lab 5.5, OR use the `kubectl apply` v1beta1 ServiceTemplate pattern from Week 1. Use whichever pattern Lab 5.5 already uses for consistency.

Check Lab 5.5 first to see which pattern it uses, then align Lab 5.1.

---

## Task 2: Add GPU Cost Estimates and Model Download Warning

**Files:**
- Modify: `curriculum/week-5-ai-workloads/labs/README.md`

**What:** Students need to know:
1. GPU instance costs (p3.8xlarge ~$4.50/hr spot, p4d.24xlarge ~$15/hr spot)
2. Model downloads can take 15-30 min (Llama-2-7B is ~13GB)
3. Foundation labs work on V100s, advanced labs (5.13-5.15) require A100s

**Fix:** Add a "Cost and Resource Planning" section near the top of the labs README, after the environment warning.

---

## Task 3: Clarify Week Duration and Track Structure

**Files:**
- Modify: `curriculum/week-5-ai-workloads/README.md`

**What:** The README claims 21 hours but foundation alone is 15h. Students can't do everything. Need explicit "choose your path" guidance.

**Fix:** Add a "Choosing Your Path" section with realistic time estimates per track combination. Also surface Lab 5.11 Run:AI license requirement here.

---

## Task 4: Fix Lab 5.7 Region Guidance

**Files:**
- Modify: `curriculum/week-5-ai-workloads/labs/lab-5.7-nvidia-fips.md`

**What:** Hardcoded us-east-1 without explaining why (FIPS regional availability).

**Fix:** Add a note explaining FIPS region constraints.

---

## Task 5: Fix Lab 5.8 sshKeyName and Naming

**Files:**
- Modify: `curriculum/week-5-ai-workloads/labs/lab-5.8-cluster-templates.md`

**What:**
1. sshKeyName assumes key exists without defensive guidance
2. Lab is in "Compliance & Templates" track but is really about GPU cluster deployment

**Fix:** Add note that sshKeyName is optional (per Week 1 findings). Title/track naming is a larger restructure — just add a clarifying note for now.

---

## Task 6: Add Theory Version Context

**Files:**
- Modify: `curriculum/week-5-ai-workloads/theory/5.2-llm-inference-architecture.md`

**What:** vLLM version v0.11.2 is dated. Add version context note.

**Fix:** Update to v0.14.0+ or add "v0.11.2 or later" note. Add a brief mention of vLLM V1 architecture.

---

## Task 7: Add TOCs to Week 5 Files

**Files:**
- All theory and lab files in week-5-ai-workloads/

**What:** Week 1 files all have TOCs. Week 5 files don't.

**Fix:** Add GitHub-style TOCs to all files (same pattern as Week 1).

---

## Execution Order

Tasks 1-6 can run in parallel (different files). Task 7 (TOCs) should run last since other tasks modify headers.
