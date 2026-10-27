# ADR-0010: Component-based path matching and scoped rewrite rules

## Status
Accepted

## Date
2026-10-26

## Context
- Predecessors matched path prefixes as raw strings (`/mnt/Movies` matched `/mnt/Movies4K`), or resolved overlaps by longest match. Both led to the wrong library being scanned, or several.
- Saltbox setups mix container paths, mergerfs and rclone mounts, so mappings can differ completely between applications.

## Decision
- **Matching:** paths are cleaned and compared **by component**. Trailing slashes don't matter.
- **Rewrite rule sets** exist per trigger, per target, and per trigger→target pair. A pair's own set **replaces** the target's set for that pair. Overlapping sources **within one set** are rejected.
- **No longest-match logic anywhere**, and that includes anchors.
- **Library resolution:** a folder is scanned in exactly the libraries whose locations contain it by components. That is the same set the server would index.
- **Entering mappings:**
  - a filesystem picker per side (Arr filesystem API, Emby/Jellyfin directory listing, Tofa folders, local browser)
  - **evidence-based** suggestions: derived from the same file seen by both an Arr and a server, and confirmed by the user

## Alternatives Considered
- **Longest-match or first-match precedence:** implicit and error-prone.
- **Name-similarity suggestions:** unreliable with mergerfs and container paths.

## Consequences
- **Server differences:** overlapping library locations behave differently per server (Plex indexes both; Jellyfin outer only; Emby inner only), so the UI warns on Jellyfin and Emby.
