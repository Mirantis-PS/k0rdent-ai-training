# Lab 5.11 - FIPS Compliance for GPU Infrastructure

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Compliance & Templates | Recommended | 2 hours |

### Week 5 Learning Paths

```
FOUNDATION (Completed)                        COMPLIANCE & TEMPLATES
━━━━━━━━━━━━━━━━━━━━━━                       ━━━━━━━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5               YOU ARE HERE
     ➔ 5.6 ➔ 5.7 ➔ 5.8 ✓                        ↓
                                             [5.11] FIPS
                                                  ↓
                                              5.12 Cluster Templates
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.8 - Vector Database](lab-5.8-vector-database.md) | **Lab 5.11 - FIPS Compliance** | [Lab 5.12 - Cluster Templates](lab-5.12-cluster-templates.md) |

---

**Duration:** 2 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab (k0rdent-managed workload cluster)

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [k0rdent Context](#k0rdent-context)
- [Part 1: Understanding the FIPS Enforcement Boundary](#part-1-understanding-the-fips-enforcement-boundary)
- [Tasks](#tasks)
  - [Task 1: Access the k0rdent-Managed GPU Cluster](#task-1-access-the-k0rdent-managed-gpu-cluster-10-min)
  - [Task 2: Verify and Enable Host FIPS Mode](#task-2-verify-and-enable-host-fips-mode-25-min)
  - [Task 3: Deploy GPU Operator with FIPS-Compliant Images](#task-3-deploy-gpu-operator-with-fips-compliant-images-30-min)
  - [Task 4: Verify FIPS Enforcement in Containers](#task-4-verify-fips-enforcement-in-containers-25-min)
  - [Task 5: DCGM Monitoring in FIPS Environment](#task-5-dcgm-monitoring-in-fips-environment-15-min)
  - [Task 6: FIPS Compliance Audit](#task-6-fips-compliance-audit-15-min)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [Verification Checklist](#verification-checklist)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

## Objective

Deploy and verify FIPS-compliant GPU infrastructure on k0rdent-managed clusters. You will enable FIPS mode at the OS level, deploy the GPU Operator with FIPS-validated container images, and verify that the cryptographic enforcement boundary operates correctly across the stack.

## Prerequisites

- Completed Lab 5.1 (GPU Operator fundamentals)
- k0rdent management cluster with a GPU-enabled workload cluster provisioned via `ClusterDeployment`
- SSH access to GPU worker nodes

## k0rdent Context

The k0rdent catalog includes the `gpu-operator-25-10-0` ServiceTemplate for deploying the NVIDIA GPU Operator. For FIPS environments, the same ServiceTemplate is used with custom values that override default container images with UBI (Universal Base Image) variants containing FIPS-validated OpenSSL.

> **Key concept:** The GPU Operator itself does not have a "FIPS mode" toggle. FIPS compliance is achieved through a layered approach:
>
> | Layer | What Provides FIPS | Example |
> |-------|-------------------|---------|
> | **OS kernel** | FIPS-validated kernel crypto modules | `fips_enabled=1` at boot |
> | **Container images** | UBI images with FIPS-validated OpenSSL | `-ubi8` / `-ubi9` image tags |
> | **Application TLS** | FIPS-approved cipher suites for network ops | OpenSSL FIPS provider |
> | **GPU compute** | *Not applicable* - CUDA/NCCL are compute, not crypto | N/A |
>
> NVIDIA GPU drivers, CUDA libraries, and NCCL perform mathematical computation, not cryptographic operations. They do not appear in the [NIST CMVP](https://csrc.nist.gov/projects/cryptographic-module-validation-program) database and do not need FIPS validation.

### FIPS 140-2 vs FIPS 140-3

| Standard | Status | Notes |
|----------|--------|-------|
| FIPS 140-2 | Sunset September 2026 | Legacy, no new validations accepted |
| FIPS 140-3 | Current | ISO/IEC 19790:2012 aligned, required for new submissions |

Modern systems (RHEL 9, Ubuntu 22.04) validate against FIPS 140-3. This lab covers FIPS configuration that satisfies both standards.

## Part 1: Understanding the FIPS Enforcement Boundary

Before deploying, understand what FIPS actually protects in a GPU cluster:

```
┌─────────────────────────────────────────────────────────────────┐
│                    FIPS Enforcement Boundary                     │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  OS Kernel (FIPS-validated crypto modules)                │   │
│  │  - AES, SHA-256/384/512, RSA, ECDSA, HMAC               │   │
│  │  - MD5, DES, RC4 DISABLED                                │   │
│  └──────────────────┬───────────────────────────────────────┘   │
│                     │                                            │
│  ┌──────────────────▼───────────────────────────────────────┐   │
│  │  OpenSSL FIPS Provider (in UBI container images)          │   │
│  │  - TLS 1.2/1.3 with FIPS cipher suites                   │   │
│  │  - Certificate operations (X.509)                         │   │
│  │  - Key derivation (HKDF, PBKDF2)                         │   │
│  └──────────────────┬───────────────────────────────────────┘   │
│                     │                                            │
│  ┌──────────────────▼───────────────────────────────────────┐   │
│  │  Container Runtime (containerd)                           │   │
│  │  - Image pull over TLS (FIPS cipher suites)               │   │
│  │  - Registry authentication                                │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│                OUTSIDE FIPS Boundary (compute only)              │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  GPU Compute Stack                                        │   │
│  │  - NVIDIA Driver (kernel module for GPU hardware access)  │   │
│  │  - CUDA (parallel compute library)                        │   │
│  │  - cuDNN (deep learning primitives)                       │   │
│  │  - NCCL (multi-GPU collective communication)              │   │
│  │  - These perform MATH, not CRYPTOGRAPHY                   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Tasks

### Task 1: Access the k0rdent-Managed GPU Cluster (10 min)

1. **Extract kubeconfig from the management cluster**

   ```bash
   # On the k0rdent management cluster
   kubectl get secret gpu-fips-kubeconfig -n kcm-system \
     -o jsonpath='{.data.value}' | base64 -d > gpu-fips.kubeconfig

   export KUBECONFIG=gpu-fips.kubeconfig
   ```

2. **Verify cluster access and GPU nodes**

   ```bash
   kubectl get nodes -o wide

   # Confirm GPU nodes are present
   kubectl get nodes -l nvidia.com/gpu.present=true
   ```

> **Note:** If your workload cluster was provisioned with an Amazon Linux 2023 or RHEL-based AMI, FIPS can be enabled on the nodes. Ubuntu-based nodes require Ubuntu Pro.

### Task 2: Verify and Enable Host FIPS Mode (25 min)

FIPS must be enabled at the OS level **before** deploying the GPU Operator. This requires SSH access to worker nodes.

1. **SSH to a GPU worker node and check FIPS status**

   ```bash
   # Get node IP
   NODE_IP=$(kubectl get nodes -l nvidia.com/gpu.present=true \
     -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

   ssh ec2-user@${NODE_IP}

   # Check FIPS mode
   cat /proc/sys/crypto/fips_enabled
   # 1 = enabled, 0 = disabled
   ```

2. **Enable FIPS mode (if not already enabled)**

   **RHEL 8/9 / Amazon Linux 2023:**
   ```bash
   # RHEL/Rocky/Alma
   sudo fips-mode-setup --enable
   sudo reboot

   # After reboot, verify
   fips-mode-setup --check
   # Expected: FIPS mode is enabled.
   ```

   **Ubuntu 22.04 (requires Ubuntu Pro):**
   ```bash
   # Ubuntu Pro is required - free for up to 5 machines
   # Get a token from https://ubuntu.com/pro
   sudo pro attach <YOUR_UBUNTU_PRO_TOKEN>

   # Enable FIPS (140-3 validated modules)
   sudo pro enable fips-updates
   sudo reboot

   # After reboot, verify
   cat /proc/sys/crypto/fips_enabled
   # Expected: 1
   ```

   > **Important:** Ubuntu FIPS is only available through Ubuntu Pro (formerly Ubuntu Advantage). The `ua` command has been rebranded to `pro`. Standard Ubuntu does not include FIPS-validated crypto modules.

3. **Verify FIPS crypto enforcement**

   ```bash
   # List loaded FIPS-validated kernel crypto modules
   cat /proc/crypto | grep -A1 "^name" | grep -E "name|fips" | head -20

   # Verify OpenSSL recognizes FIPS mode
   openssl version
   # Should show OpenSSL 3.x with FIPS provider

   # Test: MD5 should be REJECTED in FIPS mode
   openssl md5 /dev/null
   # Expected error (OpenSSL 3.x):
   # Error setting digest
   # ...unsupported...Algorithm (MD5 : 100)...

   # Test: SHA-256 should WORK in FIPS mode
   openssl sha256 /dev/null
   # Expected: SHA2-256(/dev/null)= e3b0c44298fc...
   ```

4. **Verify kernel module signing (required for FIPS)**

   ```bash
   # FIPS mode typically enforces module signatures
   cat /proc/sys/kernel/module_sig_enforce
   # 1 = enforced (required for FIPS)

   # Check that NVIDIA driver module is signed
   modinfo nvidia 2>/dev/null | grep -E "^sig|^signer"
   ```

> **Repeat** steps 1-4 on each GPU worker node. All nodes must have FIPS enabled for cluster-wide compliance.

### Task 3: Deploy GPU Operator with FIPS-Compliant Images (30 min)

Deploy the GPU Operator using k0rdent's ServiceTemplate with UBI image overrides for FIPS compliance.

1. **Option A: Deploy via ClusterDeployment serviceSpec (recommended)**

   If the cluster has not yet been provisioned, include the GPU Operator in the ClusterDeployment:

   ```yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: ClusterDeployment
   metadata:
     name: gpu-fips
     namespace: kcm-system
   spec:
     template: aws-standalone-cp-0-2-3
     credential: aws-cluster-identity-cred
     config:
       region: us-east-1
       publicIP: true
       controlPlaneNumber: 1
       controlPlane:
         instanceType: t3.large
       workersNumber: 2
       worker:
         instanceType: g5.xlarge
       clusterLabels:
         k0rdent.mirantis.com/compliance: fips
         k0rdent.mirantis.com/workload-type: ai
     serviceSpec:
       services:
         - template: gpu-operator-25-10-0
           name: gpu-operator
           namespace: gpu-operator
           values: |
             operator:
               defaultRuntime: containerd
             toolkit:
               env:
                 - name: CONTAINERD_CONFIG
                   value: /etc/k0s/containerd.d/nvidia.toml
                 - name: CONTAINERD_SOCKET
                   value: /run/k0s/containerd.sock
                 - name: CONTAINERD_RUNTIME_CLASS
                   value: nvidia
             nfd:
               enabled: true
             gfd:
               enabled: true
       priority: 100
   ```

   > **Region note:** FIPS-validated AMIs and configurations are primarily tested in US regions (us-east-1, us-east-2, us-west-2). If deploying in other regions, verify that FIPS-validated AMIs are available.

2. **Option B: Deploy via MultiClusterService for existing clusters**

   If the cluster is already provisioned, deploy the GPU Operator via MultiClusterService:

   ```yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: gpu-operator-fips
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         k0rdent.mirantis.com/compliance: fips
     serviceSpec:
       services:
         - template: gpu-operator-25-10-0
           name: gpu-operator
           namespace: gpu-operator
           values: |
             operator:
               defaultRuntime: containerd
             toolkit:
               env:
                 - name: CONTAINERD_CONFIG
                   value: /etc/k0s/containerd.d/nvidia.toml
                 - name: CONTAINERD_SOCKET
                   value: /run/k0s/containerd.sock
                 - name: CONTAINERD_RUNTIME_CLASS
                   value: nvidia
             nfd:
               enabled: true
             gfd:
               enabled: true
   ```

   ```bash
   kubectl apply -f gpu-operator-fips-mcs.yaml
   ```

3. **Verify GPU Operator deployment**

   ```bash
   # Switch to workload cluster context
   export KUBECONFIG=gpu-fips.kubeconfig

   # Watch pods come up
   kubectl get pods -n gpu-operator -w

   # Wait for all pods to be ready (this may take 5-10 minutes)
   kubectl wait --for=condition=Ready pods --all -n gpu-operator --timeout=600s
   ```

4. **Verify GPU Operator component images**

   ```bash
   # List all images used by GPU Operator pods
   kubectl get pods -n gpu-operator -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'

   # Check for UBI-based images (FIPS-compliant base)
   kubectl get pods -n gpu-operator -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u
   ```

   > **Note:** The GPU Operator v25.10.0 ships UBI-based images by default for most components. The `-ubi8` and `-ubi9` suffixed images include Red Hat's FIPS-validated OpenSSL, ensuring that all TLS operations (image pulls, API server communication, metrics endpoints) use FIPS-approved algorithms.

### Task 4: Verify FIPS Enforcement in Containers (25 min)

Test that FIPS cryptographic restrictions are enforced inside containers running on the GPU cluster.

1. **Test GPU access with FIPS-compliant base image**

   ```yaml
   # Save as fips-gpu-test.yaml
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
   ```

   ```bash
   kubectl apply -f fips-gpu-test.yaml
   kubectl wait --for=condition=Completed pod/fips-gpu-test --timeout=120s
   kubectl logs fips-gpu-test
   ```

   Confirm `nvidia-smi` shows the GPU. This verifies the GPU driver functions on a FIPS-enabled kernel.

2. **Test FIPS crypto restrictions inside a container**

   ```yaml
   # Save as fips-crypto-test.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: fips-crypto-test
   spec:
     restartPolicy: Never
     containers:
       - name: crypto-test
         image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
         command:
           - /bin/bash
           - -c
           - |
             echo "=== FIPS Crypto Enforcement Test ==="
             echo ""

             # Check if host FIPS mode is visible in container
             echo "--- Kernel FIPS status ---"
             cat /proc/sys/crypto/fips_enabled

             echo ""
             echo "--- OpenSSL version ---"
             openssl version 2>/dev/null || echo "openssl not installed"

             echo ""
             echo "--- Test: SHA-256 (FIPS-approved, should PASS) ---"
             echo -n "test" | openssl sha256 2>&1 && echo "PASS: SHA-256 works" || echo "FAIL"

             echo ""
             echo "--- Test: MD5 (NOT FIPS-approved, should FAIL) ---"
             echo -n "test" | openssl md5 2>&1 && echo "WARNING: MD5 available (FIPS may not be enforced)" || echo "PASS: MD5 correctly rejected"

             echo ""
             echo "--- OpenSSL providers ---"
             openssl list -providers 2>/dev/null || echo "Cannot list providers"
   ```

   ```bash
   kubectl apply -f fips-crypto-test.yaml
   kubectl wait --for=condition=Completed pod/fips-crypto-test --timeout=120s
   kubectl logs fips-crypto-test
   ```

   **Expected output on a FIPS-enabled system:**
   ```
   === FIPS Crypto Enforcement Test ===

   --- Kernel FIPS status ---
   1

   --- OpenSSL version ---
   OpenSSL 3.0.7 1 Nov 2022 (Library: OpenSSL 3.0.7 1 Nov 2022)

   --- Test: SHA-256 (FIPS-approved, should PASS) ---
   SHA2-256(stdin)= 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
   PASS: SHA-256 works

   --- Test: MD5 (NOT FIPS-approved, should FAIL) ---
   Error setting digest
   ...unsupported...Algorithm (MD5 : 100)...
   PASS: MD5 correctly rejected
   ```

3. **Test Python FIPS enforcement with GPU compute**

   ```yaml
   # Save as fips-python-gpu-test.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: fips-python-gpu-test
   spec:
     restartPolicy: Never
     containers:
       - name: python-test
         image: nvcr.io/nvidia/pytorch:24.09-py3
         command:
           - python3
           - -c
           - |
             import hashlib
             import ssl
             import torch

             print("=== Python FIPS + GPU Verification ===\n")

             # 1. GPU compute works (outside FIPS boundary)
             print("--- GPU Compute ---")
             print(f"CUDA available: {torch.cuda.is_available()}")
             if torch.cuda.is_available():
                 print(f"GPU: {torch.cuda.get_device_name(0)}")
                 x = torch.randn(1000, 1000, device='cuda')
                 y = torch.matmul(x, x.T)
                 print(f"Matrix multiply result shape: {y.shape}")
                 print("GPU compute: PASS\n")

             # 2. FIPS-approved hash (should work)
             print("--- FIPS-Approved Crypto ---")
             sha256 = hashlib.sha256(b"FIPS compliance test")
             print(f"SHA-256: {sha256.hexdigest()}")
             print("SHA-256: PASS\n")

             # 3. Non-FIPS hash (should fail in FIPS mode)
             print("--- Non-FIPS Crypto (MD5) ---")
             try:
                 md5 = hashlib.md5(b"test")
                 digest = md5.hexdigest()
                 print(f"MD5: {digest}")
                 print("WARNING: MD5 available - FIPS may not be enforced")
             except ValueError as e:
                 print(f"MD5 correctly rejected: {e}")
                 print("FIPS enforcement: PASS\n")

             # 4. Note: Python 3.9+ allows non-security MD5
             print("--- Non-Security MD5 (usedforsecurity=False) ---")
             try:
                 md5_nonsec = hashlib.md5(b"checksum", usedforsecurity=False)
                 print(f"Non-security MD5: {md5_nonsec.hexdigest()}")
                 print("(This is allowed - used for checksums, not security)\n")
             except TypeError:
                 print("usedforsecurity parameter not supported\n")

             # 5. TLS configuration
             print("--- TLS Configuration ---")
             ctx = ssl.create_default_context()
             print(f"Protocol: {ctx.protocol}")
             print(f"Minimum TLS: {ctx.minimum_version}")
             print(f"OpenSSL: {ssl.OPENSSL_VERSION}")
         resources:
           limits:
             nvidia.com/gpu: 1
   ```

   ```bash
   kubectl apply -f fips-python-gpu-test.yaml
   kubectl wait --for=condition=Completed pod/fips-python-gpu-test --timeout=300s
   kubectl logs fips-python-gpu-test
   ```

   > **Key takeaway:** GPU tensor operations (`torch.matmul`) work normally in FIPS mode because CUDA is a compute library, not a cryptographic module. FIPS enforcement applies only to cryptographic operations (hashing, encryption, TLS, key derivation).

### Task 5: DCGM Monitoring in FIPS Environment (15 min)

Verify that GPU health monitoring operates correctly on FIPS-enabled nodes.

1. **Check DCGM Exporter pods**

   ```bash
   kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

   # Port-forward to access metrics
   kubectl port-forward -n gpu-operator svc/nvidia-dcgm-exporter 9400:9400 &

   # Fetch GPU metrics
   curl -s http://localhost:9400/metrics | grep -E "DCGM_FI_DEV_GPU_TEMP|DCGM_FI_DEV_POWER_USAGE|DCGM_FI_DEV_GPU_UTIL"
   ```

2. **Run DCGM diagnostics**

   ```bash
   DCGM_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm \
     -o jsonpath='{.items[0].metadata.name}')

   # Discover GPUs
   kubectl exec -n gpu-operator $DCGM_POD -- dcgmi discovery -l

   # Health check
   kubectl exec -n gpu-operator $DCGM_POD -- dcgmi health -g 0

   # Run diagnostic (Level 1 = quick)
   kubectl exec -n gpu-operator $DCGM_POD -- dcgmi diag -r 1
   ```

3. **Verify DCGM metrics endpoint uses TLS with FIPS-approved ciphers (if configured)**

   ```bash
   # If DCGM exporter is configured with TLS, verify cipher suite
   # This checks that the metrics endpoint uses FIPS-approved ciphers
   kubectl exec -n gpu-operator $DCGM_POD -- \
     openssl s_client -connect localhost:9400 -tls1_2 2>/dev/null | \
     grep -E "Cipher|Protocol" || echo "TLS not configured on metrics endpoint (plaintext)"
   ```

   > **Note:** By default, DCGM exporter serves metrics over plaintext HTTP. In production FIPS environments, configure TLS on the metrics endpoint using FIPS-approved cipher suites (e.g., `TLS_AES_256_GCM_SHA384`).

### Task 6: FIPS Compliance Audit (15 min)

Create an automated compliance report suitable for audit documentation.

1. **Deploy a compliance audit Job**

   ```yaml
   # Save as fips-audit-job.yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: fips-compliance-audit
   spec:
     template:
       spec:
         restartPolicy: Never
         hostPID: true
         nodeSelector:
           nvidia.com/gpu.present: "true"
         containers:
           - name: auditor
             image: nvcr.io/nvidia/cuda:12.6.0-base-ubi9
             command:
               - /bin/bash
               - -c
               - |
                 echo "=========================================="
                 echo "  FIPS Compliance Audit Report"
                 echo "  Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
                 echo "  Hostname: $(hostname)"
                 echo "=========================================="
                 echo ""

                 # 1. Kernel FIPS status
                 echo "1. KERNEL FIPS MODE"
                 FIPS=$(cat /proc/sys/crypto/fips_enabled)
                 if [ "$FIPS" = "1" ]; then
                   echo "   Status: ENABLED (COMPLIANT)"
                 else
                   echo "   Status: DISABLED (NON-COMPLIANT)"
                 fi
                 echo ""

                 # 2. Kernel module signature enforcement
                 echo "2. KERNEL MODULE SIGNING"
                 SIG=$(cat /proc/sys/kernel/module_sig_enforce 2>/dev/null || echo "N/A")
                 echo "   module_sig_enforce: $SIG"
                 echo ""

                 # 3. OpenSSL FIPS provider
                 echo "3. OPENSSL FIPS PROVIDER"
                 openssl version 2>/dev/null || echo "   openssl not available"
                 openssl list -providers 2>/dev/null || echo "   Cannot list providers"
                 echo ""

                 # 4. Crypto algorithm enforcement
                 echo "4. CRYPTO ALGORITHM ENFORCEMENT"
                 echo -n "   SHA-256: "
                 echo -n "test" | openssl sha256 >/dev/null 2>&1 && echo "AVAILABLE (expected)" || echo "BLOCKED (unexpected)"
                 echo -n "   SHA-512: "
                 echo -n "test" | openssl sha512 >/dev/null 2>&1 && echo "AVAILABLE (expected)" || echo "BLOCKED (unexpected)"
                 echo -n "   MD5:     "
                 echo -n "test" | openssl md5 >/dev/null 2>&1 && echo "AVAILABLE (FIPS violation!)" || echo "BLOCKED (expected)"
                 echo ""

                 # 5. GPU driver status
                 echo "5. GPU DRIVER STATUS"
                 nvidia-smi --query-gpu=driver_version,gpu_name,gpu_uuid --format=csv 2>/dev/null || echo "   nvidia-smi not available in container"
                 echo ""

                 # 6. Loaded crypto modules
                 echo "6. FIPS-VALIDATED KERNEL CRYPTO MODULES (sample)"
                 cat /proc/crypto | grep -B1 "fips.*: yes" | grep "^name" | head -10
                 echo ""

                 echo "=========================================="
                 echo "  Audit complete"
                 echo "=========================================="
             securityContext:
               privileged: true
   ```

   ```bash
   kubectl apply -f fips-audit-job.yaml
   kubectl wait --for=condition=Complete job/fips-compliance-audit --timeout=120s
   kubectl logs job/fips-compliance-audit
   ```

2. **Save the audit report**

   ```bash
   # Save for compliance records
   kubectl logs job/fips-compliance-audit > fips-audit-$(date +%Y%m%d).txt
   echo "Audit report saved to fips-audit-$(date +%Y%m%d).txt"
   ```

## Cleanup

```bash
# Delete test pods and jobs
kubectl delete pod fips-gpu-test fips-crypto-test fips-python-gpu-test --ignore-not-found
kubectl delete job fips-compliance-audit --ignore-not-found

# Stop port-forward
kill %1 2>/dev/null
```

> **Note:** Do not remove the GPU Operator or disable FIPS mode if the cluster is intended for production compliance workloads.

## Troubleshooting

### GPU Driver Fails to Load on FIPS-Enabled Kernel

**Symptom:** `nvidia-driver-daemonset` pods crash with signature errors.

```bash
# Check driver pod logs
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=50

# On the node, check dmesg for module signature issues
ssh ec2-user@${NODE_IP} "sudo dmesg | grep -i 'module.*signature\|nvidia'"
```

**Cause:** FIPS-enabled kernels may enforce module signatures. The NVIDIA driver kernel module must be signed.

**Fix:** Use pre-compiled driver containers that match the node's kernel version. The GPU Operator's `driver.usePrecompiled=true` option uses drivers pre-signed for the target kernel.

### Containerd Configuration on k0s Nodes

**Symptom:** GPU pods fail to start with "runtime not found" errors.

```bash
# k0s uses non-standard containerd paths
# Verify the nvidia runtime is configured
ssh ec2-user@${NODE_IP} "cat /etc/k0s/containerd.d/nvidia.toml"
```

**Expected content:**
```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  privileged_without_host_devices = false
  runtime_type = "io.containerd.runc.v2"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
  BinaryName = "/usr/bin/nvidia-container-runtime"
```

If missing, verify the GPU Operator toolkit env vars include the k0s containerd paths shown in Task 3.

### OpenSSL Reports FIPS but MD5 Still Works

**Symptom:** `openssl md5` succeeds even though `/proc/sys/crypto/fips_enabled` shows 1.

**Cause:** The container's OpenSSL may not have the FIPS provider loaded. UBI images include it by default, but custom images may not.

```bash
# Inside the container, check if FIPS provider is active
openssl list -providers
# Should show:
#   fips
#     name: OpenSSL FIPS Provider
#     status: active
```

**Fix:** Use UBI-based container images (e.g., `*-ubi8`, `*-ubi9` tags) or configure OpenSSL to load the FIPS provider in your custom images.

## Verification Checklist

- [ ] Host OS FIPS mode enabled on all GPU nodes (`/proc/sys/crypto/fips_enabled` = 1)
- [ ] GPU Operator deployed via k0rdent ServiceTemplate with k0s containerd paths
- [ ] All GPU Operator pods running successfully
- [ ] GPU compute functional (`nvidia-smi` works from pod)
- [ ] FIPS-approved algorithms work (SHA-256, SHA-512)
- [ ] Non-FIPS algorithms blocked (MD5 rejected by OpenSSL)
- [ ] DCGM monitoring active and collecting metrics
- [ ] FIPS compliance audit report generated and saved

## Key Takeaways

1. **FIPS compliance is a layered OS + container concern**, not a GPU driver feature. GPU compute (CUDA, NCCL, cuDNN) is math, not cryptography.
2. **FIPS must be enabled at the OS level first** (`fips-mode-setup --enable` on RHEL, `pro enable fips-updates` on Ubuntu Pro). This cannot be done from Kubernetes.
3. **UBI-based container images** provide FIPS-validated OpenSSL for all in-container TLS and cryptographic operations.
4. **k0rdent deploys GPU Operator via ServiceTemplate** with values overrides for k0s containerd paths. The same ServiceTemplate works for FIPS and non-FIPS clusters.
5. **Audit regularly** - generate FIPS compliance reports for each cluster and store them for audit purposes.
6. **FIPS 140-3 is current** - new systems validate against 140-3 (superseding 140-2 which sunsets September 2026).

## Next Lab

Proceed to [Lab 5.12 - Cluster Templates for AI Workloads](lab-5.12-cluster-templates.md)
