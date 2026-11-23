# Mac acceptance handoff — post PR #19

**Status:** Prepared on Linux for execution on macOS.  
**Merged:** [PR #19](https://github.com/franklinburrus/Joey/pull/19) — *Repair Drive integrity, credential hygiene, and storage concurrency* (do not re-merge).  
**Milestone to record when green:** `MAC ACCEPTANCE PASSED — AWAITING DEPLOYMENT APPROVAL`  
**Deployment:** not authorized from this handoff. No production install/Drive mutation unless Frank separately authorizes.

## Why Linux cannot finish this

Cloud/Linux agents cannot run native Xcode Release, launch the macOS app, or exercise real FFmpeg/helper paths the same way as Frank’s Mac. They prepare scripts and this handoff only. **No further product code repairs** unless acceptance finds a defect.

## Preconditions (Mac)

1. Clean checkout of `main` at the post-#19 tip (`git fetch origin && git checkout main && git pull --ff-only`).
2. Xcode selected (`xcode-select` / `DEVELOPER_DIR` as you normally use for Joey).
3. Helpers available: `ffmpeg`, `ffprobe`, `yt-dlp` (rclone only if you intentionally smoke Drive later — **out of scope** for this milestone).
4. Run every Joey executable through `python3 Tools/run-local.py`.

## One-command entry

```bash
cd /path/to/Joey
chmod +x Tools/verify-macos-acceptance.sh
./Tools/verify-macos-acceptance.sh
```

Optional env:

| Variable | Meaning |
| --- | --- |
| `JOEY_ACCEPTANCE_OUT_DIR` | Report directory (default: `./verification-reports`) |
| `JOEY_ACCEPTANCE_SKIP_LAUNCH=1` | Skip GUI launch probe |
| `JOEY_ACCEPTANCE_SKIP_DISPOSABLE=1` | Skip disposable ffmpeg + filtered media tests |

Narrower CI-parity gate (from PR #19): `./Tools/verify-macos-repairs.sh`

## Checklist mapped to script steps

| Required check | How it is covered |
| --- | --- |
| Verify merged code on `main` | Script records `git rev-parse`, requires clean `main` (or `JOEY_ACCEPTANCE_ALLOW_DIRTY=1`) |
| Native Xcode Release build | `xcodebuild` scheme `Joey Native` if present, else scheme `Joey`, else documented SwiftPM Release fallback |
| Complete Swift test suite | `python3 Tools/run-local.py swift test` |
| Joey launches successfully | Brief open of Release product; process must start; then quit |
| Local media with disposable files | Generates short lavfi MP4 under the report dir; runs `MediaTests` + related filters (fixtures are disposable). Optional `joey-run` local-only only if already buildable |
| Low-storage recovery + job locking | `IntegritySecurityRepairTests` + `StorageTests` filters |
| Document results / blockers | Writes `verification-reports/macos-acceptance-*.txt` and a blockers section |

## Manual notes to capture in the report

After the script exits, append (or fill the blockers template):

1. Exact `main` SHA accepted.
2. Whether Release used Xcode scheme or SwiftPM fallback.
3. Launch observation (window appeared / Ready / no crash).
4. Any skipped suite cases (Joe assets, live Drive, etc.).
5. Remaining deployment blockers (typical: `docs/CREDENTIAL_INCIDENT.md` OpenAI key revocation; production install authority; live Drive smoke not run).

## Success gate wording

When all automated steps pass and launch/media/lock checks are acceptable:

> **MAC ACCEPTANCE PASSED — AWAITING DEPLOYMENT APPROVAL**

Then stop. Do not deploy from the agent. Structural repair PRs (Media/Coordinator/JobModel/STATUS/CI/UI) remain deferred until after this milestone unless acceptance exposes a defect.

## Related files

- Plan: Project Context `docs/joey-structural-repair-plan.md` (Mac acceptance section)
- PR #19 HANDOFF: repo `HANDOFF.md` (repair evidence; merge status may still say draft historically — ignore merge instructions there; PR is merged)
- Operating guide: `docs/OPERATING_GUIDE.md` (`--root`, local-only QA)
