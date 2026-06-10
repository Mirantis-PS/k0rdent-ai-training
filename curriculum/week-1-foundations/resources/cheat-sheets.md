# Week 1 Cheat Sheets

Quick reference for common k0rdent operations. Keep this open alongside your labs.

---

## kubectl Aliases (from Lab 1.1)

These aliases are pre-configured on the management cluster:

| Alias | Full Command | Use |
|-------|-------------|-----|
| `k` | `kubectl` | General shortcut |
| `kgp` | `kubectl get pods` | List pods |
| `kgn` | `kubectl get nodes` | List nodes |
| `kgaa` | `kubectl get all -A` | All resources, all namespaces |
| `kgm` | `kubectl get management -A` | k0rdent Management object |
| `kgcd` | `kubectl get clusterdeployment -A` | All cluster deployments |
| `kgct` | `kubectl get clustertemplates -A` | Available cluster templates |
| `kgcred` | `kubectl get credentials -A` | Configured credentials |

---

## k0rdent CRD Quick Reference

### View All k0rdent CRDs
```bash
kubectl get crds | grep k0rdent.mirantis.com
```

### Core CRDs

> **Scope note:** `Management`, `ProviderTemplate`, `Release`, and `MultiClusterService` are **cluster-scoped** (no `-n` flag). `ClusterTemplate`, `ServiceTemplate`, and `Credential` are namespaced and live in `kcm-system`.

```bash
# Management object (one per cluster, cluster-scoped)
kubectl get management
kubectl describe management kcm

# Cluster templates (available blueprints)
kubectl get clustertemplates -n kcm-system
kubectl get clustertemplates -n kcm-system | grep aws

# Provider templates (registered CAPI providers, cluster-scoped)
kubectl get providertemplates

# Service templates (deployable services)
kubectl get servicetemplates -n kcm-system

# Cluster deployments (running clusters)
kubectl get clusterdeployments -A
kubectl describe clusterdeployment <name> -n <namespace>

# Credentials
kubectl get credentials -n kcm-system
kubectl describe credential <name> -n kcm-system

# MultiClusterServices
kubectl get multiclusterservices -A

# Template chains (upgrade paths)
kubectl get clustertemplatechains -n kcm-system
kubectl get servicetemplatechains -n kcm-system
```

---

## Cluster Lifecycle Commands

### Provision a Cluster
```bash
# 1. Check prerequisites
kubectl get credentials -n kcm-system
kubectl get clustertemplates -n kcm-system | grep aws

# 2. Apply ClusterDeployment
kubectl apply -f my-cluster.yaml

# 3. Monitor provisioning
kubectl get clusterdeployment <name> -n <ns> -w
clusterctl describe cluster <name> -n <ns>

# 4. Get kubeconfig when Ready
kubectl get secret -n <ns> <name>-kubeconfig -o jsonpath='{.data.value}' | base64 -d > /tmp/kubeconfig
kubectl --kubeconfig /tmp/kubeconfig get nodes
```

### Check Cluster Health
```bash
# Management cluster
kubectl get nodes
kubectl get pods -n kcm-system

# CAPI resources for a specific cluster
kubectl get cluster,machines,machinedeployments -n <ns> -l cluster.x-k8s.io/cluster-name=<name>

# Managed cluster (via kubeconfig)
kubectl --kubeconfig /tmp/kubeconfig get nodes
kubectl --kubeconfig /tmp/kubeconfig get pods -A
```

### Delete a Cluster
```bash
kubectl delete clusterdeployment <name> -n <ns>
# Monitor deletion:
kubectl get clusterdeployment <name> -n <ns> -w
```

---

## KOF Commands

### Check KOF Status
```bash
kubectl get pods -n kof
helm list -n kof
```

### Access Grafana
```bash
# Get username (not guaranteed to be 'admin')
kubectl get secret grafana-admin-credentials -n kof \
  -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' | base64 -d && echo

# Get password
kubectl get secret grafana-admin-credentials -n kof \
  -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 -d && echo

# Port forward (run on the management node)
kubectl port-forward svc/grafana-vm-service -n kof 3000:3000 --address 0.0.0.0 &

# From your LOCAL machine: tunnel through the bastion (see Lab 1.6 Part 4)
./scripts/lab-connect.sh <engineer-id> --tunnel 3000:3000
# Then open http://localhost:3000 locally
```

### Query Metrics
```bash
# Port forward VictoriaMetrics
kubectl port-forward svc/vmselect-cluster -n kof 8481:8481

# Test query
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=up" | jq '.data.result | length'
```

---

## Credential Management

### AWS Credential (Three-Layer Model)

These objects are created inline (no local YAML files) — full walkthrough in Lab 1.3 Part 3:

```bash
# 1. Create secret
kubectl create secret generic aws-cluster-identity-secret \
  --from-literal=AccessKeyID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=SecretAccessKey="${AWS_SECRET_ACCESS_KEY}" \
  -n kcm-system

# 2. Create identity
cat << 'EOF' | kubectl apply -f -
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSClusterStaticIdentity
metadata:
  name: aws-cluster-identity
  labels:
    k0rdent.mirantis.com/component: "kcm"
spec:
  secretRef: aws-cluster-identity-secret
  allowedNamespaces: {}
EOF

# 2b. Create the resource template ConfigMap
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-cluster-identity-resource-template
  namespace: kcm-system
  labels:
    k0rdent.mirantis.com/component: "kcm"
  annotations:
    projectsveltos.io/template: "true"
EOF

# 3. Create credential
cat << 'EOF' | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  name: aws-cluster-identity-cred
  namespace: kcm-system
spec:
  identityRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSClusterStaticIdentity
    name: aws-cluster-identity
    namespace: kcm-system
EOF

# Verify chain
kubectl get secret aws-cluster-identity-secret -n kcm-system
kubectl get awsclusterstaticidentity
kubectl get configmap aws-cluster-identity-resource-template -n kcm-system
kubectl get credential aws-cluster-identity-cred -n kcm-system
```

---

## Upgrade Operations

### Pre-Upgrade
```bash
# Verify backup storage and create a ManagementBackup (see Lab 1.8 Part 1)
kubectl get backupstoragelocation -n kcm-system
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ManagementBackup
metadata:
  name: pre-upgrade-$(date +%Y%m%d)
spec:
  storageLocation: aws-s3
EOF

# Export resources (Management is cluster-scoped, the rest live in kcm-system)
kubectl get management kcm -o yaml > /tmp/backup-management.yaml
kubectl get credentials,clustertemplates,servicetemplates -n kcm-system -o yaml > /tmp/backup.yaml

# Current release
kubectl get releases.k0rdent.mirantis.com
kubectl get management kcm -o jsonpath='{.spec.release}' && echo ""
```

### Upgrade
```bash
kubectl create -f "https://get.mirantis.com/k0rdent-enterprise/<NEW_VERSION>/release.yaml"
kubectl patch managements.k0rdent.mirantis.com kcm \
  --patch '{"spec":{"release":"k0rdent-enterprise-<NEW_VERSION_WITH_DASHES>"}}' \
  --type=merge
```

### Rollback
```bash
# Fastest rollback: point Management back to the previous release
kubectl patch managements.k0rdent.mirantis.com kcm \
  --patch '{"spec":{"release":"<PREVIOUS_RELEASE_NAME>"}}' \
  --type=merge

# If needed, restore from the pre-upgrade backup using Velero Restore
kubectl get backups -n kcm-system
```

---

## Troubleshooting Decision Tree

```
Cluster stuck in Provisioning?
├── Check credentials: kubectl get credentials -n kcm-system
│   └── Missing? → Create credential chain (Secret → Identity → resource-template ConfigMap → Credential, see Lab 1.3)
├── Check CAPI controllers: kubectl get pods -n kcm-system | grep cap
│   └── CrashLoop? → kubectl logs <pod> -n kcm-system
├── Check events: kubectl describe clusterdeployment <name> -n <ns>
│   ├── "template not found" → kubectl get clustertemplates -n kcm-system
│   ├── "credential not found" → Check namespace + credential name
│   ├── "insufficient permissions" → Check IAM policy
│   └── "SSH key not found" → Create key pair in correct region
└── Check AWS: aws ec2 describe-instances --filters "Name=tag-key,Values=sigs.k8s.io/cluster-api-provider-aws/cluster/<name>"
    (CCM-created resources like load balancers carry the kubernetes.io/cluster/<name> tag instead)

Pods not starting in kcm-system?
├── ImagePullBackOff → Check registry access / image names
├── CrashLoopBackOff → kubectl logs <pod> -n kcm-system --previous
└── Pending → kubectl describe pod <pod> -n kcm-system (check resources/scheduling)

Network policies broke provisioning?
└── Check if webhook port 9443 is blocked:
    kubectl get networkpolicy -n kcm-system
    → Remove or add exception for port 9443
```

---

## Lab Infrastructure Scripts

```bash
# Provision your environment
./scripts/lab-provision.sh <engineer-id>

# Connect via bastion
./scripts/lab-connect.sh <engineer-id>

# Check status
./scripts/lab-status.sh <engineer-id>

# Pause for the day (the management cluster is reused all program — do NOT destroy it)
aws ec2 stop-instances --instance-ids <mgmt-instance-id> <bastion-instance-id>

# Destroy environment (ONLY after finishing all labs — see Lab 1.8 "End of Week 1" teardown)
./scripts/lab-destroy.sh <engineer-id>
```
