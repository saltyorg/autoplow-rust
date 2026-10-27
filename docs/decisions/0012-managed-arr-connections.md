# ADR-0012: Autoplow manages its own Arr webhook connections

## Status
Accepted

## Date
2026-10-26

## Context
Users configured webhooks by hand, and the definitions drifted as payloads evolved. The Arr Connect API supports full lifecycle management (see `docs/research/arr-connect-api.md` and `docs/platform-notes/arr.md`).

## Decision
- **The connection:**
  - named `Autoplow (Managed)`
  - built from the Arr's own Webhook schema template
  - authenticated with a per-instance header token
  - identified by a fingerprint header
  - `tags: []`, because tags would filter events
  - a fixed event set per app type
- **Reconciler:** detects drift field by field and repairs it with a full PUT **only when drift exists**. It re-creates a missing connection and sends a notification on drift.
- **Unmanaging** happens only in Autoplow's UI.
- **Migration helper:** detects old autoscan-style hooks and offers to disable or remove them once our connection is verified.
- **Legacy endpoints:** autoscan, A-Train and Bazarr compatibility endpoints remain as thin adapters.

## Alternatives Considered
- **Manual setup only:** drift and support burden.

## Consequences
- Autoplow's receiver must be reachable and must answer `Test` before the reconciler runs.
- Connections owned by other tools are never touched.
