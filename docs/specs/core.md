# Spec: core

**Module:** `core` · **Depends on:** none · **Decisions:** ADR-0005, ADR-0007, ADR-0008, ADR-0010, ADR-0015, ADR-0018 · **Status:** approved 2026-10-27

The configuration, bootstrap and REST API part of `core` is specified in [core-bootstrap-api.md](core-bootstrap-api.md).

## Objective
Provide the foundation every module builds on. A component can be restarted when its config changes, without restarting the process. Work survives restarts. Paths are matched correctly. Everything is observable and controllable over one authenticated API, with the UI shell on top.

## Non-goals
- Multi-node clustering
- Multi-user roles and permissions (v1 has one admin)
- Plugins

## Scope
- **Deployment** ([ADR-0018](../decisions/0018-host-service-deployment.md)):
  - A systemd service on the host, running as the Saltbox user. No container image in v1.
  - **Before the database is open,** these come from the service's environment or command line: the data directory, the listen address and port (default all interfaces, port 3030), and the secret key.
  - **HTTPS** is the reverse proxy's job. Autoplow serves plain HTTP on one port. Session cookies are marked secure when the request reached the proxy over HTTPS.
  - **One instance per data directory:** a lock stops a second copy from starting on the same data.
  - **Time zone:** the host's, with a setting to override it. Upload windows and scheduled checks use it, and the UI shows which one is in use.
- **Capabilities per feature:**
  - A feature that needs more than the service user can do (for example reading which processes hold a file open) names the capability it needs.
  - At start, the feature tests whether it can really work. If not, it switches itself off, the Health page and that feature's page say why, and nothing else is affected.
- **Supervisor:**
  - Every long-running component is an async task, `run(shutdown) -> Result<()>`.
  - A failed or panicked task restarts with backoff: 1 s, doubling to at most 60 s, reset after 10 minutes of running. Repeated restarts raise `component.failing` (see the notifications spec).
  - A config change rebuilds only the components that depend on it.
  - Graceful shutdown has a deadline.
- **Store:**
  - SQLite in WAL mode, one writer and a reader pool.
  - Versioned, tested migrations.
  - Compare-and-set helpers.
  - **Upgrades:** a consistent copy of the database is taken before migrations run. If a migration fails, Autoplow stops and says how to put the copy back.
  - **Downgrades:** a database from a newer Autoplow is refused at start, with a clear message. Nothing is changed.
  - **Backups** *(decided 2026-11-10)*: a failed backup raises `backup.failed`. A consistent copy daily, keeping the last 7 (both configurable), plus on demand from the UI and API. Copies live in the data directory. **Rebuildable data** (Drive snapshots, cached library lists) is left out of every copy, so backups stay small; it stays in the same database so that it can be updated in one transaction with the work it belongs to.
  - **Restoring** *(decided 2026-11-10)*: `autoplow restore <file>`, run on the host as the service user while the service is stopped. It checks that the file is a consistent Autoplow database, refuses one from a newer version, keeps a copy of the current database first, and upgrades an older backup on the next start. Nothing in the UI or API can replace the database.
  - **When the database can't be written** (disk full, read-only): incoming triggers are refused with 503 and `Retry-After`, never accepted and lost. The Health page shows the cause, and work resumes on its own when writing succeeds again.
- **Paths:**
  - `FolderPath`, compared by components.
  - Rewrite rule sets per trigger, per target and per pair, with overlaps rejected within a set.
  - Library containment.
  - The picker backends: a local filesystem browser, and proxies to other modules' listings.
  - **What the filesystem browser shows** *(decided 2026-11-10)*: any folder the service account can read, as folder and file names only. It never returns file contents, never follows a request outside the folder asked for (`..` is refused), and needs an admin session or a full-access key.
- **Auth:**
  - A single admin user (argon2).
  - **Sign-in can be switched off** *(decided 2026-11-10)*, for installs where a reverse proxy already authenticates every browser request. With it off, the UI is given a session without asking for a password. Nothing else changes: a script still needs an API key and a trigger its token. This is not a security boundary, and the setting says so: anyone who can reach the port can open the UI and so has admin access.
  - **Forgotten password:** `autoplow reset-password`, run on the host as the service user, sets a new one and signs out all sessions.
  - API keys, admin or read-only. A key can be regenerated; the old one stops working at once.
  - UI sessions with CSRF protection. A session lasts 30 days from its last use. Signing out ends it, and changing the password ends every other session.
  - **Trusted proxies:** a list of proxy addresses whose forwarded-for header Autoplow believes. It is how Autoplow learns the real client address behind the proxy.
  - **Login rate limit** *(decided 2026-11-10)*: 5 wrong passwords from one client address lock sign-in for that address for 1 minute; each further lockout doubles, up to 15 minutes. Other addresses are unaffected. The sign-in page shows the tries left and the wait.
  - **Secret key** *(decided 2026-11-10)*: every stored secret is encrypted with one key, supplied only through the environment (`AUTOPLOW_SECRET_KEY`); it is never written to the data directory.
    - Without the key, Autoplow refuses to start and says which variable is missing.
    - With the wrong key, it refuses to start before touching any secret (checked against a stored marker).
    - **Rotation:** start once with the new key and the old one in `AUTOPLOW_SECRET_KEY_OLD`; everything is re-encrypted in one transaction, after which the old variable can be removed.
    - A backup is only useful together with its key.
  - Encrypted secret storage, with key rotation that re-encrypts everything. This covers API keys, trigger tokens, target tokens, Arr API keys, notification URLs and Google OAuth client secrets and tokens; only the admin password is hashed.
  - **Secrets are visible to the admin** *(decided 2026-10-30)*. Anyone who can see them already has admin access. Read-only API keys can't read any secret.
    - Every stored secret (API keys, trigger tokens, Arr API keys, target tokens, notification URLs, the OAuth client secret) is masked in its dialog, with a show/hide toggle inside the field so the admin can check it is the right one (see the [UI rules](ui.md)).
    - Lists don't show secrets; the API keys list has a **Copy** button per key.
- **Outbound HTTP client** *(moved here from the targets spec 2026-11-10; every module that calls another service uses it)*:
  - Timeouts: 10 s to connect, 30 s for an answer, adjustable per connection.
  - A response size cap (4 MB by default); anything that can be larger is read in pages.
  - `Retry-After` honoured.
  - Certificate checking on by default, with a per-connection switch.
  - Errors classified as retry later, back off the whole connection, or fail this one item.
  - Tokens never appear in logs, including in request URLs.
- **Update check** *(decided 2026-11-10)*:
  - Once a day Autoplow asks GitHub for the latest release of its own repository, and shows a newer one on Settings › About and the Health page.
  - It sends nothing about the install, raises no notification, and never updates itself; Saltbox does that.
  - A switch under Settings › General turns the check off. A failed check is not a health problem.
- **Versions:** releases follow SemVer over the API, the bootstrap file and database upgrades. Going back to an older version is not supported (see the upgrade copy above).
- **Observability:**
  - `tracing` logs with a level per component, with secrets redacted by type.
  - **Where logs go** *(decided 2026-11-10)*: standard output, for the journal, and a log file. Autoplow rotates the file daily or at 50 MB and keeps the last 7 (configurable). Levels can be changed per component while running. There is no log viewer in the UI in v1.
  - Prometheus `/metrics`, which needs a read-only API key.
  - `/health`, open to anyone and answering only ok or not ok. The detail is on the Health page.
  - An SSE event stream. It does not replay missed events: after a reconnect the UI reloads what it shows. A client too slow to keep up is disconnected and reconnects.
- **UI shell:**
  - Leptos CSR app embedded in the binary: login, navigation, the live event client.
  - Follows the [UI rules](ui.md): tokens, accent, density, the sidebar, and dialog behaviour live in the shell.
  - An API client from `api-types`.

## Events raised
These are the notification types this module raises (the catalogue is in [notifications.md](notifications.md)).
- `component.failing`: a background component keeps restarting.
- `backup.failed`: a backup could not be taken.

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
6. API keys work only with the correct scope. A wrong key gets 401, a read-only key on a write endpoint gets 403, and a read-only key asking for any secret gets 403. A regenerated key replaces the old one immediately. The fifth wrong password locks sign-in for 1 minute, doubling to at most 15 minutes.
7. No log line, metric label or API response contains a secret (test that greps output under a seeded secret). The one exception is the admin-only endpoints that return a stored secret when it is asked for.
8. Steady-state RSS with an empty configuration is ≤ 64 MB, and idle CPU is ≤ 1 % of one core.
9. The UI shell passes the Playwright login test and has zero serious or critical axe violations.
10. Without `AUTOPLOW_SECRET_KEY`, or with a wrong one, Autoplow refuses to start and changes nothing. Starting with a new key and the old one in `AUTOPLOW_SECRET_KEY_OLD` re-encrypts every secret, and the old key then no longer works.
11. With sign-in switched off, opening the UI gives a session without a password; an API request with neither a session nor a key still gets 401, and a trigger route without its token is still refused.
12. `autoplow reset-password` sets a new password and ends all sessions. Changing the password in the UI ends every other session.
13. A lockout caused by one client address does not affect another. Behind a trusted proxy the forwarded address is used; a forwarded header from an untrusted address is ignored.
14. A copy of the database is taken before migrations and daily, without the rebuildable data; only the configured number is kept; a backup on demand produces a file that opens as a consistent database. A database from a newer version is refused at start.
15. With the database unwritable, a trigger request gets 503 with `Retry-After` and nothing is acknowledged; when writing works again, requests succeed without a restart.
16. A second instance started on the same data directory exits with a clear message and changes nothing.
17. `/health` answers without credentials and reveals no detail; `/metrics` without a key gets 401.
18. The log file rotates by age and size and keeps only the configured number; a component's log level changed through the API applies without a restart.
19. A feature whose required capability is missing reports itself as off, with the reason, on the Health page, and the rest of Autoplow runs normally.
20. The outbound client enforces its timeouts and size cap, honours `Retry-After`, refuses a self-signed certificate unless that connection's check is switched off, and never logs a token.
21. With the update check on, a newer release is shown on About and Health within a day and no notification is raised; with it off, no request is made. The request carries nothing that identifies the install.
22. `autoplow restore` refuses to run while the service is running, refuses a file that is not a consistent Autoplow database or comes from a newer version, and keeps a copy of the database it replaces. After a restore and start, the restored data is served.
23. The filesystem browser lists names in a readable folder, returns no file contents, refuses a path containing `..`, and answers 403 to a read-only key.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; keep wall-clock time behind the `Clock` trait.
- **Ask first:** changing the auth model or the secret-encryption scheme.
- **Never:** block a supervisor-managed task on synchronous I/O without `spawn_blocking`; log secrets.

## Open questions
- Shutdown deadline default (**decided 2026-10-27:** 30 s). systemd's default stop timeout (90 s) is longer, so the example unit needs no change.
