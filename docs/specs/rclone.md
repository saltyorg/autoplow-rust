# Spec: rclone

**Module:** `rclone` · **Depends on:** core · **Decisions:** ADR-0003 · **Status:** approved 2026-10-27

## Objective
Run and supervise `rclone rcd` as a private child process, and give `upload` and `throttle` a typed, reliable RC client: transfers, jobs, stats and bandwidth.

## Non-goals
- Embedding rclone (ADR-0001, superseded).
- Defining or editing remotes. They belong to the user's `rclone.conf`.
- Mounting.

## Scope
- **Child process:**
  - `rclone rcd` on a unix socket in a 0700 directory, with `--config <user rclone.conf>`.
  - A minimum version check.
  - Readiness via `rc/noop`.
  - Restart with backoff.
- **Typed client for:**
  - `operations/movefile` and `copyfile`
  - `job/batch`, `job/status`, `job/stop`
  - `core/stats`, `core/transferred`, `core/stats-delete`
  - `core/bwlimit`
  - `config/listremotes`
- **Polling:** completion and progress, by job ID and group.
- **Cleanup:** finished stats groups are swept.

## Acceptance criteria
1. The child starts and answers `rc/noop` within 5 s. The socket isn't reachable over the network, and its directory is 0700.
2. Killing the child (`SIGKILL`) is detected within 5 s. It restarts with backoff, and the module reports "job state lost" so `upload` re-queues.
3. A rclone below the minimum version is refused with a clear health error.
4. Progress and completion are tracked per job and group, and are correct for duplicate basenames.
5. Stats groups for finished jobs are deleted, so the group count stays bounded during a 24-hour soak test.
6. A bandwidth change via `core/bwlimit` applies to running transfers (verified in an integration test with a crypt-over-local remote).
7. Autoplow's own SIGTERM shutdown completes even after the child performed partial-file copies, because rclone's atexit hook stays in the child.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`.
- **Ask first:** changing the minimum rclone version.
- **Never:** pass RC credentials on argv; expose RC on TCP; write to `rclone.conf`.

## Open questions
- Minimum supported rclone version (**decided 2026-10-27:** 1.75).
