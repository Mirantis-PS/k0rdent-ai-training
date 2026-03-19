# Envoy Gateway UI Exposure — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the NLB + NodePort UI exposure with Envoy Gateway (Gateway API), unifying training and production paths.

**Architecture:** Envoy Gateway is installed via Helm in cloud-init Stage 4. A GatewayClass + Gateway + HTTPRoute expose the k0rdent UI on port 80. AWS CCM auto-provisions a LoadBalancer. The Terraform NLB is removed entirely.

**Tech Stack:** Envoy Gateway v1.2.6, Gateway API CRDs v1.2.1, Terraform, Bash, k0s/k0rdent

**Design Doc:** `docs/plans/2026-03-18-envoy-gateway-ui-exposure-design.md`

---

## Phase 1: Terraform — Remove NLB, Update Security Group

### Task 1: Remove NLB Resources from k0rdent-mgmt Module

**Files:**
- Modify: `lab-infrastructure/terraform/modules/k0rdent-mgmt/main.tf:187-312`
- Modify: `lab-infrastructure/terraform/modules/k0rdent-mgmt/outputs.tf:95-98`
- Modify: `lab-infrastructure/terraform/modules/k0rdent-mgmt/variables.tf:30-33`

**Step 1: Remove the NLB security group ingress rule**

In `lab-infrastructure/terraform/modules/k0rdent-mgmt/main.tf`, replace lines 187-194:

```hcl
  # NLB health checks and traffic to k0rdent UI NodePort
  ingress {
    description = "k0rdent UI via NLB"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
```

With:

```hcl
  # Envoy Gateway LoadBalancer traffic (CCM-provisioned NLB uses dynamic NodePort)
  ingress {
    description = "Envoy Gateway LoadBalancer (dynamic NodePort via CCM)"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
```

**Step 2: Delete NLB resource blocks**

Delete lines 261-312 from `main.tf` — the entire section:

```
#------------------------------------------------------------------------------
# Network Load Balancer for k0rdent UI
#------------------------------------------------------------------------------
resource "aws_lb" "k0rdent_ui" { ... }
resource "aws_lb_target_group" "k0rdent_ui" { ... }
resource "aws_lb_listener" "k0rdent_ui" { ... }
resource "aws_lb_target_group_attachment" "k0rdent_ui" { ... }
```

**Step 3: Remove the `public_subnet_ids` variable**

In `lab-infrastructure/terraform/modules/k0rdent-mgmt/variables.tf`, delete lines 30-33:

```hcl
variable "public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing NLB"
  type        = list(string)
}
```

This variable was only used by the NLB resource.

**Step 4: Replace `ui_url` output with `ui_access`**

In `lab-infrastructure/terraform/modules/k0rdent-mgmt/outputs.tf`, replace lines 95-98:

```hcl
output "ui_url" {
  description = "k0rdent UI URL via NLB"
  value       = "http://${aws_lb.k0rdent_ui.dns_name}"
}
```

With:

```hcl
output "ui_access" {
  description = "How to retrieve the k0rdent UI URL (available after cloud-init completes)"
  value       = "Gateway LB URL available after init. Run: ./scripts/lab-connect.sh ${var.engineer_id} --ui-url"
}
```

**Step 5: Commit**

```bash
git add lab-infrastructure/terraform/modules/k0rdent-mgmt/
git commit -m "refactor(terraform): remove NLB, open NodePort range for Envoy Gateway CCM"
```

---

### Task 2: Add Gateway Version Variables

**Files:**
- Modify: `lab-infrastructure/terraform/modules/k0rdent-mgmt/variables.tf`
- Modify: `lab-infrastructure/terraform/environments/student-lab/main.tf:69-99`
- Modify: `lab-infrastructure/terraform/environments/student-lab/variables.tf`

**Step 1: Add version variables to the module**

In `lab-infrastructure/terraform/modules/k0rdent-mgmt/variables.tf`, add after the `flux_version` variable (after line 104):

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

**Step 2: Add variables to the student-lab environment**

In `lab-infrastructure/terraform/environments/student-lab/variables.tf`, add in the cluster configuration section:

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

**Step 3: Pass variables through to the module**

In `lab-infrastructure/terraform/environments/student-lab/main.tf`, in the `k0rdent_mgmt` module block (lines 69-99):

Remove:
```hcl
  public_subnet_ids     = module.networking.public_subnet_ids
```

Add:
```hcl
  gateway_api_version    = var.gateway_api_version
  envoy_gateway_version  = var.envoy_gateway_version
```

**Step 4: Update student-lab outputs**

In `lab-infrastructure/terraform/environments/student-lab/outputs.tf`, replace lines 48-51:

```hcl
output "ui_url" {
  description = "k0rdent UI URL"
  value       = module.k0rdent_mgmt.ui_url
}
```

With:

```hcl
output "ui_access" {
  description = "How to retrieve the k0rdent UI URL"
  value       = module.k0rdent_mgmt.ui_access
}
```

**Step 5: Commit**

```bash
git add lab-infrastructure/terraform/
git commit -m "feat(terraform): add Gateway API and Envoy Gateway version variables"
```

---

## Phase 2: Cloud-Init — Install Envoy Gateway, Create Gateway Resources

### Task 3: Replace NodePort Service with Envoy Gateway in Cloud-Init

**Files:**
- Modify: `lab-infrastructure/terraform/modules/k0rdent-mgmt/templates/mgmt-cloud-init.yaml:204-272`

**Step 1: Update the cloud-init template variables**

The cloud-init template is rendered by Terraform. Ensure the template receives the new variables. Check where template variables are defined in `main.tf` (the `locals` block that renders the template) and add:

```hcl
gateway_api_version    = var.gateway_api_version
envoy_gateway_version  = var.envoy_gateway_version
```

To the `templatefile()` call or locals block that feeds `mgmt-cloud-init.yaml`.

**Step 2: Add lab-info.env variables**

Find where `/opt/k0rdent-lab/config/lab-info.env` is written in the cloud-init template and add:

```bash
GATEWAY_API_VERSION="${gateway_api_version}"
ENVOY_GATEWAY_VERSION="${envoy_gateway_version}"
```

**Step 3: Replace the NodePort service block with Envoy Gateway install**

In `mgmt-cloud-init.yaml`, replace lines 235-271 (the entire `k0rdent-ui-external` NodePort service block):

```bash
      # Expose k0rdent UI via a separate NodePort service for NLB access.
      # We do NOT patch the original kcm-k0rdent-ui ClusterIP service because
      # the KCM operator reconciles it back to ClusterIP. Instead, we create
      # an independent service that selects the same pods but is not managed
      # by Helm/Flux, so it won't be reverted.
      echo "Creating k0rdent UI NodePort service for external access..."
      ...
      echo "Verifying external UI service..."
      kubectl get svc k0rdent-ui-external -n kcm-system -o wide
```

With:

```bash
      # =================================================================
      # Install Envoy Gateway for k0rdent UI exposure
      # Uses Gateway API (the Kubernetes-native successor to Ingress)
      # AWS CCM will auto-provision a LoadBalancer for the Gateway
      # =================================================================

      echo "Installing Gateway API CRDs ${GATEWAY_API_VERSION}..."
      kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

      echo "Installing Envoy Gateway ${ENVOY_GATEWAY_VERSION}..."
      helm install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
        --version "${ENVOY_GATEWAY_VERSION}" \
        --namespace envoy-gateway-system \
        --create-namespace \
        --wait --timeout 5m

      echo "Waiting for Envoy Gateway controller..."
      kubectl wait deployment/envoy-gateway -n envoy-gateway-system \
        --for=condition=Available --timeout=120s

      echo "Creating Gateway API resources for k0rdent UI..."
      cat <<GWEOF | kubectl apply -f -
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
      GWEOF

      echo "Waiting for Gateway LoadBalancer address..."
      GW_ADDR=""
      for i in $(seq 1 60); do
        GW_ADDR=$(kubectl get gateway k0rdent-gateway -n kcm-system \
          -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
        if [ -n "$GW_ADDR" ]; then
          echo "k0rdent UI available at: http://${GW_ADDR}"
          break
        fi
        echo -n "."
        sleep 5
      done

      if [ -z "$GW_ADDR" ]; then
        echo "WARNING: Gateway LB address not yet available. Check: kubectl get gateway -n kcm-system"
      fi

      echo "Gateway resources:"
      kubectl get gateway,httproute -n kcm-system -o wide
```

**Step 4: Commit**

```bash
git add lab-infrastructure/terraform/modules/k0rdent-mgmt/templates/mgmt-cloud-init.yaml
git commit -m "feat(cloud-init): install Envoy Gateway, replace NodePort with Gateway API"
```

---

## Phase 3: Script Updates

### Task 4: Update lab-provision.sh to Wait for Gateway LB URL

**Files:**
- Modify: `lab-infrastructure/scripts/lab-provision.sh:229-237`

**Step 1: Add a wait-for-gateway function**

Add after the `wait_for_instance()` function (after line 73):

```bash
# Wait for cloud-init and retrieve Gateway LB URL
wait_for_gateway_url() {
    local bastion_ip="$1"
    local mgmt_ip="$2"
    local key_file="$3"
    local bastion_key="$4"
    local max_wait="${5:-600}"
    local start_time=$(date +%s)

    log_info "Waiting for k0rdent initialization to complete..."

    # SSH options for bastion jump
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    local proxy_cmd="ssh ${ssh_opts} -i ${bastion_key} -W %h:%p ubuntu@${bastion_ip}"

    while true; do
        local init_done
        init_done=$(ssh ${ssh_opts} -i "$key_file" -o "ProxyCommand=${proxy_cmd}" ubuntu@"${mgmt_ip}" \
            "test -f /opt/k0rdent-lab/.init-complete && echo yes || echo no" 2>/dev/null || echo "no")

        if [[ "$init_done" == "yes" ]]; then
            log_success "k0rdent initialization complete"
            break
        fi

        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $max_wait ]]; then
            log_warn "Timeout waiting for init (${max_wait}s). Check logs on the instance."
            return 1
        fi

        echo -n "."
        sleep 15
    done

    # Retrieve Gateway LB URL
    log_info "Retrieving Gateway LoadBalancer URL..."
    local gw_addr
    gw_addr=$(ssh ${ssh_opts} -i "$key_file" -o "ProxyCommand=${proxy_cmd}" ubuntu@"${mgmt_ip}" \
        "kubectl get gateway k0rdent-gateway -n kcm-system -o jsonpath='{.status.addresses[0].value}'" 2>/dev/null || true)

    if [[ -n "$gw_addr" ]]; then
        echo "http://${gw_addr}"
    else
        log_warn "Gateway LB address not available yet"
        echo ""
    fi
}
```

**Step 2: Update the provision output section**

Replace lines 229-237 in the `provision_lab` function:

```bash
    log_success "Lab environment provisioned for $engineer_id!"
    log_info "Bastion IP: $(terraform output -raw bastion_public_ip)"
    log_info "Primary node IP: $(terraform output -raw primary_node_private_ip)"
    log_info "SSH key: $key_dir/${engineer_id}-k0rdent.pem"
    log_info "Connect via: ./lab-connect.sh $engineer_id"
    echo ""
    log_info "k0rdent UI:"
    log_info "  URL:      $(terraform output -raw ui_url 2>/dev/null || echo 'initializing...')"
    log_info "  Password: run: terraform output ui_password"
```

With:

```bash
    local bastion_ip
    bastion_ip=$(terraform output -raw bastion_public_ip)
    local mgmt_ip
    mgmt_ip=$(terraform output -raw primary_node_private_ip)
    local mgmt_key="$key_dir/${engineer_id}-k0rdent.pem"
    local bastion_key="$key_dir/${engineer_id}-bastion.pem"

    log_success "Infrastructure provisioned for $engineer_id!"
    log_info "Bastion IP: $bastion_ip"
    log_info "Primary node IP: $mgmt_ip"
    log_info "SSH key: $mgmt_key"
    log_info "Connect via: ./lab-connect.sh $engineer_id"
    echo ""

    log_info "Waiting for k0rdent + Envoy Gateway to be ready..."
    local ui_url
    ui_url=$(wait_for_gateway_url "$bastion_ip" "$mgmt_ip" "$mgmt_key" "$bastion_key")

    local ui_password
    ui_password=$(terraform output -raw ui_password 2>/dev/null || echo "unknown")

    echo ""
    echo "============================================"
    echo "  k0rdent UI"
    echo "  URL:       ${ui_url:-'not yet available — run: ./lab-connect.sh $engineer_id --ui-url'}"
    echo "  Username:  admin"
    echo "  Password:  ${ui_password}"
    echo "============================================"
    echo ""
    log_info "To retrieve the URL later: ./lab-connect.sh $engineer_id --ui-url"
```

**Step 3: Commit**

```bash
git add lab-infrastructure/scripts/lab-provision.sh
git commit -m "feat(scripts): lab-provision waits for Gateway LB URL before finishing"
```

---

### Task 5: Add --ui-url and --show-gateway Flags to lab-connect.sh

**Files:**
- Modify: `lab-infrastructure/scripts/lab-connect.sh:197-280`

**Step 1: Add new flag variables**

In the defaults section (around line 200), add:

```bash
SHOW_UI_URL="false"
SHOW_GATEWAY="false"
```

**Step 2: Add flag parsing**

In the `case` block (lines 205-239), add before `--help`:

```bash
        --ui-url)
            SHOW_UI_URL="true"
            shift
            ;;
        --show-gateway)
            SHOW_GATEWAY="true"
            shift
            ;;
```

**Step 3: Add --ui-url handler**

After the `--show-password` handler block (after line 280), add:

```bash
# Show Gateway UI URL and exit if requested
if [[ "$SHOW_UI_URL" == "true" ]]; then
    KEY_FILE=$(get_ssh_key "$IDENTIFIER")
    IP=$(get_instance_ip "$IDENTIFIER")
    BASTION=$(get_bastion_ip)
    ensure_bastion_key "$IDENTIFIER"
    BASTION_KEY="$CONFIG_DIR/keys/${IDENTIFIER}-bastion.pem"

    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    PROXY_CMD="ssh ${SSH_OPTS} -i ${BASTION_KEY} -W %h:%p ubuntu@${BASTION}"

    GW_ADDR=$(ssh ${SSH_OPTS} -i "$KEY_FILE" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${IP}" \
        "kubectl get gateway k0rdent-gateway -n kcm-system -o jsonpath='{.status.addresses[0].value}'" 2>/dev/null || true)
    UI_PASSWORD=$(ssh ${SSH_OPTS} -i "$KEY_FILE" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${IP}" \
        "kubectl get secret -n kcm-system kcm-k0rdent-ui-basic-auth -o jsonpath='{.data.password}' | base64 -d" 2>/dev/null || true)

    if [[ -n "$GW_ADDR" ]]; then
        echo ""
        log_success "k0rdent UI"
        echo "  URL:       http://${GW_ADDR}"
        echo "  Username:  admin"
        echo "  Password:  ${UI_PASSWORD:-unknown}"
        echo ""
    else
        log_error "Gateway LB address not available. Is initialization complete?"
        log_info "Check: ssh into node and run: kubectl get gateway -n kcm-system"
        exit 1
    fi
    exit 0
fi

# Show Gateway status and exit if requested
if [[ "$SHOW_GATEWAY" == "true" ]]; then
    KEY_FILE=$(get_ssh_key "$IDENTIFIER")
    IP=$(get_instance_ip "$IDENTIFIER")
    BASTION=$(get_bastion_ip)
    ensure_bastion_key "$IDENTIFIER"
    BASTION_KEY="$CONFIG_DIR/keys/${IDENTIFIER}-bastion.pem"

    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    PROXY_CMD="ssh ${SSH_OPTS} -i ${BASTION_KEY} -W %h:%p ubuntu@${BASTION}"

    echo ""
    log_info "Gateway API Resources:"
    ssh ${SSH_OPTS} -i "$KEY_FILE" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${IP}" \
        "kubectl get gatewayclass,gateway,httproute -A -o wide" 2>/dev/null
    echo ""
    log_info "Envoy Gateway Pods:"
    ssh ${SSH_OPTS} -i "$KEY_FILE" -o "ProxyCommand=${PROXY_CMD}" ubuntu@"${IP}" \
        "kubectl get pods -n envoy-gateway-system -o wide" 2>/dev/null
    exit 0
fi
```

**Step 4: Update the --show-password handler**

In the existing `--show-password` handler (lines 264-279), update the UI URL retrieval to use Gateway instead of Terraform state. Replace:

```bash
    UI_URL=$(get_state_output "$BUCKET" "ui_url")
```

With:

```bash
    # UI URL is now served via Envoy Gateway, not Terraform output
    UI_URL="Retrieve via: ./lab-connect.sh $IDENTIFIER --ui-url"
```

**Step 5: Update the usage function**

Find the `usage()` function and add the new flags:

```
    --ui-url            Show k0rdent UI URL (via Envoy Gateway) and exit
    --show-gateway      Show Gateway API resource status and exit
```

**Step 6: Commit**

```bash
git add lab-infrastructure/scripts/lab-connect.sh
git commit -m "feat(scripts): add --ui-url and --show-gateway flags to lab-connect"
```

---

## Phase 4: Training Material Updates

### Task 6: Add Gateway API Theory Section

**Files:**
- Modify: `curriculum/week-1-foundations/theory/1.2-k0rdent-components.md`

**Step 1: Add Gateway API subsection**

Find the section on networking/service exposure (around the ServiceTemplate / ingress-nginx area, ~lines 343-365) and add a new subsection before or after it:

```markdown
### Gateway API & Envoy Gateway

k0rdent Enterprise uses the **Kubernetes Gateway API** to expose the management UI and route traffic to services. Gateway API is the Kubernetes-native successor to the Ingress API, offering a role-oriented model with clearer separation of concerns:

| Resource | Owner | Purpose |
|----------|-------|---------|
| **GatewayClass** | Infrastructure provider | Defines the controller (e.g., Envoy Gateway) |
| **Gateway** | Cluster operator | Configures listeners (ports, protocols, TLS) |
| **HTTPRoute** | Application developer | Routes traffic to backend services |

**Why Gateway API over Ingress?**
- **Role separation** — infrastructure teams manage GatewayClass/Gateway, app teams manage HTTPRoutes
- **Richer routing** — header-based routing, traffic splitting, request mirroring built-in
- **Portable** — same resources work across Envoy Gateway, Istio, Cilium, and other implementations
- **Active standard** — Ingress API is frozen; Gateway API is where Kubernetes networking evolves

**Envoy Gateway** is a CNCF project that implements Gateway API using **Envoy proxy** as the data plane. It provides a simple operator model: install via Helm, create a GatewayClass, and the controller handles the rest — including provisioning cloud LoadBalancers via the cloud controller manager.

In the training lab, Envoy Gateway runs on the management cluster and exposes the k0rdent UI. The same pattern applies to child clusters for workload ingress.
```

Also update any references to ingress-nginx as the recommended approach to instead reference Gateway API / Envoy Gateway as the primary pattern.

**Step 2: Commit**

```bash
git add curriculum/week-1-foundations/theory/
git commit -m "docs(theory): add Gateway API & Envoy Gateway section to Theory 1.2"
```

---

### Task 7: Update Lab 1.1 — Provisioning Docs

**Files:**
- Modify: `curriculum/week-1-foundations/labs/lab-1.1-provision-k0rdent.md:261-294`

**Step 1: Update the UI access section (Part 7)**

Replace the current content at lines 261-294 that references NLB and `terraform output ui_url` with:

```markdown
### Part 7: Access the k0rdent UI

The provisioning script waits for k0rdent and Envoy Gateway to be fully operational before printing the UI URL.

**How the UI is exposed:**

```
Browser (HTTP) → AWS NLB (auto-provisioned) → Envoy Gateway → HTTPRoute → k0rdent UI (:3000)
```

Envoy Gateway uses the Kubernetes Gateway API to route traffic. AWS Cloud Controller Manager automatically provisions a Network Load Balancer for the Gateway's Service.

**The URL is printed at the end of provisioning:**

```
============================================
  k0rdent UI
  URL:       http://xxxxx.elb.us-east-1.amazonaws.com
  Username:  admin
  Password:  <generated>
============================================
```

**To retrieve the URL later:**

```bash
# Get UI URL and credentials
./scripts/lab-connect.sh <your-name> --ui-url

# View Gateway API resource status
./scripts/lab-connect.sh <your-name> --show-gateway
```

**From inside the cluster (via SSH):**

```bash
# Get the Gateway LB address
kubectl get gateway k0rdent-gateway -n kcm-system

# View all Gateway API resources
kubectl get gatewayclass,gateway,httproute -A
```
```

**Step 2: Update the architecture diagram earlier in the file**

Find the "What gets provisioned" section and replace NLB references with Envoy Gateway. Change the traffic flow diagram to:

```
AWS NLB (auto-provisioned by CCM) → Envoy Gateway → k0rdent UI
```

**Step 3: Commit**

```bash
git add curriculum/week-1-foundations/labs/lab-1.1-provision-k0rdent.md
git commit -m "docs(lab-1.1): update UI access to use Envoy Gateway"
```

---

### Task 8: Rewrite Lab 1.2 — Access Architecture Section

**Files:**
- Modify: `curriculum/week-1-foundations/labs/lab-1.2-explore-k0rdent-ui.md:59-321`

This is the largest content change. Replace the entire "Part 2: Understanding k0rdent UI Access Architecture" section (lines 59-321) with a unified Gateway API approach.

**Step 1: Write the new Part 2**

The new section should have this structure:

```markdown
## Part 2: Understanding k0rdent UI Access Architecture

### How the UI is Exposed

k0rdent Enterprise exposes its UI through the **Kubernetes Gateway API** using **Envoy Gateway** as the implementation.

#### Training Lab Architecture

```
Student Browser (HTTP)
    │
    ▼
AWS NLB (auto-provisioned by AWS Cloud Controller Manager)
    │ port 80
    ▼
Envoy Gateway (envoy-gateway-system namespace)
    │ Gateway listener on port 80
    ▼
HTTPRoute (kcm-system namespace)
    │ path: / → kcm-k0rdent-ui:3000
    ▼
k0rdent UI Pod (ClusterIP, Helm-managed)
```

**Key resources:**

| Resource | Name | Namespace | Purpose |
|----------|------|-----------|---------|
| GatewayClass | `envoy-gateway` | cluster-scoped | Defines Envoy Gateway as the controller |
| Gateway | `k0rdent-gateway` | `kcm-system` | Listens on port 80 (HTTP) |
| HTTPRoute | `k0rdent-ui` | `kcm-system` | Routes `/` to `kcm-k0rdent-ui:3000` |

#### Examine the Training Setup

```bash
# View the GatewayClass (cluster-scoped)
kubectl get gatewayclass envoy-gateway -o yaml

# View the Gateway and its LoadBalancer address
kubectl get gateway k0rdent-gateway -n kcm-system -o yaml

# View the HTTPRoute
kubectl get httproute k0rdent-ui -n kcm-system -o yaml

# View the auto-provisioned Envoy proxy pods
kubectl get pods -n envoy-gateway-system

# View the LoadBalancer service (created by Envoy Gateway controller)
kubectl get svc -n envoy-gateway-system
```

### Production Upgrade Path

The training lab uses HTTP with basic auth. Production deployments add **TLS termination** and **OIDC authentication** to the same Gateway resources.

#### Step 1: Add TLS to the Gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k0rdent-gateway
  namespace: kcm-system
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: k0rdent-ui-tls
```

#### Step 2: Configure OIDC Authentication

```yaml
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Management
metadata:
  name: kcm
  namespace: kcm-system
spec:
  core:
    kcm:
      config:
        k0rdent-ui:
          enabled: true
          auth:
            oidc:
              issuerUrl: "https://login.microsoftonline.com/<tenant-id>/v2.0"
              clientId: "<your-client-id>"
              clientSecret: "<your-client-secret>"
```

#### Production Checklist

- [ ] TLS certificates provisioned (see TLS patterns below)
- [ ] Gateway listener updated to HTTPS (port 443)
- [ ] OIDC configured in the Management object
- [ ] DNS record pointing to the LoadBalancer address
- [ ] Network policies restricting UI access to corporate networks
- [ ] HTTP → HTTPS redirect configured (optional HTTPRoute)

### Alternative Deployment Patterns

Different customer environments require different approaches to LoadBalancer provisioning. The Gateway API resources (GatewayClass, Gateway, HTTPRoute) stay the same — only the infrastructure layer changes.

#### Envoy Gateway + AWS CCM (Training Default)

Used in the training lab. AWS Cloud Controller Manager auto-provisions a Network Load Balancer when the Gateway creates a `type: LoadBalancer` service.

**When to use:** AWS cloud environments with CCM configured.

**How it works:** Install Envoy Gateway → create Gateway → CCM provisions NLB automatically.

#### Envoy Gateway + MetalLB

For on-premises or bare-metal environments without a cloud LoadBalancer.

**When to use:** On-prem data centers, bare-metal clusters, home labs.

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

# Configure IP pool
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.240-192.168.1.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2
  namespace: metallb-system
EOF
```

The Gateway and HTTPRoute resources remain identical — MetalLB assigns an IP from the pool instead of a cloud NLB hostname.

#### Envoy Gateway + NodePort + External Load Balancer

For restricted cloud environments where CCM is not available or LoadBalancer services are not permitted.

**When to use:** Air-gapped environments, restricted cloud accounts, environments behind an existing external load balancer.

```yaml
# Override Envoy Gateway's service type via Helm values
# helm install envoy-gateway ... --set service.type=NodePort
```

Then configure the external load balancer to route to the NodePort allocated by Kubernetes.

#### kubectl port-forward

For quick local access without any infrastructure.

**When to use:** Developer laptops, quick debugging, temporary access.

```bash
kubectl port-forward svc/kcm-k0rdent-ui -n kcm-system 8080:3000
# Access at http://localhost:8080
```

No Gateway needed — direct access to the ClusterIP service.

### TLS Configuration Patterns

All patterns configure TLS at the Gateway listener level. The HTTPRoute and backend service remain unchanged.

#### cert-manager + Let's Encrypt

Automated certificate issuance and renewal. Best for public-facing deployments.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@company.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          gatewayHTTPRoute:
            parentRefs:
              - name: k0rdent-gateway
                namespace: kcm-system
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: k0rdent-ui-tls
  namespace: kcm-system
spec:
  secretName: k0rdent-ui-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - k0rdent.company.com
```

#### cert-manager + Internal CA

For enterprises with existing PKI infrastructure.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca
spec:
  ca:
    secretName: internal-ca-key-pair  # Your CA cert + key
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: k0rdent-ui-tls
  namespace: kcm-system
spec:
  secretName: k0rdent-ui-tls
  issuerRef:
    name: internal-ca
    kind: ClusterIssuer
  dnsNames:
    - k0rdent.company.com
```

#### AWS ACM (via NLB Annotation)

AWS-native approach — no in-cluster cert management. TLS terminates at the NLB.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k0rdent-gateway
  namespace: kcm-system
  annotations:
    # ACM certificate ARN — NLB terminates TLS
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:us-east-1:123456:certificate/abc-123"
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
```

> **Note:** With ACM, TLS terminates at the NLB. Traffic between NLB and Envoy Gateway is unencrypted inside the VPC. For end-to-end encryption, use cert-manager instead.

#### Manual TLS Secret

Bring your own certificate from any source.

```bash
# Create the TLS secret from your cert files
kubectl create secret tls k0rdent-ui-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n kcm-system
```

Then reference `k0rdent-ui-tls` in the Gateway's TLS listener configuration (same as the cert-manager examples above).
```

**Step 2: Commit**

```bash
git add curriculum/week-1-foundations/labs/lab-1.2-explore-k0rdent-ui.md
git commit -m "docs(lab-1.2): rewrite access architecture for Envoy Gateway + Gateway API"
```

---

### Task 9: Update Week 1 README and Quiz

**Files:**
- Modify: `curriculum/week-1-foundations/README.md:76-109`
- Modify: `curriculum/week-1-foundations/week-1-quiz.md:83-88, 145-146`

**Step 1: Update README architecture diagram**

In `README.md`, find the architecture diagram section (~lines 76-109) and replace NLB references with Envoy Gateway. The diagram should show:

```
AWS NLB (auto-provisioned by CCM) → Envoy Gateway → k0rdent UI (:3000)
```

Instead of:

```
AWS NLB → NodePort 30080 → k0rdent UI (:3000)
```

**Step 2: Update Quiz question 11**

In `week-1-quiz.md`, update question 11 (lines 83-88) to reference Gateway API:

```markdown
**11. What is the recommended way to expose the k0rdent UI in production?**

a) kubectl port-forward
b) NodePort service with a static port
c) Gateway API (Gateway + HTTPRoute) with TLS and OIDC authentication
d) Direct pod IP access with a load balancer
```

Update the answer key (lines 145-146) — correct answer remains (c) but the explanation should reference Gateway API instead of Ingress.

**Step 3: Commit**

```bash
git add curriculum/week-1-foundations/README.md curriculum/week-1-foundations/week-1-quiz.md
git commit -m "docs(week1): update README diagram and quiz for Gateway API"
```

---

## Summary

| Phase | Tasks | Commits |
|-------|-------|---------|
| Phase 1: Terraform | Tasks 1-2 | 2 commits |
| Phase 2: Cloud-Init | Task 3 | 1 commit |
| Phase 3: Scripts | Tasks 4-5 | 2 commits |
| Phase 4: Training Materials | Tasks 6-9 | 4 commits |
| **Total** | **9 tasks** | **9 commits** |

**Execution order matters:** Phase 1 and 2 can be done in parallel. Phase 3 depends on Phase 1 (outputs change). Phase 4 is independent of all other phases.
