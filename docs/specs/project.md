# Spec: Autoplow (project level)

**Status:** approved 2026-10-27 (spec-driven-development, Phase 1).

## Objective
Autoplow is a single daemon that keeps a Saltbox media stack consistent and moving. It takes over these jobs:
- **autoscan / autopulse:** tell media servers exactly what changed.
- **cloudplow:** move finished media to cloud storage without disturbing playback.
- **matcharr:** keep media-server matches and files in parity with the Arr apps.
- **Plex-Auto-Languages:** remember each viewer's audio and subtitle choices.

**Users:**
- **Primary:** Saltbox users, a single admin per install. Saltbox's Ansible role seeds the configuration once (ADR-0007), and the admin then uses the web UI and API.
- **Secondary:** self-hosters running Plex/Jellyfin/Emby and the Arrs on Linux with Docker, outside Saltbox. Supported on a best-effort basis: same features, no Saltbox-specific defaults.

**v1 success** (the user story behind each item):
1. **Replaces autoscan/autopulse.** Every trigger and target they support for Saltbox users works. That includes Arr webhooks, the legacy endpoints, Bazarr, the local filesystem and Drive, delivering to Plex, Jellyfin, Emby, Tdarr and another Autoplow, with no lost scans across restarts.
2. **Replaces cloudplow.** Local media is uploaded to rclone remotes with the readiness, throttling and downloader-pausing behaviour in [upload.md](upload.md) and [throttle.md](throttle.md).
3. **Replaces matcharr and Plex-Auto-Languages.** Library parity and track preferences cover their functionality ([parity.md](parity.md), [track-preferences.md](track-preferences.md)).

**Non-goals for v1:**
- service-account rotation
- server-side mover
- unionfs hidden-file cleaning
- gating uploads on Plex analysis
- autopulse-style item-refresh scanning
- multi-user or RBAC administration
- Windows or macOS hosts
- a migration tool for importing cloudplow/autoscan config files (the webhook migration helper is a feature, not a v1 success criterion)

**Scale targets** (a large home server; derived from a real install, with headroom):
| Dimension | v1 must handle comfortably |
|---|---|
| Media under management | ≥ 300 TB |
| Media servers | ≥ 3 (Plex, Tofa and one of Jellyfin/Emby concurrently) |
| Arr instances | ≥ 8 (several Sonarr and Radarr variants, plus Lidarr) |
| Library size | ≥ 500 000 items per server |
| Webhook and trigger events | ≥ 20 000 per day, with bursts of ≥ 1 000 per minute |
| Upload volume | ≥ 10 TB per day across remotes |
| Daemon resource use | ≤ 256 MB RSS steady-state for Autoplow itself (excluding the rclone child), ≤ 5 % of one CPU core when idle |

## Tech stack
Decided in ADR-0003 to ADR-0006 and ADR-0008:
- **Language:** Rust (stable, pinned) with tokio.
- **HTTP and API:** axum + utoipa for the API, reqwest (rustls) for outbound calls.
- **Storage:** rusqlite (bundled SQLite, WAL).
- **UI:** Leptos (CSR, trunk), sharing an API-types crate with the backend.
- **rclone:** a supervised `rclone rcd` child process.
- **Targets:** Linux x86_64 and aarch64, as static musl binaries, plus a container image.

## Commands
These are planned and wired in Task 0.1; `CONSTRAINTS.md` is canonical.
```
Build:        cargo build --workspace --release
UI build:     trunk build --release            (in crates/ui)
Run (dev):    cargo run -p autoplow -- --config ./dev/config --bootstrap ./dev/bootstrap.yml
Tests:        cargo nextest run --workspace
Coverage:     cargo llvm-cov nextest --lcov --output-path lcov.info && diff-cover lcov.info --compare-branch=origin/main --fail-under=90
Mutation:     cargo mutants --in-diff <(git diff origin/main) && scripts/check-mutants.sh mutants.out 80
Lint:         cargo clippy --workspace --all-targets --all-features -- -D warnings
Format:       cargo fmt --all --check
Security:     cargo deny check && gitleaks detect --redact --no-banner
UI e2e:       npx playwright test                (in e2e/)
Floor guard:  node scripts/floor-guard.mjs --base origin/main
Docs guard:   scripts/check-public-docs.sh && scripts/check-links.sh
Task end:     scripts/check-task.sh               (runs everything above; no time budget)
```

## Project structure
```
crates/autoplow/        → binary: CLI, wiring, supervisor bootstrap
crates/<module-id>/     → one library crate per module in docs/specs/README.md
                          (core, notifications, targets, arr, scan, gdrive, rclone,
                           upload, throttle, parity, track-preferences)
crates/api-types/       → serde types shared by the API and the UI
crates/ui/              → Leptos web UI (embedded into the binary)
crates/<id>/tests/      → integration tests per module (fake servers, real SQLite)
e2e/                    → Playwright UI tests
docs/                   → architecture, specs, ADRs, platform notes, research
scripts/                → check scripts used by CI and agents
tasks/                  → implementation plan and task list
```

## Code style
Rules:
- rustfmt defaults.
- Every lint in [quality-policy.md](../quality-policy.md).
- Typed errors per crate (`thiserror`). `anyhow` only in `crates/autoplow`.
- Newtypes for identifiers and paths.
- Exhaustive matches.
- No panics outside tests.
- Wall-clock time through an injected `Clock`.

Example:
```rust
/// A folder path, compared by components (ADR-0010).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct FolderPath(Vec<String>);

#[derive(Debug, thiserror::Error)]
pub enum PathError {
    #[error("path must be absolute: {0}")]
    NotAbsolute(String),
    #[error("path must not contain `..`: {0}")]
    ParentTraversal(String),
}

impl FolderPath {
    pub fn parse(raw: &str) -> Result<Self, PathError> {
        if !raw.starts_with('/') {
            return Err(PathError::NotAbsolute(raw.to_owned()));
        }
        let mut parts = Vec::new();
        for part in raw.split('/').filter(|p| !p.is_empty() && *p != ".") {
            if part == ".." {
                return Err(PathError::ParentTraversal(raw.to_owned()));
            }
            parts.push(part.to_owned());
        }
        Ok(Self(parts))
    }

    /// True if `self` is `other` or lies inside it. Never a raw string prefix.
    #[must_use]
    pub fn is_within(&self, other: &Self) -> bool {
        self.0.starts_with(&other.0)
    }
}
```

## Testing strategy
- **Unit tests** sit next to the code: pure logic, a paused tokio clock, and an injected `Clock`.
- **Integration tests** live in `crates/<id>/tests/` and use real SQLite plus recorded or fake HTTP servers for every external API. Contract fixtures come from `docs/platform-notes/` behaviours.
- **Property tests** (proptest) cover path normalisation, rewrite rules and the queue state machines.
- **End-to-end UI tests** use Playwright with axe accessibility checks.
- **Live tests** (`live` feature, ignored by default):
  - They run against real servers, configured only through environment variables, one server at a time, under resource caps.
  - They are run before each release, not in CI.
- **Thresholds:** see `CONSTRAINTS.md` (changed-line coverage ≥ 90 %, mutation score ≥ 80 %).

## Boundaries
- **Always:**
  - Follow `CONSTRAINTS.md` and the agent-skills workflow.
  - Validate all external input (webhooks, API bodies, config) at the boundary.
  - Keep work durable: never drop a queued event.
  - Write ADRs for significant decisions.
- **Ask first:**
  - adding a dependency outside the approved stack
  - schema or migration changes after a release
  - new public API endpoints or breaking API changes
  - changing CI or gate configuration
  - anything that writes to a user's Arr, media server or rclone config beyond what a spec defines
- **Never:**
  - commit secrets or environment details
  - weaken constraints to pass
  - delete or skip tests without approval
  - log tokens or credentials
  - run heavy builds or live tests uncapped
  - modify connections or config owned by other tools

## Success criteria (project level)
1. Every module's acceptance criteria pass, in its spec under `docs/specs/`.
2. The scale targets above hold, measured by a load test at the end of each phase that touches the hot path (`scan`, `upload`, `throttle`).
3. A Saltbox install can switch off autoscan, cloudplow, matcharr and Plex-Auto-Languages and keep equivalent behaviour. Verified by the live test suite plus a written checklist per tool.
4. `CONSTRAINTS.md` gates pass on `main` at every commit.

## Open questions
1. ~~Scale targets~~ **Decided 2026-10-27:** as listed above.
2. ~~Hosts without uploads~~ **Decided 2026-10-27:** `upload` is optional per install and configuration-driven.
3. **Tofa** stays provisional until its websocket and library-roots API are verified against a running server.
