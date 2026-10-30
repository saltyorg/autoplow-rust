# Spec: core

**Module:** `core` · **Depends on:** none · **Decisions:** ADR-0005, ADR-0007, ADR-0008, ADR-0010, ADR-0015 · **Status:** approved 2026-10-27

The configuration, bootstrap and REST API part of `core` is specified in [core-bootstrap-api.md](core-bootstrap-api.md).

## Objective
Provide the foundation every module builds on. A component can be restarted when its config changes, without restarting the process. Work survives restarts. Paths are matched correctly. Everything is observable and controllable over one authenticated API, with the UI shell on top.

## Non-goals
- Multi-node clustering
- Multi-user roles and permissions (v1 has one admin)
- Plugins

## Scope
- **Supervisor:**
  - Every long-running component is an async task, `run(shutdown) -> Result<()>`.
  - A failed or panicked task restarts with backoff. Repeated restarts raise `component.failing` (see the notifications spec).
  - A config change rebuilds only the components that depend on it.
  - Graceful shutdown has a deadline.
- **Store:**
  - SQLite in WAL mode, one writer and a reader pool.
  - Versioned, tested migrations.
  - Compare-and-set helpers.
- **Paths:**
  - `FolderPath`, compared by components.
  - Rewrite rule sets per trigger, per target and per pair, with overlaps rejected within a set.
  - Library containment.
  - The picker backends: a local filesystem browser, and proxies to other modules' listings.
- **Auth:**
  - A single admin user (argon2).
  - API keys stored hashed, admin or read-only.
  - UI sessions with CSRF protection and a login rate limit.
  - Encrypted secret storage, with key rotation that re-encrypts everything.
- **Observability:**
  - `tracing` logs with a level per component, with secrets redacted by type.
  - Prometheus `/metrics`.
  - An SSE event stream.
  - `/health` and readiness.
- **UI shell:**
  - Leptos CSR app embedded in the binary: login, navigation, the live event client.
  - An API client from `api-types`.

## Acceptance criteria
1. Killing a component task, or making it panic, leads the supervisor to restart it with backoff while other components keep running. A panic is logged with the component name. A third restart within 10 minutes raises `component.failing`.
2. Changing a target's URL through the API takes effect for the next delivery, with no process restart and no lost queue entries.
3. SIGTERM drains or persists in-flight state and exits within the shutdown deadline (default 30 s).
4. Migrations apply on an empty database and on every released schema version (test fixtures per version).
5. The `FolderPath` and rewrite property tests pass:
   - `/mnt/Movies` vs `/mnt/Movies4K`
   - trailing slashes
   - `..` rejected
   - overlapping rules rejected
6. API keys work only with the correct scope. A wrong key gets 401, a read-only key on a write endpoint gets 403. Login is rate-limited.
7. No log line, metric label or API response contains a secret (test that greps output under a seeded secret).
8. Steady-state RSS with an empty configuration is ≤ 64 MB, and idle CPU is ≤ 1 % of one core.
9. The UI shell passes the Playwright login test and has zero serious or critical axe violations.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; keep wall-clock time behind the `Clock` trait.
- **Ask first:** changing the auth model or the secret-encryption scheme.
- **Never:** block a supervisor-managed task on synchronous I/O without `spawn_blocking`; log secrets.

## Open questions
- Shutdown deadline default (**decided 2026-10-27:** 30 s).
