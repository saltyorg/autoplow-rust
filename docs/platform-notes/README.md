# Platform notes

These are verified behaviours of third-party software that Autoplow depends on. Each note records:
- **The behaviour**, stated plainly.
- **Version(s)** it was verified on.
- **How it was verified:** a live test, a source reading (with file reference), or both. A section built only from documentation and source says so at its top and lists what is still to be checked live.
- **Implication for Autoplow.**

**Rules:**
- Notes describe the *software*, never an environment. No hostnames, IPs, user names, paths of a particular machine, or credentials (enforced by `scripts/check-public-docs.sh`).
- When a later version changes a behaviour, add a new dated entry instead of rewriting history.

| File | Covers |
|---|---|
| [plex.md](plex.md) | Partial scans, deletes, missing paths, sections; sessions; user tokens and track selection (baseline, not yet live) |
| [jellyfin.md](jellyfin.md) | `Media/Updated` processing, monitor delay, library creation, overlapping libraries; sessions (baseline, not yet live) |
| [emby.md](emby.md) | `Media/Updated` timing, library deletion API, overlapping libraries; sessions (baseline, not yet live) |
| [arr.md](arr.md) | Connect (webhook) management lifecycle on Sonarr, Radarr and Lidarr |
| [download-clients.md](download-clients.md) | SABnzbd, NZBGet and qBittorrent pause and limit calls, units, overrides (baseline, not yet live) |
| [rclone.md](rclone.md) | RC API behaviour, `rcd` supervision, librclone and config-path gotchas, signal handling |
