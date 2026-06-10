# Week 1 Senior Trainer/Architect Review — 2026-06-10

**Scope:** All aspects of Week 1 — labs, theory, quiz, resources, `lab-infrastructure/` (Terraform + scripts), cross-week coherence, accessibility, non-ideal-learner scenarios, and program-level apparatus.
**Relationship to prior work:** Complements `2026-05-31-week-1-content-audit.md` (which covered per-file technical accuracy). This review **verified that all 5 critical findings of that audit are still present and unfixed** (no Week 1 commits since May 31), then ran a 56-agent workflow over the seven dimensions that audit never covered. Every critical/major finding below was adversarially verified against the actual files (and, where relevant, the real upstream charts/docs); 2 candidate findings were refuted and dropped.
**Full evidence:** `2026-06-10-week-1-senior-review-findings.md` (65 findings with quoted evidence, line numbers, fixes, and verifier notes).

---

## TL;DR Verdict (senior trainer/architect)

Week 1's **content voice is strong** — operational realism, cost framing, honest training-vs-production caveats — but the course as a **system** is broken in three ways that no amount of per-lab polish fixes:

1. **The lab-flow state machine is inconsistent.** Lab 1.5 tells the learner to destroy the cluster Labs 1.6–1.7 require; Lab 1.7 declares the week complete and routes to Week 2, orphaning Lab 1.8 and the quiz; expected outputs in 1.6/1.7 describe a fleet (a second cluster, 4/4 services) that the course never creates. A learner who does exactly what the pages say cannot reach the end with matching output.
2. **The executable environment was never reviewed as a product.** The provisioning script swallows 20 minutes of progress and can exit without printing the UI password; the bastion ships SSH open to `0.0.0.0/0` with the documented restriction wired to nothing; the admin password sits in IMDSv1-readable user-data; a cohort in a shared account hits AWS default quotas mid-Lab-1.5.
3. **There is no quality system.** Zero CI — no link checker, no shellcheck, no `terraform validate`, no output-reference cross-checks. The ~70 confirmed copy-paste-class defects across both audits are exactly the class a 30-minute CI workflow catches mechanically. Fixing the findings without adding the gates means they regress.

**Status of prior audit:** 100% open. Its C1 (teardown cost leak), C2 (Lab 1.7 capstone break), C3 (fabricated theory schema), C4 (non-existent `k0s etcd` commands), C5 (broken Azure path) all re-verified present today.

---

## New CRITICAL findings (all adversarially verified, high confidence)

### N1 — Lab 1.5 instructs learners to destroy the prerequisite for Labs 1.6–1.7
`lab-1.5` Part 7 (L568–580) unconditionally deletes `managed-cluster-01` and the L616 checklist requires "Cleaned up all resources". The only "keep it running!" warning lives in `lab-1.6` L74 — which a sequential learner reads *after* deleting. Lab 1.6 Part 3 then labels a cluster that no longer exists (`NotFound`).
**Fix:** Move the keep-running guidance into Lab 1.5 Part 7 itself ("SKIP if continuing to 1.6–1.8; cleanup repeats at end of week"), drop the checklist line, add the ~$0.15/hr holding-cost note.

### N2 — `lab-provision.sh` gives a silent 20-minute terminal, then can exit without the password
`ui_url=$(wait_for_gateway_url ...)` (L354) captures **every byte** of the "live" progress stream, the dots, and the success URL into the variable — the learner sees nothing during the wait, then a multi-line blob printed as "URL:". On either timeout path, `set -euo pipefail` kills the script **before the `ui_password` banner prints**. This is the first command of the course.
**Fix:** Stream progress to stderr, echo only the URL on stdout, guard the call with `|| true` so credentials always print with a retry hint.

### N3 — Week 1 footprint sits exactly at AWS default quotas; cohorts fail mid-lab
Management VPC + managed-cluster VPC consume the default 5-EIP/5-VPC per-region quotas with zero headroom. Any retry, second cluster, or **two students sharing an account** fails with `AddressLimitExceeded`/`VpcLimitExceeded` mid-Lab-1.5/1.6 — and no quota guidance exists anywhere in the curriculum. Compounded by: no Terraform state locking, and `engineer_id` as the only namespace — two students picking the same identifier silently share one state file.
**Fix:** Add a quota pre-flight check to `lab-provision.sh` (or Lab 1.1 prerequisites), document required quota increases for cohort delivery, enable state locking, and validate identifier uniqueness.

### N4 — Lab 1.6's Grafana SSH tunnel cannot work for any student
The tunnel command (L748–757) uses the author's leftover key names (`bastion.pem`, `lab-validation-k0rdent.pem` — real files are `${identifier}-bastion.pem`/`${identifier}-k0rdent.pem`) **and** the wrong bastion user (`ubuntu@` — the AL2023 bastion is `ec2-user@`). Every remote student fails publickey auth at a core Lab 1.6 deliverable. `lab-connect.sh` already supports `--tunnel 3000:3000` — the lab just doesn't use it.

### N5 — The program's entry contract is fiction (critic finding, spot-verified)
`curriculum/overview/prerequisites.md` promises "Access to lab provisioning portal (provided)" — no portal exists — and omits every real requirement: personal AWS account, effectively-admin IAM (the Terraform creates roles/policies/instance-profiles), AWS CLI v2, Terraform ≥ 1.8.0. It requires Docker/Podman, which no Week 1 lab uses. A prospective trainee cannot tell whether they can take this course.

### N6 — (Cross-week, affects Week 1's exit contract) Weeks 2 and 6 are built on a fabricated product surface
Week 2's first lab and Week 6's capstone reference a "Provider Console", "Customer Console", and a REST API (`/api/v1/tenants`, `/api/v1/auth/token`) that k0rdent Enterprise 1.2.2 does not have and Week 1 never taught. Week 1's two exit links also both point to `week-2-bmaas/README.md`, **which does not exist**. The Week 1→2 handoff is a dead link into fiction.

---

## Major findings, by theme (deduplicated; full list in the appendix)

### A. The cost story contradicts itself four ways
README says "destroy when not in use… ~$15–25 total @ 8h/day"; Lab 1.1 and Lab 1.8 say **never** destroy (management cluster "reused in all subsequent weeks" — though Weeks 2–3 never actually use it); the cheat-sheet says "Destroy environment (end of day!)"; and there is **no pause path at all** (no `stop-instances` guidance — the only verbs are provision/destroy). A literal reader either destroys their week-long cluster nightly or bills 24/7. Pick one lifecycle policy, state it in the README, and add a documented stop/start path with real idle-day cost.

### B. Self-checks that cannot match reality (trust killers)
- Lab 1.6 expects `SERVICES 4/4 (nginx + …)` — nginx doesn't exist until Lab 1.7; the real count is 3/3.
- Lab 1.7's verification numbers assume a phantom `managed-cluster-02` ("2/2 clusters", "SERVICES 2/2") that no lab creates, and ignore the 3 KOF services Lab 1.6 already added.
- Lab 1.7's `baseline-services` installs a second cert-manager onto a cluster where kof-child already owns the cert-manager CRDs → Helm ownership conflict blocks the whole MCS (and, per the lab's own note, cascades to kyverno). Verified against the actual kof-child 1.5.0 chart.
- Lab 1.7 Part 8's patch passes un-nested values — the exact "silently ignored by wrapper" mistake the same lab warns about at L377.
- Lab 1.6 L633/649/668 tells students their management cluster lacks AWS CCM — contradicting Lab 1.1/Theory 1.2, where CCM provisions the UI's load balancer.

### C. Lab-environment security posture (the course teaches hardening from an unhardened lab)
- Bastion SSH open to `0.0.0.0/0`; the documented `ALLOWED_SSH_CIDRS` knob is consumed by nothing, and `lab-provision.sh` clobbers the config file that sets it.
- k0rdent UI admin password baked into EC2 user-data, world-readable on disk, IMDSv1 enabled on every instance carrying a broad CAPA instance role (`RunInstances`, `iam:PassRole`, `Resource:"*"`) — one IMDS call from any pod.
- UI served over plaintext HTTP through an internet-facing load balancer; every student login transits cleartext.
- `lab-refresh-creds.sh` passes secret keys as SSH command-line args (visible in `ps` on both ends).
- Re-running `lab-provision.sh` with one feature flag silently **destroys** the other optional environments; `lab-destroy.sh` exits 0 "No state found" on init failure, leaving everything billing.

### D. Pedagogy / assessment
- **Day 5 packs 7 hours** — the three most failure-prone labs (KOF, MCS, upgrade) plus the graded assessment — vs 4.5–5.5h other days. Move Lab 1.8 + quiz to a Day 5 morning / restructure.
- Lab 1.4's RBAC exercise binds 1 of 3 service accounts, never binds the ClusterRoles, and never verifies access (`kubectl auth can-i`) — while Quiz Q18 assesses an isolation mechanism (`allowedNamespaces`) every lab explicitly disables.
- Quiz Q19 demands "the four AWS tags" but Theory 1.2 teaches three — the fourth exists only in the answer key. Quiz header still promises 18 questions/15-to-pass over a 19-question body, and the full answer key ships in the same student-facing file as the "graded" quiz, with no facilitator guide anywhere.
- Lab 1.8 Part 3 (managed-cluster upgrade) dead-ends at placeholders on the 1.2.2→1.2.3 path the lab itself uses, while objectives/summary still claim the skill.
- Lab 1.3 declares the SSH key optional/"not required for Lab 1.5"; Lab 1.5's prerequisites then require it.

### E. The floor: who can actually take this course
- **Windows students have no path** — every entry point is bash, remediation guidance is macOS/brew-only, and no doc states an OS/WSL2 requirement.
- "Resuming This Lab" blocks restore SSH but not session state: Lab 1.5's heredocs silently interpolate **empty** `${AWS_REGION}`/`${TEMPLATE_NAME}` after a reconnect; no resume block tells SSO users to refresh expired CAPA credentials.
- `jq` is a hard dependency of all four scripts, never checked, not preinstalled — fails as the misleading "Is the environment provisioned?".
- SSO credentials can expire mid-`terraform apply` in Lab 1.1 (~20 min), failing the first lab with partial state; the lab's only note is reactive.
- Accessibility: all architecture content is ASCII-box-only (screen-reader noise), Lab 1.2's UI exploration has no non-visual path, scripts emit unconditional ANSI color, and ~25-minute waits signal progress as bare dots.

### F. Cross-week coherence (Week 1 is the anchor; the anchor chain is loose)
- Week 4 is promised everywhere, does not exist, and Week 5 hard-requires it; the gap is explained nowhere.
- Duration math contradicts itself across four documents (26.5h vs 24.5h; ~90h vs ~96h vs 105.5h).
- Version pins conflict across READMEs (vLLM, CAPI/clusterctl).
- Week 3's only lab requires Labs 3.1/3.2, which do not exist.
- Root README misdescribes Week 1's content ("GPU HW", "BMC"); the glossary defines none of Week 1's core terms.

### G. Resources (never previously audited)
The cheat-sheet's Grafana block is unusable (wrong secret key, no username, no tunnel context), its troubleshooting tree uses an invented `tag:cluster` EC2 filter that always returns empty, its alias table contradicts the provisioned aliases, and it presents cluster-scoped CRDs as namespaced. Reference-links mixes OSS-latest and Enterprise-1.2.x doc targets.

### H. Capacity (critic finding — needs a live-run check)
Nobody has summed resource requests against allocatable: one t3.xlarge (16GB) hosts k0s + kcm + CAPI + Envoy + the entire 4-chart KOF mothership; one t3.medium worker (4GB) accumulates kof-child collectors + cert-manager + kyverno + ingress-nginx by Lab 1.7. Pending/OOMKilled failures would be indistinguishable from the broken-expected-output defects above.

---

## What genuinely works (unchanged from prior audit, reaffirmed)
The AWS CCM deep-dive, the three-layer credential model teaching, the SSO/`ExpiredToken` and cert-manager-CRD gotchas, the conditions-array readiness pattern, the honest training-vs-production caveats, and the "Resuming This Lab" *concept* (execution needs the state-restore fix above) are all above-average, customer-transferable material. The week is worth fixing.

---

## Prioritized roadmap (merging both audits)

**P0 — Learner-breaking flow + money (do first, ~1–2 days of edits)**
1. Lab 1.5 cleanup → conditional "skip if continuing" (N1).
2. Lab 1.7 footer → "Next: Lab 1.8"; move week-complete + Week-2 link to Lab 1.8 (new) — and fix the dead `week-2-bmaas/README.md` links.
3. Prior-audit C1 teardown gap + C2 capstone name break + C4 `k0s backup/restore` + C5 Azure heredoc (still open).
4. Fix every impossible expected output in Labs 1.6/1.7 (3/3 services, single-cluster numbers) and resolve the kof-child↔baseline-services cert-manager collision with an explicit branch note.
5. `lab-provision.sh` output/exit fix (N2) and `lab-destroy.sh` exit-0-on-init-failure fix.
6. One cost lifecycle policy across README/labs/cheat-sheet + documented pause path.

**P1 — Trust + safety (same sprint)**
7. Quota pre-flight + shared-account guidance + state locking (N3).
8. Grafana tunnel → `lab-connect.sh --tunnel 3000:3000` (N4).
9. Lab-env security floor: default bastion CIDR to caller IP, wire or delete `ALLOWED_SSH_CIDRS`, `http_tokens=required` on all instances, stop passing secrets as SSH args.
10. Rewrite `prerequisites.md` to the real entry contract (N5); state OS support (WSL2) explicitly.
11. Prior-audit theory-accuracy batch (C3 + A-items) and quiz arithmetic/Q17/Q19 fixes, plus the new Q19 four-vs-three-tags and RBAC-exercise completion.

**P2 — Systemic (prevents regression; the architect-level item)**
12. **Add CI**: lychee link-check, shellcheck, `terraform fmt -check` + `validate`, and a grep gate that every `terraform output` consumed by scripts/labs exists. Remove the stray committed `lab-infrastructure/lab-infrastructure/` and `networking/terraform/` trees.
13. Resume-state hygiene: every "Resuming This Lab" block re-exports its env vars and tells SSO users to refresh credentials.
14. Day-5 restructure + Theory 1.4 (Day-2 ops) from the prior audit; assessment delivery model decision (self-check vs graded + facilitator guide).
15. Capacity validation on a live run; accessibility pass (diagram text alternatives, non-visual Lab 1.2 path, NO_COLOR).
16. Decide the Week 2/4 story: either build the missing product surface weeks honestly or rescope the curriculum map.

---

*Method: 7 finder agents (infrastructure, resources, pedagogy, cross-week, accessibility, learner-floor, copy-paste walkthrough) → adversarial verifier per critical/major finding (2 findings refuted and dropped) → completeness critic (5 gaps recorded). 56 agents total. Prior-audit findings were excluded from finders and re-checked separately; zero duplicates survived verification.*
