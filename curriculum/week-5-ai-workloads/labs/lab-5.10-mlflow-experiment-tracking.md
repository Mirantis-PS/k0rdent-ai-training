# Lab 5.10 - MLflow Experiment Tracking

---

## Lab Navigation

| Track | Tier | Duration |
|-------|------|----------|
| ML Platforms | Recommended | 2.5 hours |

### Week 5 Learning Paths

```
FOUNDATION (Completed)                        ML PLATFORMS
━━━━━━━━━━━━━━━━━━━━━━                       ━━━━━━━━━━━━
5.1 ➔ 5.2 ➔ 5.3 ➔ 5.4 ➔ 5.5                5.9 Kubeflow
     ➔ 5.6 ➔ 5.7 ➔ 5.8 ✓                        ↓
                                             YOU ARE HERE
                                                  ↓
                                             [5.10] MLflow
```

| Previous | Current | Next |
|----------|---------|------|
| [Lab 5.9 - Kubeflow](lab-5.9-kubeflow-ml-platform.md) | **Lab 5.10 - MLflow** | Choose: [Lab 5.11 - FIPS](lab-5.11-nvidia-fips.md) or [Lab 5.13 - TensorRT-LLM](lab-5.13-tensorrt-llm.md) |

---

**Duration:** 2.5 hours
**Type:** Hands-on Technical
**Environment:** GPU Lab

## Table of Contents

- [Objective](#objective)
- [Prerequisites](#prerequisites)
- [k0rdent Context](#k0rdent-context)
- [Lab Environment](#lab-environment)
- [Tasks](#tasks)
  - [Task 1: Access the k0rdent-Managed GPU Cluster](#task-1-access-the-k0rdent-managed-gpu-cluster-10-min)
  - [Task 2: Deploy MLflow via k0rdent ServiceTemplate](#task-2-deploy-mlflow-via-k0rdent-servicetemplate-20-min)
  - [Task 3: Manual MLflow Deployment](#task-3-manual-mlflow-deployment-30-min)
  - [Task 4: Configure Client and Log GPU Experiments](#task-4-configure-client-and-log-gpu-experiments-30-min)
  - [Task 5: Kubernetes Training Job with MLflow](#task-5-kubernetes-training-job-with-mlflow-30-min)
  - [Task 6: Model Registry with Aliases](#task-6-model-registry-with-aliases-25-min)
- [Deliverables](#deliverables)
- [Verification Checklist](#verification-checklist)
- [Troubleshooting](#troubleshooting)
- [Key Takeaways](#key-takeaways)
- [Next Lab](#next-lab)

## Objective

Deploy MLflow as a centralized experiment tracking server on a k0rdent-managed GPU cluster, configure S3-compatible artifact storage with RustFS, and integrate it with GPU-based training workflows using the modern MLflow 3.x API for ML lifecycle management.

## Prerequisites

- Completed Lab 5.1 (GPU Scheduler deployed)
- k0rdent Enterprise management cluster operational
- At least one k0rdent-managed GPU cluster deployed
- Python 3.10+ (required for MLflow 3.x)

## k0rdent Context

### MLflow in the k0rdent Ecosystem

The k0rdent catalog currently exposes the `mlflow-1-8-1` ServiceTemplate, which wraps the MLflow community chart version `1.8.1` (app version `3.7.0` on the current catalog page). This provides a production-ready MLflow tracking server with PostgreSQL backend and S3-compatible artifact storage.

```
┌─────────────────────────────────────────────────────────────────────┐
│                   k0rdent Management Cluster                        │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │  ServiceTemplate │  │ MultiCluster     │  │ ClusterDeployment│  │
│  │  mlflow-1-8-1    │  │ Service          │  │ (GPU clusters)   │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
│           │                     │                      │            │
│           └─────────────────────┼──────────────────────┘            │
│                                 │ Sveltos                           │
│                                 ▼                                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              Workload Cluster (GPU)                           │   │
│  │  ┌─────────────┐  ┌──────────┐  ┌───────────┐               │   │
│  │  │ MLflow      │  │ RustFS   │  │PostgreSQL │               │   │
│  │  │ Tracking    │  │ S3 Artif.│  │ Backend   │               │   │
│  │  │ Server      │  │ Store    │  │ Store     │               │   │
│  │  └──────┬──────┘  └──────────┘  └───────────┘               │   │
│  │         │                                                    │   │
│  │  ┌──────┴──────────────────────────────────────────┐         │   │
│  │  │          GPU Training Jobs                       │         │   │
│  │  │  ┌────────┐  ┌────────┐  ┌────────┐            │         │   │
│  │  │  │ Run 1  │  │ Run 2  │  │ Run N  │            │         │   │
│  │  │  └────────┘  └────────┘  └────────┘            │         │   │
│  │  └─────────────────────────────────────────────────┘         │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### MLflow 3.x Migration Notes

This lab uses an alias-first MLflow 3.x workflow. The table below highlights the patterns used in this lab:

| Feature | Older Pattern | Pattern Used in This Lab |
|---------|-------------------|----------------------|
| Model lifecycle workflow | `transition_model_version_stage("Production")` | `set_registered_model_alias("champion", version)` |
| Model URI | `models:/name/Production` | `models:/name@champion` |
| Python | 3.8+ | 3.10+ recommended |
| Registry backend | File store in simple setups | SQL-backed registry recommended for shared environments |

> **Compatibility note:** MLflow still documents Projects, AI Gateway / Gateway Server, and lifecycle stages in current docs. This lab prefers aliases because they map more cleanly to promotion workflows on Kubernetes.

## Lab Environment

**Cluster Requirements:**
- Kubernetes 1.28+ with GPU nodes
- NVIDIA GPU Operator v25.10.0 installed
- StorageClass `ebs-gp3` available (AWS EBS)
- 4+ vCPUs, 8GB+ RAM for MLflow server
- 50GB storage for artifacts

## Tasks

### Task 1: Access the k0rdent-Managed GPU Cluster (10 min)

All operations in this lab target a workload cluster managed by k0rdent Enterprise. First, extract the kubeconfig from the management cluster.

1. **Identify your GPU cluster**
   ```bash
   # On the management cluster
   kubectl get clusterdeployments -n kcm-system
   ```

2. **Extract the workload cluster kubeconfig**
   ```bash
   export CLUSTER_NAME=gpu-cluster-01
   kubectl get secret ${CLUSTER_NAME}-kubeconfig \
     -n kcm-system \
     -o jsonpath='{.data.value}' | base64 -d > /tmp/${CLUSTER_NAME}.kubeconfig
   export KUBECONFIG=/tmp/${CLUSTER_NAME}.kubeconfig
   ```

3. **Verify GPU availability on the workload cluster**
   ```bash
   kubectl get nodes -l nvidia.com/gpu.present=true
   kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
   ```

### Task 2: Deploy MLflow via k0rdent ServiceTemplate (20 min)

The k0rdent catalog provides the `mlflow-1-8-1` ServiceTemplate for automated MLflow deployment. This is the recommended approach for k0rdent-managed environments.

> **⚠️ Known limitations of the `mlflow-1-8-1` ServiceTemplate (community-charts/mlflow 1.8.1, app 3.7.0) — empirically validated 2026-04-17:**
>
> 1. **`postgresql.enabled`, `tracking.persistence.*`, and other subchart toggle values are SILENTLY IGNORED.** The wrapped community chart does NOT bundle PostgreSQL or S3 subcharts; these values appear under `helm get values` but produce no pods. The deployment you get is a single-pod MLflow server.
> 2. **The single pod runs with `--backend-store-uri=sqlite:///:memory:`** — in-memory SQLite. All experiments, runs, and metadata are lost on pod restart. Unsuitable for any persistent experiment tracking.
> 3. **MLflow 3.7 security middleware blocks all non-localhost HTTP requests** with `403 "Invalid Host header - possible DNS rebinding attack detected"`. The chart does NOT expose a value to set `--allowed-hosts` or disable the middleware, so the Task 5 in-cluster Kubernetes Job (or any other client connecting via the `mlflow` Service's ClusterIP) cannot reach the tracking API.
>
> **Practical consequence:** the ServiceTemplate path is currently suitable only for a smoke test of "MLflow binary runs in a pod" — not for the experiment-tracking workflow this lab teaches. Use Task 3 (manual deployment) for a working MLflow stack until the catalog chart is updated to (a) support PostgreSQL + S3 subchart toggles, (b) persist the SQLite store to a PVC, and (c) expose `server.allowedHosts` (or equivalent) as a value.

1. **Install the MLflow ServiceTemplate from the catalog** (on the management cluster)
   ```bash
   # Switch to management cluster context
   export KUBECONFIG=~/.kube/config

   # Install the MLflow ServiceTemplate from the external catalog
   helm upgrade --install mlflow-template \
     oci://ghcr.io/k0rdent/catalog/charts/kgst \
     --set "chart=mlflow:1.8.1" \
     -n kcm-system
   ```

2. **Verify the ServiceTemplate is available**
   ```bash
   kubectl get servicetemplate mlflow-1-8-1 -n kcm-system
   ```

3. **Option A: Deploy via ClusterDeployment serviceSpec** (single cluster)

   If your GPU cluster's ClusterDeployment already exists, add MLflow to its service list:
   ```yaml
   # Save as mlflow-service-patch.yaml
   spec:
     serviceSpec:
       services:
         - template: mlflow-1-8-1
           name: mlflow
           namespace: mlflow
           # Values intentionally omitted — per the ⚠️ warning above, the
           # current catalog chart silently ignores persistence / subchart
           # toggles. Applying this MCS only validates that the
           # ServiceTemplate reconciles a single-pod MLflow against the
           # workload cluster. See Task 3 for a production-viable deploy.
   ```

   ```bash
   kubectl patch clusterdeployment ${CLUSTER_NAME} \
     -n kcm-system \
     --type merge \
     --patch-file mlflow-service-patch.yaml
   ```

4. **Option B: Deploy via MultiClusterService** (multiple clusters)
   ```yaml
   # Save as mlflow-multicluster.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: mlflow-tracking
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         k0rdent.mirantis.com/workload: ml-platform
     serviceSpec:
       services:
         - template: mlflow-1-8-1
           name: mlflow
           namespace: mlflow
           # Values intentionally omitted — see Option A note above.
   ```

   ```bash
   kubectl apply -f mlflow-multicluster.yaml
   ```

5. **Verify deployment via Sveltos** (on the management cluster)
   ```bash
   # Check the Sveltos condition
   kubectl get clusterdeployment ${CLUSTER_NAME} -n kcm-system \
     -o jsonpath='{.status.conditions[?(@.type=="SveltosHelmReleaseReady")]}' | jq .

   # Switch to workload cluster and verify pods
   export KUBECONFIG=/tmp/${CLUSTER_NAME}.kubeconfig
   kubectl get pods -n mlflow
   kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=mlflow -n mlflow --timeout=300s
   ```

> **Note:** If your environment does not have the MLflow ServiceTemplate available, or you need more control over the deployment, continue with Task 3 for a manual installation.

### Task 3: Production-ready MLflow on k0rdent — RustFS + PostgreSQL + raw MLflow (45 min)

**Use this path when Task 2 fails** (the `mlflow-1-8-1` ServiceTemplate has the known limitations listed in Task 2's warning callout), **or when you need a persistent multi-user experiment tracker** that survives pod restarts. Empirically validated end-to-end on the Lab 5.1 gpu-cluster on 2026-04-17.

**Architecture (all Mirantis / Apache-2.0 ecosystem):**

```
┌──────────────── Workload cluster: namespace `mlflow` ─────────────────┐
│                                                                        │
│  ┌─────────────────┐   backend-store-uri   ┌──────────────────────┐   │
│  │ MLflow Deploy   │──────────────────────▶│ PostgreSQL 18        │   │
│  │ burakince/      │                       │ k0rdent catalog      │   │
│  │ mlflow:3.7.0    │                       │ ServiceTemplate      │   │
│  │ --allowed-hosts=│                       │ postgresql-18-3-0    │   │
│  │   "*"           │                       │ (wraps Bitnami)      │   │
│  └─────────────────┘                       └──────────────────────┘   │
│        │                                                               │
│        │ default-artifact-root=s3://mlflow-artifacts/                  │
│        ▼                                                               │
│  ┌──────────────────────┐                                              │
│  │ RustFS standalone    │  Apache-2.0 S3-compatible object store,      │
│  │ 1 pod + 50Gi PVC     │  installed from charts.rustfs.com            │
│  └──────────────────────┘                                              │
└───────────────────────────────────────────────────────────────────────┘

      ▲
      │ MCS from kcm-system on management cluster
      │
┌─────┴─────────────────── Management cluster ─────────────────────────┐
│  ServiceTemplate postgresql-18-3-0 (kgst-installed from catalog)      │
│  MultiClusterService mlflow-postgresql (selects environment:training) │
└───────────────────────────────────────────────────────────────────────┘
```

**Why this stack:**

- **RustFS for artifact storage** — Apache-2.0 licensed S3-compatible object store. Drop-in for any `boto3` client: MLflow needs no config beyond `MLFLOW_S3_ENDPOINT_URL` pointing at the RustFS Service.
- **PostgreSQL via k0rdent catalog** — MCS-managed, Sveltos-reconciled, matches the Mirantis-native deployment flow for stateful workloads.
- **Raw MLflow Deployment (not via chart)** — gives full control over the CLI args this stack needs: `--allowed-hosts="*"` (required so non-localhost clients can reach the tracking API), `--backend-store-uri=postgresql://...`, `--default-artifact-root=s3://mlflow-artifacts/`.

**Prerequisites:**
- `kubectl get storageclass` on the workload cluster shows at least one default — on Lab 5.1 gpu-cluster this is `ebs-csi-default-sc`.
- `helm` ≥ 3.12 on the management node with network access to `ghcr.io` and `charts.rustfs.com`.
- The RustFS helm chart's storage config requires an **explicit** storageclass name — it defaults to `local-path` which does not exist on AWS EBS CSI clusters.

> **⚠️ Production Secret Management — DO NOT ship the inline plaintext pattern below to prod.**
>
> The steps in this task carry several secret values as literal strings inside `kubectl create secret --from-literal=...` commands and MCS `values:` blocks:
>
> - RustFS access key + secret (`mlflow` / `mlflow-s3cr3t-8392nX`)
> - PostgreSQL admin password (`pgadmin-s3cr3t`)
> - PostgreSQL application password for the `mlflow` user (`mlflow-pg-s3cr3t`)
>
> **That is demo-grade hygiene only.** Every value above lands in multiple places that are easy to accidentally leak: shell history, `kubectl get secret -o yaml` dumps, helm release metadata, git-committed `MultiClusterService` YAML, Sveltos audit logs, and `etcd` backups. Any one of those surfaces leaking rotates the blast radius from "one lab" to "every cluster that pulled this MCS."
>
> For anything past a training run, drive secrets through an **external secret store** reconciled by the [External Secrets Operator](https://external-secrets.io/) — which IS in the k0rdent catalog as the `external-secrets` ServiceTemplate. The canonical k0rdent flow:
>
> 1. **Install External Secrets Operator on the workload cluster via MCS:**
>    ```yaml
>    # Save as eso-mcs.yaml (on the management cluster)
>    apiVersion: k0rdent.mirantis.com/v1beta1
>    kind: MultiClusterService
>    metadata:
>      name: external-secrets
>      namespace: kcm-system
>    spec:
>      clusterSelector:
>        matchLabels:
>          environment: training
>      serviceSpec:
>        services:
>          - template: external-secrets-0-19-0   # or current catalog version
>            name: external-secrets
>            namespace: external-secrets
>    ```
>
> 2. **Wire a `SecretStore` to your source of truth.** Pick one that matches your org's posture:
>
>    | Backend | k0rdent fit | Rotation story | Notes |
>    |---|---|---|---|
>    | **AWS Secrets Manager** (recommended on AWS) | Auth via IRSA (EKS) or node IAM role (k0s on EC2) | Native 30/90-day rotation lambdas | Cheapest path when the workload cluster already has AWS IAM |
>    | **HashiCorp Vault** (recommended on-prem / multi-cloud) | Auth via Kubernetes auth method, SPIFFE, or approle | Fine-grained TTLs + dynamic PostgreSQL creds | Use the dedicated `vault` backend, not `kv-v2`, for dynamic Postgres roles that issue per-pod throwaway passwords |
>    | **Azure Key Vault / GCP Secret Manager** | Mirrors of AWS Secrets Manager per cloud | Cloud-native KMS + rotation | Same pattern, just different `SecretStore.spec.provider.*` key |
>    | **SOPS + age/PGP + git** | Works without an external API | Manual rotation (rewrite + re-encrypt) | Not ESO — use `sops-secrets-operator` or decrypt in a pre-commit hook. Fine for GitOps-only shops, brittle for dynamic creds. |
>
> 3. **Replace every `kubectl create secret --from-literal=...` in this task with an `ExternalSecret` CR** pointing at your `SecretStore`:
>    ```yaml
>    apiVersion: external-secrets.io/v1beta1
>    kind: ExternalSecret
>    metadata:
>      name: rustfs-credentials
>      namespace: mlflow
>    spec:
>      refreshInterval: 1h
>      secretStoreRef:
>        name: aws-secrets-manager         # the SecretStore you created in step 2
>        kind: ClusterSecretStore
>      target:
>        name: rustfs-credentials           # the K8s Secret ESO will materialize
>        creationPolicy: Owner
>      data:
>        - secretKey: AWS_ACCESS_KEY_ID
>          remoteRef: { key: mlflow/rustfs, property: access_key }
>        - secretKey: AWS_SECRET_ACCESS_KEY
>          remoteRef: { key: mlflow/rustfs, property: secret_key }
>    ```
>    ESO generates the same `Secret/rustfs-credentials` shape the raw Deployment expects, so downstream env/volumeMount references in step 6 (MLflow Deployment) and Task 5 (training Job) do **not** change. Drop-in at the secret boundary.
>
> 4. **Same pattern for the PostgreSQL user password** — after the manual `CREATE ROLE mlflow` bootstrap in step 4, either (a) store `mlflow-pg-s3cr3t` in the external store and mount via ExternalSecret, or (b) preferred: use Vault's **dynamic database credentials** plugin so every pod restart gets a fresh short-TTL Postgres user, and the static password disappears entirely.
>
> 5. **Admin credential hygiene.** The Bitnami chart's auto-generated `postgres-password` (the one we extract in step 4 to bootstrap the mlflow user) stays in the `postgresql` Secret on-cluster. In production, rotate it via a one-shot Job that runs `ALTER USER postgres WITH PASSWORD '<new>'` + `kubectl patch secret postgresql ...` + `rollout restart statefulset/postgresql`. Bake that into your CI/CD rotation schedule alongside the application-level creds.
>
> 6. **Student / training runs only:** use the plaintext values below as they stand — just treat the cluster as ephemeral, never push the resulting YAML to a public repo, and `lab-destroy.sh` when done so the EBS volumes (which hold the Postgres + RustFS data at rest) are reclaimed.
>
> The same three-tier callout applies to **Lab 5.7 (JupyterHub `DummyAuthenticator.password: "training123"`)** and **Lab 5.8 (Milvus `root:Milvus` default root credentials + `milvus-credentials` secret creation)**. Swap DummyAuth for OIDC-via-dex (also in the catalog as `dex-*`) for JupyterHub in prod, and wire Milvus authorization through ExternalSecrets against a Vault KV mount.

1. **Create workload namespace + RustFS S3 credentials secret**
   ```bash
   export KUBECONFIG=/tmp/${CLUSTER_NAME}.kubeconfig   # or ~/.kube/gpu-cluster.conf
   kubectl create namespace mlflow

   # These credentials will be used by MLflow (as S3 client) AND by the
   # bucket-bootstrap Job. Rotate the values for production use.
   kubectl create secret generic rustfs-credentials -n mlflow \
     --from-literal=AWS_ACCESS_KEY_ID=mlflow \
     --from-literal=AWS_SECRET_ACCESS_KEY=mlflow-s3cr3t-8392nX
   ```

2. **Deploy RustFS (standalone, 50Gi data PVC) via external helm repo**
   ```bash
   helm repo add rustfs https://charts.rustfs.com
   helm repo update rustfs

   helm install rustfs rustfs/rustfs \
     --namespace mlflow \
     --set mode.standalone.enabled=true \
     --set mode.distributed.enabled=false \
     --set replicaCount=1 \
     --set secret.rustfs.access_key=mlflow \
     --set secret.rustfs.secret_key=mlflow-s3cr3t-8392nX \
     --set storageclass.name=ebs-csi-default-sc \
     --set storageclass.dataStorageSize=50Gi \
     --wait --timeout 8m
   ```

   > **Do NOT skip `storageclass.name`.** The RustFS chart defaults to `local-path` — if you omit the flag on an EBS CSI cluster, both `rustfs-data` and `rustfs-logs` PVCs stay `Pending` forever and the helm install times out. Use `kubectl get storageclass` first, pick your default, pass it explicitly.

   Verify: `kubectl get pods,pvc,svc -n mlflow` should show `rustfs-*` pod Ready, `rustfs-data` Bound (50Gi), `rustfs-logs` Bound (1Gi), and `rustfs-svc` Service exposing `9000/TCP,9001/TCP`.

3. **Deploy PostgreSQL via the k0rdent catalog ServiceTemplate**

   The catalog provides `postgresql-18-3-0` (wraps Bitnami PostgreSQL chart 18.3.0, PostgreSQL 18). Install the ServiceTemplate on the management cluster, then apply a MultiClusterService that reconciles it onto the workload cluster.

   ```bash
   # On the management cluster
   unset KUBECONFIG   # or use ~/.kube/config

   helm upgrade --install postgresql-template \
     oci://ghcr.io/k0rdent/catalog/charts/kgst \
     --set chart=postgresql:18.3.0 \
     -n kcm-system --wait --timeout 5m

   # Wait for the ServiceTemplate to validate
   kubectl wait servicetemplate postgresql-18-3-0 -n kcm-system \
     --for=jsonpath='{.status.valid}'=true --timeout=120s
   ```

   ```yaml
   # Save as mlflow-postgresql-mcs.yaml
   apiVersion: k0rdent.mirantis.com/v1beta1
   kind: MultiClusterService
   metadata:
     name: mlflow-postgresql
     namespace: kcm-system
   spec:
     clusterSelector:
       matchLabels:
         environment: training     # label applied by Lab 5.1 ClusterDeployment
     serviceSpec:
       services:
         - template: postgresql-18-3-0
           name: postgresql
           namespace: mlflow
           values: |
             auth:
               database: mlflow
               username: mlflow
               password: mlflow-pg-s3cr3t
               postgresPassword: pgadmin-s3cr3t
             primary:
               persistence:
                 size: 10Gi
   ```

   ```bash
   kubectl apply -f mlflow-postgresql-mcs.yaml

   # Watch postgres come up on the workload cluster
   export KUBECONFIG=/tmp/${CLUSTER_NAME}.kubeconfig
   kubectl wait --for=condition=Ready pod/postgresql-0 -n mlflow --timeout=5m
   ```

   > **⚠️ Known limitation: the wrapped Bitnami chart 18.3.0 silently ignores `auth.username`, `auth.password`, `auth.postgresPassword`, and `auth.database` values.** `helm get values postgresql -n mlflow` shows your values applied, but the rendered `postgresql` Secret contains only a random auto-generated `postgres-password` — no `password` key for the `mlflow` user, and no `mlflow` role or database exist in the running instance. Root cause under investigation (probable interaction between `global.defaultFips=restricted` and the kgst / Sveltos rendering path). Until the catalog chart is fixed, apply the one-shot workaround in step 4.

4. **Bootstrap mlflow role + database (workaround for the Bitnami chart `auth.*` limitation above)**
   ```bash
   export KUBECONFIG=/tmp/${CLUSTER_NAME}.kubeconfig

   # Read the auto-generated postgres admin password from the Secret that Bitnami DID create
   PG_ADMIN_PW=$(kubectl get secret postgresql -n mlflow \
     -o jsonpath='{.data.postgres-password}' | base64 -d)

   # Create the mlflow role + database + grants manually — single idempotent block
   kubectl exec -n mlflow postgresql-0 -- bash -c \
     "PGPASSWORD=${PG_ADMIN_PW} psql -U postgres -h localhost <<'SQL'
   DO \$\$ BEGIN
     IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mlflow') THEN
       CREATE ROLE mlflow WITH LOGIN PASSWORD 'mlflow-pg-s3cr3t';
     END IF;
   END \$\$;
   SELECT 'CREATE DATABASE mlflow OWNER mlflow'
     WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mlflow')\\gexec
   GRANT ALL PRIVILEGES ON DATABASE mlflow TO mlflow;
   SQL"

   # Verify the mlflow user can authenticate
   kubectl exec -n mlflow postgresql-0 -- bash -c \
     "PGPASSWORD=mlflow-pg-s3cr3t psql -U mlflow -d mlflow -h localhost -c 'SELECT current_user, current_database()'"
   ```

   Expected output: `mlflow | mlflow`.

5. **Create the `mlflow-artifacts` bucket on RustFS**
   ```yaml
   # Save as create-bucket-job.yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: create-mlflow-bucket
     namespace: mlflow
   spec:
     backoffLimit: 3
     template:
       spec:
         restartPolicy: OnFailure
         containers:
           - name: awscli
             image: amazon/aws-cli:latest
             command:
               - sh
               - -c
               - |
                 aws --endpoint-url http://rustfs-svc.mlflow.svc:9000 s3 mb s3://mlflow-artifacts || true
                 aws --endpoint-url http://rustfs-svc.mlflow.svc:9000 s3 ls
             env:
               - { name: AWS_ACCESS_KEY_ID,     valueFrom: { secretKeyRef: { name: rustfs-credentials, key: AWS_ACCESS_KEY_ID } } }
               - { name: AWS_SECRET_ACCESS_KEY, valueFrom: { secretKeyRef: { name: rustfs-credentials, key: AWS_SECRET_ACCESS_KEY } } }
               - { name: AWS_DEFAULT_REGION,    value: us-east-1 }
   ```

   ```bash
   kubectl apply -f create-bucket-job.yaml
   kubectl wait --for=condition=complete job/create-mlflow-bucket -n mlflow --timeout=3m
   kubectl logs -n mlflow -l job-name=create-mlflow-bucket --tail=5
   # Expected: "make_bucket: mlflow-artifacts"
   ```

6. **Deploy MLflow tracking server as a raw Deployment**

   A raw Deployment (rather than the broken `mlflow-1-8-1` chart) lets us pass the CLI flags we actually need — `--allowed-hosts=*` to defeat MLflow 3.7's DNS-rebinding middleware, and `--backend-store-uri` / `--default-artifact-root` to point at our PostgreSQL and RustFS.

   ```yaml
   # Save as mlflow-deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: mlflow
     namespace: mlflow
     labels:
       app: mlflow
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: mlflow
     template:
       metadata:
         labels:
           app: mlflow
       spec:
         containers:
           - name: mlflow
             image: burakince/mlflow:3.7.0      # same image the catalog chart uses, but with our args
             command: ["mlflow"]
             args:
               - server
               - --host=0.0.0.0
               - --port=5000
               - --allowed-hosts=*                   # REQUIRED for MLflow 3.7+ behind a ClusterIP Service
               - --backend-store-uri=postgresql://mlflow:mlflow-pg-s3cr3t@postgresql.mlflow.svc:5432/mlflow
               - --default-artifact-root=s3://mlflow-artifacts/
             env:
               - { name: MLFLOW_S3_ENDPOINT_URL, value: http://rustfs-svc.mlflow.svc:9000 }
               - { name: MLFLOW_S3_IGNORE_TLS,   value: "true" }
               - { name: AWS_ACCESS_KEY_ID,     valueFrom: { secretKeyRef: { name: rustfs-credentials, key: AWS_ACCESS_KEY_ID } } }
               - { name: AWS_SECRET_ACCESS_KEY, valueFrom: { secretKeyRef: { name: rustfs-credentials, key: AWS_SECRET_ACCESS_KEY } } }
             ports:
               - { containerPort: 5000, name: http }
             readinessProbe: { httpGet: { path: /health, port: 5000 }, initialDelaySeconds: 20, periodSeconds: 5 }
             livenessProbe:  { httpGet: { path: /health, port: 5000 }, initialDelaySeconds: 60, periodSeconds: 15 }
             resources:
               requests: { cpu: 200m, memory: 512Mi }
               limits:   { cpu: 1,    memory: 1Gi }
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: mlflow
     namespace: mlflow
   spec:
     selector:
       app: mlflow
     ports:
       - { name: http, port: 5000, targetPort: http }
   ```

   ```bash
   kubectl apply -f mlflow-deployment.yaml
   kubectl wait --for=condition=Available deployment/mlflow -n mlflow --timeout=3m

   # Sanity check — should return HTTP 200 with empty body
   kubectl port-forward -n mlflow svc/mlflow 5000:5000 &
   PF=$!
   sleep 3
   curl -s -w "HTTP %{http_code}\n" http://localhost:5000/health
   # Verify the DNS rebinding middleware is NOT blocking us:
   curl -s -X POST http://localhost:5000/api/2.0/mlflow/experiments/search \
        -H 'Content-Type: application/json' -d '{"max_results":10}' | head -3
   kill $PF 2>/dev/null
   ```

   Expected: `HTTP 200` and a JSON body like `{"experiments":[...], "next_page_token":"..."}` — **not** a `403 Invalid Host header`. If you still see 403, double-check the `--allowed-hosts=*` arg made it into the running pod (that's the exact symptom the Task 2 warning callout describes, and means `--allowed-hosts` was stripped or overridden).

7. **Verify the full stack**
   ```bash
   kubectl get pods,svc,pvc -n mlflow
   # Expected pods all Running:
   #   postgresql-0             (from catalog MCS)
   #   rustfs-xxxxxxxxxx-yyyyy  (from rustfs helm)
   #   mlflow-xxxxxxxxxx-yyyyy  (from raw Deployment)
   # Expected services: postgresql, postgresql-hl, rustfs-svc, mlflow
   # Expected PVCs Bound: data-postgresql-0 (8Gi), rustfs-data (50Gi),
   #                     rustfs-logs (1Gi)
   ```

   End-to-end smoke test from the management node (validates MLflow → PostgreSQL → RustFS chain in one Job):
   ```bash
   kubectl create configmap mlflow-smoke-script --from-literal=smoke.py='
   import mlflow, os
   mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
   mlflow.set_experiment("smoke-test")
   with mlflow.start_run(run_name="e2e-check"):
       mlflow.log_param("hello", "world")
       mlflow.log_metric("answer", 42)
       with open("/tmp/artifact.txt","w") as f: f.write("rustfs ok")
       mlflow.log_artifact("/tmp/artifact.txt")
   print("OK")
   ' -n mlflow

   kubectl apply -n mlflow -f - <<EOF
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: mlflow-smoke
   spec:
     backoffLimit: 1
     template:
       spec:
         restartPolicy: Never
         containers:
           - name: s
             image: python:3.11-slim
             command: ["sh","-c","pip install --quiet 'mlflow>=3.1.0' boto3 && python /s/smoke.py"]
             env:
               - { name: MLFLOW_TRACKING_URI,    value: http://mlflow.mlflow.svc:5000 }
               - { name: MLFLOW_S3_ENDPOINT_URL, value: http://rustfs-svc.mlflow.svc:9000 }
               - { name: AWS_ACCESS_KEY_ID,     valueFrom: { secretKeyRef: { name: rustfs-credentials, key: AWS_ACCESS_KEY_ID } } }
               - { name: AWS_SECRET_ACCESS_KEY, valueFrom: { secretKeyRef: { name: rustfs-credentials, key: AWS_SECRET_ACCESS_KEY } } }
             volumeMounts: [ { name: s, mountPath: /s } ]
         volumes: [ { name: s, configMap: { name: mlflow-smoke-script } } ]
   EOF
   kubectl wait --for=condition=complete job/mlflow-smoke -n mlflow --timeout=5m
   kubectl logs -n mlflow -l job-name=mlflow-smoke --tail=3
   # Expected last line: OK
   ```

### Task 4: Configure Client and Log GPU Experiments (30 min)

1. **Install MLflow client**
   ```bash
   pip install 'mlflow>=3.1.0' boto3 psycopg2-binary torch torchvision
   ```

2. **Create GPU training script with MLflow integration**
   ```python
   # Save as train_with_mlflow.py
   import mlflow
   import mlflow.pytorch
   import torch
   import torch.nn as nn
   import torch.optim as optim
   from torchvision import datasets, transforms
   from torch.utils.data import DataLoader
   import os
   import time

   # Configure MLflow — these match the Task 3 rustfs-credentials secret.
   # Before running this script from your laptop, port-forward BOTH services:
   #   kubectl port-forward -n mlflow svc/mlflow     5000:5000 &
   #   kubectl port-forward -n mlflow svc/rustfs-svc 9000:9000 &
   os.environ['MLFLOW_S3_ENDPOINT_URL'] = 'http://localhost:9000'
   os.environ['AWS_ACCESS_KEY_ID'] = 'mlflow'
   os.environ['AWS_SECRET_ACCESS_KEY'] = 'mlflow-s3cr3t-8392nX'

   mlflow.set_tracking_uri('http://localhost:5000')
   mlflow.set_experiment('gpu-training-experiments')

   # Check GPU availability
   device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
   print(f"Training on: {device}")
   if torch.cuda.is_available():
       print(f"GPU: {torch.cuda.get_device_name(0)}")
       print(f"GPU Memory: {torch.cuda.get_device_properties(0).total_mem / 1e9:.1f} GB")


   class CNN(nn.Module):
       """Simple CNN for MNIST classification."""
       def __init__(self, hidden_size=128, dropout=0.2):
           super().__init__()
           self.conv1 = nn.Conv2d(1, 32, 3, padding=1)
           self.conv2 = nn.Conv2d(32, 64, 3, padding=1)
           self.pool = nn.MaxPool2d(2, 2)
           self.fc1 = nn.Linear(64 * 7 * 7, hidden_size)
           self.fc2 = nn.Linear(hidden_size, 10)
           self.dropout = nn.Dropout(dropout)

       def forward(self, x):
           x = self.pool(torch.relu(self.conv1(x)))
           x = self.pool(torch.relu(self.conv2(x)))
           x = x.view(-1, 64 * 7 * 7)
           x = self.dropout(torch.relu(self.fc1(x)))
           return self.fc2(x)


   def train_model(learning_rate=0.001, batch_size=64, epochs=5,
                    hidden_size=128, dropout=0.2):
       with mlflow.start_run():
           # Log parameters
           mlflow.log_param("learning_rate", learning_rate)
           mlflow.log_param("batch_size", batch_size)
           mlflow.log_param("epochs", epochs)
           mlflow.log_param("hidden_size", hidden_size)
           mlflow.log_param("dropout", dropout)
           mlflow.log_param("device", str(device))
           if torch.cuda.is_available():
               mlflow.log_param("gpu_name", torch.cuda.get_device_name(0))

           # Load MNIST data
           transform = transforms.Compose([
               transforms.ToTensor(),
               transforms.Normalize((0.1307,), (0.3081,))
           ])
           train_dataset = datasets.MNIST(
               './data', train=True, download=True, transform=transform
           )
           test_dataset = datasets.MNIST(
               './data', train=False, transform=transform
           )
           train_loader = DataLoader(
               train_dataset, batch_size=batch_size, shuffle=True
           )
           test_loader = DataLoader(test_dataset, batch_size=batch_size)

           # Initialize model and optimizer
           model = CNN(hidden_size=hidden_size, dropout=dropout).to(device)
           criterion = nn.CrossEntropyLoss()
           optimizer = optim.Adam(model.parameters(), lr=learning_rate)

           # Training loop
           start_time = time.time()
           for epoch in range(epochs):
               model.train()
               running_loss = 0.0
               correct = 0
               total = 0

               for data, target in train_loader:
                   data, target = data.to(device), target.to(device)
                   optimizer.zero_grad()
                   output = model(data)
                   loss = criterion(output, target)
                   loss.backward()
                   optimizer.step()

                   running_loss += loss.item()
                   _, predicted = output.max(1)
                   total += target.size(0)
                   correct += predicted.eq(target).sum().item()

               epoch_loss = running_loss / len(train_loader)
               epoch_acc = correct / total

               mlflow.log_metric("train_loss", epoch_loss, step=epoch)
               mlflow.log_metric("train_accuracy", epoch_acc, step=epoch)
               print(f"Epoch {epoch+1}/{epochs}: "
                     f"Loss={epoch_loss:.4f}, Acc={epoch_acc:.4f}")

           training_time = time.time() - start_time
           mlflow.log_metric("training_time_seconds", training_time)

           # Test evaluation
           model.eval()  # Use model.eval() instead of model.train(False)
           test_loss = 0
           correct = 0
           total = 0

           with torch.no_grad():
               for data, target in test_loader:
                   data, target = data.to(device), target.to(device)
                   output = model(data)
                   test_loss += criterion(output, target).item()
                   _, predicted = output.max(1)
                   total += target.size(0)
                   correct += predicted.eq(target).sum().item()

           test_loss /= len(test_loader)
           test_acc = correct / total

           mlflow.log_metric("test_loss", test_loss)
           mlflow.log_metric("test_accuracy", test_acc)

           print(f"\nTest: Loss={test_loss:.4f}, Acc={test_acc:.4f}")
           print(f"Training time: {training_time:.1f}s")

           # Log model artifact
           mlflow.pytorch.log_model(model, "model")

           return test_acc


   if __name__ == "__main__":
       # Run hyperparameter sweep
       experiments = [
           {"learning_rate": 0.001, "batch_size": 64,
            "epochs": 3, "hidden_size": 128, "dropout": 0.2},
           {"learning_rate": 0.0005, "batch_size": 128,
            "epochs": 3, "hidden_size": 256, "dropout": 0.3},
           {"learning_rate": 0.002, "batch_size": 32,
            "epochs": 3, "hidden_size": 64, "dropout": 0.1},
       ]

       for i, params in enumerate(experiments):
           print(f"\n{'='*50}")
           print(f"Experiment {i+1}/{len(experiments)}")
           print(f"{'='*50}")
           train_model(**params)
   ```

3. **Run the training script**
   ```bash
   python train_with_mlflow.py
   ```

4. **Verify experiments in the UI**
   - Open http://localhost:5000
   - Navigate to "gpu-training-experiments"
   - Compare runs side-by-side: select multiple runs and click "Compare"
   - View training curves under each run's Metrics tab
   - Download artifacts from the Artifacts tab

### Task 5: Kubernetes Training Job with MLflow (30 min)

1. **Create a ConfigMap with the training script**

   This approach keeps the training code in a ConfigMap mounted into the Job, making it easy to iterate without rebuilding images.

   ```yaml
   # Save as training-configmap.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: mlflow-training-script
     namespace: mlflow
   data:
     train.py: |
       import mlflow
       import mlflow.pytorch
       import torch
       import torch.nn as nn
       import torch.optim as optim
       from torchvision import datasets, transforms
       from torch.utils.data import DataLoader
       import os

       # MLflow configuration from environment
       mlflow.set_tracking_uri(os.environ['MLFLOW_TRACKING_URI'])
       mlflow.set_experiment('kubernetes-gpu-training')

       device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
       print(f"Training on: {device}")

       with mlflow.start_run(run_name=f"k8s-{os.environ.get('HOSTNAME', 'unknown')}"):
           mlflow.log_param("device", str(device))
           mlflow.log_param("pod_name", os.environ.get("HOSTNAME", "unknown"))

           if torch.cuda.is_available():
               mlflow.log_param("gpu_name", torch.cuda.get_device_name(0))
               gpu_mem = torch.cuda.get_device_properties(0).total_mem
               mlflow.log_param("gpu_memory_gb", f"{gpu_mem / 1e9:.1f}")

           class Net(nn.Module):
               def __init__(self):
                   super().__init__()
                   self.fc1 = nn.Linear(784, 256)
                   self.fc2 = nn.Linear(256, 128)
                   self.fc3 = nn.Linear(128, 10)

               def forward(self, x):
                   x = x.view(-1, 784)
                   x = torch.relu(self.fc1(x))
                   x = torch.relu(self.fc2(x))
                   return self.fc3(x)

           model = Net().to(device)
           transform = transforms.Compose([transforms.ToTensor()])
           train_data = datasets.MNIST(
               '/tmp/data', train=True, download=True, transform=transform
           )
           test_data = datasets.MNIST(
               '/tmp/data', train=False, transform=transform
           )
           train_loader = DataLoader(train_data, batch_size=128, shuffle=True)
           test_loader = DataLoader(test_data, batch_size=128)

           optimizer = optim.Adam(model.parameters(), lr=0.001)
           criterion = nn.CrossEntropyLoss()

           for epoch in range(5):
               model.train()
               total_loss = 0
               for data, target in train_loader:
                   data, target = data.to(device), target.to(device)
                   optimizer.zero_grad()
                   output = model(data)
                   loss = criterion(output, target)
                   loss.backward()
                   optimizer.step()
                   total_loss += loss.item()

               avg_loss = total_loss / len(train_loader)
               mlflow.log_metric("train_loss", avg_loss, step=epoch)
               print(f"Epoch {epoch+1}: Loss = {avg_loss:.4f}")

           # Test accuracy
           model.eval()  # Switch to evaluation mode
           correct = 0
           total = 0
           with torch.no_grad():
               for data, target in test_loader:
                   data, target = data.to(device), target.to(device)
                   output = model(data)
                   _, predicted = output.max(1)
                   total += target.size(0)
                   correct += predicted.eq(target).sum().item()

           test_acc = correct / total
           mlflow.log_metric("test_accuracy", test_acc)
           mlflow.pytorch.log_model(model, "model")
           print(f"Test accuracy: {test_acc:.4f}")
           print("Training complete! Model logged to MLflow.")
   ```

   ```bash
   kubectl apply -f training-configmap.yaml
   ```

2. **Create the training Job**
   ```yaml
   # Save as mlflow-training-job.yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: mlflow-gpu-training
     namespace: mlflow
   spec:
     template:
       spec:
         containers:
           - name: trainer
             image: nvcr.io/nvidia/pytorch:24.09-py3
             # The nvcr pytorch image ships with torch + torchvision but NOT mlflow.
             # Pin numpy<2 — the nvcr build links torchvision against numpy 1.x; pip's default
             # resolver upgrades to numpy 2.x when installing mlflow, which breaks torchvision
             # datasets with "RuntimeError: Numpy is not available".
             command: ["sh", "-c", "pip install --quiet 'numpy<2' 'mlflow>=3.1.0' boto3 && python /scripts/train.py"]
             env:
               # Points at the raw MLflow Deployment created in Task 3 step 6.
               # Service name: `mlflow`, port 5000. In-cluster DNS FQDN shown for clarity.
               - name: MLFLOW_TRACKING_URI
                 value: "http://mlflow.mlflow.svc:5000"
               # RustFS S3 endpoint for artifact uploads.
               - name: MLFLOW_S3_ENDPOINT_URL
                 value: "http://rustfs-svc.mlflow.svc:9000"
               - name: MLFLOW_S3_IGNORE_TLS
                 value: "true"
               - name: AWS_ACCESS_KEY_ID
                 valueFrom:
                   secretKeyRef:
                     name: rustfs-credentials
                     key: AWS_ACCESS_KEY_ID
               - name: AWS_SECRET_ACCESS_KEY
                 valueFrom:
                   secretKeyRef:
                     name: rustfs-credentials
                     key: AWS_SECRET_ACCESS_KEY
             volumeMounts:
               - name: training-script
                 mountPath: /scripts
             resources:
               requests:
                 cpu: "2"
                 memory: 4Gi
               limits:
                 nvidia.com/gpu: 1
         volumes:
           - name: training-script
             configMap:
               name: mlflow-training-script
         restartPolicy: Never
     backoffLimit: 2
   ```

   ```bash
   kubectl apply -f mlflow-training-job.yaml
   ```

3. **Monitor the training Job**
   ```bash
   # Watch job progress
   kubectl get jobs -n mlflow -w

   # Stream logs
   kubectl logs -n mlflow -l job-name=mlflow-gpu-training -f

   # Check completion
   kubectl get job mlflow-gpu-training -n mlflow \
     -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}'
   ```

### Task 6: Model Registry with Aliases (25 min)

MLflow 3.x replaces the stage-based model promotion workflow (Staging/Production/Archived) with a flexible alias system. Aliases are arbitrary string labels that point to specific model versions.

1. **Create the model registration script**
   ```python
   # Save as register_model.py
   import mlflow
   from mlflow import MlflowClient
   import os

   os.environ['MLFLOW_S3_ENDPOINT_URL'] = 'http://localhost:9000'
   os.environ['AWS_ACCESS_KEY_ID'] = 'mlflow'
   os.environ['AWS_SECRET_ACCESS_KEY'] = 'mlflow-s3cr3t'

   mlflow.set_tracking_uri('http://localhost:5000')
   client = MlflowClient()

   # Find the best run from our experiment
   experiment = client.get_experiment_by_name('gpu-training-experiments')
   runs = client.search_runs(
       experiment_ids=[experiment.experiment_id],
       order_by=["metrics.test_accuracy DESC"],
       max_results=1
   )

   if runs:
       best_run = runs[0]
       run_id = best_run.info.run_id
       test_acc = best_run.data.metrics.get('test_accuracy', 'N/A')
       print(f"Best run: {run_id}")
       print(f"Test accuracy: {test_acc}")

       # Register the model
       model_name = "mnist-classifier"
       model_uri = f"runs:/{run_id}/model"

       # create_registered_model is idempotent if model already exists
       try:
           client.create_registered_model(model_name)
           print(f"Created registered model: {model_name}")
       except mlflow.exceptions.MlflowException:
           print(f"Registered model '{model_name}' already exists")

       # Create a new model version
       mv = client.create_model_version(
           name=model_name,
           source=model_uri,
           run_id=run_id
       )
       print(f"Registered version: {mv.version}")

       # --- MLflow 3.x: Use aliases instead of stages ---
       # Set the "champion" alias to point to this version
       client.set_registered_model_alias(
           name=model_name,
           alias="champion",
           version=mv.version
       )
       print(f"Set alias 'champion' -> version {mv.version}")

       # You can also set a "challenger" alias for A/B testing
       client.set_registered_model_alias(
           name=model_name,
           alias="latest-gpu",
           version=mv.version
       )
       print(f"Set alias 'latest-gpu' -> version {mv.version}")

       # Retrieve model by alias
       champion = client.get_model_version_by_alias(model_name, "champion")
       print(f"\nChampion model: version {champion.version}")
       print(f"  Source: {champion.source}")
       print(f"  Run ID: {champion.run_id}")
   else:
       print("No runs found! Run train_with_mlflow.py first.")
   ```

   ```bash
   python register_model.py
   ```

2. **Load model by alias**

   The modern MLflow 3.x URI format uses `@alias` instead of `/Stage`:

   ```python
   # Save as load_model.py
   import mlflow
   import torch
   import os

   os.environ['MLFLOW_S3_ENDPOINT_URL'] = 'http://localhost:9000'
   os.environ['AWS_ACCESS_KEY_ID'] = 'mlflow'
   os.environ['AWS_SECRET_ACCESS_KEY'] = 'mlflow-s3cr3t'

   mlflow.set_tracking_uri('http://localhost:5000')

   # Load model using alias-based URI (MLflow 3.x)
   model = mlflow.pytorch.load_model("models:/mnist-classifier@champion")
   print(f"Loaded champion model: {type(model).__name__}")

   # Test with sample input
   sample = torch.randn(1, 1, 28, 28)
   model.cpu()
   with torch.no_grad():
       output = model(sample)
       predicted = output.argmax(dim=1).item()
       print(f"Sample prediction: {predicted}")
       print(f"Output logits: {output[0].tolist()}")
   ```

   ```bash
   python load_model.py
   ```

3. **Verify in the MLflow UI**
   - Navigate to the Models tab in the MLflow UI
   - Click on "mnist-classifier"
   - Verify the aliases ("champion", "latest-gpu") are shown
   - Each alias links to the correct model version

## Deliverables

- [ ] **Screenshot** of MLflow UI showing multiple experiment runs with GPU metrics
- [ ] **Screenshot** of Model Registry showing registered model with aliases
- [ ] **Training script** (`train_with_mlflow.py`) with MLflow 3.x integration
- [ ] **Kubernetes Job YAML** for GPU training with Secret-based credentials
- [ ] **Model registration script** using `set_registered_model_alias()` (not stages)
- [ ] **Inference test output** from loading model via `models:/name@champion` URI

## Verification Checklist

- [ ] MLflow server deployed and healthy (`/health` returns 200)
- [ ] RustFS S3 artifact store operational with `mlflow-artifacts` bucket
- [ ] PostgreSQL backend store accepting connections as user `mlflow`
- [ ] Experiments logged with metrics, parameters, and artifacts
- [ ] Model registered with alias-based promotion (not stage-based)
- [ ] Model loadable via `models:/mnist-classifier@champion` URI
- [ ] Credentials stored in Kubernetes Secrets (not ConfigMaps)

## Troubleshooting

### MLflow Server Not Starting

**Check logs:**
```bash
kubectl logs -n mlflow -l app=mlflow
```

**Verify database connection from the mlflow pod:**
```bash
kubectl exec -n mlflow deployment/mlflow -- \
  python -c "
import psycopg2
conn = psycopg2.connect('postgresql://mlflow:mlflow-pg-s3cr3t@postgresql.mlflow.svc:5432/mlflow')
print('Database connection: OK')
conn.close()
"
```

**Check health endpoint:**
```bash
# From inside the cluster
kubectl exec -n mlflow deployment/mlflow -- curl -s http://localhost:5000/health
```

**Did PostgreSQL auth fail with `password authentication failed for user "mlflow"`?** The Bitnami postgresql 18.3.0 chart used via kgst silently ignores the `auth.*` values in the MultiClusterService — the `mlflow` user and `mlflow` database may not exist. Re-run Task 3 step 4 (the manual `CREATE ROLE`/`CREATE DATABASE` block) and confirm `kubectl exec postgresql-0 -n mlflow -- psql -U postgres ...` shows the `mlflow` role in `\du`.

### Artifacts Not Uploading (403 / AccessDenied / connection refused)

**Check RustFS connectivity from the mlflow pod:**
```bash
kubectl exec -n mlflow deployment/mlflow -- \
  curl -s http://rustfs-svc.mlflow.svc:9000/
# Expected: an S3 XML ListAllMyBucketsResult response or a 403 SignatureDoesNotMatch
# (both confirm the S3 API is reachable; the 403 is expected because curl doesn't sign).
```

**Verify the S3 credentials mounted from the Secret:**
```bash
kubectl get secret rustfs-credentials -n mlflow -o jsonpath='{.data}' | \
  python3 -c "import sys,json,base64; d=json.load(sys.stdin); print({k:base64.b64decode(v).decode() for k,v in d.items()})"
```

**List the bucket directly with awscli (one-shot Pod):**
```bash
kubectl run rustfs-ls --rm -it --restart=Never -n mlflow \
  --image=amazon/aws-cli:latest \
  --env=AWS_ACCESS_KEY_ID=mlflow \
  --env=AWS_SECRET_ACCESS_KEY=mlflow-s3cr3t-8392nX \
  --env=AWS_DEFAULT_REGION=us-east-1 \
  -- --endpoint-url http://rustfs-svc.mlflow.svc:9000 s3 ls s3://mlflow-artifacts/ --recursive
```

### Training Job Fails

**Check pod events:**
```bash
kubectl describe job mlflow-gpu-training -n mlflow
kubectl get events -n mlflow --sort-by='.lastTimestamp' | tail -20
```

**Verify GPU access:**
```bash
kubectl exec -n mlflow -it $(kubectl get pod -n mlflow -l job-name=mlflow-gpu-training -o name | head -1) -- nvidia-smi
```

### Model Registry Errors

**If `transition_model_version_stage` fails:**
This method was removed in MLflow 3.x. Use the alias-based API:
```python
# Old (broken in MLflow 3.x):
# client.transition_model_version_stage(name, version, "Production")

# New (MLflow 3.x):
client.set_registered_model_alias(name, "champion", version)
```

**If `models:/name/Production` URI fails:**
The stage-based URI format is deprecated. Use the alias format:
```python
# Old (broken in MLflow 3.x):
# model = mlflow.pytorch.load_model("models:/mnist-classifier/Production")

# New (MLflow 3.x):
model = mlflow.pytorch.load_model("models:/mnist-classifier@champion")
```

## Key Takeaways

1. **k0rdent ServiceTemplate** (`mlflow-1-8-1`) provides one-command MLflow deployment across managed clusters
2. **MLflow 3.x aliases** replace the rigid four-stage model promotion with flexible, custom labels
3. **Kubernetes Secrets** (not ConfigMaps) should store database and S3 credentials
4. **The `/health` endpoint** is the correct readiness/liveness probe path for MLflow 3.x
5. **NVIDIA container images** (`nvcr.io/nvidia/pytorch`) provide pre-built GPU environments for training Jobs

## Next Lab

Choose your next elective track:

- **Compliance Track:** [Lab 5.11 - FIPS Compliance](lab-5.11-nvidia-fips.md)
- **Advanced Track:** [Lab 5.13 - TensorRT-LLM Optimization](lab-5.13-tensorrt-llm.md)
- **Or proceed to:** [Week 6 - Multi-tenancy](../../week-6-multi-tenancy/README.md)
