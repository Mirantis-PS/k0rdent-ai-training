# Module 1.1 live QA — 2026-09-08

**Result: PASS for Theory 1.1 + Lab 1.1's technical learning outcome, with documentation and preflight corrections proposed.**

Scope: provision an AWS management environment, connect through the bastion, verify k0s and k0rdent Enterprise, authenticate to the UI, and trace its AWS/Gateway routing. No Lab 1.2 or later module was started. Teardown and workload-cluster provisioning are not covered by this result.

## Execution

- Baseline: `e6899577873ea301a4ece55dd1ecbfe829868c7d` (current main at the start of the run).
- Region: `eu-west-1`; a new, isolated QA engineer ID was used with an existing AWS SSO profile.
- The baseline provisioning script ran **before** applying the proposed changes.
- Command: `./scripts/lab-provision.sh qa-w1-20260908 --region eu-west-1 --auto-approve`.
- Started 10:55:23 UTC; finished 11:02:22 UTC, exit 0 (6m59s).
- Remote acceptance commands ran 11:03:04–11:06:28 UTC, exit 0.
- Final independent health snapshot at 11:07:51 UTC: 1/1 node Ready, 50 pods, zero unhealthy pods across five namespaces.
- Runtime: k0s v1.35.4+k0s.0 and k0rdent Enterprise 1.3.1.

| Check executed | Observed result |
|---|---|
| Existing profile: STS and EC2 read APIs | Passed before provisioning; validated again with the new helper |
| Terraform apply | New management node, bastion and supporting AWS infrastructure created |
| `./scripts/lab-connect.sh qa-w1-20260908` | Real SSH session through bastion; remote user `ubuntu` |
| Initialization marker and `sudo cloud-init status` | Marker present; initialization done |
| `sudo k0s status` | Controller running with workloads enabled; API probe successful |
| `kubectl get nodes` | One Ready management node |
| `kubectl get pods -A` and final readiness inspection | All 50 pods healthy after initialization settled |
| k0rdent CRD enumeration | Management, ClusterDeployment, ClusterTemplate, Credential and other k0rdent CRDs installed |
| `kubectl wait management kcm --for=condition=Ready=True --timeout=300s` | Condition met within the documented timeout |
| `kubectl get clustertemplates -A` | 18 valid templates |
| `kubectl get credentials -A` / `clusterdeployments -A` | Both empty, as expected before later labs |
| `lab-connect.sh --ui-url` and `--show-gateway` | Exit 0; Gateway programmed; Envoy pods Ready |
| Actual browser sign-in with generated credentials | Authenticated Dashboard loaded as admin; Cluster Templates page listed the same 18 valid templates |
| Node providerID → AWS instance tag → LoadBalancer Service | Instance identity and cluster ownership tag match; Service and Gateway share the same ELB hostname |
| Sveltos and Envoy namespaces | Healthy in final snapshot |
| Fish source of generated `qa-aws.fish`, followed by real STS | Passed; returned the expected account |

Initial pod listings contained normal startup/rollout states. They were not treated as success: Management readiness was awaited and all pods were inspected again after it passed. The UI displayed an unlicensed banner while login and catalog access worked; this run does not establish training license entitlement.

## Learning value and changes

The module is coherent as a management-plane bootstrap exercise for experienced engineers. The AWS identity, Kubernetes resource and Gateway trace gives it practical value beyond running a wrapper. It does not need a major restructure.

The proposed changes address specific learner gaps:

1. Make completion depend on Management readiness, ready containers and authenticated UI access. A process exit or reachable login page alone is insufficient.
2. Label workstation and SSH commands explicitly so learners do not try to run local helper scripts on the management node.
3. Explain Bash versus Fish syntax, support an already-configured AWS profile, and provide a read-only helper that writes shell-specific selections without saving access keys.
4. Correct the documented S3 bucket name to include its region.
5. Preserve actual STS errors rather than telling a learner with an expired session or unreachable endpoint to configure new credentials.
6. Add two applied architecture questions about provider-specific templates and credential access, and route Theory 1.1 to its lab before Theory 1.2.

The latest main already corrected the earlier theory claims about portable templates and Secret encoding; those corrections were retained.

## Open PR review

Reviews were submitted against the exact heads inspected, with isolated reproductions where applicable. No PR was merged and no destructive PR test touched AWS resources.

| PR | Review | Evidence / finding |
|---|---|---|
| [14](https://github.com/Mirantis-PS/k0rdent-ai-training/pull/14) | Approved | Force, auto-approve and non-TTY gate cases executed |
| [15](https://github.com/Mirantis-PS/k0rdent-ai-training/pull/15) | Changes requested | Missing Owner tag lets a potentially owned CAPA resource bypass the orphan gate |
| [16](https://github.com/Mirantis-PS/k0rdent-ai-training/pull/16) | Changes requested | Failed instance inventory and pending instances both reproduce false orphan classification before deletion |
| [17](https://github.com/Mirantis-PS/k0rdent-ai-training/pull/17) | Approved | Four CIDR precedence/recovery cases executed |
| [18](https://github.com/Mirantis-PS/k0rdent-ai-training/pull/18) | Changes requested | Scanner exit 0 does not mean no billable survivors; dependency list incomplete |
| [19](https://github.com/Mirantis-PS/k0rdent-ai-training/pull/19) | Changes requested | Real Ubuntu execution rejects `nc -G`; diagnosis also mixes working directories |
| [20](https://github.com/Mirantis-PS/k0rdent-ai-training/pull/20) | Approved | Account guidance reviewed; scanner dependency noted |

## Change validation

- ShellCheck at the repository CI severity: passed.
- Bash syntax and the new preflight regression script: passed.
- Terraform format and validation: passed after the real provisioning init.
- Curriculum checker with PyYAML 6.0.2: 61 files checked, zero errors.
- Actual generated Fish selection and STS check: passed.

## Evidence handling and limits

Raw command logs, exact timestamps, final health JSON, browser screenshot/accessibility capture and PR reproduction fixtures are retained in the local QA evidence directory `docs/qa/week-1/module-1.1/live-20260908/` in the original checkout. They are not included in this PR because infrastructure outputs and authentication-adjacent metadata should not enter the course repository. The generated UI password and private keys are not part of the committed evidence.

This is a real macOS-to-AWS run with a Fish setup check and Ubuntu remote execution. Linux workstation provisioning, WSL2, alternate AWS regions, denied provisioning permissions, cleanup and subsequent labs were not exercised. PR cleanup findings are isolated reproductions, not live destructive tests.
