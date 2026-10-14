# Week 1: k0rdent Enterprise Installation & Configuration

**Duration:** ~15-17 hours active (labs + quiz) plus 5.5 hours theory (~23-25 hours scheduled including unattended provisioning/upgrade waits)
**Focus:** k0rdent Enterprise deployment, architecture understanding, production-ready configuration

## Learning Objectives

By the end of this week, you will be able to:

- [ ] Describe k0rdent Enterprise architecture (KCM, KSM, KOF)
- [ ] Deploy k0rdent Enterprise on a k0s Kubernetes cluster
- [ ] Configure k0rdent Enterprise for production readiness
- [ ] Navigate the k0rdent UI and understand key concepts
- [ ] Set up the AWS infrastructure provider hands-on (Azure is an optional appendix in Lab 1.5; vSphere, GCP, and OpenStack are covered conceptually only)
- [ ] Configure credential management and RBAC
- [ ] Understand cluster templates and management clusters
- [ ] Deploy fleet services with the Service Catalog and MultiClusterService (Labs 1.2, 1.7)
- [ ] Upgrade k0rdent Enterprise (management plane 1.3.1 → 1.3.2, Lab 1.8)

## Schedule

| Day | Content | Active | Total* | Type |
|-----|---------|--------|--------|------|
| 1 | Theory: k0rdent Architecture Deep Dive | 2h | 2h | Video/Reading |
| 1 | Lab 1.1: Provision k0rdent Management Cluster | ~1h | ~1.5h | Hands-on |
| 2 | Theory: k0rdent Components (KCM, KSM, KOF) | 2h | 2h | Video/Reading |
| 2 | Lab 1.2: Explore k0rdent UI and Configuration | 2.5h | 2.5h | Hands-on |
| 3 | Theory: Infrastructure Providers and Cluster API | 1.5h | 1.5h | Video/Reading |
| 3 | Lab 1.3: Configure AWS Infrastructure Provider | ~1h | ~1h | Hands-on |
| 3 | Lab 1.4: Production Configuration and RBAC | 3.5h | 3.5h | Hands-on |
| 4 | Lab 1.5: Provision Your First Managed Cluster | ~1h | 2.5h | Hands-on |
| 4 | Lab 1.6: Deploy KOF (Observability & FinOps) | 3.5-4h Full / 2.5h Core | 3.5-4h Full / 2.5h Core | Hands-on |
| 5 | Lab 1.7: Multi-Cluster Services | 2h | 2h | Hands-on |
| 5 | Lab 1.8: Upgrade k0rdent Enterprise | ~45m | 1.5h | Hands-on |
| 5 | Week 1 Assessment (self-assessment quiz, target 80%) | 45-60m | 45-60m | Quiz |

\* **Total** includes unattended waits you don't actively work through: instance provisioning in Lab 1.1 (~15-20m), managed-cluster provisioning in Lab 1.5 (~30-40m, can overlap with reading Lab 1.6's intro), and upgrade rollouts in Lab 1.8 (~45m).

**Day totals (incl. waits):** Day 1 ≈ 3.5h · Day 2 ≈ 4.5h · Day 3 ≈ 6h · Day 4 ≈ 6-6.5h Full path (≈ 5h Core) · Day 5 ≈ 4.25-4.5h.

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
- [Lab 1.9 - Kubernetes API Audit Logging](labs/lab-1.9-api-audit-logging.md) *(supplemental — add 1.5 hours; retain clusters after Lab 1.8 until audit evidence is captured)*

## Version Compatibility

These are the repo-pinned versions. Live evidence is recorded in individual labs; a version pin alone does not certify every exercise. Official Mirantis documentation may show newer releases; follow the versions in this table when working through Week 1 exactly.

| Component | Version | Used In |
|-----------|---------|---------|
| k0rdent Enterprise | 1.3.1 | Lab 1.1 (auto-installed); upgrade to 1.3.2 in Lab 1.8 |
| k0s | v1.35.4+k0s.0 | Lab 1.1 (auto-installed) |
| Flux CLI | Installed by the upstream install script during provisioning (version may vary) | Lab 1.1 (auto-installed) |
| clusterctl | v1.12.4 | Lab 1.1 (auto-installed) |
| k0sctl | v0.19.4 | Lab 1.1 (auto-installed) |
| KOF charts | 1.6.0 | Lab 1.6 |
| cert-manager ServiceTemplate | 1.20.2 | Lab 1.7 |
| ingress-nginx ServiceTemplate | 4.15.1 | Legacy/migration elective only; use Gateway API for the baseline |
| kyverno ServiceTemplate | 3.8.1 | Lab 1.7 |

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
              |   Bastion    |     | AWS Classic ELB     |
              |   Host       |     | (provisioned by CCM)|
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

**In words:** From your machine you reach the lab two ways: an SSH session through the bastion host (via `lab-connect.sh`), and a browser session to the k0rdent UI through an AWS Classic ELB that the AWS cloud controller manager provisions for the Envoy Gateway service. Both paths land on the management cluster — k0s running k0rdent (KCM, KSM, KOF) plus the CAPI providers — which you provision in Lab 1.1, work on through Labs 1.2-1.4, extend with the AWS provider in Lab 1.3 and KOF in Lab 1.6, and upgrade in Lab 1.8. In Lab 1.5 the management cluster uses Cluster API to provision a managed cluster on AWS EC2; in Lab 1.7 you deploy fleet services (cert-manager, ingress-nginx, kyverno) to it.

## Estimated AWS Cost

| Resource | Hourly Cost | When Active |
|----------|-------------|-------------|
| Management cluster (t3.2xlarge) | ~$0.33/hr | Lab 1.1 onward (preserved through the program) |
| NAT Gateway | ~$0.045/hr | Lab 1.1 onward (preserved through the program) |
| AWS Classic ELB (k0rdent UI via Envoy Gateway) | ~$0.023/hr | Lab 1.1 onward (preserved through the program) |
| Managed cluster (2x t3.medium) | ~$0.15/hr | Labs 1.5-1.8 (torn down at end of Lab 1.8) |
| **Total (all running)** | **~$0.55/hr** | |

> **Cost lifecycle:** The management cluster is provisioned once in Lab 1.1 and **preserved through the program** — do not destroy it between labs or weeks. Keep it running during the week; between sessions or weeks, pause it with `aws ec2 stop-instances` (guidance at the end of Lab 1.8). While instances are stopped, the NAT Gateway, Elastic IPs, and EBS volumes still bill ~$2/day. The managed clusters from Labs 1.5-1.7 are torn down at the end of Lab 1.8.
>
> **Week 1 estimate:** everything running 24/7 for 5 days ≈ **$66** ($0.55/hr × 120h); stopping instances outside an ~8h/day working window brings it to roughly **$35-40**.

## Prerequisites

- AWS Account with appropriate permissions
- AWS service quotas: the default limits of 5 VPCs and 5 Elastic IPs per region are exactly consumed by this week's footprint (management + managed cluster) — request increases beforehand, or use a dedicated account per student for cohorts
- AWS CLI v2, Terraform >= 1.8.0, and `jq` installed
- macOS or Linux workstation (Windows: use WSL2 with Ubuntu — native PowerShell/Git Bash are not supported)
- Basic Kubernetes knowledge
- Familiarity with Terraform

## Resources

- [k0rdent Enterprise Documentation](https://docs.mirantis.com/k0rdent-enterprise/latest/)
- [Reference Links](resources/reference-links.md)
- [Cheat Sheets](resources/cheat-sheets.md)

## Assessment

Complete the [Week 1 Quiz](week-1-quiz.md) after finishing all labs. The quiz is a self-assessment (45-60 minutes).

**Target Score:** 80%

## Next Steps

After completing Week 1, proceed to [Week 2: Bare Metal as a Service](../week-2-bmaas/README.md)
