## Routing release verification — 2026-11-02

Current integration branch: `codex/drive-routing`, based on `c10d1215e84d39d065f6b461805477617656da94` (merged PR #3). The earlier routing report below is historical evidence, not the current release state. Evidence directory: `/Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102`.

Independent review found a legacy-folder source-hash bypass. Matching owner/source/job tags no longer suffice when `joeySourceSHA256` is absent: the adapter verifies the downloaded manifest or bounded empty-folder creation intent, then binds and reads back the hash. A present conflicting hash rejects before mutation. Two regressions reproduced three failed assertions before repair; all 13 folder-ownership tests passed afterward. Independent rereview found no further material defect.

Commands below ran from the existing native checkout through the minimal-environment launcher. Direct exit status was 0 for every final command. Swift/Xcode used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
python3 Tools/run-local.py /usr/bin/swift test --jobs 2 --filter EpisodeFolderOwnershipTests
python3 Tools/run-local.py /usr/bin/env -u JOEY_REAL_MEDIA_INPUTS -u JOEY_LOCAL_ASSISTANT_SMOKE -u JOEY_MODEL_INDEPENDENT_EVIDENCE /usr/bin/swift test --jobs 2
python3 Tools/run-local.py python3 -m unittest discover -s Tests -p 'test_*.py'
python3 Tools/run-local.py /usr/bin/xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug -destination platform=macOS -derivedDataPath /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/native-build -jobs 2 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
python3 Tools/run-local.py /usr/bin/codesign --verify --deep --strict --verbose=2 /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/native-build/Build/Products/Debug/Joey.app
JOEY_REAL_MEDIA_INPUTS=/Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/live-input.json python3 Tools/run-local.py /usr/bin/swift test --jobs 2 --filter LiveDriveRoutingTests
git diff --check
```

Full Swift suite: **246 executed, 242 passed, 4 opt-in skips, 0 failures**, 181.729 seconds. Python: **22 passed**. Native Debug build and strict deep ad-hoc signature: **passed**. Existing compiler/duplicate-file warnings remain; no warning-free claim. The skips are the installed-assistant check, two real-media checks, and separately enabled live routing readback. Simulated mutation/recovery tests do not establish production writes.

Separate live read-only test: **1 passed**, 64.934 seconds. All eight roots/ancestors/permissions verified. All **299** historical receipts match; all **15 packages / 239 clips** remain misplaced and are rejected by the production location validator. The test now asserts every receipt match. No duplicate names or equivalent-byte files were found within those packages; no matching tagged/named episode folder was found directly under the intended destination roots. This bounded search does not claim a global byte-duplicate census. Exact IDs remain in the inventory below and fresh `live-readback.json`; no historical media or companion changed.

### Historical migration plan — prepared only, separate authorization required

Use `live-readback.json` as the immutable proposal and process its packages sorted by `sourceID`, then `folderID`. For each package, retain the exact folder/file IDs, current single parent, intended root, complete child manifest, hashes, sizes, names and effective permissions. Do not create a new episode directory or upload duplicate media.

Before any separately authorized migration, independently reread the folder and every child, revalidate destination ancestry and duplicate checks, and compare against this proposal. Stop that package on drift, ambiguous parent, conflicting folder, incomplete companions or any effective-access change. Assess inherited permissions before moving; this plan does not authorize sharing changes. If existing access cannot remain identical, obtain a revised migration decision.

For an approved unchanged package, use one Drive parent update on the existing folder ID: add the verified intended root and remove only the recorded previous parent. Read back exact parents/ancestry, all child IDs/names/bytes/hashes, effective permissions and duplicate absence. The deterministic rollback is the inverse parent update on that same folder ID, conditional on it still having only the expected new parent and unchanged content/access; verify the inverse independently. Never delete, rename, copy or rerender clips. Journal before/after evidence per package outside Git. Reconcile local routing receipts and applicable existing register rows by exact source/clip identity only after provider verification; a parent move alone cannot establish COMPLETED. Companion changes or contract migration need their own explicit scope. No part of this migration was executed.

Integration, installation and new production acceptance are pending at this checkpoint. Current Taxstone account metadata and five official upload-document readbacks are saved outside Git; the immutable shared encoding contract remains unchanged. Existing DUB delivery cannot be reused as a new register-write acceptance without duplicating historical media. Final deployment/production receipts will be recorded in a verified follow-up.

---

## Authoritative Drive routing correction — verified local implementation, 2026-11-02

**Local implementation/build/tests: PASSED. Live Drive roots, existing file receipts and schema reads: VERIFIED. New production delivery and installed-app replacement: NOT PERFORMED.** Evidence directory: `/Users/frank/Library/Caches/Joey-Native-Build/drive-routing-20261102`.

Repository before editing: `/Users/frank/Documents/Joey`, origin `https://github.com/franklinburrus/Joey.git`, branch `main`; local and remote `main` both `d58947ecf2808ab759862f9daf94fdd999797747`. The existing `Joey.xcodeproj` and SwiftUI architecture were reused. Twenty-two unrelated untracked duplicate files were preserved. No commit, push, installation, production restart, media relocation/deletion or provider mutation was performed.

### Implemented contract

`Joey/Core/DestinationResolver.swift` owns all eight IDs and their verified ancestor chains. Routing depends on source identity/hash, owner, inspected format and clip/full-episode classification. The existing `joeBudden` workflow distinguishes historical DUB-owned Joe requests without changing their serialized identities. New originals resolve automatically; verified legacy originals remain in their current archives. Manual destination controls were removed.

`DriveDelivery` requires this resolved destination for uploads, validates exact root/parent/ancestry, reconciles uncertain writes before retry, rejects duplicate filenames and equivalent media under another filename, preserves existing file IDs and sharing fingerprints, and downloads companion bytes for SHA-256 readback. Folder reuse requires matching source/job tags, a verified compatible manifest, or the existing bounded empty-folder creation intent. Moved legacy packages are discovered by saved folder ID and exact source/name searches; incompatible packages are reported without relocation or duplicate creation.

The coordinator checks expected receipt parents/routes and final package readback before COMPLETED. All four canonical companions, unique IDs, source-bound transcript, accepted QA, applicable unique register receipts and exact route evidence are required. Failed filing retains QA_PASSED with the error and accepted media. Legacy receipts without authoritative routing evidence cannot make the Drive stage or Completed badge green. Joe automation, Taxstone verification and Buffer preflight use the same completion/routing contract. DUB Master Link List mapping/readback remains unchanged; Joe and Taxstone do not write DUB-only rows. Historical rows are preserved.

### Commands and direct results

All executable commands used `Tools/run-local.py`; Swift/Xcode commands used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
python3 Tools/run-local.py /usr/bin/env -u JOEY_REAL_MEDIA_INPUTS -u JOEY_LOCAL_ASSISTANT_SMOKE -u JOEY_MODEL_INDEPENDENT_EVIDENCE /usr/bin/swift test --jobs 2
python3 Tools/run-local.py /usr/bin/xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug -destination platform=macOS -derivedDataPath /Users/frank/Library/Caches/Joey-Native-Build/drive-routing-20261102/native-build -jobs 2 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
python3 Tools/run-local.py /usr/bin/codesign --verify --deep --strict --verbose=2 /Users/frank/Library/Caches/Joey-Native-Build/drive-routing-20261102/native-build/Build/Products/Debug/Joey.app
```

- Final full Swift suite: direct exit **0**, **239 executed, 235 passed, 4 intentional opt-in skips, 0 failures**, 175.729 seconds. `final-full-tests.log`. Skips are the installed-assistant check, two existing real-media checks, and the new separately enabled live Drive readback.
- Native Debug build: direct exit **0**, **BUILD SUCCEEDED**, `final-native-build.log`. Existing capture-ownership and AppIntents metadata warnings remain; this is not a warning-free build claim.
- Strict deep signature verification: direct exit **0**, valid on disk and designated requirement satisfied. Local ad-hoc build only; no installation or public distribution.
- `git diff --check`: direct exit **0**.

Regression evidence: `red.log` reproduced the obsolete root IDs (1 test, 2 expected failures). `completion-red.log` reproduced the missing transcript-binding and legacy green-Drive checks (1 test, 2 expected failures). Subsequent targeted tests and the final full suite passed. A test-only QA timestamp comparison initially compared pre-serialization subsecond precision with the persisted checkpoint; the test now compares the actual persisted QA without loosening production checks. Provider protocol fixture compile/signature mismatches were repaired during implementation. Earlier logs remain in the evidence directory.

Coverage includes all eight mappings; audio content in an MP4; owner/identity/hash/date validation; wrong root, actual parent and ancestor rejection; same-folder reuse and compatible-manifest adoption; conflicting manifest preservation; lost mkdir/upload responses; duplicate filenames and byte-equivalent media; existing-original reuse without relocation; permission preservation; companion download corruption; missing register receipts; final provider failure; correct completion and QA_PASSED transitions; accepted-file/QA reuse; and existing native/email/queue/media regressions. Provider mutations in these automated tests are simulated boundaries, not production delivery evidence.

### Live read-only verification

```sh
JOEY_REAL_MEDIA_INPUTS=/Users/frank/Library/Caches/Joey-Native-Build/drive-routing-20261102/live-input.json python3 Tools/run-local.py /usr/bin/swift test --jobs 2 --filter LiveDriveRoutingTests
python3 Tools/run-local.py .build/debug/joey-run check-drive --root /Users/frank/Library/Caches/Joey-Native-Build/drive-routing-20261102/preflight
```

Both commands returned direct exit **0**. The separate live test executed **1 test, 1 passed, 0 failures**, 64.552 seconds. It uses the real existing rclone OAuth and real provider metadata through the production adapter; its helper permits only read/list/authentication operations. Initial connector metadata independently confirmed the hierarchy. `live-readback.json` records all eight exact roots, names, ancestor chains, permission fingerprints and `canAddChildren=true` for each. Existing anyone-with-link reader access was observed; sharing was not changed.

The runner used an isolated copy of existing settings. `provider-preflight.log` confirms all eight roots and the current **20-column** DUB Master Link List schema. Read access/schema validation is not a new register write or write-permission proof. No CSV was substituted for an applied register update.

Existing real packages: **15 episode folders, 239 clips, 60 companions**. All **299** provider file receipts still match saved IDs, filenames, immediate parents, sizes and MD5 checksums. All **15 episode folders** are outside the newly required direct clip-root locations, and the production placement validator rejected every one. This verifies actual wrong-location rejection and existing remote integrity; it does not establish corrected production delivery.

| Source ID | Clips | Existing episode folder | Actual parent | Expected root |
| --- | ---: | --- | --- | --- |
| `youtube:KfNBD15tkPA` | 17 | `1DBHs-sQ8jpyALLiisOw1HUi09_aFoBDb` | `1N7HyLq-Fq8a2RIaXMe7Xs17Y8UqYuCcJ` | `1X5VNP6fo3VpZPu4ZW4p7Ggk2o_IAVGSI` |
| `x:broadcast:1oKMvNPnEzDGQ` | 35 | `1_NJU2jWQEz3uSAvDYGXXJM9tfIr9s5iD` | `1N7HyLq-Fq8a2RIaXMe7Xs17Y8UqYuCcJ` | `1380CHJ3a3kl7fXNIKWqUM7_DeTZUwxsy` |
| `soundcloud:802783417` | 2 | `1t6VEL_G2ozPSTaNANXldU6gy7de6Cmqr` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:1169874577` | 19 | `1M-CakIReL8oZmihXq0escl_EtMVdDOAf` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:2126698314` | 11 | `1fjWePls7ieTTTKpqFnGrYSRnmIM6OE-4` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:210734469` | 21 | `1-lNT9IKT0Jwc3TStt-7rAd91xGkXqdSk` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:274535613` | 22 | `1m2kcq1GyRf4yRg3vBFqjWbewRlwkzRzs` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:2215319513` | 11 | `13STZ5d14uH-riK1bp9XvTvkgWCwZlZFN` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:2331720617` | 6 | `1bkZtSggMnaqrigvULctZ3pSnndH8YO9F` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:230455821` | 22 | `1bDnduFUj79RSkTrumUQV8yluLMNNeZ1E` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:1112603617` | 22 | `19bc8NiQAKFrEtAqK8ETiZRmgKJNvSg1R` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:245240397` | 21 | `1KvUL1C6fscdsnVHgBDiU1gA8Xzc-WrRs` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:1288986418` | 2 | `1S7CkmADbbJooOZE6R2vRBq_2Y4XXF5cG` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:218912703` | 17 | `11FyrmbdvN_h5TLXCvfnT8DNFdcYnFRmu` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |
| `soundcloud:1993424227` | 11 | `14gXkMAK9o5DY04VXixIlY8081aAL-DMY` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` |

The Joe Episode 977 and DUB broadcast packages share historical parent `1N7HyLq-Fq8a2RIaXMe7Xs17Y8UqYuCcJ`. Thirteen Taxstone packages sit under `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` (Taxstone X Clips), adding a retired platform-specific level. The two former Joey clip folders are currently empty. Existing media and companions were not moved, deleted, duplicated, rerendered or rewritten.

### Remaining operational scope

The tested application is at `/Users/frank/Library/Caches/Joey-Native-Build/drive-routing-20261102/native-build/Build/Products/Debug/Joey.app`; the installed app remains unchanged. Deployment must use the existing protected installation/rollback procedure under current installation authority. The 15 legacy packages require a separately authorized reconciliation/relocation decision because this task explicitly forbids automatic moves or deletion. Their accepted bytes and old receipts remain preserved; the new code refuses to present those receipts as current routing completion.

A new eligible production package through the corrected adapter, including actual uploads, companion downloads and applicable DUB register writes/readback, has not been run. Existing accepted packages were used read-only because copying or moving them would violate this correction's preservation scope. Do not claim live upload/retry acceptance, installed-app behavior, social ingestion or publication from these tests. No current credential outage was observed: all roots and schema reads succeeded. No new dependency, paid API or infrastructure was introduced.

### Changed files

- `Joey/Core/BufferPreflight.swift`
- `Joey/Core/Coordinator.swift`
- `Joey/Core/Delivery.swift`
- `Joey/Core/DestinationResolver.swift`
- `Joey/Core/Domain.swift`
- `Joey/Core/JobPresentation.swift`
- `Joey/Core/ProductionIntake.swift`
- `Joey/Core/Records.swift`
- `Joey/Core/TaxstoneLibrary.swift`
- `Joey/EmailSettingsView.swift`
- `Joey/JobModel.swift`
- `Joey/NewJobView.swift`
- `Tests/JoeyCoreTests/BufferPreflightTests.swift`
- `Tests/JoeyCoreTests/DeliveryTests.swift`
- `Tests/JoeyCoreTests/DestinationRoutingTests.swift`
- `Tests/JoeyCoreTests/DriveFilingTests.swift`
- `Tests/JoeyCoreTests/EpisodeFolderOwnershipTests.swift`
- `Tests/JoeyCoreTests/LiveDriveRoutingTests.swift`
- `Tests/JoeyCoreTests/PresentationTests.swift`
- `Tests/JoeyCoreTests/RecoveryRegressionTests.swift`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/OPERATING_GUIDE.md`
- `docs/REQUIREMENTS.md`
- `docs/STATUS.md`
- `docs/VERIFICATION.md`

---

## Clip Intelligence and GPT Buffer Handoff — verified 2026-10-31

Installed current-source native build and signature passed. Final sanitized `swift test` returned direct exit 0: 118 XCTest cases, 115 passed, 3 intentional skips, 0 failures/errors. Real accepted Taxstone clip 17 from The Lost Episode passed local decode/hash, exact Drive readback and 131,072 anonymous range-byte comparisons. Core and installed-native exports reused batch `F4288378-65EE-4735-97D1-0418062AE0EE` without provider writes. Native receipt import rejected an unknown fixture batch without changing the ledger. Isolated tests cover legitimate/partial/uncertain receipts, duplicates, renewal, exact mode/identity and restart recovery. Installation/post-launch preservation covered all 118 accepted MP4 identities, original/transcript hashes and unchanged settings. Taxstone resumed; Joe remained enabled at baseline 976 and 30-minute checks. Exact commands, evidence locations and remaining external execution/ingestion boundaries are in the latest STATUS.md and BUFFER_HANDOFF.md. This is handoff implementation acceptance, not live Buffer ingestion or publication.

## Current UI and final icon closeout — 2026-10-31

**APP INSTALLED AND USABLE. UI/final branding verified. The first authorized 35-clip production delivery is complete as documented in STATUS.md; older PARTIAL statements below describe historical milestones.**

Final installed app: `/Users/frank/Applications/Joey Native.app`, with unchanged bundle identifier and runtime root. Final icon uses the supplied black-and-white Joey artwork; ten exact macOS sizes are integrated, original preserved, white exterior margin removed without redrawing the lettering. Purple interface and persisted System/Light/Dark appearance remain. Finder/Applications icon was observed through CUA; Frank explicitly confirmed the Dock icon after Dock-only CUA inspection timed out.

Current-source build and final-icon build both returned direct exit 0; strict deep signatures and all nine installed bundle hashes passed. The initial build invocation returned exit 1 because `/usr/bin/xcodebuild` selected CommandLineTools. Recovery used `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild` with per-process DEVELOPER_DIR, through `Tools/run-local.py`; no global developer setting changed. Existing focused test evidence was reused: direct exit 0, three passed, zero failures/skips, not rerun during this continuation.

Native proof covered actual synthetic local processing progress/result, mandatory input validation and the precise unsupported-URL error, existing completed-job access, Open Clips and View Report, all three appearance modes, and appearance persistence across installed relaunch. The synthetic 60-second job is `dub-fdb500e9064fadde8b3acfc6`, one QA-passed local-only clip; it is not production acceptance. The original completed job still reports 35/35 QA-passed and Drive-verified outputs with verified records. All 178 substantive baseline runtime files and all 17 pre-existing backend source hashes remain unchanged; only Finder's jobs/.DS_Store changed. REQUIREMENTS.md was not edited.

Receipts and exact hashes: `/Users/frank/Library/Caches/Joey-Native-Build/ui-branding-20261031/final-icon-installation.json` and `final-verification.json`. Original input/transform: `final-icon-provenance.json`. Prior bundles: `Joey Rollbacks/2026-10-31-before-ui-branding/Joey Native.app` and `Joey Rollbacks/2026-10-31-before-final-icon/Joey Native.app`. Previous rollbacks and legacy app are preserved. No new provider writes, production rerender, publication, credential change, push or merge occurred.

## Installed application closeout — 2026-10-31

**APP INSTALLED AND USABLE for native intake/setup, optional local assistance and existing-output access. Production delivery remains PARTIAL.** Starting a new media job still requires genuine current X/Instagram capability evidence, as required by the approved specification; that prerequisite was not replaced with a diagnostic default. Frank explicitly authorized production-path installation and ordinary Finder use. The earlier candidate-only hold is historical and superseded for this installation.

Installed application: `/Users/frank/Applications/Joey Native.app`. Branch `codex/native-consolidated`, HEAD `517878ff9c13911bf8d033c517492ef51ccffca7`, plus preserved uncommitted implementation. Exact source manifest SHA-256 `bc66bf1960e9f5557cff85529c5ad3e5c7b68a5c639dcd7f9d0c3ccee4757347`. Installed code dylib SHA-256 `4012af68a6f6cf23c10b325a3d30f86bceda7a34a543456427e11730586573d6`. All seven installed bundle file hashes match the intended final native build; strict deep signature verification returned 0. The final build is the verified candidate implementation plus the bounded ordinary-UI changes below, not a claim that the old candidate bundle bytes are identical. The acceptance candidate itself remains unchanged.

Rollback retained: `/Users/frank/Applications/Joey Rollbacks/2026-10-31-before-assistant-promotion/Joey Native.app`. The actual pre-replacement bundle was also retained at `/Users/frank/Applications/Joey Rollbacks/2026-10-31-before-assistant-promotion/Original installed bundle.app`, preserving its original file metadata/inodes. Neither rollback is deleted. Legacy Joey.app is untouched. To roll back, quit Joey and restore the retained bundle to the installed path; runtime data is separate and remains preserved.

### Shipping changes and observed ordinary workflow

- Native Production setup now accepts the existing capability contract through fields and file choosers: actual X/Instagram account and upload surface, checked/valid dates, duration, file-size, dimensions/FPS, official URLs and hash-bound account evidence. Existing validation selects one compliant shared portrait profile. No synthetic/account data was inserted, no new account or credential setup added, and optional JSON imports are not the normal workflow.
- New job exposes full-show preferred durations of 8, 9 or 10 minutes. Optional `preferredDuration` preserves old serialized requests/job identities when absent. Both transcript-assisted and model-independent planners honor the preference; verified platform hard limits remain authoritative. The existing natural-boundary floor is derived from the platform limit, so selecting eight minutes does not introduce an avoidable 450-second cut. No tail balancing or accepted-plan changes were made.
- Existing native local-file/YouTube/X intake, full-show/highlight options, optional local transcription and Drive toggle remain. Native archive selection exposes only established owner-appropriate destinations; model-independent local audio can reuse configured approved artwork. Missing artwork/capability/dependencies retain their existing errors and safeguards.
- Job details now separate local QA, verified Drive clip/companion receipts, DUB register rows, unverified platform ingestion and publication state. Account/surface labels keep the nine-output diagnostic profile explicit. Each accepted clip has a Finder reveal action; duration exceptions are visible.
- Native setup can check the existing Drive/Sheets connection without an upload or register mutation. Blank account-evidence input first produced an unhelpful filesystem error during UI verification; the final build now reports: “Choose actual X and Instagram account evidence files before saving. No profile was saved.” No settings change occurred on either failed save.

Finder double-click launched the installed executable normally (first PID 46918, final corrected revision PID 47279, each parent PID 1), without Xcode, Codex, Terminal commands or the acceptance harness. Through SwiftUI, the native chooser selected the preserved original, the duration control read back eight minutes, ASR and filing could be switched off, and missing verified profile data kept Start disabled with its stated prerequisite. No new job or media render was initiated. The existing full-length job opened showing 9/9 local QA, 0/9 Drive files, 0/9 register rows, diagnostic account labels, every clip interval, and the final 250.952-second exception. Show local clip selected the exact first accepted MP4 in Finder.

The optional assistant initially remained stopped. Explicit Start worked under normal launch, and Stop removed only Joey's owned service. Actual Ollama PID 47134 retained default outbound-network denial and denial of existing identity/model writes. The ordinary media application retains network access needed for authorized acquisition/filing; it is not dependent on the acceptance harness. The assistant's loopback client, sandbox owner, no-cloud configuration and no-download safeguards were unchanged. Reuse the corrected candidate's successful Send/Cancel/Clear/reopen and real offline inference/performance evidence; no repeated inference benchmark or full-length media run was performed.

### Verification and exact evidence

Evidence directory: `/Users/frank/Library/Caches/Joey-Native-Build/installation-20261031`.

- Selected-duration regression: direct exit 1 before implementation, one test/three failed assertions. A second boundary regression failed with exit 1 and one assertion when a 450-second natural cut was incorrectly selected. Final suite: direct exit 0, **51 executed, 48 passed, 3 intentional skips, 0 failures**, 21.298 seconds. This includes existing assisted/model-independent, recovery and assistant regressions. The skips remain the authorized-real-media opt-in and two installed-model entry points previously passed separately; they do not reopen those completed audits.
- Native build: first attempts returned 65 for a setup binding/type-check failure and an extraction-edit syntax failure; both repaired before installation. Final `build-ui-error` returned 0. Only remaining final warning is AppIntents metadata extraction skipped because there is no AppIntents framework dependency. No feature requires AppIntents.
- Final source/build identity: `installation.json`, `source-manifest.json`; all seven bundle hashes, source HEAD/branch and dirty-source manifest are recorded. Prior installation/build attempts remain retained. Native UI observations: `swiftui-verification.json`, `finder-launch.json`, `final-finder-launch.json`, `normal-service-chain.json`.
- Final preservation: `preservation-final.json`, `preferences-restoration.json`, `identity-metadata-preservation.json`, `rollback.json`. All 181 baseline file hashes, sizes and modes match (the replaced installed bundle is compared at its retained original location). 180 match every recorded metadata field. Preferences bytes/effective values were restored, with only inode/mtime differing. Settings, source/transcript, all nine clips/QA/checkpoint records, both synthetic jobs, prior evidence, legacy app and acceptance candidate are unchanged. Finder created only `jobs/.DS_Store`; no new job/output appeared. Existing local Ollama identity metadata is unchanged; contents were not read. Final normal Quit left no Joey/Ollama processes.

Commands (from `/Users/frank/Documents/Joey`, sanitized launch boundary):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tools/run-local.py /usr/bin/xcrun swift test --scratch-path /Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance/correction-1/spm
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tools/run-local.py /usr/bin/xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug -destination platform=macOS -derivedDataPath /Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance/correction-1/native-build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
python3 Tools/run-local.py /usr/bin/codesign --verify --deep --strict '/Users/frank/Applications/Joey Native.app'
```

Installation orchestration under the same sanitized launcher used `ditto --rsrc --extattr --acl`, exact bundle hash comparisons, a retained rollback and filesystem rename before promotion. Final UI-only correction replaced only the authorized installed bundle after normal Quit. Actual argv and direct results are retained in build/test/result JSON files. All UI interactions used the authorized native computer-use tool.

### Delivery lanes and exact remaining actions

| Lane | Current result |
| --- | --- |
| Installed native application / Finder launch | PASS, final build verified |
| Local full-length QA, recovery and accepted-output reuse | Existing PASS retained; nine diagnostic outputs unchanged |
| Optional assistant / model-independent core | Existing PASS retained; ordinary owned Start/Stop additionally verified |
| Acquisition | Existing authorized complete original reused and preserved; no substitute or unnecessary download |
| Drive connection/destinations | Readback PASS: both exact Joey roots HTTP 200 with canAddChildren/canEdit true; existing anyone-reader sharing was observed and left unchanged |
| Production output filing | NOT COMPLETE: no production-eligible job/profile established; diagnostic outputs were not uploaded or relabeled |
| DUB register | BLOCKED: Drive metadata confirms canEdit on the exact Master Link List, but Sheets API returns HTTP 403 for project 145289518259 |
| Platform capability/ingestion | UNVERIFIED: no actual current X account and Instagram upload-surface evidence; no social upload or publication |
| Exposed credential | Separately OPEN pending owner-confirmed revocation; not used, probed or changed |

Smallest external actions: the authorized administrator of OAuth project **145289518259** must enable/verify `sheets.googleapis.com` (current owner not established). The existing `dubdrive` connection has configured full Drive scope, which is accepted by Sheets; no scope widening, replacement credential or new register is prescribed. Actual register edit capability is now confirmed by Drive metadata, while Sheets tab/schema readback still cannot run. Frank must identify/provide actual X account and Instagram upload-surface capability evidence through Production setup; no fixture can substitute. The account evidence must establish current duration/dimensions/FPS/file-size limits and validity, with official sources. No independent production-eligible output remains to file while these inputs are missing, and the nine accepted diagnostic clips must stay preserved.

Existing authorized Google OAuth connection was used normally, including its ordinary token refresh. No credential rotation/replacement, API-key usage, Cloud configuration, sharing change, upload, register write, push, merge or publication occurred. Source changes remain on the current branch. Overall production acceptance remains PARTIAL.

# Corrected candidate SwiftUI gate — 2026-10-31

**PASS for the corrected bounded candidate gate; overall production PARTIAL.** Staging/signature, runtime protection, actual assistant controls/reopening, actual-process network isolation, native-picker model-independent clipping, measured inference and final preservation all passed in the corrected run. The original failed attempt and the tool-triggered unprotected relaunch remain recorded below and in [LOCAL_ASSISTANT.md](LOCAL_ASSISTANT.md); neither is counted as passing isolation evidence.

- Final candidate only: `/Users/frank/Applications/Joey Native Acceptance.app`; final build/signature exit 0. Original installed apps were not replaced.
- Full suite: direct exit 0, 50 executed, 47 passed, 3 intentional skips, 0 failures. Updated offline lifecycle and client tests separately passed, direct exit 0; the skipped real-media opt-in was not rerun.
- SwiftUI assistant: Start, synthetic answer, Cancel, Clear, Stop and empty/stopped reopening observed. Candidate PID 39820, supervisor 39969, Ollama 39970 and sampled inference runners all had outbound default denied under the known loopback-only policy. The successful request took 10.09 seconds server-side and was visible by 12.773 seconds; sampled summed footprint peak 1306.474 MiB.
- Corrected native-media run: actual window owner/candidate PID 42091, verified network/model-read denial and protected existing jobs; observed FFmpeg/FFprobe helpers denied outbound networking. New synthetic job `dub-860a7223ba752b0434bda194`: three decoded, QA-passed diagnostic 720×1280 outputs, 1.2/1.2/1.0 seconds, exact 3.4-second source coverage, no transcript or exclusions. Protected SwiftUI reopen PID 42674 reused all three output identities and QA receipts without Resume or rendering.
- Preservation: all 148 baseline hashes/sizes/modes unchanged; 146 exact metadata matches; documented settings/preferences inode/mtime differences after restoration. No final candidate/service process or listener. No production compatibility, delivery, promotion or publication claim.

Evidence: `/Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance/correction-1`, especially `final-build-result.json`, `full-suite-result.json`, `offline-lifecycle-result.json`, `actual-assistant-chain.json`, `performance-summary.json`, `protected-core-helper-policies.json`, `protected-ui-core-verification.json`, `protected-reopen-verification.json`, `tool-relaunch-incident.json` and `preservation-final.json`.

# First candidate installation and SwiftUI attempt — historical, 2026-10-31

The authorized candidate was staged at `/Users/frank/Applications/Joey Native Acceptance.app`; it did not replace either installed app. **Overall production remains PARTIAL.** Full operational evidence and commands: the dated gate in [LOCAL_ASSISTANT.md](LOCAL_ASSISTANT.md), with receipts under `/Users/frank/Library/Caches/Joey-Native-Build/candidate-ui-acceptance`.

| Criterion | Result | Observed evidence |
|---|---|---|
| Candidate staging/signature | PASS | Seven hashes match verified build; initial/final strict codesign exit 0. |
| Runtime protection | PASS | Existing job/assets/helpers/source/evidence/credentials write-denied; nontruncating job write denied EPERM; shared mutable state backed up. |
| Actual SwiftUI controls/lifecycle | FAIL | Start failed closed at nested macOS sandbox application; unavailable Send, Clear, sheet close/reopen and no autostart observed. Successful Send, response Cancel and owned Stop blocked. |
| Network isolation | BLOCKED for full gate | Actual candidate PIDs 29077/30448 deny default outbound; same-profile external TCP probe denied EPERM. Ollama never started, so no actual Ollama-process acceptance claim. |
| Model-independent clipping through UI | BLOCKED | Native request picker Open stayed disabled despite allowed file reads. No job started; no core-test substitution. |
| Performance measurements | BLOCKED for inference | Candidate UI sampled peak 56.079 MiB footprint / 143.344 MiB RSS. No inference response time or model-loaded memory measurement. |
| Final preservation/restoration | PASS | All 148 baseline hashes/sizes match; 146 retain every recorded field. Settings/preferences restored; documented inode/mtime differences only. No remaining candidate/Ollama process or listener. |

Actual GUI access succeeded for the assistant controls; the later core picker recovery produced `noWindowsAvailable` then `timeoutReached`. These observations do not prove a physically locked Mac. No permission/security changes or unrestricted fallback occurred. The original nine-output SwiftUI reopen remains separate and open. Prior suites were reused, not rerun; their three opt-in skips are explained below and in LOCAL_ASSISTANT. Drive filing/register reconciliation and platform ingestion remain unchanged and unverified/not attempted as previously recorded. No candidate promotion, source-feature edits, credential changes or accepted-output rerender occurred.

# Optional local assistant — implementation evidence before candidate gate, 2026-10-31

**Implementation/build PASS; real offline integration PASS; installed SwiftUI inspection UNVERIFIED; production PARTIAL.** Full report and exact commands: [LOCAL_ASSISTANT.md](LOCAL_ASSISTANT.md).

- Final shared-core suite: direct exit 0, 46 executed, 43 passed, 3 intentional opt-in skips, 0 failures/errors, 20.458 seconds. This includes 13 new assistant behavior tests and preserves model-independent/transcript-assisted tests. The installed-model tests are opt-in and the production real-media test remains skipped.
- Final native Xcode build: direct exit 0; not installed. Credential-stripping launcher suite: direct exit 0, 5/5 passed.
- Real offline harness: direct exit 0; one owned-service lifecycle test and one actual inference-client test passed, no skips/failures. External TCP denied with EPERM; verified installed qwen3:4b replied “2 plus 2 equals 4.” Both server and client used the production loopback-only sandbox profile. Stop removed the listener; duplicate Stop and Start-during-shutdown did not create another server. Short functional smoke only, not a performance benchmark.
- Preservation: all 124 pre-existing protected identities plus 18 model-independent fixture identities unchanged. Ollama executable/manifest identities unchanged; six referenced model blobs match their hashes and sizes. Local identity regeneration occurred only after Frank's explicit authorization; no API key or cloud sign-in was added.
- Evidence root: `/Users/frank/Library/Caches/Joey-Native-Build/local-assistant`; final logs: `full-suite-verified.log`, `launcher-tests.log`, `native-build-structured-final.log`, `offline-structured-final.log`; identity/cleanup: `preservation-final.json`, `service-after.json`.
- No GUI interaction, installation, push, merge, accepted-media rerender or provider write. Drive/register/platform lanes and exposed-credential revocation remain separate and unchanged.

# Joey native verification

Verification date: 2026-10-30 EDT. Outcome: **PARTIAL**. The native implementation builds and passes local tests. Production account capabilities and required provider delivery are not yet verified.

## Model-independent core milestone — 2026-10-31

**PASS** for the new bounded local-core milestone; overall production acceptance remains PARTIAL. See [MODEL_INDEPENDENT_ACCEPTANCE.md](MODEL_INDEPENDENT_ACCEPTANCE.md) for exact commands, dependency boundary, regression evidence, offline measurements, limitations and preservation proof.

The mandatory-transcript regression failed before implementation (direct exit 1, 1 test/1 failure). The corrected policy skips ASR discovery/invocation and permits local full-show planning/rendering/QA/records without a transcript, while explicitly marking editorial features unavailable and blocking incomplete production finalization. Valid transcript reuse and assisted safeguards remain.

Targeted and network-denied runs each passed 4/4 tests, direct exit 0. Full suite: direct exit 0, 28 executed, 27 passed, 1 intentionally skipped real-media opt-in, 0 failures/errors. Separate Xcode build succeeded, direct exit 0, without replacing the installed app. Three synthetic fixture outputs measured 1.2, 1.2 and 1.0 seconds with exact 3.4-second source coverage, no transcript/helper/model available to the job, and verified network denial. Independent audit returned exit 0; all 124 pre-existing accepted/installed/source/evidence identities remained unchanged.

This establishes core behavior and compilation, not final installed SwiftUI inspection. Production transcript/editorial, profile, filing/register and ingestion evidence remain separate. No previous accepted media was rerendered or audited anew. The following full-length sections remain historical evidence, including the prior unresolved local-core question now addressed by Frank's explicit 2026-10-31 instruction and this milestone.

## Full-length local milestone — latest continuation

Overall status: **PARTIAL**. Full details, commands, preserved failed attempts and exact remaining dependencies are in [FULL_LENGTH_LOCAL_ACCEPTANCE.md](FULL_LENGTH_LOCAL_ACCEPTANCE.md). Historical implementation tests below remain historical; they do not replace the full-length run.

The installed SwiftUI app imported and started the complete 4729.152333-second authorized source. All nine outputs passed local media QA and independent measurements (direct exit 0). Eight clips are 8–10 minutes; the 250.952-second ninth is a documented duration exception. Complete retained source mappings, no exclusions, source-only presentation, audio synchronization checks, sampled picture checks and local records passed. Outputs remain diagnostic: 720×1280 canvas, 720×404 effective picture, no claim of preserved 1080p detail or X/Instagram eligibility.

Network denial for actual app/helpers and interrupted clip-2 recovery passed. On continuation, an evidence-only harness dynamically linked the actual installed `Joey.debug.dylib` and resumed the existing immutable checkpoint under verified network/fork denial. Core resume and independent before/after verifier returned direct exit **0**: all nine hashes, timestamps, inode identities, QA receipts and source/transcript identities stayed unchanged; no acquisition, ASR, rendering or duplicates occurred. Progress stage `transcription` was cached-transcript validation, not inference. Local companion records were refreshed by the existing package stage. The first test-only settings-write denial caused an exit-1 pre-resume failure; evidence preserved, profile corrected, settings bytes verified unchanged on success.

Final SwiftUI inspection/reopen remains **GUI inspection unavailable**, a separate check. Exact-path access, tool-session reset/retry and surface inventory failed with the same lock-related native-automation error. Read-only session evidence shows Frank logged in/on console, `CGSSessionScreenIsLocked=true`, `IOConsoleLocked=false`; physical lock is not inferred solely from the tool message. No restriction or security control was bypassed.

Timing reconciliation (direct exit 0) explains measured 4729.218667 seconds versus mapped 4729.152333 seconds, +0.066334 seconds. Actual video ticks/frame counts and the final audio edit list explain the per-clip differences, all within 0.075 seconds. Coverage comes from exact interval mappings, not summed file durations. Plan-only comparison explains the greedy remainder policy and a duration-feasible alternative without touching accepted files.

The previous asynchronous picker repair built successfully and strict signature verification passed; installed bundle still matches its receipt. No application source or installed bundle changed in this continuation. Earlier 24/24 tests were not rerun. Source, legacy app and pre-existing Xcode preferences remain preserved.

No-AI-core versus mandatory transcript acquisition remains **OPEN**. Existing-transcript reuse proves neither model-independent new-source operation nor approval to require AI. A minimal explicit local-ASR authorization is proposed separately, not assumed or implemented.

Drive filing and register reconciliation remain **NOT ATTEMPTED**. Sheets prerequisites remain project/client ownership, API enablement, valid granted scopes and exact register access; no credentials or Cloud settings changed. Actual platform compatibility is **UNVERIFIED** and ingestion/publication **NOT ATTEMPTED**. Passed local results are independent of these downstream dependencies.

## Checkout and preserved work

Repository: `https://github.com/franklinburrus/Joey.git`, branch `codex/native-consolidated`. Merge `5e35d4d` preserves native starter `bc34efbf88b95c726da3fe8e1eb3dcb69120bb3c` and remote main `f265a5ad2c44b933d6da4aafc752c9c6c8646a83`. Implementation commit `a4a08dfcd365acd3d0ed1d8b237a6a2185871628` was pushed to the feature branch and independently read back with `git ls-remote`; remote main remained unchanged. Existing Xcode project was retained. User scheme preferences are excluded from the implementation commit. Preservation hashes and historical failed-run logs remain under `/Users/frank/Library/Caches/Joey-Native-Build/`.

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
# Credential prevention and key-free development — 2026-10-31

**PASS for scoped prevention/build/core checks; credential invalidation PENDING; production PARTIAL.** Detailed sanitized evidence and exact commands: [CREDENTIAL_INCIDENT.md](CREDENTIAL_INCIDENT.md).

- Final launcher regression suite: direct exit 0, 5 passed, 0 failures. Dummy-only tests cover stdout, error stdout/stderr, the actual XCTest environment-dumping diagnostic, shell rejection and process identity.
- Final sanitized shared-core suite: direct exit 0, 31 executed, 30 passed, 1 intentional real-media opt-in skip, 0 failures, 19.470 seconds. Existing model-independent and transcript-assisted regressions pass. Actual test-process AI credential absence and both helper boundaries are checked.
- Final separate sanitized Xcode build: direct exit 0; no installation. New native executable headless supervisor canary: exit 0. This is not installed SwiftUI evidence.
- Preservation: 124 prior file identities and 18 model-independent fixture identities unchanged by hash, byte count and nanosecond mtime. No accepted-output rerender, replacement receipt, provider mutation, credential change, push or merge.
- Evidence: `/Users/frank/Library/Caches/Joey-Native-Build/credential-incident/{tool-environment-tests-final.log,core-tests-final.log,native-build-final.log,native-launch-canary.json,preservation-after.json,scan-final.json}`. Earlier failed toolchain and wrapper-parent attempts are retained/described in the incident report.
- Safe key-free development may continue. Owner-confirmed revocation, installed SwiftUI inspection, Drive filing/register reconciliation and platform acceptance remain separate open lanes. Google OAuth connections remain intact.


## Taxstone Library — 2026-10-31

Evidence root: `/Users/frank/Library/Caches/Joey-Native-Build/taxstone-library-20261031`. The current operational result and package links are in STATUS.md; `closeout.json` captures 106 inventoried episodes, two completed real episodes, four MP4s, eight companion receipts, preserved runtime identities, native installation and active monitoring. This is initial integration acceptance, not full-library completion or social platform ingestion.

All executable commands used `python3 Tools/run-local.py` with the existing Xcode `DEVELOPER_DIR` where required. Final native command used `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug -destination 'platform=macOS' -derivedDataPath /Users/frank/Library/Caches/Joey-Native-Build/taxstone-library-20261031/DerivedData build`; direct exit 0, `build-final-fairness.log`. Strict code-signature and all installed bundle hashes passed (`installation-dispatch.json`).

Final focused Swift command: `/usr/bin/swift test --filter 'TaxstoneLibraryTests|ProductionIntakeTests'`, direct exit 0, 11 executed/passed, zero failures/skips (`tests-dispatch-final.log`). Previous affected media/recovery command: `/usr/bin/swift test --filter 'TaxstoneLibraryTests|WorkflowTests'`, direct exit 0, 13 executed/passed, zero failures/skips (`tests-installed-final.log`). The initial unspecialized developer-directory attempt failed resolving XCTest; the existing Xcode toolchain resolved it. No global developer selection was changed.

Actual library processing first ran through the shared-core `joey-run taxstone-run --limit 1`; this completed one authorized 203.925333-second original with its verified existing transcript and two outputs. The installed native app then resumed the library, created/transcribed/rendered/filed the second episode, and advanced to a third. Controlled restarts preserved accepted output SHA-256/mtime/inode and source/transcript identities (`restart-evidence.json`, `accepted-before-dispatch-install.json`). Final installed `/usr/bin/swift-inspect dump-concurrency` returned direct exit 0 and showed the unchanged Joe monitoring timer (`operational-concurrency.txt`).

Native Taxstone UI observation and button-based Pause/Resume remain unverified: CUA getApp reported a locked desktop twice. This is a specific tool-access dependency, not evidence of universal native failure. Actual historical-clip adoption is not yet claimed; candidate media must pass source/audio/artwork/waveform/profile QA before reuse. No Buffer writes, social ingestion, publication, scheduling, email, permission change, push or merge occurred.
