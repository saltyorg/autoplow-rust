# Spec: the upload pipeline (v1)

This consolidates the upload decisions in the ADRs in [../decisions/](../decisions/README.md). The research behind it is in [../research/upload-readiness.md](../research/upload-readiness.md).

## Model
- **Unit of work:** uploads are **per file**. A file enters the upload queue from the local filesystem triggers (inotify, walk, or both) or from Arr import events.
- **Destinations:** a destination maps a local path to an ordered list of remotes taken from the user's `rclone.conf`. Each remote can have a sub-path.
- **Transport:** in-process rclone (librclone RPC). Each batch is its own job with its own stats group. Uploads are tracked by job and identity, never by file name.

## Readiness (all configurable per destination)
1. **Minimum age**
   - Age is counted from our first-seen time and **restarts whenever mtime changes**.
2. **Size stable**
   - Size, mtime, ctime and inode must be unchanged across two or more checks.
3. **Not open for writing**
   - Write-mode opens and write locks block the upload. Read-only opens never do.
   - A file is matched by dev+inode on both its `/mnt/local` identity and its mergerfs identity.
   - Long-stable hardlinked files held read-write by rTorrent or mergerfs are let through after a configurable window.
   - The process holding the file, and its container, are identified.
   - Optionally, the upload **waits while Plex, Jellyfin or Emby has the file open**.
   - This check needs `pid: host` and `SYS_PTRACE`. Without them, the UI notes that only the age and stability checks apply.
4. **Scanned first**
   - Our scan for that folder or identity must have been dispatched to the destination's targets.
5. **Hardlinked files (`nlink > 1`)**
   - Per destination: upload normally (the UI shows "space not reclaimed"), or defer until the file has a single link.

## mtime hygiene
- **Detected problems:** mtimes in the future (more than 5 minutes ahead) and implausibly old ones (before 1990, or 0/1).
- **Fixing them is opt-in.** When enabled:
  - Future-dated local files are touched to the current time.
  - Hardlinked files are never touched.
  - Nothing is touched when the Arr's Change File Date is in use.
- **When fixing is not enabled:**
  - A warning is shown in the UI and logs.
  - The warning points to the SABnzbd `ignore_unrar_dates` setting, or NZBGet's `-tsm-` unrar switch.

## Execution
- **Concurrency:**
  - A global transfer cap, plus an optional cap per remote.
  - Bandwidth is always global through rclone `core/bwlimit`, the same behaviour as the rclone CLI.
- **Failover:**
  - Decided by **remote health**.
  - A remote with repeated failures, or a quota or upload-limit error (for example exit code 7 semantics or `--drive-stop-on-upload-limit`), gets a cooldown.
  - During the cooldown, the destination's files go to its next remote.
- **Retries:**
  - Each file is retried with backoff.
  - The source is never removed unless rclone reports success.
- **Schedule windows:**
  - New transfers start only inside a window.
  - Transfers already in flight finish when the window closes.
- **Throttle:** bandwidth tiers by stream count, plus "pause new uploads" (see the throttle spec).

## Downloaders
- **Supported:** SABnzbd and NZBGet.
- **Conditions,** set per downloader:
  - **while uploads are active:** resume after the queue has been idle for a grace period
  - **disk-space guard:** pause below a free-space threshold
- **Resume is guaranteed:**
  - on error
  - on shutdown
  - by a periodic reconcile, so a crash cannot leave clients paused (cloudplow had that bug)

## Not in v1
- Server-side mover.
- unionfs hidden-file cleaning.
- Service-account rotation.
