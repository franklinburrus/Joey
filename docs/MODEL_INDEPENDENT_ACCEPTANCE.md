# Model-independent core processing acceptance

Status: **PASS for this bounded milestone**. Overall Joey production acceptance remains PARTIAL. The installed app, original source/transcript, nine accepted clips, checkpoints, QA receipts and prior acceptance evidence were preserved. Final installed SwiftUI inspection remains open and was not retried or substituted with core tests.

## Authority and boundary

Frank's 2026-10-31 “JOEY — NEXT MILESTONE: MODEL-INDEPENDENT CORE PROCESSING” explicitly authorizes local core operations without transcripts or speech-recognition models. It resolves the earlier local-core design conflict in favor of model independence; it does not approve mandatory AI or waive production transcript/editorial/delivery requirements. The canonical `/Users/frank/Documents/ChatGPT/Joey/docs/JOEY_SPECIFICATION.txt` and its identical native `docs/REQUIREMENTS.md` mirror now record this narrowly scoped amendment. Older acceptance evidence remains unchanged as historical evidence.

Repository: `https://github.com/franklinburrus/Joey.git`; branch `codex/native-consolidated`; HEAD `517878ff9c13911bf8d033c517492ef51ccffca7`. Current `git ls-remote origin refs/heads/main refs/heads/codex/native-consolidated` read back feature HEAD unchanged and main `f265a5ad2c44b933d6da4aafc752c9c6c8646a83`. No push, merge, commit, credentials/Cloud change, provider write, social upload or publication occurred.

Existing picker/UI/documentation changes and the pre-existing dirty Xcode scheme were retained. All builds/tests for this milestone use `/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance` (evidence root below). The new native build was **not installed** over `/Users/frank/Applications/Joey Native.app`.

## Dependency trace and implementation

| Former dependency | Responsible change |
| --- | --- |
| `Coordinator.run` always required transcript acquisition before any plan and force-unwrapped the transcript for exclusions/planning. | Explicit request policy `transcriptPolicy: "modelIndependent"` allows no transcript for a local full-show job with no requested exclusions. The coordinator branches on actual transcript availability and persists `planningBasis`. |
| `Acquisition.transcript` required configured Python/helper/model when no valid supplied/cached transcript existed. | Return nil only for the explicit model-independent policy, before any ASR invocation. Supplied/cached transcript validation still rejects wrong source/hash/timestamps. Assisted requests preserve existing behavior. |
| `Configuration.load` automatically discovered ASR/model files and copied the bundled helper. | Model-independent runs skip transcription discovery/copying altogether. No new dependency, service, model or automatic download was added. |
| `Editorial.plan` required transcript sentence endpoints and text-derived titles; ad detection consumed transcript text. | `planWithoutTranscript` reuses existing `Planning.fullShow` with no natural-boundary inputs or exclusions. Entire source remains chronological; generic `Part 01`, `Part 02` labels and source-ID/sequence/timestamp filenames replace inferred content titles. No tail balancing was added. |
| `Records.write` required both source and transcript; failure packaging also required a transcript. | Source-bound local CSV, manifest and reconciliation records can be written without a transcript. No fake/empty Full Transcript file is produced. |
| Production finalization relied implicitly on the earlier mandatory transcript gate. | Explicit missing-feature guard before any filing/register operation; COMPLETED fast path also rejects missing editorial evidence. Missing requirements leave locally accepted files at QA_PASSED with an exact dependency message. Automatic retry does not loop on these unmet editorial requirements. |
| SwiftUI had no model-independent intake option or explicit missing-feature recap. | Added “Use local speech recognition when a transcript is missing” toggle and missing-feature recap. Turning it off selects the bounded local policy. Build verified; GUI behavior remains unobserved. |

The default/nil policy retains the existing assisted path. The new optional request field is omitted from legacy serialization, preserving old request/job identities. Model-independent operation may reuse a valid supplied/cached transcript without invoking inference. Without one, four features are explicitly UNAVAILABLE: complete source-bound transcript; transcript-assisted sentence/topic boundaries; descriptive content titles; advertisement identification/removal. These are recorded in the manifest, reconciliation summary, per-clip QA limitations and UI recap, not marked passed.

Persisted deterministic plans are stable on resume. A transcript appearing later does not silently change exclusions, boundaries, accepted files, QA receipts or production eligibility. The test verifies this using a test-owned transcript, then removes that test-created file. No pre-existing transcript was deleted. Model-independent audio additionally requires supplied approved local artwork; native video needs no artwork. Remote acquisition, highlights and explicit exclusions are rejected by this bounded policy rather than silently altered.

Rendering, full decoding, audio/picture validation and coverage arithmetic already worked without transcript input. Those implementations were reused, not rewritten. Media QA remains technical/sampled evidence, not semantic topic or sentence validation.

## Regression and test results

| Run | Direct exit | Actual result |
| --- | ---: | --- |
| Mandatory-transcript regression, before production code changes | **1** | 1 executed, 1 assertion failure, 0 unexpected errors. Job FAILED before planning: `Required local executable unavailable: …/absent-python`. |
| First corrected-path run | **1** | Local rendering succeeded; test compared an unsaved subsecond Date to its ISO8601 persisted form. The test was corrected to compare saved QA receipts and output mtimes. No production timing/storage policy was changed. |
| Targeted corrected tests | **0** | 4 executed, 4 passed, 0 failures/errors/skips. |
| Network-denied acceptance | **0** | 4 executed, 4 passed, 0 failures/errors/skips; 6.978 seconds. |
| Full shared-core suite | **0** | 28 discovered/executed: 27 passed, 1 skipped, 0 failures/errors; 20.350 seconds. |
| Separate native Xcode build | **0** | BUILD SUCCEEDED. New app remains in isolated derived-data output. |
| Independent fixture/records/preservation audit | **0** | Three outputs and local package verified; all 124 protected file identities unchanged. |

The single skipped test is the opt-in historical real-media renderer acceptance (`JOEY_REAL_MEDIA_INPUTS` not supplied). It was intentionally not rerun against previous accepted media/evidence. Existing transcript-assisted workflow, ad-detection, source-validation, recovery, renderer and provider-mock tests ran and passed. The additional Swift Testing runner reports zero tests; it is not the XCTest count.

The regression was added before implementation using serialized `transcriptPolicy: "modelIndependent"`; the old decoder ignored the unknown field and the old coordinator failed at mandatory ASR. It is a behavioral red/green regression, not a test that only became compilable after the new API existed.

New tests cover absent transcript/helper/model through the full local pipeline, deterministic long-source plans, unsupported scope rejection, legacy serialization, cached valid transcript assistance and mismatch rejection, accepted-plan/QA reuse, later-transcript nonpromotion, blocked production before providers, and rejection of a falsely promoted COMPLETED checkpoint. Repeatability means equal plan decisions and exact source/output mappings for identical inputs/configuration. Byte-identical new encodes are **not claimed**.

## Actual commands and logs

Working directory: `/Users/frank/Documents/Joey`. Toolchain: `/Applications/Xcode.app/Contents/Developer`. The red regression command was:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   --scratch-path '/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance/spm'   --filter ModelIndependentTests.testLocalExportWithoutTranscriptModelOrHelper   > '/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance/regression-red.log' 2>&1
```

The targeted passing run used the same scratch path with `--filter ModelIndependentTests`, logging to `regression-green2.log`. The first failed corrected test remains in `regression-green.log`.

The following launcher calls use a minimal explicit environment and record exact child arguments, timestamps and direct exit statuses in `offline-result.json`, `suite-result.json` and `build-result.json`:

```sh
python3 '/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance/run_checks.py' offline
python3 '/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance/run_checks.py' suite
python3 '/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance/run_checks.py' build
python3 '/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance/audit_acceptance.py'
```

Offline test command executed by that launcher:

```sh
/usr/bin/sandbox-exec   -f '/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance/offline.sb'   /Applications/Xcode.app/Contents/Developer/usr/bin/xctest   -XCTest JoeyCoreTests.ModelIndependentTests   '/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance/spm/out/Products/Debug/JoeyCoreTests.xctest'
```

Suite/build commands executed by the launcher:

```sh
/usr/bin/xcrun swift test --scratch-path '/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance/spm'
/usr/bin/xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug   -destination 'platform=macOS'   -derivedDataPath '/Users/frank/Library/Caches/Joey-Native-Build/model-independent-acceptance/native-build'   CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

Logs: `offline.log`, `suite.log`, `build.log`. Existing AVAssetWriter APIs emit macOS deprecation warnings; this is not a warning-free build claim. No dependency installation occurred.

An attempted `xctest -help` returned exit 1 and unexpectedly dumped the inherited environment, including an API credential, into tool output. The credential is not repeated or stored in repository evidence. Subsequent launches use a minimal environment without API credentials. No credential rotation was attempted under the explicit exclusion. This diagnostic incident does not change the media/test results, but remains disclosed for separate credential handling.

## Offline fixture evidence

The request authorizes an isolated local fixture. The test generates moving `testsrc2` video plus a sine tone using installed FFmpeg, records authorization as generated test media and uses explicit diagnostic profile evidence. Source: **3.4 seconds**, **320×180**, H.264/AAC. This is bounded pipeline acceptance, not a new full-length production job or a substitute for the prior nine-output run.

Source SHA-256: `e6f1166a2503e8da0b54d097cf91cfbda614b4ff1f00abfd20b00c9c1eecf47e`. Isolated job ID: `dub-366ad0eee418607dd8bdfb9e`.

| Clip | Measured seconds | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| 1 | 1.2 | 81,030 | `94f995727d2e44a00d2948c9a5068cd350bdaff61b4b3d58baf59cadf31075e1` |
| 2 | 1.2 | 84,029 | `49f14d6ac7f4b9b329127de3791d7afd13b0b9f3f9996b57545276ba4eee9f8a` |
| 3 | 1.0 | 74,250 | `8f1237d61cc7ecd9f8494e2b1176a211a31ed4f283371efbb0f35e219cc74570` |


The diagnostic max-duration limit is **1.2 seconds**, deliberately creating three real outputs cheaply while exercising chronological segmentation. Output canvas is **720×1280**, effective source picture **320×180** with black padding; no upscaled-detail claim. Exact filenames, full probes, hashes, QA receipts, mappings and source metadata are in `acceptance-result.json`.

The source and job have no supplied/cached transcript when processing begins; configured Python/helper/model paths do not exist. No canonical transcript, ASR output or helper directory exists in the final package. Model-independent configuration skips ASR discovery even if the host has models elsewhere.

The temporary sandbox denies all networking, model-cache/helper reads and process execution except the XCTest host, native supervisor, FFmpeg, FFprobe and the diagnostic probe. It also prevents writes to pre-existing accepted jobs/evidence, originals, installed apps and rclone credentials. The direct socket probe returned **-1, errno 1 (EPERM)**; network policy check and ASR Python execution check returned **1 (denied)**. Actual observed XCTest/supervisor/media processes also reported outbound denial. No system-wide networking/security setting changed.

No model/helper invocation or attempted model download occurred in the new path: the tested acquisition branch returns nil before ASR, the configured dependencies are absent, execution/read restrictions prohibit them, and the successful pipeline contains only media helper calls. ASR invocation errors would propagate; there is no catch-and-ignore fallback hiding an attempted transcription failure. Process sampling is corroborating evidence, not a claim to capture every short-lived process. `offline.sb`, `offline-probe.c`, `offline-probe.json`, `offline-result.json` and source control flow retain the complete proof.

All outputs passed complete decode, measured technical/duration checks, source/output audio correlation and sampled full-frame fidelity. Exact mappings cover **[0,1.2], [1.2,2.4], [2.4,3.4]** once with no exclusions. One canonical three-row CSV index, manifest and reconciliation record were created; no fabricated Full Transcript or Drive links were created. QA limitations explicitly list all four unavailable editorial features. The local state is **QA_PASSED**, not COMPLETED.

## Preservation and remaining acceptance

`preservation-before.json` and `preservation-after.json` match for **124 files**, including installed native/legacy bundles, original source/transcript, all nine accepted outputs, complete existing job/checkpoint/QA records, previous full-length acceptance evidence and the pre-existing user Xcode scheme. SHA-256, bytes and nanosecond mtimes match. The original nine-output job was not resumed, rendered or rewritten during this milestone.

Production completion still needs a valid full transcript and applicable editorial work, verified actual account/profile compatibility, verified Drive filing/companions and required register readback. A deterministic local plan does not acquire those proofs automatically. The earlier Sheets prerequisites and final installed SwiftUI inspection remain open; no unrelated audit was reopened. No account/profile, tail-balancing, GUI-permission, credential or provider changes were made.

| Acceptance lane | Status |
| --- | --- |
| Model-independent core milestone | **PASS** |
| Isolated local fixture media QA and records | **PASS** |
| Network denial / absent ASR dependencies | **PASS** |
| Deterministic plan/mapping repeatability | **PASS** |
| Existing transcript-assisted tests | **PASS**, full suite as counted above |
| Existing accepted evidence preservation | **PASS**, 124 identities unchanged |
| Installed SwiftUI inspection | **OPEN**, no new GUI evidence or installation |
| Production transcript/editorial completion | **INCOMPLETE for transcriptless jobs** |
| Drive/register acceptance | **NOT ATTEMPTED**, existing dependencies unchanged |
| Platform compatibility/ingestion/publication | **NOT ESTABLISHED / NOT ATTEMPTED** |
