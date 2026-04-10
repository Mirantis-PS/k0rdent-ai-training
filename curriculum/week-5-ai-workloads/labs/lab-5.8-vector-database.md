# Lab 5.8 - Vector Database Deployment

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| Foundation | Required | 2 hours |

### Week 5 Learning Paths

```
FOUNDATION (Required)                                    CHOOSE YOUR PATH
━━━━━━━━━━━━━━━━━━━━                                    ━━━━━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5 ➔ 5.6 ➔ 5.7 ➔ [5.8]  ──►  ML Platforms (5.9-5.10)
                                               ↑           Compliance (5.11-5.12)
                                          YOU ARE HERE      Advanced (5.13-5.16)
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.7 - Jupyter Notebooks](lab-5.7-jupyter-notebooks.md) | **Lab 5.8 - Vector Database** | [Choose Your Path](#next-lab) |

---

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [Background](#background)
- [Tasks](#tasks)
  - [Task 1: Prepare Storage](#task-1-prepare-storage-15-min)
  - [Task 2: Deploy Milvus](#task-2-deploy-milvus-45-min)
  - [Task 3: Configure Authentication](#task-3-configure-authentication-15-min)
  - [Task 4: Create Collection and Load Data](#task-4-create-collection-and-load-data-30-min)
  - [Task 5: Test Similarity Search](#task-5-test-similarity-search-20-min)
  - [Task 6: Access Attu Web UI](#task-6-access-attu-web-ui-10-min)
  - [Task 7: Expose Service (Optional)](#task-7-expose-service-optional---10-min)
- [Troubleshooting](#troubleshooting)
- [Verification Checklist](#verification-checklist)

---

**Duration:** 2 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab (GPU optional but recommended for embedding generation)

## Objective

Deploy a production-ready vector database for AI applications, enabling efficient similarity search for RAG (Retrieval-Augmented Generation) pipelines, semantic search, and recommendation systems.

## Prerequisites

- Completed Lab 5.2 (vLLM Inference Service)
- Kubernetes cluster with persistent storage
- Basic understanding of embeddings and vector search

## Background

### What is a Vector Database?

Vector databases store and query high-dimensional embeddings - numerical representations of text, images, or other data. They enable:

- **Semantic Search**: Find content by meaning, not just keywords
- **RAG Pipelines**: Retrieve relevant context for LLM prompts
- **Recommendation Systems**: Find similar items or content
- **Image Search**: Find visually similar images

### Vector Database Options

| Database | Use Case | Deployment | License |
|----------|----------|------------|---------|
| **Milvus** | Production-scale, distributed | Helm/Operator | Apache 2.0 |
| **Weaviate** | Hybrid search, ML-native | Helm | BSD-3 |
| **Qdrant** | High performance, Rust-based | Helm | Apache 2.0 |
| **Chroma** | Development, embedded | Docker | Apache 2.0 |
| **pgvector** | PostgreSQL extension | Existing Postgres | PostgreSQL |

This lab deploys **Milvus** as a production-grade distributed solution.

## Lab Environment

**Cluster Requirements:**
- 3 nodes minimum (for distributed deployment)
- 8GB RAM per node minimum
- Persistent volume provisioner (local-path or cloud CSI)
- Optional: GPU node for embedding generation

## Tasks

### Task 1: Prepare Storage (15 min)

1. **Verify Storage Class**
   ```bash
   kubectl get storageclass
   ```

   The GPU cluster from Lab 5.1 includes `ebs-csi-default-sc` as the default StorageClass. If you see it listed with `(default)`, skip to the next step. If no default exists:

   ```bash
   # Only if no default StorageClass exists:
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
   kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   ```

2. **Create Namespace**
   ```bash
   kubectl create namespace vector-db
   ```

### Task 2: Deploy Milvus (45 min)

1. **Add Milvus Helm Repository**
   ```bash
   helm repo add milvus https://zilliztech.github.io/milvus-helm/
   helm repo update
   ```

2. **Create Milvus Configuration**

   > **Architecture Note (Milvus v2.6.x — forward-looking):** Milvus v2.6 plans
   > to unify four separate coordinators (root, data, query, index) into a single
   > **MixCoord** process, merge IndexNode into DataNode, and introduce
   > **StreamingNode** as a GA component. The recommended WAL backend will be
   > **Woodpecker** (replacing Pulsar). **Note:** The current stable Helm chart
   > (v4.2.x) deploys Milvus v2.5.x, which still uses separate coordinator pods
   > and Pulsar/MinIO for WAL. The v2.6 features (Woodpecker, MixCoord,
   > StreamingNode) are shown here for reference but may not yet be available in
   > the chart version you install. Adjust the values file accordingly if your
   > chart version does not support these keys.

   ```yaml
   # Save as milvus-values.yaml
   cluster:
     enabled: true

   # Enable authentication (Milvus defaults to OFF)
   extraConfigFiles:
     user.yaml: |
       common:
         security:
           authorizationEnabled: true

   etcd:
     replicaCount: 3
     persistence:
       enabled: true
       size: 10Gi

   minio:
     mode: distributed
     replicas: 4
     persistence:
       enabled: true
       size: 50Gi

   # Woodpecker WAL (recommended for v2.6+, replaces Pulsar)
   woodpecker:
     enabled: true

   # Disable legacy Pulsar (no longer needed with Woodpecker)
   pulsar:
     enabled: false
   pulsarv3:
     enabled: false

   # MixCoord replaces separate rootcoord, querycoord, datacoord, indexcoord
   mixCoordinator:
     replicas: 1
     resources:
       requests:
         cpu: "0.5"
         memory: 2Gi
       limits:
         cpu: "2"
         memory: 8Gi

   # StreamingNode (new in v2.6, handles real-time data ingestion)
   streamingNode:
     replicas: 1
     resources:
       requests:
         cpu: "0.5"
         memory: 2Gi
       limits:
         cpu: "2"
         memory: 8Gi

   queryNode:
     replicas: 2
     resources:
       requests:
         cpu: "0.5"
         memory: 2Gi
       limits:
         cpu: "2"
         memory: 8Gi

   # DataNode now includes index building (no separate indexNode in v2.6)
   dataNode:
     replicas: 1
     resources:
       requests:
         cpu: "0.5"
         memory: 2Gi
       limits:
         cpu: "2"
         memory: 8Gi

   proxy:
     replicas: 1
     resources:
       requests:
         cpu: "0.5"
         memory: 1Gi
       limits:
         cpu: "2"
         memory: 4Gi

   standalone:
     enabled: false

   attu:
     enabled: true
     service:
       type: ClusterIP

   metrics:
     enabled: true
   ```

3. **Deploy Milvus via k0rdent ServiceTemplate**

   The k0rdent catalog includes `milvus-5-0-1` (Milvus v2.6.x). Deploy it
   using a `MultiClusterService` or `ClusterDeployment` service spec, consistent
   with the patterns from Labs 5.1 and 5.2:

   ```yaml
   # Save as milvus-service.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: milvus
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         workload-type: ai-inference
     serviceSpec:
       services:
         - template: milvus-5-0-1
           name: milvus
           namespace: vector-db
           values: |
             cluster:
               enabled: true
             standalone:
               enabled: false
             extraConfigFiles:
               user.yaml: |
                 common:
                   security:
                     authorizationEnabled: true
             etcd:
               replicaCount: 3
               persistence:
                 enabled: true
                 size: 10Gi
             minio:
               mode: distributed
               replicas: 4
               persistence:
                 enabled: true
                 size: 50Gi
             pulsar:
               enabled: false
             queryNode:
               replicas: 2
               resources:
                 requests:
                   cpu: "0.5"
                   memory: 2Gi
                 limits:
                   cpu: "2"
                   memory: 8Gi
             dataNode:
               replicas: 1
               resources:
                 requests:
                   cpu: "0.5"
                   memory: 2Gi
                 limits:
                   cpu: "2"
                   memory: 8Gi
             proxy:
               replicas: 1
               resources:
                 requests:
                   cpu: "0.5"
                   memory: 1Gi
                 limits:
                   cpu: "2"
                   memory: 4Gi
             attu:
               enabled: true
               service:
                 type: ClusterIP
             metrics:
               enabled: true
   ```

   ```bash
   kubectl apply -f milvus-service.yaml
   ```

   > **Alternative (direct Helm):** If deploying outside k0rdent management,
   > you can use Helm directly. This bypasses fleet management but works for
   > single-cluster testing:
   > ```bash
   > helm repo add milvus https://zilliztech.github.io/milvus-helm/
   > helm repo update
   > helm install milvus milvus/milvus \
   >   --namespace vector-db \
   >   --values milvus-values.yaml \
   >   --version 4.2.8 \
   >   --wait --timeout 15m
   > ```
   > Pin `--version` to a known stable chart release. Run `helm search repo
   > milvus/milvus --versions` to find the latest available version.
   >
   > **Note:** The Helm chart creates services automatically. Verify with
   > `kubectl get svc -n vector-db | grep milvus` — you need `milvus` (proxy)
   > on port 19530 for the port-forward commands in Task 3.

4. **Watch Deployment Progress**
   ```bash
   kubectl get pods -n vector-db -w

   # This will take several minutes as all components start
   ```

5. **Verify Deployment**
   ```bash
   # All pods should be Running
   kubectl get pods -n vector-db

   # Check Milvus service
   kubectl get svc -n vector-db | grep milvus
   ```

6. **Expected Pod List**

   > **Note:** Pod names vary by Milvus version. The list below shows the v2.6.x
   > target architecture with MixCoord and Woodpecker. If you are running
   > Milvus v2.5.x (the current stable Helm chart default), you will instead see
   > separate coordinator pods: `milvus-rootcoord-*`, `milvus-querycoord-*`,
   > `milvus-datacoord-*`, `milvus-indexcoord-*`, and an `milvus-indexnode-*`
   > pod. You will also see Pulsar-related pods (broker, bookie, zookeeper)
   > instead of the Woodpecker components. The etcd, minio, proxy, querynode,
   > datanode, and attu pods appear in both versions.

   ```
   NAME                                      READY   STATUS    RESTARTS   AGE
   milvus-mixcoord-xxx                       1/1     Running   0          5m
   milvus-datanode-xxx                       1/1     Running   0          5m
   milvus-querynode-xxx                      1/1     Running   0          5m
   milvus-querynode-yyy                      1/1     Running   0          5m
   milvus-streaming-node-xxx                 1/1     Running   0          5m
   milvus-proxy-xxx                          1/1     Running   0          5m
   milvus-etcd-0                             1/1     Running   0          5m
   milvus-etcd-1                             1/1     Running   0          5m
   milvus-etcd-2                             1/1     Running   0          5m
   milvus-minio-0                            1/1     Running   0          5m
   milvus-minio-1                            1/1     Running   0          5m
   milvus-minio-2                            1/1     Running   0          5m
   milvus-minio-3                            1/1     Running   0          5m
   milvus-attu-xxx                           1/1     Running   0          5m
   ```

### Task 3: Configure Authentication (15 min)

1. **Create Milvus User**
   ```bash
   # Port forward to Milvus proxy
   kubectl port-forward svc/milvus -n vector-db 19530:19530 &

   # Install pymilvus client
   pip install "pymilvus>=2.5.0"
   # Check https://pypi.org/project/pymilvus/ for the latest compatible version
   ```

2. **Create Authentication Script**
   ```python
   # Save as setup_auth.py
   from pymilvus import connections, utility, Role

   # When authorizationEnabled is true, Milvus requires credentials even for initial setup.
   # The default root credentials are root/Milvus.
   connections.connect(
       alias="default",
       host="localhost",
       port=19530,
       user="root",
       password="Milvus"
   )

   # Create new user
   utility.create_user(
       user="mlops",
       password="SecurePassword123!"
   )

   # Grant admin role using the Role ORM API
   # Note: utility.grant_role() does not exist in PyMilvus ORM
   role = Role("admin")
   role.add_user("mlops")

   print("User 'mlops' created and granted admin role")
   connections.disconnect("default")
   ```

   ```bash
   python setup_auth.py
   ```

3. **Store Credentials as Secret**
   ```bash
   kubectl create secret generic milvus-credentials \
     --from-literal=username=mlops \
     --from-literal=password='SecurePassword123!' \
     -n vector-db
   ```

### Task 4: Create Collection and Load Data (30 min)

1. **Create Test Data Script**
   ```python
   # Save as load_data.py
   from pymilvus import (
       connections, Collection, FieldSchema,
       CollectionSchema, DataType, utility
   )
   import numpy as np

   # Connect with auth
   connections.connect(
       alias="default",
       host="localhost",
       port=19530,
       user="mlops",
       password="SecurePassword123!"
   )

   # Define collection schema
   collection_name = "documents"

   # Check if collection exists
   if utility.has_collection(collection_name):
       utility.drop_collection(collection_name)

   # Create schema
   fields = [
       FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
       FieldSchema(name="document_id", dtype=DataType.VARCHAR, max_length=256),
       FieldSchema(name="text", dtype=DataType.VARCHAR, max_length=65535),
       FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=384)  # Using all-MiniLM-L6-v2
   ]

   schema = CollectionSchema(
       fields=fields,
       description="Document embeddings for RAG"
   )

   # Create collection
   collection = Collection(
       name=collection_name,
       schema=schema
   )

   print(f"Collection '{collection_name}' created")

   # Create IVF_FLAT index for similarity search
   index_params = {
       "metric_type": "COSINE",
       "index_type": "IVF_FLAT",
       "params": {"nlist": 128}
   }

   collection.create_index(
       field_name="embedding",
       index_params=index_params
   )

   print("Index created")

   # Generate sample data
   sample_docs = [
       "Kubernetes is an open-source container orchestration platform.",
       "Docker containers package applications with their dependencies.",
       "NVIDIA GPUs accelerate machine learning training and inference.",
       "Vector databases enable semantic search over embeddings.",
       "RAG combines retrieval with language model generation.",
       "MLOps practices help deploy ML models to production.",
       "Distributed training scales model training across multiple GPUs.",
       "Model serving infrastructure handles inference requests.",
       "Prometheus and Grafana provide monitoring for ML systems.",
       "Infrastructure as Code manages cloud resources declaratively."
   ]

   # Generate fake embeddings (in production, use a real embedding model)
   # Using random vectors for demo - dimension 384 matches all-MiniLM-L6-v2
   embeddings = np.random.rand(len(sample_docs), 384).astype(np.float32)
   embeddings = embeddings / np.linalg.norm(embeddings, axis=1, keepdims=True)  # Normalize

   document_ids = [f"doc_{i}" for i in range(len(sample_docs))]

   # Insert data
   data = [
       document_ids,
       sample_docs,
       embeddings.tolist()
   ]

   collection.insert(data)
   # Note: flush() forces immediate persistence but Milvus auto-flushes.
   # Use only when you need guaranteed durability before the next operation.
   collection.flush()

   print(f"Inserted {len(sample_docs)} documents")

   # Load collection for searching
   collection.load()
   print("Collection loaded into memory")

   connections.disconnect("default")
   ```

   ```bash
   python load_data.py
   ```

### Task 5: Test Similarity Search (20 min)

1. **Create Search Script**
   ```python
   # Save as search_test.py
   from pymilvus import connections, Collection
   import numpy as np

   # Connect
   connections.connect(
       alias="default",
       host="localhost",
       port=19530,
       user="mlops",
       password="SecurePassword123!"
   )

   # Get collection
   collection = Collection("documents")
   collection.load()

   # Generate a query embedding (simulating "GPU machine learning" query)
   # In production, use the same embedding model as for indexing
   query_embedding = np.random.rand(1, 384).astype(np.float32)
   query_embedding = query_embedding / np.linalg.norm(query_embedding, axis=1, keepdims=True)

   # Search parameters
   search_params = {
       "metric_type": "COSINE",
       "params": {"nprobe": 10}
   }

   # Perform search
   results = collection.search(
       data=query_embedding.tolist(),
       anns_field="embedding",
       param=search_params,
       limit=5,
       output_fields=["document_id", "text"]
   )

   print("Search Results:")
   print("-" * 60)
   for hits in results:
       for hit in hits:
           print(f"Score: {hit.distance:.4f}")
           print(f"Document: {hit.entity.get('document_id')}")
           print(f"Text: {hit.entity.get('text')[:100]}...")
           print("-" * 60)

   connections.disconnect("default")
   ```

   ```bash
   python search_test.py
   ```

2. **Expected Output**
   ```
   Search Results:
   ------------------------------------------------------------
   Score: 0.8234
   Document: doc_2
   Text: NVIDIA GPUs accelerate machine learning training and inference....
   ------------------------------------------------------------
   Score: 0.7891
   Document: doc_6
   Text: Distributed training scales model training across multiple GPUs....
   ...
   ```

### Task 6: Access Attu Web UI (10 min)

1. **Port Forward to Attu**
   ```bash
   kubectl port-forward svc/milvus-attu -n vector-db 3000:3000 &
   ```

2. **Access UI**
   - Open browser to: `http://localhost:3000`
   - Connect to Milvus: `milvus:19530`
   - Login with: `mlops` / `SecurePassword123!`

3. **Explore UI Features**
   - View collections and schemas
   - Browse documents
   - Run queries visually
   - Monitor cluster health

### Task 7: Expose Service (Optional - 10 min)

1. **Create Ingress**
   ```yaml
   # Save as milvus-ingress.yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: milvus-attu
     namespace: vector-db
     annotations:
       nginx.ingress.kubernetes.io/proxy-body-size: "100m"
   spec:
     ingressClassName: nginx
     rules:
       - host: milvus.example.com
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: milvus-attu
                   port:
                     number: 3000
   ```

   ```bash
   kubectl apply -f milvus-ingress.yaml
   ```

## Simplified Alternative: Standalone Mode

For development/testing with limited resources:

```yaml
# Save as milvus-standalone-values.yaml
cluster:
  enabled: false

standalone:
  enabled: true
  persistence:
    enabled: true
    size: 20Gi
  resources:
    requests:
      cpu: "0.5"
      memory: 2Gi
    limits:
      cpu: "2"
      memory: 8Gi

# Enable authentication even in standalone mode
extraConfigFiles:
  user.yaml: |
    common:
      security:
        authorizationEnabled: true

etcd:
  replicaCount: 1
  persistence:
    enabled: true
    size: 5Gi

minio:
  mode: standalone
  persistence:
    enabled: true
    size: 20Gi

pulsar:
  enabled: false

woodpecker:
  enabled: false

attu:
  enabled: true
```

```bash
helm install milvus milvus/milvus \
  --namespace vector-db \
  --values milvus-standalone-values.yaml \
  --wait
```

## Deliverables

- [ ] **Screenshot** of Milvus pods running
- [ ] **Screenshot** of Attu UI showing collection
- [ ] **Search results output** from similarity search test
- [ ] **Configuration YAML** files
- [ ] **Notes** on resource usage and scaling considerations

## Verification Checklist

- [ ] Milvus cluster deployed and healthy
- [ ] All components (etcd, minio, mixcoord, streaming-node) running
- [ ] Authentication configured and enforced (authorizationEnabled: true)
- [ ] Collection created with index
- [ ] Data loaded successfully
- [ ] Similarity search working
- [ ] Attu UI accessible

## Troubleshooting

### Pods Stuck in Pending

**Check PVC provisioning:**
```bash
kubectl get pvc -n vector-db
kubectl describe pvc -n vector-db | grep -A5 "Events:"
```

### etcd Cluster Not Forming

**Check etcd logs:**
```bash
kubectl logs -n vector-db milvus-etcd-0
```

**Common issue:** Clock skew between nodes - ensure NTP is synchronized

### Connection Refused

**Check proxy pod:**
```bash
kubectl logs -n vector-db -l app.kubernetes.io/component=proxy
```

**Verify service:**
```bash
kubectl get endpoints milvus -n vector-db
```

### Slow Queries

**Check if collection is loaded:**
```python
from pymilvus import utility
print(utility.load_state("documents"))
# Should show: LoadState.Loaded
```

**Increase query node resources** in values.yaml

## Key Takeaways

1. **Vector databases are essential** for RAG and semantic search applications
2. **Milvus provides production-grade** distributed vector storage
3. **Index type affects performance** - IVF_FLAT for accuracy, IVF_PQ for speed
4. **Embedding dimensions must match** between indexing and search
5. **Always normalize vectors** for cosine similarity search
6. **Load collections into memory** before searching for best performance
7. **Use standalone mode** for development, cluster mode for production

## Next Lab

Proceed to [Lab 5.4 - Jupyter Notebook Stack](lab-5.7-jupyter-notebooks.md)
