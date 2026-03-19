# Envoy Gateway UI Exposure Design

**Date:** 2026-03-18
**Scope:** k0rdent Enterprise Training — UI exposure via Envoy Gateway (Gateway API)
**Replaces:** NLB + NodePort 30080 + `k0rdent-ui-external` service pattern
**Versions:** Gateway API CRDs v1.2.1, Envoy Gateway v1.2.6

---

## Context

The k0rdent UI is currently exposed in the training lab via a Terraform-managed AWS NLB routing port 80 to a manually-created `k0rdent-ui-external` NodePort service (30080). The production path documented in Lab 1.2 recommends ingress-nginx + Ingress resources — a separate pattern entirely.

This creates two problems:
1. Training and production use completely different exposure mechanisms
2. The Ingress API is deprecated in favor of the Kubernetes Gateway API

This design replaces both paths with a single **Envoy Gateway** approach using the **Gateway API**. The training lab installs Envoy Gateway during provisioning and lets AWS CCM auto-provision a LoadBalancer. The production upgrade path adds TLS + OIDC to the same Gateway resources.

---

## Architecture

### End-State Traffic Flow (Training Lab)

```
Student Browser (HTTP)
    │
    ▼
AWS NLB (auto-provisioned by AWS CCM via Gateway Service)
    │ port 80
    ▼
Envoy Gateway (envoy-gateway-system namespace)
    │ Gateway resource, listener on port 80
    ▼
HTTPRoute (kcm-system namespace)
    │ routes path "/" to kcm-k0rdent-ui service
    ▼
k0rdent UI Pod (ClusterIP :3000, Helm-managed, untouched)
```

### Gateway API Resource Model

```
GatewayClass (envoy-gateway)           ← Infrastructure provider
    │
    ▼
Gateway (k0rdent-gateway, kcm-system)  ← Cluster operator
    │  listener: HTTP port 80
    ▼
HTTPRoute (k0rdent-ui, kcm-system)     ← Application developer
    │  path: / → kcm-k0rdent-ui:3000
    ▼
Service (kcm-k0rdent-ui, ClusterIP)    ← Helm-managed, untouched
```

---

## Section 1: Cloud-Init Changes

### 1.1 Install Envoy Gateway in Stage 4

After k0rdent Helm install completes and the KCM operator is available, add:

```bash
# 1. Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml

# 2. Install Envoy Gateway via Helm
helm install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
  --version ${ENVOY_GATEWAY_VERSION} \
  --namespace envoy-gateway-system \
  --create-namespace \
  --wait --timeout 5m

# 3. Wait for controller readiness
kubectl wait deployment/envoy-gateway -n envoy-gateway-system \
  --for=condition=Available --timeout=120s
```

### 1.2 Create Gateway API Resources

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k0rdent-gateway
  namespace: kcm-system
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: k0rdent-ui
  namespace: kcm-system
spec:
  parentRefs:
    - name: k0rdent-gateway
      namespace: kcm-system
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: kcm-k0rdent-ui
          port: 3000
```

### 1.3 Wait for Gateway LB Address

```bash
echo "Waiting for Gateway LoadBalancer address..."
for i in $(seq 1 60); do
  GW_ADDR=$(kubectl get gateway k0rdent-gateway -n kcm-system \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
  if [ -n "$GW_ADDR" ]; then
    echo "k0rdent UI available at: http://${GW_ADDR}"
    break
  fi
  sleep 5
done
```

### 1.4 Remove from Cloud-Init

- Delete the `k0rdent-ui-external` NodePort service creation block

### 1.5 Version Variables

Pass from Terraform template:
- `gateway_api_version` — default: `v1.2.1`
- `envoy_gateway_version` — default: `v1.2.6`

---

## Section 2: Terraform Changes

### 2.1 Remove from `k0rdent-mgmt` Module

| Resource | Action |
|----------|--------|
| `aws_lb.k0rdent_ui` | Delete |
| `aws_lb_target_group.k0rdent_ui` | Delete |
| `aws_lb_listener.k0rdent_ui` | Delete |
| `aws_lb_target_group_attachment.k0rdent_ui` | Delete |
| Security group rule for port 30080 from 0.0.0.0/0 | Delete |
| `output "ui_url"` (NLB DNS) | Delete |

### 2.2 Update Security Group

Replace the specific port 30080 rule with the NodePort range (CCM picks the port dynamically):

```hcl
ingress {
  description = "Envoy Gateway LoadBalancer traffic (CCM-provisioned NLB)"
  from_port   = 30000
  to_port     = 32767
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}
```

### 2.3 Add Version Variables

```hcl
variable "gateway_api_version" {
  description = "Gateway API CRD version"
  type        = string
  default     = "v1.2.1"
}

variable "envoy_gateway_version" {
  description = "Envoy Gateway Helm chart version"
  type        = string
  default     = "v1.2.6"
}
```

### 2.4 Update Outputs

Replace `ui_url` with informational output:

```hcl
output "ui_access" {
  description = "How to retrieve the k0rdent UI URL"
  value       = "Run: ./scripts/lab-connect.sh ${var.engineer_id} --ui-url"
}
```

---

## Section 3: Script Changes

### 3.1 `lab-provision.sh` — Wait for Gateway LB

After Terraform completes and EC2 passes status checks, the script waits for the cloud-init completion marker, then retrieves the Gateway URL:

```bash
echo "Retrieving k0rdent UI URL..."
UI_URL=$(ssh -J bastion ubuntu@mgmt-node \
  "kubectl get gateway k0rdent-gateway -n kcm-system \
   -o jsonpath='http://{.status.addresses[0].value}'")

UI_PASSWORD=$(ssh -J bastion ubuntu@mgmt-node \
  "kubectl get secret -n kcm-system kcm-k0rdent-ui-basic-auth \
   -o jsonpath='{.data.password}' | base64 -d")

echo "============================================"
echo "  k0rdent UI:       ${UI_URL}"
echo "  Username:          admin"
echo "  Password:          ${UI_PASSWORD}"
echo "============================================"
```

### 3.2 `lab-connect.sh` — New Flags

**`--ui-url`** — Retrieve the UI URL again later:
```bash
# ./scripts/lab-connect.sh <engineer-id> --ui-url
# SSHs through bastion, runs kubectl get gateway, prints URL + credentials
```

**`--show-gateway`** — Debug/learning view of Gateway resources:
```bash
# ./scripts/lab-connect.sh <engineer-id> --show-gateway
# Prints: kubectl get gateway,httproute -n kcm-system -o wide
```

---

## Section 4: Training Material Updates

### 4.1 Theory 1.2 — New Subsection: "Gateway API & Envoy Gateway"

Brief (~200 words) covering:
- **Gateway API** — Kubernetes-native successor to Ingress. Role-oriented model: infrastructure provider (GatewayClass), cluster operator (Gateway), application developer (HTTPRoute)
- **Why Gateway API over Ingress** — richer routing, role separation, portable across implementations, the active Kubernetes standard
- **Envoy Gateway** — CNCF project implementing Gateway API using Envoy proxy as the data plane
- **How k0rdent uses it** — management cluster uses Envoy Gateway for UI exposure; same pattern applies to child clusters for workload ingress

### 4.2 Lab 1.1 — Provision k0rdent

- Update "What gets provisioned" section: NLB → Envoy Gateway
- Update architecture diagram to show Gateway → HTTPRoute → k0rdent UI
- Update "Access the UI" section with new URL retrieval (`lab-provision.sh` output or `lab-connect.sh --ui-url`)
- Remove all references to NodePort 30080 and `k0rdent-ui-external`

### 4.3 Lab 1.2 — Explore k0rdent UI (Major Rewrite)

Replace the current "Training vs Production" split with a unified Gateway API approach:

**Section A: How the UI is Exposed (Training Lab)**
- Envoy Gateway installed during provisioning
- GatewayClass → Gateway (HTTP:80) → HTTPRoute → kcm-k0rdent-ui
- AWS CCM auto-provisions NLB for the Gateway's LoadBalancer service
- Basic auth (username/password)

**Section B: Production Upgrade Path**
- Add TLS listener to the same Gateway resource
- Configure OIDC via the Management CRD
- Add DNS record
- Add network policies

**Section C: Alternative Deployment Patterns**

| Pattern | When to Use |
|---------|-------------|
| Envoy Gateway + AWS CCM | AWS cloud (auto LB provisioning) |
| Envoy Gateway + MetalLB | On-prem / bare metal environments |
| Envoy Gateway + NodePort + external LB | Restricted cloud without CCM |
| `kubectl port-forward` | Developer laptops, quick access |

Each pattern: short explanation + key configuration differences.

**Section D: TLS Configuration Patterns**

| Method | When to Use |
|--------|-------------|
| cert-manager + Let's Encrypt | Public-facing, automated renewal |
| cert-manager + internal CA | Enterprise with existing PKI infrastructure |
| AWS ACM (NLB annotation) | AWS-native, no in-cluster cert management |
| Manual TLS Secret | Bring-your-own certificate from any source |

Each method: short explanation + example YAML showing Gateway TLS listener configuration.

### 4.4 Week 1 README

- Update architecture diagram: NLB → Envoy Gateway

### 4.5 Week 1 Quiz

- Update question 11: production UI exposure now references Gateway API instead of Ingress

---

## Files Affected

| File | Action |
|------|--------|
| `terraform/modules/k0rdent-mgmt/main.tf` | Remove NLB resources, update SG |
| `terraform/modules/k0rdent-mgmt/outputs.tf` | Remove `ui_url`, add `ui_access` |
| `terraform/modules/k0rdent-mgmt/variables.tf` | Add Gateway version variables |
| `terraform/modules/k0rdent-mgmt/templates/mgmt-cloud-init.yaml` | Add Envoy Gateway install, remove NodePort service |
| `terraform/environments/student-lab/main.tf` | Pass new variables to module |
| `terraform/environments/student-lab/outputs.tf` | Update UI output |
| `terraform/environments/student-lab/variables.tf` | Add Gateway version variables |
| `scripts/lab-provision.sh` | Wait for Gateway LB, print URL |
| `scripts/lab-connect.sh` | Add `--ui-url` and `--show-gateway` flags |
| `curriculum/week-1-foundations/README.md` | Update architecture diagram |
| `curriculum/week-1-foundations/theory/theory-1.2-*.md` | Add Gateway API subsection |
| `curriculum/week-1-foundations/labs/lab-1.1-*.md` | Update provisioning docs |
| `curriculum/week-1-foundations/labs/lab-1.2-*.md` | Rewrite access architecture section |
| `curriculum/week-1-foundations/week-1-quiz.md` | Update question 11 |
