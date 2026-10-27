# Autoplow documentation

| Path | What it holds |
|---|---|
| [architecture.md](architecture.md) | Core architecture |
| [decisions/](decisions/README.md) | Architecture Decision Records (why things are the way they are) |
| [specs/](specs/README.md) | Capability map, project-level spec and one spec per module |
| [platform-notes/](platform-notes/README.md) | Verified behaviour of Plex, Jellyfin, Emby, the Arrs and rclone, with versions |
| [research/](research/README.md) | Studies of predecessor projects and external APIs |
| [quality-policy.md](quality-policy.md) | Compiler, lint and CI policy for the workspace |

**Rule:** nothing environment-specific goes into this repository ([ADR-0015](decisions/0015-public-documentation-rules.md)). Run `scripts/check-public-docs.sh` before committing.
