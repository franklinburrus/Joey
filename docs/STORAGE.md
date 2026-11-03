# Joey Storage Manager

Storage Manager operates inside the existing native application and coordinator. It preserves all DUB, Taxstone and Joe Budden originals, historical or imported/reused sources, accepted clip MP4s (including filed copies), transcripts, indexes, manifests, Drive receipts, job checkpoints, models, settings, credentials, installation evidence and rollbacks. Frank's latest 2026-11-02 instruction restores permanent Joe full-episode retention and supersedes the earlier temporary-source deletion policy. Storage Manager does not manage cloud storage or unrelated Mac folders.

## Settings and measurements

Settings → Storage shows actual free bytes on the working volume and logical sizes of Joey files. Temporary Files includes scratch; Active Processing is a subset of Temporary Files. Protected Data is non-scratch runtime data. Unregistered or uncertain scratch is also protected from deletion. Reclaimable bytes are verified under the processing and worker locks; while another worker owns storage the interface reports verification pending, not an estimate. Refresh remeasures. Clean Now revalidates candidates immediately before removal. Automatic Cleanup defaults to enabled; its setting is read again between attempts. Low Disk Protection cannot be disabled.

Cleanup receipts under `storage-cleanup/` distinguish measured bytes of removed files from the actual filesystem free-space delta. APFS allocation, snapshots and concurrent processes can make these values differ. Neither is inferred from a deletion request alone.

## Ownership, lifecycle and recovery

Only fresh render attempts registered by the coordinator under `jobs/<jobID>/scratch/<clipID>/<UUID>/` are eligible. Permanent `storage-attempts/` receipts bind job, clip, attempt, directory inode/device and captured file identities/hashes. Render JSON diagnostics are retained outside disposable scratch. Cleanup requires the saved accepted clip, matching local SHA-256 and retained QA. Accepted MP4s themselves are never cleanup candidates, even after Drive filing.

The existing processing lock excludes other coordinators and manual cleanup. Supervised helpers additionally hold shared worker leases; cleanup requires an exclusive worker lease. Native rendering remains under the coordinator lock. A live attempt or failed attempt without an accepted replacement remains protected. After restart an orphan registered attempt may be sealed only when its creator is absent, workers are excluded, its outputs are recognized, and a durable accepted replacement exists. Age and filename alone are never authority. Historical attempts without lifecycle receipts remain protected.

Paths are derived from validated identities, checked for canonical containment, and opened through no-follow directory descriptors. Symlinks, hard links, unknown files, changed identities or hashes, referenced recovery dependencies and malformed records prevent disposal. Deletion uses individual verified unlinks, never recursive directory removal. Partial cleanup can reconcile already absent expendable files. Bookkeeping failure preserves uncertain scratch and must not invalidate already accepted media or block its filing.

## Retained Joe full-episode sources

Joey archives complete Joe originals in Joe Budden Full Episodes (`1KJ0-sjGWNxwIuis_faA5z_FbPUcbjEDD`) before transcription/clipping, preserving original bytes and extension and using names such as `945 — Maximum Punishment.mp4`. Existing byte-equivalent verified archives remain reusable without reuploading or moving them.

Originals are protected after completion, on reopening and during automatic or manual scratch cleanup. The obsolete Joe source-registration and deletion lifecycle is removed. Historical `source-retention.json` receipts remain untouched as evidence; neither a registration nor an interrupted removal intent authorizes deletion under the current policy. Local originals consume protected storage, so low-disk admission can block further acquisition/rendering rather than delete retained sources.

## Capacity protection

Capacity uses actual free filesystem bytes, excluding assumed purgeable space. The operating-system reserve is 1% of volume size, bounded between 2 and 8 GiB. Admission adds source acquisition where needed, retained outputs at the existing encoder ceiling plus allowance, and bounded per-attempt WAV/PCM, encoding, faststart and QA storage. Estimates scale with duration, source bytes and audio/video workflow; they are not displayed as verified reclaimable bytes.

Media-writing helpers and native waveform rendering check free capacity every five seconds. A low-capacity interruption drains supervised workers, retains durable job/attempt state, and stops further renders. Already accepted outputs can finish Drive reconciliation without another large local render. Storage-blocked jobs poll capacity every 60 seconds; they do not repeatedly render or upload during the wait. Safe automatic cleanup runs before rechecks if enabled. Resume revalidates the unchanged request and all production gates, including capability expiry. Pause cancels the wait; restarting recovers from the existing job and library records. Joe discovery retains its original 30-minute interval and episode 976 baseline.

A later non-storage failure clears the historical capacity-wait marker. For example, expired capability evidence after capacity improves is reported at capability verification rather than repeatedly waiting for storage or overwriting the useful failure. Transcript tail recovery preserves typed low-storage errors so the same coordinator wait/resume mechanism applies.

File hashing consumes and releases each 1 MiB read buffer before the next read, including verified scratch-file hashing through the already-validated descriptor. This bounds buffer retention independently of source size while preserving SHA-256/MD5 results and all existing identity, no-follow and cleanup checks. It does not reclaim protected media or count assumed purgeable capacity.

## Limits

Storage management cannot make the entire 106-episode library fit by deleting accepted content: that deletion is explicitly outside its authority. If protected retained media exhausts available capacity, Joey blocks new media work and requires more working-volume space. Historical scratch, legacy-reuse media/evidence and unregistered process remnants remain untouched unless a future explicitly authorized reconciliation establishes safe disposal. No general-purpose cleanup or permanent background service is installed.
