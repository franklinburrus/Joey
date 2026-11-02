# iCloud email intake

Joey can receive original HTTPS YouTube and X links sent directly to
`uploadtojoey@icloud.com` in the primary account's INBOX. It uses the installed
Python standard library over certificate-validated IMAP TLS, independent of
Apple Mail, Codex and ChatGPT. It never sends mail, changes flags, moves or
deletes messages, or publishes media.

## Secure setup

1. In your Apple Account at <https://account.apple.com/>, enable two-factor
   authentication if necessary and create an app-specific password for Joey.
   Apple documents the flow at <https://support.apple.com/en-us/102654>.
2. In the built Joey app, open **Settings → iCloud Email Intake → Connection
   and Email Template**. Enter the **primary iCloud Mail address**, not the
   intake alias or an unrelated Apple Account sign-in address. Enter the
   app-specific password in the secure field. Never use your main Apple
   Account password or paste a password into chat.
3. Enter the allowed sending addresses, separated by commas. Email intake
   only saves supported source links. Content and Workflow are selected later
   for each queued link; email prose cannot choose folders or run commands.
4. Choose **Save Secure Setup**. Joey creates a 256-bit random intake token
   and saves it with the app password in its own non-synchronizing Keychain
   item. Save reads that item back in this build. Ordinary settings, receipts,
   logs, command arguments and environment variables contain neither secret.
5. Choose **Test Connection**. Success proves a read-only INBOX login, not
   alias delivery or a processed media job. A failed login stops automatic
   password retries; correct the secure setup and test again.
6. Choose **Show Email Template**. Save the displayed body in your own mail
   client's template or draft. Put original source links and the exact line
   `Joey-Token: <your generated token>` in the primary message body. Use exactly
   one token line. Keep the token private; anyone possessing it can pair it
   with a forged allowed From address. Replace it if exposed. Sender allowlist
   matching alone is never authentication, and arbitrary
   Authentication-Results headers are never trusted.
7. Choose **Enable**, then send a fresh designated test message from an allowed
   address, with the alias explicitly in **To or Cc**. First activation saves
   an INBOX UID baseline before enabling intake, excluding all existing mail.
   Later resumes keep the saved baseline and backlog. Bcc-only delivery,
   forwarding, redirects, attachments and mail outside INBOX are unsupported.

The app-specific password gives access to the parent mailbox, not just the
alias. Joey enforces read-only operations in its code; the credential itself
does not have an alias-only or read-only permission scope. Use a dedicated
app password and revoke it at Apple when no longer needed. Disconnect removes
only Joey's item for the current account; it does not revoke Apple's password
remotely. Disconnect before replacing an account if its Joey credential should
also be removed.

## Processing saved links

Open **Settings → iCloud Email Intake → Queued Links**. Each incoming authorized
link waits here without source discovery, download or processing. Choose DUB,
Taxstone or Joe Budden and Full Show or Highlights for that item. Supply the
existing complete-source archive folder ID only if needed, then click **Process**.
Official Joe Budden episodes retain their existing Joe routing and Full Show
workflow. Existing production profiles, QA, full-source archival and Drive
filing requirements still apply.

Process saves your choice before starting. If another job owns processing, the
item waits for a turn. Unselected items stay queued across checks, wake and
restart. A failure requires **Retry**; an interrupted attempt requires Process
again. A frozen request retains its original workflow and accepted outputs.
Repeated emails reuse the saved item without resetting it or requesting a run.
All pending links appear independently of the bounded recent-receipt history.

Mail Enable/Pause controls collection only. You can process an already saved
link while mail is paused or disconnected. No replies or outgoing email are sent.

## Operation and recovery

While enabled, Joey checks about once per 60 seconds. Checks never overlap.
Transient connection failures back off for 1, 2, 5 and then 15 minutes.
Wake/connectivity recovery triggers another eligible check. The app and Mac
must be running and awake; there is no daemon or always-on guarantee. Mail
moved or deleted by another client before a check may not be captured.

Limits are Joey implementation choices: 15-second socket timeout, 60-second
overall helper deadline, 50 candidate messages and a finite window of up to
1,000 UIDs per batch, 64 KiB headers, 1 MiB message bodies, 10 distinct supported
source links per message and 100 pending items. Remaining server messages stay
for later batches. The canonical-link limit is checked before queue admission;
an oversized link set receives a rejection rather than silent truncation.

Only exact To/Cc recipients are accepted. Headers and size are fetched before
body retrieval; unrelated recipient bodies and disallowed sender bodies are
not fetched. MIME parsing prefers the primary plain-text body, falling back to
HTML text and anchor targets. Scripts, external assets, named files, attachments
and attached messages are ignored. The helper returns only bounded structured
status and candidate links; it never returns raw mail or authentication headers.

**Recent Email Receipts and Jobs** shows authorization-pending messages,
rejections, queued work, running jobs, retryable failures and completed jobs.
A receipt is not evidence of media completion. Open Job navigates to the real
coordinator job. Missing/incorrect tokens do not dispatch; resend with the
current template, then dismiss the obsolete local pending receipt if desired.
Dismissal does not change server mail. Retry in Queued Links preserves the frozen
request and accepted output, including after explicit cancellation.

Pause stops future mail checks. An already requested or accepted media job
continues; use its existing Cancel action to stop active processing. Manual,
Joe Budden and Taxstone processing share the existing media owner. Only links
with an explicit Process choice get turns between automatic episodes; email
never creates another renderer. Failures wait for Retry while independently
requested items proceed. Production requirements, original
archival, transcripts, automatic QA, Drive filing and register reconciliation
are unchanged.

One private `email-intake.json` under Joey's application-support directory saves
the account-specific INBOX baselines, minimal receipts, queue, frozen requests,
explicit processing choices and coordinator job mappings together. Receipt
identity uses account, mailbox,
UIDVALIDITY and UID, never Message-ID or read/unread flags. Media identity is the
existing immutable JobRequest; mail timestamps and UIDs do not change it.
Repeated links/messages and restart reuse that request and existing job.
Version 1 ledgers upgrade without granting processing intent to any old item;
version 2 saves are rejected by older automatic-dispatch builds. Rollback must
preserve this ledger and leave intake disabled in such an older build. Display
history is bounded to 500 receipts; frozen request mappings are retained.

A changed UIDVALIDITY invalidates the numeric cursor. Joey preserves the ledger
and stops mailbox ingestion instead of replaying historical mail. Review saved
work, use **Establish New-Mail Baseline**, then resend any uncaptured links as
fresh mail. This deliberately favors no silent replay over guessing which old
messages were delivered. A damaged checkpoint is preserved and reported; it is
never replaced with an empty queue. The email-only lock allows one intake owner
per application-support root and never holds the media lock during IMAP.

Credential copies exist briefly in process memory and an anonymous stdin pipe.
Swift/Python do not guarantee secure erasure of strings. The installed Python
must remain available; Joey does not install or upgrade a runtime. An ad-hoc
test build's Keychain result does not prove access continuity after signing,
installation or an application upgrade.

## Verification and live acceptance

Synthetic tests exercise exact recipients, forged headers, template tokens,
MIME selection, read-only commands, finite UID windows, capacity, failed saves,
account changes, frozen requests, busy owners, restart boundaries, cancellation,
dummy Keychain values and sanitized helper errors. They do not access a real
mailbox or prove media delivery.

After secure setup in the intended app build, verify the designated fresh
message appears once in Queued Links with no discovery or job after Check Now
and relaunch. Choose its Content/Workflow and click Process; verify it binds
to one coordinator request/job. Send unrelated synthetic mail only if separately
authorized; inspect the designated message's unchanged flags/location through
your normal mail client. Click Process for one queued message while Joey is busy,
then confirm it receives a processing turn; an unselected message must keep
waiting. Use only a small, authorized supported
source for a live downstream media test. Confirm required Drive/record evidence
separately; a saved receipt or connection test is not delivery.

No installation, account setup, outgoing test mail or production media run is
performed by the implementation tests. Current implementation/build/test results
and unresolved live dependencies are recorded in [STATUS.md](STATUS.md).
