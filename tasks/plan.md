# Implementation Plan: Autoplow

## Overview
Autoplow is a single **Rust** binary for Saltbox. It combines:
- **Scan triggers into durable per-target scan queues:** an autoscan/autopulse successor.
- **Per-file uploads through a supervised `rclone rcd`:** a cloudplow successor.
- **Stream-aware throttling.**
- **Library parity:** formerly matcharr.
- **Track preferences:** formerly Plex-Auto-Languages.
- **Notifications.**
- **A seed-once bootstrap file plus an idempotent REST API** for Ansible.
- **An embedded SPA UI.**

Inputs:
- the specs in `docs/specs/`
- the architecture in `docs/architecture.md`
- the ADRs in `docs/decisions/`
- verified platform behaviour in `docs/platform-notes/`

## Architecture decisions (summary; details in docs/decisions/)
- **Rust, Linux only.** The binary is static musl, for x86_64 and aarch64.
- **rclone runs as a supervised `rclone rcd` child** on a private unix socket. Remotes come from the user's `rclone.conf`.
- **Panic policy:**
  - Clippy denies `unwrap`, `expect`, `panic`, indexing, `todo` and `unimplemented` outside tests.
  - `forbid(unsafe_code)`.
  - Typed errors (`thiserror`).
  - Supervised tasks catch panics as a last resort.
- **Proposed crate stack** (to confirm in Task 0.1):

  | Area | Crates |
  |---|---|
  | Runtime | tokio |
  | HTTP server and API | axum + utoipa (OpenAPI) |
  | HTTP client | reqwest (rustls with the `ring` provider, for easy musl/arm64 builds) |
  | WebSockets | tokio-tungstenite |
  | SQLite | rusqlite `bundled`: one writer thread plus a reader pool, migrations with rusqlite_migration |
  | Config | serde + serde-saphyr (YAML with line/column errors) + schemars (JSON Schema) + garde (validation) |
  | Filesystem watching | notify |
  | /proc | procfs, plus a small fdinfo parser |
  | Google | oauth2, plus a hand-written Drive Changes client |
  | Logging and metrics | tracing, prometheus-client |
  | Secrets and crypto | secrecy, argon2, aes-gcm |
  | UI | **Leptos** (CSR, trunk, wasm-opt), Playwright end-to-end tests |
  | SPA embedding | rust-embed |
  | Builds | cargo-zigbuild |
- **SQLite (modernc, pure Go) in WAL mode:** one writer and a pool of readers. Migrations are versioned and tested. Dedup is enforced by the database (unique partial indexes) and status writes use compare-and-set.
- **Every component implements `Run(ctx) error` under a supervisor** that rebuilds only the affected components when config changes. No process restarts.
- **Paths are compared by component.** Rewrite rule sets are scoped per trigger, per target and per pair, overlapping rules within a set are rejected, and longest-match is never used.
- **One durable queue per target.** Entries are acknowledged by generation, delivered FIFO by ready time, scanned at folder level (approach A only), and batched where the target supports it.
- **REST API first.** The UI uses only the public API and SSE.

## Task list
The detailed tasks, with acceptance criteria and verification, are in [todo.md](todo.md). Phases are ordered so that each one leaves a working binary and the highest-risk pieces come early.

| Phase | Module | Outcome |
|---|---|---|
| 0 | `core` | Workspace, constraints tooling, store, supervisor, paths, config/bootstrap, API/auth, observability, UI shell |
| 1 | `notifications` | Durable outbox; Discord, Apprise and webhook channels |
| 2 | `targets` | Plex, Jellyfin, Emby, Tdarr, Autoplow and (provisional) Tofa clients |
| 3 | `arr` | Arr client, webhook receiver and parsers, managed connections, migration helper |
| 4 | `scan` | Triggers, per-target durable queues, delivery, anchors, verification, filesystem trigger, load test |
| 5 | `rclone` | Supervised `rcd` and RC client, crypt `decode` |
| 6 | `gdrive` | OAuth accounts; snapshot plus Changes API monitors; crypt remotes, change log, controls, snapshot browser |
| 7 | `upload` | Per-file queue, readiness, open-file detection, failover, schedules, downloaders, soak test |
| 8 | `throttle` | Session registry and bandwidth policies |
| 9 | `parity` | Engine, fixes, review UI |
| 10 | `track-preferences` | Matching, per-user preferences, UI |
| 11 | Release | Container, release pipeline, replacement checklists |

Phases follow the approved build order in `docs/specs/README.md`. Every task traces to numbered acceptance criteria in its module spec.

A checkpoint after each phase requires: tests green, build clean, a demo of the phase outcome, and a human review.

## Testing strategy
- **Unit tests** use `tokio::time::pause` plus an injected `Clock` trait for wall-clock (`SystemTime`) logic, covering every timer-based behaviour.
- **Fake HTTP servers** stand in for Plex, Jellyfin, Emby, Tofa, the Arrs, SABnzbd and NZBGet.
- **Pipeline tests** run against real SQLite.
- **The rclone transport is tested against a real `rclone rcd`** with the local and crypt backends, including child crash and restart.
- **Live-server tests** sit behind a cargo feature or ignored tests (`live`) and read endpoints and credentials only from environment variables. They run one server at a time, under `systemd-run` memory and CPU caps, with unbuffered progress output.

## Risks and mitigations
| Risk | Impact | Mitigation |
|---|---|---|
| rclone child crashes or misbehaves | Low | Supervision, health checks, re-queue from our database; the child is isolated from Autoplow. |
| Jellyfin/Emby quirks (monitor delay; empty-folder libraries silently drop updates) | Med | Post-delivery verification, UI notes, target health warnings. |
| Plex partial scans are lost when the path doesn't exist yet | Med | The "path must exist before delivery" check, with retry. |
| Open-file detection needs `pid: host` and `SYS_PTRACE` | Med | Make it optional and degrade to the age and size-stable checks, with a UI notice. |
| Tofa's API is in beta, lacks a library-roots endpoint and its websocket isn't documented | Med | Build the Tofa target last, behind capabilities. Verify against a running Tofa server. |
| More hand-written clients (no Rust Drive/Arr/Plex libraries) | Med | Narrow typed clients per target, each with contract tests against recorded fixtures and live tests. |
| Rust compile times on the shared host | Low | Capped builds (`systemd-run`), sccache, incremental debug builds. |
| The scope is large: autoplow v1 stalled on breadth | High | Vertical slices, and no UI for a feature until its backend is wired end to end. Checkpoints with review. |
| Shared production test host | High | Live tests always run capped and one server at a time; check processes by memory before attributing any load. |

## Open questions
- ~~Default timings~~ decided in the module specs (scan: 30 s minimum age, 10 min maximum wait; upload: 2 min age, 2 stability checks 30 s apart).
- **Tofa research,** pending verification against a running Tofa server: library roots, the websocket, the webhook trigger, TVDB IDs.
