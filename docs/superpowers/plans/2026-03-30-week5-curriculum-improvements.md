# Week 5 AI Workloads Curriculum Improvements

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix critical errors, improve UX/navigation, and rationalize the Week 5 curriculum structure so learners can realistically complete it within 15 hours.

**Architecture:** Documentation-only changes across 21 markdown files in `curriculum/week-5-ai-workloads/`. No code or infrastructure changes. Organized into 7 tasks by priority: critical fixes first, then structural improvements, then content additions.

**Tech Stack:** Markdown, YAML (inline examples only)

**Base path:** `curriculum/week-5-ai-workloads`

---

## File Map

### Files to modify

| File | Responsibility | Tasks |
|------|---------------|-------|
| `labs/lab-5.3-vector-database.md` | Fix broken `valuesFrom` YAML | 1 |
| `labs/lab-5.14-rdma-multi-cloud.md` | Fix mislabeled prerequisite | 1 |
| `labs/README.md` | Fix durations, add Lab 5.16, add theory index, add time planning guide | 2, 3, 4 |
| `README.md` | Fix FIPS reference, update Week 5 section | 2 |
| `labs/lab-5.2-vllm-inference.md` | Fix `TRANSFORMERS_CACHE` -> `HF_HOME` | 2 |
| `theory/5.4-distributed-training.md` | Fix fictional PyTorch image tag | 2 |
| `theory/5.5-ml-platforms.md` | Fix fictional PyTorch image tag | 2 |
| `labs/lab-5.1-gpu-scheduler.md` | Add cleanup section | 5 |
| `labs/lab-5.2-vllm-inference.md` | Add cleanup section | 5 |
| `labs/lab-5.3-vector-database.md` | Add cleanup section | 5 |
| `labs/lab-5.4-jupyter-notebooks.md` | Add cleanup section | 5 |
| `labs/lab-5.5-service-catalog.md` | Add cleanup section | 5 |
| `labs/lab-5.10-mlflow-experiment-tracking.md` | Add cleanup section | 5 |
| `labs/lab-5.11-runai-gpu-orchestration.md` | Add cleanup section | 5 |
| `labs/lab-5.12-slurm-operator-hpc.md` | Add cleanup section | 5 |
| `labs/lab-5.14-rdma-multi-cloud.md` | Add cleanup section | 5 |
| `labs/lab-5.16-kai-scheduler.md` | Add cleanup section | 5 |
| `labs/lab-5.7-nvidia-fips.md` | Fix compliance track nav diagram | 6 |
| `labs/lab-5.8-cluster-templates.md` | Fix compliance track nav diagram, normalize heading format | 6 |
| 7 files with containerd config | Add NRI plugin note | 7 |

---

## Task 1: Fix Critical Errors (3 broken things)

**Files:**
- Modify: `labs/lab-5.3-vector-database.md:230`
- Modify: `labs/lab-5.14-rdma-multi-cloud.md:44`

- [ ] **Step 1: Fix `valuesFrom` in Lab 5.3 MultiClusterService YAML**

  In `labs/lab-5.3-vector-database.md` line 230, the MultiClusterService YAML uses `valuesFrom: milvus-values.yaml` (a bare filename string) which is not valid. The k0rdent `valuesFrom` field expects a Secret reference (as correctly shown in Lab 5.5 line 341-345).

  Find:
  ```yaml
           valuesFrom: milvus-values.yaml
  ```

  Replace with a proper Secret reference matching the pattern from Lab 5.5:
  ```yaml
           values: |
             cluster:
               enabled: true
             standalone:
               enabled: false
             attu:
               enabled: true
               service:
                 type: ClusterIP
             metrics:
               enabled: true
  ```

  These are the exact Milvus values defined earlier in the same lab (lines 186-206). Using inline `values:` is the simplest correct approach here since the values are not sensitive (unlike Lab 5.5's database credentials which correctly use a Secret).

  Verify: Search the file for any other bare-string `valuesFrom` references and fix those too.

- [ ] **Step 2: Fix Lab 5.14 mislabeled prerequisite**

  In `labs/lab-5.14-rdma-multi-cloud.md` line 44:

  Find:
  ```
  - Completed Lab 5.3 (GPU Communication) recommended
  ```

  Replace with:
  ```
  - Read Theory 5.3 (GPU Communication) recommended
  ```

  Rationale: Lab 5.3 is the vector database lab. Theory 5.3 covers GPU communication.

- [ ] **Step 3: Verify fixes**

  Search all lab files for any other cross-references that confuse theory numbers with lab numbers:
  ```bash
  grep -rn "Lab 5\.[0-9].*Communication\|Lab 5\.[0-9].*Scheduling\|Lab 5\.[0-9].*Inference Architecture" curriculum/week-5-ai-workloads/labs/
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add curriculum/week-5-ai-workloads/labs/lab-5.3-vector-database.md curriculum/week-5-ai-workloads/labs/lab-5.14-rdma-multi-cloud.md
  git commit -m "fix(week5): fix broken valuesFrom YAML and mislabeled prerequisite"
  ```

---

## Task 2: Fix Accuracy Issues (durations, versions, env vars)

**Files:**
- Modify: `labs/README.md:338,368-370`
- Modify: `README.md:921,1045,1133`
- Modify: `labs/lab-5.2-vllm-inference.md:286,636`
- Modify: `theory/5.4-distributed-training.md` (grep for `2.10.0`)
- Modify: `theory/5.5-ml-platforms.md` (grep for `2.10.0`)

- [ ] **Step 1: Fix duration mismatches in labs/README.md**

  Update the navigation table to match actual lab file durations (lab file is source of truth):

  | Lab | README says | Lab file says | Fix to |
  |-----|-------------|---------------|--------|
  | 5.2 | 2.5h | 4h | 4h |
  | 5.13 | 3h | 3.5h | 3.5h |
  | 5.14 | 3h | 4h | 4h |
  | 5.15 | 3h | 4.5h | 4.5h |

- [ ] **Step 2: Fix FIPS 140-2 references in README.md**

  In `README.md`, update three occurrences:
  - Line 921: `FIPS 140-2` -> `FIPS 140-3`
  - Line 1045: `FIPS 140-2` -> `FIPS 140-3`
  - Line 1133: `FIPS 140-2` -> `FIPS 140-3`

- [ ] **Step 3: Fix TRANSFORMERS_CACHE in Lab 5.2**

  In `labs/lab-5.2-vllm-inference.md` at lines 286 and 636:

  Find:
  ```yaml
              - name: TRANSFORMERS_CACHE
  ```

  Replace with:
  ```yaml
              - name: HF_HOME
  ```

  `TRANSFORMERS_CACHE` is deprecated; `HF_HOME` is the current HuggingFace standard.

- [ ] **Step 4: Fix fictional PyTorch image tag**

  In `theory/5.4-distributed-training.md` (3 occurrences) and `theory/5.5-ml-platforms.md` (3 occurrences), replace **all 6 occurrences** of:
  ```
  pytorch/pytorch:2.10.0-cuda12.6-cudnn9-runtime
  ```

  With a real tag:
  ```
  pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime
  ```

  Use replace-all in each file. Verify with: `grep -c "2.10.0" theory/5.4-distributed-training.md theory/5.5-ml-platforms.md` — should return 0 for both.

- [ ] **Step 5: Commit**

  ```bash
  git add curriculum/week-5-ai-workloads/labs/README.md \
        curriculum/week-5-ai-workloads/README.md \
        curriculum/week-5-ai-workloads/labs/lab-5.2-vllm-inference.md \
        curriculum/week-5-ai-workloads/theory/5.4-distributed-training.md \
        curriculum/week-5-ai-workloads/theory/5.5-ml-platforms.md
  git commit -m "fix(week5): correct durations, FIPS version, env var, and PyTorch image tag"
  ```

---

## Task 3: Add Lab 5.16 to Navigation & Resolve 5.1/5.16 Overlap

**Files:**
- Modify: `labs/README.md:344-378`

- [ ] **Step 1: Add Lab 5.16 to the elective navigation table**

  In `labs/README.md`, after the ML Platforms table (around line 362), add Lab 5.16 as an open-source alternative row:

  ```markdown
  **ML Platforms**

  | Lab | Title | Duration |
  |-----|-------|----------|
  | [5.9](lab-5.9-kubeflow-ml-platform.md) | Kubeflow ML Platform | 3h |
  | [5.10](lab-5.10-mlflow-experiment-tracking.md) | MLflow Experiment Tracking | 2.5h |
  | [5.11](lab-5.11-runai-gpu-orchestration.md) | Run:AI GPU Orchestration | 3h |
  | [5.12](lab-5.12-slurm-operator-hpc.md) | Slurm Operator for HPC | 3h |
  | [5.16](lab-5.16-kai-scheduler.md) | KAI Scheduler (Open-Source) | 2.5h |
  ```

  Add a note below the table:
  ```markdown
  > **Note:** Lab 5.16 is an open-source alternative to Lab 5.11 (Run:AI). If you completed Lab 5.1 (GPU Scheduler), Lab 5.16 expands on KAI Scheduler with advanced queue hierarchies and topology-aware scheduling. Skip Lab 5.16 if you completed both Lab 5.1 and Lab 5.11.
  ```

- [ ] **Step 2: Update the ASCII navigation diagram**

  Update the diagram around line 373-378 to include Lab 5.16:

  ```
  FOUNDATION (Required)                          CHOOSE YOUR PATH
  ━━━━━━━━━━━━━━━━━━━━                          ━━━━━━━━━━━━━━━━
  5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6    ──►  ML Platforms (5.9-5.12, 5.16)
                                                 Compliance (5.7-5.8)
                                                 Advanced (5.13-5.15) ⚠ p4d required
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add curriculum/week-5-ai-workloads/labs/README.md
  git commit -m "fix(week5): add Lab 5.16 to navigation tables and clarify overlap with 5.1"
  ```

---

## Task 4: Add Theory Index and Time Planning Guide to Labs README

**Files:**
- Modify: `labs/README.md` (insert new sections before "Lab Navigation")

- [ ] **Step 1: Add Theory Reading Order section**

  Insert before the `## Lab Navigation` section (around line 329) a new section:

  ```markdown
  ## Theory Modules

  Read these before starting the corresponding labs:

  | Theory | Title | Duration | Prepares For |
  |--------|-------|----------|-------------|
  | [5.1](../theory/5.1-gpu-scheduling.md) | GPU Scheduling & Resource Management | 1.25h | Labs 5.1, 5.6, 5.11, 5.16 |
  | [5.2](../theory/5.2-llm-inference-architecture.md) | LLM Inference Architecture | 1h | Labs 5.2, 5.13 |
  | [5.3](../theory/5.3-gpu-communication.md) | GPU Communication & Interconnects | 1h | Labs 5.1, 5.14, 5.15 |
  | [5.4](../theory/5.4-distributed-training.md) | Distributed Training Patterns | 1h | Labs 5.9, 5.12, 5.15 |
  | [5.5](../theory/5.5-ml-platforms.md) | ML Platform Architecture | 1h | Labs 5.9, 5.10 |

  > **Minimum theory for foundation track:** Read Theory 5.1 and 5.2 before starting labs (~2.25h).
  ```

- [ ] **Step 2: Add Week Planning Guide section**

  Insert after the Lab Navigation section (after the ASCII diagram) a new section:

  ```markdown
  ## Week Planning Guide

  Total content exceeds 15 hours. Use these paths based on available time:

  **Essential Path (~12h):** Theory 5.1-5.2 + Labs 5.1, 5.2, 5.5, 5.6
  Covers GPU scheduling, LLM inference, k0rdent service catalog, and troubleshooting.

  **Full Foundation (~17h):** Theory 5.1-5.2 + All Foundation Labs (5.1-5.6)
  Complete GPU platform setup including vector DB and Jupyter. Extends slightly beyond one week.

  **Foundation + 1 Elective (~22-29h):** Foundation + one elective track
  Best spread across 2 weeks. Choose based on role:
  - **Platform engineers:** Compliance (5.7-5.8) — 4h additional
  - **ML engineers:** ML Platforms (5.9-5.12) — 11.5h additional
  - **Performance engineers:** Advanced (5.13-5.15) — 12h additional, requires p4d.24xlarge
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add curriculum/week-5-ai-workloads/labs/README.md
  git commit -m "docs(week5): add theory reading order and time planning guide"
  ```

---

## Task 5: Add Cleanup Sections to 10 Labs

**Files:**
- Modify: `labs/lab-5.1-gpu-scheduler.md` (append before Key Takeaways)
- Modify: `labs/lab-5.2-vllm-inference.md`
- Modify: `labs/lab-5.3-vector-database.md`
- Modify: `labs/lab-5.4-jupyter-notebooks.md`
- Modify: `labs/lab-5.5-service-catalog.md`
- Modify: `labs/lab-5.10-mlflow-experiment-tracking.md`
- Modify: `labs/lab-5.11-runai-gpu-orchestration.md`
- Modify: `labs/lab-5.12-slurm-operator-hpc.md`
- Modify: `labs/lab-5.14-rdma-multi-cloud.md`
- Modify: `labs/lab-5.16-kai-scheduler.md`

Each cleanup section should be inserted just **before** the `## Key Takeaways` or `## Verification Checklist` section at the end of the file (whichever comes first).

- [ ] **Step 1: Read each file's tail to find the right insertion point**

  For each of the 10 files, read the last 30 lines to identify where `## Key Takeaways` or `## Verification Checklist` starts.

- [ ] **Step 2: Add cleanup section to each lab**

  Each cleanup section follows this pattern — adapt the namespace and resource names to match what was deployed in that specific lab:

  ```markdown
  ## Cleanup

  Remove lab resources to free GPU capacity:

  ```bash
  # Delete lab namespace (removes all resources within)
  kubectl delete namespace <lab-namespace> --wait=false

  # Verify GPU resources are freed
  kubectl get pods -A | grep -i nvidia
  ```

  > **Cost reminder:** GPU instances cost $4.50-$15/hr. Destroy your GPU environment when not actively working. See the [labs README cleanup guide](README.md#cleanup).
  ```

  Specific namespaces per lab:
  - **5.1:** `gpu-scheduling` (KAI queues, NCCL test pods)
  - **5.2:** `vllm-inference` (vLLM deployment, model PVC)
  - **5.3:** `vector-db` (Milvus, PVCs)
  - **5.4:** `jupyter` (JupyterHub, user PVCs)
  - **5.5:** Multiple namespaces from MultiClusterService deployments — list them
  - **5.10:** `mlflow` (MLflow server, PostgreSQL, MinIO)
  - **5.11:** `runai-system`, `runai-projects` (Run:AI components)
  - **5.12:** `slurm` (Slurm operator, SlurmCluster)
  - **5.14:** `rdma-test` (NCCL RDMA test pods)
  - **5.16:** `kai-scheduler-system`, `gpu-scheduling` (KAI components, queues)

  **Important:** Read each lab to identify the exact namespaces and resources created. Do not guess — use the namespaces from the lab's own YAML manifests.

- [ ] **Step 3: Verify no cleanup section was duplicated**

  ```bash
  grep -c "## Cleanup" curriculum/week-5-ai-workloads/labs/lab-5.*.md
  ```

  Every lab file should show exactly 1 match.

- [ ] **Step 4: Commit**

  ```bash
  git add curriculum/week-5-ai-workloads/labs/lab-5.*.md
  git commit -m "docs(week5): add cleanup sections to 10 labs missing them"
  ```

---

## Task 6: Fix Navigation Diagram and Formatting Inconsistencies

**Files:**
- Modify: `labs/lab-5.7-nvidia-fips.md` (nav diagram near top)
- Modify: `labs/lab-5.8-cluster-templates.md` (nav diagram near top, normalize headings)

- [ ] **Step 1: Read the nav diagram sections of Labs 5.7 and 5.8**

  Read the first 30 lines of each file to see the current nav diagram.

- [ ] **Step 2: Fix compliance track nav diagrams**

  The current diagrams imply Compliance leads into ML Platforms and Advanced (sequential). Fix to show all three elective tracks as peers branching from the foundation:

  ```
  FOUNDATION (Required)                         CHOOSE YOUR PATH
  ━━━━━━━━━━━━━━━━━━━━                         ━━━━━━━━━━━━━━━━
  5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6    ──►  Compliance (5.7-5.8)
                                                 ML Platforms (5.9-5.12, 5.16)
                                                 Advanced (5.13-5.15)

  COMPLIANCE TRACK
  ━━━━━━━━━━━━━━━━
  YOU ARE HERE: [5.7] ➔ 5.8
  ```

- [ ] **Step 3: Normalize Lab 5.8 heading format**

  In `labs/lab-5.8-cluster-templates.md`:
  - Change `## Learning Objectives` to `## Objective` (single paragraph, matching all other labs)
  - Move the `## Duration` section content into the header table at the top (matching all other labs), then remove the standalone section

- [ ] **Step 4: Commit**

  ```bash
  git add curriculum/week-5-ai-workloads/labs/lab-5.7-nvidia-fips.md \
        curriculum/week-5-ai-workloads/labs/lab-5.8-cluster-templates.md
  git commit -m "fix(week5): fix misleading nav diagrams and normalize Lab 5.8 format"
  ```

---

## Task 7: Add GPU Operator NRI Plugin Note

**Files:**
- Modify: 7 files containing `CONTAINERD_CONFIG` env vars (see file list above)

- [ ] **Step 1: Identify all affected locations**

  ```bash
  grep -rn "CONTAINERD_CONFIG\|CONTAINERD_SOCKET\|CONTAINERD_RUNTIME_CLASS" curriculum/week-5-ai-workloads/
  ```

- [ ] **Step 2: Add a note after each containerd config block**

  After each YAML block that sets `CONTAINERD_CONFIG`, `CONTAINERD_SOCKET`, and `CONTAINERD_RUNTIME_CLASS`, add this note:

  ```markdown
  > **Note (GPU Operator v25.10.0+):** The toolkit environment variable approach shown above works but is being superseded by the NRI (Node Resource Interface) plugin method for k0s. If using GPU Operator v25.10.0+, see the [NVIDIA k0rdent partner validation docs](https://docs.nvidia.com/datacenter/cloud-native/partner-validated/latest/k0rdent.html) for the NRI plugin configuration, which eliminates the need for these containerd env vars.
  ```

  Do NOT replace the existing YAML — it still works. Just add awareness of the newer approach.

- [ ] **Step 3: Verify the note was added consistently**

  ```bash
  grep -c "NRI" curriculum/week-5-ai-workloads/labs/*.md curriculum/week-5-ai-workloads/theory/*.md
  ```

  Should match the number of files that had containerd config blocks.

- [ ] **Step 4: Commit**

  ```bash
  git add curriculum/week-5-ai-workloads/
  git commit -m "docs(week5): add NRI plugin note for GPU Operator v25.10.0+ across all files"
  ```

---

## Post-Implementation Verification

After all 7 tasks are complete:

- [ ] **Verify no broken markdown links:**
  ```bash
  # macOS-compatible (no GNU grep -P needed)
  grep -rn '](.*\.md)' curriculum/week-5-ai-workloads/labs/ | \
    sed 's/.*](\([^)]*\.md\)).*/\1/' | sort -u | while read link; do
    if [ ! -f "curriculum/week-5-ai-workloads/labs/$link" ]; then
      echo "CHECK: $link"
    fi
  done
  ```

- [ ] **Verify all 16 labs have cleanup sections:**
  ```bash
  for f in curriculum/week-5-ai-workloads/labs/lab-5.*.md; do
    count=$(grep -c "## Cleanup" "$f")
    echo "$f: $count"
  done
  ```
  All should show `1`.

- [ ] **Verify duration consistency:**
  Spot-check that labs/README.md durations now match lab file headers for 5.2, 5.13, 5.14, 5.15.
