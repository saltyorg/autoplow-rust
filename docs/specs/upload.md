# Spec: the upload pipeline (v1)

**Module:** `upload` · **Depends on:** core, rclone, scan, notifications · **Decisions:** ADR-0003, ADR-0011 · **Status:** approved 2026-10-27

## Objective
Move finished local media to the user's rclone remotes per file, only once it is ready (age, stability, not being written, scanned), without stalling on seeding torrents, and without ever removing a source that was not confirmed uploaded.

## Non-goals
- Service-account rotation
- Server-side mover
- Folder-size thresholds (cloudplow model)
- Defining rclone remotes (the user's rclone.conf owns them)

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

## Acceptance criteria
1. A file becomes eligible only after its readiness rules pass; any mtime change restarts its age clock.
2. A file held open for writing (or write-locked) by any process is not uploaded while the optional open-file check is active; a read-only open (e.g. a seeding torrent client, Plex) does not block.
3. Without `pid: host`/`SYS_PTRACE`, the UI states that only age and stability checks apply; uploads still work.
4. Two files with identical basenames in different folders in one batch are tracked and completed independently.
5. The source file is removed only after rclone reports the transfer successful; a cancelled or failed transfer leaves the source intact and the entry retried with backoff.
6. Killing the rclone child mid-transfer leads to restart and re-queue; the file is uploaded exactly once after recovery.
7. A remote returning quota/upload-limit errors is put on cooldown and the destination's next remote is used until the cooldown ends.
8. Outside a schedule window no new transfer starts; transfers in flight finish.
9. Hardlinked files follow the destination's policy (upload, reported as 'space not reclaimed', or defer while `nlink > 1`).
10. SABnzbd/NZBGet paused by Autoplow are always resumed: after uploads go idle (grace period), on error, on shutdown, and by periodic reconcile after a crash.
11. Sustained 10 TB/day across remotes completes without Autoplow exceeding its resource budget (project.md).

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Touching (normalising) local file mtimes beyond the opt-in rule; Supporting additional downloaders.
- **Never:** Delete a source without a confirmed successful transfer; Touch a hardlinked file's mtime; Write to the user's rclone.conf.

## Open questions
- Default readiness values (**decided 2026-10-27:** age 2 min, stability 2 checks 30 s apart).
