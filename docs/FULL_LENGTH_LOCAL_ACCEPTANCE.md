# Full-length local acceptance

Status: **PARTIAL**. Local full-length media QA, network-denied operation, interrupted-processing recovery and all-nine-output installed-core/checkpoint reuse passed. Final SwiftUI inspection/reopen is separately unavailable; requirements and downstream dependencies remain open. This record concerns the explicitly requested local milestone, not product completion or delivery. Evidence remains outside Git at `/Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance`.

## Authorization and scope

Frank requested one complete existing authorized native-video source through the installed SwiftUI app, actual 8–10-minute clips where feasible, complete retained coverage, local records, interruption/recovery, reopen/reuse and operation without networking. Upload, register mutation and publication are excluded. Repository replacement, merging to main and modification of legacy Joey are excluded.

Frank separately authorized a temporary network-denied command-line launch of the installed app and its helpers, with SwiftUI job actions, no system-wide networking change, no disabled safeguards and no bypass of tool restrictions. Terminal UI control was denied by the computer-use tool; it was not used. The authorized command-line tool launched the app under macOS `sandbox-exec` instead.

## Identity and preservation

GitHub connector lookup by numeric ID returned **1440349888**, `franklinburrus/Joey`, URL `https://github.com/franklinburrus/Joey.git`. Baseline branch: `codex/native-consolidated`; baseline HEAD: `517878ff9c13911bf8d033c517492ef51ccffca7`. The only baseline dirty file was `Joey.xcodeproj/xcuserdata/frank.xcuserdatad/xcschemes/xcschememanagement.plist`, SHA-256 `ffb4628f56d8b88bd7361da04a9b915c6e1ac6772c88b23dd34f76439cceb7c2`.

Installed `/Users/frank/Applications/Joey Native.app` initially matched all 7 files in the prior installation receipt. Its bundle ID is `devplaceholder.C88ISLGM.Joey`. `codesign --verify --deep --strict --verbose=2` returned exit 0. The baseline includes hashes of the separate legacy `/Users/frank/Applications/Joey.app` for final preservation readback.

The initial native file picker selected the JSON request but left Open disabled; repeated Open/Return/double-click did not accept it and Cancel/Escape timed out. A sample located the synchronous `NSOpenPanel.runModal()` inside the SwiftUI action. A separate SDK-default probe confirmed `canChooseFiles=true`, `canChooseDirectories=false`, unrestricted content types; those defaults were not the cause. The scoped repair changes the picker to asynchronous AppKit completion and adapts its four call sites. The updated build returned direct exit 0 (`chooser-build.log`). The old installed bundle is preserved at `installed-before-chooser-repair.app`; `chooser-installed.json` records the replacement bundle hashes. After repair, selecting the JSON enabled Open and the GUI action started the coordinator. This is an observed intake regression/repair, not a new application or repository.

## Requirements and approval evidence

The exact earlier user decision is in ChatGPT “Start-Up,” chat `6ae534ec-9b44-83e9-a246-224ab1bda31b`, user message `262e961d-272e-4ec2-b6b3-7303d09d8951`: **“No AI dependency for core operations.”** This was a user-authored confirmed decision, distinct from assistant proposals.

The later user attachment `/Users/frank/.codex/attachments/76b90115-84c5-4fb8-b628-936fed13a09e/Pasted text.txt`, retained in current `docs/REQUIREMENTS.md`, explicitly directs use of the consolidated specification and requires in section 7: **“Generate or reuse a complete timestamped, source-bound transcript locally. Use it for boundaries, titles, ad identification and coverage reconciliation.”** It explicitly supersedes earlier video additions, duplicate platform variants, destinations and human-QA holds. It does **not** explicitly state that AI/model inference may become mandatory for core operations.

Current behavior: `Coordinator.run` unconditionally obtains a transcript before planning. `Acquisition.transcript` reuses a matching local transcript or accepts a supplied source-bound transcript; otherwise it requires an existing Python ASR helper and installed model. Thus a new untranscribed source cannot currently complete without model inference or an externally prepared transcript. No explicit user waiver resolving that model-independent-core conflict was found in the reviewed Start-Up and SwiftUI App Requirements user decisions or consolidated request. “No paid AI,” “no remote AI,” and “no AI dependency” are not treated as synonyms.

This acceptance run reuses the existing complete transcript and preserves its MLX Whisper provenance. It tests processing with an already-present input and does not establish model-independent operation for new untranscribed originals. Transcription features remain intact. The broader product conflict remains an explicit decision dependency; it does not prevent this cached-input local test.

## Source, profile and expected plan

Authorized original: `https://x.com/i/broadcasts/1oKMvNPnEzDGQ`, identity `x:broadcast:1oKMvNPnEzDGQ`, title “Can’t DUB Me Radio: PACK EM UP!!!!”. Existing path: `/Users/frank/Dub/work/dub-clips/1oKMvNPnEzDGQ/source/source.mp4`. No copy or relocation of the original was needed.

- SHA-256: `2dc4e7c4e639ef56f9c28bb43e761c1a757d04c83e0dc66e03b38d50433a51fe`.
- Size: 2,359,633,468 bytes. Measured duration: 4,729.152333 seconds (78:49.152333).
- Source picture: 1920×1080. Exact streams are recorded in `source-probe.json`.
- Existing transcript: 1,589 segments, source ID/hash match, original SHA-256 `837d2c9eeb9b196a3bda8343c8041ec85019af2574a509aab7009bf4abc6813a`. Complete-source ASR provenance is retained; accuracy is not claimed independently verified.
- Selected planning target: 600 seconds with natural boundaries in 480–600 seconds. Full source selected; no identified ad exclusions.
- Diagnostic export: 720×1280, 30 fps, H.264/yuv420p, AAC-LC. Effective source picture: 720×404, proportionally padded in black. No added logo, title, captions, template or outro.
- Diagnostic hard ceiling: 660 seconds and 512,000,000 bytes per file. The planner still targets at most 600 seconds; the diagnostic ceiling leaves room for encoder duration rounding. This is not account-entitlement evidence.

`full-length-request.json` is visibly titled **DIAGNOSTIC LOCAL ONLY**, has `fileToDrive=false`, and is imported as a job through SwiftUI. Production profile settings are not changed. The legacy profile schema's account fields explicitly say `DIAGNOSTIC-NO-ACCOUNT-ELIGIBILITY`; its evidence text disclaims actual account eligibility and forbids production use. Network isolation additionally prevents provider access. No diagnostic profile is imported as a verified production setting.

| Clip | Expected source start | Expected source end | Expected seconds |
| --- | ---: | ---: | ---: |
| 1 | 0 | 600 | 600 |
| 2 | 600 | 1123.58 | 523.58 |
| 3 | 1123.58 | 1694.76 | 571.18 |
| 4 | 1694.76 | 2294.76 | 600 |
| 5 | 2294.76 | 2894.12 | 599.36 |
| 6 | 2894.12 | 3385.3 | 491.18 |
| 7 | 3385.3 | 3969.6 | 584.30 |
| 8 | 3969.6 | 4478.20 | 508.60 |
| 9 | 4478.20 | 4729.152333 | 250.952333 |

The final clip is an explicitly recorded retained-remainder exception. The first eight are expected to be 8–10 minutes. Actual rendering measurements are recorded below, separately from this expected plan.

## Actual isolation and GUI execution

The temporary profile is exactly:

```scheme
(version 1)
(allow default)
(deny network*)
```

The authorized launch command is:

```sh
/usr/bin/sandbox-exec \
  -f '/Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance/offline.sb' \
  '/Users/frank/Applications/Joey Native.app/Contents/MacOS/Joey'
```

A control executable under this profile exited 0. Curl failed DNS resolution (exit 6); a separate direct-IP socket connection to `1.1.1.1:443` failed with `PermissionError: [Errno 1] Operation not permitted` (exit 1). More importantly, `sandbox_check` on the actual running app PID 32243 and its supervisor/FFmpeg children returned 1 (denied) for network inbound and outbound. File-read permission remained allowed; an unconfined control process returned 0 for network outbound. Evidence: `offline-socket-probe.json`, `live-sandbox-check.json`, `offline-processing-processes.json`.

Through SwiftUI, Setup → Import job request selected `full-length-request.json`; Open started the job. Actual durable job ID: `dub-6a9c4dcb2874abc2e48f43e3`, under `~/Library/Application Support/Joey Native/jobs/`. The full-source decoder ran as a child of the installed, isolated app. No CLI `joey-run run` was used for this job.

## Sheets prerequisite — separate integration status

Correction to the earlier report: `dubdrive` uses a **custom configured client**, not rclone's built-in client. Current public OAuth client ID is `145289518259-9sr6c2alldhso34dvrpi05ll0kiv0kee.apps.googleusercontent.com`, project number **145289518259**. Installed rclone v1.74.4's default client is `202264815644.apps.googleusercontent.com`, confirmed against its official source. The actual Cloud project/IAM owners are **not established** from the local client ID; Frank's ownership must not be inferred.

The earlier standalone response was Sheets HTTP 403, indicating Sheets API unused/disabled in project 145289518259. In this milestone the existing stored access token was expired and rejected: tokeninfo HTTP 400 `invalid_token`; direct Drive/Sheets reads HTTP 401 `UNAUTHENTICATED`. No refresh, rotation or new authorization was performed. This newer authentication result does not establish that the earlier API-enablement issue is repaired.

Required, separately verified prerequisites:

1. Identify the owner/authorized administrator of Cloud project 145289518259 and its OAuth client. Do not infer ownership from the repository or rclone remote.
2. That authorized project administrator must verify/enable `sheets.googleapis.com` if still disabled. Google lists `serviceusage.services.enable` as the permission for enablement. This milestone does not authorize Cloud changes.
3. Verify actual granted OAuth scopes after normal authorized token availability. Local rclone configuration says `scope=drive`; this is configuration, not current token introspection. Full `https://www.googleapis.com/auth/drive` is accepted by Sheets values-update APIs, so adding a separate `spreadsheets` scope is not automatically necessary. Any scope widening needs separate authority.
4. Verify the authenticated account can edit the exact existing Master Link List `17uhDO06vmVEz96YrUnA6aHyV5fL_3AAs3ylOjrYRLwI`, then read current tab/schema. Drive permission and API enablement are distinct. Current access could not be revalidated using the rejected stored token. No test write is authorized during this local milestone.

Authoritative references: [rclone v1.74.4 Drive client source](https://github.com/rclone/rclone/blob/v1.74.4/backend/drive/drive.go), [Sheets get scopes](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/get), [Sheets values.update scopes](https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets.values/update), [Google Service Usage enablement](https://cloud.google.com/service-usage/docs/enable-disable).

## Acceptance results

The installed application reached `QA_PASSED` at 2026-10-31T03:33:00Z. The progress-monitor process and independent output audit each returned direct exit **0**. All **9/9** outputs passed; no failed output remains. The audit independently probed and hashed each accepted file and reconciled the app's decoder/audio/picture QA receipts, source intervals, render recipe and local records. This was an actual full-source GUI-started job, not a planner test or short renderer fixture.

| Lane or criterion | Result | Evidence and limit |
| --- | --- | --- |
| Local media QA | **PASS** | Nine MP4s, exact retained interval coverage, measured durations, source-only presentation and canonical local records verified. Diagnostic profile only. |
| SwiftUI intake | **PASS** | Installed app's repaired file picker imported the request and started the full source job. |
| Network-unavailable local processing | **PASS** | Direct socket denied; actual app, supervisor and media-helper PIDs denied inbound/outbound networking, including recovery. Existing source/transcript/dependencies reused. |
| Interrupted local processing | **PASS** | App killed during clip 2; no orphan writers remained; isolated relaunch resumed clip 2 and reused accepted clip 1 unchanged. Nine unique accepted outputs at finish. |
| Final SwiftUI result inspection | **GUI INSPECTION UNAVAILABLE** | Computer-use tool reports: `The Mac is locked and automatic unlock could not unlock it. Ask the user to unlock the Mac manually before continuing.` Durable local readback succeeded; this does not substitute for final UI inspection. The continuation below corrects the earlier inference of physical lock state using independent session observations. |
| All-nine-output core/checkpoint reuse | **PASS** | Authorized non-GUI resume linked the actual installed core binary. All output identities, timestamps and QA receipts remained unchanged. This does not substitute for SwiftUI reopening. |
| Final installed SwiftUI reopen | **GUI INSPECTION UNAVAILABLE** | Native automation cannot access the session; exact errors, session indicators and recovery attempts are recorded below. |
| Drive filing | **NOT ATTEMPTED** | Excluded by this milestone, `fileToDrive=false`; zero verified Drive clips. |
| Register reconciliation | **NOT ATTEMPTED / integration BLOCKED** | No writes authorized. OAuth/API/access prerequisites above remain unresolved. Local CSV is not a register write. |
| Social-platform ingestion | **NOT ATTEMPTED** | No upload/publication; real account eligibility and ingestion unverified. |

### Measured outputs

All files are H.264/yuv420p, progressive, square pixels, 30 fps, 720×1280 with 720×404 source picture, AAC-LC stereo at 48 kHz, and fast-start MP4 ordering. Exact filenames, sizes, hashes, source mappings, ffprobe commands/results and QA receipts are retained in `output-measurements.json`. Filenames were separately checked for sequence, source identity and start/end timestamps by `capture_reuse.py before-reopen` (direct exit 0).

| Clip | Measured seconds | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| 1 | 600.0 | 56,265,597 | `90b23c335b8694de779e240790fa1ae8bc3852a98fcf9f323376c6cf38e9e56f` |
| 2 | 523.6 | 49,724,330 | `2fa7ffba759f41240e15bed88b0d69c6f0d61536cf2ebe0cd2100370290f1205` |
| 3 | 571.2 | 53,660,511 | `8fdceb5dea3726fd99eec50ffd4470022705c37ddf2dcb219156f74859857dd2` |
| 4 | 600.0 | 56,282,986 | `ad81fd99d542623f4df89ec10e6e3c0598d41e1837e1b633e112649ff8ee7de3` |
| 5 | 599.366667 | 50,815,824 | `67f403ae01e0d0351d8ee969cd3c35b6a81e8e59fb58b4b79331d98f4742f46d` |
| 6 | 491.2 | 53,439,837 | `498f15148f7d01ddbba0fced1cf9db24e53743894b22478109fd84f647f3d8df` |
| 7 | 584.3 | 56,042,393 | `36c71c5c62f2cc7689125d93daab17640f20c53e8efa80a3889c566319b7f7eb` |
| 8 | 508.6 | 51,634,478 | `dea2fc258187e25bad48031e8f8d5f63bf256effe7d4c5c54af1b31936835f96` |
| 9 | 250.952 | 25,213,380 | `f5796132634f373480fe0490a68f8b7bcd0674929ee014145b35c38a7da25dde` |

The retained source intervals cover **0–4729.152333 seconds exactly once**, without exclusions or gaps. Per-file encoded-duration tolerance is **0.075 seconds**; measured encoded durations are not asserted to sum exactly to the source duration. The short ninth clip preserves the actual ending. Its video stream is 250.900 seconds and audio 250.952 seconds, within the documented tolerance.

Each clip passed full decoding. Audio checks compare one-second channel windows at 12 kHz, including silence; minimum zero-lag correlation across outputs is **0.9784607448564604**. Whole-frame picture checks sample at 2 fps at 160×284 grayscale; maximum per-clip mean error is **0.1407393632629108/255**. Source-only recipes and picture checks support no added artwork, logo, captions or outro. These checks do not claim exhaustive semantic viewing or independently verified transcript accuracy.

The package has exactly nine accepted MP4s, one canonical nine-row CSV index, a full 1,589-segment transcript, `clip_manifest.json` and `RECONCILE.md`. Source/output mappings, QA hashes and local status agree. The index has no fabricated Drive links, and no filing/register receipts exist. Evidence: `local-acceptance-audit.json`, `after-full-run-job.json`, `output-audit.log`.

### Recovery and remaining GUI action

After clip 1 passed, app PID 32243 was deliberately sent SIGKILL while clip 2 had a partial file larger than 500,000 bytes. `orphan-cleanup.json` records no remaining supervisor/media writers. The same installed app was relaunched under the same network-denied profile as PID 33939. Its durable checkpoint resumed rendering clip 2; clip 1's SHA-256, nanosecond modification time and QA receipt remained unchanged through final acceptance. `interruption.json`, `initial-recovery-readback.json` and `recovery-process-isolation.json` retain that evidence. Disposable interrupted scratch is not counted as a duplicate accepted output.

Earlier attempts returned a lock-related tool error after outputs finished. That error alone did not establish physical lock state; the continuation below supersedes that interpretation. No lock or tool restriction was bypassed. The authorized non-GUI core resume has now passed. When native GUI access is available, inspect and reopen this existing job through SwiftUI as a separate check, capturing fresh before/after identities for that action. Do not restart the media job, rerender accepted clips or create another job.

### Actual commands and preservation

The scoped picker repair was built with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug \
-destination 'platform=macOS' \
-derivedDataPath '/Users/frank/Library/Caches/Joey-Native-Build' \
CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build \
> /Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance/chooser-build.log 2>&1
```

Direct exit **0**. The repaired picker enabled Open and the actual SwiftUI import started processing. The shared core was unchanged; the earlier 24/24 suite is historical evidence, not a newly executed suite in this milestone.

```sh
python3 -u '/Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance/audit_outputs.py' \
> '/Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance/output-audit.log' 2>&1
python3 '/Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance/capture_reuse.py' before-reopen
codesign --verify --deep --strict --verbose=2 '/Users/frank/Applications/Joey Native.app'
```

Each returned direct exit **0**. The audit invokes `/opt/homebrew/bin/ffprobe -v error -show_streams -show_format -of json` for each actual file; complete argument arrays and output are in `output-measurements.json`. The network-denied launch command appears above. No `joey-run` execution substituted for this GUI job.

Final preservation readback at 2026-10-31T03:34:31Z passed: original source/transcript hashes unchanged; legacy app unchanged; original installed native bundle preserved; repaired installed bundle matches all seven receipt hashes; user scheme preferences unchanged; production profile remains unset. Branch and HEAD remain `codex/native-consolidated` / `517878ff9c13911bf8d033c517492ef51ccffca7`. No commit, push or main merge occurred during this milestone. Only the two picker source files and milestone documentation were intentionally edited, in addition to the preserved pre-existing dirty scheme preference. Evidence: `final-preservation.json`.

Overall status is **PARTIAL**, not COMPLETED. Only the final installed SwiftUI inspection/reopen is blocked by demonstrably unavailable native automation access. The all-nine-output core/checkpoint reuse check has passed independently. The unresolved no-AI/transcript decision, actual account-capability evidence and Sheets prerequisites remain separately documented product/integration dependencies; they do not erase passed local results.


## Continuation — installed-core reuse, timing and GUI reassessment

Frank explicitly authorized reopening/resuming the existing checkpoint through a non-GUI route, with no restart of the media job, rerender of accepted clips, credential changes, push, merge, upload or publication. Overall status remains PARTIAL. This continuation changes no application source, installed bundle, accepted media or approved workflow. It adds bounded evidence helpers outside Git and updates the existing report/checkpoints.

### GUI inspection unavailable — observed evidence

At **2026-10-31T03:49:31.707Z**, `cua.getApp('/Users/frank/Applications/Joey Native.app')` attempted to obtain the installed application's UI. Exact response:

> The Mac is locked and automatic unlock could not unlock it. Ask the user to unlock the Mac manually before continuing.

Permitted recovery reset only the computer-use tool session and retried that exact installed path between **03:49:42.891Z and 03:50:00Z**; the same error returned. The second attempt has a bounded timestamp because no exact timestamp was emitted with that call. At **03:52:58.449Z**, `cua.getState()` returned `apps: []` and `Native apps: Error: ` followed by the same exact message. Browser-provider inventory remained available, with no native app surface.

Read-only session observations at **03:49:42.891Z** found `/dev/console` owned by `frank` UID **501**, a logged-in console session, `kCGSSessionOnConsoleKey=true`, `kCGSessionLoginDoneKey=true`, **`CGSSessionScreenIsLocked=true`**, and **`IOConsoleLocked=false`**. Installed Joey PID **33939** was present. These flags concern session/console state; their different values and the absence of visual access do not establish the physical display state. The observed cause is a native-automation session rejection with a lock-related error, corroborated by one session lock flag. The earlier categorical “Mac locked” conclusion is corrected.

Evidence: `gui-session-evidence.json`, `gui-access-reassessment.json`. No credentials were entered, security controls changed, alternative UI automation used or tool restriction bypassed. Smallest user action: bring Frank's desktop to an unlocked, usable session and retry native automation. If the desktop is already usable, confirm that; the remaining issue is native automation access, not permission to bypass macOS controls. An asynchronous request was issued while independent work continued.

### All nine accepted outputs reused by the actual installed core

The existing app's executable has no non-GUI job-resume command. A small evidence-only Swift entry point, `InstalledCoreReuse.swift`, imports the existing build module and dynamically links **the actual installed** `/Users/frank/Applications/Joey Native.app/Contents/MacOS/Joey.debug.dylib`. It calls the public `Coordinator.run` with the immutable request loaded from this existing `job.json`. No core source was recompiled or replaced. Runtime loaded-image output confirms that exact installed dylib; all seven installed bundle files still match the installation receipt. This is stronger identity evidence than assuming a separate CLI binary uses equivalent source.

Actual compile command (working directory does not affect these absolute paths):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcrun swiftc -parse-as-library -I '/Users/frank/Library/Caches/Joey-Native-Build/Build/Products/Debug' '/Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance/InstalledCoreReuse.swift' '/Users/frank/Applications/Joey Native.app/Contents/MacOS/Joey.debug.dylib' -Xlinker -rpath -Xlinker '/Users/frank/Applications/Joey Native.app/Contents/MacOS' -o '/Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance/installed-core-reuse'
```

Direct exit **0**. The linker reported a deployment-target warning: the harness defaulted to macOS 27.0 while the installed dylib was built for 27.0.1. The subsequent actual run succeeded on this Mac; this is not a warning-free compilation claim.

```sh
python3 '/Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance/verify_core_reuse.py'
```

This records identities, then executes:

```sh
/usr/bin/sandbox-exec -f '/Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance/core-reuse.sb' '/Users/frank/Library/Caches/Joey-Native-Build/full-length-acceptance/installed-core-reuse'
```

The test profile denies networking, process forks and writes to all nine accepted MP4s, source original, canonical transcript, retained QA/render evidence and the rclone credential directory. Probe calls verified both a direct socket and a child-process attempt fail with `[Errno 1] Operation not permitted`. These are temporary process restrictions, not system configuration changes.

The first protective test returned direct exit **1** before checkpoint changes because it also denied `settings.json` writes. Existing `Configuration.load` unconditionally saves that noncredential configuration. The exact error was `FAIL: You don’t have permission to save the file “settings.json” in the folder “Joey Native”.` Every accepted file and the checkpoint stayed unchanged. This was an overrestrictive test profile, not an accepted-media failure. All first-attempt evidence is preserved with the `attempt1-` prefix. The second profile permitted the existing settings save and verified identical settings bytes afterward; credential protection remained in place.

Successful resume: **2026-10-31T03:51:37.301530Z–03:51:39.790900Z**, core process direct exit **0**, verification script direct exit **0**. The existing job ID remained `dub-6a9c4dcb2874abc2e48f43e3`, checkpoint timestamp advanced, and result remained `QA_PASSED` with no error. Progress was:

```text
PROCESSING: source
PROCESSING: transcription
PROCESSING: transcription
QA_PASSED: local package
```

Those stage labels do not mean reacquisition or ASR occurred. Current `Coordinator.run` validates the prior source hash; `Acquisition.transcript` reads and validates the already-present canonical transcript, returning before ASR. Each accepted clip is skipped after its hash matches the saved QA receipt. Child-process creation and network access were denied throughout the successful resume. No render or replacement-QA stage appeared, no new acquisition/transcription output or scratch attempt appeared, and the exact job file inventory stayed unchanged.

Before/after evidence records **each of the nine files' SHA-256, bytes, nanosecond modification and change times, device/inode, clip identity, intervals, embedded QA receipt and on-disk QA/render receipt identity**. All matched. Source and canonical transcript identities also matched; the installed bundle and settings bytes remained unchanged. Local index/manifest/reconciliation records were regenerated by the existing package stage; they are not replacement QA receipts.

Evidence: `core-reuse-before.json`, `core-reuse-after.json`, `core-reuse-result.json`, `core-reuse.log`, `core-reuse-denial-probe.json`, `verify_core_reuse.py`. These are explicitly **core/checkpoint verification**, not SwiftUI inspection or reopening.

| Clip | Before = after mtime (ns) | QA checkedAt (unchanged) | Hash, inode and QA receipt |
| --- | ---: | --- | --- |
| 1 | 1793416365540986634 | 2026-10-31T03:13:43Z | Identical; full SHA-256 in measured-output table and JSON |
| 2 | 1793416510332849732 | 2026-10-31T03:16:36Z | Identical; full SHA-256 in measured-output table and JSON |
| 3 | 1793416652311499597 | 2026-10-31T03:19:02Z | Identical; full SHA-256 in measured-output table and JSON |
| 4 | 1793416801028120124 | 2026-10-31T03:21:30Z | Identical; full SHA-256 in measured-output table and JSON |
| 5 | 1793416954855040682 | 2026-10-31T03:24:15Z | Identical; full SHA-256 in measured-output table and JSON |
| 6 | 1793417103349997483 | 2026-10-31T03:26:25Z | Identical; full SHA-256 in measured-output table and JSON |
| 7 | 1793417243097006106 | 2026-10-31T03:29:00Z | Identical; full SHA-256 in measured-output table and JSON |
| 8 | 1793417390661595882 | 2026-10-31T03:31:15Z | Identical; full SHA-256 in measured-output table and JSON |
| 9 | 1793417522930814231 | 2026-10-31T03:33:00Z | Identical; full SHA-256 in measured-output table and JSON |


### Boundary policy and the final duration exception

The ninth output is **250.952 seconds**, a documented retained-remainder exception, not an ordinary 8–10-minute clip. `Planning.fullShow` sets its target to `min(600, profile.maxDuration)`, then takes the latest transcript punctuation endpoint in the next 480–600-second window. If none exists, it cuts at 600 seconds. `Editorial.plan` defines these candidates using transcript text ending in `.`, `!` or `?`. The planner does not look ahead, compute a balanced clip count or redistribute earlier boundaries when the remaining suffix is short.

For this source, the first eight cuts consume **4478.2 seconds**, leaving **250.952333 seconds** of mapped source. There are **284** punctuation endpoints, with none in the initial 480–600-second window. Six of the seven subsequent nonterminal cuts use punctuation; clip 4 also uses the 600-second fallback. The short tail is therefore a consequence of the implemented greedy policy, not a demonstrated requirement imposed by source length or the diagnostic 660-second ceiling. Merely joining the final two clips would produce **759.552333 seconds**, exceeding both the preferred 600-second target and diagnostic ceiling.

A read-only plan comparison used exact transcript segment endpoints to search eight-clip paths constrained to 480–600 seconds. It found this duration-feasible alternative:

| Proposed clip | Source interval (s) | Planned seconds |
| --- | --- | ---: |
| 1 | 0–590.7 | 590.7 |
| 2 | 590.7–1181.4 | 590.7 |
| 3 | 1181.4–1771.82 | 590.42 |
| 4 | 1771.82–2361.8 | 589.98 |
| 5 | 2361.8–2952.06 | 590.26 |
| 6 | 2952.06–3546.36 | 594.30 |
| 7 | 3546.36–4138.52 | 592.16 |
| 8 | 4138.52–4729.152333 | 590.632333 |


All seven interior cuts in that alternative lack the current punctuation marker. They are transcript segment ends, not proven sentence or conversation boundaries. A separate finite search restricted to punctuation endpoints plus existing fallback endpoints found no entirely 480–600-second path of eight or nine clips. That is evidence about this candidate set only, not proof that semantically suitable boundaries cannot exist. Better duration balancing trades against the current sentence-end heuristic; no policy change or rerender was made. Evidence: `boundary-policy-comparison.json`; command `python3 reconcile_timing.py` in the evidence directory, direct exit **0**.

A second plan-only comparison prioritizes the fewest nonpunctuation cuts before balancing duration. It finds eight durations of **599.62, 599.10, 599.46, 551.20, 593.34, 592.88, 594.78 and 598.772333 seconds**. Three interior endpoints have punctuation (**1798.18, 2349.38, 4130.38**); four require nonpunctuation segment-end fallbacks (**599.62, 1198.72, 2942.72, 3535.6**). This is a better sentence-heuristic tradeoff than equal balancing, but still not verified conversation continuity. Both alternatives remain plans only. The original remainder was not mathematically unavoidable; removing it requires changing the greedy boundary selection or accepting different fallback cuts. Exact alternatives and objectives are retained in `boundary-policy-comparison.json`.

### Exact timing reconciliation

No exclusions exist. The manifest maps each clip's retained source range to local output time zero through its exact planned duration. Adjacent source endpoints match, starting at **0** and ending at **4729.152333**. That mapping establishes retained coverage; summed encoded-file durations do not establish coverage.

| Clip | Exact source interval (s) | Planned output interval (s) | Measured file (s) | Difference (s) |
| --- | --- | --- | ---: | ---: |
| 1 | 0–600 | 0–600 | 600.000000 | 0.000000 |
| 2 | 600–1123.58 | 0–523.58 | 523.600000 | 0.020000 |
| 3 | 1123.58–1694.76 | 0–571.18 | 571.200000 | 0.020000 |
| 4 | 1694.76–2294.76 | 0–600.00 | 600.000000 | 0.000000 |
| 5 | 2294.76–2894.12 | 0–599.36 | 599.366667 | 0.006667 |
| 6 | 2894.12–3385.3 | 0–491.18 | 491.200000 | 0.020000 |
| 7 | 3385.3–3969.6 | 0–584.3 | 584.300000 | 0.000000 |
| 8 | 3969.6–4478.2 | 0–508.6 | 508.600000 | 0.000000 |
| 9 | 4478.2–4729.152333 | 0–250.952333 | 250.952000 | -0.000333 |


The table's deltas sum exactly to **+0.066334 seconds** using the reported decimal values: **4729.218667 − 4729.152333**. Every per-clip delta is within the implemented **0.075-second** media tolerance; source interval adjacency uses the separate **0.000001-second** planning tolerance.

This is supported by track timing, not a generic rounding assumption. Clips **2, 3 and 6** have video durations **523.600, 571.200 and 491.200 seconds**, while their audio durations exactly match mapped durations **523.580, 571.180 and 491.180**. Their 30-fps video tracks add **0.020 seconds each** to the measured file duration. Clip **5** has **17,981 video frames / 30 fps = 599.366666… seconds**, while audio is **599.360 seconds**; ffprobe reports the container duration as **599.366667**. Exact video tick counts and time bases are in `timing-reconciliation.json`.

For clip **9**, MP4 `mdhd` gives audio media duration **12,046,736 / 48,000 seconds**, and the edit list skips **1,024** priming samples. The remaining **12,045,712 / 48,000 = 250.952333… seconds** matches the exact source audio remainder. The audio edit-list segment duration is **250,952 ticks** at movie timescale **1,000**, so the effective audio duration reported by ffprobe is **250.952 seconds** (**12,045,696 / 48,000**), a **16-sample = 0.000333…-second** difference. The final video stream is **250.900 seconds**, so audio determines this file's reported duration. Source video itself ends at **4729.112 seconds**, before source audio's **226,999,312 / 48,000 = 4729.152333… seconds**. The evidence records these distinct stream endpoints rather than claiming identical A/V tails.

At full rational precision, the three 0.020-second video extensions plus clip 5's 1/150-second extension, minus the final 1/3000-second audio edit-list difference, equal **199/3000 = 0.066333… seconds**. The user's **0.066334** difference is the exact subtraction of the two six-decimal reported totals. The evidence keeps both reported decimal values and rational stream timing. No omitted ad, duplicate mapped speech or invented exclusion is needed to reconcile them; the existing temporal QA tolerance explicitly bounds the measured differences. This does not claim sample-perfect end-to-end identity.

### Open requirements and smallest proposed correction

**OPEN:** transcript reuse proves neither model-independent operation for a new untranscribed source nor an approved waiver of “No AI dependency for core operations.” No later explicit AI waiver was found; no requirement has been silently redefined.

The smallest proposed requirements correction that preserves the currently approved mandatory-transcript workflow is an explicit user decision permitting **local ASR/model inference when no valid supplied or cached transcript exists**, while retaining transcript reuse and source binding. This is a proposal, not approval. If the strict no-AI-core rule is retained instead, an explicitly approved model-independent workflow must be designed; simply removing the transcript gate would conflict with the current specification. No such implementation change occurred here.

The accepted **720×1280 canvas / 720×404 effective source picture** outputs remain **diagnostic**. They do not preserve 1080p landscape detail and do not establish X/Instagram account compatibility, ingestion or production readiness. The previously documented OAuth project ownership, Sheets API enablement, valid granted scopes and target-register access prerequisites remain unchanged. No credentials were refreshed or altered.

### Current separate statuses

| Item | Status |
| --- | --- |
| Full-length local media QA | **PASS**, nine accepted outputs; clip 9 is a duration exception. |
| Network-denied operation | **PASS**, original installed-app/helpers run plus independently denied core reuse. |
| Interruption/recovery | **PASS**, original interrupted clip-2 recovery evidence retained. |
| All-nine-output checkpoint reuse | **PASS**, actual installed dylib, unchanged file identities and QA receipts. |
| Final installed SwiftUI inspection/reopen | **GUI inspection unavailable**; only this UI check is blocked by native automation access. |
| Requirements conflicts | **OPEN**, no-AI-core versus mandatory transcript acquisition remains unresolved. |
| Drive filing | **NOT ATTEMPTED**, excluded from this milestone. |
| Register reconciliation | **NOT ATTEMPTED**; separately documented OAuth/API/access prerequisites unresolved. |
| Platform compatibility | **UNVERIFIED**, diagnostic limits are not real account-capability evidence. |
| Platform ingestion/publication | **NOT ATTEMPTED**, no upload or publication authorized. |
| Overall milestone | **PARTIAL**. Passed independent checks remain passed. |

Final continuation preservation readback at **2026-10-31T03:56:08.321210Z** passed: all nine file/QA identities unchanged, original source hash matches baseline, legacy app and user scheme preferences unchanged, installed seven-file receipt matches, production profile remains unset, and no Drive/register receipts exist. Branch remains `codex/native-consolidated`, HEAD `517878ff9c13911bf8d033c517492ef51ccffca7`. `git diff --check` returned direct exit **0**. Evidence: `continuation-preservation.json`.
