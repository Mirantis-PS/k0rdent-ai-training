# Prerequisites

## Required Knowledge

### Kubernetes (Required)
- [ ] Can create and manage Deployments, Services, ConfigMaps, Secrets
- [ ] Understands Pod networking and Service discovery
- [ ] Familiar with RBAC (Roles, RoleBindings, ClusterRoles)
- [ ] Can use kubectl effectively
- [ ] Understands Persistent Volumes and Storage Classes
- [ ] Familiar with Helm charts

### Linux Administration (Required)
- [ ] Comfortable with command-line operations
- [ ] Can manage systemd services
- [ ] Understands networking (IP, routing, firewalls)
- [ ] Familiar with disk and storage management
- [ ] Can troubleshoot using logs and system tools

### Virtualization (Basic)
- [ ] Understands VM vs container concepts
- [ ] Familiar with hypervisor basics
- [ ] Knows what CPU/memory virtualization extensions are

### Infrastructure as Code (Helpful)
- [ ] Experience with Terraform or similar
- [ ] Familiar with declarative configuration
- [ ] Can read and modify YAML/JSON

## Technical Requirements

Labs are self-provisioned: you fork (or copy) this repository and run its Terraform against your own AWS account. There is no hosted lab portal.

### AWS Account
**Use one dedicated AWS account per learner for cohorts.** A shared account requires the controls below and an instructor responsible for ownership and cleanup.

- Your principal must be authorized to create the lab IAM roles, policies and instance profiles. Use an account approved for training; do not run the course in a production account.
- Historical platform-lab budget estimate (not a current quote): roughly **$25-50** (everything running 24/7 for 5 days ≈ $47; stopping instances outside an ~8h/day working window ≈ $25-30) — later weeks vary, see each week's README
- Check current VPC, Elastic IP, instance and GPU quotas in your chosen region before provisioning. Template networking choices and concurrent learners change the footprint; do not assume a fixed number of learners fits an account.

#### Shared-account controls

- Assign distinct engineer IDs and record the account, region, owner and resources for each lab. Do not reuse an ID while its resources remain.
- Activate `Owner` and `Project` cost-allocation tags before the cohort if your billing permissions allow it. Verify actual tag propagation: CAPA and other controllers may create resources without these tags.
- Assign a named person to review retained resources and cleanup after each session. Separate accounts improve accountability but do not automatically delete anything.
- Run the [report-only orphan scan](../../lab-infrastructure/README.md#lab-reapsh) after teardown and at agreed intervals. A successful scan covers only its documented tagged resource types; independently inspect managed-cluster and load-balancer resources.
- Stopping EC2 does not remove networking, storage or address charges. Record what is retained and use the [course finish/pause checklist](../README.md#finish-or-pause).

### Workstation
- macOS or Linux (Windows: use WSL2 with Ubuntu — native PowerShell/Git Bash are not supported); labs are driven by bash scripts
- AWS CLI v2 installed
- Terraform >= 1.8.0 installed
- Git installed, plus your own fork or copy of this training repository
- `jq` installed
- Browser (Chrome/Firefox recommended) and an SSH client

> kubectl, Helm, and the other cluster tooling are pre-installed on the lab instances — no local installation is required.

## Recommended Pre-Reading

If you need to brush up on Kubernetes:
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)

For GPU/NVIDIA background:
- [NVIDIA Data Center Documentation](https://docs.nvidia.com/datacenter/)
- [GPU Operator Overview](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/overview.html)

## Self-Assessment

Before starting, ensure you can:

1. Deploy a multi-container application on Kubernetes
2. Create network policies to restrict pod communication
3. Set up persistent storage for a stateful application
4. Debug a pod that won't start
5. Use Helm to install and configure a chart

If any of these are challenging, consider reviewing Kubernetes fundamentals first.
