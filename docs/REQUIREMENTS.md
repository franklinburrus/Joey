IMPLEMENT JOEY — CONSOLIDATED REQUIREMENTS

Use the attached specification as Joey’s current requirements. First verify that the selected folder contains the existing Joey project and identify its GitHub repository. Reconcile conflicting requirements, then implement and test the changes. Use Swift/SwiftUI and Xcode, with local media processing and optional Xcode Cloud builds. Preserve existing work. Continue through implementation and verification without human QA approval.

The repository is https://github.com/franklinburrus/Joey
Git remote: https://github.com/franklinburrus/Joey.git

Frank has connected Xcode to this repository. Reuse that existing connection and the matching Xcode project/workspace. Verify the selected checkout, origin, branch, current remote history, project files and uncommitted changes before editing. Do not assume an older local checkout matches the current GitHub history. Do not create a replacement repository, repoint Xcode, reset existing work or upload unrelated old implementation files.

The consolidated specification below contains the latest requirements. Reconcile older attachments and repository product rules against it. Preserve compatible safeguards and historical evidence. Current explicit instructions from Frank govern task scope; do not interpret historical documentation-only holds as a new hold on implementation explicitly authorized by this prompt.

1. CAVEMAN ULTRA THROUGHOUT THE BUILD

Use Caveman Ultra for all Codex conversational work on Joey: planning, progress, debugging, test reports and final answers. Read the repository’s AGENTS.md and .agents/skills/ultracave/SKILL.md at session start. The repository instruction activates the default; Frank must not repeat a slash command for every task.

Retain .agents/skills/caveman/SKILL.md for requests for standard Caveman. Preserve third_party/caveman/provenance.json, licenses and NOTICE. If a checkout is missing these files, reconcile it with the current repository and reuse the verified package before considering a new installation.

Address Frank directly. Lead with the outcome. Use the shortest clear wording, preserve every essential fact, and state each fact once. Preserve technical literals, commands, paths, API names, errors, numbers, units and negation. Clarity takes priority over compression.

Do not shorten code, comments, specifications, documentation, commits, PR descriptions or external messages unless explicitly requested. Caveman Ultra must not reduce task scope, implementation quality, testing or verification. Honor an explicit request for normal prose and all higher-priority instructions.

These are response skills. They do not require Caveman Cloud, a proxy, paid APIs, global Codex configuration changes or a dependency inside Joey. Do not claim measured token savings or automatic hook enforcement without evidence.

2. DEVELOPMENT STACK AND RUNTIME

- Swift and SwiftUI: native macOS application.
- Xcode: build, debug, test and package Joey using the existing repository connection.
- GitHub: source control, change history and recovery in franklinburrus/Joey.
- Xcode Cloud: optional automated builds and suitable tests.
- Frank’s Mac: acquisition, transcription, clip planning, rendering, soundwaves and automatic media QA.
- Google Drive: existing source archives and verified Joey outputs.

Xcode is required for this chosen development workflow. The finished application must run without requiring the user to open Xcode.

GitHub is the selected source host. It is not technically necessary for a locally developed Swift application, but use the existing Joey repository. Keep production media, transcripts, credentials, downloaded models and local runtime data out of Git.

Xcode Cloud is optional. Reuse an existing configuration if present. Its absence must not block local development or media jobs. Xcode Cloud requires a supported remote Git repository; GitHub, GitLab and Bitbucket are supported, and Joey uses GitHub. Reference: https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud

Xcode Cloud and Codex cloud development are distinct services. Neither is Joey’s production media-processing host. Run CI builds and suitable fixture tests in cloud CI. Run tests requiring local media, local models or Frank’s Drive connection on the Mac. Do not upload production media to CI.

Joey’s everyday operation must not depend on Codex, a ChatGPT conversation, GitHub availability or Xcode Cloud availability. Network operations such as source acquisition and Drive filing still require connectivity. Reuse working local tools and models. Keep the UI responsive during long operations.

2026-10-31 explicit credential boundary: No AI-service API key is required or permitted as a prerequisite for Joey development or the finished application. Codex uses ChatGPT sign-in; do not configure API-key billing. Joey must build, test, install, launch and perform core local media processing without OPENAI_API_KEY or any other AI-service credential. Do not create, request, replace, embed or use an AI-service key. Launch project tools, tests and Joey through a minimal environment, and enforce the same boundary for media helpers. Preserve the model-independent processing path. Existing authorized Google Drive/Sheets OAuth connections are separate integrations and must not be removed. The exposed-key incident remains open until its owner supplies provider-side revocation confirmation; it does not block safe, key-free development. Do not probe the exposed credential with /v1/me or another API request.

3. OBJECTIVE AND OUTPUTS

Automatically acquire or import authorized DUB and Taxstone media, plan clips, render, perform QA, file verified outputs and produce complete delivery records.

Native video: cut the original footage into clips without added video templates or branding.
Audio: render the approved audio artwork/template with a moving soundwave generated from the final clip audio.

Produce ONE shared MP4 per clip satisfying both X and Instagram. There are no separate X and Instagram clip versions, rendering jobs or platform output folders. This applies to native video clips and audio-template MP4s.

TikTok is eliminated. Keep DUB and Taxstone source identities, artwork, manifests, histories and records separate. Do not schedule or publish social posts.

4. AUTONOMOUS OPERATION — NO HUMAN QA APPROVAL

After a valid job starts, automatically complete planning, rendering, validation, supported repairs, filing and record reconciliation.

Do not require approval of individual boundaries, samples, rendered clips or review receipts. Do not require a person to watch or listen through outputs. There must be no routine WAITING_FOR_HUMAN_QA state.

Failed checks trigger automatic repair or an accurate failure state. Never bypass checks, invent evidence or request human approval to compensate for failed automation.

Missing credentials, inaccessible sources and missing essential inputs may require user action. These are operational dependencies, not QA approvals. Continue independent work while an affected item is unresolved.

5. SOURCE IDENTITY AND ACQUISITION

Accept authorized local media, YouTube sources, original X broadcasts and X Spaces. Reuse a verified existing original before downloading. Otherwise use an existing supported downloader and preserve direct-original provenance. Never bypass access controls or silently substitute reposts.

Inspect actual streams and content. A static artwork MP4 is audio-led content, not automatically native moving video.

Record ownership, original URL, stable source ID, source title, verified episode/broadcast date, actual duration, dimensions, frame rate, streams, local path, byte size, SHA-256, authorization basis and existing archive reference.

Acquire the complete original. Resume interrupted downloads. Reject incomplete source files. Do not infer redistribution rights merely from downloading.

Full-length originals remain where they are currently stored. Preserve and reference verified existing archives. Do not move or duplicate full-length files solely because Joey has dedicated clip folders. For a new source requiring archival, use its established full-length destination; preserve source bytes.

2026-11-02 latest explicit creator-retention amendment: preserve the entire Taxstone full-episode library, DUB originals and complete Joe Budden episodes. Frank restored permanent Joe archival in `1KJ0-sjGWNxwIuis_faA5z_FbPUcbjEDD`, superseding the earlier same-day archive-retirement and temporary-source-deletion instruction. File complete Joe source bytes before transcription/clipping, naming full-episode files `<episode number> — <episode title>.<original extension>`, for example `945 — Maximum Punishment.mp4`. Preserve the source's original title and provenance in records and its original container/extension. Do not delete Joe originals on completion, reopening or scratch cleanup, even when a historical `source-retention.json` removal receipt exists. Preserve those historical receipts unchanged. Reuse existing verified originals without relocation, duplication or rerendering. Existing full-episode files in the named folder may be renamed in place to the requested pattern, preserving IDs, bytes, parents, permissions and links; this is not authority for a catalog download or archive purge.

6. COVERAGE AND BOUNDARIES

Full-show clipping is the default for complete episodes and broadcasts, including Taxstone. Highlight mode runs only when explicitly selected and produces self-contained selections, honoring any requested count.

For full-show jobs:
- Cover retained program content chronologically through its actual ending.
- Target 8–10 minutes per clip; calculate clip count automatically.
- Prefer complete sentences and natural discussion boundaries.
- Record necessary duration exceptions, including short remainders.
- A source shorter than the target becomes one complete clip.
- Never omit retained content, repeat speech, stretch footage or add silence to force duration.

Verified platform hard limits take priority over preferred duration. Automatically plan shorter shared segments where necessary while preserving required coverage. Do not silently alter an explicitly fixed interval; report the exact conflict if it cannot comply.

Each retained source interval appears exactly once within a documented, tested encoding tolerance. Store exact source/output interval mappings, including multiple intervals when an ad exclusion occurs within a clip.

7. ADVERTISEMENTS AND TRANSCRIPTS

Exclude confidently identified ad reads in full-show mode. Record exact exclusions and their source evidence. Preserve uncertain material automatically; do not request human classification.

Preserve introductions, source endings, silence and other non-ad program content unless removal is explicitly requested.

Generate or reuse a complete timestamped, source-bound transcript locally. Use it for boundaries, titles, ad identification and coverage reconciliation. Do not retranscribe unchanged sources because a later stage failed. Include the full transcript in the episode package.


2026-10-31 explicit local-core amendment — MODEL-INDEPENDENT CORE PROCESSING:

Provide a bounded local-processing path that requires neither a transcript nor speech-recognition inference. With no valid supplied or cached transcript, retain the entire local source chronologically using deterministic time-based segmentation, source metadata and sequence-based filenames. Do not infer topics, generate descriptive content titles or remove suspected advertisements. Explicitly report the complete transcript, transcript-assisted boundaries, descriptive titles and advertisement identification/removal as unavailable. Do not invoke an ASR helper/model or download a model in this path. Preserve valid transcript reuse, source binding and the existing optional assisted workflow.

This exception permits local planning, rendering, technical/coverage QA and local records without a transcript. It does not waive production transcript/editorial requirements, verified profile requirements, Drive filing or required register reconciliation. Missing production requirements prevent COMPLETED. Do not create a fake full-transcript file. Preserve existing accepted plans, clips, QA and receipts; a newly appearing transcript must not silently reclassify an accepted deterministic plan. Repeatability concerns identical planning decisions and interval mappings for identical inputs/configuration, not byte-identical encoding.

8. NATIVE VIDEO PRESENTATION

For native DUB, Joe Budden and Taxstone video, cut the original footage. Preserve original audio, picture proportions, synchronization and existing graphics, logos and subtitles already within the source.

Add no video template, artwork panel, logo, waveform, title overlay, speech captions or separate outro. Do not stretch footage or crop essential content. Older Joe Budden logo/outro additions and separate platform video templates are superseded for these jobs.

9. AUDIO PRESENTATION

Audio sources produce a shared social-ready MP4 using the correct approved presentation. Preserve the original recording in its existing archive.

DUB audio:
- Use the approved artwork and reference composition, including its existing branding.
- Render the source-grounded clip title in the established style and position.
- Generate the gold soundwave from the actual final clip audio.
- Keep horizontal bar positions fixed; heights respond vertically to the audio.
- Do not use fake, scrolling, baked-in or prerecorded waveform animation.
- Add no speech subtitles or separate outro.

Taxstone audio:
- Automatically resolve the existing artwork matching the selected episode. It is a standard production input.
- Preserve the full artwork and TAX SEASON mark.
- Generate a fresh white soundwave from final clip audio.
- Do not substitute DUB assets, invent artwork or add unsupported lettering.

Use the established Taxstone portrait geometry on a 1080×1920 canvas: artwork region 900×900 at x=90, y=120; soundwave region 900×180 at x=90, y=1400. Fit artwork proportionally. Scale the approved layout proportionally for a smaller shared canvas. Preserve DUB’s own approved reference layout; do not borrow Taxstone geometry.

If an expected asset cannot be retrieved, automatically inspect established asset locations and report the exact unresolved dependency. Do not substitute unrelated art or introduce human QA approval.

10. SHARED TECHNICAL EXPORT

Export MP4 with H.264, yuv420p, progressive scan, square pixels, 30 fps, AAC-LC audio where present and web playback support.

Use a portrait 1080×1920 canvas when verified for both upload destinations. Use 720×1280 for both when the verified common profile requires it. Never produce a second platform version.

Fit complete native landscape frames proportionally with plain black padding. This preserves the frame but reduces its visible size inside a portrait canvas. Report source resolution and effective picture dimensions; do not label this preserved full-frame 1080p landscape detail. Do not upscale poor source footage and claim native quality.

Verify current duration, dimensions, frame-rate and file-size limits for the actual X account and Instagram upload surface. Record the profile, account capability evidence and official sources. Do not assume account eligibility or treat a legacy profile’s verified flag as current evidence.

Automatically select a compliant shared profile or report the exact incompatibility. Packaging compliance does not prove successful platform ingestion. Do not guarantee Instagram will present video as a traditional feed post rather than a Reel.

11. AUTHORITATIVE DUB FILING DESTINATIONS — 2026-11-02 CORRECTION

Frank reorganized the Drive tree by creator, then explicitly restored Joe's permanent full-episode archive at the new folder below. The following eight active destinations reflect his latest 2026-11-02 instructions. They supersede the former Media/Clips hierarchy, intermediate platform folders, the earlier same-day Joe archive retirement, and retired Joey Video Clips/Joey Audio Clips roots. The authoritative tree is https://drive.google.com/drive/folders/1owpGIsjztPdlIIVb7DaszgtlbgEwrJ0Q, with creator folders directly inside Content. Never recreate retired wrappers or require another approval of the settled creator layout.

| Content | Clip root | New full-episode root |
| --- | --- | --- |
| DUB X audio | `1FRi-yy2D9yenjQRailTA2iAbPaqAEPXm` | `109_QzHpF0Bi-OG6-AxuTDw1uHG4zeop3` |
| DUB X video | `1380CHJ3a3kl7fXNIKWqUM7_DeTZUwxsy` | `1GpuGWGIbSt3afwsi9L782soT9WJKOHS9` |
| Taxstone | `1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8` | `1wQMwzUconRC3UCvH2jpL1kD__ctBv29p` |
| Joe Budden | `1X5VNP6fo3VpZPu4ZW4p7Ggk2o_IAVGSI` | `1KJ0-sjGWNxwIuis_faA5z_FbPUcbjEDD` |

Use one deterministic resolver for source ownership (DUB, Taxstone or Joe Budden), inspected source format, asset classification (clip or full episode), and verified source identity. Never route by MP4 extension. Joe Budden retains its historical serialized DUB owner and explicit joeBudden workflow for existing request identity compatibility; that combination routes to Joe Budden's destinations and separate records. No manual Drive destination selection is required. A saved explicit archive selection conflicting with the authoritative route must fail with the exact conflict rather than silently override it. The known retired Joe selection `1IIYLVDhCvwf5ZoMb0aM5vpSCe-eMCmyK` is the sole migration exception: resolve it to Frank's newly specified Joe full-episode root without changing saved job identity. Reject arbitrary conflicting selections.

Google Drive IDs, folder names, exact parents, ancestry and existing permissions must be verified before filing. DUB clip packages are directly below Content/Dub/X Audio Clips or Content/Dub/X Video Clips; its originals are under Content/Dub/Full X Audio Spaces and Content/Dub/Full X Broadcasts. Taxstone packages are directly below Content/Taxstone/Taxstone Clips; retain all originals under Content/Taxstone/Taxstone Full Episodes. Joe packages are directly below Content/Joe Budden/Joe Budden Clips, whose current name has no trailing space; full originals are directly below Content/Joe Budden/Joe Budden Full Episodes. Creator parent IDs are Dub `1JQH012UFDeHukvigMf4dGxCoUgWvMc4U`, Taxstone `1kxv3bbnPPRt914npHFUI51jrbCY0atyU`, and Joe Budden `1-HjL5kpENfWQm5jwshAhU3QM-THI6u53`; Content is `18Ix3mVu8gCFSa-EGGpzQsh03SajrZvKm`. These are existing branches, not instructions to recreate Media or platform wrappers.

New DUB, Taxstone and Joe Budden full-length sources requiring archival use the corresponding full-episode root. Existing byte-equivalent originals remain in their current verified archives, including historical Taxstone archives; never silently relocate or duplicate them. Incorrectly routed existing clip packages must be identified and reported without automatic relocation, deletion, or copying to a second root. Ambiguous source identity, ownership, destination, or folder identity stops the affected filing operation while preserving accepted work.

12. EPISODE FILING STRUCTURE

Overall organizational example:
https://drive.google.com/drive/folders/1N7HyLq-Fq8a2RIaXMe7Xs17Y8UqYuCcJ

Detailed episode example:
https://drive.google.com/drive/folders/1SkV-Ea1DAYyOuNwKLpNCY9UEmVoBrzvz

Directly inside the resolved clip root, create or reuse one matching episode folder:

YYYY-MM-DD — Source Title — Source ID/
  01_Title_SourceID_HH-MM-SS_to_HH-MM-SS.mp4
  02_Title_SourceID_HH-MM-SS_to_HH-MM-SS.mp4
  Clip Index — Source Title — Source ID.csv
  Source Title — Source ID — Full Transcript.txt
  clip_manifest.json
  RECONCILE.md

Use verified episode/broadcast dates; use Date Unknown when unavailable. Keep ownership and episode identities distinct. Reuse the matching source-job folder on retries. Do not create X/Instagram subfolders for duplicate versions.

Maintain one canonical Clip Index with clip numbers, titles, exact source timestamps, measured final durations, filenames, source IDs and verified Drive links. Preserve exact fractional timing internally even when filenames use whole seconds.

The manifest records source/output identities, interval mappings, exclusions, hashes, automated QA and filing receipts. The reconciliation summary reports actual completion and remaining gaps.

Generate applicable registry CSVs when needed. A prepared CSV does not prove a register write. Do not reproduce duplicate indexes, stale statuses or historical recovery files merely because they appear in the example.

13. VERIFIED DRIVE FILING AND RECORDS

Use the existing authorized rclone connection bound to exact Drive IDs. Before uploading, look for an integrity-verified equivalent; reuse it rather than creating a duplicate.

Independently read back Drive file ID, filename, actual parent ID, expected destination ancestry, size, supported checksum or exact downloaded bytes, link/access state, and absence of unintended duplicates. Compare permissions across writes, including identities, roles and discovery settings; preserve sharing without automatically making anything public. Download required companion files for byte verification. Completion requires every planned clip, all four canonical companion receipts, passing automated QA, validated source/coverage, and applicable register reconciliation. A CSV alone is not a register-write receipt.

DUB jobs reconcile the existing Master Link List against its current schema:
https://docs.google.com/spreadsheets/d/17uhDO06vmVEz96YrUnA6aHyV5fL_3AAs3ylOjrYRLwI/edit

Identify Joey-generated entries through supported fields or linked job evidence. Do not create competing registers or unnecessarily change the schema. Taxstone and Joe Budden records remain separate from DUB-only records. Joe uses its episode package records; do not add Joe rows to the DUB Master Link List or delete historical rows during this correction. Required DUB writes need matching readback and duplicate checks.

Return an in-app recap with source identity, output count, titles, timestamps, durations, QA results, episode folder and direct links. Do not automatically email, schedule or publish media.

14. AUTOMATIC QA, RECOVERY AND RESOURCE USE

Check complete decoding; actual codecs/dimensions/frame rate/duration/size; source/output audio fidelity and sync; required coverage and exclusions; clean boundaries and unintended duplication; proportional framing and picture fidelity; audio artwork/layout; soundwave response to actual audio; absence of unrequested additions; hashes/manifest consistency; and Drive integrity/required register readback.

Report only what each check actually establishes. Automated technical or editorial checks are not infallible semantic judgment. Preserve material when an optional removal is uncertain. Never fabricate viewing, listening, reviewer or approval records.

Retry transient operations up to three times. Repair affected files/stages and continue independent items. Persist progress after each stage. Reuse unchanged sources, transcripts, accepted clips and valid receipts. Reconcile uncertain external writes before retrying.

Check disk space, bound concurrency and support cancellation. Use application-owned working data outside synchronized Drive storage. Keep the UI responsive. Preserve originals and accepted files. Cleanup must not remove the only verified copy or unrelated files. The Mac must remain available for local processing; sleep/shutdown pauses or stops work, and restart must recover from durable state.

15. COMPLETION STATES

Normal progression: PLANNED, PROCESSING, QA_PASSED, FILED, COMPLETED.
Failure reports preserve the exact stage, affected item, error and recovery status.
A filing outage leaves accepted media as QA_PASSED — NOT FILED.

COMPLETED requires every planned output exactly once, passing applicable automated QA, reconciled required coverage, verified Drive outputs and companion records, required register readback and a current manifest matching the actual files. Render success, an exported CSV or a queued upload cannot independently establish completion.

2026-11-01 explicit clarification: Drive filing is required for every Joey clip. The UI must never describe it as "Not requested" or label local-only outputs Completed. Local processing and accepted-file recovery remain available while delivery is pending; they do not waive Drive filing. Completed badges and delivery checkmarks require saved evidence matching every accepted clip. Preview fixtures must show this same workflow and must remain clearly identified as synthetic sample data.

16. ACTIVE ASSETS AND EXISTING ARCHIVES

DUB approved audio artwork:
https://drive.google.com/file/d/1fRg-Dfd-V_VdZQuPZVGDM3kdHD-qi6V1/view

DUB approved audio presentation sample:
https://drive.google.com/file/d/1anBMtGWXGIRHPbhQKVh5UtiDxyoPRPtg/view

Taxstone portrait audio instructions, governing the shared audio layout:
https://docs.google.com/document/d/1uzCYO0canF-N9Lfy0iZpJzevT2f1uafdCfbVk2yRNPQ/edit

Taxstone previous landscape audio instructions: retain compatible artwork/soundwave guidance; separate landscape export is superseded:
https://docs.google.com/document/d/1E3ELBN7gX-uFSmqAx-SjQWeJEIaQauJ3LUEcQHzLF6c/edit

Joe Budden current full-length archive (complete originals named `945 — Maximum Punishment` with their original extensions):
https://drive.google.com/drive/folders/1KJ0-sjGWNxwIuis_faA5z_FbPUcbjEDD

DUB existing full X-broadcast archive:
https://drive.google.com/drive/folders/1GpuGWGIbSt3afwsi9L782soT9WJKOHS9

Taxstone retired full-length wrapper (historical reference only):
https://drive.google.com/drive/folders/12g_etkCruq4tjG07t9hAqQffc4NqbSQK

Taxstone Full Episodes (preserved complete library and current new-original destination):
https://drive.google.com/drive/folders/1wQMwzUconRC3UCvH2jpL1kD__ctBv29p

Taxstone Lost Lil Uzi Vert presentation examples, not universal artwork masters:
https://drive.google.com/file/d/1EdeO03nq5f_GI9uy4Wbka_gGWVCIArWa/view
https://drive.google.com/file/d/1g89EodIK589vFBpnJZVxtaLCXcD0azTO/view
https://drive.google.com/file/d/1tWi7UuDnUmmOF0qlBVW9hDaPXGPt58Eg/view

17. HISTORICAL ASSETS — DO NOT APPLY TO NATIVE-VIDEO CLIPS

DUB Primary Logo:
https://drive.google.com/file/d/1rOBwiIFLGvglfDye1hlMh2HrL1PqRdfl/view

Joe Budden outro:
https://drive.google.com/file/d/1aIEOk1KUaYu82rL98Hfx1gufCM4cy6bw/view

DUB video template:
https://drive.google.com/file/d/1E_KOKod4NlpqsdREaFtE8syuQsEFUlbd/view

Previous Taxstone X video template:
https://docs.google.com/document/d/1l96p6NiiRsgpbmShsFYZCm5N_aWc9nQm7NO1uOY-SSs/edit

Previous Taxstone Instagram video template:
https://docs.google.com/document/d/1wiBM8Mnqkkb8K-XtVS-0voKC-SL1aFeBZrU7Vwi0I3o/edit

Compatible Taxstone operational references:
https://drive.google.com/drive/folders/1_DOLsqnp9SVeXG_Go82VdGAb6evs17pz
https://drive.google.com/drive/folders/1fRaM_N4M4RnXYrlhcfr5l0vBJIZ4QULi

Retain historical assets and receipts. Conflicting platform exports, destinations, video additions and human-QA requirements are superseded; compatible identity, authorization, integrity and recovery safeguards remain.

18. IMPLEMENTATION AND ACCEPTANCE

Use the simplest implementation fitting the current Swift/SwiftUI application. Reuse existing working media helpers where appropriate; do not revive an obsolete browser/Python app architecture merely because older documents describe it. Preserve old work without treating it as the current product direction.

Save this as the single current requirements document in the existing project documentation location. Reconcile conflicting active instructions, plans and acceptance criteria. Keep temporary task progress in the existing checkpoint, not permanent policy. Preserve historical documents as history.

Public distribution, signing and notarization are separate from building for Frank’s Mac. Do not add services, CI systems, paid APIs or infrastructure unless required by the authorized task. Reuse existing Xcode/GitHub connections and optional CI.

Verify the build and meaningful unit/integration tests, then demonstrate:
- A real native-video job with source-only cuts.
- A real DUB audio job with the correct layout and source-driven soundwave.
- A real Taxstone audio job with matching episode art and source-driven soundwave.
- A known 60-minute source yielding six chronological 10-minute clips when both destinations permit and no exclusions/boundary adjustments apply.
- Short sources, remainders, ad exclusions and shorter platform-limited segments preserving required coverage.
- Automatic rejection of corrupted output.
- Recovery from interrupted rendering/filing without duplicate files, uploads or rows.
- Completed jobs reopening without unnecessary reprocessing.
- Correct Joey destination, episode structure, transcript, index and verification records.
- End-to-end operation without human QA approval.
- Local app operation without Codex, GitHub or Xcode Cloud connectivity, except for explicitly network-dependent acquisition/Drive steps.

Use authorized existing media for real acceptance. If a required source, credential or capability is unavailable, finish independent work and report the exact remaining dependency. Synthetic tests cannot establish real-media acceptance or provider delivery.

Report actual commands, direct exit status, test counts, changed files, measured results and verified links. Do not let later commands mask a failed test. State unresolved risks accurately. Continue through necessary repairs until authorized work is complete. Use Caveman Ultra for conversational reports throughout, while keeping implementation and persisted documents complete.

19. OPTIONAL LOCAL TEXT ASSISTANT — EXPLICIT 2026-10-31 AMENDMENT

Provide an optional, user-initiated local assistant for conversation, writing, summarization, planning and occasional coding questions. Reuse the existing Ollama 0.40.13 installation at ~/Applications/Ollama.app and the installed qwen3:4b Q4_K_M Apache-2.0 model in ~/.ollama/models. Do not download duplicate models, introduce AI-service APIs, subscriptions, credentials or cloud inference. This feature does not change the model-independent clipping contract, transcription options or production acceptance gates.

Only process text the user types or explicitly pastes/selects into the assistant conversation. Do not scan files or the clipboard automatically, attach media jobs/transcripts, execute generated code or shell commands, access accounts, or publish. Assistant output is text only and cannot invoke tools or alter clipping plans. Keep conversation state in memory; clear it on explicit Clear or closing the assistant.

Frank explicitly chose Start/Stop service controls in Joey. Do not start Ollama merely by launching Joey or opening the assistant. Start uses the existing executable, loopback-only listening, disabled cloud features, denied external networking, one model/one inference at a time and the existing model storage without downloads or pruning. Stop and closing the assistant stop only a service Joey started; never terminate a pre-existing external service. Keep failures confined to the assistant. Pause assistant use while Joey is processing media to limit contention on the M1/16 GB Mac.

Frank explicitly authorized regeneration of Ollama's local id_ed25519 identity pair only when required for explicit startup. This is a local identity, not an API key, billing credential or cloud sign-in. Do not display or copy key contents into evidence. This narrow exception does not resolve or authorize changes to the separately exposed OPENAI_API_KEY incident. Do not rotate unrelated credentials or modify Google Drive/Sheets integrations.

Use the verified installed model identity, an 8192-token context, bounded conversation/input/output sizes, finite timeouts, cancellation and no silent remote fallback, model substitution or automatic retry. Native implementation/build verification, real offline inference and GUI acceptance must be reported separately. A short synthetic response is not a performance benchmark or a guarantee of answer quality. Preserve accepted media, receipts and production status.


20. EXPLICIT LINK-WORKFLOW AND JOE BUDDEN CORRECTIONS — 2026-10-31

Frank's later workflow corrections supersede conflicting earlier intake and Joe Budden presentation rules for new jobs. Native intake is Paste Link (YouTube/X), without local-source selection or a separate authorization-entry form. Preserve existing source provenance and legacy local job recovery; removing a form does not manufacture redistribution rights. Call the selection Workflow. Complete-original filing is mandatory for every new production job, before clipping, regardless of whether the selected clip workflow covers the full show or highlights.

DUB and Taxstone highlights use one selection per 15 minutes of source content, with a final partial block included; duration must satisfy their one shared X/Instagram export contract. Full-show clipping remains the default. Transcript, QA, source integrity, accepted-output reuse, exact Drive placement and required companion/register verification remain required.

Joe Budden uses the official Joe Budden TV numbered full episode on YouTube as its source. Frank specifically clarified: download and file the complete original, then create chronological 8–10-minute source-content clips of the retained entire show, apply the DUB logo in the lower left and the approved complete outro, and file to Drive, nothing further. This narrow Joe Budden exception restores those two approved assets only for that workflow. It does not add branding to other native-video workflows. This is a Drive delivery contract, not a claim of X/Instagram upload compatibility; the approved 140-second Buffer contract continues to govern DUB/Taxstone shared exports. Preserve the historical serialized DUB ownership for Joe job identity compatibility. The 2026-11-02 routing amendment requires Joe destinations and episode records to remain separate from DUB-only register writes; preserve Taxstone separation.

Frank requested automated background processing like Taxstone. Reuse the native app and existing processing/delivery coordinator, with opt-in Start/Resume, Pause, a durable new-episode queue, duplicate reconciliation, visible failures and safe restart. Do not replay an old catalog merely by enabling it. The current bounded implementation scans the official channel's 30 recent uploads on launch, every 30 minutes while enabled, and Check Now; it runs while Joey and the Mac are available, without a permanent service or automatic launch. Discovery cadence and the initial latest-episode baseline are implementation choices, not evidence of historical library coverage. No social publication, scheduling, email, new service, or permission change is included.

21. ICLOUD EMAIL LINK INTAKE — EXPLICIT 2026-11-01 AMENDMENT

Add iCloud-only incoming link intake for `uploadtojoey@icloud.com`, an alias of Frank's existing primary iCloud Mail account. Use native secure setup, an app-owned non-synchronizing Keychain item, the existing installed Python standard library and certificate-validated read-only IMAP. The app must operate without Apple Mail, Codex or ChatGPT. No outgoing email, SMTP, publication, mailbox reorganization, daemon, new provider or new AI runtime is included.

Frank explicitly chose the researched high-entropy intake-token fallback during implementation. Generate a 256-bit random token, keep it in Keychain with the app-specific password, and require exactly one matching token line in the primary email body plus a single allowed From address before admitting a link to the queue. Never treat From matching or arbitrary Authentication-Results headers as authentication. Explain the broader parent-mailbox credential scope and the need to keep the saved template token private.

Accept fresh direct INBOX messages with the exact alias in To or Cc. Ignore named files, attachments and attached messages; prefer primary plain text, otherwise parse HTML text and anchor targets without loading external content. Reuse existing supported HTTPS YouTube/X source identity, discovery, workflow selection and coordinator validation. Email text cannot select paths, execute instructions, override configuration or authorize publication.

Frank subsequently chose queue-only intake. Mail admission saves links without source discovery, download, rendering or automatic processing. Choose Content and Workflow per queued item, then explicitly select Process. Timers, wake, Enable, new messages and restart must not authorize an unselected item. Existing queued/retryable items also wait after upgrade. Mail setup has no global Content or Workflow controls.

Save receipt identity, per-account UID baseline/frontier, queue, explicit processing intent and immutable JobRequests atomically before acknowledging or dispatching work. Busy owners must defer durable work explicitly. Repeated emails, retries and restart reuse matching source/workflow requests and existing coordinator jobs. Bound checks, MIME sizes, queue capacity and retries; preserve corrupt state and surface UIDVALIDITY resynchronization instead of replaying old mail. Give explicitly requested items fair turns between existing automatic episodes without changing Joe's monitoring cadence. A busy Process request persists until a turn is available; failures and interrupted attempts require explicit Retry/Process. Duplicate mail must not authorize or reset a saved item. Pause/Disconnect stop mail collection; saved links can still be processed manually, and accepted media jobs continue. Preserve legacy requests and use a versioned ledger that older automatic-dispatch builds reject.

Provide native secure setup, allowed senders, per-item Content/Workflow/Process controls, Test Connection, Enable/Pause, Check Now, Disconnect, private template access, recoverable errors and receipt-to-job navigation. Keep production, Drive/register delivery, live mailbox acceptance and installed-build Keychain continuity separately evidenced. Setup and bounded operating behavior are documented in ICLOUD_INTAKE.md; implementation progress remains in STATUS.md.
