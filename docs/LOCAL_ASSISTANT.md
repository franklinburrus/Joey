# Optional local assistant — 2026-10-31

Overall production acceptance remains **PARTIAL**. The optional assistant is a separate local feature, not a transcription/clipping dependency or a production-completion waiver. The exposed OpenAI credential incident remains independently open pending owner-confirmed revocation.

## Installed ordinary-use promotion — 2026-10-31

Frank subsequently authorized installation at `/Users/frank/Applications/Joey Native.app`. The candidate-only hold below is historical. The final installed build includes the same assistant implementation plus bounded native intake/profile/duration/status changes documented in STATUS.md. Finder launch works without the acceptance harness. Opening Joey and the assistant sheet did not start Ollama. Explicit UI Start/Stop worked; actual owned Ollama PID 47134 retained default outbound denial and existing identity/model-write denial. Existing Send/Cancel/Clear, offline inference and performance evidence is reused, not repeated. Closing and normal Quit left no service running. Local identity metadata and accepted media remain unchanged.

Installation/source hashes, rollback, native UI observations and preservation receipts are under `/Users/frank/Library/Caches/Joey-Native-Build/installation-20261031`. Final build and strict signature verification returned 0; core suite returned 0 with 51 executed, 48 passed, three previously explained opt-in skips and zero failures. Production remains PARTIAL because actual account evidence and Sheets API enablement are missing; assistant availability does not waive those requirements. The separate exposed-credential incident remains open.

## Corrected candidate gate — PASS, 2026-10-31

Frank authorized minimal startup/import repairs and replacement of the acceptance candidate only. This section supersedes the first-attempt status below while preserving all failed-attempt evidence. Overall production acceptance remains PARTIAL. No production promotion, credential change, model download, push, merge, external write or nine-output rerender occurred.

Evidence directory: `/Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance/correction-1`.

### Established boundaries and retained changes

The failed process chain was protected candidate → the same native executable in `--supervise` mode → `sandbox-exec` → fixed sanitized `/usr/bin/env` configuration → Ollama. The previous offline parent test was not externally sandboxed: it applied the service policy independently to Ollama and the inference client. The GUI harness instead applied a different outer policy before the service owner attempted its policy. Small `/usr/bin/true` reproductions established that identical nested profiles succeed (exit 0), but the actual different outer/service pair and a stricter replacement profile fail (exit 71, `sandbox-exec: sandbox_apply: Operation not permitted`). This was a profile-replacement boundary, not a broken model or tool denial of the executable. The SDK documents that a process already sandboxed cannot replace its profile; the observed identical-profile success is recorded separately rather than generalized into support for arbitrary nesting.

The smallest supported correction keeps sandbox application at both boundaries and uses the same sufficiently restrictive policy. `LocalAssistantService.sandboxProfile` now denies writes throughout the actual home directory, preserves existing local identities, and permits only a missing standard identity file to be generated after explicit Start. Existing model, Applications and runtime protections remain. The assistant acceptance launch uses the exact profile emitted by the built candidate through a linked read-only diagnostic helper. This is stronger than the previous outer write protections, with no skip-sandbox flag, sandbox escape, unrestricted fallback or system-wide network change. In this run both identity files existed, so neither was writable. Service startup remains user-controlled.

A dummy-canary regression found that Foundation's URL normalization can abbreviate `/private/var` to `/var`, causing Seatbelt path denials to miss temporary test files. The profile builder now uses Darwin `realpath` at the policy boundary. The regression proves all eight dummy home-data write attempts are denied and identical outer/inner profiles retain those denials. A separate dummy-only test verifies that only the two missing local-identity filenames can be created, without generating real keys.

`Configuration.load` now compares encoded settings before saving. Unchanged settings retain their file identity and can be loaded under read-only runtime protection; legitimate discovered configuration changes still use the existing atomic save. No media coordinator, transcription, planning, rendering, QA or completion rule changed.

The picker failure was before request decoding. Instrumentation observed `canChooseFiles=true`, directories=false, no type filter, main-thread callbacks, one selected URL and a readable file. The fresh synthetic JSON passed the actual candidate's decoder and request validation. A parent-sheet experiment did not help and was removed. A small AppKit-only test artifact under the same protection accepted direct file selection. Controlled comparison in Joey then reproduced the interaction boundary: Go To highlighted the request but left Open disabled; directly clicking the displayed filename enabled Open. Clicking enabled Open started the actual job. The supported repair was to the acceptance interaction sequence, not import validation. JobModel content is byte-identical to its pre-experiment version; temporary diagnostic code was removed. `noWindowsAvailable` and `timeoutReached` were never treated as proof of a locked Mac.

### Harness failure and corrected attribution

After an earlier Quit, a subsequent native-tool `getAXState()` call returned a new initial window. Process audit found unexpected candidate PID 41945 with outbound networking allowed. It was immediately terminated after exact-path verification. The application has no unrestricted fallback; this was an unintended tool-triggered relaunch. The first synthetic job (`dub-a894f0de63c2fc37cf347916`) retains its local QA results, but its network-isolation attribution was invalidated. Its files were preserved and write-protected during the corrected run. This failure is retained in `tool-relaunch-incident.json`; it is not hidden by later passes.

The corrected harness verifies that only the intended candidate PID exists, checks the actual native window owner, samples its descendant policies, and performs no native-tool access after Quit. CLI process readback then confirmed normal Quit with no replacement process (`quit-without-inspection.json`). The corrected fresh job used a different diagnostic identity; no existing accepted outputs were replaced or rerendered.

### Actual SwiftUI assistant and performance — PASS

All times are UTC. The final candidate PID 39820 ran under `assistant-protected.sb`. Before Start, no listener existed and its actual process denied outbound defaults and settings writes. Sheet opening at 18:09:21.340 and entering a synthetic prompt did not start a service. Explicit Start at 18:09:37.560 succeeded. The actual chain was candidate 39820 → supervisor 39969 → Ollama 39970; all denied default outbound networking, settings writes and existing identity writes. Observed llama-server runners also carried outbound denial. The known profile permits loopback only, and preflight external TCP attempts failed with EPERM. Loopback requests then succeeded, proving the allowed local path remained usable.

Send at 18:10:03.426 returned “2 plus 2 equals 4.” The owned daemon's sanitized HTTP timing recorded 200 for `/api/chat` in **10.09 seconds**. The final answer was visibly observed at 18:10:16.199, **12.773 seconds after Send**; this latter value includes observation/tool delay, not just inference. A second synthetic writing request started at 18:10:46.837; Stop response at 18:10:56.265 cancelled it, retained the draft and did not append a late answer. The daemon logged the cancelled request as 500 after 9.03 seconds; this is retained as cancellation evidence, not a successful answer. Clear emptied the conversation by 18:11:26.272. Stop at 18:11:31.703 removed the owned daemon/supervisor and listener. Sheet reopening at 18:11:47.236 was empty and stopped. Subsequent app reopening also showed a fresh stopped assistant.

The external sampler targeted 0.2-second intervals and recorded RSS/physical footprint for the candidate and discovered descendants. During the successful response, sampled summed peak physical footprint was **1306.474 MiB**, RSS **3726.953 MiB**. Across the complete UI run including cancellation, peaks were **1308.209 MiB** and **3780.953 MiB**. These sums can count shared pages more than once; they are not incremental system-memory use, guaranteed lifetime peaks, or a performance benchmark. Unknown executable paths on very short-lived sampled processes are retained as unknown rather than assigned invented identities. Actual Ollama and inference runners were observed explicitly.

### Protected model-independent native job and reopen — PASS

The isolated request uses explicit synthetic capability evidence created for this test, with a two-hour diagnostic validity window. It is not real account evidence. A controlled-clock regression verifies acceptance within a synthetic interval and rejection at expiry; no real capability record was backdated, extended or relabeled. Request decode/validation returned exit 0. Production X/Instagram eligibility remains UNVERIFIED.

The corrected launch was the sole candidate PID **42091**, native window owner **42091**, window **446**. Its policy denied all networking, model reads and writes to every pre-existing job. Ollama execution was also denied by the retained core profile. The owned service was stopped. At 18:23:19.245, enabled Open in the native picker started `protected-diagnostic-request.json`; SwiftUI displayed QA_PASSED for **`dub-860a7223ba752b0434bda194`**. Observed FFprobe/FFmpeg processes were descendants of this exact protected candidate and had default outbound denial. No shell/ASR/Ollama invocation was needed by the model-independent job.

Source: existing authorized synthetic `model-independent-acceptance/offline-fixture/source.mp4`, **3.4 seconds, 320×180**, SHA-256 `e6f1166a2503e8da0b54d097cf91cfbda614b4ff1f00abfd20b00c9c1eecf47e`. Three diagnostic **720×1280** MP4s measured **1.200000, 1.200000, 1.000000 seconds**. Exact intervals are `[0,1.2)`, `[1.2,2.4)`, `[2.4,3.4]`, with no exclusions or gaps. All three independent full decodes returned exit 0 with no errors. The job has no transcript, uses deterministicTime planning, and retains Clip Index, clip_manifest.json, RECONCILE.md and job.json. The UI explicitly lists the four unavailable transcript-assisted features and states that local QA does not establish production completion. This tiny diagnostic proves the missing UI boundary; it does not replace the prior full-length acceptance.

Normal Quit was verified without a post-quit UI call. Reopened protected candidate **42674** displayed the accepted diagnostic job at 18:24:17.179. All three output hashes, sizes, nanosecond mtimes, modes, inodes and QA receipts, plus job.json bytes, were unchanged. Resume was not invoked. Ollama remained stopped. No accepted nine-output job was resumed or rendered. Exact source/output measurements, filenames and receipts are in `protected-ui-core-verification.json`; reopen readback is in `protected-reopen-verification.json`.

### Regression, build and preservation results

The first new regression run returned exit **1**: three tests, two failing test cases/three failed assertions (unchanged settings were replaced; home-data writes were allowed). The corrected focused run returned exit **0**, three tests passed; a fourth missing-identity canary case was included in the final suite. Final full suite: **exit 0, 50 executed, 47 passed, 3 skipped, 0 failures**, 19.445 seconds. The three skips are the same opt-in real-media and two offline entry points; the updated offline lifecycle/client harness separately passed **two tests, no skips**, direct exit **0**. The full-length real-media audit was not rerun.

Final native build returned exit **0**, with only the candidate bundle replaced. Seven staged bundle hashes match the build; strict signature checks returned **0** before and after testing. An intermediate diagnostic build failed (exit 65) for a temporary diagnostic's missing UTType import; that instrumentation was corrected, then entirely removed. The unsuccessful presentation experiment and all failed test logs remain in evidence.

Actual commands were run through the credential-stripping launcher from `/Users/frank/Documents/Joey`. Python orchestration recorded direct subprocess exit statuses and exact argument arrays in the corresponding `*-result.json` files:

```sh
python3 Tools/run-local.py /usr/bin/xcrun swift test --scratch-path /Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance/correction-1/spm --filter ProtectedLaunchTests
python3 Tools/run-local.py /usr/bin/xcrun swift test --scratch-path /Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance/correction-1/spm
python3 Tools/run-local.py /usr/bin/xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug -destination platform=macOS -derivedDataPath /Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance/correction-1/native-build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
JOEY_LOCAL_ASSISTANT_SMOKE=1 python3 Tools/run-local.py /Applications/Xcode.app/Contents/Developer/usr/bin/xctest -XCTest JoeyCoreTests.LocalAssistantOfflineTests/testExplicitStartOfflineReplyAndOwnedStop /Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance/correction-1/spm/out/Products/Debug/JoeyCoreTests.xctest
python3 Tools/run-local.py /usr/bin/codesign --verify --deep --strict '/Users/frank/Applications/Joey Native Acceptance.app'
```

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` was supplied to build/test children without changing global xcode-select. Protected launches used `/usr/bin/sandbox-exec -f <assistant-protected.sb | core-final-protected.sb | reopen-protected.sb> '/Users/frank/Applications/Joey Native Acceptance.app/Contents/MacOS/Joey'`, through sanitized Python subprocess arguments. Runtime protection was verified before launch; no original permissions or data locations were changed to create isolation.

Final preservation/restoration returned exit **0**. All **148** saved baseline hashes, sizes and modes match; **146** also match every recorded metadata field. Settings bytes/mtime and effective preferences match backup. Settings inode changed during early pre-fix launches; preferences inode/mtime changed through picker updates and restoration. These differences are documented, not described as metadata-identical. Original native/legacy bundles, full-length source/transcript, nine accepted clips/receipts/checkpoint and prior evidence remain unchanged. The two new isolated synthetic jobs remain as evidence. Existing local-identity inode/mtime/size/mode values are unchanged; no key contents were read or copied. No candidate, owned Ollama/runner or diagnostic UI process remains; no listener remains. The candidate stays staged and is not promoted.

**Final gate statuses:** staging/signature PASS; runtime protection PASS for the corrected run; actual SwiftUI assistant controls/reopen PASS; actual-process network isolation PASS for the corrected runs; model-independent clipping through UI PASS; bounded performance measurement PASS; preservation/restoration PASS. No remaining blocker for this bounded gate. Separate production delivery, account compatibility/ingestion, original-installed-build acceptance and exposed-credential owner-confirmed revocation remain unchanged.

## First candidate installation and SwiftUI attempt — historical, 2026-10-31

This section supersedes the earlier installation/UI status below; earlier implementation and offline evidence remains historical and valid. Frank explicitly accepted the prior instruction, “Integrate the existing local assistant into Joey as an optional, user-initiated feature,” as resolving scope. The feature is inside Joey's interface, not a second application. The acceptance bundle is a staged candidate of that same application, not a replacement product.

Checkout: `codex/native-consolidated`, HEAD `517878ff9c13911bf8d033c517492ef51ccffca7`, origin `https://github.com/franklinburrus/Joey.git`. Pre-existing dirty source and Xcode changes were preserved. This gate changed documentation and local test evidence only; no application source, model, credential, delivery or production-profile changes were made.

Evidence root: `/Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance`.

### Staging and protection — PASS

The existing verified Debug build was copied to `/Users/frank/Applications/Joey Native Acceptance.app`. All seven bundle file hashes match the source build. Both initial and final `codesign --verify --deep --strict` returned exit 0. This establishes local signature integrity, not notarization or a production release. Both original installed apps remain intact. Rollback is to quit the candidate and use the untouched installed native app; neither original was launched by this gate.

The application has no supported acceptance-data-root override. Its startup can inspect resumable jobs automatically. Before launch, non-job runtime state and the app preferences domain were backed up to `shared-state-backup`; 148 files were recorded in `preservation-before.json`. The only existing job was QA_PASSED and not resumable, but protection did not rely on that fact. Both launch profiles deny writes to its directory, shared assets/helpers, original source, prior evidence, installed applications and credential locations. Unlinking the jobs/runtime roots is denied. Settings remain writable with a recoverable backup. No original permission or production-data location changed.

The same-profile preflight used a nontruncating O_WRONLY open of existing job.json: denied with errno 1. External TCP to `1.1.1.1:443` was denied with errno 1. Actual candidate process policy readback confirmed denied job/credential writes. Receipts: `preflight.json`, `protection-preflight.json`, `actual-candidate-policy.json`, `actual-core-policy.json` and the two retained `.sb` profiles.

### Actual assistant SwiftUI lifecycle — FAIL; dependent checks BLOCKED

All times below are UTC on 2026-10-31. Protected candidate PID 29077 launched at 17:33:26. The assistant sheet opened at 17:34:05.800; synthetic text was entered by 17:34:18.149. At 17:34:51.303819, there was still no listener. Launch, opening and typing did not start Ollama.

Start was clicked at 17:34:55.746. The UI reported exactly: “macOS could not apply the local-only service sandbox. Media jobs are unaffected.” The nested-profile diagnostic returned `sandbox-exec: sandbox_apply: Operation not permitted`, direct exit 71. Joey's service owner tries to apply a child sandbox while the candidate already carries the externally imposed protection profile. That operation failed; no unrestricted fallback or manual replacement service was used. No Ollama process started, so its actual-process network and memory checks are BLOCKED.

Send at 17:35:16.207 produced, by 17:35:16.675: “Local assistant unavailable. Start your existing local Ollama service, then send again. Media jobs are unaffected.” The draft remained. Clear at 17:35:21.332 cleared the editor and error. Closing/reopening at 17:35:30.341 showed an empty conversation and initial stopped state, with Stop disabled. Successful inference, cancellation of a real response and owned-service Stop remain BLOCKED. The 0.468-second Send-to-observation interval measures only an unavailable-service UI observation, not model response time. The first candidate was quit through Joey's menu and its absence confirmed.

Network result: **actual candidate isolation PASS; complete candidate-plus-Ollama gate BLOCKED.** Candidate PID 29077's outbound default was denied with loopback exceptions; the second candidate PID 30448 denied all networking. Policy readback applied to the actual executable path/PIDs, not only the probe. No Ollama process existed to inspect. The 0.2-second descendant sampler saw only the candidate; short-lived helpers could fall between samples, so this is not proof that every possible child was individually sampled.

### Model-independent clipping through UI — BLOCKED

PID 30448 launched at 17:36:30 under `core-ui.sb`, denying all networking, model-directory reads and execution of the installed Ollama binary. Actual process readback confirmed model reads and outbound networking denied. Its cross-process process-exec policy query returned -1, causing that initial assertion command to exit 1; it is not counted as a passing query. A supported probe under the identical profile then attempted model open, Ollama execution and loopback connection: all denied with errno 1, direct exit 0 (`core-denial-probe.json`). No model file was moved, deleted or changed.

Setup → Import job request opened the actual native file picker. The selected `core-request.json` used the existing authorized 3.4-second synthetic source, a fresh source ID, modelIndependent policy, no exclusions and fileToDrive=false. Expected plan was three diagnostic intervals of 1.2, 1.2 and 1.0 seconds. Open remained disabled after row selection, double-click and Return. Actual process policy allowed reading the request (`picker-file-access.json`). Sampling PID 30448 for one second returned exit 0; its main thread was in the normal AppKit event wait, not proof of a blocked coordinator. The picker cause remains unresolved.

Escape inspection then returned `Computer Use server error -10005: noWindowsAvailable`; a further state/screenshot request returned `Computer Use server error -10005: timeoutReached`. These do not establish a physical screen lock. After verifying its exact executable path, the test PID received SIGTERM; process absence was confirmed. The retained cleanup timestamp is in `cleanup-action.json`. No job or output was created. The diagnostic request also retained an expired fixture capability validity date (16:14:29 UTC), an independent input prerequisite for any later attempt; the application never reached that validation here. No dates were extended or production safeguards bypassed. Existing model-independent core test evidence remains PASS but does not satisfy this UI gate.

### Performance — inference BLOCKED; UI memory measured

`monitor.py` sampled `proc_pid_rusage` RSS and physical footprint for the candidate and discovered descendants every 0.2 seconds. Actual intervals include tool/scheduler overhead. `performance-summary.json` retains counts and byte values.

| Run | Samples / observed span | First footprint / peak | First RSS / peak |
|---|---|---|---|
| Assistant UI, idle/failed start | 441 / 109.772 s | 44.063 / 56.079 MiB | 115.172 / 143.344 MiB |
| Core UI/picker, from early startup | 1454 / 363.645 s | 3.735 / 47.079 MiB | 13.234 / 121.469 MiB |

These are sampled peaks, not guaranteed process-lifetime peaks. The independent `sample` report showed 36.4M current / 57.0M lifetime peak footprint for the core candidate at its observation. No inference ran; response speed, token rate and model-loaded memory remain unmeasured. The earlier arithmetic smoke test remains functional evidence only.

### Commands, cleanup and preservation

All executable diagnostics/installations were launched through `python3 Tools/run-local.py`, including Python orchestration using direct subprocess arguments. The actual staged copy and executable launch commands were:

```sh
python3 Tools/run-local.py /usr/bin/ditto '/Users/frank/Library/Caches/Joey-Native-Build/credential-incident/native-build/Build/Products/Debug/Joey.app' '/Users/frank/Applications/Joey Native Acceptance.app'
python3 Tools/run-local.py /usr/bin/codesign --verify --deep --strict '/Users/frank/Applications/Joey Native Acceptance.app'
```

The sanitized Python orchestration launched these exact argument arrays (captured in `candidate-pid.json` and `core-pid.json`):

```text
/usr/bin/sandbox-exec -f /Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance/assistant-ui.sb /Users/frank/Applications/Joey Native Acceptance.app/Contents/MacOS/Joey
/usr/bin/sandbox-exec -f /Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance/core-ui.sb /Users/frank/Applications/Joey Native Acceptance.app/Contents/MacOS/Joey
```

These were asynchronous GUI launches, not successful XCTest results. UI actions used the authorized native computer-use tool only. The preservation verifier and restoration script each returned direct exit 0. Settings bytes had never changed; their modification time was restored. Only two preference keys changed (`NSWindow Frame GoToSheet`, `NSOSPLastRootDirectory`); `defaults import devplaceholder.C88ISLGM.Joey <backup>` returned 0, and `defaults export ... -` returned 0 and matched the backup's effective values. No preference daemon was killed.

Final result: **preservation PASS.** All 148 baseline hashes/sizes match; 146 files retain all recorded fields. Settings inode changed through atomic save; preferences inode/mtime changed through normal updates/restoration. Their bytes and values match the baseline. The installed native/legacy bundles, source/transcript, nine accepted clips, QA receipts, checkpoint and prior evidence remain unchanged. The sole production job directory remains the sole job. No saved-application-state directory appeared. Local identity metadata remains unchanged, without reading key contents. No candidate/Ollama process or listener remains. Candidate still matches its seven staging hashes and strict signature verification exits 0. Receipts: `changes-before-restoration.json`, `restoration.json`, `preservation-after.json`, `preservation-final.json`.

No test suite was rerun. The prior 46-test suite's three skips were `RealMediaTests.testAuthorizedRealMediaRenderers` (real-media opt-in absent; prior acceptance reused) and `LocalAssistantOfflineTests.testExplicitStartOfflineReplyAndOwnedStop` / `testNetworkDeniedClientResponse` (opt-in tests separately passed by the earlier headless harness). None proves the failed/blocked UI steps passed. No accepted-media rerender is needed to resolve this gate.

The candidate is not approved for promotion by these results. Remaining work is a scoped correction to protected service startup, picker diagnosis and valid test-only fixture input, followed by only the missing UI/performance checks. No security bypass or new architecture is presumed authorized. Production remains PARTIAL; local-media/core evidence, Drive filing, register reconciliation, actual platform compatibility/ingestion and owner-confirmed credential revocation remain separate.

## Implemented boundary

The native toolbar opens a separate assistant sheet for conversation, writing, summarization, planning and coding questions. Nothing starts or sends when the sheet opens. The user types or pastes text, selects Send, and can stop a response or clear the conversation. The conversation stays in memory and clears on close. No file chooser, clipboard scan, media-job attachment, account adapter, command executor or publishing capability is available to model output. Answers render as selectable plain text; generated code is not executed.

`AssistantConversation` owns only text and a cancellable request. It has no Coordinator, transcription, rendering, QA, records or delivery references. Failure preserves the unsent draft and existing completed turns. Cancellation/clear invalidates the current attempt so a late reply cannot restore cleared text. Repeated Send cannot queue concurrent requests. Media processing disables the assistant entry and requests; a media-busy transition cancels assistant activity to limit memory contention on this M1/16 GB Mac.

`LocalAssistant` uses an ephemeral Foundation URLSession at fixed `http://127.0.0.1:11434`. Only `/api/tags` and `/api/chat` are called. Redirects and authentication challenges are rejected; proxies, shared credentials, cookies and caching are disabled. It checks the installed model identity before every chat and rejects changed/missing models without pulling, substituting or retrying. No API key or cloud endpoint is present.

Resource limits: one request per conversation, 6,000 UTF-8 bytes across complete conversation text, at most 41 input turns, 8192 context tokens, at most 1024 generated tokens, 512 KiB response capture, 5-second metadata request timeout, 120-second chat request timeout and 180-second resource timeout. The conservative byte budget leaves room for the template, system instruction and output inside 8K without adding a tokenizer dependency. `keep_alive: 0` requests immediate model unload after a response. An output-limit stop is explicitly identified; history is not silently summarized or truncated.

The installed Qwen template always pre-fills a thinking block. Live verification showed `think:false` could return reasoning in final content, including a prefix missing its opening tag. The corrected client requests Ollama's structured thinking output and consumes only `message.content`; `message.thinking` never enters displayed or retained conversation text. An explicit leading `<think>…</think>` wrapper is also removed defensively; unfinished/reasoning-only responses are rejected. Literal tags elsewhere or inside fenced examples are preserved. This is response separation, not a claim that reasoning computation is disabled or faster.

## User-controlled service lifecycle

Frank explicitly selected Start/Stop controls. A separate, supervised service owner starts the existing executable only on Start. It uses fixed sanitized local configuration, `OLLAMA_NO_CLOUD=1`, `127.0.0.1:11434`, the existing model directory, `OLLAMA_NOPRUNE=1`, one loaded model, one parallel inference and no debug logging. A macOS child sandbox denies external networking and model-store writes. If sandbox application fails, startup fails closed; there is no unsandboxed fallback.

Stop and closing the assistant terminate only the process tree Joey owns. A pre-existing compatible listener can be used but is never killed by Joey. Duplicate Stop calls await the same shutdown task, and Start cannot race ongoing shutdown. The existing process supervisor handles parent disappearance and descendant cleanup. The media coordinator was not changed.

Before authorization, a restricted startup probe observed: `Error: open /Users/frank/.ollama/id_ed25519: operation not permitted`. Both identity files remained absent. Frank then explicitly authorized Ollama's local identity pair only. The next authorized startup regenerated the standard private/public pair; the private file is mode 0600 and public file 0644. Their contents were not read, printed or copied into evidence. They remain in Ollama's normal local storage. No API key, API billing, cloud sign-in, replacement credential or Google integration change occurred.

## Installation and model identity

- Existing app: `/Users/frank/Applications/Ollama.app`, version `0.40.13`.
- Existing executable: `Contents/Resources/ollama`; SHA-256 `270089e59e1d411ac4d0987154b4e95f48b29a81c9d274833c6b766d6df88300`.
- Existing model: `qwen3:4b`, Q4_K_M, 4.0B, GGUF, Apache-2.0; model storage `~/.ollama/models`.
- Verified API model digest: `359d7dd4bcdab3d86b87d73ac27966f4dbb9f5efdfcc75d34a8764a09474fae7`. This is the installed manifest layer used by this Ollama version, not the SHA-256 of the outer on-disk wrapper manifest.
- Wrapper manifest SHA-256: `31d9857b5705086d352d4d6db04e86c5d0f6a2b5d59a4dc7ce5cdb271ccf9141`.

No model copy, dependency installation or model download was made. Existing build caches were reused because the volume had 18 GiB free at preflight. The installed Joey Native and legacy app bundles were preserved. The new native build was not installed or opened against production jobs.

## Implementation verification

**PASS — scoped source integration and native build.** Final native build returned direct exit 0 (`native-build-structured-final.log`). The launcher regression suite returned direct exit 0, 5/5 passed (`launcher-tests.log`). The new assistant-specific tests passed 13/13, including structured-content separation and preserved literal markup. The final shared-core suite returned direct exit 0: 46 executed, 43 passed, 3 intentional opt-in skips, 0 failures/errors, 20.458 seconds (`full-suite-verified.log`). The skips are the existing real-media test and the two installed-model test entry points, which are exercised separately by the explicit offline harness. Existing model-independent and transcript-assisted tests still pass without an Ollama service or model requirement in the ordinary suite.


Evidence root: `/Users/frank/Library/Caches/Joey-Native-Build/local-assistant`.

The initial assistant contract test failed as expected: direct exit 1, one test/one failure, `Local assistant is not implemented` (`red.log`). Subsequent tests exercise exact loopback requests, explicit text/history, model identity, invalid/oversized input, bounded output, no tools/auth/cookies, HTTP failure without raw error echo or retry, malformed/tool responses, redirect rejection, cancellation, failed-draft retention, clear/late-result protection and external-service ownership. A second targeted regression reproduced the observed reasoning-wrapper defect before correction (`reasoning-red.log`: exit 1, one test/three assertions).

An independent read-only review found and prompted fixes for duplicate-Stop state races and a smoke harness that originally checked only child exit status. The final harness requires network-denial and response markers plus exactly one passing child test; zero tests or skips cannot count as offline success.

Commands run from `/Users/frank/Documents/Joey` through the credential-stripping launcher:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tools/run-local.py /usr/bin/xcrun swift test --scratch-path /Users/frank/Library/Caches/Joey-Native-Build/credential-incident/spm

python3 Tools/run-local.py /opt/homebrew/bin/python3 -m unittest discover -s Tests -p test_tool_environment.py -v

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tools/run-local.py /usr/bin/xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug -destination platform=macOS -derivedDataPath /Users/frank/Library/Caches/Joey-Native-Build/credential-incident/native-build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

Native UI evidence is compilation only. No installation or SwiftUI interaction/reopen acceptance is claimed. The prior installed-app GUI acceptance remains open.

## Real offline verification

**PASS — actual installed model through the same client/service owner as SwiftUI.** `offline-structured-final.log` records direct exit 0, one parent lifecycle test and one child inference test, each passed with zero failures/skips. External TCP was denied with `EPERM`; the retained final reply was exactly “2 plus 2 equals 4.” The owned listener was unavailable after Stop and in `service-after.json`. Neither the Ollama GUI nor the installed Joey GUI was opened.


The test explicitly starts and stops the same service owner used by SwiftUI, using the installed executable/model. It launches an inference-client test under the same production sandbox profile. The client asserts an external TCP connection to `1.1.1.1:443` is denied with `EPERM`, then sends one synthetic arithmetic question through the actual `LocalAssistant`. The server independently runs under that profile, with cloud disabled. The final answer must be nonempty, short, contain the correct answer and contain no reasoning tags. Duplicate Stop and Start-during-shutdown are exercised; the original listener must be unavailable afterward.

```sh
JOEY_LOCAL_ASSISTANT_SMOKE=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tools/run-local.py /Applications/Xcode.app/Contents/Developer/usr/bin/xctest -XCTest JoeyCoreTests.LocalAssistantOfflineTests/testExplicitStartOfflineReplyAndOwnedStop /Users/frank/Library/Caches/Joey-Native-Build/credential-incident/spm/out/Products/Debug/JoeyCoreTests.xctest
```

Earlier failed attempts are retained: the first sandbox profile used an unsupported numeric address form (exit 65), corrected to the supported `localhost:*` form; putting the service-owner test inside another broader sandbox caused service sandbox application failure (exit 1), corrected by independently sandboxing the daemon and actual inference client at their launch boundaries; the initial digest pin incorrectly used the wrapper-file hash (exit 1 readiness timeout), corrected using actual `/api/tags` readback and the corresponding installed manifest layer. No failure triggered remote inference or download.

The short response establishes functional offline integration, not a speed, quality, long-context or coding benchmark. No claim is made about general answer accuracy. The assistant has no production media authority.

## Preservation and remaining acceptance

`preservation-final.json` records 124 prior source/transcript/nine-output/checkpoint/receipt/installed-app/evidence identities plus 18 model-independent fixture identities unchanged by SHA-256, size and nanosecond modification time. The Ollama executable and wrapper manifest identities also remained unchanged; all six referenced model/config/template/license/manifest blobs matched their content-addressed hashes and declared sizes. This was preservation verification, not a rerender or a repeated media audit.

Implementation tests/build, real offline inference, and installed SwiftUI acceptance remain separate statuses in STATUS/VERIFICATION. Drive filing, register reconciliation, platform compatibility/ingestion and publication were not exercised. No push, merge, installation or accepted-media rerender occurred. The separate exposed API-key incident remains open until its owner confirms revocation.
