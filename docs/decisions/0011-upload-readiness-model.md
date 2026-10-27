# ADR-0011: Per-file upload readiness model

## Status
Accepted

## Date
2026-10-26

## Context
Research (see `docs/research/upload-readiness.md`) found that file mtime is unreliable and open-file checks need care:
- **mtime:**
  - Sonarr/Radarr "Change File Date" sets mtime to the air or release date.
  - Archive extraction keeps archive timestamps, which can be in the future.
- **Torrent imports:**
  - **While seeding:** a hardlink. The torrent client keeps the shared inode open, usually read-only.
  - **When hardlinking fails:** a copy written in place with a write lock.
- **rTorrent** may hold read-write handles while seeding.

## Decision
- **Uploads are per file** to destinations (an ordered list of remotes).
- **Readiness options:**
  - **Age:** counted from Autoplow's first-seen time, and restarted whenever mtime changes.
  - **Size stable.**
  - **Not open for writing:** write-mode handles and write locks only, matched by dev+inode for both local and mergerfs identities. It identifies the process and container holding the file, and can optionally wait while a media server has it open. This check is **optional**, because it needs `pid: host` and `SYS_PTRACE`.
  - **Scanned first.**
  - **Hardlinked files:** upload normally or defer, per destination.
- **Future-dated mtimes:** fixing them locally is opt-in, otherwise Autoplow warns. Hardlinked files are never touched.
- **Failover** is based on remote health with a cooldown.
- **Bandwidth** is global (`core/bwlimit`), with a global transfer cap and optional per-remote caps.
- **Schedule windows** let transfers already running finish.

## Alternatives Considered
- **Folder size thresholds** (cloudplow).
- **Gating on Plex analysis** (predecessor): fragile title matching; dropped.
- **Service-account rotation:** out of scope.

## Consequences
- Accurate open-file detection depends on deployment privileges. Without them, the UI says only age and stability apply.
