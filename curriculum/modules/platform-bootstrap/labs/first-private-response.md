# AI-LAB-01 — First private response

> **Course step 13 of 21.** [Previous step](../../gpu-allocation/labs/kai-scheduler.md) · [Course checklist](../../../README.md) · [Next step](../../gpu-systems/labs/memory-concurrency.md)

**Status:** [draft](../../../README.md#check-runtime-readiness) · **Profile:** GPU-1 candidate; CPU analysis only · **Guidance:** high, commands supplied

## Prerequisites and input state

- Course guide foundation and GPU entry steps, including the KAI transition.
- Instructor environment card with a qualified single-device model, image and dtype (a source four-GPU deployment isn't GPU-1).

## Objectives and problem

Serve one private response for team A and name every owning resource from desired state to GPU process. Tell service readiness from cluster health, and classify team B's needs without deploying extra tools.

## Concept capsule

Read [Request to platform](../lessons/request-to-platform.md), sketch the request and desired-state paths and complete its five-use-case classification.

## Hypothesis

Predict which observation proves the model loaded, which proves reachability and which proves a successful request. Why isn't a Ready node or Running Pod enough?

## Procedure and checkpoints

1. Copy the session template to a private evidence directory, set CTX, NS, DEPLOY and SVC from the card, confirm cluster identity with the instructor and record an object inventory.
2. Review the model access and server configuration approved from source [5.5](../../inference-and-data/labs/vllm-inference.md); model tokens stay in the existing secret mechanism. Deploy with the owner-approved manifest, one qualified GPU and private ClusterIP access, with no new product API or public Gateway. Without an approved manifest, mark deployment blocked and finish the diagram and configuration review.
3. Once the owning controller applies the desired state, collect conditions and startup logs and confirm the actual model revision and GPU allocation, not just the image tag.
4. Forward the Service and run the response check from a second terminal with the served model name. The example assumes port 8000; use the card's port if different. These are client commands, not a k0rdent AI installation.

```bash
: "${CTX:?set workload context}" "${NS:?set learner namespace}"
: "${DEPLOY:?set serving deployment}" "${SVC:?set private service}"
kubectl --context "$CTX" -n "$NS" get pods,services
kubectl --context "$CTX" -n "$NS" rollout status "deployment/$DEPLOY" --timeout=300s
kubectl --context "$CTX" -n "$NS" logs "deployment/$DEPLOY" --tail=100
kubectl --context "$CTX" -n "$NS" port-forward --address 127.0.0.1 "service/$SVC" 8000:8000
```

Second terminal (add the approved authentication if the service requires it):

```bash
curl --fail-with-body --max-time 20 http://127.0.0.1:8000/v1/models
: "${MODEL:?set exact served model name}"
export MODEL
REQUEST_JSON=$(mktemp "${TMPDIR:-/tmp}/ai-lab-01.XXXXXX")
python3 -c 'import json,os; print(json.dumps({"model":os.environ["MODEL"],"prompt":"Explain why a platform needs a readiness check in one sentence.","max_tokens":32,"temperature":0}))' > "$REQUEST_JSON"
curl --fail-with-body --max-time 120 -H 'Content-Type: application/json' --data-binary @"$REQUEST_JSON" http://127.0.0.1:8000/v1/completions
rm -- "$REQUEST_JSON"
```

Check HTTP success, a nonempty completion and token accounting. Save timestamps, the sanitized response, the workload owner and the management source revision. At the five-minute readiness deadline, stop and diagnose.

## Interpretation

- Which component generated the response?
- Where would a wrong model revision show up?
- What would a RAG request add in storage, retrieval and context cost?
- Which components are demonstrated k0rdent integrations, and which k0rdent AI classifications are unresolved?

## Bounded incident or tradeoff

Put a wrong Service name in the local port-forward only, compare its error with the healthy server status, then restore it. Don't alter shared Services.

## Declarative delivery

Save the approved desired-state revision and an ownership diagram. Link the server configuration to its catalog or template owner if documented; otherwise label the gap P3-SOURCES.

## Restoration and cleanup

Stop the port-forward, delete only the temporary request file and keep the service for AI-LAB-02. Record allocated GPUs and their expiry; don't run the source whole-cluster teardown.

## Evidence and acceptance

- Use-case classification and ownership trace (these pass alone as analysis).
- For runtime: exact versions, private response, model identity, GPU allocation, ownership path and retained-resource inventory.

A response copied from documentation doesn't pass.

## Provenance and instructor route

[Evidence contract](../../../references/pedagogy/evidence-contract.md) · [Instructor solutions](../../../instructor/pedagogical-v2/solutions.md#ai-lab-01)
