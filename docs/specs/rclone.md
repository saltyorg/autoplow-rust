# Spec: rclone

**Module:** `rclone` · **Depends on:** core · **Decisions:** ADR-0003, ADR-0021 · **Status:** approved 2026-10-27

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
- **Settings are applied to the running child** *(decided 2026-11-11, [ADR-0021](../decisions/0021-rclone-settings-applied-at-runtime.md))*:
  - The child is started with almost no options. Autoplow stores the rclone settings and applies them over the control socket after every child start and whenever one changes. What rclone accepts while running is recorded in the [platform note](../platform-notes/rclone.md).
  - There is no free-text options field and no list of environment variables.
  - **A change applies to transfers started afterwards.** Running transfers keep the values they started with, and nothing is stopped.
- **Options for every transfer:** the admin adds options from a list (for example buffer size, user agent, timeouts, low-level retries). The list holds the tuning options Autoplow allows; only those the running rclone knows are offered, each with rclone's own description and default.
- **Options for one remote:**
  - A remote from `rclone.conf` can have its own options, chosen the same way from the list for its backend type: chunk and part sizes, upload cutoffs, the backend's own request pacing where it has any (Drive, Dropbox, WebDAV), stopping at the provider's upload limit, and that remote's own user agent, timeouts and connection cap.
  - They are stored in Autoplow once per remote, so every destination that uses the remote gets the same values. `rclone.conf` is not changed, and a value here wins over the one in `rclone.conf`.
  - They are sent with each call that uses the remote. **Test** opens the remote with the options and reports rclone's answer.
  - **Remotes that wrap another** (crypt, alias, chunker, compress, hasher): options are set on the remote that talks to the provider, and Autoplow passes them through the wrapper. Members of a union or combine remote take their options from `rclone.conf` only.
- **The request limit** (`--tpslimit`): one optional ceiling for the whole daemon, off by default and shared by every remote. rclone cannot change it while running, so a new value restarts the child as described under "Restart" below.
- **The config password:** stored like other secrets and given to the child in its environment, never on the command line.
- **The config file:**
  - Autoplow never writes to `rclone.conf`. rclone itself saves refreshed tokens there, so the file must be writable by the service's account. Other rclone processes on the host (a mount) may use the same file.
  - **Changes need no restart** *(decided 2026-11-11)*. rclone re-reads the file when it changes. Autoplow watches the file's folder to refresh its list of remotes. A remote added to the file can be used at once. An edited remote is used with its new values by the next transfer that starts. A remote removed from the file is shown as missing wherever it is used.
  - A change that only renews a token does nothing.
- **Restart:**
  - Needed only for a new request limit, config password, rclone path or config path. The child restarts as soon as no transfer is running, and Settings › rclone says a restart is pending until then. If no idle moment comes within 1 hour, new transfers are held until the running ones finish, and the child restarts then.
  - **Restart now** restarts it at once; running transfers are stopped and re-queued.
- **How remotes are addressed:**
  - Every call names the remote by its root and puts the whole path in the file argument. rclone opens each distinct root separately, with its own request pacing, so this keeps one pacer per remote.
  - Autoplow builds the remote's address itself from the stored name and options. Nothing the admin types is passed to rclone as an address.
- **Typed client for:**
  - `operations/movefile` and `copyfile`
  - `job/batch`, `job/status`, `job/stop`
  - `core/stats`, `core/transferred`, `core/stats-delete`
  - `core/bwlimit`
  - `config/listremotes`, `config/providers` and `options/info` (which remotes and options exist)
  - `options/set` (settings for every transfer) and `operations/fsinfo` (testing a remote with its options)
  - `backend/command` with the crypt `decode` command, in batches (for `gdrive` crypt remotes)
- **Polling:** completion and progress, by job ID and group.
- **Cleanup:** finished stats groups are swept.
- **On a fresh child:** whenever the child starts (first start, crash, restart), the stored settings and the current bandwidth limit are applied before any transfer is started.
- **Bandwidth** is set as one value for both directions. That form also limits a copy to a local or NFS folder, which a separate upload value does not.
- **What can never be set** *(security review 2026-11-10, widened 2026-11-11)*: the lists above hold tuning options only. No setting, for the daemon or for a remote, may
  - run a program (`metadata_mapper`, `name_transform`, `password_command`, sftp `ssh`, WebDAV `bearer_token_command`);
  - change where a remote points or how it signs in (its type, address, credentials, tokens, keys, the wrapped remote, crypt passwords);
  - weaken the connection (certificate checks, custom certificates, proxies, extra headers) or print credentials (`dump`);
  - open a listener, or move the config or the log;
  - set the bandwidth limit, which throttle owns;
  - change what a transfer does to files (dry run, skipping checks, backup folders). Autoplow sets those itself.
  - Backend options are never given to the whole daemon: they would override the values in the user's own `rclone.conf` for every remote of that type.
- **Control calls:** only the calls listed under "Typed client" are ever made. Calls that run commands, change the config or return its secrets are never reachable from anything the admin enters.
- **Environment:** the child gets a short fixed set (`HOME`, `PATH`, `TZ`, proxy settings) plus the config password when one is set. It never gets Autoplow's secret key, and it does not inherit any capability the service holds.
- **The rclone path** must be absolute, a regular file, and not writable by anyone but its owner and root.
- **Remotes** in a destination must be names from `rclone.conf` or an absolute local path; a connection string made up on the spot is refused. A destination may not contain Autoplow's data directory or `rclone.conf`.

## Events raised
These are the notification types this module raises (the catalogue is in [notifications.md](notifications.md)).
- `rclone.unsupported`: the rclone found is older than the minimum.

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
13. A remote added to `rclone.conf` while the child runs can be used by the next transfer, with no restart of the child or of Autoplow. An edited remote is used with its new values by the next transfer, while a transfer already running finishes undisturbed.
14. An option saved for every transfer, or for one remote, applies to the next transfer started and to no transfer already running; the child is not restarted. An option set for one remote does not apply to another remote of the same backend type.
15. Only options on the allowed list that the running rclone knows can be saved; any other name is rejected when saved, whatever its spelling, through the UI and the API alike. The child's environment holds the fixed set and the config password, and never Autoplow's secret key.
16. After every child start, the stored settings and the current bandwidth limit are in place before the first transfer begins.
17. A token renewal in `rclone.conf` causes nothing. A new request limit restarts the child when idle, and within an hour even with transfers always running; Restart now does it at once and re-queues what was running.
18. Two transfers to different folders of one remote share one request pacer: with a pacing option set on the remote, their combined request rate stays within it.
19. An option set on the remote under a crypt remote applies to uploads made through the crypt remote.
20. A bandwidth limit also limits a copy to a local-folder destination.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`.
- **Ask first:** changing the minimum rclone version (only in a release, with a release note).
- **Never:** pass a secret on the command line; pass admin-typed text to rclone as an option name or a remote address; expose the control socket on the network; write to `rclone.conf`; leave a child running without Autoplow.

## Open questions
- Minimum supported rclone version (**decided 2026-10-27:** 1.75).
