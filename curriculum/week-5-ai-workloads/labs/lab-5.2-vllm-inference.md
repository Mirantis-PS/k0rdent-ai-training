# Lab 5.2 - Deploy vLLM Inference Service

**Duration:** 2.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Objective

Deploy a production-ready LLM inference service using vLLM on Kubernetes with proper resource management and monitoring.

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler deployed)
- Kubernetes cluster with GPU nodes
- At least 1 GPU with 24GB+ VRAM (A100 recommended)
- Hugging Face account (for model access)

## Lab Environment

**Cluster Requirements:**
- 1+ GPU nodes with NVIDIA A100 or equivalent
- GPU Operator installed
- Network access to Hugging Face

**Model:** Llama-2-7B-chat (or Mistral-7B as alternative)

## Tasks

### Task 1: Prepare Model Access (15 min)

1. **Create Hugging Face Token Secret**
   ```bash
   # Get token from https://huggingface.co/settings/tokens
   # Accept Llama-2 license at https://huggingface.co/meta-llama/Llama-2-7b-chat-hf

   kubectl create namespace vllm-inference

   kubectl create secret generic hf-token \
     --from-literal=token=<your-hf-token> \
     -n vllm-inference
   ```

2. **Create Model Cache PVC**
   ```yaml
   # Save as model-cache-pvc.yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: model-cache
     namespace: vllm-inference
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 50Gi
     storageClassName: standard  # Adjust for your cluster
   ```

   ```bash
   kubectl apply -f model-cache-pvc.yaml
   ```

### Task 2: Deploy vLLM Server (45 min)

1. **Create vLLM Deployment**
   ```yaml
   # Save as vllm-deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: vllm-llama2
     namespace: vllm-inference
     labels:
       app: vllm-llama2
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: vllm-llama2
     template:
       metadata:
         labels:
           app: vllm-llama2
       spec:
         containers:
           - name: vllm
             image: vllm/vllm-openai:v0.11.2
             args:
               - --model
               - meta-llama/Llama-2-7b-chat-hf
               - --tensor-parallel-size
               - "1"
               - --max-model-len
               - "4096"
               - --gpu-memory-utilization
               - "0.9"
               - --host
               - "0.0.0.0"
               - --port
               - "8000"
             ports:
               - containerPort: 8000
                 name: http
             env:
               - name: HUGGING_FACE_HUB_TOKEN
                 valueFrom:
                   secretKeyRef:
                     name: hf-token
                     key: token
               - name: TRANSFORMERS_CACHE
                 value: /root/.cache/huggingface
             resources:
               limits:
                 nvidia.com/gpu: 1
               requests:
                 nvidia.com/gpu: 1
                 memory: 32Gi
                 cpu: "4"
             volumeMounts:
               - name: model-cache
                 mountPath: /root/.cache/huggingface
               - name: shm
                 mountPath: /dev/shm
             livenessProbe:
               httpGet:
                 path: /health
                 port: 8000
               initialDelaySeconds: 300
               periodSeconds: 30
               failureThreshold: 10
             readinessProbe:
               httpGet:
                 path: /health
                 port: 8000
               initialDelaySeconds: 60
               periodSeconds: 10
               failureThreshold: 30
         volumes:
           - name: model-cache
             persistentVolumeClaim:
               claimName: model-cache
           - name: shm
             emptyDir:
               medium: Memory
               sizeLimit: 16Gi
         tolerations:
           - key: nvidia.com/gpu
             operator: Exists
             effect: NoSchedule
   ```

2. **Apply Deployment**
   ```bash
   kubectl apply -f vllm-deployment.yaml

   # Watch deployment progress
   kubectl get pods -n vllm-inference -w

   # Check logs for model loading progress
   kubectl logs -f deployment/vllm-llama2 -n vllm-inference
   ```

3. **Expected Log Output**
   ```
   INFO:     Started server process [1]
   INFO:     Waiting for application startup.
   INFO:     Loading model meta-llama/Llama-2-7b-chat-hf...
   INFO:     Model loaded in 45.23 seconds.
   INFO:     Application startup complete.
   INFO:     Uvicorn running on http://0.0.0.0:8000
   ```

### Task 3: Create Service and Ingress (20 min)

1. **Create ClusterIP Service**
   ```yaml
   # Save as vllm-service.yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: vllm-llama2
     namespace: vllm-inference
     labels:
       app: vllm-llama2
   spec:
     type: ClusterIP
     ports:
       - port: 8000
         targetPort: 8000
         protocol: TCP
         name: http
     selector:
       app: vllm-llama2
   ```

2. **Create Ingress (Optional)**
   ```yaml
   # Save as vllm-ingress.yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: vllm-llama2
     namespace: vllm-inference
     annotations:
       nginx.ingress.kubernetes.io/proxy-body-size: "100m"
       nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
   spec:
     ingressClassName: nginx
     rules:
       - host: llama2.example.com
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: vllm-llama2
                   port:
                     number: 8000
   ```

3. **Apply Service**
   ```bash
   kubectl apply -f vllm-service.yaml
   # kubectl apply -f vllm-ingress.yaml  # If using ingress
   ```

### Task 4: Test Inference Endpoint (30 min)

1. **Port Forward for Testing**
   ```bash
   kubectl port-forward svc/vllm-llama2 8000:8000 -n vllm-inference &
   ```

2. **Test Health Endpoint**
   ```bash
   curl http://localhost:8000/health
   # Expected: {"status":"ok"}
   ```

3. **List Available Models**
   ```bash
   curl http://localhost:8000/v1/models | jq .

   # Expected response:
   # {
   #   "object": "list",
   #   "data": [
   #     {
   #       "id": "meta-llama/Llama-2-7b-chat-hf",
   #       "object": "model",
   #       ...
   #     }
   #   ]
   # }
   ```

4. **Test Chat Completion**
   ```bash
   curl http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "meta-llama/Llama-2-7b-chat-hf",
       "messages": [
         {"role": "system", "content": "You are a helpful assistant."},
         {"role": "user", "content": "What is Kubernetes?"}
       ],
       "max_tokens": 200,
       "temperature": 0.7
     }' | jq .
   ```

5. **Test Streaming Response**
   ```bash
   curl http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "meta-llama/Llama-2-7b-chat-hf",
       "messages": [
         {"role": "user", "content": "Write a haiku about containers"}
       ],
       "stream": true
     }'
   ```

6. **Benchmark with Multiple Requests**
   ```bash
   # Simple load test
   for i in {1..10}; do
     time curl -s http://localhost:8000/v1/chat/completions \
       -H "Content-Type: application/json" \
       -d '{
         "model": "meta-llama/Llama-2-7b-chat-hf",
         "messages": [{"role": "user", "content": "Hello!"}],
         "max_tokens": 50
       }' > /dev/null
   done
   ```

### Task 5: Monitor GPU Utilization (20 min)

1. **Watch GPU Usage**
   ```bash
   # In a separate terminal, exec into the pod
   kubectl exec -it deployment/vllm-llama2 -n vllm-inference -- nvidia-smi -l 1
   ```

2. **Check Memory Usage**
   ```bash
   kubectl exec -it deployment/vllm-llama2 -n vllm-inference -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv
   ```

3. **View vLLM Metrics**
   ```bash
   curl http://localhost:8000/metrics

   # Key metrics to observe:
   # - vllm:num_requests_running
   # - vllm:num_requests_waiting
   # - vllm:gpu_cache_usage_perc
   # - vllm:cpu_cache_usage_perc
   ```

4. **Create Prometheus ServiceMonitor (Optional)**
   ```yaml
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: vllm-llama2
     namespace: vllm-inference
   spec:
     selector:
       matchLabels:
         app: vllm-llama2
     endpoints:
       - port: http
         path: /metrics
         interval: 30s
   ```

### Task 6: Configure Horizontal Scaling (20 min)

1. **Create HPA (if multiple GPUs available)**
   ```yaml
   # Save as vllm-hpa.yaml
   apiVersion: autoscaling/v2
   kind: HorizontalPodAutoscaler
   metadata:
     name: vllm-llama2
     namespace: vllm-inference
   spec:
     scaleTargetRef:
       apiVersion: apps/v1
       kind: Deployment
       name: vllm-llama2
     minReplicas: 1
     maxReplicas: 4
     metrics:
       - type: Pods
         pods:
           metric:
             name: vllm_num_requests_waiting
           target:
             type: AverageValue
             averageValue: "10"
   ```

2. **Alternative: Manual Scaling**
   ```bash
   # Scale to 2 replicas (requires 2 GPUs)
   kubectl scale deployment vllm-llama2 --replicas=2 -n vllm-inference
   ```

## Deliverables

- [ ] **Screenshot** of successful chat completion response
- [ ] **GPU utilization screenshot** during inference
- [ ] **Metrics output** from `/metrics` endpoint
- [ ] **Deployment YAML** with your configuration notes
- [ ] **Performance results** from benchmark test

## Verification Checklist

- [ ] vLLM pod running and healthy
- [ ] Model loaded successfully
- [ ] Health endpoint responding
- [ ] Chat completions working
- [ ] Streaming responses working
- [ ] GPU utilization visible
- [ ] Metrics endpoint accessible

## Troubleshooting

### Pod Stuck in Pending

**Check GPU availability:**
```bash
kubectl describe nodes | grep -A5 "Allocatable:"
kubectl get pods -n vllm-inference -o wide
```

**Check events:**
```bash
kubectl describe pod -l app=vllm-llama2 -n vllm-inference
```

### Model Loading Fails

**Check Hugging Face token:**
```bash
kubectl logs deployment/vllm-llama2 -n vllm-inference | grep -i error
```

**Common errors:**
- "401 Unauthorized" - Token invalid or missing
- "403 Forbidden" - Need to accept model license on HF
- "Out of memory" - Reduce `--gpu-memory-utilization` or use smaller model

### OOM (Out of Memory)

**Reduce memory usage:**
```bash
# In deployment args:
- --gpu-memory-utilization
- "0.8"  # Reduce from 0.9
- --max-model-len
- "2048"  # Reduce context length
```

### Slow Inference

**Check if model is on GPU:**
```bash
kubectl exec deployment/vllm-llama2 -n vllm-inference -- nvidia-smi
# GPU utilization should spike during inference
```

**Verify tensor parallelism:**
```bash
# For multi-GPU setup, increase tensor-parallel-size
- --tensor-parallel-size
- "2"  # Use 2 GPUs
```

## Key Takeaways

1. **vLLM provides OpenAI-compatible API** making integration easy
2. **Model caching with PVC** speeds up subsequent deployments
3. **GPU memory utilization** should be tuned based on model size
4. **Shared memory (shm)** is required for efficient tensor operations
5. **Health/readiness probes** must account for model loading time
6. **Always pin vLLM versions** in production (current: v0.11.2)
7. **vLLM V1 architecture** (v0.11+) provides significant performance improvements

## Next Lab

Proceed to [Lab 5.3 - Vector Database Deployment](lab-5.3-vector-db.md)
