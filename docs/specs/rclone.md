# Spec: rclone

**Module:** `rclone` · **Depends on:** core · **Decisions:** ADR-0003 · **Status:** approved 2026-10-27

## Objective
Run and supervise `rclone rcd` as a private child process, and give `upload`, `throttle` and `gdrive` a typed, reliable RC client: transfers, jobs, stats, bandwidth and crypt name decoding.

## Non-goals
- Embedding rclone (ADR-0001, superseded).
- Defining or editing remotes. They belong to the user's `rclone.conf`.
- Mounting.

## Scope
- **Started only when needed** *(decided 2026-11-10)*: the child runs while something uses it: an upload destination, or a Drive monitor with a crypt remote. With neither (for example an install that only limits download clients), it is not started, and a missing or too-old rclone is not an error.
- **Child process:**
  - `rclone rcd` on a unix socket in a 0700 directory, with `--config <user rclone.conf>`.
  - **Which rclone:** the one shipped in the image by default. A setting can point to another binary, for users who want a newer rclone.
  - **Version check** *(decided 2026-11-10)*:
    - Only a minimum is enforced. There is no maximum: a newer rclone than the one Autoplow was tested with runs without a warning.
    - Below the minimum, the child is not started. That shows on the Health page and raises `rclone.unsupported`, which is sent only to channels that subscribe to it.
    - The minimum changes only in an Autoplow release, and that release's notes say so.
  - Readiness via `rc/noop`.
  - Restart with backoff.
- **Typed client for:**
  - `operations/movefile` and `copyfile`
  - `job/batch`, `job/status`, `job/stop`
  - `core/stats`, `core/transferred`, `core/stats-delete`
  - `core/bwlimit`
  - `config/listremotes`
  - `backend/command` with the crypt `decode` command, in batches (for `gdrive` crypt remotes)
- **Polling:** completion and progress, by job ID and group.
- **Cleanup:** finished stats groups are swept.

## Acceptance criteria
1. The child starts and answers `rc/noop` within 5 s. The socket isn't reachable over the network, and its directory is 0700.
2. Killing the child (`SIGKILL`) is detected within 5 s. It restarts with backoff, and the module reports "job state lost" so `upload` re-queues.
3. A rclone below the minimum version is not started, shows on the Health page with the version found and the version needed, and raises `rclone.unsupported`. A rclone newer than any tested version starts normally with no warning. A configured binary path is used instead of the bundled one.
4. Progress and completion are tracked per job and group, and are correct for duplicate basenames.
5. Stats groups for finished jobs are deleted, so the group count stays bounded during a 24-hour soak test.
6. A bandwidth change via `core/bwlimit` applies to running transfers (verified in an integration test with a crypt-over-local remote).
7. Autoplow's own SIGTERM shutdown completes even after the child performed partial-file copies, because rclone's atexit hook stays in the child.
8. `decode` on a crypt-over-local remote returns the original names for a batch of encrypted paths, and reports which names couldn't be decrypted.
9. With no upload destination and no crypt Drive monitor, no rclone child is started and no rclone health error is raised; adding a destination starts it without restarting Autoplow.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`.
- **Ask first:** changing the minimum rclone version (only in a release, with a release note).
- **Never:** pass RC credentials on argv; expose RC on TCP; write to `rclone.conf`.

## Open questions
- Minimum supported rclone version (**decided 2026-10-27:** 1.75).
