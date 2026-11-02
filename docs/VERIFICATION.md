## Routing/migration closeout — PARTIAL (2026-11-02)

This is verification of existing delivery and Frank's reported completed file moves, plus narrowly authorized record repair. It is not a new production run. The earlier new-DUB source/register-write acceptance gate is outside this task. No media download, render, upload, move, copy, deletion, new job, publication or scheduling occurred. No Drive media/companion bytes or permissions changed. The sole external mutation was six independently verified duration-cell corrections in the existing Master Link List.

Evidence directory: `/Users/frank/Library/Caches/Joey-Native-Build/routing-closeout-20261102/`. Raw provider snapshots, local runtime data and repair proposals remain outside Git.

### Repository and installed routing

Origin: `https://github.com/franklinburrus/Joey.git`. Baseline local/remote main: `9a75a0f9c3e75af70d94a85d68595263cc81ff76`; development branch: `codex/routing-closeout`. Prior documentation was already merged in PRs #6/#7. This change adds only STATUS/VERIFICATION evidence; requirements, application code, native project, dependencies and installed bundle are unchanged. All 22 unrelated untracked duplicate files are preserved.

The installed ten-file bundle matches the start snapshot; executable SHA-256 is `c4fae13e649913970d0172023e972d224a8413dff1ffa1142c848440173ab99f`. Strict deep signature verification and Xcode project/Joey scheme discovery passed. The existing matching-build native reopen evidence in `dub-drift-audit-20261102/integration.json` remains applicable: accepted Taxstone shows Completed/23 clips; historical DUB shows Delivery incomplete/35 QA passes. Neither Resume nor Process was selected. No reinstall or repeated production acceptance was needed.

`DestinationResolver.swift` selects by verified owner, inspected source kind, asset role and source identity. DUB audio-led MP4s route as audio; Taxstone/Joe keep their own destinations and records. Joe's serialized DUB owner is disambiguated by `productionWorkflow == .joeBudden`. New originals use separate archive roots; verified historical originals are preserved.

### Eight live destination roles and instruction conflict

All eight configured roots are active folders with matching identities and recorded parents. Complete paginated direct-child inventories were read. Counts below are immediate children, including folders, not recursive clip counts.

| Role | Configured Drive ID | Direct children |
| --- | --- | ---: |
| DUB audio clips | `1FRi-yy2D9yenjQRailTA2iAbPaqAEPXm` | 5 |
| DUB native-video clips | `1380CHJ3a3kl7fXNIKWqUM7_DeTZUwxsy` | 1 |
| Taxstone clips | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` | 3 |
| Joe Budden clips | `1X5VNP6fo3VpZPu4ZW4p7Ggk2o_IAVGSI` | 25 |
| DUB audio originals | `109_QzHpF0Bi-OG6-AxuTDw1uHG4zeop3` | 2 |
| DUB video originals | `1GpuGWGIbSt3afwsi9L782soT9WJKOHS9` | 70 |
| Taxstone originals | `12g_etkCruq4tjG07t9hAqQffc4NqbSQK` | 1 |
| Joe Budden originals | `1IIYLVDhCvwf5ZoMb0aM5vpSCe-eMCmyK` | 0 |

The latest prompt names different DUB clip IDs. Raw Drive readback confirms `1fgABGYTtNC_h2u-v6fwTcPkVKjFd7GQx` (Joey Video Clips) is **trashed**, with zero active children; `1_s2K9Pw2Je93IwazQ6QgLjz_SimVYuPz` (Joey Audio Clips) is active, with zero children. They are children of the configured X Video/Audio folders. REQUIREMENTS section 11 explicitly supersedes those former roots. No configuration change can be inferred safely from this conflict, and no folder was restored. Clarification was requested; no answer had been received at this checkpoint.

The Drive connector omitted requested trash/checksum fields, so complete metadata was obtained through GET-only requests using the existing rclone OAuth connection. `provider_read.py` prohibits media transfer and has no mutation implementation. Both initial and final root metadata are identical; no permission failure was observed.

### Existing packages and Frank's reported migration

Two independent provider passes agree: **16 packages / 262 clips / 64 companions = 326 delivered files**, plus 16 source-original metadata checks. Every expected file exists once with matching ID, filename, immediate episode parent, bytes, MD5, SHA-256, link and saved access roles. Recorded permission fingerprints also match where present. There are zero unexpected episode children, duplicate expected IDs, duplicate filenames within an episode, or duplicate clip-byte identities across the audited packages. All source-original sizes/SHA-256 match their checkpoints. These counts cover Joey's known filed packages, not every historical file in the wider Drive tree.

Frank reports that the moves are complete. The current readback does not establish the required final placement: all 15 historically flagged episode folders retain the same direct parents as the prior readback. This does not infer what other files Frank moved. Current REQUIREMENTS require direct episode folders under the applicable clip roots.

| Package | Episode folder ID | Current direct parent | Clips |
| --- | --- | --- | ---: |
| DUB `dub-bc24818564d22380585be027` | `1_NJU2jWQEz3uSAvDYGXXJM9tfIr9s5iD` | `1N7HyLq-Fq8a2RIaXMe7Xs17Y8UqYuCcJ` (Dub under X Video) | 35 |
| Joe Episode 977 | `1DBHs-sQ8jpyALLiisOw1HUi09_aFoBDb` | `1N7HyLq-Fq8a2RIaXMe7Xs17Y8UqYuCcJ` | 17 |
| Taxstone `1ae8e260e0033a777f213141` | `1t6VEL_G2ozPSTaNANXldU6gy7de6Cmqr` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 2 |
| Taxstone `46898c5fc70c3c152215e5b0` | `1M-CakIReL8oZmihXq0escl_EtMVdDOAf` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 19 |
| Taxstone `5134623dc985abd5af160e4e` | `1fjWePls7ieTTTKpqFnGrYSRnmIM6OE-4` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 11 |
| Taxstone `710814e0e6fb7a8fec073443` | `1-lNT9IKT0Jwc3TStt-7rAd91xGkXqdSk` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 21 |
| Taxstone `77ade3f57f0576eea23d8ff7` | `1m2kcq1GyRf4yRg3vBFqjWbewRlwkzRzs` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 22 |
| Taxstone `8eadff92a6c6c263dde016d2` | `13STZ5d14uH-riK1bp9XvTvkgWCwZlZFN` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 11 |
| Taxstone `a7e6ff4bfa4d7ebc82ba274f` | `1bkZtSggMnaqrigvULctZ3pSnndH8YO9F` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 6 |
| Taxstone `c04fb3967b852f659a08de9e` | `1bDnduFUj79RSkTrumUQV8yluLMNNeZ1E` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 22 |
| Taxstone `c99f0d8fb23a15ae5763fc8e` | `19bc8NiQAKFrEtAqK8ETiZRmgKJNvSg1R` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 22 |
| Taxstone `d4487616a9e796b6ba501cb3` | `1KvUL1C6fscdsnVHgBDiU1gA8Xzc-WrRs` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 21 |
| Taxstone `daae42819794661120fea59e` | `1S7CkmADbbJooOZE6R2vRBq_2Y4XXF5cG` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 2 |
| Taxstone `eb9eb0e64110f6617f5457f8` | `11FyrmbdvN_h5TLXCvfnT8DNFdcYnFRmu` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 17 |
| Taxstone `f670e51da9d2cd0a1e5021fa` | `14gXkMAK9o5DY04VXixIlY8081aAL-DMY` | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | 11 |
| Accepted Taxstone `ab50e1cf3e21aec596cc88be` | `1eXKK3Pit7VnWKtlUF6zTHyBFoaejY0t1` | `1kxv3bbnPPRt914npHFUI51jrbCY0atyU` (correct root) | 23 |

The intermediate Taxstone parent is Taxstone X Clips beneath the Taxstone root. The 15 exceptions total 239 clips and 60 companions; the accepted Taxstone package contributes 23 clips/four companions. No file, parent, sharing permission or link was changed. Existing links resolve to the same provider IDs/access metadata; no new anonymous media download or social-platform ingestion test was performed.

### Existing records and the six-cell repair

All 16 source identities, manifest clip IDs/links and complete source-bound transcripts reconcile. Fifteen packages' manifest bytes match their saved provider receipts and current clip metadata. The historical DUB remote manifest is a separate content failure:

- File `16gkG0VVotxLf1GUU2T6zW4xhM8oWdXoG`, 340,302 bytes, SHA-256 `232ff7d0ec01fc9edf1f6322a967d4981374961f72a45cd3a7584c412f7089c4`, matches its old receipt but contains stale size/hash values for all 35 clips and six stale measured durations (76 scalar discrepancies, plus nested QA/Drive receipts).
- Its source identity, exact intervals, clip identities, filenames, Drive IDs/links and register references remain correct. Current local checkpoint and local manifest clip data match current provider media. The local manifest was not replaced.
- The canonical index `1dGk5Z8oh9Eeu1kMyAmmWzKcmmqQ9LprB` has the same six stale durations. All other index identities/links reconcile.
- The existing RECONCILE narrative describes generic padded shared output, while current DUB QA explicitly describes its historical landscape correction. Its existing counts still match.
- `proposed-clip-index.csv` changes only the six validated duration tokens. `companion-correction-proposal.json` records 146 exact clip-field replacements and required receipt/readback sequencing. These are drafts in the evidence cache, not uploaded or installed records. Companion content replacement requires upload semantics; the explicit no-reupload boundary remains unresolved. No synthetic receipt or premature COMPLETED state was created.

The live Master Library schema has sheet ID `672400447`, 4,468 grid rows, 25 grid columns and 20 populated headers; 4,467 data rows. All 35 expected DUB records uniquely occupy rows 4417–4451. Their clip IDs, Drive IDs, links, filenames and source/episode keys match. Taxstone and Joe records were not inserted into this DUB register.

Fresh local SHA-256 plus FFprobe measurements established the corrections below. Immediately before writing, the exact live row identity, string value, formatting and validation were read. One atomic batch used six `updateCells` requests, each with field mask `userEnteredValue` only.

| Master Library cell | Clip | Before (seconds) | Corrected/read back (seconds) |
| --- | ---: | ---: | ---: |
| F4423 | 7 | 129.766667 | 129.740000 |
| F4425 | 9 | 133.766667 | 133.740000 |
| F4440 | 24 | 116.700000 | 116.680000 |
| F4441 | 25 | 122.366667 | 122.340000 |
| F4448 | 32 | 133.866667 | 133.840000 |
| F4451 | 35 | 110.952000 | 110.966016 |

Independent connector CellData readback matched exactly, including unchanged formats, validation and neighboring cells. Independent OAuth GET of the full bounded `'Master Library'!A1:Y4468` FORMULA snapshot matched the before snapshot with only these six substitutions; schema, all other values/formulas and 35 unique identities are unchanged. Zero rows inserted, zero blind retries, zero provider/authorization failures. This corrects historical metadata; it does not exercise a new application-level production/register-write acceptance.

### Commands, results and preservation

All diagnostics ran through `python3 Tools/run-local.py`; Xcode/Swift additionally used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Command / evidence | Actual result |
| --- | --- |
| `/usr/bin/swift test --jobs 2 --filter 'DestinationRoutingTests\|DeliveryTests\|DriveFilingTests\|EpisodeFolderOwnershipTests'` | Exit 0; 31 passed, zero failures; 4.047 seconds. Isolated providers, no production mutation. |
| `/usr/bin/xcodebuild -list -project Joey.xcodeproj` | Exit 0; existing Joey project/target/scheme present. |
| `/usr/bin/codesign --verify --deep --strict '/Users/frank/Applications/Joey Native.app'` | Exit 0; unchanged installed bundle. |
| `audit_existing.py` | Exit 0; 16 packages, 326 receipts, 16 originals, 35 register identities verified; placement/content limitations recorded separately. |
| `finish_readback.py` | Final exit 0; only six sheet cells changed, all 35 identities unique, root metadata unchanged, correction drafts verified. First draft-only stage failed on an incorrect CSV header label; corrected to the observed `Measured duration (seconds)`. No additional write resulted. |
| `final_drive_read.py` | Exit 0; second independent read of all 326 files, 16 episode folders and 16 originals matches initial state; zero duplicate expected IDs or clip-byte hashes. |
| `preservation.py` | Exit 0; all 278 accepted outputs match checkpoint/QA SHA-256; all 1,545 runtime JSON files, 20 jobs, ten bundle files and 22 unrelated untracked files unchanged. |
| Prior full Swift/Python/native build and native reopen evidence | Reused for unchanged implementation/bundle; not newly run. Prior full Swift: 255 passed/four skipped/zero failures, then 41 affected tests after final cancellation adjustment; Python: 22 passed. |

The focused tests cover all eight route roles, ownership/source ambiguity, folder/source-hash reuse, incorrect parents, safe recovery and duplicate prevention. Existing verified production recovery/reopen evidence is reused; no successful job was interrupted to repeat it. No application code change requires another build. Technical export and actual social ingestion remain distinct.

### PRE-COMMIT DRIFT AUDIT

| Audit area | Finding |
| --- | --- |
| Current task / baseline | Existing routing and migration verification; `codex/routing-closeout` from `9a75a0f9c3e75af70d94a85d68595263cc81ff76`. |
| Files reviewed | AGENTS, Ultracave, REQUIREMENTS, IMPLEMENTATION_PLAN, STATUS, VERIFICATION, OPERATING_GUIDE; DestinationResolver, production intake, delivery/completion/reopen paths; relevant tests; complete task diff; live provider/local evidence. |
| Requirements alignment | Sections 11–15 routing, exact placement, canonical records, provider readback and preservation retain their invariants. No requirement weakened to excuse historical placement or stale companions. |
| Roadmap alignment | Task 3 verified delivery and existing routing correction closeout. No new production, feature, architecture or dependency work. The separate DUB production milestone remains unchanged and outside this task. |
| Scope control | Only STATUS/VERIFICATION enter Git. Six proven historical duration corrections are authorized by Phase 4. All 22 pre-existing untracked files, production media, transcripts, models, credentials, evidence cache and runtime records remain excluded. |
| Ambiguity and uncertainty | Prompt's retired roots conflict with current requirements; video root is trashed. Fifteen current placements do not satisfy the specified direct-parent invariant. Companion-content edits conflict with no-reupload instruction. These are explicit closeout blockers, not invented approval gates. |
| Architecture and quality | Native Swift/SwiftUI architecture and installed implementation unchanged. No refactor, dependency, credential or permission change. Accepted work and recovery checkpoints preserved. |
| Verification and evidence | 31 focused tests, project/signature checks, two live Drive passes, independent Sheets readback and preservation checks passed within the stated bounds. Stale companion contents and unresolved placement are not described as passed. |
| Corrections | Six duration cells repaired once; corrected the local diagnostic's header assumption; documentation now distinguishes receipt-byte integrity from manifest-content correctness. |
| Commit eligibility | **PASS for the explicitly documented partial verification/repair scope**, after full diff and staging review. This does not mark routing/migration CLOSED. |
| Remaining risks / next action | Integrate the authorized evidence-only change. Resolve which DUB mapping governs, reconcile the 15 exact placement exceptions without prohibited automatic moves, and permit or defer the concrete companion-record corrections. No new broadcast is required. |

The final status remains PARTIAL until those routing/migration requirements reconcile. Historical entries below are preserved as evidence of earlier tasks, including their separate acceptance limits.

---

## DUB register repair — mandatory pre-commit drift audit (2026-11-02)

This continuation implements the latest explicit instruction to repair concrete defects discovered by the drift audit. It is a bounded technical repair of roadmap Task 3, not completion of the source-blocked production mission. No real provider mutation, new media job, publication, scheduling or email was performed. The earlier preflight entry below remains historical evidence of the stage before this repair.

### Baseline, authority and complete scope

Origin is `https://github.com/franklinburrus/Joey.git`; development branch is `codex/dub-register-reconciliation`, based on `1a3afa99fe6a72f7a11c7e6366e8dea6ee616397`. Before repair, only STATUS and VERIFICATION contained task edits; nothing was staged and 22 unrelated untracked duplicate files were preserved. The audit read AGENTS, Ultracave, REQUIREMENTS, IMPLEMENTATION_PLAN, STATUS, VERIFICATION, OPERATING_GUIDE, LOCAL_HELPERS, the complete task diff, delivery/record/coordinator call paths and affected tests. REQUIREMENTS sections 13–15 govern current-schema reconciliation, bounded transient retries, cancellation, independent provider readback and completion. No requirements or destination mapping was changed.

### Six-part review

| Category | Evidence and disposition |
| --- | --- |
| Requirements alignment | Repair remains in the existing `DriveDelivery` owner. Typed HTTP failures distinguish permanent rejection from transient failure; fresh reads and unique Drive IDs govern reconciliation. Missing/changed schema cannot authorize writes or acceptance. No completion requirement was removed. |
| Roadmap alignment | Task 3 verified delivery and Task 4 native verification remain the current phase. No premature feature or architecture work was added. Actual new DUB production/register-write acceptance remains blocked and is not replaced by fixtures. |
| Scope control | Proposed files are Delivery.swift, RegisterReconciliationTests.swift, STATUS and VERIFICATION only. The 22 pre-existing untracked files remain excluded. No media, transcripts, credentials, models, runtime checkpoints, dependencies or requirement changes belong in the commit. |
| Ambiguity and uncertainty | Exact new source authority remains absent; the prompt's intermediate clip folders conflict with current REQUIREMENTS/installed resolver while requirements changes are prohibited. Those dependencies remain documented rather than guessed. A successful append with absent readback must fail without a new append. |
| Architecture and quality | Existing native Swift/SwiftUI architecture, serial coordinator, durable checkpoints and accepted media remain intact. Small private helpers preserve status and validate register snapshots; no new public interface, service or dependency. An independent reviewer identified cancellation error normalization as necessary to preserve the coordinator's CANCELLED state. |
| Verification and evidence | Behavioral red tests reproduced the defects. HTTP/rclone fixtures use dummy credentials and run the real adapter. Focused tests verify mutation counts, request ordering, exact row identities, supported-cell-only updates, unknown formulas, unrelated rows, duplicate rejection and reopen reuse. Full-suite, final focused/native-build and preservation results passed as recorded below. |

### Defects and corrections

1. The previous append loop caught every error and could issue three POSTs after HTTP 403. Permanent HTTP rejection now stops the affected operation immediately. Only explicitly transient HTTP/transport errors permit another append after a fresh valid read proves the identity absent.
2. The previous final append attempt had no subsequent readback, including when the provider committed before losing its response. The reconciliation loop now reads after all three permitted attempts and can accept a committed third attempt without a fourth write.
3. Missing `values` became an empty register, and headers were trusted after the initial read. Every snapshot now requires valid, unchanged headers; unavailable or changed schema stops the operation. A successful append absent from readback is an explicit failure with no repeat append.
4. Cancellation stops immediately. The coordinator recognizes `CancellationError`; URLSession's cancelled append now becomes that error type. A strengthened regression first failed on the wrong error type and then passed with the correction, preserving the native coordinator's cancellation classification.

### Executed verification and evidence

All commands use `python3 Tools/run-local.py`; Swift/Xcode commands also set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for that process only. Evidence directory: `/Users/frank/Library/Caches/Joey-Native-Build/dub-drift-audit-20261102/`.

- Initial register fixture compile attempt exited 1 due to incorrect `Interval(start:end:)` labels; corrected to the existing unlabeled initializer before behavioral testing (`register-red.log`).
- `swift test --jobs 2 --filter RegisterReconciliationTests`: exit 1; 12 tests, 13 assertion/uncaught-error failures across nine failing tests (`register-red-behavior.log`). Failures include three POSTs on 403, cancelled/unknown transport replay, missing/changed schema acceptance and missing final-attempt readback. Three existing invariants passed.
- `swift test --jobs 2 --filter 'RegisterReconciliationTests|DeliveryTests|DriveFilingTests|RecoveryRegressionTests'`: exit 0; 40 passed, zero failures, 60.962 seconds (`register-green.log`).
- `swift test --jobs 2 --filter RegisterReconciliationTests.testSuccessfulAppendMissingFromReadbackIsNotAppendedAgain`: exit 1; one test/two assertions failed, proving the remaining successful-response/absent-row duplicate risk (`missing-readback-red.log`). The stop guard was then added.
- `/usr/bin/python3 -m unittest discover -s Tests -p 'test_*.py'`: exit 0; 22 passed (`python-tests.log`).
- `swift test --jobs 2`: exit 0; 259 executed, 255 passed, four intentional opt-in skips, zero failures, 232.257 seconds (`full-swift.log`). This broad run precedes only the final one-line cancellation error normalization. Skips cover installed-assistant, two real-media opt-ins and separately enabled live Drive readback; isolated tests do not replace those operational acceptance boundaries.
- `swift test --jobs 2 --filter RegisterReconciliationTests.testCancellationDoesNotContinueReconciliationOrMutation`: exit 1; one test/one assertion failed on the wrong error type (`cancellation-red.log`).
- Final `swift test --jobs 2 --filter 'RegisterReconciliationTests|DeliveryTests|DriveFilingTests|RecoveryRegressionTests'`: exit 0; 41 passed, zero failures, 64.246 seconds, including all 13 register cases after cancellation normalization (`final-focused.log`). Unaffected media tests were not repeated for that one-line correction.
- `/usr/bin/xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug -destination 'platform=macOS' -derivedDataPath /Users/frank/Library/Caches/Joey-Native-Build/dub-drift-audit-20261102/native-build CODE_SIGN_IDENTITY=- build`: initial and final direct exits 0 (`native-build.log`, `final-native-build.log`). The final build includes cancellation normalization. `/usr/bin/codesign --verify --deep --strict --verbose=2` on that candidate: exit 0 (`signature.log`). This is a local ad-hoc build, not public distribution/notarization.

Initial clean build warnings concern the preserved duplicate icon assets, existing weak-capture diagnostics in JobModel and missing optional AppIntents metadata. The incremental final build reports only the AppIntents warning. SwiftPM also identifies two pre-existing untracked duplicate runner files as unhandled. These unchanged warnings do not justify deleting unrelated work or refactoring this task.

Preservation snapshot after testing began: all 22 unrelated file hashes, all 1,539 existing runtime JSON hashes and REQUIREMENTS match the original preflight snapshot (`preservation-before-install.json`). An initial audit helper incorrectly compared a structured runtime entry to a digest; the corrected comparison reads its `sha256` field and passes. No actual file drift was found. Baseline metadata and pre-repair documentation diff are retained in `baseline.json` and `preexisting.diff`. Production media and private diagnostic artifacts remain outside Git.

### Commit gate and remaining limits

**PASS for the bounded technical repair.** All ten commit criteria are satisfied within that explicitly documented partial scope: requirements/roadmap alignment, scoped files, resolved implementation ambiguities, passing applicable tests, preserved existing functionality, accurate documentation, no prohibited files/dependencies and recorded limitations. The complete source/test/documentation diff was reviewed; the independent reviewer found no residual material findings after cancellation normalization. Final staged-file and secret-pattern verification must confirm the same four-file scope immediately before commit. `git diff --check` passed. The GitHub connector lacks branch-protection detail; a read-only GitHub CLI query confirms current main has no required status checks or enabled branch protection. No protection is bypassed.

The original user instruction already authorizes a development commit, push, PR and permitted verified merge for necessary source repairs. This audit grants no additional authority. Git integration and protected installation remain unexecuted at this pre-commit checkpoint. Deployment must preserve a rollback, exact tested bundle and runtime/accepted-output identities. No new production source, actual DUB register write/readback, current portrait episode package or social ingestion is accepted by these tests. Full production outcome remains **BLOCKED** by source-specific authority and the unresolved filing-map conflict; the historical DUB package and Taxstone production evidence below remain distinct.

### Verified integration and protected deployment

The staged-file gate passed with exactly four files and no credential patterns or prohibited artifacts. Commit `fd540079bf4b09735f7a767494f55b01238644b5` was pushed on `codex/dub-register-reconciliation`. [PR #6](https://github.com/franklinburrus/Joey/pull/6) was independently read back as merged at `2026-11-02T16:36:22Z`, merge commit `7a4c70af333e4844226b75b68309b7d06e9f2197`. Local main fast-forwarded to that remote commit; `git diff --exit-code fd540079bf4b09735f7a767494f55b01238644b5 HEAD` returned 0. The merged tree is exactly the tested candidate tree. No required checks, commit statuses, check runs or workflow runs were returned; the absence of configured cloud checks is not presented as cloud-test success. Connector argument validation errors were corrected before their respective read/merge actions; no uncertain mutation was blindly replayed.

The existing protected installer was reused from the prior routing release, with only evidence/staging/rollback paths and the recorded base commit adapted in the external task cache. It verified the stopped app, exclusive runtime locks, candidate hash/signature, all protected identities and a preserved original bundle before replacing the installation. Direct installer exit: 0. It preserved 446 protected files, including all 278 accepted MP4 identities, with rollback at `/Users/frank/Applications/Joey Rollbacks/2026-11-02-before-register-reconciliation/Joey Native.app`. Installed executable SHA-256: `c4fae13e649913970d0172023e972d224a8413dff1ffa1142c848440173ab99f`; all ten bundle files match the tested candidate. No further rebuild was needed after merge because the entire tested tree was identical.

The first idle-stop diagnostic exited 1 after the process exited but before its email lease released. A subsequent targeted process/lock-holder inspection found no remaining process or holder; the installer then independently acquired all required locks before mutation. There was no forced kill, lock bypass or settings change. Joey relaunched through the minimal environment as PID 1505. `check-launch.py` returned 0 after launch and after UI readback. Both show queues remain paused; settings and all accepted media/checkpoints are preserved. The original 1,539 JSON hashes were identical before installation. After native startup, 1,538 remain identical; only `joe-automation.json.lastCheckedAt` changed from `2026-11-02T15:11:08Z` to `2026-11-02T16:37:50Z`, from the existing startup discovery check. Its enabled state, queue and every other field are unchanged. An initially strict whole-runtime comparison reported this real timestamp delta; it is recorded rather than reset or hidden.

Native UI readback first encountered a locked Mac, then succeeded through the supported computer-use interface. Taxstone reopened as Completed with 23/23 QA/Drive and verified records. Selecting historical DUB opened its 35 accepted clips and 35 saved register receipts with Delivery incomplete, preserving the routing gate. No Resume, Process, Buffer, publishing or scheduling action was used. The screenshot independently confirms the correct DUB source title and picture; grouped accessibility text retained the prior Taxstone title. This pre-existing UI code was unchanged; the accessibility observation is nonblocking for this source-blocked register repair and is not a claim of complete accessibility acceptance.

The documentation-only follow-up reuses the unchanged implementation tests and installation evidence. Its six-part audit remains PASS for this bounded repair: only STATUS/VERIFICATION record completed actions and exact remaining limitations; no product, roadmap, route, runtime or test change is introduced. Final staging must include only those two Markdown files, preserve all 22 unrelated files and pass whitespace/secret-pattern checks before the authorized follow-up commit/PR. Evidence: `commit-gate.json`, `verification.json`, `integration.json`, `installation/installation.json`, `installation/before.json`, `installation/post-launch.json` and `installation/post-ui.json`. Actual DUB production remains BLOCKED; no new clips, companions, uploads or register writes occurred.

---

## Final DUB acceptance preflight — BLOCKED before production (2026-11-02)

This entry records new read-only verification, not a second production delivery. No eligible, specifically authorized undelivered DUB source was established. No new job or production request was created. New planned/rendered/QA-passed/filed clips: **0/0/0/0**; uploads: **0**; register inserts/updates: **0/0**. Full-show coverage, actual register writes, production retry behavior and final completion remain unexecuted for a new job. The user’s Phase 2 authorization boundary limits continuation to non-mutating preflight until the source is established.

### Repository and installed application

The existing origin is `https://github.com/franklinburrus/Joey.git`. Local `main`, upstream `origin/main`, and a fresh `git ls-remote` agree at `1a3afa99fe6a72f7a11c7e6366e8dea6ee616397`. GitHub connector readbacks independently confirm PR #4 merged at `4bc576d26d3526c6fe6c12ee1964a799d99c5de2` and PR #5 merged at `1a3afa99fe6a72f7a11c7e6366e8dea6ee616397`. No tracked changes existed at preflight; all 22 unrelated untracked duplicates are hash-preserved. This task changes only STATUS and VERIFICATION, locally/uncommitted. No application source change, PR, merge, reinstall or deployment was performed.

`xcodebuild -list` returned exit 0 with existing project, target and scheme `Joey`. All ten installed files exactly match `routing-release-20261102/verification.json`; no additional bundle files or implementation-hash drift was found. Installed executable SHA-256 remains `a1c456591c936f4422e48174425bc428937c4b836f47695e8aa1b7d1fbbfb5f3`; version 1.0/build 1, bundle identifier `devplaceholder.C88ISLGM.Joey`, running PID 83800. Strict deep signature validation returned exit 0. Native computer-use readback opened saved jobs without starting processing: Taxstone showed Completed/23 QA passes; DUB showed Delivery incomplete/35 QA passes/35 register receipts. An initial computer-access error cleared on the next supported observation, so no desktop-access blocker remains.

The prior Swift result (246 executed, 242 passed, four intentional skips, zero failures), Python 22 passes and native build are **reused existing evidence**, not newly executed tests. Implementation files match those receipts. No media render/QA or full test suite was repeated for documentation-only work.

### Source eligibility and duplicate preflight

Reviewed the six serialized DUB-owned Joey jobs, their production-workflow discriminators, current local DUB manifests, `Dub/config/approved_sources.json`, source recovery/title-reconciliation records, 70 direct video-archive files and 89 DUB audio-archive files. A general source approval or archival permission does not authorize a new shared full-show package. No candidate below was selected for production:

| Review priority | Source | Evidence and disposition |
| --- | --- | --- |
| 1 | `x:broadcast:1oKMvNPnEzDGQ` — Can't DUB Me Radio: PACK EM UP!!!! | Strong explicit prior Joey-production authority, but already delivered as `dub-bc24818564d22380585be027`; 35 existing Joey rows and 54 total source matches across older packages. The nine-clip diagnostic request expressly excludes upload. Duplicate production is ineligible. |
| 2 | `1DxLdZBwezMxm`, `1qGvverwMlaGB`, `1qKDzWkERNwJV`, `1DGleVlAjBqJL` | Existing manifests/receipts describe prior production and delivery, not authority for another Joey package. Recent recorded original paths are absent. The old Frenzy Friday top-level pending label is superseded for media filing by its recorded 26-file delivery, and its X-highlight task is separately marked completed. |
| 3 | `1rGmqqargvLGy`, `1kJzDDYMPZXKv` | Explicit older source approvals found, but current register has 25 matches at rows 2320–2344 and 32 at rows 1986–2017. No authority for a new overlapping full-show delivery was established. |
| 4 | `1AxRnnDqbEyxl` — Just CRASHED OUT; `1jxXggVLYgyJZ` — Hate in America | Source-specific old audio-process approvals and archive lineage exist. Current register has four rows at 1982–1985 and 20 at 1962–1981 respectively under original tweet URLs `2085043857385726038` and `2084863570777461204`. Searching Space IDs alone returned zero and was insufficient; URL-alias reconciliation exposed the existing deliveries. |
| Excluded | Joe Episode 977 and synthetic UI jobs | Joe uses the distinct `joeBudden` workflow and cannot satisfy a DUB-only register gate. Synthetic jobs have diagnostic-only authority. |

Known historical DUB original: https://x.com/i/broadcasts/1oKMvNPnEzDGQ; stable ID `x:broadcast:1oKMvNPnEzDGQ`; recorded broadcast date 2026-10-29; 4729.152333 seconds; native moving video, 1920×1080 H.264 with AAC audio, approximately 30 fps; 2,359,633,468 bytes; SHA-256 `2dc4e7c4e639ef56f9c28bb43e761c1a757d04c83e0dc66e03b38d50433a51fe`. The exact original remains in Drive as https://drive.google.com/file/d/1RJklyN44ttg6DczGpOp6J1-XvzNfinuF/view ; current provider SHA-256 and byte size match the checkpoint. Its saved local path `/Users/frank/Dub/work/dub-clips/1oKMvNPnEzDGQ/source/source.mp4` does not exist. No download or fresh complete-source decode was performed for this ineligible duplicate candidate. Broadcast identity/date/stream details are from the existing source-bound records, not a newly queried X broadcast.

### Runtime, platform and destination preflight

Fresh helper diagnostics returned exit 0: FFmpeg 8.1.2, FFprobe 8.1.2, rclone 1.74.4 and MLX Whisper 0.4.3 import. Required `libx264`, `h264_videotoolbox`, AAC, scale/pad/concat/fps and waveform-related filters exist. Configured local Python/model are present; adapter SHA-256 is `f41ff480247f1be47366b4a883964eb2f3e17ed085aa4b866cd6f13dc1d0722b`, matching the installed bundled adapter. Free space measured 45,529,608,192 bytes (approximately 42.4 GiB). Runtime stays under `~/Library/Application Support/Joey Native`; diagnostic settings were copied only into the task cache. No new inference/model download or AI-service credential use occurred.

The existing production runner's `check-drive` used an isolated settings copy and returned exit 0, reading all eight authoritative roots and the live 20-column Master Library schema through existing rclone/Sheets OAuth. This establishes read capability, not a new write-permission test. No permission/provider failure was encountered.

Fresh Buffer connector reads of Apache / My organization (`6a9ef058f39b6bf3faeff64c`) confirmed connected/unlocked X Premium channel `6a9ef0ffcd8b9c702c23cdcb` and Instagram Business channel `6a9f2a92cd8b9c702c2620a9`, both `dubwiththefiles`; Instagram direct publishing is configured (`defaultToReminders=false`). Reused same-day official-document observations at `2026-11-02T14:10:56Z`, with all five saved HTTP-200 evidence files hash/size verified and current evidence expiry `2026-11-03T14:10:56Z`. No timestamps/settings were renewed without need. Actual production profile: X via Buffer 140 seconds/512,000,000 bytes; Instagram Reel via Buffer 900 seconds/299,999,999 bytes; both allow 1080×1920 and up to 60 fps. Joey's common export remains 1080×1920/30 fps/H.264/yuv420p/progressive/square pixels/AAC-LC/faststart, below 300,000,000 bytes, with conservative 5–139.9-second measured exports. Thus the preferred 8–10-minute target is shortened by the verified common limit. Technical packaging is separate from actual platform ingestion; none was attempted.

Live Drive metadata identifies the prompt's `1fgABGYTtNC_h2u-v6fwTcPkVKjFd7GQx` as **Joey Video Clips**, directly inside REQUIREMENTS root `1380CHJ3a3kl7fXNIKWqUM7_DeTZUwxsy` (**X Video Clips**). Likewise, `1_s2K9Pw2Je93IwazQ6QgLjz_SimVYuPz` is **Joey Audio Clips**, directly inside current root `1FRi-yy2D9yenjQRailTA2iAbPaqAEPXm` (**X Audio Clips**). These are distinct folders, not aliases. The installed resolver explicitly rejects the retired intermediate-root architecture. The prompt simultaneously specifies those intermediate IDs and forbids changing product requirements; clarification is required before filing. Existing anyone-with-link reader access was observed and preserved. No folder, permission or routing change occurred.

### Independent historical readback and preservation

The read-only diagnostic verifies the existing episode https://drive.google.com/drive/folders/1_NJU2jWQEz3uSAvDYGXXJM9tfIr9s5iD . It contains exactly **35 clips and four canonical companions**, with no unexpected child, duplicate expected Drive ID or duplicate expected register identity. Every current clip matches local SHA-256, provider MD5/SHA-256, byte size, filename, episode parent and recorded legacy access roles. All four remote companion downloads match their saved receipt SHA-256. The existing source-bound transcript and exact interval arithmetic cover 4729.152333 seconds once, with no exclusions. Existing QA hashes match all accepted clip bytes; those are prior QA results, not a newly executed QA run.

The package's parent is the historical `1N7HyLq-Fq8a2RIaXMe7Xs17Y8UqYuCcJ`, not either proposed new filing root. Current accepted clips are the earlier landscape correction (2,248,656,777 aggregate bytes), not a new shared portrait export. Local `clip_manifest.json` is 307,334 bytes/SHA-256 `fda574722ebef7f7cdc5bf051e32e65db0c94738ead8273de3914b6ffd681d7c`; the remote receipt/download is 340,302 bytes/SHA-256 `232ff7d0ec01fc9edf1f6322a967d4981374961f72a45cd3a7584c412f7089c4`. The local manifest already had that hash in the initial task snapshot. These pre-existing historical differences were recorded, not repaired or accepted as current production completion. Canonical companion content acceptance for a new job remains outstanding.

Fresh Sheets metadata: Master Library sheet ID `672400447`, 4,468 grid rows, 25 grid columns, one frozen header row; 4,467 populated data rows and 20 populated headers. Exact existing Joey clip rows: `Master Library!A4417:T4451`, one row for each saved Drive ID, with matching links, filenames and original URL. Before/after `FORMULA` reads of `Master Library!A1:Y4468` are equal, including unrelated values/formulas and unknown columns. Both canonical snapshot hashes are `68432efc344f93d3beac0f23e693f319b00e769b2e046ba8485b7fc07df78a1d`. Rows inserted/updated: zero. A successful read is not register-write acceptance.

Final local preservation: all **278 accepted MP4 SHA-256 values** match their saved checkpoints, including the 23 accepted Taxstone clips; all **1,539 pre-existing runtime JSON files** are byte-identical; all **22 unrelated untracked files** retain their SHA-256; REQUIREMENTS remains `f38ad652af4ee5b6abcec6f9bc122af61a1a20b8e20fdbc0b86e9f7f09a86096`. Both show queues remain paused. No accepted media, historical package, source archive or permission was mutated.

### Recovery evidence and bounded limitations

Reused `routing-release-20261102/filing-recovery-after.json`, `upload-interruption.json`, `production-recovery-after.json` and `completed-reopen.log`: the prior real Taxstone delivery preserved 23 accepted hashes/mtimes/QA receipts, its folder ID and the existing clip-1 provider ID across native restart and a single supervised interrupted upload. No destructive interruption was repeated. This task opened saved native records without Resume; it did not perform a new application restart or new DUB production recovery test.

Code trace confirms accepted-output hash reuse, source-bound transcript reuse, completion guards and fresh register inspection before another append. A separate static concern was found at `Delivery.swift`'s register append catch: it currently catches every append error before looping, rather than explicitly excluding permanent permission failures. A real or isolated permanent-denial case was not executed; do not represent this path as verified or confuse it with a current credential failure. No code repair was made during the source-blocked, non-mutating preflight. Keep this concrete concern visible for the next scoped acceptance continuation.

### Commands, failures and evidence

All Joey diagnostics used the minimal-environment launcher. Fresh successful commands (direct exit 0):

```sh
python3 Tools/run-local.py /usr/bin/git ls-remote origin refs/heads/main refs/heads/codex/drive-routing refs/heads/codex/drive-routing-verification
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tools/run-local.py /usr/bin/xcodebuild -list -project Joey.xcodeproj
python3 Tools/run-local.py /usr/bin/codesign --verify --deep --strict --verbose=2 '/Users/frank/Applications/Joey Native.app'
python3 Tools/run-local.py .build/debug/joey-run check-drive --root /Users/frank/Library/Caches/Joey-Native-Build/dub-final-acceptance-20261102/read-only-preflight
python3 Tools/run-local.py /usr/bin/python3 /Users/frank/Library/Caches/Joey-Native-Build/dub-final-acceptance-20261102/read-only-reconciliation.py
```

The first inventory helper exited 1 on `jobs/.DS_Store`; restricting enumeration to directories recovered. Drive search returned an empty video listing while folder fetch returned 70 files; the direct folder listing and Joey/rclone preflight established the actual inventory. Historical manifest lookup paths missing from disk were replaced by retained title-lineage records and current provider identity checks. The first historical reconciliation diagnostic exited 1 on the pre-existing manifest mismatch; the second exited 1 on the missing saved local source. The final diagnostic records those exact limitations, verifies the original via provider SHA-256 without downloading it, and returns exit 0 **for inventory collection**, with `currentRoutingAcceptance=false` and the failed local companion checks explicitly retained. No failed acceptance check was waived or relabeled a pass. Initial documentation whitespace verification found a trailing blank line; the final documentation pass removes it.

Task evidence: `/Users/frank/Library/Caches/Joey-Native-Build/dub-final-acceptance-20261102/`, including `installed-verification.json`, `job-inventory.json`, `candidates.json`, `video-archive.json`, `audio-archive.json`, exact source/URL row-search receipts, `roots.json`, `runtime-preflight.json`, `helper-preflight.json`, `official-evidence-integrity.json`, `provider-preflight.log`, `historical-dub-readback.json`, `register-before.json`, `register-after.json`, `register-preservation.json`, `runtime-before.json`, `unrelated-before.json` and `preservation.json`. Media, transcripts and OAuth remain outside Git. Final outcome: **BLOCKED**, pending an exact eligible source's production/Drive authorization and resolution of the destination conflict. Overall Joey production acceptance is not claimed.

---

## Final production acceptance — Taxstone verified; overall task PARTIAL (2026-11-02)

Real installed-app acceptance completed `taxstone-ab50e1cf3e21aec596cc88be`, source `soundcloud:261140871`, at `2026-11-02T15:05:24Z`. **23 clips passed automated QA and Drive verification; all four companions passed upload/download readback; the durable job checkpoint is COMPLETED.** Correct direct-root episode folder: https://drive.google.com/drive/folders/1eXKK3Pit7VnWKtlUF6zTHyBFoaejY0t1, parent `1kxv3bbnPPRt914npHFUI51jrbCY0atyU`. No manual destination selection was needed.

An independent read-only Python provider audit used the existing real rclone OAuth and direct Google metadata/content GETs. It verified all 27 file IDs, exact names, parents, sizes, local SHA-256 and matching provider checksums, permission fingerprints, one matching source folder, no duplicate filenames/clip bytes, source-bound transcript, exact CSV timestamps and complete chronological source coverage. It independently downloaded all four companion files. The uploaded manifest remains FILED with the durable app checkpoint identified as completion authority, avoiding circular self-hashes or premature external completion. Original archive `1wN7bh6hEwzdduJi9XrzVNmKyxJD2n92C` remains unchanged under legacy parent `1wQMwzUconRC3UCvH2jpL1kD__ctBv29p`; no original was moved or duplicated. Source and destination permissions remained unchanged.

Real recovery evidence: native Cancel and Save Progress after clip 1, restart, and Resume preserved its accepted bytes/mtime/QA. During filing, the bounded diagnostic interrupted exactly one supervised `rclone copyto` for new clip 2 at `15:02:10Z`; the app, originals and historical media were untouched. Production reconciliation retried automatically and continued. Final checks preserved all 23 accepted hashes/mtimes/QA receipts, the same episode folder, and the already verified clip-1 provider ID. The completed-job runner reopen returned exit 0 without new delivery work. No duplicate episode folder or remote file remained.

Final live audit returned exit **0**, **1 test passed**, 82.344 seconds. It verified **326 receipts across 16 packages / 262 clips**: the new correct package plus the **15 historical misplaced packages / 239 clips / 299 receipts**, unchanged from the pre-production audit. All eight roots and permission fingerprints are unchanged. Historical migration remains unexecuted; the deterministic reversible plan below and `historical-migration-plan.json` identify the proposed exact folder/parent operations.

The first before/after comparison helper exited 1 because Swift dictionary iteration emitted companion receipts in a different array order. Inspection confirmed only ordering differed. Sorting receipts by immutable Drive ID produced an exact match for all 15 historical packages (exit 0); no provider data, expected integrity value or application validation was changed.

Commands and direct exits (all 0):

```sh
python3 Tools/run-local.py python3 /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/provider-acceptance.py before
python3 Tools/run-local.py python3 /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/interrupt-one-upload.py
python3 Tools/run-local.py python3 /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/provider-acceptance.py after
python3 Tools/run-local.py python3 /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/filing-recovery.py after
python3 Tools/run-local.py .build/debug/joey-run run /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/completed-request.json --root '/Users/frank/Library/Application Support/Joey Native'
JOEY_REAL_MEDIA_INPUTS=/Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/live-input-after.json python3 Tools/run-local.py /usr/bin/swift test --jobs 2 --filter LiveDriveRoutingTests
python3 Tools/run-local.py python3 /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/final-preservation.py
```

All **255 previously accepted local MP4s**, unrelated protected records, source/plan, REQUIREMENTS and **22 unrelated untracked files** remain unchanged. Installed bundle hashes still match the tested build. DUB and Taxstone capability observations were renewed from current matching authenticated accounts and official upload-surface documentation; immutable account/surface/technical limits and all other settings were preserved. Joe's ordinary `lastCheckedAt` changed; both show queues remain paused. For the post-acceptance capability refresh, two idle-stop diagnostic probes exited 1 around the app-lifetime email lock; source inspection confirmed that lifetime lease, and independent readback then verified app exit and lock release before settings renewal (exit 0). No forced kill or lock bypass occurred. The installed app reopened successfully afterward.

Evidence: `provider-before.json`, `provider-after.json`, `production-progress.jsonl`, `production-recovery-before.json`, `production-recovery-after.json`, `upload-interruption.json`, `filing-recovery-before.json`, `filing-recovery-after.json`, `completed-reopen.log`, `live-readback-after.json`, `historical-preservation-after.json`, `final-preservation.json`, and capability/installation receipts in `/Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102`. Runtime media, transcripts, account evidence and OAuth remain outside Git.

**Unverified gate:** a new DUB production upload and Master Link List write/readback needs an authorized undelivered DUB source. Current account/profile evidence and the existing 20-column schema are verified; all 35 historical DUB clips have exactly one existing register row. Those reads are not a new register-write acceptance. Taxstone correctly writes no DUB rows. No credential outage, platform ingestion, publication, historical migration or live production delivery in every category is claimed. Overall task is PARTIAL despite verified implementation, integration, deployment and Taxstone production acceptance.

The sections below retain earlier release checkpoints. Their pending statements are superseded by this final evidence.

---

## Verified integration and native installation — 2026-11-02

Implementation commit `1457f581a7979c173ad4f4dbc45bdb15c8443b7f` was pushed on `codex/drive-routing` and merged through [PR #4](https://github.com/franklinburrus/Joey/pull/4) using the repository's normal merge-commit strategy. GitHub confirmed merged/closed state and merge SHA `4bc576d26d3526c6fe6c12ee1964a799d99c5de2`; fetched local/remote `main` agree. The remote PR diff matched the complete reviewed staged diff exactly. No branch protections/rules, required check runs, commit statuses or submitted reviews were configured. No protection was bypassed. The merged tree equals the tested implementation tree.

The native build command below was rerun against merged `main` and returned exit 0. The entire candidate app bundle, including its debug dylib, matched the tested build's SHA-256 map. The existing protected installer was adapted with fresh staging/rollback paths and run through `Tools/run-local.py`, exit 0. It held all four existing processing/storage/library/mail locks, preserved checkpoint backups, verified candidate/staged/installed signatures and hashes, and retained the prior bundle at `/Users/frank/Applications/Joey Rollbacks/2026-11-02-before-drive-routing/Joey Native.app`.

Installation preserved **422 protected files**, including **255 accepted MP4s**: inode, nanosecond mtime/ctime and sizes unchanged; JSON/text/CSV/Markdown contents hash-checked. Installed application: `/Users/frank/Applications/Joey Native.app`. Normal `open` launch from Applications and native window observation passed. Quit/reopen produced a new process and restored existing jobs. Executable/bundle hashes matched; all 255 accepted files and settings remained unchanged across restart. The only pre-existing protected JSON change was Joe's ordinary `lastCheckedAt`; Joe and Taxstone enabled flags remained false. The initial computer-tool lock error cleared on retry; native access is verified. Historical jobs correctly display Delivery incomplete while retaining their passed QA counts and records.

```sh
python3 Tools/run-local.py python3 /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/installation/install.py
python3 Tools/run-local.py /usr/bin/open '/Users/frank/Applications/Joey Native.app'
python3 Tools/run-local.py python3 /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/installation/check-launch.py
python3 Tools/run-local.py python3 /Users/frank/Library/Caches/Joey-Native-Build/routing-release-20261102/installation/check-launch.py post-restart.json
python3 Tools/run-local.py .build/debug/joey-run check-drive --root '/Users/frank/Library/Application Support/Joey Native'
```

All commands returned exit 0. Exact source/PR/bundle receipts are in `integration.json`, `verification.json`, `installation/installation.json`, `installation/post-launch.json` and `installation/post-restart.json` within the evidence directory below. `provider-preflight.log` verifies all eight roots and the unchanged 20-column Master Link List schema. Independent read-only provider acceptance also found exactly one existing register row for each of the 35 historical DUB clips. No new register write is claimed.

Production acceptance is still in progress. The unfinished authorized Taxstone job resumed from its existing source, transcript, artwork and 23-clip plan. Only current Taxstone capability evidence was renewed from authenticated channels and official documentation; immutable limits, accounts and surfaces did not change. Native cancellation after the first accepted clip, application restart and explicit Resume preserved that clip's SHA-256, mtime and QA receipt and continued at clip 2. This establishes real processing recovery, not interrupted-upload recovery. Final filing/readback results will be added before closeout.

---

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
