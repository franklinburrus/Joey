# HANDOFF — Joey PR #19 integrity/security repairs

**Current status (post-merge):** [PR #19](https://github.com/franklinburrus/Joey/pull/19) is **merged** on `main`. Do not re-merge. Next milestone is native Mac acceptance — see [`docs/MAC_ACCEPTANCE_HANDOFF.md`](docs/MAC_ACCEPTANCE_HANDOFF.md) and run `./Tools/verify-macos-acceptance.sh` on macOS. Target wording when green: `MAC ACCEPTANCE PASSED — AWAITING DEPLOYMENT APPROVAL`. Do not deploy from the agent. Sections below keep historical repair evidence from before merge.

Updated: 2026-11-08 20:25 America/New_York (final evidence consolidation).

## Branch / PR

- Repository: https://github.com/franklinburrus/Joey
- Branch: `cursor/integrity-security-repairs-79c7`
- Base: `main` @ `1e6092c7fe6de85d405fa53bb93c9ab16854b624`
- PR: https://github.com/franklinburrus/Joey/pull/19 — **merged** (historical draft/do-not-merge notes below are superseded by the top status)
- Head SHA: branch tip of `cursor/integrity-security-repairs-79c7` (exact value in CI matrix after tip verification)
- Workflow: `.github/workflows/macos-verify.yml` (`macos-latest`)
- Local Mac backup (PR #19 repair gate): `Tools/verify-macos-repairs.sh`
- Native Mac acceptance (post-merge): `Tools/verify-macos-acceptance.sh` + `docs/MAC_ACCEPTANCE_HANDOFF.md`

## A. Repair Evidence Matrix

| Finding | Severity | Repair Commit | Regression Evidence | macOS Result | Status |
|---|---|---|---|---|---|
| Companion replacement | P1 | `bc65f27` (`Delivery.replaceCompanionTransactionally`; Drive renames documented non-atomic; rollback best-effort) | `DriveFilingTests.testCompanionReplacementPreservesPreviousUntilPromotionVerifies`, `testCompanionIsPlacedBesideClipsAndDownloadedForByteReadback` | Covered by full suite PASS | VERIFIED |
| Drive SHA-256/readback | P1 | `bc65f27` (`Delivery.verify` + `readRemoteBytes`; BufferPreflight requires SHA) | `DriveFilingTests` post-upload/readback cases; `BufferPreflightTests.testDriveReadbackRejectsWrongOwnerFolderHashDuplicatesAndAccessChanges` | Covered by full suite PASS | VERIFIED |
| Artwork integrity | P1 | `bc65f27` (`Delivery.downloadArtwork` temp→verify→promote) | Artwork path covered via Drive/delivery suite + production promote path | Covered by full suite PASS | VERIFIED |
| Diagnostic sanitization | P1 | `f9d07b2` + `ce821cb` (`Processes.sanitizeDiagnostic`, synthetic `JOEY_DUMMY_` patterns) | `IntegritySecurityRepairTests.testSanitizeDiagnosticRedactsSyntheticSecretsAndKeepsExitCode` | Filter + full suite PASS | VERIFIED |
| Mail credential isolation | P1 | `f9d07b2` (`Processes.credentialPython`; `MailCredentials` uses it) | `IntegritySecurityRepairTests.testCredentialPythonRejectsRelativeShellAndSystemInterpreters`; `RuntimeTests.testCredentialPythonRejectsShellAndUnownedInterpreters` | Filter + full suite PASS | VERIFIED |
| Capacity-wait locking | P1 | `5403266` (Coordinator holds `ProcessingLock` across capacity wait) | `IntegritySecurityRepairTests.testCapacityWaitCleanupUsesHeldLockWithoutCompetingExclusiveOpen`; `StorageTests` capacity/recovery cases | Filter + full suite PASS | VERIFIED |
| Scratch retention | P2 | `79f3801` (`StorageManager.accepted` requires `clip.drive` or completed); `docs/STORAGE.md` | `StorageTests.testAcceptedScratchWithoutDriveReceiptIsRetained`; Media/Workflow expectations aligned in `7ae1a67` | Full suite PASS | VERIFIED |
| Original archive integrity | P2 | `bc65f27` / `79f3801` (archive/download SHA-256 preference) | `DriveFilingTests` archive routing + verify paths | Full suite PASS | VERIFIED |
| Checkpoint isolation | P2 | `5403266` (`Coordinator.isolateCheckpointFailures`); test fix `8f62207` | `JobInventoryTests.testIsolatingCorruptCheckpointsPreservesBytesAndUnblocksIntake` | Full suite PASS | VERIFIED |
| Email admission durability | P2 | `5403266` (early `job.stage = "admitted"` save) | `EmailModelTests.testEmailAdmissionReconcilesCheckpointCreatedDuringDiscoveryBeforeFreezing`, `testFrozenRequestEntersRealCoordinatorWithoutRediscoveryAfterCrash` | Full suite PASS | VERIFIED |
| Accepted-plan hash preservation | P2 | `5403266` (stable `acceptedPlanSHA256` binding) | Coordinator plan-hash path + suite coverage | Full suite PASS | VERIFIED |
| Cancellation handling | P2 | `ec06467` (`JobModel.cancel` pauses Joe/library); expectation align `ce821cb` | `EmailModelTests.testCancelDuringInterleavedEmailPausesJoeAndLibraryAndCancelsProcessing` | Full suite PASS | VERIFIED |
| Executable restrictions | P2 | `f9d07b2` (`refuseShellHelper` + credential stdin refusal) | `IntegritySecurityRepairTests.testShellHelperCannotReceiveCredentialStdin` | Filter + full suite PASS | VERIFIED |
| Cleanup error visibility | P3 | `5403266` (`storageWarnings` surfaces) | Coordinator warning paths exercised in Media/Storage suites | Full suite PASS | VERIFIED |
| Parent-directory fsync | P3 | `ec06467` (`Persistence.save` parent `fsync`) | `IntegritySecurityRepairTests.testParentDirectoryFsyncPathStillRoundTripsCheckpoint` | Filter + full suite PASS | VERIFIED |
| UI selection stability | P3 | `ec06467` (`JobModel.receive(select:)`) | `IntegritySecurityRepairTests.testReceiveProgressDoesNotStealForeignSelection` | Filter + full suite PASS | VERIFIED |
| OpenAI credential revocation | P0 external | N/A | `docs/CREDENTIAL_INCIDENT.md` — owner provider confirmation required | N/A | BLOCKED |

Product-code verification baseline: Actions run https://github.com/franklinburrus/Joey/actions/runs/42543479929 on `7ae1a678b54ae145bdd2d6825ca0845944b0789b` (478 tests / 8 skipped / 0 failures; IntegritySecurityRepairTests 6 / 0; `swift build -c release` Build complete 77.63s). Later tip commits are documentation/evidence only relative to that product tree unless noted.

## B. CI Verification Matrix

| Requirement | Acceptance Standard | Actual Result | Evidence |
|---|---|---|---|
| Branch HEAD | Exact SHA recorded | Filled after tip macOS CI concludes | PR #19 head + Actions run for that SHA |
| macOS CI | All required checks successful on exact HEAD | Must PASS on tip (`Linux Actions smoke` + `Swift tests and Release build`) | Actions runs for this branch; product baseline `42543479929` |
| Full Swift suite | Zero failures | PASS on `7ae1a67`: 478 executed, 8 skipped, 0 failures (606.908s) | `/opt/cursor/artifacts/macos-ci-7ae1a67-full.log`; run `42543479929` |
| IntegritySecurityRepairTests | Zero failures | PASS on `7ae1a67`: 6 executed, 0 failures (0.017s) | Same run, job step `IntegritySecurityRepairTests` |
| Release build | BUILD SUCCEEDED | PASS on `7ae1a67`: shared scheme `Joey Native` absent; `swift build -c release` → `Build complete! (77.63s)` | Same run, job step `Release build` |
| Security review | No unresolved P0/P1 code defects in authorized scope | PASS — final diff scan of repair files found only sanitizer patterns for secret redaction; no live credential material added | `git diff origin/main...HEAD` review this session |
| Media integrity | Required checks pass | PASS within suite (Drive/Buffer/Storage/Media paths) | Full suite log |
| Concurrency | Required checks pass | PASS (lock/capacity/cancel/isolation tests) | IntegritySecurity + Storage + EmailModel |
| Final diff review | Completed | PASS for authorized scope; residual risks listed below | PR #19 diff vs `main` |
| Production integration | Not authorized | NOT RUN | Authorization boundary |
| Credential revocation | Owner confirmation required | BLOCKED / pending | `docs/CREDENTIAL_INCIDENT.md` |
| PR merge | Not authorized | NOT MERGED; remains draft | https://github.com/franklinburrus/Joey/pull/19 |

Toolchain on verified runner: Apple Swift 6.3.3, Xcode 26.6, `macos-26-arm64`, `ffmpeg` 9.0.2, `yt-dlp` 2026.10.26.

## Residual risks (authorized code still carries these)

1. Drive companion promote uses rename sequencing; rollback is best-effort (`try?`), **not** provider-atomic. Documented in `Delivery.swift`.
2. Scratch retained until Drive filing or completed state — higher local disk use; low-disk capacity wait still lock-owned.
3. CI Release used SwiftPM `-c release`, not Xcode shared scheme `Joey Native`.
4. Eight suite skips include missing approved Joe assets on the runner; live OAuth/Drive/real-media not in CI.
5. External `OPENAI_API_KEY` revocation remains owner-side (BLOCKED). Code prevention boundaries exist; incident is not closed.

## Required physical Mac acceptance (owner)

1. Optional: `./Tools/verify-macos-repairs.sh` including Xcode scheme `Joey Native` Release if present.
2. Optional nonproduction Drive smoke of companion replace/readback — not authorized for this agent against production.
3. Owner revoke/confirm `OPENAI_API_KEY` per `docs/CREDENTIAL_INCIDENT.md`.

## Next owner decision

PR #19 is merged. Run native Mac acceptance per `docs/MAC_ACCEPTANCE_HANDOFF.md` / `Tools/verify-macos-acceptance.sh`. Do not deploy from the agent. No production Drive/media destruction occurred. (Historical pre-merge text retained in evidence matrix above.)
