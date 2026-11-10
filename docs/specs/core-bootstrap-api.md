# Spec: bootstrap file and REST API (v1)

**Module:** `core` · **Depends on:** — · **Decisions:** ADR-0007 · **Status:** approved 2026-10-27

## Objective
Configure Autoplow once from Ansible and manage it afterwards through a complete, idempotent REST API that the UI also uses.

## Non-goals
- The file as permanent source of truth
- GraphQL

## Bootstrap file
- **Location:**
  - `<config dir>/bootstrap.yml`
  - or `--bootstrap <path>`
  - or the `AUTOPLOW_BOOTSTRAP` environment variable
- **When it is read:** at startup, and only if it is present.
- **Format:** YAML with a strict schema. Unknown keys are errors. Errors include line and column.
- **Semantics: seed once.**
  - A resource is created **only if no resource of that kind with that name exists**. Existing resources are never modified.
  - Resources are identified by stable, user-chosen `name`s.
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
  callback_base_url: http://autoplow:3030
rclone:
  config: /config/rclone/rclone.conf
targets:
  - name: plex
    type: plex
    url: http://plex:32400
    token: "..."
    rewrite: [{ from: /mnt/unionfs/Media/, to: /data/ }]
arrs:
  - name: sonarr
    type: sonarr            # verified against system/status
    url: http://sonarr:8989
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
    url: http://sabnzbd:8080
    api_key: "..."
notifications:
  - name: discord-alerts
    type: discord
    url: "..."
    events: [target.unavailable, remote.quota, parity.merged.manual]
```
The detailed schema will be generated from the same Rust types the API uses, as a single source of truth, and published as a JSON Schema.

## REST API
- **Base:** `/api/v1`, designed OpenAPI-first. The OpenAPI document is served at `/api/v1/openapi.json`.
- **Auth:**
  - `Authorization: Bearer <api key>` (scoped: admin, read-only).
  - The UI uses session cookies plus CSRF protection.
- **Resources:**
  - `targets`, `arrs`, `triggers`, `destinations`, `downloaders`, `limiters`, `remotes` (read-only, from `rclone.conf`), `notifications`, `anchors`, `rewrite-sets`, `gdrive/accounts`, `gdrive/monitors`, `users`, `api-keys`, `settings`
  - Each supports `GET` (list), `GET /{name}`, `PUT /{name}` (idempotent upsert) and `DELETE /{name}`.
  - `PATCH` uses JSON merge patch.
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
  - `POST /gdrive/monitors/{name}/poll|pause|resume|rebuild`; `GET /gdrive/monitors/{name}/changes|snapshot`
  - `POST /notifications/undelivered/{id}/resend`; `DELETE /notifications/undelivered[/{id}]`
  - `POST /downloaders/{name}/test`
  - `GET /throttle` (sessions and each limiter's current limit)
  - `GET /health`
  - `GET /metrics` (Prometheus)
- **Events:** `GET /api/v1/events` (SSE) for the UI's live updates.
- **Secrets in responses:** resource responses never contain a secret; the field is reported as `{"set": true}`. An admin can read one stored secret at a time through a separate admin-only endpoint (`GET /{kind}/{name}/secret`), which the UI uses for its show/hide toggle and Copy. Read-only keys get 403 there (see the core spec, "Secrets are visible to the admin").
- **Errors:** RFC 9457 problem+json, with field-level validation errors.

## Acceptance criteria
1. A bootstrap file creates only missing resources; existing ones are never modified; a fully successful run deletes the file and writes a secret-free report; a partial failure keeps the file.
2. `PUT /api/v1/<kind>/{name}` twice with the same body yields `unchanged` the second time; `POST /apply?dry_run=true` performs no writes.
3. No list or resource response contains a secret (`{"set": true}` only). The admin-only secret endpoint returns one secret, and a read-only key gets 403 from it.
4. Every UI page is built solely on public API endpoints.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Breaking API changes.
- **Never:** Return a secret in a list or resource response, or to a read-only key; Accept unknown config keys silently.
