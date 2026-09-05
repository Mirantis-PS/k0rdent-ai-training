# KOF 1.6: authenticated cross-VPC metrics and logs

This baseline exposes one TLS endpoint for **writes** to the management cluster.
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
certificates covering the **actual NLB DNS name**. Keep the private CA on the
administration machine; only the public CA and client keypair go to the child.
Use organizational PKI and a rotation procedure for persistent environments.

```bash
umask 077
CERT_DIR=$(mktemp -d)
openssl req -x509 -newkey rsa:3072 -nodes -days 7 -subj /CN=kof-lab-ca \
  -keyout "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt"
openssl req -newkey rsa:3072 -nodes -subj "/CN=$INGEST_HOST" \
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

Save the current ConfigMap and annotation so the change can be reverted. Patch
only write endpoints; read endpoints are consumed within the management/storage
cluster and can retain their internal names.

```bash
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system get configmap "kof-cluster-config-$CLUSTER_NAME" -o yaml > /tmp/kof-endpoints-before.yaml
jq -n --arg host "$INGEST_HOST" '{data:{write_metrics_endpoint:("https://"+$host+"/metrics"),write_logs_endpoint:("https://"+$host+"/logs/v1/logs")}}' > /tmp/kof-endpoints-patch.json
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system patch configmap "kof-cluster-config-$CLUSTER_NAME" --type=merge --patch-file /tmp/kof-endpoints-patch.json
helm --kubeconfig "$WORKLOAD_KUBECONFIG" -n kof get values kof-collectors --all -o json > /tmp/kof-values.json
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system get cluster "$CLUSTER_NAME" -o json | jq -r '.metadata.annotations["k0rdent.mirantis.com/kof-collectors-values"] // "{}"' > /tmp/kof-annotation-before.yaml
python3 curriculum/examples/telemetry/prepare-kof-values.py --mode storage \
  --values /tmp/kof-values.json --existing /tmp/kof-annotation-before.yaml > /tmp/kof-ingest-values.yaml
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n kcm-system annotate cluster "$CLUSTER_NAME" \
  k0rdent.mirantis.com/kof-collectors-values="$(cat /tmp/kof-ingest-values.yaml)" --overwrite
```

Wait for KSM reconciliation. Inspect **all** child collector CRs for the TLS mounts
and the two HTTPS exporter endpoints. Test rejection without a client certificate,
then a successful empty OTLP log request with the client certificate:

```bash
curl --cacert "$CERT_DIR/ca.crt" -o /dev/null -w '%{http_code}\n' "https://$INGEST_HOST/logs/v1/logs"
curl --fail-with-body --cacert "$CERT_DIR/ca.crt" --cert "$CERT_DIR/client.crt" \
  --key "$CERT_DIR/client.key" -H 'Content-Type: application/json' \
  -d '{"resourceLogs":[]}' "https://$INGEST_HOST/logs/v1/logs"
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" run kof-ingest-probe --restart=Never \
  --image=busybox:1.37.0 -- sh -c 'echo KOF_CROSS_CLUSTER_PROBE; sleep 5'
```

Acceptance requires the probe log in management Grafana/VictoriaLogs **and** a
current child `up`/node metric labelled with the child cluster. Record both, and
confirm exporter failures stop increasing. A successful empty request or Running
collector alone is insufficient. A disconnected child is a failed ingest test.

After the exercise, restore the saved annotation and ConfigMap if reverting, then
delete the proxy Deployment, Service, ConfigMap and server/client Secrets. Wait for
AWS to remove the NLB before destroying management infrastructure. Remove the test
pod and securely remove the temporary certificate directory when no longer needed.
