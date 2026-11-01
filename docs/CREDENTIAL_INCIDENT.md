# Credential exposure and key-free development — 2026-10-31

Credential invalidation is **PENDING**. Overall production acceptance remains **PARTIAL**. Safe development without AI-service credentials can continue independently; invalidation is not a new API-key setup prerequisite. No credential, billing, Cloud, Google Drive/Sheets connection or installed-app change was made. No provider probe, including `/v1/me`, was made. No accepted media was rerendered.

## Identity, custody and required owner action

The exposed variable is `OPENAI_API_KEY`, identifying an OpenAI credential. Its exact value matches an export in `/Users/frank/.zshrc`, line 1, owned by UID 501 (Frank), mode 0644. This establishes user-level shell custody, not the OpenAI project principal or key owner. The credential is not established as development-environment-managed. Codex authentication configuration reports `auth_mode: chatgpt`; its API-key field is null and does not match the exposed value. ChatGPT sign-in remains the authorized Codex authentication method.

An owner/revocation request is pending with Frank. If Frank owns the key, he should revoke the exposed key in the OpenAI dashboard and provide only its non-secret key ID/name and provider confirmation. If someone else owns it, identify that owner so the incident can be directed to them. No replacement key is requested or needed. Do not claim invalidation until provider-side confirmation arrives. No authority to rotate credentials, edit shell credential configuration or contact another person has been assumed.

## Established exposure

The original direct diagnostic was `/Applications/Xcode.app/Contents/Developer/usr/bin/xctest -help`. It exited 1 and printed its inherited environment. This historical command is recorded to explain the incident, not as a command to rerun with the ambient environment.

The local rollout contains the exposure at **2026-10-31T15:13:15.114Z** (event record) and **2026-10-31T15:13:15.251Z** (tool-output record), call ID `call_f0fa37ed1e31462b95a78096547dbe7b`.

| Location | Sanitized finding |
| --- | --- |
| `/Users/frank/.zshrc`, line 1 | Original configuration assignment |
| `/Users/frank/.codex/shell_snapshots/01a18fa3-c499-7dd2-983e-b9cb171d729e.1793411828754591000.sh`, line 4172 | Export captured in shell snapshot |
| `/Users/frank/.codex/shell_snapshots/01a18fa3-c499-7dd2-983e-b9cb171d729e.1793457603892455000.sh`, line 4173 | Export captured in shell snapshot |
| `/Users/frank/.codex/sessions/2026/10/30/rollout-2026-10-30T21-47-17-01a18fa3-c499-7dd2-983e-b9cb171d729e.jsonl`, lines 2034 and 2035 | Two local records of the leaking diagnostic output |

Do not display those raw lines. No credential value or credential hash is included in this report or new incident evidence. Existing logs were not deleted and Git history was not rewritten.

Observed inheritance: the Codex CLI process and its command child contained the exported credential. The ChatGPT parent process did not visibly contain it in the inspected process environment; `launchctl getenv` returned no value. A non-login command child still inherited the credential, so disabling login-shell startup alone was insufficient. Shell configuration/snapshots establish a local source, but the exact original export-to-Codex capture mechanism was not exhaustively reconstructed. The leaking diagnostic bypassed Joey's native helper layer, so fixing only `Processes.run` would not address its actual launch boundary.

The bounded exact-value scan initially checked 194 text files; the follow-up checked 203 and the final scan checked 212. All found only the known locations above. No matches appeared in scanned Joey working trees or generated evidence. The final scan had zero read errors or size skips and is recorded in `scan-final.json`. Roots included both Joey folders, the Joey build/evidence cache, `~/.codex/log`, `~/Library/Logs/ChatGPT`, the current rollout and shell snapshots. Build/binary caches, Git history, backups, other sessions and remote retention were outside this scan. A name-only comparison of current secret-like environment variables against the two original records identified only `OPENAI_API_KEY`; credentials no longer present or using unrelated names remain outside that check. These results do not establish absence of remote replicas or prove that nobody accessed the exposed key. Key validity, provider owner and misuse remain unknown.

## Prevention at the launch boundaries

`Tools/run-local.py` now launches direct executables with `os.execvpe` and an explicit allowlist, replacing the wrapper process so PID tracking, signals and exit status remain intact. It permits only local identity/path/locale inputs, `DEVELOPER_DIR` and the two existing test-fixture selectors, plus a fixed PATH. It does not copy arbitrary environment entries. Direct login/interactive shell launch is rejected to avoid restoring shell exports. Missing-executable diagnostics do not echo arbitrary arguments or environments. Project instructions require this entry for build/test/diagnostic commands, direct Joey launches and any separately authorized installation tool.

Native `Processes.run` independently allowlists inherited and explicit override environments. `ProcessSupervisor` applies the same function immediately before `posix_spawn`, including direct supervisor invocations. Local HOME/locale and installed tool paths remain usable; `HF_HUB_OFFLINE=1` and `TOKENIZERS_PARALLELISM=false` remain enforced. The existing local Google rclone/OAuth configuration is intact. No provider mutation or new connection was required to test this protection.

The scope is Joey's project launch and helper boundaries. This does not scrub the already-running Codex process, alter global tool configuration, prevent an unrelated command from reading credential files, or retrofit the preserved installed app. Never run raw environment-dumping diagnostics outside the protected launcher. The new native build was kept separate and was not installed. The native executable was exercised through its headless supervisor entry only; final installed SwiftUI inspection remains open.

Frank's explicit clarification is now in `docs/REQUIREMENTS.md` and the canonical linked `docs/JOEY_SPECIFICATION.txt`: build, test, install, launch and core processing must not require any AI-service key; no key creation, replacement, embedding, usage or API-key billing; ChatGPT sign-in for Codex; authorized Google integrations remain separate.

## Regression evidence

Evidence root: `/Users/frank/Library/Caches/Joey-Native-Build/credential-incident`.

All prevention tests use constructed dummy-only parent environments. They never copy ambient credentials into the deliberately leaking positive control. The harmless canary is checked in memory and is not a real key.

Commands from `/Users/frank/Documents/Joey`:

```sh
python3 Tools/run-local.py /opt/homebrew/bin/python3 -m unittest discover -s Tests -p test_tool_environment.py -v

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tools/run-local.py /usr/bin/xcrun swift test --scratch-path /Users/frank/Library/Caches/Joey-Native-Build/credential-incident/spm

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tools/run-local.py /usr/bin/xcodebuild -project Joey.xcodeproj -scheme Joey -configuration Debug -destination platform=macOS -derivedDataPath /Users/frank/Library/Caches/Joey-Native-Build/credential-incident/native-build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

Output is redirected to `tool-environment-tests-final.log`, `core-tests-final.log` and `native-build-final.log` respectively. Final launcher tests passed with direct exit 0: 5 tests, 0 failures. The final explicitly selected-Xcode suite passed with direct exit 0: 31 executed, 30 passed, 1 intentional real-media opt-in skip, 0 failures, 19.470 seconds. It covers the model-independent and assisted paths, actual helper stdout/error capture, direct supervisor filtering and absence of AI credential names from the test process. The final native build also returned direct exit 0; it is not an installation or GUI acceptance claim.

Launcher tests cover normal output, error stdout/stderr with exit 7, the actual XCTest diagnostic with a dummy-only positive control, shell rejection and stable process identity. The new native app's headless entry also passed with a dummy-only parent: no canary or AI credential names reached the helper output; offline policy remained present. Exact command and assertions are recorded in `native-launch-canary.json`.

Preserved failures: the first Swift attempt used the global CommandLineTools selection, exited 1 before tests with `unable to resolve module dependency: 'XCTest'`, and is retained in `runtime-tests.log`. Per-command `DEVELOPER_DIR` corrected it without changing global Xcode selection. The first headless launch harness exited 1 because the initial subprocess-based wrapper inserted an extra parent; replacing it with `execvpe` repaired the launch relationship and the stable-PID regression now protects it.

`preservation-after.json` verifies all 124 prior source/transcript/nine-output/checkpoint/receipt/installed-app/evidence identities and all 18 model-independent fixture identities unchanged by SHA-256, bytes and nanosecond modification time. These are preservation checks, not reopened media audits. No prior accepted clips or receipts were replaced.

## Remaining boundaries

- Credential incident: OPEN, invalidation pending the owner's provider confirmation.
- Prevention and key-free build/core verification: final results recorded in STATUS/VERIFICATION; no AI-service dependency introduced.
- Production acceptance: PARTIAL. Existing local QA/reuse/recovery evidence is retained.
- Installed SwiftUI inspection/reopen: still open; headless launch is not GUI evidence.
- Drive filing, register reconciliation and platform ingestion: unchanged, separate acceptance lanes. No external writes or social publication occurred.
- Safe development can proceed without a replacement secret. Installation, pushing, merging and publication were not performed by this task.
