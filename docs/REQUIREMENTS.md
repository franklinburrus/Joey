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

11. AUTHORITATIVE JOEY OUTPUT DESTINATIONS

Native-video clips: Joey Video Clips
https://drive.google.com/drive/folders/1fgABGYTtNC_h2u-v6fwTcPkVKjFd7GQx

Audio-template clips with soundwave: Joey Audio Clips
https://drive.google.com/drive/folders/1_s2K9Pw2Je93IwazQ6QgLjz_SimVYuPz

Route by source type, not output extension. Both workflows produce MP4s. These destinations apply to DUB and Taxstone work produced by Joey and replace all older Joey/platform clip destinations. Full-length files keep their existing locations.

12. EPISODE FILING STRUCTURE

Overall organizational example:
https://drive.google.com/drive/folders/1N7HyLq-Fq8a2RIaXMe7Xs17Y8UqYuCcJ

Detailed episode example:
https://drive.google.com/drive/folders/1SkV-Ea1DAYyOuNwKLpNCY9UEmVoBrzvz

Inside the correct Joey root use:

YYYY-MM-DD — Source Title — Source ID/
  01_Title_SourceID_HH-MM-SS_to_HH-MM-SS.mp4
  02_Title_SourceID_HH-MM-SS_to_HH-MM-SS.mp4
  Clip Index — Source Title — Source ID
  Source Title — Source ID — Full Transcript.txt
  clip_manifest.json
  RECONCILE.md

Use verified episode/broadcast dates; use Date Unknown when unavailable. Keep ownership and episode identities distinct. Reuse the matching source-job folder on retries. Do not create X/Instagram subfolders for duplicate versions.

Maintain one canonical Clip Index with clip numbers, titles, exact source timestamps, measured final durations, filenames, source IDs and verified Drive links. Preserve exact fractional timing internally even when filenames use whole seconds.

The manifest records source/output identities, interval mappings, exclusions, hashes, automated QA and filing receipts. The reconciliation summary reports actual completion and remaining gaps.

Generate applicable registry CSVs when needed. A prepared CSV does not prove a register write. Do not reproduce duplicate indexes, stale statuses or historical recovery files merely because they appear in the example.

13. VERIFIED DRIVE FILING AND RECORDS

Use the existing authorized rclone connection bound to exact Drive IDs. Before uploading, look for an integrity-verified equivalent; reuse it rather than creating a duplicate.

Independently read back Drive file ID, name, parent, size, supported checksum or exact downloaded bytes, and existing link/access state. Preserve permissions; do not automatically make files public.

DUB jobs reconcile the existing Master Link List against its current schema:
https://docs.google.com/spreadsheets/d/17uhDO06vmVEz96YrUnA6aHyV5fL_3AAs3ylOjrYRLwI/edit

Identify Joey-generated entries through supported fields or linked job evidence. Do not create competing registers or unnecessarily change the schema. Taxstone records remain separate from DUB-only records. Required writes need matching readback and duplicate checks.

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

16. ACTIVE ASSETS AND EXISTING ARCHIVES

DUB approved audio artwork:
https://drive.google.com/file/d/1fRg-Dfd-V_VdZQuPZVGDM3kdHD-qi6V1/view

DUB approved audio presentation sample:
https://drive.google.com/file/d/1anBMtGWXGIRHPbhQKVh5UtiDxyoPRPtg/view

Taxstone portrait audio instructions, governing the shared audio layout:
https://docs.google.com/document/d/1uzCYO0canF-N9Lfy0iZpJzevT2f1uafdCfbVk2yRNPQ/edit

Taxstone previous landscape audio instructions: retain compatible artwork/soundwave guidance; separate landscape export is superseded:
https://docs.google.com/document/d/1E3ELBN7gX-uFSmqAx-SjQWeJEIaQauJ3LUEcQHzLF6c/edit

Joe Budden existing full-length archive:
https://drive.google.com/drive/folders/1IIYLVDhCvwf5ZoMb0aM5vpSCe-eMCmyK

DUB existing full X-broadcast archive:
https://drive.google.com/drive/folders/1GpuGWGIbSt3afwsi9L782soT9WJKOHS9

Taxstone existing full-length archive:
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
