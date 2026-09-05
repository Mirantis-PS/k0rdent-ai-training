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

This lab deploys a **standalone Milvus** baseline with persistent storage, authentication and Attu. Distributed production deployment is an elective requiring additional nodes and sizing.

## Lab Environment

**Cluster Requirements:**
- One workload node with sufficient CPU/RAM and bound persistent volumes; distributed mode requires additional nodes
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

   > **Architecture Note (Milvus v2.6.x):** Current Milvus 5.0.x charts deploy the
   > v2.6 architecture, which introduces **MixCoord**, **StreamingNode**, and
   > **Woodpecker**-based WAL settings. Older 2.5-era charts used separate
   > coordinator pods plus Pulsar-backed WAL. If you intentionally install an
   > older chart, adjust the values file to match that legacy layout.

   ```yaml
   # Save as milvus-values.yaml
   attu:
     enabled: true
   cluster:
     enabled: false
   standalone:
     persistence:
       enabled: true
       persistentVolumeClaim:
         size: 20Gi
   etcd:
     replicaCount: 1
   minio:
     mode: standalone
   pulsar:
     enabled: false
   pulsarv3:
     enabled: false
   woodpecker:
     enabled: false
   streaming:
     woodpecker:
       embedded: true
   extraConfigFiles:
     user.yaml: "common:\n  security:\n    authorizationEnabled: true\n"
   ```

3. **Deploy the standalone baseline via k0rdent ServiceTemplate**

   First install the template on the management cluster (a catalog entry is not automatically installed):

   ```bash
   helm upgrade --install milvus-template oci://ghcr.io/k0rdent/catalog/charts/kgst \
     --set "chart=milvus:5.0.14" -n kcm-system
   kubectl get servicetemplate milvus-5-0-14 -n kcm-system -o yaml
   ```

   The k0rdent catalog includes `milvus-5-0-14` (Milvus v2.6.x). Deploy it
   using a `MultiClusterService` or `ClusterDeployment` service spec, consistent
   with the patterns from Labs 5.1 and 5.2. This resource-sized baseline uses
   standalone Milvus; distributed components are an elective requiring multiple
   workers and a separate storage/capacity plan. Render chart 5.0.14 with the exact
   values before applying; the catalog wrapper requires `milvus:` while the direct
   upstream Helm chart takes the inner values:

   > **Cluster selector — adjust to match your workload cluster labels.** The example uses `environment: training`, matching Lab 5.1. Inspect the actual CAPI Cluster labels in `kcm-system` before applying the MCS; ClusterDeployment metadata labels alone do not prove a selector matches the delivered cluster.

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
         environment: training      # matches Lab 5.1's default ClusterDeployment label; adjust if you renamed
     serviceSpec:
       services:
         - template: milvus-5-0-14
           name: milvus
           namespace: vector-db
           values: |
             milvus:
               attu:
                 enabled: true
               extraConfigFiles:
                 user.yaml: |
                   common:
                     security:
                       authorizationEnabled: true
               cluster:
                 enabled: false
               standalone:
                 persistence:
                   enabled: true
                   persistentVolumeClaim:
                     size: 20Gi
               etcd:
                 replicaCount: 1
               minio:
                 mode: standalone
               pulsar:
                 enabled: false
               pulsarv3:
                 enabled: false
               woodpecker:
                 enabled: false
               streaming:
                 woodpecker:
                   embedded: true
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
   >   --version 5.0.14 \
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

   The pinned standalone configuration renders a Milvus Deployment, one etcd
   StatefulSet, one MinIO Deployment and the Attu UI. Pod suffixes vary:

   ```text
   milvus-standalone-<suffix>
   milvus-etcd-0
   milvus-minio-<suffix>
   milvus-attu-<suffix>
   ```

   Verify each rollout and bound PVCs before the insert/search exercise. Separate
   MixCoord, streaming-node and Pulsar pods are not part of this baseline.

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

   > **⚠️ Production hardening — three issues with the defaults above:**
   >
   > 1. **Milvus `root:Milvus` is the factory default** and stays unchanged if you only `create_user('mlops', ...)`. Add `utility.reset_password("root", "Milvus", "<new-long-random>")` before anything else, or disable the root account after the first admin user is provisioned — otherwise `root:Milvus` remains a valid login and every pymilvus client on the internet knows the defaults.
   > 2. **`SecurePassword123!` literal in the lab markdown + in your shell history.** Same exfiltration surfaces as the Lab 5.10 postgres/rustfs passwords (shell history, `kubectl get secret -o yaml`, etcd backups, helm values dumps, git commits). For prod: generate with `openssl rand -base64 32`, push to your external secret store, and mount via an `ExternalSecret` instead of `kubectl create secret --from-literal`.
   > 3. **Milvus `authorizationEnabled: true` authenticates but does NOT authorize per-collection read/write by default** — the `admin` role grants everything. For multi-tenant workloads, build custom roles via `Role("readonly").grant("CollectionA", "Search")` and assign users to the least-privileged one. Audit periodically with `utility.list_grants(role)`.
   >
   > Canonical k0rdent-native path for (1) + (2): install the `external-secrets` ServiceTemplate via MCS (it's in the catalog), wire a `ClusterSecretStore` against Vault / AWS Secrets Manager / Azure KV, and replace this `kubectl create secret --from-literal` block with an `ExternalSecret` CR that materializes `milvus-credentials` from the external store. Pattern and backend comparison table: see **Lab 5.10 Task 3's "⚠️ Production Secret Management" callout**.

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

## Distributed deployment elective

Standalone is already the baseline in Task 2. For a distributed deployment, use a
separate release/namespace, start from the **5.0.14** chart values, and size etcd,
object storage, coordination, query/data and streaming components for the target
node count. Render the chart and inspect requests, persistence and WAL selection
before applying. Do not upgrade the baseline to distributed mode without a tested
data migration and backup/restore procedure.

## Deliverables

- [ ] **Screenshot** of Milvus pods running
- [ ] **Screenshot** of Attu UI showing collection
- [ ] **Search results output** from similarity search test
- [ ] **Configuration YAML** files
- [ ] **Notes** on resource usage and scaling considerations

## Verification Checklist

- [ ] Milvus cluster deployed and healthy
- [ ] Standalone Milvus, etcd, MinIO and Attu ready; PVCs bound
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
