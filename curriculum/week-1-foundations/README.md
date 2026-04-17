# Week 1: k0rdent Enterprise Installation & Configuration

**Duration:** 26.5 hours
**Focus:** k0rdent Enterprise deployment, architecture understanding, production-ready configuration

## Learning Objectives

By the end of this week, you will be able to:

- [ ] Describe k0rdent Enterprise architecture (KCM, KSM, KOF)
- [ ] Deploy k0rdent Enterprise on a k0s Kubernetes cluster
- [ ] Configure k0rdent Enterprise for production readiness
- [ ] Navigate the k0rdent UI and understand key concepts
- [ ] Set up infrastructure providers (AWS, Azure, vSphere)
- [ ] Configure credential management and RBAC
- [ ] Understand cluster templates and management clusters

## Schedule

| Day | Content | Duration | Type |
|-----|---------|----------|------|
| 1 | Theory: k0rdent Architecture Deep Dive | 2h | Video/Reading |
| 1 | Lab 1.1: Provision k0rdent Management Cluster | 3h | Hands-on |
| 2 | Theory: k0rdent Components (KCM, KSM, KOF) | 2h | Video/Reading |
| 2 | Lab 1.2: Explore k0rdent UI and Configuration | 2.5h | Hands-on |
| 3 | Theory: Infrastructure Providers and Cluster API | 1.5h | Video/Reading |
| 3 | Lab 1.3: Configure AWS Infrastructure Provider | 3h | Hands-on |
| 4 | Lab 1.4: Production Configuration and RBAC | 3h | Hands-on |
| 4 | Lab 1.5: Provision Your First Managed Cluster | 2.5h | Hands-on |
| 5 | Lab 1.6: Deploy KOF (Observability & FinOps) | 3h | Hands-on |
| 5 | Lab 1.7: Multi-Cluster Services | 2h | Hands-on |
| 5 | Lab 1.8: Upgrade k0rdent Enterprise | 1.5h | Hands-on |
| 5 | Week 1 Assessment | 0.5h | Quiz |

## Theory Content

- [1.1 k0rdent Enterprise Architecture](theory/1.1-k0rdent-architecture.md)
- [1.2 k0rdent Components Deep Dive](theory/1.2-k0rdent-components.md)
- [1.3 Infrastructure Providers and CAPI](theory/1.3-infrastructure-providers.md)

## Lab Exercises

- [Lab 1.1 - Provision k0rdent Management Cluster](labs/lab-1.1-provision-k0rdent.md)
- [Lab 1.2 - Explore k0rdent UI](labs/lab-1.2-explore-k0rdent-ui.md)
- [Lab 1.3 - Configure AWS Provider](labs/lab-1.3-configure-aws-provider.md)
- [Lab 1.4 - Production Configuration](labs/lab-1.4-production-configuration.md)
- [Lab 1.5 - Provision Your First Managed Cluster](labs/lab-1.5-provision-managed-cluster.md)
- [Lab 1.6 - Deploy KOF (Observability & FinOps)](labs/lab-1.6-deploy-kof.md)
- [Lab 1.7 - Multi-Cluster Services](labs/lab-1.7-multicluster-services.md)
- [Lab 1.8 - Upgrade k0rdent Enterprise](labs/lab-1.8-upgrade-k0rdent.md)

## Version Compatibility

These labs are validated against the repo-pinned versions and installation behavior below. Official Mirantis documentation may show newer releases; follow the versions in this table when working through Week 1 exactly.

| Component | Version | Used In |
|-----------|---------|---------|
| k0rdent Enterprise | 1.2.2 | Lab 1.1 (auto-installed); upgrade to 1.2.3 in Lab 1.8 |
| k0s | v1.32.4+k0s.0 | Lab 1.1 (auto-installed) |
| Flux CLI | Installed by the upstream install script during provisioning (version may vary) | Lab 1.1 (auto-installed) |
| clusterctl | v1.12.4 | Lab 1.1 (auto-installed) |
| k0sctl | v0.19.4 | Lab 1.1 (auto-installed) |
| KOF charts | 1.5.0 | Lab 1.6 |
| cert-manager ServiceTemplate | 1.16.2 | Lab 1.7 |
| ingress-nginx ServiceTemplate | 4.11.0 | Labs 1.2, 1.7 |
| kyverno ServiceTemplate | 3.2.6 | Lab 1.7 |

> **Tip:** If a hardcoded version is unavailable, check what's available:
> ```bash
> # List available cluster templates
> kubectl get clustertemplates -n kcm-system
> # List available service templates
> kubectl get servicetemplates -n kcm-system
> ```

## Lab Architecture

```
                YOUR MACHINE
                  |       |
    SSH (lab-     |       |  Browser (k0rdent UI)
    connect.sh)   |       |
                  v       v
              +--------------+     +---------------------+
              |   Bastion    |     | AWS NLB (auto-      |
              |   Host       |     | provisioned by CCM) |
              +------+-------+     +----------+----------+
                     |                        |
                     | SSH jump               | Envoy Gateway
                     v                        v
         +-------------------------------------------+
         |  Management Cluster         Labs 1.1-1.4  |
         |  (k0s + k0rdent)                          |
         |  Envoy Gateway → k0rdent UI (:3000)       |
         |  KCM  |  KSM  |  KOF     Lab 1.6 (KOF)   |
         |  CAPI providers           Lab 1.3 (AWS)   |
         +-------------------+-----------------------+
                             |
                             | Cluster API provisioning
                             v
         +-------------------------------------------+
         |  Managed Cluster          Lab 1.5         |
         |  (AWS EC2 / k0s)                          |
         |                                           |
         |  cert-manager             Lab 1.7         |
         |  ingress-nginx            (services)      |
         |  kyverno                                  |
         +-------------------------------------------+
```

## Estimated AWS Cost

| Resource | Hourly Cost | When Active |
|----------|-------------|-------------|
| Management cluster (t3.xlarge) | ~$0.17/hr | Labs 1.1-1.7 |
| NAT Gateway | ~$0.045/hr | Labs 1.1-1.7 |
| AWS NLB (k0rdent UI via Envoy Gateway) | ~$0.023/hr | Labs 1.1-1.7 |
| Managed cluster (2x t3.medium) | ~$0.15/hr | Labs 1.5-1.7 |
| **Total (all running)** | **~$0.39/hr** | |

> Running 8 hours/day for 5 days: **~$15-25 total**. Remember to destroy environments when not in use -- see cleanup instructions at the end of each lab.

## Prerequisites

- AWS Account with appropriate permissions
- Basic Kubernetes knowledge
- Familiarity with Terraform

## Resources

- [k0rdent Enterprise Documentation](https://docs.mirantis.com/k0rdent-enterprise/latest/)
- [Reference Links](resources/reference-links.md)
- [Cheat Sheets](resources/cheat-sheets.md)

## Assessment

Complete the [Week 1 Quiz](week-1-quiz.md) after finishing all labs.

**Passing Score:** 80%

## Next Steps

After completing Week 1, proceed to [Week 2: Bare Metal as a Service](../week-2-bmaas/README.md)
