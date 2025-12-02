# Lab 5.7 - NVIDIA FIPS Configuration

**Duration:** 2 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy and configure NVIDIA GPU Operator with FIPS 140-2 compliant components for regulated environments requiring cryptographic validation.

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler deployed)
- Kubernetes cluster with GPU nodes
- Understanding of FIPS 140-2 compliance requirements

## Background

### What is FIPS 140-2?

FIPS 140-2 (Federal Information Processing Standard) is a U.S. government security standard for cryptographic modules. Organizations in government, healthcare, and finance often require FIPS compliance for their infrastructure.

### NVIDIA FIPS Components

NVIDIA provides FIPS-validated versions of:
- **GPU Driver**: Cryptographic operations in driver
- **Container Toolkit**: Secure container runtime integration
- **CUDA Libraries**: FIPS-validated cryptographic functions
- **NCCL**: Secure multi-GPU communication

## Lab Environment

**Cluster Requirements:**
- Kubernetes 1.28+ with GPU nodes
- NVIDIA A100 or H100 GPUs
- RHEL 8.x or Ubuntu 22.04 (FIPS-enabled OS)

## Tasks

### Task 1: Verify Host FIPS Mode (20 min)

1. **Check if OS FIPS Mode is Enabled**
   ```bash
   # SSH to GPU node
   ssh gpu-node-1

   # Check FIPS mode status
   cat /proc/sys/crypto/fips_enabled
   # Expected: 1 (enabled) or 0 (disabled)

   # For RHEL/CentOS
   fips-mode-setup --check

   # For Ubuntu
   cat /proc/sys/crypto/fips_enabled
   ```

2. **Enable FIPS Mode (if not enabled)**
   ```bash
   # RHEL/Rocky Linux
   sudo fips-mode-setup --enable
   sudo reboot

   # Ubuntu 22.04
   sudo apt install ubuntu-fips
   sudo ua enable fips
   sudo reboot
   ```

3. **Verify FIPS Crypto Modules**
   ```bash
   # List FIPS-validated modules
   cat /proc/crypto | grep -i fips

   # Check OpenSSL FIPS mode
   openssl version
   openssl md5 /dev/null  # Should fail in FIPS mode (MD5 not allowed)
   ```

### Task 2: Deploy NVIDIA GPU Operator with FIPS (30 min)

1. **Add NVIDIA Helm Repository**
   ```bash
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
   helm repo update
   ```

2. **Create FIPS Configuration Values**
   ```yaml
   # Save as nvidia-gpu-operator-fips-values.yaml
   operator:
     defaultRuntime: containerd

   driver:
     enabled: true
     version: "570.00"
     repository: nvcr.io/nvidia
     image: driver
     # Use FIPS-validated driver
     licensingConfig:
       configMapName: ""
     env:
       - name: NVIDIA_DRIVER_CAPABILITIES
         value: "compute,utility"

   toolkit:
     enabled: true
     version: v1.16.2-ubi8
     repository: nvcr.io/nvidia/k8s
     image: container-toolkit

   devicePlugin:
     enabled: true
     version: v0.16.2-ubi8

   dcgm:
     enabled: true
     version: 3.3.8-1-ubi9

   dcgmExporter:
     enabled: true
     version: 3.3.8-3.6.0-ubi9
     env:
       - name: DCGM_EXPORTER_COLLECTORS
         value: "/etc/dcgm-exporter/dcp-metrics-included.csv"

   # FIPS-specific configurations
   validator:
     enabled: true
     driver:
       env:
         - name: NVIDIA_VISIBLE_DEVICES
           value: "all"

   # Node feature discovery for FIPS detection
   nfd:
     enabled: true

   # GPU Feature Discovery
   gfd:
     enabled: true
   ```

3. **Deploy GPU Operator with FIPS Values**
   ```bash
   kubectl create namespace gpu-operator

   helm install gpu-operator nvidia/gpu-operator \
     --namespace gpu-operator \
     --version v25.10.0 \
     --values nvidia-gpu-operator-fips-values.yaml \
     --wait
   ```

4. **Monitor Deployment**
   ```bash
   # Watch pods come up
   kubectl get pods -n gpu-operator -w

   # Check operator logs
   kubectl logs -n gpu-operator -l app=gpu-operator --tail=100
   ```

### Task 3: Verify FIPS Driver Installation (25 min)

1. **Check Driver Pod Status**
   ```bash
   kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset

   # Get driver pod logs
   kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=50
   ```

2. **Verify Driver FIPS Mode**
   ```bash
   # Exec into driver pod
   DRIVER_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o jsonpath='{.items[0].metadata.name}')

   kubectl exec -n gpu-operator $DRIVER_POD -- nvidia-smi

   # Check driver version and FIPS status
   kubectl exec -n gpu-operator $DRIVER_POD -- cat /proc/driver/nvidia/version
   ```

3. **Test GPU Functionality**
   ```bash
   # Create a test pod
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: fips-gpu-test
   spec:
     restartPolicy: Never
     containers:
       - name: cuda-test
         image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
         command: ["nvidia-smi"]
         resources:
           limits:
             nvidia.com/gpu: 1
   EOF

   # Check results
   kubectl wait --for=condition=Completed pod/fips-gpu-test --timeout=120s
   kubectl logs fips-gpu-test

   # Cleanup
   kubectl delete pod fips-gpu-test
   ```

### Task 4: Configure FIPS-Compliant Container Runtime (25 min)

1. **Verify Container Toolkit FIPS Configuration**
   ```bash
   # Check toolkit pods
   kubectl get pods -n gpu-operator -l app=nvidia-container-toolkit-daemonset

   # Exec into toolkit pod
   TOOLKIT_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-container-toolkit-daemonset -o jsonpath='{.items[0].metadata.name}')

   kubectl exec -n gpu-operator $TOOLKIT_POD -- nvidia-ctk --version
   ```

2. **Test Container Runtime with FIPS Crypto**
   ```bash
   # Deploy test workload that uses cryptographic operations
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: fips-crypto-test
   spec:
     restartPolicy: Never
     containers:
       - name: crypto-test
         image: nvcr.io/nvidia/pytorch:24.09-py3
         command:
           - python3
           - -c
           - |
             import torch
             import hashlib

             # Test GPU availability
             print(f"CUDA available: {torch.cuda.is_available()}")
             print(f"GPU count: {torch.cuda.device_count()}")

             # Test FIPS-compliant crypto (SHA-256)
             data = b"FIPS compliance test"
             hash_sha256 = hashlib.sha256(data).hexdigest()
             print(f"SHA-256 hash: {hash_sha256}")

             # GPU tensor operations
             if torch.cuda.is_available():
                 x = torch.randn(1000, 1000, device='cuda')
                 y = torch.matmul(x, x.T)
                 print(f"GPU computation successful, result shape: {y.shape}")
         resources:
           limits:
             nvidia.com/gpu: 1
   EOF

   # Wait and check results
   kubectl wait --for=condition=Completed pod/fips-crypto-test --timeout=300s
   kubectl logs fips-crypto-test
   ```

3. **Verify FIPS Crypto Restrictions**
   ```bash
   # This should fail if FIPS is properly enabled (MD5 not allowed)
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: fips-md5-test
   spec:
     restartPolicy: Never
     containers:
       - name: md5-test
         image: python:3.11-slim
         command:
           - python3
           - -c
           - |
             import hashlib
             try:
                 # MD5 should be disabled in FIPS mode
                 hashlib.md5(b"test")
                 print("WARNING: MD5 is available - FIPS may not be active")
             except ValueError as e:
                 print(f"FIPS enforced: {e}")
   EOF

   kubectl wait --for=condition=Completed pod/fips-md5-test --timeout=60s
   kubectl logs fips-md5-test
   ```

### Task 5: DCGM Monitoring with FIPS (20 min)

1. **Verify DCGM Exporter**
   ```bash
   kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

   # Port forward to access metrics
   kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400 &

   # Fetch metrics
   curl -s http://localhost:9400/metrics | grep -E "DCGM_FI_DEV_GPU_TEMP|DCGM_FI_DEV_POWER_USAGE"
   ```

2. **Check GPU Health Metrics**
   ```bash
   # Get DCGM pod
   DCGM_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm -o jsonpath='{.items[0].metadata.name}')

   # Run DCGM diagnostics
   kubectl exec -n gpu-operator $DCGM_POD -- dcgmi discovery -l
   kubectl exec -n gpu-operator $DCGM_POD -- dcgmi health -g 0
   ```

3. **Create FIPS Compliance Report**
   ```bash
   # Generate compliance summary
   cat <<'EOF' > fips-compliance-check.sh
   #!/bin/bash
   echo "=== NVIDIA FIPS Compliance Report ==="
   echo "Date: $(date)"
   echo ""

   echo "=== Host FIPS Status ==="
   cat /proc/sys/crypto/fips_enabled

   echo ""
   echo "=== GPU Driver Version ==="
   nvidia-smi --query-gpu=driver_version --format=csv,noheader

   echo ""
   echo "=== CUDA Version ==="
   nvidia-smi --query-gpu=cuda_version --format=csv,noheader

   echo ""
   echo "=== GPU Operator Components ==="
   kubectl get pods -n gpu-operator -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IMAGE:.spec.containers[0].image

   echo ""
   echo "=== Crypto Modules ==="
   cat /proc/crypto | grep -E "^name|^driver" | head -20
   EOF

   chmod +x fips-compliance-check.sh
   ```

## Deliverables

- [ ] **Screenshot** of host FIPS mode enabled
- [ ] **GPU Operator deployment** with FIPS values file
- [ ] **nvidia-smi output** from FIPS-enabled cluster
- [ ] **Crypto test results** showing FIPS enforcement
- [ ] **FIPS compliance report** from check script

## Verification Checklist

- [ ] Host OS FIPS mode enabled
- [ ] GPU Operator deployed with FIPS configuration
- [ ] GPU driver pods running successfully
- [ ] Container toolkit operational
- [ ] DCGM monitoring active
- [ ] FIPS crypto restrictions verified

## Troubleshooting

### Driver Fails to Load in FIPS Mode

**Check kernel module signing:**
```bash
# Verify module signature requirements
cat /proc/sys/kernel/module_sig_enforce

# Check driver module
modinfo nvidia | grep sig
```

### Container Toolkit Errors

**Verify runtime configuration:**
```bash
# Check containerd config
cat /etc/containerd/config.toml | grep nvidia

# Restart containerd if needed
sudo systemctl restart containerd
```

### Crypto Operations Fail

**Check OpenSSL FIPS provider:**
```bash
# List available providers
openssl list -providers

# Test FIPS provider
openssl list -providers -provider fips
```

## Key Takeaways

1. **FIPS compliance requires OS-level enablement** before GPU operator deployment
2. **Use UBI-based images** for FIPS-validated container components
3. **DCGM and monitoring** work normally in FIPS mode
4. **Test crypto operations** to verify FIPS restrictions are enforced
5. **Document compliance** for audit purposes

## Next Lab

Proceed to [Lab 5.8 - Cluster Templates for AI Workloads](lab-5.8-cluster-templates.md)
