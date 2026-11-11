# ADR-0021: rclone settings are applied to the running daemon

## Status
Accepted. Amends [ADR-0019](0019-admin-access-and-security-rules.md) ("rclone options refused by family") and the options rules decided in the rclone spec on 2026-11-10.

## Date
2026-11-11

## Context
The first design let the admin type extra command-line options and environment variables for the `rclone rcd` child. That had three problems.

- **Every change needed a restart of the child,** which stops running transfers. The same went for a change to `rclone.conf`.
- **Options given at start are shared.** A backend option covers every remote of its type, and `--tpslimit` is one bucket for the whole daemon, so two providers could not get different values.
- **A free-text field had to be defended by a refuse-list,** and the list was incomplete: some options run a program.

We then measured what a running `rcd` accepts (rclone 1.75.1; details in the [platform note](../platform-notes/rclone.md)):

- It re-reads `rclone.conf` by itself when the file changes.
- Most global options can be changed through its API and apply to transfers started afterwards.
- A remote can carry its own options on each call, including its own connection settings.
- A backend's request pacing belongs to one opened remote, and is tunable for some backends (Drive, Dropbox, WebDAV).
- `--tpslimit` cannot be changed after start by any means.

## Decision
- **One `rcd` child, started with almost no options.** Autoplow stores the rclone settings and applies them over the control socket after every child start and whenever they change.
- **No free-text options and no admin-listed environment variables.** Settings are chosen from a list of tuning options that Autoplow allows and the running rclone knows. The only secret is the config password.
- **Options per remote.** A remote from `rclone.conf` can have its own options in Autoplow. They are stored once per remote, not per destination, and are sent with every call that uses the remote. `rclone.conf` is still never written.
- **A change applies to transfers started afterwards.** Running transfers keep the values they started with. Nothing is stopped.
- **`rclone.conf` changes need no restart.** A new remote is usable at once; an edited remote is used with its new values by the next transfer.
- **The request limit (`--tpslimit`) stays a start-up setting:** one optional ceiling for the whole daemon, off by default. Changing it restarts the child when no transfer is running. Pacing for one provider uses that backend's own pacing options where it has them, and Autoplow's per-remote transfer cap everywhere.
- **Restart remains** for the request limit, the config password, the rclone path and the config path, and as a button.

## Alternatives Considered
### One `rcd` per provider or per remote
- **Pros:** a real request limit per provider.
- **Cons:** about 65 MB idle and 130 MB busy per process (measured), one supervisor each, and no shared bandwidth bucket, so Autoplow would have to split the limit between processes.
- **Rejected:** the cost is paid by every install for a limit few need. It can be added later without changing how settings are stored.

### Keep the free-text field beside the runtime settings
- **Pros:** covers any option not on the list.
- **Cons:** keeps the restart, the shared scope and the refuse-list.
- **Rejected:** an option worth supporting is added to the list in a release.

### One `rclone` process per file
- **Pros:** every flag is per transfer; nothing to restart.
- **Cons:** no shared pacing or bandwidth bucket between concurrent transfers, a control socket per process for live bandwidth changes, and more token refreshes writing `rclone.conf`.
- **Rejected:** it gives up what [ADR-0003](0003-rclone-as-supervised-rcd.md) chose the daemon for.

## Consequences
- The settings page shows fields, not a text box, and the per-remote options are checked against what the running rclone reports, so a misspelt option cannot be saved. rclone itself ignores unknown names silently.
- Autoplow must always address a remote by its root and put the whole path in the file argument. Each distinct root is opened separately and gets its own pacing, so anything else multiplies the request rate.
- An option set on a remote that wraps another (crypt, alias) does not reach the wrapped remote. Options are therefore set on the remote that talks to the provider, and Autoplow passes them through the wrapper. Union and combine remotes take their members' options from `rclone.conf` only.
- Two things are refused that the earlier list missed: options that run a program (`metadata_mapper`, `name_transform`, sftp `ssh`, WebDAV `bearer_token_command`) and backend options given to the whole daemon, which would override the values in the user's own `rclone.conf`.
- Drive and Dropbox option behaviour is from source reading, not a live test. The first live upload tests must confirm it (task 5.3).
