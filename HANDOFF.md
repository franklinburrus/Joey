# HANDOFF — Joey PR #19 integrity/security repairs

Updated: 2026-11-08 20:18 America/New_York after verified macOS CI success.

## Branch / PR

- Branch: `cursor/integrity-security-repairs-79c7`
- Head: `7ae1a678b54ae145bdd2d6825ca0845944b0789b`
- Base: `main` @ `1e6092c7fe6de85d405fa53bb93c9ab16854b624`
- Draft PR: https://github.com/franklinburrus/Joey/pull/19
- Status: **draft** — do not merge
- Verified Actions run: https://github.com/franklinburrus/Joey/actions/runs/42543479929

## Repair commit inventory (verified present in `origin/main...HEAD`)

| # | Repair | Evidence |
|---|---|---|
| 1 | Companion stage/replace | `Delivery.replaceCompanionTransactionally` |
| 2 | Drive SHA-256 / readback verify | `Delivery.verify` + `readRemoteBytes` |
| 3 | Artwork temp promote | `Delivery.downloadArtwork` |
| 4 | Helper diagnostic sanitization | `Processes.sanitizeDiagnostic` |
| 5 | Mail Python boundary | `Processes.credentialPython` |
| 6 | Capacity-wait lock ownership | `Coordinator.run` holds `ProcessingLock` |
| 7 | Drive-gated scratch cleanup | `StorageManager.accepted` requires `clip.drive` or completed |
| 8 | Archive SHA preference | `archive` / `downloadOriginal` SHA-256 paths |
| 9 | Corrupt checkpoint isolation | `Coordinator.isolateCheckpointFailures` |
| 10 | Email admission scaffold | `job.stage = "admitted"` early save |
| 11 | Stable accepted-plan hash | early `acceptedPlanSHA256 = nil` removed from clip loop |
| 12 | Cancel pauses library/Joe | `JobModel.cancel` |
| 13 | Shell + credential stdin refused | `Processes.run` + `refuseShellHelper` |
| 14 | Cleanup warnings surfaced | Coordinator storage warning paths |
| 15 | Parent-dir fsync | `Persistence.save` |
| 16 | Selection not stolen by progress | `JobModel.receive(select:)` |
| 17 | Regression tests added | `IntegritySecurityRepairTests` + updated suites |

All 17 confirmed in the current PR diff.

## Verified macOS CI (`7ae1a67`, run `42543479929`)

Runner: GitHub Actions `macos-latest` (`macos-26-arm64`). Toolchain: Apple Swift 6.3.3 / Xcode 26.6. Helpers installed on runner: `ffmpeg` 9.0.2, `yt-dlp` 2026.10.26.

| Check | Result |
|---|---|
| Diff inventory of 17 repairs | PASS |
| Linux Actions smoke (Python helpers) | PASS |
| Full Swift package test suite | **PASS** — `Executed 478 tests, with 8 tests skipped and 0 failures` (606.908s) |
| `IntegritySecurityRepairTests` filter | **PASS** — `Executed 6 tests, with 0 failures` (0.017s) |
| Release build | **PASS** — shared scheme `Joey Native` absent on runner; `swift build -c release` completed (`Build complete! (77.63s)`) |

Log extract saved under `/opt/cursor/artifacts/macos-ci-7ae1a67-full.log`.

Local Mac backup remains: `Tools/verify-macos-repairs.sh` (same three checks, timestamped report).

## Remaining blockers / risks

1. **External:** `OPENAI_API_KEY` revocation remains an owner action outside Joey.
2. **Integration (not CI):** Live Drive rename promote is still best-effort rollback, not provider-atomic.
3. **Integration (by design):** Scratch retention until Drive filing increases local disk use.
4. **Integration:** Native Xcode shared-scheme Release (`Joey Native`) was not exercised on CI; package Release build did pass. Confirm on Frank’s Mac if the shared scheme must be part of ship gate.
5. **Integration:** Approved local Joe assets / real-media / live OAuth paths remain opt-in and were skipped or unused in CI (8 suite skips include Joe-asset hosts).

## Next required action

Keep PR #19 draft. Owner review of repair semantics + optional OPENAI revocation. Do not merge or deploy from this agent. No production Drive/media destruction from this PR.
