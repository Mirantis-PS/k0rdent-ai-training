# Lab 5.5 - Service Catalog Blueprints

**Duration:** 2 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy AI/ML services from k0rdent's service catalog using blueprints, understanding how automatic Ingress, network policies, and secrets management are integrated into the deployment workflow.

## Prerequisites

- Completed Labs 5.1-5.4
- k0rdent management cluster access
- Understanding of Helm and Kubernetes services

## Background

### What is the Service Catalog?

k0rdent's service catalog provides:

- **Pre-configured Blueprints**: Production-ready service templates
- **Automatic Networking**: Ingress and network policies
- **Secret Injection**: Platform-managed certificates and credentials
- **Version Management**: Curated, tested service versions
- **Multi-Tenancy**: Namespace isolation per team

### Service Categories

| Category | Services | Use Case |
|----------|----------|----------|
| **AI/ML** | vLLM, Triton, TensorFlow Serving | Model inference |
| **Data** | Milvus, PostgreSQL, Redis | Data storage |
| **ML Platform** | Kubeflow, MLflow, JupyterHub | ML lifecycle |
| **Monitoring** | Prometheus, Grafana, DCGM | Observability |
| **Networking** | Istio, NGINX, Cert-Manager | Traffic management |

## Lab Environment

**Cluster Requirements:**
- k0rdent management cluster access
- At least one workload cluster
- Service catalog configured

## Tasks

### Task 1: Explore Service Catalog (15 min)

1. **List Available Service Templates**
   ```bash
   # List all service templates
   kubectl get servicetemplates -n kcm-system

   # Filter by category
   kubectl get servicetemplates -n kcm-system -l category=ai-ml
   kubectl get servicetemplates -n kcm-system -l category=data
   kubectl get servicetemplates -n kcm-system -l category=monitoring
   ```

2. **View Service Template Details**
   ```bash
   # Get template details
   kubectl get servicetemplate <template-name> -n kcm-system -o yaml

   # Example for vLLM
   kubectl get servicetemplate vllm -n kcm-system -o yaml | head -100
   ```

3. **Understand Template Structure**
   ```yaml
   apiVersion: k0rdent.mirantis.com/v1alpha1
   kind: ServiceTemplate
   metadata:
     name: vllm
     namespace: kcm-system
     labels:
       category: ai-ml
       type: inference
   spec:
     # Helm chart reference
     helm:
       chartRef:
         name: vllm
         version: 0.11.2
         repo: https://charts.example.com

     # Configurable parameters
     parameters:
       - name: model
         description: "HuggingFace model ID"
         type: string
         default: "meta-llama/Llama-2-7b-chat-hf"
       - name: gpuCount
         description: "Number of GPUs"
         type: integer
         default: 1

     # Network policy rules
     networkPolicy:
       ingress:
         - from:
             - namespaceSelector:
                 matchLabels:
                   kubernetes.io/metadata.name: istio-system
       egress:
         - to:
             - ipBlock:
                 cidr: 0.0.0.0/0

     # Automatic ingress configuration
     ingress:
       enabled: true
       pathPrefix: /v1
       tls: true
   ```

### Task 2: Deploy Service Using CLI (30 min)

1. **Create Target Namespace**
   ```bash
   kubectl create namespace ml-services
   kubectl label namespace ml-services k0rdent.mirantis.com/managed=true
   ```

2. **Create Service Deployment**
   ```yaml
   # Save as vllm-service-deployment.yaml
   apiVersion: k0rdent.mirantis.com/v1alpha1
   kind: ServiceDeployment
   metadata:
     name: vllm-inference
     namespace: ml-services
   spec:
     # Reference the service template
     template:
       name: vllm
       namespace: kcm-system

     # Override default values
     values:
       model: "mistralai/Mistral-7B-Instruct-v0.2"
       gpuCount: 1
       replicas: 1
       resources:
         limits:
           nvidia.com/gpu: 1
           memory: 32Gi
           cpu: "4"

     # Ingress configuration
     ingress:
       enabled: true
       host: vllm.ml-services.example.com
       tls:
         enabled: true
         secretName: vllm-tls

     # Network policy
     networkPolicy:
       enabled: true
       allowedNamespaces:
         - istio-system
         - monitoring

     # Secrets to inject
     secrets:
       - name: huggingface-token
         key: HF_TOKEN
   ```

3. **Apply Service Deployment**
   ```bash
   kubectl apply -f vllm-service-deployment.yaml

   # Watch deployment progress
   kubectl get servicedeployment vllm-inference -n ml-services -w
   ```

4. **Verify Created Resources**
   ```bash
   # Check all resources created by the service
   kubectl get all -n ml-services -l k0rdent.mirantis.com/service=vllm-inference

   # Check ingress
   kubectl get ingress -n ml-services

   # Check network policy
   kubectl get networkpolicy -n ml-services

   # Check TLS secret (auto-generated)
   kubectl get secret -n ml-services | grep tls
   ```

### Task 3: Deploy via k0rdent UI (Optional - 20 min)

1. **Access k0rdent UI**
   ```bash
   kubectl port-forward svc/k0rdent-ui -n kcm-system 8080:80 &
   ```
   - Open: `http://localhost:8080`

2. **Navigate to Service Catalog**
   - Click "Service Catalog" in left navigation
   - Browse available services

3. **Deploy Service**
   - Select "vLLM Inference"
   - Choose target namespace
   - Configure parameters (model, GPU count)
   - Enable Ingress
   - Click "Deploy"

4. **Monitor Deployment**
   - View deployment progress in UI
   - Check logs and events

### Task 4: Customize Blueprint Inputs (30 min)

1. **View Available Parameters**
   ```bash
   # Get all configurable parameters
   kubectl get servicetemplate vllm -n kcm-system -o jsonpath='{.spec.parameters[*].name}'
   ```

2. **Create Custom Configuration**
   ```yaml
   # Save as custom-vllm-deployment.yaml
   apiVersion: k0rdent.mirantis.com/v1alpha1
   kind: ServiceDeployment
   metadata:
     name: vllm-custom
     namespace: ml-services
   spec:
     template:
       name: vllm
       namespace: kcm-system

     values:
       # Model configuration
       model: "codellama/CodeLlama-7b-Instruct-hf"
       tensorParallelSize: 1
       maxModelLen: 8192
       gpuMemoryUtilization: 0.85

       # Scaling
       replicas: 2
       autoscaling:
         enabled: true
         minReplicas: 1
         maxReplicas: 4
         targetCPUUtilization: 70

       # Resources per replica
       resources:
         requests:
           nvidia.com/gpu: 1
           memory: 24Gi
           cpu: "2"
         limits:
           nvidia.com/gpu: 1
           memory: 32Gi
           cpu: "4"

       # Probes
       livenessProbe:
         initialDelaySeconds: 300
         periodSeconds: 30
       readinessProbe:
         initialDelaySeconds: 60
         periodSeconds: 10

     # Advanced networking
     ingress:
       enabled: true
       host: codellama.ml-services.example.com
       annotations:
         nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
         nginx.ingress.kubernetes.io/proxy-body-size: "100m"

     # Monitoring
     monitoring:
       enabled: true
       serviceMonitor: true
       prometheusRule: true
   ```

3. **Apply and Verify**
   ```bash
   kubectl apply -f custom-vllm-deployment.yaml

   # Check deployment
   kubectl get servicedeployment vllm-custom -n ml-services

   # Verify HPA was created
   kubectl get hpa -n ml-services

   # Verify ServiceMonitor
   kubectl get servicemonitor -n ml-services
   ```

### Task 5: Verify Network Policy Enforcement (15 min)

1. **View Created Network Policy**
   ```bash
   kubectl get networkpolicy -n ml-services -o yaml
   ```

2. **Test Network Isolation**
   ```bash
   # Create a test pod in allowed namespace
   kubectl run test-allowed -n istio-system --rm -it --image=curlimages/curl -- \
     curl http://vllm-inference.ml-services:8000/health

   # Create a test pod in disallowed namespace
   kubectl create namespace test-blocked
   kubectl run test-blocked -n test-blocked --rm -it --image=curlimages/curl -- \
     curl --connect-timeout 5 http://vllm-inference.ml-services:8000/health
   # This should timeout due to network policy
   ```

3. **Clean Up Test Resources**
   ```bash
   kubectl delete namespace test-blocked
   ```

### Task 6: Review Version Pinning (10 min)

1. **Check Available Versions**
   ```bash
   # List template versions
   kubectl get servicetemplates -n kcm-system -l app=vllm

   # Or check annotations
   kubectl get servicetemplate vllm -n kcm-system -o jsonpath='{.metadata.annotations}'
   ```

2. **Pin to Specific Version**
   ```yaml
   # In ServiceDeployment spec:
   spec:
     template:
       name: vllm
       namespace: kcm-system
       version: "0.11.2"  # Pin specific version
   ```

3. **Understand Version Strategy**
   - **Development**: Track latest minor version
   - **Staging**: Pin patch version
   - **Production**: Pin exact version, manual upgrades

## Deliverables

- [ ] **Screenshot** of service catalog listing
- [ ] **ServiceDeployment YAML** with custom configuration
- [ ] **Screenshot** of deployed service showing all components
- [ ] **Network policy test results** showing isolation
- [ ] **Notes** on parameter customization

## Verification Checklist

- [ ] Service templates visible in catalog
- [ ] ServiceDeployment created successfully
- [ ] Pods running and healthy
- [ ] Ingress created with TLS
- [ ] Network policy enforced
- [ ] Monitoring enabled (if applicable)
- [ ] Version pinning understood

## Troubleshooting

### ServiceDeployment Stuck

**Check KCM controller logs:**
```bash
kubectl logs -n kcm-system -l app=kcm-controller --tail=100
```

**Check events:**
```bash
kubectl describe servicedeployment <name> -n <namespace>
```

### Ingress Not Working

**Check ingress controller:**
```bash
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

**Verify DNS/host resolution:**
```bash
nslookup vllm.ml-services.example.com
```

### Network Policy Blocking Traffic

**Debug network policies:**
```bash
kubectl describe networkpolicy -n ml-services
```

**Check if source namespace is labeled correctly:**
```bash
kubectl get namespace <source-ns> --show-labels
```

## Key Takeaways

1. **Service catalog simplifies deployment** of complex AI/ML services
2. **Templates encode best practices** for production deployments
3. **Automatic networking** reduces configuration errors
4. **Network policies provide security** without manual configuration
5. **Version pinning is critical** for production stability
6. **Blueprints can be customized** while maintaining governance
7. **Monitor deployments** through integrated observability

## Next Lab

Proceed to [Lab 5.6 - Troubleshooting GPU Scheduling](lab-5.6-troubleshooting-gpu.md)
