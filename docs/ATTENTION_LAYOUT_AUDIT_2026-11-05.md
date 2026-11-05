# Joey attention and adaptive window audit

November 5, 2026. Prepared for Frank.

## Application repair implementation closeout

All four P2 findings and the Shows navigation label are corrected in the installed native app. The approved implementation scope excluded content. The original audit below remains evidence of the baseline defects and earlier verification limits.

| Finding | Delivered correction | Current owner |
| --- | --- | --- |
| F1 unreadable history | Structured inventory, visible recovery notice/details/Refresh, healthy history and guarded creation while identity is unresolved | [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:50) |
| F2 artwork recovery | Accepted hash reuse precedes artwork access. Only required renders load/validate/resolve artwork | [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:295) |
| F3 source marker | Current checking, rejection and pause remain distinct from retained source evidence | [JobPresentation.swift](/Users/frank/Documents/Joey/Joey/Core/JobPresentation.swift:18) |
| F4 helper upgrade | Hash-versioned atomic helper installation, prior/custom retention, safe concurrent reads/publication and FIFO rejection | [Configuration.swift](/Users/frank/Documents/Joey/Joey/Core/Configuration.swift:40) |
| Shows wording | Back to Shows and Return to Shows match the actual destination | [ContentView.swift](/Users/frank/Documents/Joey/Joey/ContentView.swift:6) |

### Final verification

Final Swift suite passed with direct exit 0, 399 executed, 395 passed, four opt-in skips and zero failures. Python passed 22/22, direct exit 0. The skipped cases were live Drive routing, real media and two installed-assistant checks. Targeted regressions demonstrated the relevant failures before correction. Final whole-change review caught a FIFO startup-hang edge case, which was repaired with nonblocking opening before regular-file validation and a bounded bundle/legacy/managed-path regression. Re-review found no remaining material introduced issue.

Native fixture verification exposed an integration defect in the new recovery notice. Its placement outside the bounded root viewport raised the native minimum height to 2158 points. An AVPlayer-only wrapper did not solve it and was removed. Keeping the recovery notice and panes inside the existing GeometryReader viewport reduced the measured minimum to 440 × 512 points. With a loaded generated portrait MP4 and the notice visible, native Left, Fill, Return to Previous Size and Left again produced 840 × 1050, 1680 × 1050, 1280 × 800 and 840 × 1050-point windows. The original proportional player remains in use. [ContentView.swift](/Users/frank/Documents/Joey/Joey/ContentView.swift:46)

The viewport correction changed only a view excluded from the Swift Package test target. Core/test suite inputs remain identical. Final Xcode build, strict signing and native visual/metric checks cover the corrected view. Native synthetic observation also verified recovery details, healthy-history preservation, repair/Refresh clearing the notice, neutral rejected-source markers and Back to Shows. The final installed UI separately retained Taxstone's 11/26 accepted clips and capability-ready Resume. No production Resume was clicked.

The final app is `/Users/frank/Applications/Joey Native.app`, version 1.0 (1), native dylib SHA-256 `7c732c3a856e7854728a580828a0cfed762cb615e316de54542fa25551823189`. Pre-plan rollback remains at `/Users/frank/Applications/Joey Rollbacks/2026-11-05-before-app-reliability/Joey Native.app`. The intermediate reviewed build remains at `/Users/frank/Applications/Joey Rollbacks/2026-11-05-before-recovery-viewport/Joey Native.app`. Candidate, installation, process, bundle, helper, signature and rollback readbacks returned direct exit 0.

Final protected readback preserves 31 jobs, 509 accepted outputs, 28 originals and 808 protected identities. Extended baseline checks preserve 1529 media-file identities and 3189 runtime-record hashes, with only the expected helper settings pointer and normal monitoring timestamp changed. Legacy helper bytes and every other decoded setting remain preserved. No content processing or live provider write occurred during implementation.

Evidence is under `/Users/frank/Library/Caches/Joey-Native-Build/app-reliability-20261105`. Final installation receipts are in viewport-install/. Native metrics are in preview-viewport-final.log and the repeated half-screen screenshot is preview-repeat-half-green.jpg. Actual sleep/wake, VoiceOver and other display scaling remain unverified. Earlier native-tool lock reports remain retracted. Repair source was committed as `261c894`. Frank subsequently authorized including the retained historical documentation and pushing main. The publication closeout reuses the installed artifact after fresh source/bundle/signature readback.

## Original audit status

The capability-renewal defect and fixed-width main window are repaired in the installed native application. Tax Season Episode 7 passes the current read-only Resume assessment after renewal from live account and official-source observations. Its production checkpoint remains at 11/26 accepted clips, 0/26 verified Drive clips and 0/4 companion records. Continuing production is separate from this audit.

Actual macOS half-screen tiling and expansion were visually verified. The workflow and main-code audits identified four P2 findings for subsequent implementation. The prioritized plan below includes effort, dependencies, risks and observable acceptance criteria.

## Audit target and scope

The authoritative application checkout is `/Users/frank/Documents/Joey`, using the existing `Joey.xcodeproj`. Origin is `https://github.com/franklinburrus/Joey.git`. Local `main`, `origin/main` and live default `main` matched `2ca35487ed188ab65012494350a1bcc4a79c21c2` at the opening check. The linked `/Users/frank/Documents/ChatGPT/Joey` folder supplies instructions and historical reference. Current product criteria come from `docs/REQUIREMENTS.md`, including its later creator-routing, width, link-workflow, Joe retention and queue-only email amendments.

Three documentation files already had uncommitted edits when this task began. Those edits are preserved. This task changes the two requested behaviors, their focused regressions, this report and the active STATUS checkpoint. Existing historical reports remain available. Source changes remain uncommitted on the existing checkout. No branch switch, reset, merge or push occurred.

The audit inspected the supported media journey, authoritative state transitions, helper boundaries, persistence, cancellation, storage, provider reconciliation and native presentation. Representative existing tests used local synthetic media and provider doubles. Production sources, accepted media, transcripts and provider records remained preserved. Inspection of optional email and assistant integrations was limited to their core workflow boundaries and relevant existing tests.

## Process version and criteria

Completion for this assignment requires an exact capability diagnosis and safe recovery, preservation of accepted work and identity, observed native half-screen behavior, and one consolidated audit and prioritized improvement plan. Broader production acceptance remains governed by REQUIREMENTS section 18.

Evidence classes are identified separately throughout this report.

- **Code inspection** establishes control flow and concrete implementation defects.
- **Automated execution** establishes behavior of the specific local fixtures and provider doubles that ran.
- **Native observation** establishes displayed controls, window behavior and saved recap navigation.
- **Live-service readback** establishes the current Taxstone channel metadata and retrieved official documentation. It establishes no media ingestion or production-delivery result.

## Attention issue root cause and resolution

### Current source evidence

The attachment accurately corresponds to the current saved job `taxstone-dab68d252199c1c4e076c776`, source title Tax Season Episode 7. This correspondence was independently checked against its checkpoint and the installed UI. The saved state is `FAILED` at `capability verification`, retaining the previous generic renewal error. Source, transcript, 26 planned clips and 11 accepted clips remain present in its saved evidence.

Only the maximum-width observations differ between the saved and configured technical contracts.

| Requirement | Saved job | Configured profile at opening | Result |
| --- | --- | --- | --- |
| X account | JailCallwithTax | Same account | Matches |
| X upload surface | Buffer X video | Same surface | Matches |
| Instagram account | thejailcallwithtaxstone | Same account | Matches |
| Instagram upload surface | Buffer Instagram Reel | Same surface | Matches |
| Audio canvas | 1080 × 1920 | 1080 × 1920 | Matches |
| X and Instagram maximum width | 1080 pixels each | 1920 pixels each | Broader capability |
| X maximum duration / bytes / FPS | 140 seconds / 512000000 bytes / 60 fps | Same values | Matches |
| Instagram maximum duration / bytes / FPS | 900 seconds / 299999999 bytes / 60 fps | Same values | Matches |
| Maximum height | 1920 pixels each | 1920 pixels each | Matches |
| Saved observation expiry | November 3 at 9:10:56 a.m. EST | — | Expired |
| Configured observation expiry | — | November 4 at 12:46:56 p.m. EST | Expired |

Both opening evidence files existed and matched their recorded SHA-256 values. Their age still prevented new operations. The width rejection was an implementation defect. The expired observation was a legitimate current prerequisite.

### Trace through the application

The detail view originally sent Resume directly to `JobModel.start`. Coordinator then located the saved identity, loaded owner-specific configuration and attempted capability renewal. `SharedProfile.renewingEvidence` compared complete immutable contracts for exact equality before considering observation freshness. That rejected an increase in maximum width even though the saved audio export remained within every current limit. The catch path preserved the job and its clips, then persisted the generic message at capability verification. The native Resume button remained available because it checked worker activity only.

Renewal now compares account, platform, upload surface, canvas, delivery mode and each maximum explicitly. A current observation must support every saved maximum. The returned profile retains the saved technical limits and identity, copying only validated observation dates, official sources and account evidence. Lower limits, changed identities, changed canvases and invalid evidence remain rejected. Supplied requests with a changed immutable contract still encounter the existing coordinator identity guards. The native-video output profile continues to be validated against the saved contract. This repair grants no larger export to an old job. [Domain.swift](/Users/frank/Documents/Joey/Joey/Core/Domain.swift:109) [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:69)

`Configuration.resumeIssue` reuses the same renewal and resolved-output checks for a read-only assessment. The detail view checks on job changes, configuration notification, application activation, explicit Check Again and a 30-second idle refresh. Manual Resume rechecks immediately in the view and model. Coordinator repeats admission under its processing lock before processing and provider operations. Existing validation also rejects mid-run expiry. [Configuration.swift](/Users/frank/Documents/Joey/Joey/Core/Configuration.swift:27) [JobModel.swift](/Users/frank/Documents/Joey/Joey/JobModel.swift:219) [JobDetailView.swift](/Users/frank/Documents/Joey/Joey/JobDetailView.swift:71)

The attention section now precedes the preview. It names the failed field or expiry, supplies Production Setup and Check Again actions, and disables Resume while capability admission fails. Capability details show account/surface match results, numeric saved/current limits and each platform’s current expiry date. Conflict diagnostics omit raw account names, upload-surface values and evidence paths. The previous attempt remains available in its own disclosure.

### Live renewal and exact recovery state

Fresh Buffer readback used the same organization and channel IDs as the saved evidence. X remained a connected, unlocked Premium profile. Instagram remained a connected, unlocked business channel using direct publishing. Four existing official Buffer pages returned HTTP 200 and reconfirmed the applicable duration, size, frame-rate and 1920-pixel longest-side constraints. Account metadata involved four read calls, including account discovery, channel listing and two channel details. Provider writes were zero.

Only Taxstone observation fields in local settings were renewed. Account identities, upload surfaces, configured technical maxima, audio canvas, DUB settings, every job checkpoint and all accepted-media identities were preserved. The existing 24-hour observation lifetime was retained. The renewed interval is `2026-11-05T12:46:56Z` through `2026-11-06T12:46:56Z`, equivalent to November 5–6 at 7:46:56 a.m. EST. Proof and its referenced source snapshots are private local runtime/evidence files. Previous evidence and the pre-renewal settings backup remain available.

A compiled read-only invocation of the actual `Configuration.resumeIssue` against the production checkpoint and renewed settings returned direct exit 0 and `RESUME_READY`, retaining saved width limits of 1080/1080 and 11/26 accepted clips. No coordinator run occurred. To continue this existing production job, open its details, choose Check Again and then Resume. The coordinator will verify the source/checkpoint and accepted hashes, reuse valid source/transcript/plan/accepted clips, and continue missing work under the normal delivery guards.

Post-renewal native readback is now verified. After resetting the computer-use session and selecting the installed application by its exact path, the UI showed “Requirements ready to recheck” and an enabled Resume button, with 11/26 accepted clips. The earlier “locked Mac” explanation was a false positive from the native-control tool and is retracted. A generic tool error did not establish the Mac’s lock state. No production Resume was clicked during the audit.

Official sources retrieved for renewal follow. Their local snapshots and hashes are retained with the evidence.

- Video specifications and Instagram/X surface limits. [Buffer video documentation](https://support.buffer.com/articles/sharing-videos-through-buffer-LOe2p2rnAI)
- X third-party duration and account distinctions. [Buffer X documentation](https://support.buffer.com/articles/using-xtwitter-with-buffer-nA84XnWtuU)
- Instagram business/Reel requirements. [Buffer Instagram documentation](https://support.buffer.com/articles/using-instagram-with-buffer-YSjg2dXFV8)
- Resolution and third-party upload constraints. [Buffer troubleshooting documentation](https://support.buffer.com/en-us/articles/troubleshooting-video-uploads-in-buffer-LK0CldlFNB)

## Half-screen changes and visual verification

The former `HStack` always displayed a 220-point sidebar and two minimum-width panes, with a 1040 × 660-point minimum main window. An actual native half-screen command left the original application at least 1040 points wide on this display.

The main window now permits a 440 × 480-point minimum. Available content width selects the layout. At 1100 points and above it shows the sidebar and two panes. From 900 through 1099 points it collapses navigation into a menu and keeps both panes. Below 900 points it shows one workspace or job detail pane with explicit list/detail navigation. These thresholds reserve room for the existing panes. macOS determines the actual tile dimensions. Selected job identity survives expansion. Settings can reopen the requested job directly into narrow details. Buffer retains access to its separate list and handoff views. [ContentView.swift](/Users/frank/Documents/Joey/Joey/ContentView.swift:34)

The detail view uses vertical scrolling, wrapping attention text and fit-based horizontal/vertical action groups. Preview bounds use a proportional aspect ratio and AVPlayer preserves the media's picture proportions. Native navigation and primary action labels remain exposed to accessibility. Existing readable fonts and the source/artwork presentation are retained. Apple's current ViewThatFits documentation guided the control wrapping. [Apple layout documentation](https://developer.apple.com/documentation/swiftui/viewthatfits)

### Measured environment

| Measurement | Observed value |
| --- | --- |
| Display | Built-in Color LCD, Apple M1 |
| Native panel classification | 2560 × 1600 Retina |
| Rendered backing resolution | 3360 × 2100 pixels |
| Effective display size | 1680 × 1050 points at 60 Hz |
| Backing scale | 2.0 |
| Tested native left-half window | 840 × 1050 points, captured at 1680 × 2100 pixels |
| Tested expanded window | 1680 × 1050 points, captured at 3360 × 2100 pixels |
| Recovery setup sheet | 740 × 740 points, captured at 1480 × 1480 pixels |

Native observation covered the half-screen attention message, disabled Resume, safe capability disclosure, scroll to QA/Drive/record counts, list/detail switching, reopening completed history and returning to Taxstone. The Production Setup sheet fit inside the measured tile and closed without saving. Keyboard Down/Return selection through the native navigation menu opened Jobs. Expansion restored the sidebar and both panes while retaining Tax Season Episode 7.

Subsequent redundant native snap commands after Fill did not change the captured geometry through the automation interface. After reconnecting, fresh tiling-menu interactions returned `AXError.invalidUIElement`, including after refreshing the accessibility state. The successful initial half-screen transition and narrow-to-wide expansion are evidenced. Repeated wide-to-narrow snap verification remains limited by the native-control tool. Arbitrary display scales, smaller tiles, VoiceOver, larger system text settings and full-screen Split View were not exercised. Existing fixed-size setup/import/settings dialogs were visually checked only where stated above.

Screenshots are retained outside Git.

- Half-screen attention and actions. [Screenshot](</Users/frank/Library/Caches/Joey-Native-Build/attention-layout-20261105/half-screen.jpg>)
- Safe capability comparison. [Screenshot](</Users/frank/Library/Caches/Joey-Native-Build/attention-layout-20261105/capability-details.jpg>)
- Half-screen stage counts and recap after scrolling. [Screenshot](</Users/frank/Library/Caches/Joey-Native-Build/attention-layout-20261105/half-screen-scrolled.jpg>)
- Recovery dialog. [Screenshot](</Users/frank/Library/Caches/Joey-Native-Build/attention-layout-20261105/recovery-dialog.jpg>)
- Expanded layout. [Screenshot](</Users/frank/Library/Caches/Joey-Native-Build/attention-layout-20261105/wide-screen.jpg>)
- Renewed capability readiness with enabled Resume. [Screenshot](</Users/frank/Library/Caches/Joey-Native-Build/attention-layout-20261105/renewed-ready-wide.jpg>)

## Evidence map and workflow results

The normal durable progression is PLANNED, PROCESSING, QA_PASSED, FILED and COMPLETED. Each stage persists its own evidence. A later failure preserves earlier accepted work. COMPLETED requires the product's complete artifact and record predicate plus final provider verification. The UI also checks that predicate before displaying Completed.

| Stage and owner | Inputs and outputs | Completion, state and recovery controls | Evidence from this task |
| --- | --- | --- | --- |
| Link intake, NewJobView / ProductionIntake | Supported original YouTube/X link, Content and Workflow become an immutable JobRequest. Legacy local requests remain recoverable. | Production requires Drive and transcript-assisted planning. Joe requires a numbered official-channel full episode. Discovery errors return to the UI. | Source inspection and ProductionIntake tests. No new production intake. [ProductionIntake.swift](/Users/frank/Documents/Joey/Joey/Core/ProductionIntake.swift:6) |
| Capability and identity, Domain / Configuration / Coordinator | Saved contract and current owner-specific observations become an admitted saved job. | Exclusive processing lock, stable identity and legacy matching prevent a competing checkpoint. Exact conflicts reject new operations. Current evidence is required before operations. | Actual checkpoint comparison, five new core regressions, manual-Resume regression and read-only current readiness. [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:69) |
| Acquisition and source verification, Acquisition / Media | Original link, existing local source or hash-bound archive becomes inspected source metadata and retained bytes. | Existing own-job sources and valid archives are reused. Actual streams, hash and expected duration reject substitution or incompleteness. Download state survives retry. | SourceIntegrity and Workflow tests. Network acquisition of a real production source was not repeated. [Acquisition.swift](/Users/frank/Documents/Joey/Joey/Core/Acquisition.swift:42) |
| Complete-original retention, Coordinator / DestinationResolver / Delivery | Verified original and creator/source classification become the matching archive reference. | Production archives before transcription/clipping. Correct creator ancestry and byte-equivalent reuse prevent duplicate or relocated originals. | Drive provider doubles and source/routing inspection. No live archive write. [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:193) |
| Transcription, Acquisition / local helper | Complete source and valid supplied/cached transcript become source-bound timestamped canonical text. | Source ID, SHA-256 and duration bind reuse. Raw ASR and bounded recovery proof remain available. Missing helper/model or unsupported corruption fails accurately. Legacy model-independent processing retains explicit editorial limitations. | Twenty Transcript tests and source integrity tests. Fresh whole-show local inference was not run. [Acquisition.swift](/Users/frank/Documents/Joey/Joey/Core/Acquisition.swift:146) |
| Planning, Editorial / Planning / DurationPolicy | Transcript, retained intervals, explicit mode/count and saved limits become chronological clip intervals, titles and exceptions. | Plan is created when absent. Exact retained coverage rejects gaps/duplicates/reordering. Uncertain ads remain. Explicit fixed intervals are validated. Accepted deterministic plans cannot silently change basis. | Planning, ProductionIntake and Workflow tests. [Planning.swift](/Users/frank/Documents/Joey/Joey/Core/Planning.swift:32) |
| Artwork and branding, AudioPresentation / Delivery / JoeBranding | Correct creator/episode artwork or Joe's expressly approved assets become render inputs. | Ownership/source/hash checks preserve the approved presentation. Missing inputs report a dependency. Artwork recovery finding F2 below remains. | Code inspection and existing audio/native media fixtures. [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:229) |
| Rendering and automatic QA, Media / Coordinator | Verified source, plan and presentation inputs become one accepted shared MP4 per clip with SHA-bound QA. | Matching accepted QA and current file SHA skip rendering. Attempt directories fence interrupted writers. Decode, timing, audio/picture fidelity, framing and waveform checks run. Supported re-encode repairs are bounded. Clip-local failure does not discard other accepted clips. | Media, SourceIntegrity, Workflow and recovery fixtures. No accepted production clip was rerendered. [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:239) |
| Coverage and local companions, Planning / Records | All accepted outputs, source mappings and transcript become QA_PASSED and the canonical local package. | Full-show coverage is reconciled before filing. Missing production editorial requirements stop completion. Local output creation cannot establish COMPLETED. | Planning, Workflow and recovery execution. [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:309) |
| Drive folder and clip delivery, DestinationResolver / Delivery | Accepted file identity and authoritative creator route become unique verified folder/clip receipts. | IDs, actual parents, ancestry, bytes/checksums, links, access and duplicate counts are checked. Persisted folder intent and readback reconcile uncertain writes before retry. Existing different media is preserved. | Fourteen DriveFiling tests and recovery doubles. No live upload or permission change. [Delivery.swift](/Users/frank/Documents/Joey/Joey/Core/Delivery.swift:330) |
| Companions and register, Records / Delivery | Clip/transcript/index/manifest/reconciliation and applicable DUB register data become verified receipts. | Four companion readbacks are required. DUB alone uses its Master Link List. Schema and file-ID reads precede appends. Lost responses reconcile before replay. Unknown columns/formulas remain preserved. | RegisterReconciliation and DriveFiling tests plus recovery doubles. No live register write. [Delivery.swift](/Users/frank/Documents/Joey/Joey/Core/Delivery.swift:484) |
| Completion and recap, Domain / Coordinator / JobPresentation | All accepted identities, routed receipts, companions, transcript and applicable register rows become COMPLETED and a persisted recap. | Unique remote IDs and complete evidence are required before final provider package verification and durable completion. Completed local reopening verifies accepted bytes without requiring a new provider write. | Completion/recovery tests and native completed-history reopening. The 48/48 production recap displays saved results. [Domain.swift](/Users/frank/Documents/Joey/Joey/Core/Domain.swift:460) |
| Cancellation, restart and resume, JobModel / Persistence / Processes / StorageManager | Durable stage, accepted files and uncertain-operation evidence become a preserved stopped/recoverable job. | Atomic restricted-permission checkpoints, locks, child process-group supervision and bounded retries protect state. Explicit cancellation waits for termination. Capacity polling does not replay work. Startup excludes creator/email-owned jobs. | NativeModel, recovery, protected-launch and Workflow tests. The app was safely relaunched with all automations paused and zero unowned resumable jobs. Actual sleep/wake remains untested. [Persistence.swift](/Users/frank/Documents/Joey/Joey/Core/Persistence.swift:34) |

Queue-only email remains a separate admission boundary. Incoming links require per-item Content/Workflow selection and explicit Process before joining the same coordinator. Joe and Taxstone background queues remain disabled. This audit neither enabled a queue nor consumed production work.

## Main-code findings

Severity reflects user impact under the demonstrated preconditions. All four findings have code-level evidence. Their production incidence is qualified individually. These baseline findings were subsequently authorized for app-only implementation and are now resolved as recorded above.

### F1 P2 Resolved unreadable checkpoints disappear from history

`Coordinator.jobs()` uses `try?` inside `compactMap`, removing an unreadable or undecodable `job.json` from its successful result. `JobModel.refresh()` receives no error for that file. History and startup recovery can therefore hide existing work. A malformed legacy checkpoint also falls outside the collection used to reconcile old identities. Files are preserved, but the user receives no recovery explanation. [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:26) [JobModel.swift](/Users/frank/Documents/Joey/Joey/JobModel.swift:213)

Return readable jobs together with explicit unreadable-checkpoint diagnostics. Preserve each file and prevent affected-source processing until its identity is reconciled. Existing recovery tests exercise valid, incompatible and interrupted checkpoints. No located regression combines one malformed checkpoint with a healthy job. Confidence is high from control flow. No malformed production checkpoint was created for this audit.

### F2 P2 Resolved accepted audio recovery unnecessarily depends on artwork

Audio artwork resolves before the loop skips accepted, SHA-matching clips. Link requests commonly omit artwork, and `artwork.json` is written but has no loading path. A job resuming only delivery can therefore fail on an unavailable artwork input or repeat an artwork lookup despite having no render work. [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:230) [Delivery.swift](/Users/frank/Documents/Joey/Joey/Core/Delivery.swift:436)

Resolve artwork only when a clip actually requires rendering. Reuse durable owner/source/hash-bound artwork when available. Keep artwork enforcement for every required render. A focused all-accepted-audio recovery fixture should prove zero artwork calls, zero rendering and unchanged accepted identities while delivery reconciliation advances. Existing recovery coverage concentrates on native video. Confidence is high from ordering and call ownership. The outage precondition was not injected into a production job.

### F3 P2 Resolved rejected source can retain a green verification marker

The Source stage becomes Verified original whenever `job.source` exists. Source-validation failure intentionally restores the saved evidence snapshot, then persists FAILED at source. Those correct preservation semantics can leave a green current-verification marker beside a source hash/duration/classification rejection. [JobPresentation.swift](/Users/frank/Documents/Joey/Joey/Core/JobPresentation.swift:20) [Coordinator.swift](/Users/frank/Documents/Joey/Joey/Core/Coordinator.swift:371)

Distinguish retained historical evidence from a currently rejected source. Preserve all source, clip and receipt artifacts. Extend PresentationTests with the present-but-rejected source cases already represented in SourceIntegrityTests. The latter tests passed in this task. The inconsistent marker follows directly from the current presentation predicate. No fresh native source-failure UI was induced.

### F4 P2 Resolved owned transcription adapter lacks upgrade reconciliation

Configuration copies its bundled transcription helper only when the owned file is absent. Hash comparison runs when the configured path is missing or points into a build/plugin directory. Once the normal owned helper path is saved, subsequent bundle changes do not trigger comparison or reconciliation. Acquisition executes that configured helper. An app update can therefore continue using an earlier adapter. [Configuration.swift](/Users/frank/Documents/Joey/Joey/Core/Configuration.swift:49) [Acquisition.swift](/Users/frank/Documents/Joey/Joey/Core/Acquisition.swift:175)

The current installed helper and configured helper match SHA-256 `f41ff480247f1be47366b4a883964eb2f3e17ed085aa4b866cd6f13dc1d0722b`. This finding concerns the demonstrated future-upgrade path. Introduce versioned, bundle-hash-verified reconciliation for the app-owned helper while preserving custom adapters and accepted transcripts. Existing protected-launch coverage checks unchanged settings, with discovery disabled. No located test exercises differing old-owned and new-bundled adapters.

### Reviewed controls without an additional demonstrated defect

Inspection and the specified tests cover exclusive coordinator ownership, source rejection preservation, accepted-output hash reuse, secure helper environment allowlists, supervised worker groups, storage ownership/inode/hash checks, duplicate-resistant Drive reconciliation and uncertain Sheets append readback. Completion predicates require accepted output identities, correct creator routing, unique Drive IDs, companions and applicable register evidence. These results retain their stated fixture and service scope.

The baseline also contained a minor navigation wording issue, now corrected. In narrow Shows mode, the Job List toggle returns to the Shows workspace. A later wording correction can name the actual destination. It does not prevent opening job details or navigating elsewhere.

## Prioritized improvement plan

Estimates are developer working days including focused verification, with processing time called out separately. Current-task rows describe delivered changes. Later rows remain planned.

| Order and status | Problem and proposed change | Dependency and owner | Effort | Risk | Observable acceptance |
| --- | --- | --- | --- | --- | --- |
| 1 P1 Delivered | Broadening capability observations incorrectly blocks saved audio jobs. Preserve the saved contract and renew compatible observations. Add exact diagnostics and prerequisite-gated Resume. | Existing SharedProfile, owner configuration and native JobModel. Joey maintainer. | 1 day actual task scope | High if identity or limits were weakened. Regression checks retain them. | Same-account/surface broader observations retain stable identity and every saved limit. Lower limits and changed identities dispatch no provider work. Expiry and evidence integrity failures name the requirement. |
| 2 P1 Delivered within measured scope | A forced 1040-point three-pane window obstructs half-screen use. Collapse navigation and panes according to available width. | Existing SwiftUI views and actual macOS display. Joey maintainer. | 0.5–1 day | Medium UI/navigation risk. | Actual 840 × 1050-point tile exposes attention/actions and scrolling without overlap. Production Setup fits. Expansion restores all panes and selection. Repeat snap after Fill needs the follow-up observation described below. |
| 3 P2 Completed F1 | Saved work can silently disappear from history. Surface per-checkpoint read failures while retaining healthy jobs and protecting affected identities. | Coordinator job-loading result and JobModel presentation. | 0.5–1 day | Medium recovery/migration risk. | One malformed and one healthy synthetic checkpoint yield a visible healthy job and actionable recovery diagnostic. Both files remain unchanged. An affected legacy source cannot create a duplicate job. |
| 4 P2 Completed F2 | Accepted-only audio delivery depends on artwork. Load verified durable artwork and resolve it lazily for required renders. | Existing artwork model and Coordinator render boundary. | 0.5–1 day | Low–medium. Owner/source/hash binding must remain mandatory. | All-accepted audio reaches delivery reconciliation with unavailable artwork, no render/artwork call and identical accepted hashes/QA. A required render still blocks on missing or incorrect artwork. |
| 5 P2 Completed F3 | Green Source status can contradict a current rejection. Present current rejection separately from retained evidence. | Persisted source-failure semantics and JobPresentation. | 0.5 day | Low presentation risk. | Hash, duration and classification failures never show current Source verification as passed. Preserved artifacts and unaffected completed jobs remain intact. |
| 6 P2 Completed F4 | Future app updates can use an old owned ASR adapter. Reconcile app-owned helpers by bundle hash/version while preserving custom paths. | Configuration and bundled resource provenance. | 0.5–1 day | Medium migration risk. | Old owned helper plus new bundle selects the current verified adapter. Custom helpers and accepted transcripts stay unchanged. Repeated loads are idempotent. |
| 7 P2 Deferred content acceptance | Complete installed-native audio acceptance remains narrower than the code and fixture coverage. Continue one specifically scoped authorized audio job through its native recap and actual delivery/records. | Selected source/job authority, current account evidence, capacity/assets/tools and existing provider access. | 1–2 days plus processing | Real media and provider effects. Keep separate from this audit. | Native intake/recovery, original retention, complete transcript, chronological coverage, waveform presentation, QA, clip/four-companion verification, applicable register and reopened recap are observed. Accepted stages are reused. |
| 8 P3 Native fixes verified with stated limits | Repeat snap after Fill, smaller tiles and larger-text/VoiceOver behavior are incompletely observed. Perform a bounded native window/accessibility pass. Also correct the Shows return label. | Working native-control session. | 0.25–0.5 day | Low. No production processing required. | Wide-to-narrow repeat and intermediate width preserve selected job, attention and controls. Any smaller-dialog limitation is reproduced and corrected within the layout owner. Keyboard and VoiceOver labels match actual destinations. |
| 9 P3 Unverified sleep/wake observation | Actual sleep/wake remains distinct from engine cancellation/restart fixtures. Observe a controlled local interruption and recovery. | Scoped isolated native fixture and available Mac. | 0.5 day | Low with isolated runtime. | Workers terminate or pause appropriately. Restart resumes only missing work. Accepted identities and uncertain-write reconciliation remain intact. |

Keep the compact active objective, proof and next action at the top of STATUS. Historical receipts remain useful without reopening passed production stages or creating another policy/checklist system.

## Verification performed

All project builds, tests, diagnostics and installation commands used `python3 Tools/run-local.py` and direct executable arguments. The Xcode developer directory was `/Applications/Xcode.app/Contents/Developer`.

| Verification | Direct result | Evidence |
| --- | --- | --- |
| Capability regressions, RecoveryRegressionTests and selected storage/capability cases | Exit 0, 27 executed, 27 passed, zero failures | `capability-regressions.log` |
| Native model, planning, Drive filing, register reconciliation, presentation, intake, protected-launch and Workflow tests | Exit 0, 66 executed, 66 passed, zero failures | `workflow-tests.log` |
| Final NativeModelRegressionTests after diagnostics/admission changes | Exit 0, 7 executed, 7 passed, zero failures | `native-model-final.log` |
| Media, source integrity and transcript selection | Exit 0, 49 executed, 48 passed, one opt-in real-media skip, zero failures | `media-source-transcript-tests.log` |
| Existing Xcode project native Debug build | Exit 0, BUILD SUCCEEDED | `native-build-verified.log` |
| Candidate and installed strict deep code-signature verification | Exit 0 | `signature.log`, installation readback |
| Protected native installation and relaunch | Exit 0 on completed phases | `installed.json`, `launch.json`, `readback.json` |
| Post-renewal native readiness readback | Requirements ready to recheck and Resume enabled, without processing | `renewed-ready-ax.txt`, `renewed-ready-wide.jpg` |
| Actual renewed production request read-only assessment | Exit 0, RESUME_READY, saved width 1080/1080, QA 11/26 | `renewed-readiness.log` |
| Source diff whitespace check | Exit 0 | `git diff --check` |
| Independent final source/test diff review | No material introduced defect identified | Review covered Core, preflight/diagnostics and responsive views |

The test selections overlap. Their invocation counts are reported separately. A complete fresh suite, cloud CI and actual platform ingestion were not run. The widening and diagnostic regressions failed against the original behavior before repair. An initial legacy-recovery assertion exposed fixture timestamp precision and was corrected before the final behavioral checks. The new model test first failed to compile before its missing admission methods were added. That compile failure supplies API absence evidence only.

One installation readback initially failed to see the expected launched process. A fresh process inventory identified the exact launched PID and installed executable, and rerunning the unchanged readback succeeded. Bundle hashes, signatures, runtime identities and rollback then verified. No forced process kill was used.

## Delivery and preservation

The updated app is `/Users/frank/Applications/Joey Native.app`, version 1.0 (1). The prior app is retained at `/Users/frank/Applications/Joey Rollbacks/2026-11-05-before-attention-layout/Joey Native.app`. Candidate, installed and rollback bundle hashes are recorded in the installation receipts.

Protected installation readback covers 31 jobs, 509 accepted outputs, 28 originals and 807 protected identities. The only normal launch change was Joe monitoring's `lastCheckedAt`. The subsequent authorized Taxstone capability renewal changed local settings and added its evidence. It preserved all 31 checkpoint hashes, all source/output identities and every other decoded setting. Production media was checked through protected identity/size/timestamp metadata. This task did not reread all media bytes for a new complete hash audit.

The evidence directory is `/Users/frank/Library/Caches/Joey-Native-Build/attention-layout-20261105`. It contains build/test logs, source and bundle hashes, runtime baselines, rollback/install receipts, private settings backup, live capability observations, official-source snapshots and screenshots. Production/runtime material remains outside Git.

## Limitations and next action

The production job is ready for a capability-admitted Resume. It still has 15 clips awaiting acceptance and all required delivery/record work pending. Those counts remain accurate. Full installed-native audio delivery, actual sleep/wake, live Drive/Sheets recovery and social platform ingestion retain separate acceptance scope.

Post-renewal native readiness is verified and the unlock request is withdrawn. The remaining repeated-snap observation requires working native controls. A later production continuation should use the existing Taxstone checkpoint and current evidence. Implement broader code findings in the order above under their own scoped work. This audit supplies no publication, deletion, permission-change or backlog-processing authority.
