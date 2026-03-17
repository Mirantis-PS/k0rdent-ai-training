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
| `kgm` | `kubectl get management` | k0rdent Management object |
| `kgcd` | `kubectl get clusterdeployments -A` | All cluster deployments |
| `kgct` | `kubectl get clustertemplates -n kcm-system` | Available cluster templates |
| `kgcred` | `kubectl get credentials -n kcm-system` | Configured credentials |

---

## k0rdent CRD Quick Reference

### View All k0rdent CRDs
```bash
kubectl get crds | grep k0rdent.mirantis.com
```

### Core CRDs
```bash
# Management object (one per cluster)
kubectl get management -n kcm-system
kubectl describe management kcm -n kcm-system

# Cluster templates (available blueprints)
kubectl get clustertemplates -n kcm-system
kubectl get clustertemplates -n kcm-system | grep aws

# Provider templates (registered CAPI providers)
kubectl get providertemplates -n kcm-system

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
kubectl get clusterttemplatechains -n kcm-system
kubectl get servicettemplatechains -n kcm-system
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
# Get credentials
kubectl get secret -n kof grafana-admin-credentials -o jsonpath='{.data.admin-password}' | base64 -d && echo

# Port forward
kubectl port-forward svc/grafana-vm-service -n kof 3000:3000
# Open http://localhost:3000
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
```bash
# 1. Create secret
kubectl apply -f aws-secret.yaml

# 2. Create identity
kubectl apply -f aws-identity.yaml

# 3. Create credential
kubectl apply -f aws-credential.yaml

# Verify chain
kubectl get secret aws-cluster-identity-secret -n kcm-system
kubectl get awsclusterstaticidentity -n kcm-system
kubectl get credential aws-cluster-identity-cred -n kcm-system
```

---

## Upgrade Operations

### Pre-Upgrade
```bash
# Backup etcd
k0s etcd backup /tmp/etcd-backup.tar.gz

# Export resources
kubectl get management,credentials,clustertemplates,servicetemplates -n kcm-system -o yaml > /tmp/backup.yaml

# Current version
helm list -n kcm-system
```

### Upgrade
```bash
helm upgrade kcm oci://ghcr.io/k0rdent/kcm/charts/kcm --version <NEW> -n kcm-system --wait --timeout 10m
```

### Rollback
```bash
helm history kcm -n kcm-system
helm rollback kcm <REVISION> -n kcm-system --wait
```

---

## Troubleshooting Decision Tree

```
Cluster stuck in Provisioning?
├── Check credentials: kubectl get credentials -n kcm-system
│   └── Missing? → Create credential chain (Secret → Identity → Credential)
├── Check CAPI controllers: kubectl get pods -n kcm-system | grep cap
│   └── CrashLoop? → kubectl logs <pod> -n kcm-system
├── Check events: kubectl describe clusterdeployment <name> -n <ns>
│   ├── "template not found" → kubectl get clustertemplates -n kcm-system
│   ├── "credential not found" → Check namespace + credential name
│   ├── "insufficient permissions" → Check IAM policy
│   └── "SSH key not found" → Create key pair in correct region
└── Check AWS: aws ec2 describe-instances --filters "Name=tag:cluster,Values=<name>"

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

# Destroy environment (end of day!)
./scripts/lab-destroy.sh <engineer-id>
```
