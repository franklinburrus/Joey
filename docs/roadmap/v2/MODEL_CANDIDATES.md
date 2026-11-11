# Joey 2.0 — Model and License Candidate Register

**Status:** Research candidates. Reported upstream license is not a final clearance of exact weights, conversions, tokenizer/voice assets, dependencies or commercial-media rights. Confirm exact release, artifacts, provenance and licenses before any download or integration.

| Candidate | Proposed use | License reported by assessment | Resource/fit considerations | Decision |
| --- | --- | --- | --- | --- |
| SQLite FTS5 | Lexical retrieval; model-free fallback | Public domain (SQLite) | Small on-device database; benchmark at library scale | P1 default |
| LocalAI | Optional loopback inference API | MIT (server) | Extra process, lifecycle, packaging and backend validation | Compare, not required |
| `BAAI/bge-small-en-v1.5` | English embeddings | MIT | Small initial retrieval model; quantify exact installed backend RSS | P1 first model trial |
| `ibm-granite/granite-embedding-107m-multilingual` | Multilingual embeddings | Apache-2.0 | More language coverage; separate evaluation set | P1 alternative |
| `Qwen/Qwen3-Embedding-0.6B` | Embedding alternative | Apache-2.0 | Larger memory/time footprint, first smaller candidates | Later comparison |
| `cross-encoder/ms-marco-MiniLM-L6-v2` | Rerank first 10–30 results | Apache-2.0 | May require additional Python backend; validate native arm64 | P2 conditional |
| Current Ollama `qwen3:4b` | Grounded editorial drafting | Apache-2.0 for model family; confirm installed artifact | Already integrated locally; not a new model | P3 first test |
| `hexgrad/Kokoro-82M` | Optional TTS previews | Apache-2.0 reported | Voice assets, phonemizer/dependencies require independent rights/QA | 2.1 candidate |
| `snakers4/silero-vad` | Speech intervals | MIT | Test quiet speech, music, time offsets; not a clip or speaker truth oracle | 2.1 research |
| Diarization backend | Anonymous speaker-turn indexing | **Not selected, license unknown** | Gated and auxiliary assets may preclude completely offline setup | Hold |
| `HuggingFaceTB/SmolVLM2-2.2B-Instruct` | Selected-frame metadata | Apache-2.0 reported | Verify backend+vision projector+memory on M1/16 GB | 2.2 conditional |

Source register: Joey LocalAI Integration Review, pages 6–13 and 19–22: https://drive.google.com/file/d/1ayRlti8uNTC7m8_bVHQAVk51V2HHmHeK/view

## Before adoption, record per artifact

Name; source URL; precise revision; model-format/quantization hash and conversion history; license/NOTICE for model, backend, tokenizer, assets and dependencies; Apple arm64 compatibility; local service security; download location; inference egress restrictions; measured cold/warm latency; measured memory pressure/RSS/swap; supported vector dimension/prompt convention; cancellation behavior; rollback copy; approval decision.

**No installation, download, execution, license clearance or Mac benchmark has been performed by this roadmap.**
