# KOF 1.6: authenticated cross-VPC metrics and logs

This baseline exposes one mutually authenticated TLS endpoint for telemetry writes and OpenCost metric queries to the management cluster.
It uses mutual TLS, a dedicated NGINX proxy and an AWS NLB; it does not expose the
unauthenticated storage Services directly. It creates billable AWS infrastructure
when you apply it. Trace forwarding and multi-region production design are separate
electives. Run from the repository root with kubectl, Helm, jq, OpenSSL, Python and
PyYAML available. The storage Service names match Lab 1.6; inspect them before use.

```bash
export MGMT_KUBECONFIG=$HOME/.kube/config
export WORKLOAD_KUBECONFIG=/tmp/managed-cluster-01.kubeconfig
export CLUSTER_NAME=managed-cluster-01
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kof get svc vminsert-cluster kof-storage-victoria-logs-cluster-vlinsert
kubectl --kubeconfig "$MGMT_KUBECONFIG" apply -f curriculum/examples/telemetry/ingest-gateway.yaml
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kof wait svc/kof-ingest-gateway \
  --for=jsonpath='{.status.loadBalancer.ingress[0].hostname}' --timeout=5m
INGEST_HOST=$(kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kof get svc kof-ingest-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

The proxy remains Pending until its TLS Secret exists. Issue short-lived lab
certificates covering the **actual NLB DNS name** in `subjectAltName`. Use a short Common Name: AWS NLB hostnames can exceed the certificate CN limit of 64 characters. Keep the private CA on the
administration machine; only the public CA and client keypair go to the child.
Use organizational PKI and a rotation procedure for persistent environments.

```bash
umask 077
CERT_DIR=$(mktemp -d)
openssl req -x509 -newkey rsa:3072 -nodes -days 7 -subj /CN=kof-lab-ca \
  -keyout "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt"
openssl req -newkey rsa:3072 -nodes -subj /CN=kof-ingest-gateway \
  -keyout "$CERT_DIR/server.key" -out "$CERT_DIR/server.csr"
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "$INGEST_HOST" > "$CERT_DIR/server.ext"
openssl x509 -req -in "$CERT_DIR/server.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
  -CAcreateserial -days 7 -extfile "$CERT_DIR/server.ext" -out "$CERT_DIR/server.crt"
openssl req -newkey rsa:3072 -nodes -subj "/CN=$CLUSTER_NAME" \
  -keyout "$CERT_DIR/client.key" -out "$CERT_DIR/client.csr"
printf 'extendedKeyUsage=clientAuth\n' > "$CERT_DIR/client.ext"
openssl x509 -req -in "$CERT_DIR/client.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
  -CAcreateserial -days 7 -extfile "$CERT_DIR/client.ext" -out "$CERT_DIR/client.crt"
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kof create secret generic kof-ingest-server \
  --from-file=tls.crt="$CERT_DIR/server.crt" --from-file=tls.key="$CERT_DIR/server.key" \
  --from-file=ca.crt="$CERT_DIR/ca.crt" --dry-run=client -o yaml | kubectl --kubeconfig "$MGMT_KUBECONFIG" apply -f -
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kof create secret generic kof-ingest-client \
  --from-file=tls.crt="$CERT_DIR/client.crt" --from-file=tls.key="$CERT_DIR/client.key" \
  --from-file=ca.crt="$CERT_DIR/ca.crt" --dry-run=client -o yaml | kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" apply -f -
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kof rollout status deployment/kof-ingest-gateway --timeout=5m
```

Save the current ConfigMap and annotation so the change can be reverted. Patch the write endpoints. OpenCost runs on the child and also needs a reachable read endpoint; management `.svc` DNS fails there. The pinned OpenCost process does not expose client-certificate environment settings, so a child-local NGINX proxy handles mTLS to the same gateway. It is a ClusterIP Service, with no additional load balancer.

```bash
sed "s/INGEST_HOST/$INGEST_HOST/g" curriculum/examples/telemetry/opencost-query-proxy.yaml | \
  kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" apply -f -
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kof rollout status deployment/kof-query-proxy --timeout=3m
```

```bash
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system get configmap "kof-cluster-config-$CLUSTER_NAME" -o yaml > /tmp/kof-endpoints-before.yaml
jq -n --arg host "$INGEST_HOST" '{data:{write_metrics_endpoint:("https://"+$host+"/metrics"),write_logs_endpoint:("https://"+$host+"/logs/v1/logs")}}' > /tmp/kof-endpoints-patch.json
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system patch configmap "kof-cluster-config-$CLUSTER_NAME" --type=merge --patch-file /tmp/kof-endpoints-patch.json

# Keep the hand-configured endpoint source discoverable by the KOF operator.
# This single-cluster lab uses management storage rather than a regional ClusterDeployment.
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system get configmap "kof-cluster-config-$CLUSTER_NAME" -o json |
  jq '{apiVersion:"v1",kind:"ConfigMap",metadata:{name:"kof-management",namespace:"kcm-system"},data:.data}' |
  kubectl --kubeconfig "$MGMT_KUBECONFIG" apply -f -
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system label clusterdeployment "$CLUSTER_NAME" \
  k0rdent.mirantis.com/kof-regional-cluster-name=management --overwrite
helm --kubeconfig "$WORKLOAD_KUBECONFIG" -n kof get values kof-collectors --all -o json > /tmp/kof-values.json
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system get cluster "$CLUSTER_NAME" -o json | jq -r '.metadata.annotations["k0rdent.mirantis.com/kof-collectors-values"] // "{}"' > /tmp/kof-annotation-before.yaml
python3 curriculum/examples/telemetry/prepare-kof-values.py --mode storage \
  --values /tmp/kof-values.json --existing /tmp/kof-annotation-before.yaml > /tmp/kof-ingest-values.yaml
python3 - <<'PY'
import yaml
p='/tmp/kof-ingest-values.yaml'
v=yaml.safe_load(open(p))
oc=v.setdefault('opencost',{}).setdefault('opencost',{})
oc.setdefault('prometheus',{}).setdefault('external',{}).update(enabled=True,url='http://kof-query-proxy.kof.svc:8080/prometheus')
oc.setdefault('exporter',{}).setdefault('startupProbe',{})['failureThreshold']=100
oc['exporter'].setdefault('extraEnv',{}).update(PROM_CLUSTER_ID_LABEL='cluster',CURRENT_CLUSTER_ID_FILTER_ENABLED='true')

collectors=v.setdefault('opentelemetry-kube-stack',{}).setdefault('collectors',{})
for name in ['daemon','target-allocator','controller-k0s']:
    tolerations=collectors.setdefault(name,{}).setdefault('tolerations',[
        {'key':'node-role.kubernetes.io/master','operator':'Exists','effect':'NoSchedule'}
    ])
    if not any(t.get('key')=='node-role.kubernetes.io/control-plane' for t in tolerations):
        tolerations.append({'key':'node-role.kubernetes.io/control-plane','operator':'Exists','effect':'NoSchedule'})
with open(p,'w') as f: yaml.safe_dump(v,f,sort_keys=False)
PY
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system annotate cluster "$CLUSTER_NAME" \
  k0rdent.mirantis.com/kof-collectors-values="$(cat /tmp/kof-ingest-values.yaml)" --overwrite
```

Wait for KSM reconciliation and each collector Deployment/DaemonSet rollout to finish before creating the probe. Inspect **all** child collector CRs for the TLS mounts
and the two HTTPS exporter endpoints. Test rejection without a client certificate,
then a successful empty OTLP protobuf log request with the client certificate. The pinned VictoriaLogs backend rejects OTLP JSON; an empty protobuf message is a valid empty export request:

```bash
curl --cacert "$CERT_DIR/ca.crt" -o /dev/null -w '%{http_code}\n' "https://$INGEST_HOST/logs/v1/logs"
curl --fail-with-body --cacert "$CERT_DIR/ca.crt" --cert "$CERT_DIR/client.crt" \
  --key "$CERT_DIR/client.key" -H 'Content-Type: application/x-protobuf' \
  --data-binary '' "https://$INGEST_HOST/logs/v1/logs"
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" run kof-ingest-probe --restart=Never \
  --image=busybox:1.37.0 -- sh -c 'for i in $(seq 1 24); do echo KOF_CROSS_CLUSTER_PROBE; sleep 5; done'
```

Acceptance requires the probe log in management Grafana/VictoriaLogs **and** a
current child `up`/node metric labelled with the child cluster. Query OpenCost with `aggregate=node` and verify that only child node names are returned. The [OpenCost shared-backend configuration](https://opencost.io/docs/installation/multi-cluster-single-source-of-data/) requires both the `cluster` label name and current-cluster filtering; HTTP 200 alone can hide mixed allocations. Record these results, and
confirm exporter failures stop increasing. A successful empty request or Running
collector alone is insufficient. A disconnected child is a failed ingest test.

After the exercise, restore the saved annotation and ConfigMap if reverting, then
delete the management `kof-ingest-gateway` and child `kof-query-proxy` Deployment, Service and ConfigMap, plus the server/client Secrets. Wait for
AWS to remove the NLB before destroying management infrastructure. Remove the test
pod and securely remove the temporary certificate directory when no longer needed.
