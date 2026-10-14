# Request to platform

Lesson ID: AI-CON-01. Read before AI-LAB-01; revisit in AI-LAB-07 and AI-CAP-01.

## The customer problem

Team A needs a private interactive assistant over approved documents. Team B needs batch experiments and occasional fine-tuning. They share scarce accelerators. The platform engineer must deliver a repeatable service, explain resource demand, and restore it after failure. A successful text response alone does not establish availability, tenant separation or model quality.

Training changes parameters by calculating gradients and applying an optimizer. Full fine-tuning changes existing weights; LoRA trains a smaller adapter while usually retaining frozen base weights. Neither makes the input dataset free to store or process. Inference uses the resulting weights. RAG retrieves external content and supplies it as context at inference time; it does not by itself retrain the model. Batch inference prioritizes completing a finite workload; online inference usually adds latency and availability constraints. Ask who owns data, artifacts, model evaluation and the serving SLO before choosing infrastructure.

## Just enough model anatomy

A tokenizer maps text to token IDs; tokens are not reliably equal to words. An embedding maps IDs to vectors. Transformer attention combines information across tokens; model parameters are learned values used in those computations. Context length counts input and generated tokens within the model/runtime limits. More context can require more cache and more prefill work even when parameter count stays constant. A vector database indexes embeddings for retrieval; it is not the inference model's KV cache. These distinctions explain why a RAG workload can stress both storage and inference without training anything.

## Trace two control paths

Draw the request path: private client → workload Service → serving process → tokenizer/model/GPU → response. Separately draw the desired-state path: versioned configuration → management controller → workload resources → reconciliation/status. Mark where the registry, object store, credentials, scheduler and telemetry enter. A management cluster being healthy does not prove model readiness. A running Pod does not prove a correct response.

The preserved foundation labs demonstrate k0rdent management and workload cluster operations. They do not establish every capability of a product called k0rdent AI. Record each component as native, integrated, optional, unsupported or unresolved, with a versioned source and controller owner. Until P3 supplies those sources, label k0rdent AI ownership unresolved; use the preserved k0rdent route only within its documented scope.

## Decision exercise

Classify five requests: answer an internal FAQ; create embeddings nightly; adapt style with approved examples; train a model from scratch; summarize a million existing documents. For each, identify changing artifacts, request pattern, persistent data, isolation need and one useful service metric. Then explain why installing every ML platform tool would not resolve those requirements. Revisit your choices when the capstone customer changes context length and concurrency.

## Source bridge

Use [architecture](../theory/k0rdent-architecture.md), [components](../theory/k0rdent-components.md), [inference architecture](../../inference-and-data/theory/llm-inference-architecture.md), and the [technical source ledger](../../../references/pedagogy/sources.md). This lesson supplies the missing operator-oriented entry point; it does not replace those sources.
