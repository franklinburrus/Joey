# Joey Native Implementation Plan

> Execute inline with superpowers:executing-plans; use test-driven development for meaningful behaviors. Track evidence and decisions in STATUS.md. Current user authorization permits implementation and automated acceptance without another design or QA approval.

**Goal:** Implement the standalone local media workflow in REQUIREMENTS.md.
**Architecture:** SwiftUI calls a serial actor coordinator with atomic JSON checkpoints and cross-process locking. Foundation Process invokes installed media tools without a shell; Swift owns planning, state, hashes and provider readback. Existing Xcode folder membership compiles the shared core; Swift Package Manager provides a dependency-free test/runner harness using the same files and Xcode toolchain.
**Tech Stack:** Swift, SwiftUI, Foundation, CryptoKit, AppKit/CoreGraphics, FFmpeg/FFprobe, existing yt-dlp/rclone/local ASR.
**Spec:** REQUIREMENTS.md, sole current requirements document.

## Global constraints
One shared MP4, exact interval coverage, no native-video additions, no human QA state, no public permission change, no production media/models/credentials in Git. Full-show target 600 seconds with natural boundaries between 480 and 600 seconds; lower verified shared limits take precedence. Taxstone art region 900x900 at (90,120), waveform 900x180 at (90,1400), scaled proportionally. DUB uses its own approved reference. No destructive cleanup. Cancellation and restart preserve accepted files.

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
