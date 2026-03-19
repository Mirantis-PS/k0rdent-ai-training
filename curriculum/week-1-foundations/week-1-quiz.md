# Week 1 Assessment: k0rdent Enterprise Foundations

**Duration:** 30 minutes
**Passing Score:** 80% (15/18 correct)
**Format:** 12 multiple choice + 6 short answer

---

## Multiple Choice

Select the single best answer for each question.

### 1. In k0rdent's hub-spoke architecture, what is the primary role of the Management Cluster?

a) Run application workloads alongside management components for efficiency
b) Orchestrate provisioning and lifecycle operations for workload clusters via CRDs and CAPI
c) Serve as a backup cluster that takes over when workload clusters fail
d) Provide a container registry and CI/CD pipeline for all managed clusters

### 2. A platform engineer wants to deploy the same monitoring stack to all clusters labeled `environment: production`. Which k0rdent resource should they use?

a) ClusterDeployment with `serviceSpec` embedded in each cluster definition
b) ServiceTemplate applied directly to each workload cluster via kubectl
c) MultiClusterService with a `clusterSelector` matching the label
d) Management CRD with a global services section

### 3. Which component within KCM enables running the workload cluster control plane as pods on the management cluster instead of dedicated VMs?

a) Flux Helm Controller
b) k0smotron Hosted Control Plane provider
c) CAPI core controller manager
d) cert-manager

### 4. k0rdent uses a three-layer credential model for cloud providers. What is the correct order from innermost (stores actual keys) to outermost (referenced by ClusterDeployments)?

a) Credential CRD -> Provider Identity CRD -> Kubernetes Secret
b) Kubernetes Secret -> Credential CRD -> Provider Identity CRD
c) Provider Identity CRD -> Kubernetes Secret -> Credential CRD
d) Kubernetes Secret -> Provider Identity CRD -> Credential CRD

### 5. After applying restrictive network policies to the `kcm-system` namespace, a colleague reports that `ClusterDeployment` creation fails with webhook timeout errors. What is the most likely cause?

a) The ClusterTemplate referenced in the deployment has expired
b) The network policies are blocking traffic to webhook ports (9443), preventing the API server from reaching admission webhooks
c) The AWS credentials have been rotated and the Secret is stale
d) The Flux Helm Controller is unable to pull charts from the OCI registry

### 6. What distinguishes a ClusterTemplate from a ClusterDeployment in k0rdent?

a) ClusterTemplate runs on workload clusters; ClusterDeployment runs on the management cluster
b) ClusterTemplate is a reusable blueprint referencing a Helm chart; ClusterDeployment is an instance with concrete configuration values
c) ClusterTemplate manages service deployments; ClusterDeployment manages infrastructure only
d) ClusterTemplate is immutable after creation; ClusterDeployment cannot be updated once provisioned

### 7. KOF uses a pipeline of tools for metrics collection. Which sequence correctly describes the metrics flow from a workload cluster to a dashboard?

a) Prometheus -> Thanos -> Grafana
b) OpenTelemetry Collector -> VictoriaMetrics -> Grafana
c) Fluentd -> Elasticsearch -> Kibana
d) kube-state-metrics -> InfluxDB -> Grafana

### 8. How does KSM (k0rdent State Manager) install and manage Helm charts on workload clusters?

a) It SSHs into each workload cluster node and runs `helm install` directly
b) It creates HelmRelease objects that Flux's Helm Controller reconciles on target clusters via Sveltos
c) It embeds chart manifests into the ClusterDeployment spec and applies them during provisioning
d) It uses Argo CD ApplicationSets to sync charts from a Git repository

### 9. An organization wants to prevent incompatible version jumps when upgrading cluster infrastructure. Which k0rdent CRD defines the allowed upgrade paths between template versions?

a) ProviderTemplate
b) Management
c) ClusterTemplateChain
d) Credential

### 10. When upgrading k0rdent Enterprise via Helm, what is the recommended first step before running `helm upgrade`?

a) Delete all existing ClusterDeployments to prevent conflicts
b) Scale down CAPI controllers to zero replicas
c) Take an etcd backup and export k0rdent resource definitions
d) Upgrade all workload clusters to the latest Kubernetes version first

### 11. What is the recommended way to expose the k0rdent UI in production?

a) kubectl port-forward
b) NodePort service with a static port
c) Gateway API (Gateway + HTTPRoute) with TLS and OIDC authentication
d) Direct pod IP access with a load balancer

### 12. The RemoteMachine provider in k0smotron differs from cloud-based CAPI providers in a specific way regarding credentials. What is that difference?

a) RemoteMachine does not require any credentials at all
b) RemoteMachine uses OAuth2 tokens instead of static credentials
c) The Credential CRD references a Secret directly without an intermediate provider identity CRD
d) RemoteMachine credentials are stored in a ConfigMap instead of a Secret

---

## Short Answer

Answer each question in 1-3 sentences.

### 13. Why does k0rdent use a three-layer credential model (Secret -> Provider Identity CRD -> Credential CRD) instead of having ClusterDeployments reference Kubernetes Secrets directly?

### 14. A managed cluster provisioned via k0rdent shows a `Failed` status. Describe the sequence of resources and logs you would check to diagnose the root cause, starting from the highest-level k0rdent resource.

### 15. Explain how MultiClusterService and ServiceTemplateChain work together to manage service lifecycle across a fleet of clusters.

### 16. KOF deploys OpenTelemetry collectors to child clusters, but in a multi-VPC AWS environment the collectors cannot reach VictoriaMetrics on the management cluster. Explain why this happens and name two approaches to solve it.

### 17. Why are etcd backups critical before upgrading k0rdent Enterprise, and under what circumstances would you use an etcd restore versus a Helm rollback?

### 18. Explain how RBAC and namespace isolation work together in k0rdent to support multi-team access to shared management infrastructure. Include the role of the `k0rdent.mirantis.com/project` label.

---

## Answer Key

<details>
<summary><strong>Click to reveal answers</strong></summary>

### Multiple Choice

1. **b)** -- The Management Cluster runs k0rdent components (KCM, KSM, KOF) and orchestrates provisioning via CRDs and CAPI. It does NOT run application workloads (eliminating option a). It is not a backup or failover cluster (c), nor does it provide CI/CD pipelines (d).

2. **c)** -- MultiClusterService uses `clusterSelector` with `matchLabels` to target clusters by label and deploy services from ServiceTemplates to all matching clusters. Option (a) works for single-cluster service deployment but does not scale. Option (b) is not a valid k0rdent workflow. Option (d) does not exist.

3. **b)** -- k0smotron provides the Hosted Control Plane capability, running the workload cluster's control plane as pods on the management cluster. Flux (a) handles Helm chart reconciliation, CAPI core (c) manages cluster lifecycle primitives, and cert-manager (d) handles TLS certificates.

4. **d)** -- The correct order is: Kubernetes Secret (stores actual cloud keys) -> Provider Identity CRD like AWSClusterStaticIdentity (references the Secret and adds provider-specific config like allowedNamespaces) -> k0rdent Credential CRD (references the identity and is what ClusterDeployments actually use). Option (a) reverses the entire chain. Options (b) and (c) swap the middle and outer layers.

5. **b)** -- Network policies restricting ingress to `kcm-system` can block the Kubernetes API server from reaching admission webhooks on port 9443. The lab materials explicitly warn against applying network policies before completing provisioning labs, and provide `kubectl delete networkpolicy -n kcm-system --all` as the fix. Options (a), (c), and (d) would produce different error messages.

6. **b)** -- A ClusterTemplate is a reusable blueprint that wraps a Helm chart with provider requirements and CAPI contract versions. A ClusterDeployment is a concrete instance that references a template and supplies cluster-specific values (region, instance types, node counts). Option (d) is wrong because ClusterDeployments can be updated (e.g., scaling workers).

7. **b)** -- KOF's metrics pipeline is: OpenTelemetry Collector (on each cluster) -> VictoriaMetrics (vminsert/vmselect/vmstorage for storage and querying) -> Grafana (visualization). The other options describe different monitoring stacks not used by KOF.

8. **b)** -- KSM creates HelmRelease objects that are reconciled by Flux's Helm Controller. Sveltos distributes these to target workload clusters based on MultiClusterService label selectors. KSM does not SSH into nodes (a), embed charts in ClusterDeployments (c), or use Argo CD (d).

9. **c)** -- ClusterTemplateChain defines `supportedTemplates` with `availableUpgrades` fields that specify which template versions can upgrade to which. ProviderTemplate (a) registers CAPI providers, Management (b) is the core config object, and Credential (d) handles authentication.

10. **c)** -- The recommended pre-upgrade steps are: take an etcd backup (`k0s etcd backup`) and export k0rdent resource definitions to YAML files. This ensures you can restore to a known-good state if the upgrade fails. Deleting ClusterDeployments (a) would destroy running clusters. Scaling down controllers (b) is unnecessary. Upgrading workload clusters first (d) is not required and is independent of the management plane upgrade.

11. **c)** Gateway API (Gateway + HTTPRoute) with TLS and OIDC authentication -- Gateway API is the Kubernetes-native successor to Ingress, providing role-based separation and richer routing capabilities.

12. **c)** -- The RemoteMachine provider is the only provider where the Credential CRD references a Kubernetes Secret (containing an SSH private key) directly, without an intermediate provider identity CRD like AWSClusterStaticIdentity or VSphereClusterIdentity. It still requires credentials (eliminating a), uses SSH keys not OAuth2 (b), and uses Secrets not ConfigMaps (d).

### Short Answer

13. The three-layer model provides separation of concerns and access control. The Kubernetes Secret holds raw credentials that should be tightly restricted. The Provider Identity CRD adds provider-specific configuration (such as `allowedNamespaces` to control which tenants can use the credential) and abstracts the secret reference. The Credential CRD provides a k0rdent-native abstraction that ClusterDeployments reference, decoupling cluster definitions from provider-specific identity types. This allows credential rotation at the Secret layer without modifying ClusterDeployments, and enables administrators to restrict credential usage across namespaces via the identity layer's `allowedNamespaces` field.

14. Start with the ClusterDeployment: `kubectl describe clusterdeployment <name> -n <namespace>` to check `status.conditions` for error messages. Next, inspect the underlying CAPI Cluster resource: `kubectl describe cluster <name> -n <namespace>`. Then check individual Machine resources: `kubectl describe machines -n <namespace>` for infrastructure-level failures (e.g., instance type unavailable, insufficient IAM permissions). Finally, check the CAPI provider controller logs: `kubectl logs -n kcm-system -l cluster.x-k8s.io/provider=infrastructure-aws --tail=100` for API-level errors from the cloud provider.

15. MultiClusterService deploys services from ServiceTemplates to all clusters matching a label selector, providing centralized fleet-wide service management. ServiceTemplateChain defines allowed upgrade paths between ServiceTemplate versions (e.g., `ingress-nginx-4-10-0` can upgrade to `ingress-nginx-4-11-0`), preventing incompatible version jumps. Together, they enable an operator to update the template reference in a MultiClusterService to a newer version, and the chain ensures only validated upgrade paths are followed across the fleet.

16. CAPA creates a new, isolated VPC for each managed cluster. The internal Kubernetes DNS names (e.g., `vminsert-cluster.kof.svc.cluster.local`) only resolve within the management cluster, and the management cluster's pod/service CIDRs are not routable from the managed cluster's VPC. Two solutions: (1) VPC Peering -- create a peering connection between the management and managed cluster VPCs with appropriate route table and security group updates; (2) LoadBalancer exposure -- expose KOF storage services (vminsert, VictoriaLogs vlinsert, Jaeger collector) via AWS Network Load Balancers and update the child cluster configuration to use the NLB endpoints (requires AWS Cloud Controller Manager on the management cluster).

17. etcd contains all Kubernetes state, including k0rdent CRDs, ClusterDeployments, credentials, and template definitions. If an upgrade corrupts CRDs or introduces breaking schema changes, the backup ensures recovery to a known-good state. Use Helm rollback (`helm rollback kcm <revision>`) as the first response to a failed upgrade, since it reverts the Helm release and restarts controllers without affecting other cluster state. Use etcd restore only as a last resort when Helm rollback itself fails or CRD data is corrupted beyond what a Helm rollback can fix, keeping in mind that etcd restore reverts ALL cluster state (not just k0rdent) to the backup point.

18. k0rdent uses Kubernetes namespaces as tenant boundaries. Each team gets a dedicated namespace (e.g., `team-platform`, `team-ml`) labeled with `k0rdent.mirantis.com/project=<project-name>` to identify the project. RBAC Roles scoped to these namespaces (e.g., `k0rdent-project-admin`) grant teams permission to create and manage ClusterDeployments and MultiClusterServices only within their own namespace. ClusterRoles like `k0rdent-cluster-viewer` provide read-only fleet visibility. The Provider Identity CRD's `allowedNamespaces` field further restricts which namespaces can use specific cloud credentials, and ResourceQuotas limit the number of clusters and compute resources each team can consume.

</details>
