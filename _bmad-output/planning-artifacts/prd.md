---
stepsCompleted: [1, 2, 3, 4, 5-skipped, 6-skipped, 7, 8, 9, 10, 11]
workflowStatus: complete
inputDocuments:
  - curriculum/k0rdent-ai-infrastructure-training-curriculum.md
  - README.md
workflowType: 'prd'
lastStep: 11
documentCounts:
  briefs: 0
  research: 0
  brainstorming: 0
  projectDocs: 2
scope: "Critical Path - Week 1 + Week 5"
projectType: "developer_tool_edtech_hybrid"
domain: "edtech"
complexity: "medium"
---

# Product Requirements Document - k0rdent-ai-training

**Author:** Moustapha
**Date:** 2026-01-06

## Executive Summary

The k0rdent AI Infrastructure Training is a hands-on enablement program that prepares Mirantis engineers to deploy k0rdent Enterprise and configure production-ready AI infrastructure for customers.

**Critical Path Focus:** Week 1 (k0rdent Foundations) + Week 5 (AI Workloads)

**Primary Outcome:** Engineers who complete this training can:
1. Deploy a k0rdent Enterprise management cluster
2. Serve a model endpoint using vLLM or equivalent
3. Explain and configure underlying AI infrastructure technologies (NVLink, RDMA, GPUDirect, NUMA, MIG, SR-IOV)

### What Makes This Special

- **Hands-on first:** 70% labs, 30% theory. Engineers learn by deploying real infrastructure on AWS.
- **Deep technical understanding:** Goes beyond k0rdent to teach the AI infrastructure stack (GPU topology, high-performance networking, memory architecture).
- **Modular design:** Week 1 foundation enables any Week 5 AI workload lab. No forced linear path.
- **Production-ready:** Engineers don't just follow runbooks—they understand WHY things work to troubleshoot and advise customers.

### The Gap This Fills

k0rdent documentation explains WHAT. This training teaches WHY and HOW—the deep technical knowledge required to configure AI workloads at enterprise scale.

## Project Classification

| Attribute | Value |
|-----------|-------|
| **Technical Type** | Developer Tool / EdTech Hybrid |
| **Domain** | Internal Enablement (EdTech) |
| **Complexity** | Medium |
| **Project Context** | Brownfield - completing existing curriculum |
| **Scope** | Critical Path: Week 1 + Week 5 |
| **Timeline** | 1 month to rollout |

## Success Criteria

### User Success (Engineer Experience)

**The "Aha Moment":** Engineer deploys k0rdent → provisions AI workload → serves model endpoint → understands WHY the infrastructure works.

| Metric | Target | Measurement |
|--------|--------|-------------|
| Critical Path completion | 80%+ of engineers | Assessment pass rate |
| Time to competency | ~1 week | Time from start to serving model endpoint |
| Deep understanding | Can explain NVLink/RDMA/GPUDirect | Technical assessment questions |
| Customer-ready | Can troubleshoot, not just follow runbooks | Scenario-based evaluation |

**Key Checkpoints:**
- **Day 1-2:** k0rdent management cluster deployed (Week 1 Labs 1.1-1.4)
- **Day 3-5:** AI workload running, model endpoint serving (Week 5 Labs)
- **Day 5-7:** Buffer for exploration, custom scenarios, troubleshooting practice

### Business Success (Mirantis Outcomes)

| Metric | Target | Timeline |
|--------|--------|----------|
| Engineers enabled | 15+ per cohort | Per training run |
| Deployment velocity | Reduce onboarding time | 30-day checkpoint |
| Customer escalation reduction | Fewer "I don't know why this works" situations | 90-day checkpoint |
| Assessment pass rate | 80%+ | Per cohort |
| Cost per cohort | ≤ $2,300 | AWS spend with spot instances |

**Budget Breakdown:**
- Spot instances: 60-70% savings vs on-demand
- TTL enforcement: Auto-terminate after lab window
- Shared GPU resources: p3.8xlarge pooled across engineers
- Target: $2,000-2,300 per 15-engineer cohort

### Technical Success (Platform Quality)

| Metric | Target |
|--------|--------|
| Lab provisioning success | 95%+ first-try success rate |
| Cloud-init reliability | Scripts complete without manual intervention |
| Content accuracy | All commands work as documented |
| Infrastructure tear-down | Clean destruction, no orphaned resources |

### Product Scope

#### MVP (Week 1 + Week 5 Critical Path)

**Must work to be useful:**
- [ ] Week 1: k0rdent Foundations (4 labs)
  - Lab 1.1: Provision k0rdent Management Cluster
  - Lab 1.2: Explore k0rdent UI
  - Lab 1.3: Configure AWS Provider
  - Lab 1.4: Production Configuration
- [ ] Week 5: AI Workloads - vLLM Lab (primary)
  - Deploy vLLM on k0rdent-managed cluster
  - Serve model endpoint
  - Understand GPU operator, NVIDIA driver stack

**Theory content (with placeholders for SME input):**
- k0rdent Architecture (KCM, KSM, KOF)
- Infrastructure Providers & CAPI
- AI Infrastructure Deep Dive (NVLink, RDMA, GPUDirect, NUMA, MIG, SR-IOV)

#### Growth (Post-MVP)

**Competitive differentiators:**
- [ ] Remaining Week 5 labs (Run:AI, Kubeflow, MLflow)
- [ ] Week 2: Bare Metal as a Service (Metal3, Ironic)
- [ ] Week 3: Virtual Machines as a Service (KubeVirt)
- [ ] Airgap deployment module (MSR 4 / Harbor)

#### Vision (Future)

**Where this could go:**
- Full 6-week certification program
- Customer-facing training option (currently OUT OF SCOPE)
- Self-paced online version
- Integration with Mirantis University

## User Journeys

### Journey 1: Alex Chen - From Kubernetes Admin to AI Infrastructure Expert

Alex is a Mirantis systems engineer with 3 years of Kubernetes experience. He's confident managing clusters but feels uncertain when customers ask about AI workloads—NVLink, GPUDirect, RDMA feel like a foreign language. His manager assigns him to the AI Infrastructure Training, and Alex forks the training repo on a Monday morning.

Day 1 starts with a familiar feeling: running Terraform. But this time, the infrastructure he's deploying isn't just another k8s cluster—it's a k0rdent management plane. The lab provisions, he SSHs in, and suddenly he's exploring CRDs he's never seen before: `Management`, `ClusterTemplate`, `ClusterDeployment`. By end of day, he's deployed his first k0rdent cluster and understands how KCM orchestrates Cluster API providers.

The real breakthrough comes on Day 4. Alex deploys a vLLM workload and watches the NVIDIA GPU Operator configure the driver stack. When the model endpoint serves its first inference, something clicks. He reads the theory on NVLink topology and finally understands WHY p3 instances have NVSwitch fabric. That evening, Alex confidently explains to a colleague how GPUDirect RDMA bypasses the CPU for GPU-to-GPU communication.

Six weeks later, a customer calls with a stuck GPU workload. Alex asks the right question: "What's your NUMA configuration?" He knew to ask because he lived through the training labs. He's no longer just following runbooks—he's diagnosing infrastructure at the architectural level.

### Journey 2: Alex Chen - The 2 AM Spot Instance Termination

Same Alex, Day 3. Everything was going smoothly until his spot instance gets reclaimed at 2 AM. When he reconnects the next morning, his management cluster is gone.

For a moment, panic. But then he remembers the training emphasized TTL-based infrastructure and the re-provision workflow. He runs `./scripts/lab-provision.sh k0rdent alex-chen --auto-approve` and in 15 minutes, he's back where he started. The cloud-init scripts handle everything—k0s installation, k0rdent deployment, even restoring his aliases.

What could have been a frustrating setback becomes a learning moment: this is exactly what happens in production. Infrastructure fails. The training taught him the recovery path, not just the happy path.

### Journey 3: Sarah Torres - The Training Administrator

Sarah is the Mirantis enablement lead responsible for running the Q2 cohort of 15 engineers. Two weeks before training starts, she needs to validate the environment and manage costs.

She starts by reviewing the cost estimate in the README: ~$2,300 per cohort with spot instances and TTL enforcement. She creates the shared infrastructure once (`./scripts/lab-provision.sh shared`), sets up the S3 bucket for Terraform state, and validates the bastion host connectivity.

On Day 1 of training, she monitors the `lab-status.sh all` command, watching engineers spin up their individual environments. When one engineer reports a networking issue, she SSHs through the bastion and checks the cloud-init logs at `/var/log/k0rdent-init.log`. The issue is a transient EC2 capacity error—she advises the engineer to retry in a different AZ.

At the end of the week, Sarah runs `lab-destroy.sh` for any lingering environments, ensuring the TTL enforcement keeps costs within budget. She reports back to leadership: 14 of 15 engineers completed the Critical Path, total AWS spend: $2,150.

### Journey 4: Marcus Webb - The Content Contributor

Marcus is a solutions architect who just helped a customer solve a complex MIG (Multi-Instance GPU) configuration issue. His manager suggests he contribute this knowledge back to the training.

He clones the training repo, navigates to `curriculum/week-5-ai-workloads/theory/`, and finds the `[PLACEHOLDER]` markers in the AI infrastructure deep dive section. Perfect—he can add the MIG configuration content here.

Marcus follows the contribution pattern: theory file references hands-on lab, lab includes troubleshooting section based on real customer scenarios. He writes the content, tests the commands on his own AWS environment, and opens a PR.

The PR template asks him to verify: "Commands copy-paste correctly? Screenshots current? Theory matches lab?" He checks all boxes, and the training repo now includes battle-tested MIG content from a real customer engagement.

### Journey Requirements Summary

| Journey | Capabilities Revealed |
|---------|----------------------|
| Engineer Success Path | Lab provisioning, k0rdent deployment, vLLM serving, theory-to-practice connection |
| Engineer Edge Case | Infrastructure recovery, spot instance handling, cloud-init reliability |
| Training Admin | Multi-tenant provisioning, cost monitoring, bastion connectivity, troubleshooting |
| Content Contributor | Content contribution workflow, PR templates, theory-lab linkage |

## Developer Tool / EdTech Hybrid Requirements

### Project-Type Overview

This project combines two technical domains:
1. **EdTech**: Structured curriculum with theory modules and lab exercises
2. **Developer Tool**: Infrastructure-as-code platform for provisioning lab environments

The hybrid nature means requirements span both educational content delivery and infrastructure automation.

### Technical Architecture Considerations

#### Content Delivery Model
- **Repository-based**: Engineers fork/template the GitHub repo
- **Markdown curriculum**: Theory and lab content in `curriculum/` directory
- **Copy-paste friendly**: All commands templated for direct execution
- **Progressive structure**: Week 1 foundations enable Week 5 AI workloads

#### Lab Infrastructure Model
- **Terraform modules**: Reusable infrastructure components
- **Cloud-init automation**: k0s + k0rdent installation scripts
- **Per-engineer isolation**: Unique Terraform state per `<engineer-id>`
- **Bastion connectivity**: SSH tunneling through shared bastion host
- **Cost optimization**: Spot instances, TTL enforcement, shared GPU pools

#### Content-Infrastructure Linkage
- Theory files reference corresponding lab files
- Labs include troubleshooting sections for common issues
- `[PLACEHOLDER]` markers for SME contributions
- Aliases and helper scripts for improved DX

### Implementation Considerations

#### Content Maintenance
- PR-based contribution model
- Validation checklist: "Commands work? Screenshots current?"
- Version pinning for k0s, k0rdent, NVIDIA Operator

#### Lab Reliability
- Cloud-init scripts must complete without manual intervention
- 95%+ first-try provisioning success rate target
- Clean tear-down with no orphaned AWS resources

#### Assessment Model
- Hands-on validation: "Deploy k0rdent and serve model endpoint"
- Technical understanding: "Explain NVLink/RDMA/GPUDirect"
- Scenario-based troubleshooting exercises

## Project Scoping & Phased Development

### MVP Strategy & Philosophy

**MVP Approach:** Problem-Solving MVP
- Solve the core problem: Engineers need hands-on k0rdent + AI infrastructure knowledge
- Minimum viable: Deploy k0rdent → Serve model endpoint → Understand WHY

**Resource Requirements:**
- Primary Author: 1 (current state)
- SME Contributors: As available for `[PLACEHOLDER]` content
- Infrastructure: Existing Terraform modules + cloud-init scripts

### MVP Feature Set (Phase 1 - Critical Path)

**Core User Journeys Supported:**
- Engineer Success Path (Alex Chen - Day 1-5)
- Engineer Edge Case (Spot instance recovery)

**Must-Have Capabilities:**

| Week | Labs | Status |
|------|------|--------|
| Week 1 | Lab 1.1: Provision k0rdent Management Cluster | Validated |
| Week 1 | Lab 1.2: Explore k0rdent UI | Pending validation |
| Week 1 | Lab 1.3: Configure AWS Provider | Pending validation |
| Week 1 | Lab 1.4: Production Configuration | Pending validation |
| Week 5 | vLLM Lab: Deploy and serve model endpoint | To create |

**Must-Have Theory:**
- k0rdent Architecture (KCM, KSM, KOF)
- Infrastructure Providers & CAPI
- AI Infrastructure Deep Dive (NVLink, RDMA, GPUDirect, NUMA, MIG)

### Post-MVP Features

**Phase 2 (Growth - Remaining Week 5):**
- Run:AI integration lab
- Kubeflow/MLflow deployment
- Multi-model serving patterns

**Phase 3 (Expansion - Full Curriculum):**
- Week 2: Bare Metal as a Service (Metal3, Ironic)
- Week 3: Virtual Machines as a Service (KubeVirt)
- Week 4: Kubernetes as a Service (CAPI deep dive)
- Week 6: Full-stack capstone project

**Phase 4 (Vision):**
- Certification program
- Self-paced online version
- Mirantis University integration

### Risk Mitigation Strategy

**Technical Risks:**

| Risk | Mitigation |
|------|------------|
| Cloud-init failures | Test scripts on fresh instances, add retry logic |
| Spot instance termination | Document re-provision workflow, use TTL enforcement |
| GPU capacity constraints | Use shared p3.8xlarge, schedule cohort GPU time |

**Content Risks:**

| Risk | Mitigation |
|------|------------|
| Stale k0rdent versions | Pin versions, document upgrade path |
| Missing SME content | `[PLACEHOLDER]` markers, PR contribution workflow |
| Commands that don't work | Validation checklist in PR template |

**Budget Risks:**

| Risk | Mitigation |
|------|------------|
| Cost overrun | TTL enforcement, spot instances, destroy scripts |
| Orphaned resources | `lab-destroy.sh` automation, AWS billing alerts |

## Functional Requirements

### Lab Provisioning

- FR1: Engineer can fork/template the training repository to create their own copy
- FR2: Engineer can provision a k0rdent management cluster using a single command
- FR3: Engineer can specify their unique engineer-id for resource isolation
- FR4: Engineer can connect to the management cluster via SSH through bastion
- FR5: Engineer can verify k0rdent installation status via logs and completion markers
- FR6: Engineer can access the k0rdent UI via port-forwarding

### Lab Operations

- FR7: Engineer can check the status of their lab environment
- FR8: Engineer can destroy their lab environment cleanly
- FR9: Engineer can re-provision after spot instance termination
- FR10: Engineer can use pre-configured kubectl aliases for common operations
- FR11: Engineer can view k0rdent CRDs and resources

### Curriculum Access

- FR12: Engineer can navigate Week 1 theory modules in sequential order
- FR13: Engineer can navigate Week 5 theory modules after completing Week 1
- FR14: Engineer can copy-paste commands directly from lab documentation
- FR15: Engineer can reference theory content while completing labs
- FR16: Engineer can view learning objectives for each module

### k0rdent Configuration (Week 1)

- FR17: Engineer can explore the k0rdent UI dashboard
- FR18: Engineer can configure AWS infrastructure provider credentials
- FR19: Engineer can view available cluster templates
- FR20: Engineer can understand credential management model
- FR21: Engineer can configure production-ready k0rdent settings

### AI Workload Deployment (Week 5)

- FR22: Engineer can deploy vLLM on a k0rdent-managed cluster
- FR23: Engineer can serve a model endpoint
- FR24: Engineer can verify model inference is working
- FR25: Engineer can understand GPU Operator configuration
- FR26: Engineer can explain NVLink, RDMA, GPUDirect concepts

### Cohort Administration

- FR27: Admin can provision shared infrastructure once per cohort
- FR28: Admin can monitor all engineer environments via status commands
- FR29: Admin can track AWS costs against cohort budget
- FR30: Admin can destroy lingering environments after training window
- FR31: Admin can troubleshoot engineer provisioning issues via bastion

### Content Contribution

- FR32: Contributor can identify content gaps via `[PLACEHOLDER]` markers
- FR33: Contributor can add theory content via pull requests
- FR34: Contributor can add lab content following established patterns
- FR35: Contributor can validate commands work before submitting PR
- FR36: Contributor can link theory files to corresponding lab files

### Assessment & Validation

- FR37: Engineer can demonstrate k0rdent deployment capability
- FR38: Engineer can demonstrate model endpoint serving capability
- FR39: Engineer can explain AI infrastructure concepts (NVLink, RDMA, etc.)
- FR40: Engineer can troubleshoot common infrastructure issues

## Non-Functional Requirements

### Performance

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Lab provisioning time | ≤15 minutes | Time from `lab-provision.sh` to SSH-ready |
| k0rdent installation | ≤15 minutes | Time from instance ready to `.init-complete` |
| Cloud-init completion | ≤20 minutes | Total bootstrap time |
| kubectl response time | ≤2 seconds | Time for standard kubectl commands |

### Reliability

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Provisioning success rate | 95%+ | First-try success without manual intervention |
| Cloud-init reliability | 99% | Scripts complete without errors |
| Re-provisioning recovery | 100% | Engineer can recover from spot termination |
| Clean destruction | 100% | No orphaned AWS resources after destroy |

### Maintainability

| Requirement | Approach |
|-------------|----------|
| Version pinning | All tool versions (k0s, k0rdent, NVIDIA Operator) pinned in cloud-init |
| Content updates | `[PLACEHOLDER]` markers for SME contributions |
| Command validation | PR checklist ensures commands work as documented |
| Curriculum structure | Clear week/theory/lab organization |

### Cost Efficiency

| Requirement | Target | Approach |
|-------------|--------|----------|
| Cohort budget | ≤$2,300 | Spot instances, TTL enforcement |
| Spot instance usage | 60-70% savings | Default to spot for all lab instances |
| Resource cleanup | Zero orphans | Automated destroy scripts, billing alerts |
| GPU sharing | Pooled p3.8xlarge | Shared across engineers, scheduled access |

### Integration

| System | Requirement |
|--------|-------------|
| AWS | CAPA provider, EC2, VPC, S3, IAM |
| Terraform | ≥1.5.0, S3 backend for state |
| k0rdent Enterprise | v1.2.1, kcm-system namespace |
| k0s | v1.32.4+k0s.0 |
| kubectl | Standard Kubernetes API access |
