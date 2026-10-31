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
