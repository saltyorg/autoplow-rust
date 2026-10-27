# ADR-0014: v1 feature scope

## Status
Accepted

## Date
2026-10-27

## Context
Autoplow merges ideas from autoscan, autopulse, cloudplow, matcharr and Plex-Auto-Languages. The predecessor stalled on breadth.

## Decision
**In v1:**
- **Scan triggers into targets:**
  - Triggers: Sonarr, Radarr, Lidarr, Whisparr, Bazarr, generic, legacy endpoints, local filesystem, Google Drive.
  - Targets: Plex, Jellyfin, Emby, Tdarr, another Autoplow, Tofa.
- **Per-file uploads.**
- **Stream-aware throttling.**
- **Library parity** (formerly matcharr).
- **Track preferences** (formerly Plex-Auto-Languages, Plex only).
- **Notifications:** Discord, Apprise, webhook.

**Out of v1:**
- service-account rotation
- the server-side mover
- unionfs hidden-file cleaning
- gating uploads on Plex analysis
- autopulse-style item-refresh scanning ([ADR-0009](0009-folder-level-scans-only.md))

## Consequences
- **Delivery order:** features ship in vertical slices, and a feature's UI comes after its backend works end to end (see `tasks/plan.md`).
- **Provisional:** Tofa support depends on its beta API.
