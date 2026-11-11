# Spec: bootstrap file and REST API (v1)

**Module:** `core` · **Depends on:** — · **Decisions:** ADR-0007, ADR-0019 · **Status:** approved 2026-10-27

## Objective
Configure Autoplow once from Ansible and manage it afterwards through a complete, idempotent REST API that the UI also uses.

## Non-goals
- The file as permanent source of truth
- GraphQL
- Exporting the configuration (database backups cover moving to another host)

## First start
*(decided 2026-11-10)*
- **With a bootstrap file** (Saltbox): the file creates the admin, as below.
- **Without one:** as long as no admin exists, the UI shows a one-time setup page to choose the username and password.
  - It always asks for a setup token, which Autoplow prints once in its log at start *(decided 2026-11-10; there is no shortcut for requests from the host itself, because behind a proxy every request looks local)*.
  - The page does not exist while a bootstrap file is present, whether or not it was applied.
  - The page stops existing as soon as an admin exists.

## Bootstrap file
- **Location:**
  - `<data directory>/bootstrap.yml`
  - or `--bootstrap <path>`
  - or the `AUTOPLOW_BOOTSTRAP` environment variable
- **When it is read:** at startup, and only if it is present.
- **Format:** YAML with a strict schema. Unknown keys are errors, and so is a `version` this Autoplow doesn't know; either way nothing is applied. Errors include line and column.
- **The file holds secrets,** so it must be readable only by the service's own account. A file others can read is refused, with a message saying how to fix it.
- **Semantics: seed once.**
  - A resource is created **only if no resource of that kind with that name exists**. Existing resources are never modified.
  - "Exists" means a resource of that kind currently has that name. A resource renamed in the UI no longer has its old name, so a later seed with the old name would create a second one; Saltbox seeds only on the first install.
- **Cleanup:**
  - **After a fully successful ingest:** the file is deleted and `bootstrap-report.json` is written. The report has no secrets and lists created, skipped and failed resources with reasons.
  - **On partial failure:** the file is kept, the errors are reported in the report, the logs and the UI, and the next start retries.
  - **If the file can't be deleted** (for example, no permission): a loud warning appears in the logs and the UI.
- **Ansible:** Saltbox templates this file **only on initial install**. After that the user owns the configuration.

### Shape (sketch)
```yaml
version: 1
admin:
  username: admin
  password: "..."          # stored as an argon2 hash
  api_keys:
    - name: ansible
      key: "..."           # stored encrypted; used as Authorization: Bearer
settings:
  callback_base_url: https://autoplow.example
rclone:
  config: ~/.config/rclone/rclone.conf
targets:
  - name: plex
    type: plex
    url: https://plex.example
    token: "..."
    rewrite: [{ from: /mnt/unionfs/Media/, to: /data/ }]
arrs:
  - name: sonarr
    type: sonarr            # verified against system/status
    # An Arr carries its own trigger settings; there is no separate trigger entry for it.
    minimum_age: 30s
    url: https://sonarr.example
    api_key: "..."
    managed_connection: true
    rewrite: [{ from: /tv/, to: /mnt/unionfs/Media/TV/ }]
triggers:
  - name: local-media
    type: filesystem
    paths: [/mnt/local/Media/]
    mode: both              # inotify | walk | both
destinations:
  - name: media
    local_path: /mnt/local/Media/
    scan_path: /mnt/unionfs/Media/     # the same folder as scans and media servers see it
    remotes: [{ remote: "google:", path: /Media/ }]
downloaders:
  - name: sabnzbd
    type: sabnzbd
    url: https://sabnzbd.example
    api_key: "..."
notifications:
  - name: discord-alerts
    type: discord
    url: "..."
    events: [target.unavailable, remote.quota, parity.merged.manual]
```
The detailed schema will be generated from the same Rust types the API uses, as a single source of truth, and published as a JSON Schema.

## Resource model
*(decided 2026-11-10)*
- **Identity:** every resource has a fixed internal ID and a unique, changeable name. The ID is a random UUID generated when the resource is created; it is never derived from the name and never chosen by the admin.
  - The API addresses a resource by name. A rename changes only the name: its queue, history and every reference follow it.
  - Addresses given to other systems (an Arr's webhook URL, the address a webhook trigger gives its caller) use the ID, so a rename never breaks them and the address cannot be guessed from the trigger's name. The only name-based trigger addresses are the fixed legacy routes.
- **An Arr is one resource.** An `arrs` entry carries its connection and its trigger settings: token, minimum age, filters, path rules, managed connection. `triggers` holds every other trigger except Google Drive monitors, which live under `gdrive/monitors`. The UI lists all three on the Triggers page. Deleting an Arr removes all of it, including its managed webhook.
- **Concurrent edits:** each resource carries a version (`ETag`). A change sent with an older version (`If-Match`) is refused with 412, and the UI says the item changed elsewhere and offers to reload it. A change sent without a version is applied.
- **Deleting something in use** is refused with 409 and the list of what uses it (for example the triggers, anchors and destinations that name a target). Nothing else is removed as a side effect.
- **Deleting something that still has work, or cannot be reached:** the 409 lists what would be lost (queued work, parity findings and settings for that Arr or target); repeating the delete with `?confirm=true` goes ahead and removes those with it. For an Arr that is down, the answer also says its managed connection may still exist in the Arr.
- **`settings`** is a single resource with one group per area. Every key is typed and validated, and every value a Settings page or an options card shows is a key here:
  - **general:** callback base URL, Autoplow's own browser address (for links in notifications), trusted proxies, time zone, the update check switch, shared trigger credentials, the Arr reconcile interval, retention periods, backup schedule, log levels and log-file retention.
  - **scan:** minimum age and maximum wait defaults, dead-letter attempts.
  - **notifications:** the problem delay, delivery attempts, the grouping window.
  - **rclone:** config path, which rclone, the config password, the request limit, and the options for every transfer. Options for one remote are stored on the remote (`PUT /remotes/{name}/options`).
  - **uploads:** the global transfer cap, upload windows, fixing file dates, retry attempts, cooldown times, the stalled-transfer time.
  - **throttle:** what counts as a stream, the local networks, the settling time, "no new uploads above N streams", and per client "pause above N streams".
  - **parity:** when to check, automatic fixes per server and finding type, the safety limit, match language, excluded pairs and finding types, retention.
  - **track-preferences:** per Plex target whether it is on and for which libraries, the ignore label, ignored file patterns, the trigger switches, the sweep time, the default scope.

## Routes
| Route | For | Authentication |
|---|---|---|
| `/api/v1/…` | the UI, scripts | session cookie with CSRF, or `Authorization: Bearer <api key>`. A read-only key may only `GET`, and not the admin-only reads marked below. Signing in, setup and the OpenAPI document need neither. |
| `/api/v1/events` | live updates | as above; a read-only key is enough |
| `/api/v1/gdrive/oauth/callback` | Google's redirect | the signed `state` value |
| `/triggers/{id}` (a random UUID) | webhooks from Arrs and other callers | that trigger's own token |
| `/triggers/{sonarr,radarr,lidarr,manual}`, `/triggers/a-train/{drive}`, `/triggers/bazarr`, `/stats`, `/api/config-template` | callers written for autoscan, A-Train and Bazarr | the matching trigger's credentials |
| `/health` | service checks | none; reveals only ok or not ok |
| `/metrics` | Prometheus | an API key of any scope |
| `/api/v1/setup` | first-start setup (the page is part of the UI) | the setup token; absent once an admin exists or while a bootstrap file is present |
| everything else | the UI's own files | none |

No route under `/triggers` ever depends on a browser sign-in. A request under `/api/v1` carries a session or an API key.

## REST API
- **Base:** `/api/v1`, designed OpenAPI-first. The OpenAPI document is served at `/api/v1/openapi.json`.
- **Auth:**
  - `Authorization: Bearer <api key>` (scoped: admin, read-only, metrics).
  - The UI uses session cookies plus CSRF protection.
- **Resources:**
  - `targets`, `arrs`, `triggers`, `destinations`, `downloaders`, `limiters`, `remotes` (from `rclone.conf`; only their options can be changed), `notifications`, `anchors`, `rewrite-sets`, `gdrive/clients`, `gdrive/accounts`, `gdrive/monitors`, `api-keys`, `settings`
  - Each supports `GET` (list), `GET /{name}`, `PUT /{name}` (idempotent upsert) and `DELETE /{name}`.
  - `PATCH` uses JSON merge patch.
- **Lists:**
  - Paged by cursor: `limit` (default 100, at most 1000) and `after`. The response carries the next cursor and the total count.
  - Each list documents its filters and its sort order; the order is stable, so paging never skips or repeats a row.
- **Long jobs:** an operation that can take more than a few seconds (a Drive snapshot rebuild, a full parity check, a backup) returns 202 with a job.
  - `GET /jobs/{id}` gives its state, progress and result. Progress is also on the event stream.
  - A job keeps running when the browser closes. Starting the same job while one is running is refused with 409 and the running job.
  - A job cut off by a restart is reported as interrupted, not as failed or finished. A job that resumes by itself (a Drive snapshot) continues instead.
- **Apply:** `POST /api/v1/apply?mode=seed|upsert&dry_run=true|false`, with the bootstrap schema as the body.
  - It returns a per-resource result: `created | updated | unchanged | skipped | error`, plus a diff.
  - `upsert` never deletes. Deletion is always explicit.
- **Operations:**
  - `POST /scans` (manual scan, with a preview: `dry_run=true` returns the rewrite and library resolution for each target)
  - `GET /queues/{target}`; `GET /queues/{target}/delivered` (history); `GET /scans/unmatched`; `POST /scans/unmatched/{id}/retry`
  - `POST /queues/{target}/{id}/send` (send now); `POST /queues/{target}/{id}/retry`
  - `GET /uploads` (filter by state: waiting, running, failed, finished)
  - `POST /uploads/now` (all, or `?destination=`); `POST /uploads/{id}/retry|stop`; `DELETE /uploads/{id}` (discard a failed file)
  - `DELETE /queues/{target}/dead-letters[/{id}]` (discard one or all)
  - `POST /uploads/hold` and `DELETE /uploads/hold`; `POST /uploads/stop` (stop all)
  - `POST /parity/runs`
  - `GET /parity/findings`; `GET /parity/findings/{id}` (both sides, history and what was done)
  - `POST /parity/findings/{id}/fix|skip|ignore|unignore`
  - `POST /arrs/{name}/reconcile|unmanage`; `POST /arrs/test` (a connection not saved yet) and `POST /arrs/{name}/test`
  - `GET /arrs/{name}/mapping-suggestions` (admin only); `GET /arrs/{name}/webhooks` (older ones); `POST /arrs/{name}/webhooks/{id}/disable`; `DELETE /arrs/{name}/webhooks/{id}`
  - `POST /targets/test` and `POST /targets/{name}/test`; `GET /targets/{name}/libraries`
  - `POST /targets/plex-sign-in` (start) and `GET /targets/plex-sign-in/{id}` (result; admin only)
  - Admin only: `GET /browse/files?path=` (the filesystem browser); `GET /browse/targets/{name}?path=`; `GET /browse/gdrive/{account}?drive=&folder=`
  - `POST /backups` (take one now); `GET /backups`
  - `POST /session` (sign in); `DELETE /session` (sign out); `PUT /session/password`; `POST /setup` (first start only)
  - `POST /api-keys/{name}/regenerate`
  - `GET /status` (version and the latest release, bootstrap result, every component, every connection, recent health and security events: what the Health and About pages show)
  - `GET /stats` (the Dashboard tiles and the per-trigger and per-target counts)
  - `PUT /log-levels/{component}`
  - `POST /gdrive/monitors/{name}/poll|pause|resume|rebuild`; `GET /gdrive/monitors/{name}/changes|snapshot`
  - `GET /notifications/undelivered`; `POST /notifications/undelivered/{id}/resend`; `DELETE /notifications/undelivered[/{id}]` (all, or with `?channel=` one channel's)
  - `POST /notifications/{name}/test`
  - `POST /gdrive/accounts/connect` (start) and `GET /gdrive/accounts/connect/{id}` (result; admin only); `GET /gdrive/accounts/{name}/drives`; `GET /gdrive/redirect-check`
  - `GET /rclone` (state, version, and whether a restart is pending); `POST /rclone/restart`
  - `GET /rclone/options` (the options that can be set for every transfer, and per backend type for a remote, each with description and default); `GET` and `PUT /remotes/{name}/options`; `POST /remotes/{name}/test` (opens the remote with the given options)
  - `POST /downloaders/{name}/test`
  - `GET /throttle` (sessions and each limiter's current limit); `PUT /throttle/override` and `DELETE /throttle/override`
  - `GET /track-preferences/users`; `PATCH /track-preferences/users/{id}` (opt out, scope override); `DELETE /track-preferences/users/{id}/preferences` (clear all)
  - `GET /track-preferences/users/{id}/preferences`; `PUT` and `DELETE /track-preferences/users/{id}/preferences/{show}[/{season}]`
  - `GET /track-preferences/excluded-shows`; `PUT` and `DELETE /track-preferences/excluded-shows/{show}`
  - `GET /track-preferences/history`; `POST /track-preferences/sweeps` (a long job)
- **Events:** `GET /api/v1/events` (SSE) for the UI's live updates. Each event has a type, a time, the resource it is about and a typed payload; the types are part of the OpenAPI document.
- **Secrets in responses:** resource responses never contain a secret; the field is reported as `{"set": true}`. An admin can read one stored secret at a time through a separate admin-only endpoint (`GET /{kind}/{name}/secret`), which the UI uses for its show/hide toggle and Copy. Read-only keys get 403 there (see the core spec, "Secrets are visible to the admin").
- **Errors:** RFC 9457 problem+json, with field-level validation errors.

## Acceptance criteria
1. A bootstrap file creates only missing resources; existing ones are never modified; a fully successful run deletes the file and writes a secret-free report; a partial failure keeps the file.
2. `PUT /api/v1/<kind>/{name}` twice with the same body yields `unchanged` the second time; `POST /apply?dry_run=true` performs no writes.
3. No list or resource response contains a secret (`{"set": true}` only). The admin-only secret endpoint returns one secret, and a read-only key gets 403 from it.
4. Every UI page is built solely on public API endpoints.
5. With no admin and no bootstrap file, the setup page creates the admin, and only with the setup token. Once an admin exists, or while a bootstrap file is present, the page is gone and its route answers 404.
6. A bootstrap file readable by other accounts, or with an unknown `version`, is refused and nothing is applied.
7. Renaming a target keeps its queue entries, history and references, and an Arr webhook created before the rename still delivers.
8. A change sent with a stale version gets 412 and changes nothing; the same change sent with the current version succeeds.
9. Deleting a resource that others reference gets 409 with every dependent listed, and removes nothing.
10. Creating an Arr creates no separate `triggers` entry; deleting it removes its trigger settings and its managed webhook.
11. A list of 10 000 rows is returned in pages that never skip or repeat a row while rows are being added.
12. A long job returns 202 at once, reports progress, survives the client disconnecting, and a second start of the same job gets 409.
13. Every route in the routes table accepts exactly the authentication listed for it and rejects the others (matrix test).
14. A delete that would lose queued work, findings or settings, or whose Arr is unreachable, answers 409 with what would be lost, and goes ahead when repeated with `confirm=true`.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Breaking API changes; adding a route outside `/api/v1`.
- **Never:** Return a secret in a list or resource response, or to a read-only key; Accept unknown config keys silently.
