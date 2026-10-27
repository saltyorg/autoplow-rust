# ADR-0003: Run rclone as a supervised `rclone rcd` child process

## Status
Accepted (supersedes [ADR-0001](0001-embed-rclone-in-process.md))

## Date
2026-10-27

## Context
- Autoplow drives rclone through the RC JSON API: transfers, jobs, stats, bandwidth limits, config listing.
- Spikes showed that in-process `librclone.RPC` and `rcd` over HTTP use the **same** RC call table. `rcd` even supports a few methods that the in-process RPC can't run.
- In-process use exposes the host to:
  - rclone crashes and memory leaks
  - rclone's `atexit` SIGINT/SIGTERM hook, which calls `os.Exit(143)` after any partial-file copy (verified in both Go and Rust hosts)
  - a rclone version fixed at Autoplow's build time
- See `docs/platform-notes/rclone.md`.

## Decision
- Autoplow starts and supervises `rclone rcd` on a private unix socket in a 0700 directory, with `--config` pointing at the user's existing `rclone.conf`. Remotes are referenced by name, and Autoplow defines none of its own.
- **Supervision:** health check with `rc/noop`, and restart with backoff.
- **Job state:** unfinished uploads are re-queued from Autoplow's own database after a restart, because rclone's job state does not survive one.
- **Completion:** job completion is polled.

## Alternatives Considered
- **In-process `librclone`:** [ADR-0001](0001-embed-rclone-in-process.md). Same control, worse isolation, and practical only in Go.
- **The `librclone` Rust crate:** same mechanism as a cgo c-archive; pinned to rclone v1.69 at its last release.
- **Pure-Rust storage libraries (for example OpenDAL):** no rclone crypt, union or chunker remotes, and no `rclone.conf` compatibility.

## Consequences
- A second process to supervise.
- rclone versioning is independent of Autoplow: a minimum version is checked, and the container image ships a pinned rclone.
- No push-style job completion events. Polling about once a second is acceptable for uploads.
- The implementation language is free (enables [ADR-0004](0004-rust-as-implementation-language.md)).
