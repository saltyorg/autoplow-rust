# Spec: core

**Module:** `core` · **Depends on:** none · **Decisions:** ADR-0005, ADR-0007, ADR-0008, ADR-0010, ADR-0015, ADR-0018, ADR-0019 · **Status:** approved 2026-10-27

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
  - **Low disk space:** Autoplow keeps a small reserve in the data directory (64 MB, not configurable) and gives it up when the disk fills, so it can go on recording what uploads do; uploads are what frees space. A backup that would not fit is skipped and reported as `backup.failed`. A transfer whose result cannot be recorded is checked against the remote at the next start before its file is touched again.
  - **After a restore:** notifications still waiting to be sent that are older than the restore are discarded, not sent; sessions are cleared; Autoplow's record of having paused a download client is cleared; Drive monitors rebuild their snapshots. The secret key is checked against the restored file by the command itself.
- **Time:**
  - Waits and backoff that live only in memory are measured on a clock that never jumps. Anything that must survive a restart (a cooldown, a manual override, a session, a file's first-seen time, retention) is stored as a wall-clock time. Scheduled times use the wall clock.
  - A scheduled time that does not exist on a day (clocks go forward) runs at the next valid minute; one that occurs twice runs once.
  - **Missed schedules:** a scheduled check, sweep or backup that was due while Autoplow was down runs once at start, if it is less than a day late.
  - Retention removal never runs in the first 10 minutes after start, so a host that boots with a wrong clock does not prune early.
- **Paths:**
  - `FolderPath`, compared by components.
  - Rewrite rule sets per trigger, per target and per pair, with overlaps rejected within a set.
  - Library containment.
  - The picker backends: a local filesystem browser, and proxies to other modules' listings.
  - **What the filesystem browser shows** *(decided 2026-11-10)*: any folder the service account can read, as folder and file names only. It never returns file contents, never follows a request outside the folder asked for (`..` is refused), and needs an admin session or a full-access key.
- **Auth:**
  - A single admin user (argon2).
  - **Sign-in is always on** *(decided 2026-11-10; replaces an earlier switch to turn it off)*. Autoplow asks for its own sign-in even behind a proxy that already authenticates, because containers and other machines can reach its port without going through the proxy. See [ADR-0019](../decisions/0019-admin-access-and-security-rules.md).
  - **Forgotten password:** `autoplow reset-password`, run on the host as the service user, sets a new one and signs out all sessions.
  - API keys: admin, read-only or metrics. A key can be regenerated; the old one stops working at once.
  - UI sessions with CSRF protection. A session lasts 30 days from its last use and at most 90 days in all. Signing out ends it, and changing the password ends every other session.
  - **Trusted proxies:** a list of proxy addresses whose forwarded-for header Autoplow believes. It is how Autoplow learns the real client address behind the proxy.
  - **Login rate limit** *(decided 2026-11-10)*: 5 wrong passwords from one client address lock sign-in for that address for 1 minute; each further lockout doubles, up to 15 minutes. Other addresses are unaffected. The sign-in page shows the tries left and the wait.
  - **Secret key** *(decided 2026-11-10)*: every stored secret is encrypted with one key, supplied only through the environment (`AUTOPLOW_SECRET_KEY`); it is never written to the data directory.
    - Without the key, Autoplow refuses to start and says which variable is missing.
    - With the wrong key, it refuses to start before touching any secret (checked against a stored marker).
    - **Rotation:** start once with the new key and the old one in `AUTOPLOW_SECRET_KEY_OLD`; everything is re-encrypted in one transaction, after which the old variable can be removed.
    - A backup is only useful together with its key.
  - Encrypted secret storage, with key rotation that re-encrypts everything. This covers everything listed under "What counts as a secret" in the security rules; only the admin password is hashed.
  - **Secrets are visible to the admin** *(decided 2026-10-30)*. Anyone who can see them already has admin access. Read-only API keys can't read any secret.
    - Every stored secret except Plex users' tokens is masked in its dialog, with a show/hide toggle inside the field so the admin can check it is the right one (see the [UI rules](ui.md)).
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
  - **Where logs go** *(decided 2026-11-10)*: standard output, for the journal, and a log file. Autoplow rotates the file daily or at 50 MiB and keeps the last 7 (configurable). Levels can be changed per component while running. There is no log viewer in the UI in v1.
  - Prometheus `/metrics`, which needs an API key of any scope; the metrics scope is made for it.
  - `/health`, open to anyone and answering only ok or not ok. The detail is on the Health page.
  - An SSE event stream. It does not replay missed events: after a reconnect the UI reloads what it shows. A client too slow to keep up is disconnected and reconnects.
- **UI shell:**
  - Leptos CSR app embedded in the binary: login, navigation, the live event client.
  - Follows the [UI rules](ui.md): tokens, accent, density, the sidebar, and dialog behaviour live in the shell.
  - An API client from `api-types`.

## Security rules
*(Added 2026-11-10 after a security review; the reasoning is in [ADR-0019](../decisions/0019-admin-access-and-security-rules.md).)*

**Admin access is equivalent to a shell as the service account.** The admin chooses which rclone runs and with what options, and can point a move at any folder. Every rule below exists to keep admin access with the admin.

- **Who is asking:**
  - The `Host` of every request to the UI or made with a session must be Autoplow's browser address, the callback base, or a loopback name; anything else is refused. This stops a web page elsewhere from reaching a LAN-only install.
  - Forwarded headers are believed only from a trusted proxy. The client address is the rightmost one not in the trusted list. A trusted range wider than a /24 is warned about.
  - The login lockout is per client address, as above. With no trusted proxy set, every visitor shares the proxy's address, so the Health page warns when Autoplow sees forwarded headers from an address that is not trusted.
- **Sessions:**
  - The cookie is `HttpOnly`, `SameSite=Strict`, and `Secure` whenever the request came over HTTPS.
  - A change is accepted from a browser only with a JSON content type, a matching `Origin` and the session's CSRF token. There is no cross-origin access.
  - Only a hash of a session is stored. Sessions are left out of backups, last 30 days from last use and at most 90 days in all, and end when the password changes.
  - API keys are accepted in the `Authorization` header only, never in a query string.
- **Read-only keys:** every request that is not a `GET` needs an admin key or the session. These `GET`s are admin-only too: any secret, every `/browse` route, the results of Plex and Google sign-ins, and mapping suggestions. A **metrics** key can read `/metrics` and nothing else.
- **What counts as a secret:** tokens, passwords and API keys of every connection; webhook header values; Apprise and webhook URLs; shared trigger credentials; values of rclone environment variables; Plex user tokens (these are never shown). A connection URL (a target, an Arr, a download client) with a user name or password in it is refused; the credentials go in their own fields. Apprise and webhook URLs may carry them and are stored whole as secrets.
- **Triggers:**
  - The token is checked before the body is read. Failed attempts are slowed per client address.
  - A body is at most 1 MB and names at most 1000 paths.
  - Back-pressure is counted per trigger as well as overall, so one noisy sender cannot shut out the others.
  - A query-string token is accepted only where the sender cannot send a header (the legacy routes and Bazarr).
- **Outbound calls:** redirects are not followed, so a token is never sent to a host the admin did not enter.
- **Responses:** a content security policy that allows only Autoplow's own scripts and styles, no framing by other sites, no content sniffing, no referrer, and no caching of API responses. Fonts are served by Autoplow.
- **The UI:** text from outside (file names, titles, server names, release notes) is always shown as text. The address to return to after sign-in must be a path within Autoplow. An address never performs an action when opened.
- **Files:** the data directory, database, backups, logs and bootstrap report are readable by the service account only, and Autoplow refuses to start if the data directory is open to others.
- **Commands:** `reset-password` and `restore` ask for any password or key at a prompt, never as an argument, and refuse to run as a different account from the one that owns the data.
- **Security events** are logged and listed on the Health page: sign-ins and lockouts, secrets shown, API keys created or changed, and changes to rclone settings.
- **The setup token** is the one secret written to the log, once, and is useless after an admin exists.
- **Encryption:** stored secrets use authenticated encryption, each bound to the row and field it belongs to. Changing the key does not protect a backup taken under the old key.

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
11. Every request under `/api/v1` without a session or a key gets 401 (except signing in, first-start setup, the Google callback and the OpenAPI document), and a trigger route without its token is refused; no setting changes that.
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
24. A request to the UI, or made with a session, whose `Host` is not Autoplow's browser address, the callback base or a loopback name is refused; `/health`, `/metrics`, trigger routes and requests made with an API key are not subject to this. Forwarded headers from a peer that is not a trusted proxy are ignored, and the client address is the rightmost one not in the trusted list.
25. The session cookie is `HttpOnly` and `SameSite=Strict`. A change from a browser without the CSRF token, with another `Origin`, or without a JSON content type is refused. The stored session cannot be used as a cookie, no backup contains a session, and a session ends 90 days after it began.
26. A read-only key gets 403 for every request that is not a `GET` and for each admin-only `GET`; a metrics key gets 403 everywhere but `/metrics`; an API key in a query string is refused.
27. Every response carries the content security policy, no-framing, no-sniffing and no-referrer headers, and the UI loads nothing from another origin.
28. Autoplow refuses to start when its data directory is readable by other accounts, and every file it creates there is private.
29. The outbound client does not follow a redirect.
30. Sign-ins, lockouts, secrets shown, API key changes and rclone setting changes each appear in the security events list.
31. On a full disk the reserve is given up and upload results are still recorded. A schedule missed while stopped runs once at start; a scheduled time that does not exist that day runs at the next valid minute. After a restore, older undelivered notifications are discarded and no session survives.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; keep wall-clock time behind the `Clock` trait.
- **Ask first:** changing the auth model or the secret-encryption scheme.
- **Never:** block a supervisor-managed task on synchronous I/O without `spawn_blocking`; log secrets.

## Open questions
- Shutdown deadline default (**decided 2026-10-27:** 30 s). systemd's default stop timeout (90 s) is longer, so the example unit needs no change.
