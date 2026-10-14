# Lab 1.7: Multi-Cluster Service Deployment

**Duration:** 2 hours · **Type:** Hands-on lab

## Objectives and prerequisites

Deploy a baseline through MultiClusterService, prove policy behavior, change its
values, and observe how label selection changes the rollout scope. Validate a
workload HTTP route through Gateway API. Keep the managed cluster and KOF running
through Labs 1.8 and 1.9; teardown happens after audit acceptance.

Complete Labs 1.1–1.6, including kof-child. Its cert-manager release already owns
the certificate CRDs: do not install a second cert-manager release. This baseline
uses Kyverno and Envoy Gateway. Community ingress-nginx retired in March 2026;
legacy migration analysis is outside this exercise.

Commands run in Bash on the management host. Keep kubeconfig explicit when changing
between management and workload clusters.

```bash
export MGMT_KUBECONFIG=$HOME/.kube/config
export WORKLOAD_KUBECONFIG=/tmp/managed-cluster-01.kubeconfig
export KUBECONFIG=$MGMT_KUBECONFIG
kubectl get clusterdeployment managed-cluster-01 -n kcm-system
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" get nodes
```

## Part 1: Select and inspect a ServiceTemplate

Browse [the service catalog](https://catalog.k0rdent.io/). Compare chart version,
application version, support tier, values, and upstream lifecycle. Record one
integration useful to your team and explain its support requirements. A support
tier is not necessarily a license restriction.

Reuse the catalog repository and Kyverno template from Lab 1.2:

```bash
kubectl get helmrepository k0rdent-catalog -n kcm-system
kubectl get servicetemplate kyverno-3-8-1 -n kcm-system -o yaml
```

Require VALID=true before proceeding. If missing, create the Kyverno template using
Lab 1.2. The catalog Kyverno chart wraps the upstream chart, so its values must be
nested under **kyverno:**. Inspect dependency names before applying this pattern to
another catalog chart; a silently ignored override can look like a successful install.

## Part 2: Deploy the baseline

MultiClusterService is cluster-scoped. Its selector matches ClusterDeployment
metadata labels, not the labels inside the template's configuration.

```bash
kubectl label clusterdeployment managed-cluster-01 -n kcm-system environment=training --overwrite
cat <<EOF | kubectl apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: MultiClusterService
metadata:
  name: baseline-services
spec:
  clusterSelector:
    matchLabels:
      environment: training
  serviceSpec:
    services:
    - template: kyverno-3-8-1
      name: kyverno
      namespace: kyverno
      values: |
        kyverno:
          admissionController:
            replicas: 1
    priority: 100
EOF
```

```bash
kubectl wait multiclusterservice/baseline-services --for=condition=Ready --timeout=5m
kubectl get multiclusterservice baseline-services -o yaml
kubectl get servicesets -n kcm-system
kubectl get clustersummaries -A
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kyverno get deployments
```

Require the matching cluster to be deployed and every Kyverno Deployment available.
Trace the MCS through its ServiceSet and Sveltos ClusterSummary to the Helm release.
Management-side acceptance does not prove that the child service works.

## Part 3: Validate certificate issuance and policy results

### Certificate issuance

Use the cert-manager installed by kof-child in namespace **kof**. Wait for issuance
before inspecting the TLS Secret:

```bash
export KUBECONFIG=$WORKLOAD_KUBECONFIG
kubectl -n kof get pods | grep cert-manager
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-cert-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - test.example.com
EOF
kubectl wait certificate/test-cert --for=condition=Ready --timeout=120s
kubectl get secret test-cert-tls
kubectl delete certificate test-cert
kubectl delete clusterissuer selfsigned-issuer
kubectl delete secret test-cert-tls
```

### Policy violation and remediation

Audit mode admits a violating Pod and reports it. Scope this teaching policy to a
disposable namespace. Production enforcement needs a rollout and exception policy.

```bash
kubectl create namespace policy-test
cat <<'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Audit
  rules:
  - name: check-for-labels
    match:
      any:
      - resources:
          kinds: [Pod]
          namespaces: [policy-test]
    validate:
      message: "label 'app' is required"
      pattern:
        metadata:
          labels:
            app: "?*"
EOF
kubectl wait clusterpolicy/require-labels --for=condition=Ready --timeout=120s
kubectl run test-pod -n policy-test --image=nginx:1.28.0 --restart=Never
kubectl get pod test-pod -n policy-test --show-labels
```

The generated **run=test-pod** label does not satisfy **app**. PolicyReports are
asynchronous: inspect the report whose scope is this Pod. Allow up to two minutes
for each expected result:

```bash
kubectl get policyreport -n policy-test -o json | jq '
  .items[] | select(.scope.name == "test-pod") |
  .results[] | select(.policy == "require-labels") | {rule,result,message}'
# Require result=fail, then remediate:
kubectl label pod test-pod -n policy-test app=test-pod
# Repeat the query above; require result=pass before cleanup.
```

Record both results and explain why the Pod was admitted in both cases.

```bash
kubectl delete namespace policy-test
kubectl delete clusterpolicy require-labels
export KUBECONFIG=$MGMT_KUBECONFIG
```

## Part 4: Update values and change rollout scope

Change one service entry without replacing the entire services array:

```bash
cat > /tmp/kyverno-values-patch.json <<'EOF'
[{"op":"replace","path":"/spec/serviceSpec/services/0/values","value":"kyverno:\n  admissionController:\n    replicas: 2\n"}]
EOF
kubectl patch multiclusterservice baseline-services --type=json --patch-file=/tmp/kyverno-values-patch.json
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kyverno get deployment kyverno-admission-controller
```

Wait for two available replicas. A merge patch replaces a supplied services array;
inspect its complete contents before using that approach on a multi-service MCS.

Add an opt-in selector before applying its matching label:

```bash
kubectl patch multiclusterservice baseline-services --type=merge \
  -p '{"spec":{"clusterSelector":{"matchLabels":{"policy-enabled":"true"}}}}'
kubectl get multiclusterservice baseline-services
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kyverno get deployments
```

Both **environment=training** and **policy-enabled=true** are now required.
Wait for zero matching clusters and removal of the Kyverno Deployments, then opt in:

```bash
kubectl label clusterdeployment managed-cluster-01 -n kcm-system policy-enabled=true
kubectl get multiclusterservice baseline-services
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" -n kyverno get deployments
```

Require one deployed match and the restored two-replica admission controller.
A selector change can uninstall a service: review its blast radius.

## Part 5: Dependencies and version paths

On a separate MCS with a real application that requires this baseline, use
**spec.dependsOn: [baseline-services]**. This orders MCS reconciliation; it does not
replace application readiness checks. **serviceSpec.priority** resolves competing
ownership of the same release, not deployment order among unrelated services.

Inspect **status.servicesUpgradePaths** on the MCS and installed ServiceTemplateChains.
Do not invent an upgrade version to complete an exercise. Lab 1.8 separates
management, cluster, and service upgrade mechanisms.

## Part 6: Validate an HTTP route on the child

Kyverno above is centrally managed. This routing exercise uses the upstream Envoy
chart directly. Follow the pinned [installation procedure](https://gateway.envoyproxy.io/v1.8/install/install-helm/).
The LoadBalancer creates billable AWS infrastructure. The new child from Lab 1.5
does not have provider-managed Gateway API CRDs.

```bash
export KUBECONFIG=$WORKLOAD_KUBECONFIG
helm upgrade --install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
  --version v1.8.4 -n envoy-gateway-system --create-namespace --wait --timeout 5m
```

For an existing Envoy installation, follow the upstream CRD upgrade procedure first.

```bash
kubectl create deployment gateway-test --image=nginx:1.28.0
kubectl expose deployment gateway-test --port=80
cat <<'EOF' | kubectl apply -f -
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
  name: training-gateway
  namespace: default
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
  name: gateway-test
  namespace: default
spec:
  parentRefs:
  - name: training-gateway
  hostnames:
  - gateway-test.example.com
  rules:
  - backendRefs:
    - name: gateway-test
      port: 80
EOF
kubectl rollout status deployment/gateway-test --timeout=180s
```

```bash
kubectl wait gateway/training-gateway --for=condition=Programmed --timeout=5m
kubectl get httproute gateway-test -o jsonpath='{.status.parents[*].conditions}'
HOST=$(kubectl get gateway training-gateway -o jsonpath='{.status.addresses[0].value}')
curl --fail --max-time 20 -H 'Host: gateway-test.example.com' "http://$HOST"
```

Require Accepted and ResolvedRefs for the route and an actual nginx HTTP response.
A newly assigned ELB name can take several minutes to resolve; retry after checking
load-balancer instance health. Resource creation alone does not pass this test.

## Cleanup and acceptance

Keep the route, baseline and child through Lab 1.8's continuity checks.
After Lab 1.9, remove them before deleting the ClusterDeployment:

```bash
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" delete httproute gateway-test
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" delete gateway training-gateway
kubectl --kubeconfig "$WORKLOAD_KUBECONFIG" delete service,deployment gateway-test
kubectl --kubeconfig "$MGMT_KUBECONFIG" delete multiclusterservice baseline-services
# Wait for the Gateway's AWS load balancer to disappear before deleting its controller.
helm --kubeconfig "$WORKLOAD_KUBECONFIG" uninstall envoy-gateway -n envoy-gateway-system
```

- [ ] Template valid and MCS deployed to the selected cluster.
- [ ] Certificate Ready and TLS Secret created.
- [ ] Exact test Pod reports fail, then pass after remediation.
- [ ] Desired replica change reaches the child.
- [ ] Opt-out uninstalls and opt-in restores the baseline.
- [ ] Gateway and route conditions pass; external HTTP serves the application.
- [ ] Explain dependencies, conflicting release ownership, and selector blast radius.

Continue to [Lab 1.8: Upgrade k0rdent Enterprise](lab-1.8-upgrade-k0rdent.md), then
[Lab 1.9: API audit logging](lab-1.9-api-audit-logging.md) before teardown.
