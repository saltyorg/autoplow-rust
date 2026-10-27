# Upload readiness: torrent hardlinks, copy fallback, usenet mtimes, Plex

This research was done from source on 2026-10-26, using Sonarr v5 develop, Radarr develop, libtorrent RC_2_0 and RC_2_1, Transmission, rakshasa libtorrent, SABnzbd, NZBGet and the .NET runtime. Key Sonarr claims were spot-checked against the source.

## Sonarr/Radarr import transfer
- **How the mode is chosen** (Auto mode):
  - The import is copy-only when the download client reports `CanMoveFiles == false` (`ImportApprovedEpisodes.cs:109-121`).
  - **Usenet clients always allow moving**, so usenet imports are a **move**.
  - **Torrent clients allow moving only if "Remove Completed" is on and seeding has finished.** Otherwise the import is a **copy**.
  - A copy becomes **hardlink-or-copy** when `CopyUsingHardlinks` is on, which is the default.
  - In practice, a torrent that is still seeding gets a **hardlink**, and a usenet download gets a **rename/move**.
- **Hardlink fails** (EXDEV, for example separate Docker volumes or different mergerfs branches): Sonarr falls back to a **copy written straight to the final library path** (`DiskTransferService.cs:319-352`).
  - There is no temp name and no `.partial~`.
  - .NET opens the destination with `O_RDWR|O_CREAT|O_EXCL` and holds `flock(LOCK_EX)` while writing.
  - After the copy it sets the **source mtime** using futimens, verifies the file by reading it back, and then applies "Change File Date".
  - **During the copy, a partial file sits at the final path with a fresh mtime.**
- **Move:** Sonarr tries `rename()` first. On EXDEV it copies and then deletes the source. **mtime is kept in every case.** A rename or link bumps ctime.
- **"Change File Date"** (default None):
  - In Sonarr it sets mtime to the air date after every import and again on every series rescan.
  - In Radarr it uses the release or cinema date.
  - Either way, **mtime can be years in the past the moment the import finishes**, which defeats any age check based on mtime. On a hardlink it also changes the torrent client's copy of the file, because both links share one inode.

## Torrent clients while seeding
| Client | Payload files while seeding |
|---|---|
| libtorrent 2.0 (qBittorrent 4.4+/5.x, Deluge 2) | mmap backend by default on 64-bit. When a torrent finishes, its files are released and then reopened **read-only** on demand (LRU pool of 40). The fd stays open alongside the `MAP_SHARED` mapping. The POSIX backend opens and closes the file for every operation. |
| libtorrent 2.1 | pread/pwrite with a file pool, no mmap. |
| Transmission | Closes files when they complete and reopens them **read-only**. |
| rTorrent | Can keep an **`O_RDWR` fd from downloading while seeding** until it is evicted or the download is closed. Reads go through mmap. |

What this means for us:
- **A hardlinked library file shares its dev+inode with the seeding file.** Blocking the upload on *any* open would block it for the whole seeding period.
- **Reading the file while it seeds is safe**, because the payload no longer changes. Deleting our path only removes our name, so the torrent keeps its link and its open fd.
- **Uploading a hardlinked file frees no disk space** until the torrent is removed as well (`st_nlink > 1`).
- **Touching mtime on a hardlinked inode can trigger a re-verify** in Transmission and rTorrent.
- **Containers see files through mergerfs.** A client's fd therefore stats to the **mergerfs dev+inode** (`/mnt/unionfs`), not the `/mnt/local` one. The mergerfs daemon holds the real backing fd, opened with the caller's flags. **Check mergerfs FUSE passthrough on Saltbox's version**, because with passthrough the kernel may hold the backing file without a visible fd.

## Usenet mtimes
- Plain files and par2-repaired files get roughly the download time as their mtime.
- **Files extracted from archives keep the mtime stored in the archive**, which can be years old, 0/1970, or in the future.
  - SABnzbd uses `unrar -ai` without `-tsm-` unless the hidden `ignore_unrar_dates` setting is enabled. 7z also keeps archive times.
  - NZBGet uses `unrar -y -ai -o+`; the user must add switches in `UnrarCmd`.
- Sonarr's move keeps the bad mtime unless "Change File Date" overwrites it.

## Plex
- There is no official documentation on this.
- **Future mtimes are demonstrably harmful:** items get a future "Date Added" and stay stuck at the top of Recently Added. Running `touch` afterwards doesn't fix the database.
- Past mtimes are mostly harmless.
- References: forums.plex.tv/t/233254, /t/457933, /t/802268.

## Recommended readiness rules
1. **The age clock is `now - max(firstSeen, ctime)`, never mtime alone.**
   - `firstSeen` is our own record of when we first saw the file's identity (dev, ino, size).
   - ctime can't be set from userspace, and links, renames, writes and utimes all update it.
2. **Stability:** (size, mtime, ctime, nlink, ino) must be unchanged across at least 2 checks spaced at least N seconds apart. Any change resets `firstSeen`.
3. **mtime sanity:** an mtime more than 5 minutes in the future, or before 1990 (or 0/1), is flagged and logged. It never blocks the upload beyond rule 1.
4. **Open detection blocks only on write intent.**
   - Scan `/proc/*/fd`, stat each magic link, and match by dev+ino against **both** the `/mnt/local` identity and the mergerfs identity.
   - Block when `fdinfo` flags have an `O_ACCMODE` of `O_WRONLY` or `O_RDWR`.
   - Also block on WRITE locks in `/proc/locks`, which catches Sonarr's copy fallback.
   - Optionally block on `rw-s` mappings in `/proc/*/maps`.
   - Read-only opens never block: Plex, seeding, mediainfo.
5. **Escape hatch:** an rTorrent or mergerfs `O_RDWR` handle on a long-stable file with `nlink > 1`, held by a known torrent client or by mergerfs, is allowed after a long window (30–60 min). The decision is logged.
6. **Hardlinked files (`nlink > 1`):** uploading them is safe but frees no space. Show a "space not reclaimed" metric, and give them lower priority when space is short.
7. **"Scanned first"** keys on the file's identity, not just its path.
8. **Normalising bad mtimes** is off by default. If it is enabled:
   - Only future mtimes, optionally also ones before 1990, and only when `nlink == 1`.
   - Never touch a hardlinked file.
   - Never touch files when the Arr's "Change File Date" is in use.
   - A better option is to correct the **remote** modtime after upload (`rclone touch`) and/or tell users to enable SAB `ignore_unrar_dates` or NZBGet `-tsm-`.
