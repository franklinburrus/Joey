# Joey Native Implementation Plan

> Existing implementation roadmap. Current task state and evidence are recorded in STATUS.md. Historical handoff limitations below are superseded by Frank’s subsequent explicit implementation and installation instructions. First production delivery and the approved UI/final branding milestone are complete; Taxstone Library Mode is installed and running; initial real deliveries are verified, with native UI acceptance pending.

**Goal:** Implement the standalone local media workflow in REQUIREMENTS.md.
**Architecture:** SwiftUI calls a serial actor coordinator with atomic JSON checkpoints and cross-process locking. Foundation Process invokes installed media tools without a shell; Swift owns planning, state, hashes and provider readback. Existing Xcode folder membership compiles the shared core; Swift Package Manager provides a dependency-free test/runner harness using the same files and Xcode toolchain.
**Tech Stack:** Swift, SwiftUI, Foundation, CryptoKit, AppKit/CoreGraphics, FFmpeg/FFprobe, existing yt-dlp/rclone/local ASR.
**Spec:** REQUIREMENTS.md, sole current requirements document.


## Authoritative filing correction — 2026-11-02

Final closeout verification (2026-11-02): the seven active creator-based destinations, all 16 historical packages/262 clips/64 companions and existing 35 DUB register identities now reconcile. Frank authorized the remaining historical DUB companion edits; the three existing record IDs were updated with conditional writes, independently downloaded, and matched to current media/coverage/access and persisted receipts. Media, Taxstone packages, sharing, register data and unrelated files remain preserved. Installed routing and completed-job reopening pass without new production, migration or application changes. This routing/migration project closes on the verified merge of the final STATUS/VERIFICATION record; the containing PR and external integration receipt establish Git closure. Unrelated whole-product/new-DUB/social-ingestion acceptance remains separate. Details below retain the earlier implementation sequence and release history.

Latest explicit continuation: Frank completed the creator-first reorganization under Content, confirmed all DUB destinations, consolidated Taxstone into Taxstone Clips/Taxstone Full Episodes, renamed Joe Budden Clips and retired Joe's full-episode archive. Verify his actual moves with rclone and preserve IDs/bytes/permissions; update the existing resolver's names, roots and ancestry. Preserve historical serialized Joe archive identities while excluding that retired root from active preflight. Stop archiving new Joe full episodes; register only fresh application-owned Joe sources for removal after durable verified completion, using the existing storage/lock safeguards. Preserve all Taxstone full episodes, DUB originals, accepted media, imports, reused sources and records. Add isolated lifecycle/recovery regressions, run affected checks and the native build, audit the complete diff, then integrate and redeploy the necessary app change. No new production job or media reprocessing is part of this continuation. Current results and exact final IDs are in STATUS/VERIFICATION and REQUIREMENTS section 11; the following paragraphs preserve the earlier eight-root release history.

Frank's eight-root mapping in REQUIREMENTS section 11 supersedes the historical two-root implementation. Extend the existing Swift coordinator and Drive adapter, without replacing the native application or changing media production requirements.

1. Centralize destination and verified ancestry in `DestinationResolver.swift`. Preserve request serialization; use the explicit Joe workflow as its ownership discriminator.
2. Pass the resolved route through folder creation/reuse, archive selection, uploads, interrupted reconciliation, final package verification, library readback and Buffer preflight. Remove manual destination controls. Preserve verified legacy originals and report misplaced packages without relocation.
3. Independently check IDs, actual parents, ancestry, hashes, sizes, permissions and duplicates. Download companions. Keep DUB Master Link List writes/readback under its existing schema; Joe and Taxstone use separate episode records. Require complete evidence before COMPLETED.
4. Exercise all eight mappings, ambiguous identity, wrong parent/ancestry, recovery, deduplication, source preservation, permissions, companions and completion transitions with meaningful Swift tests. Build the existing Xcode project. Use read-only real provider/accepted-media evidence where live production writes would duplicate or relocate existing packages.
5. Record exact commands, counts, live inventory and remaining operational dependencies in STATUS and VERIFICATION. Installation, relocation and publication are separate actions; no success claim may substitute simulated provider tests for production delivery.

Frank authorized integration, protected installation and eligible production acceptance on 2026-11-02. Review, regression repair, full local verification, PR #4 merge, merged-source build, protected installation, launch/restart/data checks, real Taxstone delivery (23 clips plus four companions), interrupted-upload recovery and independent provider readback are verified. The final historical audit confirms 15 misplaced packages/239 clips/299 receipts unchanged. Overall task remains PARTIAL: a new DUB upload/register-write acceptance requires an authorized undelivered source; current matching account/profile evidence and schema are verified. Historical relocation remains separately authorized and unexecuted, with a deterministic reversible plan in VERIFICATION. REQUIREMENTS and all 22 unrelated untracked files remain unchanged. Final documentation follows through a scoped verified follow-up commit; no application code changed after the tested routing commit.


## Progress at verified handoff — 2026-10-31

- Tasks 1–2: core/media implementation, model-independent processing and documented local acceptance/recovery are implemented; preserve existing accepted sources, transcripts, nine diagnostic clips and receipts. Reuse the evidence indexed in STATUS.md rather than repeating those runs.
- Task 3: delivery implementation exists, but production filing and register readback are not established. Historical Drive metadata reported destination access and register edit capability; Sheets operations still fail with HTTP 403 for API enablement in project 145289518259. Actual account-capability evidence is also missing. Neither dependency is resolved by code completion.
- Task 4: installed native application, ordinary Finder launch, native intake/profile setup/duration/output status and optional assistant are verified in the installation receipts. Source identity is HEAD plus the manifest-bound working changes, not HEAD alone. Required end-to-end production delivery/platform evidence remains separate and incomplete.
- Next objective: production setup and the first authorized full-source delivery through the installed app, including Drive filing and required register readback. No social publication. Do not begin it during session closeout.
- Chat readiness: START NEW for that objective. At substantial task starts and milestone transitions, assess CONTINUE versus START NEW using the existing STATUS.md checkpoint; do not create a second tracker or repeat valid acceptance solely because the chat changed.

## COMPLETED — Simplified native SwiftUI interface and final branding

Frank approved this interface on 2026-10-31. This entry extends and consolidates the previously approved visual identity and appearance work in this existing plan. It does not create another roadmap or change REQUIREMENTS.md.

The original approval was recorded as **APPROVED — DEFERRED UNTIL FIRST VERIFIED PRODUCTION DELIVERY**. That prerequisite was satisfied by native job `dub-bc24818564d22380585be027` with 35 verified clips, four companion records and 35 reconciled register rows. Frank subsequently explicitly authorized UI implementation and installation. The simplified native interface and final branding are now installed and verified; see STATUS.md and `ui-branding-20261031/final-verification.json`. No repeat production job was needed.

### Final branding decision — 2026-10-31

The final approved icon replaces every previous icon design: solid black background, bold white text reading exactly “Joey”, flat and minimalist, with no gradients, shadows, play button, clapperboard or additional graphics. Use the supplied `/Users/frank/Downloads/square_app_icon_style_graphic_minimal_and_flat_o.png` artwork, preserving its original and removing the surrounding white image margin for the macOS asset catalog. Ten macOS icon sizes and the in-app brand image are integrated. Finder/Applications verification passed; Frank confirmed the running Dock icon. Preserve the approved purple interface theme, application name Joey and persistent System-default/Light/Dark appearance. This branding decision does not alter media rendering, production rules, settings, job history or bundle identity.

### Approved user experience

1. **New Job:** Paste a YouTube/X link or select a local file.
2. **Selections:** Choose **DUB** or **Taxstone**, and **Full Show** (default) or **Highlights**.
3. **Start Processing:** Provide one primary action.
4. **Processing:** Show a progress bar, the current stage, and completed/total clips.
5. **Results:** Show completion status, clip count, and buttons to open clips or view the report.

### Approved interface and identity principles

- Keep the native interface clean, intuitive and minimal.
- Application name: **Joey**.
- Use the final black-and-white Joey application icon specified above and retain the approved purple interface theme. The final icon supersedes the earlier purple clapperboard; do not restore that retired design.
- Support **System** (default), **Light**, and **Dark** appearance, with a persistent preference across launches.
- Centralize SwiftUI colors and retain native macOS accessibility, including readable contrast, accessible control states and meaningful labels.
- Keep advanced settings and technical diagnostics collapsed by default.
- Automatically determine supported processing settings from verified source information and the existing approved production contract. Do not fabricate account capabilities, guess essential missing inputs, or silently waive production requirements.
- Display meaningful errors and appropriate recovery actions when necessary.
- Base progress on actual completed work. Use an indeterminate progress indicator where the backend cannot substantiate a percentage; distinguish clip processing from filing and reconciliation. Never fabricate progress or show premature completion.
- Preserve all existing production safeguards and backend functionality, including source authority and ownership separation, required transcripts, QA and coverage checks, verified Drive filing, register readback, duplicate prevention, cancellation/resume, and optional user-initiated assistance.

### Implementation boundary and acceptance

After the verified delivery milestone, simplify the existing SwiftUI views in the current Xcode application. Do not rebuild the application from scratch, replace the checkout, or change its processing architecture. Reuse the current coordinator, durable job state, production settings and working UI patterns. Preserve accepted media, jobs, evidence, credentials, the installed build and rollbacks; appearance work is not a production prerequisite.

Verify the approved intake, selection, processing and results flows; real-state progress and recovery presentation; persisted System/Light/Dark behavior; and focused native accessibility. Run only checks affected by the actual UI changes. Do not rerender accepted media or repeat unchanged production acceptance to validate cosmetic work. Keep implementation progress in STATUS.md.

## IMPLEMENTED AND INSTALLED — Taxstone Library Mode; initial deliveries verified

Frank approved this feature on 2026-10-31. Record and preserve the scope in this existing roadmap; do not create a separate planning system or change REQUIREMENTS.md. First-production-delivery work takes priority. Do not implement this feature before that delivery is verified unless Frank explicitly changes the priority.

The first-delivery prerequisite is already satisfied by native job `dub-bc24818564d22380585be027`, completed on 2026-10-31 with independent Drive/register readback documented in STATUS.md. Frank subsequently authorized implementation, installation, and real-media acceptance of this feature. Current progress and verified results are maintained in STATUS.md.

Installed execution now uses a persistent native inventory/queue, the existing coordinator and delivery contract, source/interval/hash reconciliation, owner-specific export evidence, actual-byte legacy QA, partial-work reuse, episode-level continuation, and the minimal Taxstone Library view. Two real episodes have verified delivery; processing continues. Native UI button acceptance remains pending desktop access. Exact counts, tests, operational limits and next action are recorded only in STATUS.md.

### Objective

Create a single-start, resumable workflow that processes the authorized Taxstone audio library into the maximum number of unique, compliant, useful clips while preserving complete eligible episode coverage.

### Approved requirements

1. Discover and inventory existing Taxstone full-length audio, transcripts, clips, manifests, and Drive records.
2. Reconcile previously completed and partially completed episodes before creating work.
3. Identify missing source coverage using stable source identities and exact source intervals, not filenames alone.
4. Organize eligible episodes into one persistent, prioritized processing queue.
5. Use the existing Taxstone audio processing pipeline, approved episode artwork, and source-driven waveform.
6. Produce exactly one shared MP4 per clip for X and Instagram under the verified common production limits.
7. Maximize unique retained-content coverage without unnecessary fragmentation, duplicate clips, omitted content, or repeated speech.
8. Automatically perform QA, Drive filing, companion-record reconciliation, and required verification.
9. Persist progress after each stage and support safe pause, cancellation, restart, and recovery.
10. Reconcile existing outputs before retries or resumed uploads. Never overwrite accepted work unnecessarily.
11. Continue independent episodes when an individual episode is blocked.
12. Provide a minimal interface with Start/Resume, Pause, overall progress, current episode, and expandable details.
13. Require no permanent background service, 24/7 operation, cloud processing service, automatic scheduling, or social publishing.

### Architecture and preservation

Reuse Joey's existing native SwiftUI application, processing coordinator, media engine, checkpoints, delivery infrastructure, and established Taxstone Drive destinations. Do not introduce a parallel clipping system, duplicate database, or separate delivery contract. Maintain durable episode-level and library-level processing state through the existing persistence architecture.

Preserve accepted work and the distinction between authorized eligible sources, completed coverage, incomplete coverage, and blocked episodes. Keep Taxstone identities and records separate from DUB. Maximize useful unique clips subject to complete eligible coverage and compliant natural segmentation; clip-count optimization must not introduce unnecessary fragmentation or repeated speech. Existing production safeguards, current verified common limits, source-bound transcripts, episode-matched artwork, waveform checks, exact interval reconciliation and provider readback remain applicable.

### Observable completion criteria

The durable inventory and queue must account for every eligible episode and its exact required source coverage. Previously accepted compatible work must be reconciled and reused; only missing or demonstrably invalid work is processed. Each completed episode must satisfy the existing QA, Drive integrity/placement, companion-record and applicable register-verification contract, with no duplicate output or repeated coverage. A library recap must distinguish completed, remaining, paused/cancelled and blocked work without declaring incomplete coverage complete. Recovery must retain accepted stages, reconcile uncertain uploads and continue independent eligible episodes without requiring permanent background operation.

Keep implementation progress in STATUS.md and this existing plan. Recording this approval does not alter requirements, establish redistribution rights for undiscovered sources, or authorize social publication.

## Global constraints
One shared MP4, exact interval coverage, no native-video additions, no human QA state, no public permission change, no production media/models/credentials in Git. Full-show default target is 600 seconds; the installed native interface supports an 8/9/10-minute preference with natural boundaries and recorded duration exceptions; lower verified shared limits take precedence. Taxstone art region 900x900 at (90,120), waveform 900x180 at (90,1400), scaled proportionally. DUB uses its own approved reference. No destructive cleanup. Cancellation and restart preserve accepted files.

## Review focus
- Fractional intervals, adjacent exclusions and tiny remainders cannot lose/duplicate content.
- Stale or unrelated capability/transcript/artwork evidence must not authorize a job.
- Crashes between provider write and local checkpoint must not duplicate objects/rows.
- Malformed media/process failures must preserve prior acceptance and exact stage/error.
- Paths, arbitrary titles, remote redirects and concurrent starts must not escape owned storage or invoke shell commands.

## Task 1: Core contracts and recovery
Files: Joey/Core/Domain.swift, Planning.swift, Persistence.swift; Tests/JoeyCoreTests.
Write failing tests for hour-to-six, short/remainder/exclusion/platform cases, fixed interval conflict, invalid evidence, source hashes and durable reuse. Implement typed Codable request/source/profile/transcript/job records, interval algebra, transcript-grounded planning, atomic persistence and exclusive processing locks. Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` and record direct status/counts.

## Task 2: Media pipeline
Files: Joey/Core/Processes.swift, Media.swift, AudioPresentation.swift, Acquisition.swift.
Test real FFmpeg fixture renders/decoding, corruption rejection, source-only proportional framing, audio waveform response and cancellation. Use local originals or supported resumable yt-dlp acquisition with direct original provenance; hash/probe/decode and content classification. Reuse source-bound local ASR. Assemble exact retained intervals. Native rendering is black-padded source only. Audio uses approved artwork and source-derived fixed bars; compare resulting PCM/picture/layout against expected material. Keep disk/concurrency bounded and reuse accepted stages.

## Task 3: Verified delivery
Files: Joey/Core/Delivery.swift, Records.swift, Coordinator.swift.
Test local state transitions and idempotent recovery with HTTP/provider boundaries where live mutation is inappropriate. Use existing rclone to exact Drive root IDs, list/reconcile before copy, independent metadata/checksum/access readback. Reuse source-job folder, maintain one canonical index, full transcript, manifest and reconciliation. Write only supported current DUB register columns with row identity/readback; Taxstone stays separate. Keep QA_PASSED on filing failure.

## Task 4: Native operation and acceptance
Files: Joey/ContentView.swift, Joey/MyApp.swift, Joey/JobModel.swift, Tools/JoeyRunner; existing project settings.
Expose intake, setup dependencies, progress, cancel/resume, recap and local/Drive links. No Codex/GitHub/cloud runtime calls. Build using existing Xcode project. Run unit/integration suite, standalone fixture jobs and real authorized source jobs. Verify reopen/recovery and provider integrity separately. Document exact unavailable dependencies rather than substituting synthetic proof. Request one independent whole-change review, repair material findings, update STATUS with commands/counts/links and remaining gaps.


## Link-only intake and Joe Budden background processing — INSTALLED AND VERIFIED 2026-10-31

Continue the existing SwiftUI application and coordinator. Deliver Paste Link, Workflow labels, mandatory full-original filing before clips, automatic one-highlight-per-15-minute-block planning, official numbered Joe Budden YouTube discovery, and opt-in durable Start/Resume/Pause automation while the app is running. The Joe-specific Drive-only 8–10-minute source-content workflow includes the approved lower-left DUB logo and full outro, per Frank's later explicit correction; other DUB/Taxstone shared exports retain their verified limits. Reuse existing job identities, transcript requirements, QA, Drive receipts and records. Do not implement Taxstone Library Mode as part of this item. Installation, focused verification and exact remaining limits are tracked in STATUS.md.

Saved implementation readback: native build/signature, focused tests, official Episode 976 discovery, Start/Pause/restart persistence and preservation verified; details and limitations in STATUS.md. Automation remains paused at activation baseline 976. No new real episode or provider write was performed during verification.


## Storage Manager — IMPLEMENTED AND INSTALLED 2026-11-01

Extend the existing Swift coordinator, supervised workers, persistence and Settings. Add explicit attempt ownership/lifecycle receipts, canonical containment and no-follow deletion, worker exclusion, measured cleanup accounting, automatic cleanup preference (default enabled), and always-on workflow-aware disk admission/monitoring. Preserve uncertain historical scratch and all originals, accepted outputs, transcripts, manifests, indexes, receipts, settings, models and rollbacks. Add minimal storage metrics and Clean Now using the same rules. Test classification, interrupted recovery, protected data, traversal/symlinks, concurrent workers, low-capacity blocking/recovery and measured deletion in isolated directories. Install through a controlled checkpointed restart with rollback, verify Taxstone and Joe recovery and accepted file identities, and record precise results in STATUS. No general Mac or cloud cleanup is included.

Storage Manager closeout: implemented in the existing coordinator, workers and Settings; final 13/13 storage tests and native build/signature passed. Installed with rollback and native pause/restart/resume. Preserved 83 accepted MP4 identities and the 80 original protected baseline hashes. Taxstone resumed unchanged accepted media, completed its fifth episode and advanced to the next source; Joe remained enabled at baseline 976. Production reclaim count was zero at closeout because historical scratch lacks lifecycle receipts and the next source was transcribing. Details, measured bytes, focused regression history and limitations are recorded in STATUS and STORAGE.

## Swiss UI redesign — authorized 2026-10-31

Goal: implement Frank's approved minimal Swiss/Helvetica three-pane native interface in the existing checkout. The current explicit request authorizes implementation. The referenced Swiss UI Mockup chat confirms approval, labeled Process/Jobs/Shows navigation, Ready status, minimal intake and recent jobs, and a persistent inspector. Retrieved image attachments establish proportions and palette; the last label correction is authoritative.

Scope: extend ContentView, JoeyTheme, NewJobView and read-only JobPresentation; retain existing JobModel actions, media engine, automation, preferences and recovery. Settings and the assistant remain reachable without occupying primary navigation. No requirements edits, installation, production jobs, provider writes, publication, dependencies, or repository replacement.

Implementation:
- [x] Add presentation tests for evidence-backed stages, QA progress versus delivery completion, failed/cancelled work and absent transcripts. Extend existing JobPresentation only where needed.
- [x] Implement neutral Helvetica chrome with labeled sidebar, link drop/import surface, selectable recent jobs and persistent selected-job inspector. Reuse link-only intake from REQUIREMENTS section 20; dropped links prefill intake and never start jobs by themselves. Keep optional controls in sheets/Shows.
- [x] Show local source/accepted-output preview, actual stage, QA counts, verified delivery/record counts, metadata and results. Unknown progress remains indeterminate only while running. Never invent ETA, global percent, thumbnails or waveform data. Audio previews use actual rendered output; native video receives no waveform decoration.
- [x] Build native target and run meaningful presentation/core regression tests through Tools/run-local.py. Inspect native layout using isolated fixture data without resuming production. Record exact outcomes in STATUS.

Acceptance: persistent three-pane layout; labeled keyboard-accessible controls; selection preserved during background updates; no fake job data in product; measured progress and delivery states remain distinct; current requirements and pre-existing work preserved; build/test results recorded. Completion covers UI implementation/verification, not installation or fresh production/platform acceptance.

Risks/dependencies: checkout has substantial existing uncommitted work; preserve pre-edit copies/hashes in the task cache. Existing installed app may be processing; do not launch the candidate against production storage. UI fixture verification must not imply production evidence. Existing models and durable job records supply all business data.

Swiss UI closeout: implementation, native build, 82 passing/3 skipped XCTest cases, 5 environment tests, independent scoped review and isolated native UI checks are recorded in STATUS. The installed app was not replaced.

Swiss UI installation follow-up (2026-10-31): Frank authorized applying the built changes. Installed and verified at ~/Applications/Joey Native.app, with rollback, preservation of 111 accepted outputs, live UI readback and saved-queue recovery. STATUS contains the exact receipt and scope.
## IMPLEMENTED, TESTED, INSTALLED AND VERIFIED — Clip Intelligence and GPT Buffer Handoff

Frank's consolidated 2026-10-31 directive is implemented in the existing Swift application. Completed jobs, transcript/QA/Drive evidence, local persistence and locks are reused. Native recommendations, strict media/anonymous URL preflight, Ready for Buffer, episode actions, `joey-buffer-v1` export, default five-operation sub-batches, account/presentation/mode checks, durable reservations, evidence renewal and validated GPT-mediated receipts are installed. Final tests: 115 passed, 3 intentional skips, zero failures; native build/signature and genuine accepted-media handoff passed. Controlled installation preserved 118 accepted MP4s and resumed Taxstone; Joe remains enabled at baseline 976 with 30-minute checks. No social write or ingestion acceptance was performed. Queue/scheduling still requires retrieval-longevity evidence; Instagram requires an explicit supported presentation choice. Exact commands, package identity, preservation proof and boundaries are in STATUS.md and BUFFER_HANDOFF.md. REQUIREMENTS remains unchanged.
