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

**One dedicated AWS account per student. For cohorts this is a requirement, not a preference.**

- The account must let your principal create IAM roles, policies, and instance profiles — effectively AdministratorAccess (the lab Terraform creates `aws_iam_role`, `aws_iam_role_policy`, and `aws_iam_instance_profile`)
- Budget for Week 1: roughly **$25-50** (everything running 24/7 for 5 days ≈ $47; stopping instances outside an ~8h/day working window ≈ $25-30) — later weeks vary, see each week's README
- Service quotas: the AWS default limits of **5 VPCs and 5 Elastic IPs per region** are exactly consumed by Week 1's footprint (management + managed cluster) — request increases beforehand. A shared account exhausts these fastest, and the failure surfaces mid-lab as an opaque Terraform error.

#### Why a shared account causes problems

A shared account was tried and it accumulated abandoned infrastructure. Ten people left twelve Terraform state buckets behind, and four environments across four regions were still billing long after their owners had moved on — the oldest for over five months, together on the order of **$1,000** with roughly **$130/month** still accruing.

The mechanics are unforgiving rather than careless. The costly resource is the NAT gateway, which bills for as long as it exists regardless of whether any instance is running, so stopping instances does not stop the charge. Once resources belong to nobody in particular, nobody reconciles them.

Separate accounts fix this structurally: each student's spend is visible on their own bill, and cleaning up is unambiguously one person's job.

#### If you must share an account

- Give every student a distinct engineer-id and never reuse one; all resources are tagged `Owner=<engineer-id>`.
- Activate **`Owner` and `Project` as cost-allocation tags** in Billing before the cohort starts. Without this, Cost Explorer cannot attribute spend per student — costs can only be inferred from resource creation timestamps.
- Run the orphan scan on a schedule and after each week:
  ```bash
  ./lab-infrastructure/scripts/lab-reap.sh
  ```
  It reports every surviving environment across all regions and exits non-zero when anything is flagged, so it can drive a cron job or CI alert.
- Raise the VPC and Elastic IP quotas first: with the defaults, roughly two concurrent students exhaust a region.

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
