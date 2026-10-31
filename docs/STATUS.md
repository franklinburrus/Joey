# Joey native implementation checkpoint

## Mission
Implement and verify docs/REQUIREMENTS.md in the existing SwiftUI/Xcode application. This is the single current specification. Preserve the original Python checkouts, historical evidence, source archives, and user Xcode changes. No social publication, email, TikTok, duplicated platform exports, paid services, or routine human QA.

## Repository reconciliation — verified
Frank explicitly approved connecting the native checkout and preserving both histories. `/Users/frank/Documents/Joey` is now on `codex/native-consolidated` with origin `https://github.com/franklinburrus/Joey.git`. Both `bc34efbf88b95c726da3fe8e1eb3dcb69120bb3c` (native starter) and `f265a5ad2c44b933d6da4aafc752c9c6c8646a83` (current remote) are ancestors. Original uncommitted project/scheme hashes and all Caveman provenance hashes were verified after the merge. No push occurred.

## Plan and acceptance
Follow IMPLEMENTATION_PLAN.md. Completion requires section 18 of REQUIREMENTS: native build and meaningful tests, real native/DUB audio/Taxstone audio jobs, exact coverage cases, corruption rejection, restart/idempotence, verified Drive records and required register readback. A starter build or synthetic test suite alone cannot establish this.

## Current evidence
Baseline Xcode 27.2 build returned direct exit 0. No tests existed. Details and preserved files: `/Users/frank/Library/Caches/Joey-Native-Build/implementation-preflight.md` and its `preservation/` sibling. Runtime work belongs outside synchronized Documents/Drive, under Application Support. About 13 GiB disk free at preflight; bound scratch usage and reuse originals. Both authoritative Joey Drive roots exist and are empty; current permission metadata includes anyone:reader, preserved unchanged. Media/account capability/registry credentials still require live verification.

## Decisions
Use Swift for the UI, durable coordinator, planning, media validation and provider orchestration. Reuse installed FFmpeg/FFprobe, yt-dlp, rclone and local transcription where available. No new services or package dependencies. Native runtime data is separate from historical Python runtime data. Processing runs off the main actor, one job at a time with cross-process locking. Failed dependencies are exact operational errors, never human QA states.

## Progress
- [x] Reconcile native checkout and verify preservation.
- [x] Save exact current requirements.
- [x] Implement/test core identity, interval coverage, profiles and durable local recovery.
- [x] Implement/test local transcription, audio/video rendering and QA; acquisition adapter implemented.
- [x] Implement Drive filing, companion records and register readback; live delivery acceptance remains blocked below.
- [x] Wire responsive native UI and standalone runner; build and test.
- [x] Run independent review and local real-media verification; report exact gaps.
- [ ] Complete production-profile and provider end-to-end acceptance.

## Implementation checkpoint — 2026-10-30, 22:18 EDT

Native core, UI and standalone runner implemented. Unit/integration suite at `review-fixes-test3.log` returned direct exit 0: 21 tests, 21 passed, 0 failed/errors/skipped. Xcode native build at `native-build2.log` returned direct exit 0. Compatible AVAssetWriter APIs emit macOS 27 deprecation warnings; this is not a zero-warning claim. Initial native build failed for a missing CoreGraphics import, repaired. An async Foundation `waitUntilExit()` deadlock was captured in `test-hang.sample.txt`; the exact test process was terminated and the runner repaired. Earlier failed runs remain recorded in the same evidence directory.

Independent review identified six material issues. Current fixes cover source-driven waveform pixels, native orphan/descendant supervision and attempt fencing, recoverable Drive folder-create intent, non-premature provider finalization states, DUB pinned asset enforcement and strict platform hard limits. Follow-up independent review is running. Native Xcode build and shared Swift test target use the same core sources.

Production runtime root: `~/Library/Application Support/Joey Native`, separate from historical Python Joey. Bundled ASR adapter removes the runtime dependency on Codex package files; hash-verified artwork is copied into owned storage. Native helper supervisor handles subprocess group cleanup on parent loss; unique attempt directories prevent stale writes from corrupting a retry.

Read-only standalone provider preflight: `./.build/debug/joey-run check-drive --root '/Users/frank/Library/Application Support/Joey Native'` returned direct exit 1. Drive metadata/list operations succeeded. Google Sheets returned HTTP 403: `Google Sheets API has not been used in project 145289518259 before or it is disabled.` The default rclone OAuth client cannot currently reconcile the Master Link List through Sheets. Do not bypass by claiming a CSV is a register write or requiring Codex as production operator. An existing authorized Sheets-enabled OAuth connection is the unresolved dependency. No provider writes or media uploads have occurred.

The intended X account and Instagram account/upload surface remain pending in an asynchronous question to Frank. Official X help was checked, but account eligibility and Instagram upload-surface limits are not established. No production verified profile is fabricated.

The initial real-media test subsequently passed. It exercises original DUB native video, DUB audio and matching Taxstone episode art. It deliberately records isolated renderer verification using fixture technical limits, not account eligibility, production job completion or provider delivery. Media and evidence remain outside Git.

## Latest checkpoint — 2026-10-30, 22:35 EDT

Status: PARTIAL — native implementation and local verification finished; production delivery acceptance is not established. Full evidence and exact commands are in VERIFICATION.md.

- Final shared-core suite: direct exit 0, 24 discovered/executed, 24 passed, 0 failures/errors/skips, 22.522 seconds. Three real-source renderer cases passed using explicit fixture limits; accepted media was reused.
- Final current-source Xcode build: direct exit 0. Installed `/Users/frank/Applications/Joey Native.app`, byte-for-byte matching the built bundle. Strict code-signature verification returned exit 0. Historical `/Users/frank/Applications/Joey.app` remained unchanged.
- Real local DUB audio workflow: 57.301333-second source, 20 transcript segments, one 57.333008-second MP4, 3,937,868 bytes, all local checks passed. Initial run and current-runner reopen returned exit 0 and `QA_PASSED`; accepted output hash and QA timestamp stayed unchanged. No delivery claim.
- Independent review fixes are complete. Final recovery regression first failed with direct exit 1, then passed in the final suite: explicit cancellation retains accepted clip QA but does not auto-resume; `FILED` checkpoints resume companion/register work. Successful-attempt scratch cleanup preserves the output and retained evidence.
- Provider GET requests now retry transient HTTP/network failures up to three attempts. A mocked HTTP integration test proves retry recovery and that uncertain POST mutations return to their reconciliation owner without automatic replay. The sole configured rclone remote is `dubdrive`; no alternative existing connection was available for the Sheets 403.
- Native UI was inspected earlier in this session. The final installed build's UI could not be re-inspected because the computer-use tool reported the Mac locked. Installation, signature, CLI and tests did not depend on GUI access. Sleep/wake remains untested.

Remaining dependencies: actual X account and Instagram upload surface/capability evidence; an authorized Sheets-enabled OAuth connection for the existing DUB register (current connection returns HTTP 403). No production upload or register mutation occurred. Provider idempotence, completed-job reopen and full delivery remain unverified until those dependencies support an authorized real job. Do not substitute fixture profiles into production configuration.

Next action: supply/verify actual account capability evidence and the Sheets-enabled connection, then run the three production acceptance workflows and verify Drive/register readback. No new design or human media QA approval is required.
