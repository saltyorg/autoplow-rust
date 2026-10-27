# ADR-0007: Seed-once bootstrap file, idempotent REST API, API-only UI

## Status
Accepted

## Date
2026-10-25

## Context
Autoplow is primarily deployed by Saltbox (Ansible). Saltbox templates an application's config only on initial install; afterwards the user owns the configuration. The predecessor stored everything in a database with a UI but no complete API, which made automation hard.

## Decision
- **Bootstrap file:**
  - A YAML file with a strict schema. It is applied at startup and **creates only resources that don't exist yet** (seed once), including the admin user and an admin API key.
  - After a fully successful ingest the file is **deleted**, and a secret-free `bootstrap-report.json` is written. On partial failure the file is kept and errors are reported.
- **REST API:**
  - `/api/v1`, OpenAPI-first.
  - Resources are addressed by stable names, and `PUT` is an idempotent upsert.
  - `POST /api/v1/apply` uses the bootstrap schema, with `mode=seed|upsert` and `dry_run`.
  - Secrets are write-only.
  - Errors follow RFC 9457.
- **The web UI uses only the public API and SSE.**

## Alternatives Considered
- **The file stays the source of truth, with a locked UI:** conflicts with "the user owns configuration after install".
- **The file overwrites on every start:** surprising, and destroys UI edits.
- **A database plus UI with no full API** (the predecessor's approach): poor automation.

## Consequences
- Ansible changes after installation go through the API.
- Keeping the UI API-only keeps the API complete.
- Plain secrets in the bootstrap file are exposed only until the first successful ingest.
