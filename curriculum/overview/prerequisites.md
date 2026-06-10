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
- A personal (or dedicated) AWS account where your principal can create IAM roles, policies, and instance profiles — effectively AdministratorAccess (the lab Terraform creates `aws_iam_role`, `aws_iam_role_policy`, and `aws_iam_instance_profile`)
- Budget for Week 1: roughly **$25-50** (everything running 24/7 for 5 days ≈ $47; stopping instances outside an ~8h/day working window ≈ $25-30) — later weeks vary, see each week's README
- Service quotas: the AWS default limits of **5 VPCs and 5 Elastic IPs per region** are exactly consumed by Week 1's footprint (management + managed cluster) — request increases beforehand, or use a dedicated account per student for cohorts

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
