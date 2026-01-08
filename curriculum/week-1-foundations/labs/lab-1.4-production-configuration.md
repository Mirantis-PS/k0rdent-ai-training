# Lab 1.4: Production Configuration and RBAC

**Duration:** 3 hours
**Type:** Hands-on Lab

## Objectives

In this lab, you will:
- Configure k0rdent for production readiness
- Set up RBAC policies for multi-team access
- Configure backup and disaster recovery
- Enable monitoring and alerting
- Implement security hardening

## Prerequisites

- Completed Labs 1.1, 1.2, and 1.3
- Understanding of Kubernetes RBAC
- Basic security concepts

## Part 1: Production Architecture Overview

### Single vs Multi-Node Management Cluster

| Aspect | Single Node | Multi-Node (HA) |
|--------|-------------|-----------------|
| Availability | No redundancy | Tolerates failures |
| Use Case | Dev/Test | Production |
| Etcd | Single instance | 3-node quorum |
| Cost | Lower | Higher |

### Exercise: Evaluate Your Setup

```bash
# Check current node count
kubectl get nodes

# For production, you would deploy 3 nodes
# This lab focuses on single-node configuration hardening
```

## Part 2: Configure RBAC for Multi-Team Access

### Understanding k0rdent RBAC

k0rdent extends Kubernetes RBAC with project-based isolation:

```
+-------------------+
|   Organization    |
+--------+----------+
         |
    +----+----+
    |         |
+---+---+ +---+---+
| Team A| | Team B|
+---+---+ +---+---+
    |         |
+---+---+ +---+---+
|Project| |Project|
+-------+ +-------+
```

### Create Namespaces for Teams

```bash
# Create team namespaces
kubectl create namespace team-platform
kubectl create namespace team-ml
kubectl create namespace team-data

# Label namespaces for k0rdent
kubectl label namespace team-platform k0rdent.mirantis.com/project=platform
kubectl label namespace team-ml k0rdent.mirantis.com/project=ml-team
kubectl label namespace team-data k0rdent.mirantis.com/project=data-team
```

### Create Cluster Roles

```bash
# Cluster Admin - Full access
cat << 'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k0rdent-cluster-admin
rules:
- apiGroups: ["k0rdent.mirantis.com"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["infrastructure.cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["*"]
EOF

# Cluster Viewer - Read-only access
cat << 'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k0rdent-cluster-viewer
rules:
- apiGroups: ["k0rdent.mirantis.com"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["cluster.x-k8s.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
EOF

# Project Admin - Manage clusters within a project
cat << 'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: k0rdent-project-admin
  namespace: team-platform
rules:
- apiGroups: ["k0rdent.mirantis.com"]
  resources: ["managedclusters", "clusterdeployments"]
  verbs: ["*"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "create", "update", "delete"]
EOF
```

### Create Service Accounts and Bindings

```bash
# Create service accounts for teams
kubectl create serviceaccount platform-admin -n team-platform
kubectl create serviceaccount ml-admin -n team-ml
kubectl create serviceaccount ml-viewer -n team-ml

# Bind roles
kubectl create rolebinding platform-admin-binding \
  --role=k0rdent-project-admin \
  --serviceaccount=team-platform:platform-admin \
  -n team-platform
```

## Part 3: Configure Audit Logging

### Enable Kubernetes Audit Logging

```bash
# Create audit policy
cat << 'EOF' | sudo tee /var/lib/k0s/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log all k0rdent operations at RequestResponse level
  - level: RequestResponse
    resources:
    - group: "k0rdent.mirantis.com"
      resources: ["*"]

  # Log cluster operations
  - level: RequestResponse
    resources:
    - group: "cluster.x-k8s.io"
      resources: ["clusters", "machines"]

  # Log authentication attempts
  - level: Metadata
    resources:
    - group: ""
      resources: ["secrets"]
    verbs: ["get", "list"]

  # Don't log read-only requests to certain resources
  - level: None
    resources:
    - group: ""
      resources: ["events", "endpoints"]
    verbs: ["get", "list", "watch"]

  # Default level for everything else
  - level: Metadata
EOF
```

### Configure k0s for Audit Logging

```bash
# Note: This requires k0s configuration update
# View current k0s config
sudo k0s config create

# Audit logging is enabled via k0s.yaml configuration
# For this lab, we'll use kubectl for audit awareness
```

## Part 4: Configure Backup and Recovery

### Etcd Backup

```bash
# Create backup script
cat << 'EOF' | sudo tee /usr/local/bin/etcd-backup.sh
#!/bin/bash
BACKUP_DIR="/var/lib/k0s/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

# Take etcd snapshot
sudo k0s etcd snapshot save "$BACKUP_DIR/etcd-snapshot-$TIMESTAMP.db"

# Keep only last 7 backups
ls -t "$BACKUP_DIR"/etcd-snapshot-*.db | tail -n +8 | xargs -r rm

echo "Backup completed: $BACKUP_DIR/etcd-snapshot-$TIMESTAMP.db"
EOF

sudo chmod +x /usr/local/bin/etcd-backup.sh

# Test backup
sudo /usr/local/bin/etcd-backup.sh
```

### Schedule Automated Backups

```bash
# Add cron job for daily backups
echo "0 2 * * * root /usr/local/bin/etcd-backup.sh >> /var/log/etcd-backup.log 2>&1" | \
  sudo tee /etc/cron.d/etcd-backup
```

### Backup k0rdent Resources

```bash
# Export all k0rdent resources
kubectl get management,credential,clustertemplate,servicetemplate \
  -A -o yaml > k0rdent-resources-backup.yaml

# Export cluster configurations
kubectl get clusters,machines,machinedeployments \
  -A -o yaml > cluster-resources-backup.yaml
```

## Part 5: Enable Monitoring with KOF

### Check KOF Status

```bash
# KOF (k0rdent Observability & FinOps) provides monitoring
kubectl get pods -n kof-system 2>/dev/null || echo "KOF not installed"

# List KOF components if available
kubectl get servicetemplates -n kcm-system | grep -i observ
```

### Configure Basic Monitoring

```bash
# Create monitoring namespace
kubectl create namespace monitoring

# Deploy a basic metrics collection ConfigMap
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: k0rdent-monitoring-config
  namespace: monitoring
data:
  scrape-interval: "30s"
  metrics-retention: "7d"
  alert-email: "platform-team@example.com"
EOF
```

### Health Check Script

```bash
# Create health check script
cat << 'EOF' | sudo tee /usr/local/bin/k0rdent-health-check.sh
#!/bin/bash

echo "=== k0rdent Health Check ==="
echo "Timestamp: $(date)"
echo ""

echo "--- Node Status ---"
kubectl get nodes

echo ""
echo "--- k0rdent System Pods ---"
kubectl get pods -n kcm-system

echo ""
echo "--- CAPI Pods ---"
# Note: In k0rdent Enterprise, CAPI components run in kcm-system
kubectl get pods -n kcm-system | grep -E 'capi|capa|capv|capz'

echo ""
echo "--- Recent Events ---"
kubectl get events -n kcm-system --sort-by='.lastTimestamp' | tail -10

echo ""
echo "--- Cluster Resources ---"
kubectl get clusters -A 2>/dev/null || echo "No clusters deployed"

echo ""
echo "=== Health Check Complete ==="
EOF

sudo chmod +x /usr/local/bin/k0rdent-health-check.sh

# Run health check
sudo /usr/local/bin/k0rdent-health-check.sh
```

## Part 6: Security Hardening

### Network Policies

```bash
# Restrict traffic in kcm-system namespace
cat << 'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: kcm-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-kcm-internal
  namespace: kcm-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: kcm-system
EOF
```

### Pod Security Standards

```bash
# Apply Pod Security Standards to namespaces
kubectl label namespace team-platform \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted

kubectl label namespace team-ml \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted
```

### Secret Encryption

```bash
# View k0s encryption configuration (if enabled)
kubectl get secret -n kube-system | grep encryption

# Note: At-rest encryption requires k0s configuration
# For production, enable encryption at rest
```

## Part 7: Configure Resource Quotas

### Set Namespace Quotas

```bash
# Set quotas for team namespaces
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-platform
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    count/clusters.cluster.x-k8s.io: "5"
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-ml
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    count/clusters.cluster.x-k8s.io: "10"
EOF
```

## Part 8: Production Readiness Checklist

### Create Assessment Script

```bash
cat << 'EOF' | sudo tee /usr/local/bin/production-readiness.sh
#!/bin/bash

echo "=== Production Readiness Assessment ==="
echo ""

PASS=0
FAIL=0

check() {
    if $1 &>/dev/null; then
        echo "[PASS] $2"
        ((PASS++))
    else
        echo "[FAIL] $2"
        ((FAIL++))
    fi
}

# Core Components
check "kubectl get pods -n kcm-system | grep -q Running" "KCM pods running"
# Note: In k0rdent Enterprise, CAPI components run in kcm-system
check "kubectl get pods -n kcm-system | grep -E 'capi|capa' | grep -q Running" "CAPI pods running"
check "kubectl get credential -n kcm-system | grep -q aws" "AWS credentials configured"

# RBAC
check "kubectl get clusterrole k0rdent-cluster-admin" "Cluster admin role exists"
check "kubectl get clusterrole k0rdent-cluster-viewer" "Cluster viewer role exists"

# Backup
check "test -x /usr/local/bin/etcd-backup.sh" "Backup script exists"
check "test -f /etc/cron.d/etcd-backup" "Backup cron configured"

# Monitoring
check "test -x /usr/local/bin/k0rdent-health-check.sh" "Health check script exists"

# Security
check "kubectl get networkpolicy -n kcm-system | grep -q deny" "Network policies configured"

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "Production readiness: READY"
else
    echo "Production readiness: NOT READY - Address failures above"
fi
EOF

sudo chmod +x /usr/local/bin/production-readiness.sh

# Run assessment
sudo /usr/local/bin/production-readiness.sh
```

## Validation Checklist

Before completing this lab, verify:

- [ ] Created team namespaces with proper labels
- [ ] Configured RBAC roles and bindings
- [ ] Set up etcd backup script
- [ ] Configured automated backup schedule
- [ ] Created health check script
- [ ] Applied network policies
- [ ] Set resource quotas for namespaces
- [ ] Ran production readiness assessment

## Summary

In this lab, you:
- Configured multi-team RBAC policies
- Set up backup and disaster recovery procedures
- Enabled monitoring and health checks
- Applied security hardening measures
- Created production readiness assessment

## Week 1 Complete!

Congratulations on completing Week 1! You have:
- Deployed a k0rdent Enterprise management cluster
- Explored the k0rdent UI and configuration
- Configured AWS infrastructure provider
- Hardened the setup for production use

## Next Week

Proceed to [Week 2: Bare Metal as a Service](../../week-2-bmaas/README.md) to learn how to manage bare metal infrastructure with k0rdent.
