# ADR-0009: Folder-level partial scans as the only scan approach

## Status
Accepted

## Date
2026-10-27

## Context
- Two approaches were measured on Plex, Jellyfin 12.3.0 and Emby 4.10.2 (see `docs/platform-notes/`):
  - **A, folder-level:** a Plex `refresh?path=` per folder; Jellyfin/Emby `Media/Updated` with folder paths, batched.
  - **B, autopulse-style:** a refresh per file, plus item refresh/analyze.
- **Findings:**
  - **B was never faster.** Plex was about 1 s for both. Jellyfin and Emby are bounded by their own monitor delay (about 60 s and 90 s).
  - **B costs more:** 10 identical Plex requests for a season pack, and library walks on Jellyfin/Emby.
  - **B broke deletes on Jellyfin and Emby:** refreshing a deleted file's item doesn't remove it.

## Decision
Approach A is the only scan mode:
- Scan the file's parent folder.
- A queued parent absorbs its children.
- Batch where the target supports it.

## Alternatives Considered
- **B as an optional mode:** rejected; no benefit and a correctness regression.

## Consequences
- The UI documents the Jellyfin and Emby processing delays.
- **Optional checks to add:**
  - "path must exist before delivery", because Plex ignores partial scans for paths it doesn't know yet
  - post-delivery verification, because servers can accept scans and index nothing
