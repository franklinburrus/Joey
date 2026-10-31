# Joey native verification

Verification date: 2026-10-30 EDT. Outcome: **PARTIAL**. The native implementation builds and passes local tests. Production account capabilities and required provider delivery are not yet verified.

## Checkout and preserved work

Repository: `https://github.com/franklinburrus/Joey.git`, branch `codex/native-consolidated`. Merge `5e35d4d` preserves native starter `bc34efbf88b95c726da3fe8e1eb3dcb69120bb3c` and remote main `f265a5ad2c44b933d6da4aafc752c9c6c8646a83`. Existing Xcode project was retained. User scheme preferences are excluded from the implementation commit. Preservation hashes and historical failed-run logs remain under `/Users/frank/Library/Caches/Joey-Native-Build/`.

Changed implementation groups: native SwiftUI intake/history/setup/progress; shared core identity, planning, acquisition, transcription, rendering, QA, checkpoints, supervision and delivery; standalone runner; dependency-free test harness; active specification, operating guide and helper provenance. No production media, transcripts, credentials or models are included in Git.

## Final test and build commands

Run from `/Users/frank/Documents/Joey` with Xcode 27.2 (27B52). Global `xcode-select` was not changed.

```sh
JOEY_REAL_MEDIA_INPUTS='/Users/frank/Library/Caches/Joey-Native-Build/real-media/inputs.json' \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
> /Users/frank/Library/Caches/Joey-Native-Build/final-suite-delivery.log 2>&1
```

Direct exit **0**. XCTest: **24 discovered/executed, 24 passed, 0 failures, 0 errors, 0 skips**, 22.522 seconds. The additional Swift Testing runner contains zero tests; it is not the suite count. Coverage includes chronological hour-to-six planning, short/fractional remainders, exclusions, platform limits, evidence validation, real/generated media QA, corruption and absent-waveform rejection, cancellation, TERM-resistant descendants, accepted-output reuse, scratch cleanup, and cancellation/filing recovery eligibility.

The final cancellation regression was first run against the faulty implementation: direct exit **1**, 1 test, 1 assertion failure (`qaPassed` instead of `cancelled`). After repair, the same test passed in the full suite. Log: `recovery-regression-red.log`. Existing failed build/debug logs remain evidence, not current success claims.

The provider transport integration test uses an in-memory URLProtocol response sequence: GET recovers after two HTTP 503 responses on its third attempt; an uncertain POST returns after one attempt for caller-owned reconciliation. This verifies local retry behavior, not live Drive/Sheets delivery or duplicate recovery. `rclone listremotes` confirmed `dubdrive` is the sole configured remote, so no alternate existing local connection resolves the Sheets dependency.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug \
-destination 'platform=macOS' \
-derivedDataPath '/Users/frank/Library/Caches/Joey-Native-Build' \
CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build \
> /Users/frank/Library/Caches/Joey-Native-Build/native-delivery-build.log 2>&1
```

Direct exit **0**, `BUILD SUCCEEDED`. Compatible AVAssetWriter APIs emit deprecation warnings under macOS 27; this is not a warning-free build claim.

Installed at `/Users/frank/Applications/Joey Native.app`. All 7 bundle files match the build by SHA-256. The historical `Joey.app` was hash-checked unchanged. Receipt: `native-install.json`.

```sh
codesign --verify --deep --strict --verbose=2 '/Users/frank/Applications/Joey Native.app'
```

Direct exit **0**, valid on disk and designated requirement satisfied. This is a local ad-hoc build, not notarized public distribution. Earlier UI inspection verified native intake, Full show default and disabled Start without account evidence. Final installed-build UI inspection was unavailable because the computer-use tool reported the Mac locked; non-GUI verification continued.

## Real local media evidence

Local evidence root: `/Users/frank/Library/Caches/Joey-Native-Build/real-media/`. Each case retains source/render/QA/acceptance JSON and the accepted MP4. These are original authorized recordings with explicit **fixture technical limits**, not production account eligibility or provider delivery.

| Case | Source interval | Measured output | Automated evidence |
| --- | --- | --- | --- |
| DUB native video | 272.84–289.42 s | 16.6 s; 1,566,497 bytes | Source-only picture; 1920×1080 source becomes 720×404 picture within 720×1280; minimum audio correlation 0.9958876 |
| DUB audio | 0–15 s | 15.0 s; 1,059,502 bytes | Pinned approved artwork; 1,200/1,200 sampled waveform bars within 4 pixels; minimum audio correlation 0.9995496 |
| Taxstone episode `275592592` | 594.22–609.22 s | 15.0 s; 1,318,036 bytes | Matching episode artwork; 1,200/1,200 sampled waveform bars within 4 pixels; minimum audio correlation 0.9997783 |

All three passed complete decode and measured codec, dimensions, rate, duration, size, audio, picture/layout and fast-start checks. Visual checks sample at 2 fps; they are not exhaustive semantic viewing. Technical compliance does not establish social-platform ingestion.

A complete local DUB audio workflow also used the authorized 57.301333-second source at `/Users/frank/Dub/work/dub-skill-family-acceptance/jobs/row265-audio.m4a`. Existing local MLX Whisper produced 20 source-bound transcript segments, direct exit 0 (`transcription-test.log`).

```sh
.build/debug/joey-run run \
'/Users/frank/Library/Caches/Joey-Native-Build/real-media/local-audio-request.json' \
--root '/Users/frank/Library/Application Support/Joey Native Acceptance'
```

Initial run and current-runner reopen: direct exit **0**, explicit state **QA_PASSED**. One output: 57.333008 seconds, 3,937,868 bytes, SHA-256 `bc3f08804e0acfcafe66b8ddfc18ad1cfbd75c33cddbe3b4ea887cdd836d5bc8`. Source-to-output minimum audio correlation 0.9991768; 4,600/4,600 sampled waveform bars within 4 pixels. Reopen retained the accepted output hash and original QA timestamp, with no rendering stage. Logs: `real-local-job.log`, `real-local-job-reopen.log`. Checkpoint: `~/Library/Application Support/Joey Native Acceptance/jobs/dub-07dc8630147630775135009f/job.json`.

The request explicitly disables Drive filing and uses diagnostic fixture capability evidence. It does not establish production completion. The local package contains a canonical CSV index, full transcript, manifest and reconciliation record.

## Provider preflight and acceptance gaps

```sh
.build/debug/joey-run check-drive --root '/Users/frank/Library/Application Support/Joey Native'
```

Direct exit **1**. Existing rclone Drive reads succeeded. Sheets returned HTTP **403**: `Google Sheets API has not been used in project 145289518259 before or it is disabled.` Log: `drive-preflight.log`. A Sheets-enabled authorized OAuth connection for the existing DUB Master Link List is required. No replacement register or Codex-dependent runtime workaround was introduced.

Both exact Joey destination folder IDs were read back. Existing anyone-with-link reader access was observed and preserved. No production files were uploaded, no register rows were written, and no sharing permissions changed.

Actual X account and Instagram account/upload-surface capability evidence remain missing. Production settings contain no fabricated verified profile. These dependencies prevent full delivery acceptance; they do not invalidate local renderer results.

| Required behavior | Current proof and limit |
| --- | --- |
| Native SwiftUI/local operation | Build and earlier UI inspection; CLI/shared-core operation verified. No Codex, GitHub or Xcode Cloud runtime service calls. Actual disconnected-machine UI run not performed. |
| Real native/DUB audio/Taxstone audio | All three isolated renderer cases passed. Full local coordinator workflow also passed for DUB audio. Full provider workflows remain pending. |
| One hour to six chronological 10-minute clips | Deterministic planner test passed; no hour-long production render claimed. |
| Short/remainder/exclusion/platform coverage | Unit tests passed; uncertain ads remain included. |
| Corruption rejection | Real decoder/QA rejection and missing-waveform rejection tests passed. |
| Interrupted rendering/reopen | Accepted output reuse and subprocess cancellation tests passed. Actual sleep/wake not tested. |
| Interrupted filing and duplicate prevention | Recovery/idempotence implementation reviewed; no live mutation/retry acceptance completed. |
| Completed-job reopen | Local implementation preserves accepted receipts; no genuinely completed provider job available to demonstrate it. |
| Destination/index/transcript/manifest/register | Exact roots read; local package verified. Uploaded companion integrity and register writes/readback remain pending. |
| No human QA requirement | No approval state in the workflow. Remaining inputs are operational credentials/capabilities. |

Next acceptance run must use actual verified platform evidence and an authorized Sheets-enabled connection, then verify all three real workflows through Drive companion records and required register readback. Report publishing and actual platform ingestion separately; neither is requested here.
