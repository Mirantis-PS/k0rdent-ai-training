# Lab 6.6 - CAPSTONE: End-to-End Tenant Onboarding

**Duration:** 3 hours
**Type:** Capstone Project
**Environment:** Full Stack Lab

## Objective

Complete a full tenant onboarding scenario that demonstrates mastery of all k0rdent concepts learned throughout the training program.

## Scenario

**Customer:** TechCorp AI Solutions
**Request:** Set up a complete AI development environment with:
- Isolated tenant environment
- Kubernetes cluster for AI workloads
- LLM inference service
- Integration with their identity provider

## Requirements

TechCorp needs:
1. **Resource Allocation:**
   - 4 H100 GPUs quota
   - 256 vCPUs
   - 1TB RAM
   - 500GB storage

2. **Network:**
   - Isolated network space
   - Egress allowed only to specific domains
   - Internal service mesh

3. **Access:**
   - Integration with their Okta IdP
   - 1 Tenant Admin
   - 5 Tenant Users (AI developers)

4. **Workloads:**
   - Kubernetes cluster (3 control plane, 4 workers with GPU)
   - vLLM deployment for Llama-2-7B

5. **Compliance:**
   - Full audit trail
   - Usage metering for chargeback

## Tasks

### Phase 1: Tenant Setup (45 min)

#### Task 1.1: Create Tenant

1. **Via Provider Console:**
   - Navigate to Tenants → Create New
   - Name: `techcorp-ai`
   - Description: "TechCorp AI Solutions - AI Development Environment"
   - State: Active

2. **Via API:**
   ```bash
   curl -X POST https://<k0rdent>/api/v1/tenants \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "techcorp-ai",
       "displayName": "TechCorp AI Solutions",
       "description": "AI Development Environment",
       "state": "active",
       "metadata": {
         "customer_id": "TC-2024-001",
         "contract_start": "2024-01-01",
         "tier": "enterprise"
       }
     }'
   ```

3. **Capture tenant ID for subsequent steps:**
   ```bash
   TENANT_ID=$(curl -s https://<k0rdent>/api/v1/tenants?name=techcorp-ai \
     -H "Authorization: Bearer <token>" | jq -r '.items[0].id')
   echo "Tenant ID: $TENANT_ID"
   ```

#### Task 1.2: Configure Network Isolation

1. **Create Tenant Network Space:**
   ```bash
   curl -X POST https://<k0rdent>/api/v1/tenants/$TENANT_ID/networks \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "techcorp-network",
       "cidr": "10.100.0.0/16",
       "subnets": [
         {
           "name": "control-plane",
           "cidr": "10.100.1.0/24"
         },
         {
           "name": "workers",
           "cidr": "10.100.10.0/23"
         },
         {
           "name": "services",
           "cidr": "10.100.20.0/24"
         }
       ]
     }'
   ```

2. **Configure Egress Policies:**
   ```bash
   curl -X POST https://<k0rdent>/api/v1/tenants/$TENANT_ID/network-policies \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "techcorp-egress",
       "type": "egress",
       "rules": [
         {
           "action": "allow",
           "destinations": [
             "*.huggingface.co",
             "huggingface.co",
             "cdn-lfs.huggingface.co"
           ],
           "ports": ["443"]
         },
         {
           "action": "allow",
           "destinations": ["*.github.com", "github.com"],
           "ports": ["443"]
         },
         {
           "action": "allow",
           "destinations": ["pypi.org", "files.pythonhosted.org"],
           "ports": ["443"]
         },
         {
           "action": "deny",
           "destinations": ["*"],
           "ports": ["*"]
         }
       ]
     }'
   ```

#### Task 1.3: Set Resource Quotas

1. **Configure GPU Quotas:**
   ```bash
   curl -X PUT https://<k0rdent>/api/v1/tenants/$TENANT_ID/quotas \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "gpu": {
         "nvidia.com/H100": 4
       },
       "compute": {
         "vcpus": 256,
         "memory_gb": 1024
       },
       "storage": {
         "total_gb": 500,
         "by_class": {
           "fast-ssd": 200,
           "standard": 300
         }
       },
       "kubernetes": {
         "max_clusters": 2,
         "max_nodes_per_cluster": 10
       }
     }'
   ```

2. **Verify Quotas:**
   ```bash
   curl https://<k0rdent>/api/v1/tenants/$TENANT_ID/quotas \
     -H "Authorization: Bearer <token>" | jq .
   ```

### Phase 2: Access Management (30 min)

#### Task 2.1: Configure OIDC Integration

1. **Register Okta as Identity Provider:**
   ```bash
   curl -X POST https://<k0rdent>/api/v1/identity-providers \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "techcorp-okta",
       "type": "oidc",
       "config": {
         "issuer": "https://techcorp.okta.com",
         "client_id": "<okta-client-id>",
         "client_secret": "<okta-client-secret>",
         "scopes": ["openid", "profile", "email", "groups"],
         "claim_mappings": {
           "username": "preferred_username",
           "email": "email",
           "groups": "groups"
         }
       },
       "tenant_id": "'$TENANT_ID'"
     }'
   ```

2. **Map Okta Groups to Roles:**
   ```bash
   curl -X POST https://<k0rdent>/api/v1/tenants/$TENANT_ID/role-mappings \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "mappings": [
         {
           "idp_group": "TechCorp-AI-Admins",
           "role": "tenant_admin"
         },
         {
           "idp_group": "TechCorp-AI-Developers",
           "role": "tenant_user"
         }
       ]
     }'
   ```

#### Task 2.2: Create Initial Users

1. **Create Tenant Admin:**
   ```bash
   curl -X POST https://<k0rdent>/api/v1/tenants/$TENANT_ID/users \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "username": "john.smith@techcorp.com",
       "email": "john.smith@techcorp.com",
       "role": "tenant_admin",
       "idp": "techcorp-okta"
     }'
   ```

2. **Verify User Created:**
   ```bash
   curl https://<k0rdent>/api/v1/tenants/$TENANT_ID/users \
     -H "Authorization: Bearer <token>" | jq .
   ```

### Phase 3: Kubernetes Cluster Deployment (45 min)

#### Task 3.1: Deploy Kubernetes Cluster

1. **Create Cluster Request:**
   ```bash
   curl -X POST https://<k0rdent>/api/v1/tenants/$TENANT_ID/clusters \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "techcorp-ai-cluster",
       "version": "1.32",
       "template": "gpu-optimized",
       "controlPlane": {
         "replicas": 3,
         "flavor": "medium"
       },
       "nodePools": [
         {
           "name": "gpu-workers",
           "replicas": 4,
           "flavor": "gpu-h100",
           "labels": {
             "node-type": "gpu",
             "gpu-type": "h100"
           },
           "taints": [
             {
               "key": "nvidia.com/gpu",
               "value": "true",
               "effect": "NoSchedule"
             }
           ]
         }
       ],
       "network": {
         "podCIDR": "10.244.0.0/16",
         "serviceCIDR": "10.96.0.0/12"
       },
       "addons": [
         "gpu-operator",
         "prometheus",
         "ingress-nginx"
       ]
     }'
   ```

2. **Monitor Cluster Deployment:**
   ```bash
   # Watch cluster status
   watch -n 10 "curl -s https://<k0rdent>/api/v1/tenants/$TENANT_ID/clusters/techcorp-ai-cluster \
     -H 'Authorization: Bearer <token>' | jq '.status'"
   ```

3. **Wait for Cluster Ready** (this may take 15-20 minutes)

#### Task 3.2: Retrieve Kubeconfig

1. **Generate Kubeconfig:**
   ```bash
   curl -X POST https://<k0rdent>/api/v1/tenants/$TENANT_ID/clusters/techcorp-ai-cluster/kubeconfig \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "ttl": "24h",
       "user": "john.smith@techcorp.com"
     }' -o techcorp-kubeconfig.yaml
   ```

2. **Test Cluster Access:**
   ```bash
   export KUBECONFIG=techcorp-kubeconfig.yaml
   kubectl get nodes
   kubectl get pods -A
   ```

3. **Verify GPU Nodes:**
   ```bash
   kubectl get nodes -l gpu-type=h100
   kubectl describe nodes -l gpu-type=h100 | grep -A10 "Allocatable:"
   ```

### Phase 4: AI Workload Deployment (30 min)

#### Task 4.1: Deploy vLLM from Service Catalog

1. **List Available Services:**
   ```bash
   curl https://<k0rdent>/api/v1/service-catalog?category=inference \
     -H "Authorization: Bearer <token>" | jq '.items[].name'
   ```

2. **Deploy vLLM Service:**
   ```bash
   curl -X POST https://<k0rdent>/api/v1/tenants/$TENANT_ID/services \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "catalog_item": "vllm-inference",
       "name": "techcorp-llm",
       "cluster": "techcorp-ai-cluster",
       "namespace": "ai-inference",
       "config": {
         "model": "meta-llama/Llama-2-7b-chat-hf",
         "gpu_count": 1,
         "max_model_len": 4096,
         "replicas": 1
       }
     }'
   ```

3. **Monitor Deployment:**
   ```bash
   kubectl get pods -n ai-inference -w
   ```

#### Task 4.2: Verify Inference Service

1. **Port Forward (for testing):**
   ```bash
   kubectl port-forward svc/techcorp-llm -n ai-inference 8000:8000 &
   ```

2. **Test Inference:**
   ```bash
   curl http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "meta-llama/Llama-2-7b-chat-hf",
       "messages": [
         {"role": "user", "content": "What is machine learning?"}
       ],
       "max_tokens": 100
     }' | jq .
   ```

### Phase 5: Verification & Documentation (30 min)

#### Task 5.1: Generate Usage Report

1. **Query Usage Metrics:**
   ```bash
   curl "https://<k0rdent>/api/v1/tenants/$TENANT_ID/usage?from=2024-01-01&to=2024-12-31" \
     -H "Authorization: Bearer <token>" | jq . > techcorp-usage-report.json
   ```

2. **Expected Metrics:**
   - GPU hours consumed
   - vCPU hours consumed
   - Storage usage
   - Network egress

#### Task 5.2: Review Audit Logs

1. **Query Audit Trail:**
   ```bash
   curl "https://<k0rdent>/api/v1/tenants/$TENANT_ID/audit-logs?limit=50" \
     -H "Authorization: Bearer <token>" | jq '.items[] | {timestamp, action, user, resource}' > techcorp-audit.json
   ```

2. **Verify Key Events Logged:**
   - [ ] Tenant creation
   - [ ] Network configuration
   - [ ] Quota assignment
   - [ ] User creation
   - [ ] Cluster deployment
   - [ ] Service deployment

#### Task 5.3: Create Handoff Documentation

Create a document (`techcorp-handoff.md`) containing:

```markdown
# TechCorp AI Solutions - Deployment Summary

## Tenant Information
- Tenant ID: <id>
- Name: techcorp-ai
- State: Active
- Created: <timestamp>

## Resource Allocation
| Resource | Quota | Used |
|----------|-------|------|
| H100 GPUs | 4 | 1 |
| vCPUs | 256 | 48 |
| RAM | 1TB | 128GB |
| Storage | 500GB | 50GB |

## Network Configuration
- Tenant CIDR: 10.100.0.0/16
- Subnets: control-plane, workers, services
- Egress: Limited to HuggingFace, GitHub, PyPI

## Access Management
- IdP: Okta (techcorp-okta)
- Admin: john.smith@techcorp.com
- Group Mappings: Configured

## Deployed Resources
### Kubernetes Cluster
- Name: techcorp-ai-cluster
- Version: 1.32
- Control Plane: 3 nodes
- Workers: 4 GPU nodes (H100)

### Services
- vLLM (Llama-2-7B): Running in ai-inference namespace

## Endpoints
- Customer Console: https://customer.k0rdent.example.com
- Cluster API: https://techcorp-ai-cluster.k0rdent.example.com:6443
- vLLM Inference: https://llm.techcorp.k0rdent.example.com

## Monitoring
- Prometheus: Enabled
- Grafana: Enabled
- GPU Metrics: Enabled

## Next Steps
1. Customer to add remaining users via Customer Console
2. Customer to accept IdP configuration
3. Schedule training session for AI developers
```

## Deliverables

Submit the following:

- [ ] **Tenant configuration** - Screenshot of tenant in Provider Console
- [ ] **Network topology diagram** - Showing subnets and egress rules
- [ ] **Quota allocation summary** - From API response
- [ ] **RBAC role assignments** - User list with roles
- [ ] **Cluster verification** - `kubectl get nodes` output
- [ ] **AI workload test** - Screenshot of successful inference
- [ ] **Usage report** - JSON export (`techcorp-usage-report.json`)
- [ ] **Audit log excerpt** - JSON export (`techcorp-audit.json`)
- [ ] **Handoff documentation** - Completed `techcorp-handoff.md`

## Evaluation Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Tenant Isolation | 20 | Network properly isolated, quotas enforced |
| Network Policies | 15 | Egress rules correctly configured |
| Resource Quotas | 15 | Correct limits applied and enforced |
| RBAC Configuration | 15 | Roles properly assigned, IdP integrated |
| Cluster Deployment | 15 | Cluster running with GPU nodes |
| AI Workload | 10 | vLLM service operational |
| Documentation | 10 | Complete and accurate handoff doc |
| **Total** | **100** | |

**Passing Score:** 80 points

## Troubleshooting Guide

### Tenant Creation Fails
- Check Provider_Admin permissions
- Verify tenant name is unique
- Review API error message

### Network Isolation Issues
- Verify CIDR ranges don't overlap
- Check egress policy syntax
- Test with simple connectivity test

### Cluster Won't Deploy
- Check quota allows requested resources
- Verify template exists
- Review cluster events

### vLLM Fails to Start
- Check GPU availability in cluster
- Verify HuggingFace token
- Review pod logs and events

## Congratulations

Upon completing this capstone, you have demonstrated proficiency in:

1. Tenant lifecycle management
2. Network isolation and security policies
3. Resource quota configuration
4. Identity federation with OIDC
5. Kubernetes cluster deployment
6. AI workload deployment from service catalog
7. Usage metering and audit trails
8. Documentation and handoff procedures

**You are now ready to implement k0rdent for production customer deployments.**
