# Joey 2.0 — Proposed Acceptance Plan

**State:** Planning draft. Testing is not authorized or performed by this document.

## Preparation / preflight

1. Reconfirm actual Joey local folder, `origin`, checked-out branch, HEAD, uncommitted work, current specification, installed app and resource budget. Protect existing 1.0 baseline, active jobs, accepted outputs and archival copies.
2. Pin a known authorized set of 3–5 sources and their canonical transcripts; verify original source hash, owner, transcript version, exact timestamp/segment binding, and access rights.
3. Build a human-labeled search query dataset (at least 30 queries), covering exact names, paraphrases, topics, negation, ambiguous terms, slang and no-answer cases. Keep test media/text private and outside Git/CI.
4. Select one embedding model and one native inference route after license/dependency security review; verify all required artifacts can operate offline with no runtime download.

## Search acceptance — proposed quality thresholds

- **Truth:** 100% of displayed links resolve to an authorized source/segment with correct timestamp identity. Wrong-owner or stale-hash results: zero accepted.
- **Retrieval:** Initial >=80% relevant top-five hits across answerable test queries. Report Recall@5, MRR@10, lexical-versus-hybrid differences and false positives; do not conceal exact-name regressions. Threshold is provisional until measured baseline.
- **Indexing:** Idempotent updates; altered transcript hashes only reindex affected entries; model/hash/vector dimension changes cannot mix incompatible vectors; source removal removes derived searchable entries.
- **No answers:** No fabricated quotes, summaries or source references for queries with no evidence. Search may return no results.
- **Fallback:** With embeddings/local inference unavailable, lexical FTS5 stays useful; with all search disabled, production remains unaffected.

## Security / runtime acceptance

- No paid keys, remote inference, free-tier dependency, remote failover, unexpected egress, or model-generated tools. Verify no outbound DNS/network attempts by backend or children after setup; authenticated Drive/rclone remains independently functional.
- Check fixed model identity, finite numeric embeddings, exact vector dimension, result-ID mapping, malformed response rejection and unsafe path inputs.
- Bounded memory and disk; record measured M1/16 GB system memory pressure, swap, process footprint, cold/warm latency, indexing speed and interaction stalls while Joey handles realistic ASR/render workloads.
- Cancellation, app restart, crash, low disk and model mismatch preserve original transcripts, existing records, QA receipts, source media and production progress. No duplicate indexing records or unfinished atomic writes.
- Optional reranker admitted only if blind labeled comparisons show a clear lift that justifies latency/memory complexity.
- Editorial suggestions admitted only with source/timestamp/segment verification, grounded truth checks and no unauthorized media/provider mutation. Retain existing deterministic fallback and no routine human-QA hold in core processing.

## Exit decision

Deliver a reproducible comparison report, independent review, license manifest, measured resource profile, network-isolation proof, reversible cleanup/rollback guide and explicit `GO`, `REVISE` or `NO-GO`. Separate owner approval is required to begin even the bounded local POC and again to change or install production Joey. CI fixture tests do not constitute a real Mac acceptance run.
