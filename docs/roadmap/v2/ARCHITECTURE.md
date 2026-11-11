# Joey 2.0 — Draft Media Intelligence Architecture

**Status:** Planning only. All runtime components below are candidates, not installed systems.

## Separation of responsibility

**Native SwiftUI UI**: Search entry, results, source navigation. Never interpret an inference result as production authorization.

**Swift application coordinator**: Validates source ownership, hash, transcript version, exact fractional time mapping, access, cancellation, job isolation, and available resource budget. No new production job states. Model output is untrusted data.

**Search library**: Local SQLite FTS5 index (model-independent); optional sidecar vectors indexed by immutable model and transcript provenance. Queries combine lexical/vector scores with deterministic deduplication. Search results refer back to original transcript segments, not generated passages.

**Inference adapter (optional)**: One allowlisted local model for embeddings, potentially direct local inference or a reviewed LocalAI installation bound to `127.0.0.1`. Separate methods for embeddings and conditional reranking; no general agents or model-generated tool calls. Verify model IDs, hashes, dimensions, response structure, timeout, cancellation, network isolation and resource limits. Do not implicitly reuse Ollama's chat API contract as if it were LocalAI's.

**Existing independent subsystems**: Swift media pipeline, local Whisper ASR, Ollama assistant, accepted media, Drive/rclone and required registers remain untouched. No model needed to run them.

## Suggested versioned index records

```
SourceRef: owner, source_id, source_sha256, authorization_scope
TranscriptRef: transcript_id, source_id, source_sha256, transcript_version
ChunkRef: chunk_id, transcript_id, ordered_segment_ids, start_s, end_s, exact_text_hash
EmbeddingRef: chunk_id, model_id, model_artifact_sha256, backend_id,
              prompt_version, chunker_version, vector_dimension, normalization
```

All fields are illustrative schema design, not current `Domain.swift` structures. Never make `start_s`/`end_s` a model-generated value. Maintain exact source identity and fractional interval references; validate rehydrated passages before display. Exclude/expire indexes when a source, transcript, or authorization changes. Ensure file path traversal and cross-owner access cannot escape approved storage.

## Model-free operation

FTS5 remains usable with all optional inference disabled. Service outage, invalid model identity, timeout, OOM or malformed JSON must degrade only optional retrieval/reranking—not existing production, rendering, export, archive filing or current completion states. Keep sidecars rebuildable, separate from original and canonical job data.

## Security and operation

- Strict loopback and outbound network-denied sandbox during inference; inspect all backend descendants, DNS, lazy model installation and failover configuration.
- Existing authorized Drive/rclone and Sheets network connections continue outside model prompts and credentials.
- Minimal local inference endpoint allowlist; no administrator credentials in the app; no tool execution, MCP, remote model registry, auto-download, or network callbacks during operation.
- Model cache and index use application-owned disk outside synchronized Drive folders, with bounded storage, atomic writes, provenance and recovery tests.
- Indexing prioritizes low resource usage, cancellation and foreground UI responsiveness. Exports/ASR should take precedence over optional indexing.
- Track versioned quality and performance evidence before promotion; never infer completion from a model response.
