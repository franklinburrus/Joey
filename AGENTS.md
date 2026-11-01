# Joey Codex instructions

## Default response style: Caveman Ultra

Frank explicitly requires Caveman Ultra throughout Codex's work on Joey.
At the start of every session, read `.agents/skills/ultracave/SKILL.md` and
apply it to conversational planning, progress, debugging, test reports and final
answers. This repository instruction activates the default; Frank does not
need to repeat a slash command for each task. Use
`.agents/skills/caveman/SKILL.md` only when standard Caveman is requested.

Address the user as Frank. Lead with the result. Use the shortest clear wording
and state each fact once. Preserve exact code, commands, paths, API names,
errors, numbers, units, negation and essential reasoning. Clarity and safety
take priority over compression. Use complete sentences whenever a fragment
could be misunderstood.

Do not compress or omit requirements in code, comments, specifications,
documentation, commit messages, PR descriptions or external messages unless
Frank explicitly requests it. The style controls communication, not task
scope, implementation quality, test coverage or verification.

An explicit request for normal prose overrides the style for its stated scope.
Respect higher-priority system, developer and current user instructions. Do
not claim that a hook enforces the mode when no hook has been verified.

## Build continuity

Launch Joey build, test and diagnostic executables through
`python3 Tools/run-local.py EXECUTABLE [ARG ...]`, using direct arguments rather
than login/interactive shells. This launcher supplies a minimal environment at
the child-process boundary. Raw diagnostic commands can dump inherited secrets;
do not run them with the ambient development environment. Never use real
credentials for prevention tests; use dummy canaries. Native media helpers use
the matching allowlist in Processes/ProcessSupervisor. Do not add credential
variables to either allowlist to work around a missing dependency.

Use ChatGPT sign-in for Codex. AI-service API keys and API-key billing are not
Joey development or application prerequisites. Never create, request, replace,
embed or use such keys, including for credential-owner probes. Use the same
launcher for direct Joey executable launches and authorized installation tools;
do not change the installed app without current installation authority. Keep
authorized Google Drive/Sheets OAuth integrations separate and intact. Pending
owner-confirmed revocation does not block safe development without API keys.

The optional local assistant is separate from core clipping and transcription.
Frank authorized explicit Start/Stop of the existing Ollama installation and
regeneration of Ollama's local `id_ed25519` pair only when needed for startup.
This is not AI-service API-key authority or cloud sign-in. Keep owned Ollama
loopback-only, with cloud and external networking disabled, existing models
read-only, no downloads, and no model-generated tool execution. Do not start it
automatically or stop a service Joey did not start.

Verify that the selected checkout belongs to
`https://github.com/franklinburrus/Joey` before editing. Inspect its branch,
current history and uncommitted changes. Preserve existing work and use the
current Joey specification and task authorization. Read the existing project
checkpoint when present; record progress there for interrupted or handed-off
work. Do not infer app or test completion from an old chat or this instruction
file.

Continue authorized work through implementation, appropriate testing and
necessary repairs. Report actual results and unresolved gaps. No routine human
QA approval is required for Joey's media workflow; failed checks still require
repair or an accurate failure state.

## Skill installation boundary

The vendored Caveman and Ultracave files are response instructions only.
Their source and hashes are recorded in `third_party/caveman/provenance.json`.
Keep their licenses and NOTICE. They do not require a Caveman runtime,
Caveman Cloud, paid API, proxy, global Codex changes or Joey runtime dependency.

## Current native product direction

Read `docs/STATUS.md`, `docs/REQUIREMENTS.md`, and `docs/IMPLEMENTATION_PLAN.md`. REQUIREMENTS is the sole current product specification; the consolidated user request supersedes historical Python architecture, platform-specific variants, old destinations and human-QA holds. Keep temporary progress in STATUS. Use the existing SwiftUI/Xcode project; local media tools are helpers, not a browser application runtime.
