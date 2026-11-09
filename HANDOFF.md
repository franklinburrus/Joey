# HANDOFF — Joey PR #19 integrity/security repairs

Updated: 2026-11-08 (America/New_York) during verification/stabilization.

## Branch / PR

- Branch: `cursor/integrity-security-repairs-79c7`
- Head: `ec064679149f251dbf9285dde47584dfcf0b1b96`
- Base: `main` @ `1e6092c7fe6de85d405fa53bb93c9ab16854b624`
- Draft PR: https://github.com/franklinburrus/Joey/pull/19
- Status: **draft** — do not merge

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

## Verification executed in this environment

| Check | Result |
|---|---|
| PR diff inventory of 17 repairs | PASS |
| GitHub Actions workflow list | `total_count: 0` (no prior workflows) |
| Actions permissions / runners APIs | **403** — cannot enable or inspect runners via this token |
| `swift` / `xcodebuild` on agent host | **Absent** (Linux Ubuntu) |
| Full Swift test suite | **NOT RUN** — external macOS blocker |
| `IntegritySecurityRepairTests` | **NOT RUN** — external macOS blocker |
| Release build | **NOT RUN** — external macOS blocker |
| Linux Python unittest (non-Swift) | previously OK with 1 xctest skip; not claimed as Swift compilation |

## Artifacts added for macOS verification

1. `.github/workflows/macos-verify.yml` — minimal `macos-14` workflow (full `swift test`, filter, Release/`swift build -c release`). May not execute until Actions is enabled for the repo.
2. `Tools/verify-macos-repairs.sh` — single local Mac script that runs all three checks, records exit codes, and writes `verification-reports/macos-verify-<UTC>.txt`.

## Remaining blockers

1. **External:** macOS Swift compilation/tests/Release build have not passed on this PR head.
2. **External:** GitHub Actions macOS execution is not confirmed available (empty workflow catalog; permissions APIs 403).
3. **External:** `OPENAI_API_KEY` revocation remains an owner action outside Joey.

## Next required action

On Frank’s Mac:

```bash
cd /path/to/Joey
git fetch origin
git checkout cursor/integrity-security-repairs-79c7
chmod +x Tools/verify-macos-repairs.sh
./Tools/verify-macos-repairs.sh
```

Paste/report the generated `verification-reports/macos-verify-*.txt` summary. Merge remains blocked until that report shows `result=PASS`.

Optional: enable GitHub Actions for `franklinburrus/Joey` so `.github/workflows/macos-verify.yml` can run on the draft PR.
