# ADR-0001: Embed rclone in-process via librclone

## Status
Superseded by [ADR-0003](0003-rclone-as-supervised-rcd.md)

## Date
2026-10-25

## Context
Uploads need rclone's transfers, crypt/union remotes, progress stats and bandwidth limiting. The predecessor (autoplow, Go) ran `rclone rcd` as a child. Embedding rclone looked like it would give more control and a single binary.

## Decision
Embed rclone in the Autoplow process through rclone's `librclone` RPC (Go).

## Alternatives Considered
- **Supervised `rclone rcd`:** the approach in effect at the time; it means a second process.
- **Pure re-implementation:** not viable. No other library supports rclone's crypt, union or chunker remotes or `rclone.conf`.

## Consequences
- Tied the implementation language to Go.
- **Superseded after measurement:**
  - `librclone.RPC` *is* the RC API, so embedding gives no extra control over transfers.
  - In-process rclone also exposes the host to rclone's SIGTERM `atexit` hook, which can `os.Exit` the process (see `docs/platform-notes/rclone.md`).
