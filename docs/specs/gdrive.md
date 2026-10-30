# Spec: the Google Drive trigger (v1)

**Module:** `gdrive` · **Depends on:** core, scan, rclone · **Decisions:** ADR-0013 · **Status:** approved 2026-10-27, crypt remotes, change log, controls and snapshot browser added 2026-10-30

## Objective
Turn Google Drive changes (My Drive and shared drives) into scan events for the corresponding mounted paths, with a sign-in flow a user can complete from the UI.

## Non-goals
- Service accounts
- Uploading through Drive APIs (uploads go through rclone)

## Connecting
1. The user creates a Google Cloud OAuth client of type **Web application**. The UI includes a step-by-step guide with screenshots.
2. They enter its client ID and secret in our UI. Each set is stored once as an encrypted "Google account" credential and can be reused.
3. They click **Connect**:
   - The browser goes through Google consent, requesting `drive.readonly` and offline access.
   - Google redirects to `https://<our-ui>/api/v1/gdrive/oauth/callback` with a state parameter.
   - The refresh token is stored encrypted, and key rotation re-encrypts it too.
4. The UI shows the exact redirect URI to register and checks that the request reached us on that URL. Saltbox domains provide HTTPS.
5. Several Google accounts are supported. Their tokens are refreshed automatically, and a revoked or expired grant raises a `health` notification.

## Monitors
- A monitor is (account, drive) where the drive is **My Drive** or a **shared drive**, chosen from a list fetched from the API.
- Each monitor has:
  - **Rewrite rules:** map Drive paths (`/<drive>/Media/TV/...`) to the canonical local path, usually the rclone mount, e.g. `/mnt/remote/<remote>/Media/TV/...`. They are scoped the same way as other triggers (no longest-match, no overlaps within a set).
  - **Include and exclude filters.**
  - **Polling interval:** default 1 minute, minimum 30 seconds.
  - **Minimum age.**
  - **Target excludes.**
  - **Crypt remote (optional):** the name of a crypt remote in the user's `rclone.conf` that wraps this drive (see below).

## Change tracking
Based on the bernard and autoplow designs.
1. **Initial snapshot:**
   - A full listing into `gdrive_snapshot_entries` (id, parents, name, mimeType, trashed).
   - Then the starting page token is recorded.
2. **Each poll:**
   - Read `changes.list` from the stored token, including shared drives and items from all drives.
   - Resolve every change to its old and new paths through the snapshot tree.
3. **Events produced:**
   - **Add or change:** a scan of the parent folder.
   - **Trash or delete:** a scan of the former parent folder, without an existence check.
   - **Rename or move:** a scan of both the old and the new folder.
   - Folder-level changes become a scan of the folder itself.
   - Redundant child paths are pruned.
4. **Ordering guarantee:**
   - Events are handed to the router **in the same transaction** that updates the snapshot.
   - The new page token is saved **only after** that commit, so a crash replays the changes and never loses them.
5. **An invalid page token** causes a fresh snapshot, a diff against the old one, and a resume from there.
6. **Rate limits and errors:**
   - Rate-limited per account.
   - Exponential backoff that honours `Retry-After` and 403 `rateLimitExceeded`.

## Crypt remotes
When the monitored folder holds an rclone crypt remote, the Drive API only sees encrypted names, while the mount and the media servers see decrypted ones. Rewrite rules and filters are written against **decrypted** paths.
- **How names are decrypted:** through the `rclone` module, with rclone's own crypt `decode` backend command (`backend/command` on the crypt remote) on our supervised `rcd`. It uses the remote's settings from the user's `rclone.conf`: password, salt, filename and directory-name encryption, encoding, suffix. Autoplow doesn't read keys itself and never touches the mount.
- **When:**
  - The snapshot stores both the encrypted and the decrypted name of every entry. Names are decoded in batches when the snapshot is built.
  - Each poll decodes only names it hasn't seen.
- **Failures:**
  - A name that can't be decrypted (a file that isn't part of the crypt remote, or a wrong password) isn't mapped. It's recorded in the change log as "couldn't decrypt", and no scan is produced.
  - If the crypt remote is missing from `rclone.conf`, or most names in the first snapshot fail to decrypt, the monitor stops with a `health` notification instead of mapping garbage.
- **Spike required:** before the design is final, verify against rclone 1.75 that `decode` through `rc` handles full paths, directory-name encryption on and off, every filename encoding, and batches large enough for a full snapshot.

## Change log
Every change the monitor reads is recorded, with what Autoplow did about it, so the UI can list recent changes.
- **Each entry has:**
  - Time, monitor and change kind (add, change, trash, delete, rename, move).
  - Drive path (decrypted when a crypt remote is set), the old path for renames and moves, and the mapped local path.
  - **Outcome:** a scan was queued (with a link to it), dropped by a filter (which one), not mapped by any rewrite rule, waiting for the minimum age, or couldn't decrypt.
- **Retention:** 7 days by default and configurable. Older entries are pruned daily.
- Entries are written in the same transaction as the events and the snapshot update, so the log never shows a change that was lost or one that never happened.

## Manual controls
- **Poll now:** runs one poll for the monitor right away. It goes through the same per-account rate limit.
- **Pause and resume:**
  - Stops polling. The pause is persisted and survives a restart.
  - On resume, polling continues from the saved page token, so changes made during the pause are still processed. If the token is no longer valid, the invalid-token path below applies.
- **Rebuild snapshot:**
  - Asks for confirmation.
  - Takes a fresh full listing, diffs it against the stored snapshot, and emits events for the differences (the same path as an invalid page token). Nothing is lost or scanned twice.

## Snapshot browser
A read-only view of what the snapshot holds for a monitor:
- Search by name or path, with paging.
- The total entry count.
- For crypt remotes, the encrypted and decrypted names side by side.
- Each entry's mapped local path, or "not mapped".

## Interaction with the rclone mount
- A change seen in the Drive API isn't visible to the rclone VFS mount until the mount's own change polling notices it (rclone's `--poll-interval`, default 1 minute).
- **Decided:**
  - The monitor's default minimum age is set **above the mount's poll interval**.
  - The trigger does **not** check whether paths exist. If needed, the scan pipeline's generic "path must exist before delivery" check handles that (see [scan.md](scan.md)).

## Not in v1
- Service accounts.
- Using tokens from `rclone.conf` (possible later). Crypt remotes use only the crypt settings from `rclone.conf`, not its tokens.

## Acceptance criteria
1. A user with their own OAuth web client can connect an account from the UI; refresh tokens are stored encrypted and survive key rotation.
2. Adds/changes, deletes/trash and renames/moves in a monitored drive produce scan events for the mapped folders (both old and new for moves).
3. Events are committed before the page token is saved: a crash between the two replays the changes rather than losing them.
4. An invalid page token triggers a re-snapshot and diff without losing changes.
5. Rate-limit responses (403 rateLimitExceeded, 429, `Retry-After`) back off without failing the monitor.
6. With a crypt remote set, changes under encrypted names produce scans for the decrypted mapped paths. A name that can't be decrypted produces no scan and a "couldn't decrypt" change-log entry. A missing crypt remote stops the monitor with a `health` notification.
7. Every change read appears in the change log with its outcome, written in the same transaction as its events. Entries older than the retention period are pruned.
8. "Poll now" runs a poll immediately, within the rate limit. A paused monitor makes no API calls, stays paused after a daemon restart, and on resume processes the changes made while paused.
9. "Rebuild snapshot" replaces the snapshot and emits events only for the differences.
10. The snapshot browser finds entries by name or path and shows the total count; for crypt remotes it shows both names.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Reusing rclone.conf tokens.
- **Never:** Request scopes beyond drive.readonly; read crypt keys from `rclone.conf` ourselves (decryption goes through rclone).
