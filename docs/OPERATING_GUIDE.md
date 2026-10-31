# Joey operating guide

## Start a job

Open Joey Native.app. Choose New job, choose DUB or Taxstone, select the authorized original or enter its direct YouTube/X URL, and supply its stable source ID, source title and authorization basis. Use the complete local original when already available. Supply the verified existing archive file link when available; the app checks its bytes before reusing it. Full-show coverage is the default. Highlights are explicit and may specify a count. Imported job requests can also specify exact intervals, verified episode date evidence, a source-bound transcript and artwork bindings.

Unknown dates stay `Date Unknown`. Uncertain ad material stays in the program. Full-show planning targets 8–10 minutes, constrained by verified shared limits, and preserves short sources/remainders. Native clips contain the original picture/audio with proportional black padding and no new branding. Audio uses its approved presentation and source-driven fixed-position bars. Taxstone art must match the episode; it never falls back to DUB artwork.

## One-time operational setup

Import a verified shared profile through Setup. It records each platform's actual account, upload surface, checked/expiry dates, maximum duration, dimensions, file size and frame rate, official documentation URLs and a local evidence file/hash. A historical `verified` flag is insufficient. The app selects 1080×1920 only when both records allow it, otherwise 720×1280. A JSON profile is configuration evidence, not an assertion that platform ingestion has succeeded. Never populate production settings with the test fixture profile.

Local settings are at `~/Library/Application Support/Joey Native/settings.json`. Initial setup locates the existing local Python Whisper environment/model, installs the bundled ASR adapter into the app-owned helpers directory, and reuses verified DUB artwork. Configure a different existing local Python/model path there when needed. Approved Taxstone episode bindings are keyed by exact source ID; known matching art is copied byte-for-byte into the owned asset catalog. When absent, Joey inspects the configured catalog and established Drive asset locations and reports the exact dependency.

The existing `dubdrive` rclone connection is used for Drive operations. Tokens remain in its existing configuration and process memory. Joey does not store them in manifests or Git. DUB jobs additionally require a Google Sheets-enabled authorized OAuth connection for the existing Master Link List. A provider 403 is an operational dependency; the application must not mark those jobs complete or treat a CSV as a successful register write.

## Progress, cancellation and recovery

The app displays stage, errors, clip titles, exact fractional intervals, measured durations, QA checks and verified Drive links. Cancel stops the native subprocess supervisor and tool descendants. Accepted files and originals remain intact. Reopen resumes interrupted processing once from the durable checkpoint; explicit cancellations wait for Resume. A cross-process lock prevents simultaneous writers in the same library. Unique render-attempt directories fence writes after abrupt termination. The Mac must remain awake/available for processing; actual sleep/wake acceptance has not been established merely by unit tests.

Unchanged accepted outputs are hash-checked and reused. Complete timestamped transcripts are source-bound and reused after later failures. Disposable scratch from a successfully validated attempt is removed only after output/evidence persistence. No unrelated files, source originals or accepted outputs are automatically deleted.

A completed job reopens from local evidence without contacting GitHub, Codex or cloud build services. This does not claim a new provider readback while offline. Filing failures retain accepted media as `QA_PASSED — NOT FILED`. Errors identify the affected stage/clip; independent clips continue. Ordinary transient operations are bounded to three attempts, with uncertain external writes reconciled before repetition.

## Filing and completion

Native-video clips route to Joey Video Clips (`1fgABGYTtNC_h2u-v6fwTcPkVKjFd7GQx`); audio-template MP4s route to Joey Audio Clips (`1_s2K9Pw2Je93IwazQ6QgLjz_SimVYuPz`). Both roots already have anyone-with-link read access. Joey preserves that existing state and never changes sharing. Full-length originals stay in their existing archive. New originals use only established full-length roots and preserve source bytes.

An episode folder contains numbered MP4s, one canonical Clip Index CSV, the full transcript, `clip_manifest.json` and `RECONCILE.md`. The CSV is the canonical episode index; no duplicate native index or platform-specific folders are created. Exact multi-interval mappings and exclusions remain in the manifest. DUB Master Link List cells are mapped by current headers, duplicate-checked by verified Drive ID and read back; unknown columns/formulas are preserved. Taxstone never writes DUB-only register rows.

Drive file ID/name/parent/size/MD5/link/access state are independently read back. Local SHA-256 links the accepted artifact to its receipt. Required companion readback and DUB register reconciliation precede local `COMPLETED`. Uploaded finalization records stay `FILED` with the durable local checkpoint named as completion authority, avoiding a premature external completion claim or circular self-hash. Platform ingestion and Instagram placement remain separate from packaging.

## Standalone runner

```sh
joey-run setup
joey-run list
joey-run check-drive
joey-run run /absolute/path/request.json
```

`--root /absolute/path` selects an isolated application-owned runtime directory for controlled acceptance. A local-only request returns `QA_PASSED`, never `COMPLETED`. CLI exit 0 means the requested local-only QA or complete delivery succeeded; consult the explicit job state. Runtime JSON, media, logs, models and credentials belong outside Git.

## Current acceptance limits

See STATUS and VERIFICATION for exact commands/results. Local renderer verification using real source recordings does not establish actual account capability or verified provider delivery. Real media must not be uploaded until the selected account/upload profile is supported. Public distribution, signing identities, notarization and Xcode Cloud setup remain separate from this local build.
