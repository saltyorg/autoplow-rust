# Spec: the Google Drive trigger (v1)

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

## Interaction with the rclone mount
- A change seen in the Drive API isn't visible to the rclone VFS mount until the mount's own change polling notices it (rclone's `--poll-interval`, default 1 minute).
- **Decided:**
  - The monitor's default minimum age is set **above the mount's poll interval**.
  - The trigger does **not** check whether paths exist. If needed, the scan pipeline's generic "path must exist before delivery" check handles that (see [scan.md](scan.md)).

## Not in v1
- Service accounts.
- Using tokens from `rclone.conf` (possible later).
