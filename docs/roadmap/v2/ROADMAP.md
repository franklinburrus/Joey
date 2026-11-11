# Joey 2.0 — Media Intelligence Roadmap

**Status:** DRAFT / EXPLORATORY. Not approved for implementation.  
**Prepared:** November 11, 2026.  
**Repository:** `franklinburrus/Joey`  
**Recommended storage after review:** `docs/roadmap/v2/` on an isolated branch named `planning/joey-v2-media-intelligence`; do not merge into `main` until explicitly approved.  
**Inspected GitHub baseline:** `main` at `b7f4ce5df656d02b17a8c2cabc74ff0d63df7da4`.  
**Authoritative current product specification:** `docs/REQUIREMENTS.md` on the actual current Joey checkout. This roadmap does not amend it.

## Decision

Finish and stabilize Joey's current native macOS production implementation first. Preserve every existing media pipeline, accepted output, source archive, transcript, provenance link, recovery checkpoint, credential boundary, and verified Drive record. Stage potential local-AI enhancements as a separately governed Version 2.0 product track. No new service, model download, code change, repository branch, commit, deployment, or production processing is authorized by this roadmap itself.

**Product theme:** *Media Intelligence* — the ability to find, understand, and navigate authorized recordings without compromising deterministic production. LocalAI is an optional inference provider, not the product architecture.

## Current state — preserved, not rebuilt

Current repository evidence supports:

- Native Swift/SwiftUI application and durable Swift coordinator, with local FFmpeg/FFprobe, yt-dlp, Google Drive/rclone, and required registration workflows.
- Existing source-bound timestamped transcripts from an installed local MLX Whisper/faster-whisper helper.
- `Planning.swift` and `Editorial.swift`: deterministic duration, coverage, exclusions, and boundaries. Model-independent local processing remains available.
- `ClipIntelligence.swift`: deterministic evidence-backed clip recommendations and boundary advisories, not a validated model prediction of performance.
- `LocalAssistant.swift` and `LocalAssistantService.swift`: optional explicitly started, loopback-only Ollama `qwen3:4b`; no model-generated tool execution.
- Current landscape-native-video and creator-specific delivery requirements, including the distinct Joe Budden exception. Historical October 31 portrait-native reference material is superseded. Refer only to current `docs/REQUIREMENTS.md` when implementing.

The inspected code does **not establish** a complete cross-episode semantic transcript search feature; absence of search in a bounded inspection is not proof about every uninspected branch, plugin, or local helper.

## Release boundaries

| Track | Outcome | Explicit boundary |
| --- | --- | --- |
| **1.0 current build** | Complete authorized repairs, Mac acceptance, and production/reconciliation gates. | No new LocalAI or semantic-search work inserted into the current build. |
| **2.0 (proposed core)** | Search approved source-linked transcripts by meaning; accurate source navigation; lexical fallback. | Read-only discovery; no changes to accepted clips or production status. |
| **2.0.x (conditional)** | Optional search reranking and relevance tuning. | Only if measured quality improvement justifies memory, latency and maintenance. |
| **2.1 (candidate)** | Evidence-grounded editorial drafts; optional TTS previews; speech segmentation research. | Separate opt-in feature authorizations; never edit or publish accepted media by model output. |
| **2.2 (candidate)** | Selected-frame scene/thumbnail and source-navigation hints. | Bounded frames; no automated cropping, identity claims, or production alterations. |

These are planning labels, not a committed release schedule.

## P1 — Local semantic search, first proposed 2.0 feature

**Outcome:** An editor asks, “Find episodes where Dub talks about owning your work,” and receives original source excerpts, creator, source identity, exact start/end timestamps, and navigation to the source recording. No generated summaries required.

**Design:** From valid canonical transcript segments, create bounded overlapping, source-linked chunks with immutable source ID and SHA-256, creator, transcript identity/version, segment references, and exact fractional times. Build an SQLite FTS5 lexical index. Optionally build a local embedding index with frozen model ID/hash, vector dimension, chunking version, normalization and prompt settings. Search by hybrid lexical/vector retrieval, deterministic deduplication, and actual-source navigation. Remove derived entries when authorization, source identity, or transcript changes invalidate them. Keep original transcripts unchanged.

**Candidate software/models and observed report licenses (reconfirm specific artifacts before use):**

- SQLite FTS5 — SQLite public domain; no model, lexical search and fallback.
- `BAAI/bge-small-en-v1.5` — MIT; preferred small English embedding candidate.
- `ibm-granite/granite-embedding-107m-multilingual` — Apache-2.0; only if multilingual search is justified.
- `Qwen/Qwen3-Embedding-0.6B` — Apache-2.0; larger comparison only after testing small models.
- LocalAI server — MIT; optional local serving layer, not a requirement. Compare with direct native local inference first.

**Mac M1 / 16 GB:** A small embedding model with modest chunk/batch sizes is plausible, not measured. Model weight size is not end-to-end resident memory. Use bounded serialized inference; pause indexing when ASR, rendering or the existing Ollama assistant uses resources. Measure memory pressure, swap and UI responsiveness before approval.

**Fallback:** SQLite FTS5 exact/keyword search without model or LocalAI. Production processing continues without any search service.

**Risks:** semantic false matches, ambiguous transcript context, wrong source time, index/source version drift, accidental creator mixing, private transcript leakage through logs, network traffic from hidden backend downloads, and memory contention.

## P2 — Optional reranking

**Outcome:** Improve ordering of initially retrieved passages without changing evidence or source metadata.

**Candidate:** `cross-encoder/ms-marco-MiniLM-L6-v2`, reported Apache-2.0. Evaluate only on top 10–30 source-identified passages. LocalAI documents `/v1/rerank`, but its backend support and native macOS packaging require testing. Never interpret scores as probabilities.

**Fallback:** Original FTS5+vector ordering, or FTS5-only if inference is unavailable. Do not ship unless relevance improves and latency/memory remains acceptable.

## P3 — Grounded editorial discovery, optional

**Outcome:** From a user-supplied editorial brief, identify related moments across approved sources with textual evidence and candidate clip times. Avoid duplicating already accepted deterministic titles, captions, scores, or planning.

**Candidate:** First evaluate a narrowly scoped prompt with Joey's existing local Ollama Qwen model, not a second copy or replacement runtime. Suggested output contains source ID, exact timestamps, evidence segment IDs, draft title and rationale. The Swift application validates source identity, all evidence references, time bounds, and allowable fields; rejects unsupported assertions. Model output must not execute a tool or mutate any production job, accepted cut, upload, or record.

**Fallback:** Existing deterministic `ClipIntelligence` recommendations and source-linked lexical retrieval. These editorial suggestions are a separate optional review surface, **not** a routine human-QA gate imposed on current full-show production.

## Later candidates: separate product cases

- **2.1 audio:** Kokoro-82M (reported Apache-2.0) for *preview-only* text-to-speech, with separate voice/phonemizer rights checks. Silero VAD (reported MIT) may identify speech intervals; it does not validate cuts or speakers. Diarization remains unapproved until a complete locally operable, license-reviewed backend is identified; speaker IDs are not verified real identities. Existing Whisper/MLX stays first-line; a whisper.cpp alternative must beat the baseline.
- **2.2 visual:** SmolVLM2-2.2B-Instruct (reported Apache-2.0) for selectively sampled frames if performance and projector/backend compatibility are proven. No facial identity recognition, autonomous cropping, publication safety judgments, or generated imagery in current DUB/Taxstone native output.

## Explicit out of scope

Paid or hosted inference; cloud/freemium API dependence; secret model/service keys; unapproved internet egress; large autonomous agent stacks; remote MCP servers, terminals, shell or account tools; unreviewed model marketplaces; mass image/video generation; voice cloning; facial identification; automatic social publishing or scheduling; replacing ASR, Ollama or clipping logic without evidence; altering source-only presentation; modifying existing archives, accepted jobs, provenance, manifests, Drive permissions, or current requirements.

## Decision gates

1. **1.0 preservation:** Current product acceptance remains independently governed by current `docs/REQUIREMENTS.md` and verified operational state. No source/record/media change from 2.0 exploration.
2. **Source/model legal clearance:** Capture exact artifact revisions, URLs, license/NOTICE, derivative/voice rights, native backend license, dependency licenses, hash, and any conversion provenance. Report unknowns as blockers, not approvals.
3. **Locality/security:** All inference stays on the Mac, including retries/failover; no remote backend. Network-disabled post-install runs pass. Authorized Drive/rclone storage remains separately governed. No Drive credentials enter prompts or inference logs.
4. **Performance:** Baseline and candidate measured under actual M1/16 GB representative Joey workload; bounded concurrency, no serious swapping, UI starvation, lost progress, or export regression.
5. **Truth and isolation:** Every result opens the correct source time; no mismatched source/hash/creator, stale vectors, invented quotations, or unauthorized cross-source disclosure.
6. **Fallback and recovery:** Remove/stop LocalAI or corrupt the optional index; lexical search and existing production remain usable. Sidecars are rebuildable; originals and transcripts preserved.
7. **User value:** At least 30 realistic editorial queries with labeled relevant source intervals. Starting target: >=80% answerable queries have relevant top-five hit and no material exact-name regression; compare quality against keyword baseline, report precision/recall and false positive cases. Targets may be revised only after baseline evidence.
8. **Promotion:** Independent review of benchmarks, data integrity, security, lifecycle, and scope. No production enablement without new explicit approval.

## Small proof-of-concept (planning only)

- Select 3–5 **authorized** canonical transcripts spanning creators; record source ID/hash, transcript version and fixed query-to-evidence gold labels. Work on an isolated local copy of derived text only, not production source files.
- Build read-only SQLite FTS5 baseline and compare a single approved small embedding model through one **optional** backend. Record indexing/search timing, process RSS/physical footprint where available, system pressure and observed outbound connections.
- Run >=30 queries with exact-name, paraphrase, short phrase, negation, and no-answer cases. Ensure click-through exact timestamps, no creator leakage, invalidation on source change and model-version mismatch, safe empty/malformed responses and cancellation.
- Create a reproducible evidence bundle with before/after metrics and a Go/No-Go decision. Do not ship a feature by passing only smoke tests.

## Supporting evidence and handoff

- LocalAI assessment (22 pages): `https://drive.google.com/file/d/1ayRlti8uNTC7m8_bVHQAVk51V2HHmHeK/view` (read Nov 11, 2026).
- LocalAI documentation: `https://localai.io/docs/index.html` (capabilities are candidates, not established Joey integrations).
- Joey source baseline: `https://github.com/franklinburrus/Joey/tree/b7f4ce5df656d02b17a8c2cabc74ff0d63df7da4`.
- Preserve current `docs/REQUIREMENTS.md`, `docs/STATUS.md`, `AGENTS.md` and local uncommitted work as authority. Re-verify all on actual local checkout before implementing.

**Current action state:** Plan prepared for owner review. No implementation, benchmark, model installation, Git branch, commit, deployment, cloud or Drive write performed.
