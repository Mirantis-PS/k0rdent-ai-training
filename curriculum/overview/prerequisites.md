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

### For Local Development
- Workstation with 16GB+ RAM
- Docker or Podman installed
- kubectl installed
- Helm installed
- Git installed

### For Cloud Labs
- Browser (Chrome/Firefox recommended)
- SSH client
- Access to lab provisioning portal (provided)

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
