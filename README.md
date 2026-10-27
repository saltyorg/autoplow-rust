# Autoplow

Autoplow is a single Rust daemon for [Saltbox](https://saltbox.dev) media servers. It brings together jobs previously split across separate tools:

- **Scan triggers.** Sonarr/Radarr/Lidarr/Whisparr/Bazarr webhooks (managed automatically), local filesystem watching and Google Drive changes feed durable, per-target scan queues for Plex, Jellyfin, Emby, Tdarr, Tofa and other Autoplow instances.
- **Uploads.** Per-file uploads to rclone remotes, with readiness checks: age, stability, open-file detection and hardlink awareness. They run through a supervised `rclone rcd`.
- **Stream-aware throttling.** Upload bandwidth adapts to active media streams.
- **Library parity.** Compares what the Arrs manage with what each media server holds: wrong matches, missing or unmanaged items, file differences.
- **Track preferences.** Remembers each Plex user's audio and subtitle choices per show.
- **Notifications.** Discord, Apprise and generic webhooks.

> **Status:** planning. There is no code yet. See [`docs/`](docs/README.md) for the architecture, specifications and decision records, and [`tasks/plan.md`](tasks/plan.md) for the implementation plan.

## Documentation
| | |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Core architecture |
| [docs/decisions/](docs/decisions/README.md) | Architecture Decision Records |
| [docs/specs/](docs/specs/) | Feature specifications |
| [docs/platform-notes/](docs/platform-notes/README.md) | Verified behaviour of Plex, Jellyfin, Emby, the Arrs and rclone |
| [docs/research/](docs/research/README.md) | Studies of predecessor projects and external APIs |
| [docs/quality-policy.md](docs/quality-policy.md) | Compiler, lint and CI policy |

## Contributing
- **Commits** follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:`, `ci:` …). Releases and the changelog are automated from them.
- **Public docs check:** run `scripts/check-public-docs.sh` before committing. Documentation must not contain environment-specific details ([ADR-0015](docs/decisions/0015-public-documentation-rules.md)).
- **AI agents:** see [CLAUDE.md](CLAUDE.md).

## License
[GPL-3.0](LICENSE)
