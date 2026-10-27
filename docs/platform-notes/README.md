# Platform notes

These are verified behaviours of third-party software that Autoplow depends on. Each note records:
- **The behaviour**, stated plainly.
- **Version(s)** it was verified on.
- **How it was verified:** a live test, a source reading (with file reference), or both.
- **Implication for Autoplow.**

**Rules:**
- Notes describe the *software*, never an environment. No hostnames, IPs, user names, paths of a particular machine, or credentials (enforced by `scripts/check-public-docs.sh`).
- When a later version changes a behaviour, add a new dated entry instead of rewriting history.

| File | Covers |
|---|---|
| [plex.md](plex.md) | Partial scans, deletes, missing paths, sections |
| [jellyfin.md](jellyfin.md) | `Media/Updated` processing, monitor delay, library creation, overlapping libraries |
| [emby.md](emby.md) | `Media/Updated` timing, library deletion API, overlapping libraries |
| [arr.md](arr.md) | Connect (webhook) management lifecycle on Sonarr, Radarr and Lidarr |
| [rclone.md](rclone.md) | RC API behaviour, `rcd` supervision, librclone and config-path gotchas, signal handling |
