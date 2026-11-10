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
  - **Which rclone:** the one installed on the host, found on the service's `PATH`. A setting can point to another binary, for users who keep a newer rclone elsewhere. Nothing is bundled.
  - **Version check** *(decided 2026-11-10)*:
    - Only a minimum is enforced. There is no maximum: a newer rclone than the one Autoplow was tested with runs without a warning.
    - Below the minimum, the child is not started. That shows on the Health page and raises `rclone.unsupported`, which is sent only to channels that subscribe to it.
    - The minimum changes only in an Autoplow release, and that release's notes say so.
  - Readiness via `rc/noop`.
  - Restart with backoff.
  - **Access:** the control socket is the only way in. Its folder is readable by the service's account alone, so no password is used.
  - **Never orphaned** *(decided 2026-11-10)*: the child is tied to Autoplow, so it is killed if Autoplow dies for any reason. At start, a child left over from an earlier run is found and stopped before a new one starts. Two children never run at once.
  - **Hung child:** `rc/noop` is called every 30 s while the child runs. Three missed answers in a row count as dead: the child is killed and restarted, and job state is reported lost.
  - **Shutdown** *(decided 2026-11-10)*: when Autoplow stops, running transfers are stopped. Their files stay where they are and are queued again at the next start.
  - **Its output** goes to Autoplow's log under the `rclone` component, at that component's level.
- **Options** *(decided 2026-11-10)*:
  - The admin can give extra command-line options and environment variables for the child (chunk sizes, API pacing, a config password, a user agent). Values that are secrets are stored like other secrets.
  - Autoplow refuses the options it must control itself (the control socket, the config path, the bandwidth limit) and says why. Its own bandwidth limit always wins over one in the environment.
- **The config file:**
  - Autoplow never writes to `rclone.conf`. rclone itself saves refreshed tokens there, so the file must be writable by the service's account. Other rclone processes on the host (a mount) may use the same file.
  - **Changes** *(decided 2026-11-10)*: Autoplow watches the file. When it changes, the child is restarted as soon as no transfer is running, and Settings › rclone says a restart is pending until then. **Reload** restarts it at once; running transfers are stopped and re-queued.
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
3. A rclone below the minimum version is not started, shows on the Health page with the version found and the version needed, and raises `rclone.unsupported`. A rclone newer than any tested version starts normally with no warning. A configured binary path is used instead of the one on `PATH`.
4. Progress and completion are tracked per job and group, and are correct for duplicate basenames.
5. Stats groups for finished jobs are deleted, so the group count stays bounded during a 24-hour soak test.
6. A bandwidth change via `core/bwlimit` applies to running transfers (verified in an integration test with a crypt-over-local remote).
7. Autoplow's own SIGTERM shutdown completes even after the child performed partial-file copies, because rclone's atexit hook stays in the child.
8. `decode` on a crypt-over-local remote returns the original names for a batch of encrypted paths, and reports which names couldn't be decrypted.
9. With no upload destination and no crypt Drive monitor, no rclone child is started and no rclone health error is raised; adding a destination starts it without restarting Autoplow.
10. Killing Autoplow (`SIGKILL`) leaves no rclone child running, and a child left over from an earlier run is stopped before a new one starts.
11. A child that stops answering is killed and restarted within 2 minutes, and job state is reported lost.
12. On shutdown, running transfers are stopped, their sources are intact, and they are queued again after restart.
13. A remote added to `rclone.conf` is available after the child restarts when idle, without restarting Autoplow; Reload makes it available at once.
14. An extra option Autoplow must control is refused with the reason; any other is passed to the child; a bandwidth limit in the environment does not override the throttle's.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`.
- **Ask first:** changing the minimum rclone version (only in a release, with a release note).
- **Never:** pass a secret on the command line; expose the control socket on the network; write to `rclone.conf`; leave a child running without Autoplow.

## Open questions
- Minimum supported rclone version (**decided 2026-10-27:** 1.75).
