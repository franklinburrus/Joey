# Clip Intelligence and GPT Buffer Handoff

Joey prepares accepted content and keeps distribution history. The existing Buffer connector is operated by GPT only after Frank separately authorizes an exact batch/items, destination accounts and delivery mode. Joey contains no Buffer write client. Exporting, opening or copying a package is not authorization. No live drafts, schedules or posts were created during implementation acceptance.

## Native workflow

Open **Ready for Buffer**, or **Prepare for Buffer** in a completed episode's Results. Select clips, choose X, Instagram or both, and leave **Save as Draft** selected unless a different execution mode is explicitly intended. Run Preflight, review account identities and blocked items, then select the review acknowledgement and Generate GPT Handoff. Open the resulting folder and give GPT its manifest and instructions with a separate execution request. Import returned JSON using Import GPT Receipts. Missing or uncertain results stay unresolved.

The existing Swiss interface, appearance preference and production coordinator are retained. Completed media is read, never renamed or rerendered for this feature. Scores are deterministic transcript-based editorial heuristics, not virality probabilities. Twelve criteria and limitations are visible in expandable details. Unverified timeliness, audience fit and semantics are explicitly low-confidence. Titles/captions use conservative topics and source context; uncertain evidence cannot invent allegations or quotes. Boundary notes are advisory, and production coverage remains unchanged. Optional performance-observation fields are reserved for actual dated provider metrics; no analytics collection or training occurs.

Instagram traditional single-video feed placement is not silently converted into a Reel. The user must explicitly choose and acknowledge Reel or Reel shared to feed. Otherwise Instagram is blocked, independently of X. Joe Budden remains Drive-only without an authorized additional destination mapping and compliant shared media.

## Evidence and expiration

Preflight requires a COMPLETED source-bound job, transcript, accepted output/QA hash, companion records, correct Drive folder and required register evidence. It probes actual MP4/H.264/yuv420p/progressive/square-pixel/30-fps portrait media, AAC-LC audio where present, actual bytes/bitrates/timing and complete decoding. Current owner-specific Buffer capability evidence remains mandatory. The common maximum is the stricter verified limit or 140 seconds, with a 0.1-second encoding margin. Existing accepted files that fail are preserved and blocked.

The shared `DurationPolicy` owns planning, rendering QA and preflight bounds. For Buffer profiles, measured duration must be 5–139.9 seconds under the 140-second capability. New plans reserve the additional 0.075-second encoding tolerance, so their maximum is 139.825 seconds. Smaller verified capability ceilings remain authoritative. Full-show planning rebalances short remainders without changing exact retained coverage; a final automatic highlight may include preceding unselected content to retain the source ending at the minimum length. Explicit fixed intervals are never altered: conflicts and genuinely too-short retained sources are reported. Existing accepted bytes remain preserved, including legacy media that fails current delivery eligibility.

Official constraint check on 2026-11-01: [Buffer's video guide](https://support.buffer.com/articles/sharing-videos-through-buffer-LOe2p2rnAI) lists X uploads up to 140 seconds and Instagram Reels from 3 seconds. Joey retains its existing, stricter 5-second operational minimum and 0.1-second measured ceiling margin; neither is represented as a newly discovered platform limit. This documentation check is not account eligibility or successful platform ingestion evidence.


Drive metadata, parent, identity, checksums, duplicate filenames and existing access are read back. Anonymous retrieval follows only approved Google redirect hosts, rejects authentication/HTML/oversized or changed responses, and compares two bounded 64 KiB ranges to local bytes. This is sampled remote verification, not a full remote SHA-256. Full local hashing is separate. URL evidence lasts at most 15 minutes, bounded by capability expiry. GPT must recheck immediately before execution.

Queue and custom scheduling choices are visible but blocked for the current direct-Drive method: verification today does not prove retrieval suitability through publication. A separately authorized supported delivery mechanism with longevity evidence is needed; Joey never expands sharing or creates hosting to resolve this. Channel observations expire within 24 hours and must be refreshed through the existing read-only Buffer connector. Settings remain untouched. Refreshed evidence can be imported in the expandable account controls; exact lane/platform/handle/organization/channel, connection and lock state, source and timestamps must be retained. GPT must resolve those identities live before writing even when saved evidence remains current.

## Durable contract

Application-owned state is `~/Library/Application Support/Joey Native/buffer/handoff.json`. This extends the existing job records; it is not a competing production database. A separate nonblocking `handoff.lock` serializes reservations and imports without interrupting the media worker. Selection and each completed preflight persist. Production checkpoints, accepted media, credentials and delivery receipts remain elsewhere and unchanged.

Packages live under `buffer/exports/<parent-batch-UUID>/<manifest-SHA256>/` and contain:

- `manifest.json`: `joey-buffer-v1`, exact source intervals and output SHA-256, media/URL/capability evidence, editorial recommendations, destination identity/mode/presentation, blockers, prior receipts and deterministic sub-batches.
- `manifest-canonical.json`: the exact canonical bytes hashed by the manifest, with its own manifestSHA256 field empty. Hash is integrity evidence, not a signature or authority grant.
- `GPT-INSTRUCTIONS.txt`: the complete execution, authorization, duplicate reconciliation, rate-limit, uncertainty and readback contract.
- `receipt-template.json`: one explicitly unexecuted result per expected operation. Never import it as proof of provider success.

Default sub-batches contain at most five clip/destination operations; X plus Instagram is two. A conservative 1–20 bound is configurable. Stable operation identity binds lane, source, exact intervals, final hash, platform and channel. Repeated unchanged exports reuse the package. Renewal preserves parent and operation identities, records the preceding manifest hash and retains every old export. Known or uncertain provider attempts block new submission and require reconciliation. Local locks cannot coordinate independent GPT sessions; provider readback remains the final safeguard.

The execution contract requires current short/daily/long-window allowances, provider Retry-After, sequential operations, no more than three transient attempts, and stop on expiry or exhausted allowance. Ambiguous writes are UNCONFIRMED and must be reconciled before any retry. The local rate-gate tests validate these decisions; Joey does not itself execute provider retries.

## Receipt reconciliation

Receipts use `joey-buffer-receipts-v1` and match the exact stored batch, manifest hash, operation, job, clip, source, lane, platform, organization, channel, requested mode and submitted media reference. Unknown enum values, mismatches, duplicate conflicting items, post-ID conflicts, false independent-verification claims and unauthorized mode escalation are rejected atomically. Identical imports are idempotent. Confirmed evidence cannot be downgraded by an uncertain receipt.

Workflow states VALIDATED, PREPARED, SUBMITTED, RECONCILED, BLOCKED, FAILED and UNCONFIRMED remain separate from provider states draft, scheduled, sending, sent and error. Imported provenance is always **GPT-mediated provider evidence; not independently verified by Joey**. Receipt histories preserve actual post IDs and readback times. `submissionOrigin=existingPost` permits legitimate historical creation times with current readback; it does not authorize recreation or count an earlier draft as fulfillment of a queue request. An error record is not successful delivery. A draft is not publication, and creation acknowledgement is not platform-ingestion acceptance.

## Recovery and acceptance limits

Restart reloads selection, preflight, reservations, immutable manifests and receipt history. Recheck expired evidence, then renew the same parent batch. Return results for every expected operation, including blocked, failed and unresolved items. A partial batch never restarts successful operations automatically. No live-provider ingestion claim is established by local tests or fixture receipts. Actual results and installation evidence are recorded in STATUS.md.
