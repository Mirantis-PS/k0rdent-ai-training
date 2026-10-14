# AI-LAB-01 — First private response

**Status:** educational draft; no GPU execution claimed. **Profile:** GPU-1 candidate; CPU analysis only. **Guidance:** high; command scaffold.

## Prerequisites and input state

Complete the foundation and GPU entry sequence in the learner path, including source KAI transition. Instructor supplies a qualified single-device model/image/dtype and environment card. A source four-GPU deployment is not automatically a GPU-1 deployment. P3 blocks unknown product-native installation; P4 blocks unqualified hardware/model execution.

## Objectives and problem

Deliver one private response for team A and locate every owning resource between desired state and GPU process. Distinguish service readiness from cluster health. Classify team B’s batch/training needs without deploying unrelated tools.

## Concept capsule

Read [Request to platform](../lessons/request-to-platform.md). Sketch request and desired-state paths before touching a cluster. Complete its five-use-case classification exercise.

## Hypothesis

Predict which observable condition proves the model loaded, which proves network reachability, and which proves a successful request. Write why a Ready node or Running Pod alone is insufficient.

## Procedure and checkpoints

1. Copy the session template to a private evidence directory. Set CTX, NS, DEPLOY and SVC from the environment card; verify the displayed cluster identity with the instructor. Record an initial object inventory.
2. Inspect the approved source 5.5 model access and server configuration. Keep model access tokens in the existing secret mechanism. Use the owner-approved serving manifest, one qualified GPU and private ClusterIP access. Do not install a new product API or reuse the source public Gateway as a convenience. If no approved manifest exists, mark deployment blocked and finish the diagram/config review.
3. After the owning controller applies the approved desired state, collect conditions and startup logs. Confirm the actual model revision and GPU allocation, not just the image tag.
4. Forward the approved Service locally. Run the response check from another terminal, with the model name returned by the server. The example assumes the approved Service exposes port8000; use the card’s port if different. These are inspection/client commands, not a k0rdent AI installation procedure.

```bash
: "${CTX:?set workload context}" "${NS:?set learner namespace}"
: "${DEPLOY:?set serving deployment}" "${SVC:?set private service}"
kubectl --context "$CTX" -n "$NS" get pods,services
kubectl --context "$CTX" -n "$NS" rollout status "deployment/$DEPLOY" --timeout=300s
kubectl --context "$CTX" -n "$NS" logs "deployment/$DEPLOY" --tail=100
kubectl --context "$CTX" -n "$NS" port-forward --address 127.0.0.1 "service/$SVC" 8000:8000
```

In the second terminal (use the approved authentication mechanism if the service requires one):

```bash
curl --fail-with-body --max-time 20 http://127.0.0.1:8000/v1/models
: "${MODEL:?set exact served model name}"
export MODEL
REQUEST_JSON=$(mktemp "${TMPDIR:-/tmp}/ai-lab-01.XXXXXX")
python3 -c 'import json,os; print(json.dumps({"model":os.environ["MODEL"],"prompt":"Explain why a platform needs a readiness check in one sentence.","max_tokens":32,"temperature":0}))' > "$REQUEST_JSON"
curl --fail-with-body --max-time 120 -H 'Content-Type: application/json' --data-binary @"$REQUEST_JSON" http://127.0.0.1:8000/v1/completions
rm -- "$REQUEST_JSON"
```

Check HTTP success, nonempty completion and token accounting. Save timestamps and sanitized response. Record the workload object’s owner and management source revision. Stop on the five-minute readiness deadline; diagnose rather than retrying indefinitely.

## Interpretation

Which component generated the response? Where would a wrong model revision be detected? Would a RAG request add storage, retrieval and context costs? Explain which components are demonstrated k0rdent integrations and which k0rdent AI classifications remain unresolved.

## Bounded incident or tradeoff

Use an incorrect Service name only in the local port-forward command. Observe the local error; compare it with the healthy server status. Restore the correct name. Do not delete or alter shared Services to simulate a network incident.

## Declarative delivery

Save the approved desired-state file/revision and a resource ownership diagram. Link the server configuration to its catalog/template owner if documented; otherwise label the integration gap P3-SOURCES.

## Restoration and cleanup

Stop the port-forward with Ctrl-C, remove only the local temporary request file, and retain the known-good private service for AI-LAB-02. Record GPU resources still allocated and their expiry. Do not run source whole-cluster teardown.

## Evidence and acceptance

Accept the reasoning exercise independently. Runtime acceptance additionally requires exact versions, private response, model identity, GPU allocation, ownership path and retained-resource inventory. A saved sample response from documentation does not pass.

## Provenance and instructor route

Derived from [Lab 1.1](provision-k0rdent.md), [Lab 1.5](provision-managed-cluster.md), [Lab 5.1](../../gpu-systems/labs/gpu-cluster-setup.md), [Lab 5.2](../../ai-service-delivery/labs/service-catalog.md) and [Lab 5.5 Tasks 1–4](../../inference-and-data/labs/vllm-inference.md). Original provisioning and serving bodies remain intact.

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Learner path](../../../learning-paths/pedagogical-v2.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-01)
