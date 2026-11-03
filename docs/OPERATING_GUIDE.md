# Joey operating guide

## Start a job

Open Joey Native.app, choose Import Link, paste the original YouTube/X URL and choose DUB, Taxstone or Joe Budden. Source identity and metadata are resolved from that link. Full-show coverage is the default; DUB/Taxstone Highlights explicitly selects one highlight per 15-minute source block, including the final partial block. Advanced Settings accepts an existing full-length archive link and source-bound transcript. Complete-original filing is required before new DUB, Taxstone and Joe Budden production clips. Imported legacy job requests retain local-source recovery and may specify exact intervals, verified date evidence and artwork bindings.

Unknown dates stay `Date Unknown`. Uncertain ad material stays in the program. Full-show planning targets 8–10 minutes, constrained by verified shared limits, and preserves retained coverage. The Buffer shared profile enforces measured 5–139.9-second clips; plans reserve encoder tolerance and rebalance remainders. DUB/Taxstone native clips preserve original picture/audio with proportional black padding and no new branding. Joe Budden's separate Drive-only workflow uses 8–10-minute source-content clips with the approved DUB logo and complete outro, as required by the later product amendment. Audio uses its approved presentation and source-driven fixed-position bars. Taxstone art must match the episode; it never falls back to DUB artwork.

## One-time operational setup

Open Production Configuration for the selected owner, or Taxstone Production Setup from the library. DUB and Taxstone profiles remain separate. Setup records each platform's actual account, upload surface, checked/expiry dates, maximum duration, dimensions, file size and frame rate, official documentation URLs and a local evidence file/hash. A historical `verified` flag is insufficient. The app selects 1080×1920 only when both records allow it, otherwise 720×1280. Profile evidence does not establish successful platform ingestion. Never populate production settings with the test fixture profile.

Local settings are at `~/Library/Application Support/Joey Native/settings.json`. Initial setup locates the existing local Python Whisper environment/model, installs the bundled ASR adapter into the app-owned helpers directory, and reuses verified DUB artwork. Configure a different existing local Python/model path there when needed. Approved Taxstone episode bindings are keyed by exact source ID; known matching art is copied byte-for-byte into the owned asset catalog. When absent, Joey inspects the configured catalog and established Drive asset locations and reports the exact dependency.

The existing `dubdrive` rclone connection is used for Drive operations. Tokens remain in its existing configuration and process memory. Joey does not store them in manifests or Git. DUB jobs additionally require a Google Sheets-enabled authorized OAuth connection for the existing Master Link List. A provider 403 is an operational dependency; the application must not mark those jobs complete or treat a CSV as a successful register write.

## Progress, cancellation and recovery

The app displays stage, errors, clip titles, exact fractional intervals, measured durations, QA checks and verified Drive links. Cancel stops the native subprocess supervisor and tool descendants. Accepted files and originals remain intact. Reopen resumes interrupted processing once from the durable checkpoint; explicit cancellations wait for Resume. A cross-process lock prevents simultaneous writers in the same library. Unique render-attempt directories fence writes after abrupt termination. The Mac must remain awake/available for processing; actual sleep/wake acceptance has not been established merely by unit tests.

Unchanged accepted outputs are hash-checked and reused. Complete timestamped transcripts are source-bound and reused after later failures. Disposable scratch from a successfully validated attempt is removed only after output/evidence persistence. Unrelated files, retained originals and accepted outputs remain protected. Joe originals remain protected after completion, including historical sources with obsolete deletion receipts.

An eligible locally generated ASR overrun confined to the final 30 seconds is recovered from that actual audio interval using the configured offline helper. Joey preserves the original `asr-source.json` and unchanged prefix, validates regenerated segment/word timings and saves `transcript-repair.json` with the retained excerpt and helper output. It never clamps timestamps. Invalid imported transcripts, mismatched sources and earlier/order defects fail with the exact segment or binding issue. Failed recovery remains available for diagnosis; restarting reuses valid evidence and does not repeatedly invoke inference on the same invalid result. A supplied complete source-bound transcript can provide explicit recovery. Do not delete or edit repair evidence to force acceptance.

A completed job with current routing evidence reopens from local evidence without contacting GitHub, Codex or cloud build services. A legacy completion record without authoritative destination evidence cannot receive a current Completed badge; its accepted files and receipts remain preserved for reconciliation. This does not claim a new provider readback while offline. Filing failures retain accepted media as `QA_PASSED — NOT FILED`. Errors identify the affected stage/clip; independent clips continue. Ordinary transient operations are bounded to three attempts, with uncertain external writes reconciled before repetition.

Missing companion receipts do not invalidate accepted clips or authorize rerendering. Resume verifies existing files and folder bindings, reuses valid provider identities, reconciles the four required companions and then performs required register readback. An incomplete receipt or missing companion prevents completion; repeated recovery must retain the same accepted media and provider identities.

## Filing and completion

Destinations resolve automatically from content ownership, inspected source format, asset class and verified episode/source identity. No Drive folder selection is required. Frank's creator-based Content tree has eight active delivery destinations:

| Content | Clip root | New full-episode root |
| --- | --- | --- |
| DUB X audio | `1FRi-yy2D9yenjQRailTA2iAbPaqAEPXm` | `109_QzHpF0Bi-OG6-AxuTDw1uHG4zeop3` |
| DUB X video | `1380CHJ3a3kl7fXNIKWqUM7_DeTZUwxsy` | `1GpuGWGIbSt3afwsi9L782soT9WJKOHS9` |
| Taxstone | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1wQMwzUconRC3UCvH2jpL1kD__ctBv29p` |
| Joe Budden | `1X5VNP6fo3VpZPu4ZW4p7Ggk2o_IAVGSI` | `1KJ0-sjGWNxwIuis_faA5z_FbPUcbjEDD` |

The creator folders sit directly under Content. DUB's four folders retain their existing names; Taxstone uses Taxstone Clips and Taxstone Full Episodes; Joe uses Joe Budden Clips and Joe Budden Full Episodes. Joey preserves permissions and verifies exact established ancestry under the DUB root. New source archives use the full-episode roots above; verified legacy originals stay where they are. Complete Joe originals are filed before transcription/clipping as `<episode number> — <episode title>.<original extension>`, for example `945 — Maximum Punishment.mp4`. Source titles and provenance remain unchanged in records. Completion and reopening never delete originals or act on historical `source-retention.json` receipts. An ambiguous identity or conflicting saved destination stops filing with the exact issue; the one known retired Joe archive selection resolves to the restored current root while preserving job identity. Existing packages outside the direct clip roots are reported and preserved, never moved or duplicated automatically by the production workflow.

An episode folder contains numbered MP4s, one canonical Clip Index CSV, the full transcript, `clip_manifest.json` and `RECONCILE.md`. The CSV is the canonical episode index; no duplicate native index or platform-specific folders are created. Exact multi-interval mappings and exclusions remain in the manifest. DUB Master Link List cells are mapped by current headers, duplicate-checked by verified Drive ID and read back; unknown columns/formulas are preserved. Taxstone and Joe Budden never write DUB-only register rows. Their canonical episode records remain in their respective episode folders; historical rows are preserved.

Folder reuse requires a matching source hash as well as source, owner and job identity. Legacy tags without a hash must pass downloaded-manifest verification or the bounded empty-folder creation-intent check before Joey binds the hash. A conflicting hash stops filing before mutation. Historical misplaced packages remain readable but display Delivery incomplete; moving them requires separate authorization and the migration/readback plan in VERIFICATION.md.

Drive file ID/name/actual parent/expected ancestry/size/MD5/link/access state and duplicate absence are independently read back. Permission fingerprints include permission identities, roles and discovery settings. Companion files are downloaded and hash-checked. Local SHA-256 links the accepted artifact to its receipt. Required companion readback and DUB register reconciliation precede local `COMPLETED`. Uploaded finalization records stay `FILED` with the durable local checkpoint named as completion authority, avoiding a premature external completion claim or circular self-hash. Platform ingestion and Instagram placement remain separate from packaging.

## Standalone runner

```sh
python3 Tools/run-local.py .build/debug/joey-run setup
python3 Tools/run-local.py .build/debug/joey-run list
python3 Tools/run-local.py .build/debug/joey-run check-drive
python3 Tools/run-local.py .build/debug/joey-run run /absolute/path/request.json
```

`--root /absolute/path` selects an isolated application-owned runtime directory for controlled acceptance. A local-only request returns `QA_PASSED`, never `COMPLETED`. CLI exit 0 means the requested local-only QA or complete delivery succeeded; consult the explicit job state. Runtime JSON, media, logs, models and credentials belong outside Git.

## Current acceptance limits

See STATUS and VERIFICATION for exact commands/results. Local renderer verification using real source recordings does not establish actual account capability or verified provider delivery. Real media must not be uploaded until the selected account/upload profile is supported. Public distribution, signing identities, notarization and Xcode Cloud setup remain separate from this local build.


## Storage management

Settings → Storage measures the working volume, temporary files, active scratch, protected runtime files and verified reclaimable bytes. Automatic Cleanup defaults to on; Low Disk Protection is always enabled. Clean Now uses the same ownership, lifecycle, hash and locking checks as automatic cleanup. Unknown historical scratch remains preserved. Scratch cleanup never removes accepted MP4s, originals, transcripts or delivery records. See [Storage Manager](STORAGE.md) for capacity estimates, 60-second blocked-state recovery, cleanup audit receipts and limitations.
# GPT Buffer handoff extension

The installed Ready for Buffer workflow prepares completed clips and imports external receipts. It does not submit drafts, schedule or publish. See [BUFFER_HANDOFF.md](BUFFER_HANDOFF.md) for preflight expiry, explicit account/presentation/mode review, portable packages, separate Frank execution authorization, bounded sub-batches and receipt recovery. Production filing and coverage rules below remain unchanged.
