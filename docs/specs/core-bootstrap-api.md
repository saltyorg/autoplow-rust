# Spec: bootstrap file and REST API (v1)

**Module:** `core` · **Depends on:** — · **Decisions:** ADR-0007 · **Status:** approved 2026-10-27

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
  - A request from the host itself can use it directly. From anywhere else it also asks for a setup token, which Autoplow prints once in its log at start.
  - The page stops existing as soon as an admin exists.

## Bootstrap file
- **Location:**
  - `<config dir>/bootstrap.yml`
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
  - **If the file can't be deleted** (read-only mount): a loud warning appears in the logs and the UI.
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
- **Identity:** every resource has a fixed internal ID and a unique, changeable name.
  - The API addresses a resource by name. A rename changes only the name: its queue, history and every reference follow it.
  - Addresses given to other systems (an Arr's webhook URL) use the ID, so a rename never breaks them.
- **An Arr is one resource.** An `arrs` entry carries its connection and its trigger settings: token, minimum age, filters, path rules, managed webhook. `triggers` holds every other trigger. The UI lists both on the Triggers page. Deleting an Arr removes all of it, including its managed webhook.
- **Concurrent edits:** each resource carries a version (`ETag`). A change sent with an older version (`If-Match`) is refused with 412, and the UI says the item changed elsewhere and offers to reload it. A change sent without a version is applied.
- **Deleting something in use** is refused with 409 and the list of what uses it (for example the triggers, anchors and destinations that name a target). Nothing is removed as a side effect. Work still queued for the item is dropped only when the delete is confirmed.
- **`settings`** is a single resource: callback base URL, Autoplow's own browser address (for links in notifications), sign-in switch, trusted proxies, time zone, scan timing defaults, retention periods, backup schedule and log levels. Every key is typed and validated.

## Routes
| Route | For | Authentication |
|---|---|---|
| `/api/v1/…` | the UI, scripts | session cookie with CSRF, or `Authorization: Bearer <api key>` |
| `/api/v1/events` | live updates | as above; a read-only key is enough |
| `/api/v1/gdrive/oauth/callback` | Google's redirect | the signed `state` value |
| `/triggers/{id}` | webhooks from Arrs and other callers | that trigger's own token |
| `/triggers/{sonarr,radarr,lidarr,manual}`, `/triggers/a-train/{drive}`, `/triggers/bazarr`, `/stats`, `/api/config-template` | callers written for autoscan, A-Train and Bazarr | the matching trigger's credentials |
| `/health` | service checks | none; reveals only ok or not ok |
| `/metrics` | Prometheus | a read-only API key |
| everything else | the UI's own files | none |

No route under `/triggers` or `/api/v1` ever depends on a browser sign-in, including when sign-in is switched off.

## REST API
- **Base:** `/api/v1`, designed OpenAPI-first. The OpenAPI document is served at `/api/v1/openapi.json`.
- **Auth:**
  - `Authorization: Bearer <api key>` (scoped: admin, read-only).
  - The UI uses session cookies plus CSRF protection.
- **Resources:**
  - `targets`, `arrs`, `triggers`, `destinations`, `downloaders`, `limiters`, `remotes` (read-only, from `rclone.conf`), `notifications`, `anchors`, `rewrite-sets`, `gdrive/accounts`, `gdrive/monitors`, `users`, `api-keys`, `settings`
  - Each supports `GET` (list), `GET /{name}`, `PUT /{name}` (idempotent upsert) and `DELETE /{name}`.
  - `PATCH` uses JSON merge patch.
- **Lists:**
  - Paged by cursor: `limit` (default 100, at most 1000) and `after`. The response carries the next cursor and the total count.
  - Each list documents its filters and its sort order; the order is stable, so paging never skips or repeats a row.
- **Long jobs:** an operation that can take more than a few seconds (a Drive snapshot rebuild, a full parity check, a backup) returns 202 with a job.
  - `GET /jobs/{id}` gives its state, progress and result. Progress is also on the event stream.
  - A job keeps running when the browser closes. Starting the same job while one is running is refused with 409 and the running job.
  - A job cut off by a restart is reported as interrupted, not as failed or finished.
- **Apply:** `POST /api/v1/apply?mode=seed|upsert&dry_run=true|false`, with the bootstrap schema as the body.
  - It returns a per-resource result: `created | updated | unchanged | skipped | error`, plus a diff.
  - `upsert` never deletes. Deletion is always explicit.
- **Operations:**
  - `POST /scans` (manual scan, with a preview: `dry_run=true` returns the rewrite and library resolution for each target)
  - `GET /queues/{target}`
  - `POST /queues/{target}/{id}/retry`
  - `GET /uploads`
  - `POST /uploads/{id}/retry|cancel`
  - `DELETE /queues/{target}/dead-letters[/{id}]` (discard one or all)
  - `POST /uploads/hold` and `DELETE /uploads/hold`; `POST /uploads/stop` (stop all)
  - `POST /parity/runs`
  - `GET /parity/findings`
  - `POST /parity/findings/{id}/fix|skip|ignore`
  - `POST /arrs/{name}/reconcile`
  - `POST /backups` (take one now); `GET /backups`
  - `PUT /log-levels/{component}`
  - `POST /gdrive/monitors/{name}/poll|pause|resume|rebuild`; `GET /gdrive/monitors/{name}/changes|snapshot`
  - `POST /notifications/undelivered/{id}/resend`; `DELETE /notifications/undelivered[/{id}]`
  - `POST /downloaders/{name}/test`
  - `GET /throttle` (sessions and each limiter's current limit)
  - `GET /health`
  - `GET /metrics` (Prometheus)
- **Events:** `GET /api/v1/events` (SSE) for the UI's live updates. Each event has a type, a time, the resource it is about and a typed payload; the types are part of the OpenAPI document.
- **Secrets in responses:** resource responses never contain a secret; the field is reported as `{"set": true}`. An admin can read one stored secret at a time through a separate admin-only endpoint (`GET /{kind}/{name}/secret`), which the UI uses for its show/hide toggle and Copy. Read-only keys get 403 there (see the core spec, "Secrets are visible to the admin").
- **Errors:** RFC 9457 problem+json, with field-level validation errors.

## Acceptance criteria
1. A bootstrap file creates only missing resources; existing ones are never modified; a fully successful run deletes the file and writes a secret-free report; a partial failure keeps the file.
2. `PUT /api/v1/<kind>/{name}` twice with the same body yields `unchanged` the second time; `POST /apply?dry_run=true` performs no writes.
3. No list or resource response contains a secret (`{"set": true}` only). The admin-only secret endpoint returns one secret, and a read-only key gets 403 from it.
4. Every UI page is built solely on public API endpoints.
5. With no admin and no bootstrap file, the setup page creates the admin: from the host itself directly, from elsewhere only with the setup token. Once an admin exists the page is gone and its route answers 404.
6. A bootstrap file readable by other accounts, or with an unknown `version`, is refused and nothing is applied.
7. Renaming a target keeps its queue entries, history and references, and an Arr webhook created before the rename still delivers.
8. A change sent with a stale version gets 412 and changes nothing; the same change sent with the current version succeeds.
9. Deleting a resource that others reference gets 409 with every dependent listed, and removes nothing.
10. Creating an Arr creates no separate `triggers` entry; deleting it removes its trigger settings and its managed webhook.
11. A list of 10 000 rows is returned in pages that never skip or repeat a row while rows are being added.
12. A long job returns 202 at once, reports progress, survives the client disconnecting, and a second start of the same job gets 409.
13. Every route in the routes table accepts exactly the authentication listed for it and rejects the others (matrix test).

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Breaking API changes; adding a route outside `/api/v1`.
- **Never:** Return a secret in a list or resource response, or to a read-only key; Accept unknown config keys silently.
