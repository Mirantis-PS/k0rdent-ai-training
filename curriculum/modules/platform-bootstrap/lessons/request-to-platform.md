# Request to platform

Lesson ID: AI-CON-01 · Before AI-LAB-01 · Revisit in AI-LAB-07 and AI-CAP-01.

## The customer problem

Team A needs a private interactive assistant over approved documents; team B needs batch experiments and occasional fine-tuning; both share scarce accelerators. You deliver a repeatable service, explain its resource demand and restore it after failure. A text response alone doesn't establish availability, tenant separation or model quality.

Training changes parameters by computing gradients and applying an optimizer. Full fine-tuning changes existing weights; LoRA trains a small adapter and usually freezes the base weights; both still need the dataset stored and processed. Inference uses the resulting weights. RAG retrieves external content and passes it as context at inference time, without retraining. Batch inference aims to finish a finite workload; online inference adds latency and availability constraints. Before choosing infrastructure, ask who owns the data, artifacts, model evaluation and serving SLO.

## Just enough model anatomy

A tokenizer maps text to token IDs, which don't reliably match words; an embedding maps IDs to vectors. Transformer attention combines information across tokens using learned parameters. Context length counts input and generated tokens within model and runtime limits, and more context means more cache and prefill work at the same parameter count. A vector database indexes embeddings for retrieval and is separate from the model's KV cache, so a RAG workload can stress both storage and inference without any training.

## Trace two control paths

Draw the request path: private client → workload Service → serving process → tokenizer/model/GPU → response. Separately draw the desired-state path: versioned configuration → management controller → workload resources → reconciliation/status. Mark where the registry, object store, credentials, scheduler and telemetry enter. A healthy management cluster doesn't prove model readiness, and a running Pod doesn't prove a correct response.

The foundation labs demonstrate k0rdent management and workload cluster operations, not every capability of k0rdent AI. Record each component as native, integrated, optional, unsupported or unresolved, with a versioned source and controller owner. Until P3 supplies sources, label k0rdent AI ownership unresolved and use the k0rdent route only within its documented scope.

## Decision exercise

Classify five requests: answer an internal FAQ; create embeddings nightly; adapt style from approved examples; train a model from scratch; summarize a million existing documents. For each, name the changing artifacts, request pattern, persistent data, isolation need and one useful service metric, and explain why installing every ML platform tool wouldn't meet those needs. Revisit your answers when the capstone changes context length and concurrency.

## Source bridge

Go deeper with the [architecture](../theory/k0rdent-architecture.md), [components](../theory/k0rdent-components.md), [inference architecture](../../inference-and-data/theory/llm-inference-architecture.md) and the [technical source ledger](../../../references/pedagogy/sources.md).
