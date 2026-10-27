# Cloudplow: codebase report

- **Repository:** github.com/l3uddz/cloudplow
- **Analysed:** HEAD `584263a` (2026-06-11)
- **Size:** about 3k lines of Python

## Purpose
Cloudplow automates rclone in "cloud mount" setups:
- Moves local media to cloud remotes once a size threshold is reached.
- Rotates Google service accounts (SAs) when a daily quota is hit.
- Cleans unionfs "hidden" whiteout files.
- Syncs one remote to another, either locally or on a temporary Scaleway VM.
- Throttles rclone bandwidth while Plex is streaming.
- Pauses NZBGet and SABnzbd while uploads run.
- Sends notifications.

## 1. Architecture
- **Import-time startup** (cloudplow.py:28-83)
  - Sets up logging: console output plus a rotating file (5 MB × 5).
  - Parses arguments: `--config`, `--logfile`, `--cachefile`, `--loglevel`, with `CLOUDPLOW_*` environment variable equivalents.
  - Loads the config. Missing default keys are merged in and saved, and **the process then exits**.
  - Opens `sqlitedict` tables `uploader_bans`, `syncer_bans` and `sa_bans`.
  - Runs a `git fetch` version check on every start.
  - An environment variable named after a top-level config section, containing JSON, replaces that whole section.
- **Modes**
  - `clean`: runs the hidden cleaner.
  - `upload`: runs the hidden cleaner, then every uploader. Ignores the size threshold, the time window and suspensions.
  - `sync`: runs the syncers.
  - `update_config`: upgrades the config file.
  - `run`: daemon mode. A single-threaded `schedule` loop runs each uploader every `check_interval` minutes and each syncer every `sync_interval` hours. Scaleway syncers run in a separate `multiprocessing.Process`.
- **Scheduled uploader tick**
  1. Returns early if the uploader is suspended. An expired suspension is cleared and a notification sent.
  2. Clears expired SA bans.
  3. Runs `du`.
  4. If the folder is at least `max_size_gb` **and** the current time is inside the schedule window, runs `do_hidden()` for all hidden configs, then `do_upload(name)`.
  - Because the loop is single-threaded, an upload blocks every other job.
- **Locks:** `upload`, `sync` and `hidden`, using the deprecated `lockfile` package in `./locks`. Taking a lock blocks until it is free. The systemd unit's `ExecStopPost` deletes the locks directory.
- **Threads:** the Plex monitor runs as a daemon thread while the upload lock is held. The hidden cleaner runs 16 deletion threads.

## 2. Upload
### Sequence, per uploader
1. Send a "starting upload of N GB" notification.
2. Start the Plex monitor, unless `can_be_throttled` is false.
3. Pause NZBGet and SABnzbd.
4. Run the upload, with SA rotation if configured.
5. Remove empty directories with `find <folder> -mindepth <remove_empty_dir_depth> -type d -empty -delete`.
6. Resume the download clients.
7. Run the mover.

If any step raises, the remaining uploaders are skipped and the download clients **stay paused**.

### Size check
- Command: `du -s --block-size=1G [--exclude=…] folder | cut -f1`.
- Each file is rounded up to a whole GB.
- If the output can't be parsed, the size is taken as 0, so the uploader never uploads.

### Open-file exclusion
1. Run `lsof -wFn +D folder` to list files currently open.
2. Keep open files that match an `opened_excludes` substring. These are still uploaded.
3. Make the remaining paths relative to the upload folder, pass them through `glob.escape`, and append them as `--exclude` arguments.

Bug: the config is shallow-copied, so these excludes **pile up in the global config** with every daemon run.

### The rclone command
```
<rclone_binary> <move|copy> '<upload_folder>' '<upload_remote>' --config=... <rclone_extras as k=v, null → bare flag> --exclude=... [--rc --rc-no-auth --rc-addr=host:port (when Plex is enabled)] [--dry-run]
```
- `rclone_command: sync` is changed to `move`.
- Excludes that start with `/` are passed through `glob.escape`, which double-escapes some of them.
- Execution: `shlex.split`, then `Popen` with stderr merged into stdout. Output is read line by line and each line goes to a callback. If the callback returns true, rclone is killed with **SIGKILL**.

### Triggers (`rclone_sleeps`)
- Each entry is `{phrase: {count, timeout (seconds), sleep (hours)}}`. Phrases match as case-insensitive substrings of an output line.
- A counting window of `timeout` seconds opens at the first match. When `count` matches arrive inside it, rclone is killed and the uploader is banned.
- Sample entries:
  - `"User rate limit exceeded"`: 5 matches in 3600 s, then a 25 h ban.
  - `" 0/s,"`: 15 matches in 140 s, used as a stall detector.

### Exit codes
| Exit code | Meaning | Result |
|---|---|---|
| 0 | OK | No ban |
| 7 | `--drive-stop-on-upload-limit` or `--max-transfer` reached | Ban for a **hard-coded 25 h** |
| -9 | rclone killed by a trigger | Ban for a hard-coded 25 h. **Bug:** the trigger's configured `sleep` is ignored. |

### Service-account rotation
- **The SA pool:** every `*.json` in `service_account_path`, mapped to either nothing or an unban time. The pool is persisted in `sqlitedict` and reconciled against the directory on each check, so added and removed files are picked up.
- **Injection:** cloudplow runs `rclone config dump` and walks crypt, chunker and union remotes down to the underlying `drive` remotes. It then sets `RCLONE_CONFIG_<NAME>_SERVICE_ACCOUNT_FILE` for each drive remote.
  - The walk from a union remote into a chunker remote does not resolve correctly.
  - The dump ignores the configured rclone binary.
  - A missing remote calls `exit(1)`.
  - The full environment, including secrets, is logged at DEBUG.
- **Rotation loop:**
  1. Try the available SAs in natural sort order.
  2. If a trigger fires, ban that SA for the trigger's sleep hours and move to the next SA.
  3. When every SA is banned, suspend the uploader until the earliest unban time.
  - Some of the bookkeeping has issues: one call gets an argument of the wrong type, one write never persists, and the "lift the ban when new SAs are added" branch can never run.
- **Without SAs:** the uploader is suspended for `delay` hours. The suspension is not extended if one is already in place, and a successful upload clears it.

### Mover
- Config: `uploader.<name>.mover = {enabled, move_from_remote, move_to_remote, rclone_extras}`.
- After every upload, successful or not, it runs `rclone move from to`. This is a server-side move, used for example to move from a team drive into the main drive.
- rclone's exit code is ignored.
- Plex throttling still applies, because the upload lock is still held.

### Other settings
- **`can_be_throttled`:** controls only whether this uploader starts the Plex monitor. The `--rc` flags are still added.
- **Schedule window:** `{enabled, allowed_from, allowed_until}` as HH:MM strings.
  - Compared as strings, and the window can wrap past midnight.
  - Badly formatted values allow uploads.
  - It only controls when an upload starts; a running upload is not stopped.

## 3. Hidden cleaner (unionfs whiteouts)
### What it's for
With unionfs-fuse, deleting a file creates a whiteout entry at `<meta>/.unionfs-fuse/<rel>_HIDDEN~`. The cleaner deletes the matching path on the remote, then deletes the local whiteout. For mergerfs the README says to leave `hidden` empty; there is no mergerfs-specific logic.

### Steps
1. Scan the meta folder for entries ending in `_HIDDEN~`, deepest first.
2. Turn each one into a remote path: replace the meta prefix with `hidden_remote`, then strip the suffix with `rstrip('_HIDDEN~')`.
3. Run `rclone delete` on each path using 16 threads. A delete counts as successful when the output doesn't contain "Failed to delete".
4. Run `rclone rmdir`. This counts as successful when the output doesn't contain "Failed to rmdir".
5. Send a notification with the counts.
6. Delete the local whiteouts, then run `find -empty -delete`.

### Issues observed
- File whiteouts are **never** found, because the scan only walks directories.
- `rstrip` removes any of those characters from the end rather than the exact suffix, so file names get truncated.
- The remote delete ignores dry-run, because the argument ends up in the wrong parameter.
- Local whiteouts are deleted even when the remote delete failed.
- The scan crashes when it raises an error.

## 4. Sync
### Config (`syncer.<name>`)
- `service`: `local` or `scaleway`.
- `sync_from`, `sync_to`: keys under `remotes`; each remote's `sync_remote` gives the actual path.
- `tool_path`, `sync_interval` (hours), `rclone_extras`, `use_copy`, `instance_destroy`.
- Scaleway only: `region`, `type`, `image`.

### Lifecycle
- The steps are startup, setup, sync and destroy, all under the sync lock. A notification is sent at every step.

### How a sync runs
- The command is `rclone sync|copy from to [extras] [--dry-run]`.
- The triggers from both remotes are merged. Unlike uploads, the trigger's `sleep` value is honoured.
- rclone's exit code is ignored. A sync only counts as failed when a trigger fires.

### Scaleway agent
- Uses the defunct `scw` v1 CLI.
- Steps:
  1. Create the instance with `scw run`, or start an existing one with `scw start`.
  2. Install rclone on it.
  3. Copy rclone.conf **to the VM**.
  4. Run the sync with `scw exec`.
  5. Copy the VM's rclone.conf back over the local one, without validation.
  6. Remove (`scw rm`) or stop (`scw stop`) the instance.
- Because of a signature mismatch in `error_handling`, a failed setup can leave a **paid VM running**.

### Hetzner
- Not supported.

## 5. Plex throttling
### Polling Plex
- **Request:** `GET /status/sessions` with `X-Plex-Token` and `verify=False`.
- **Validation:** the response must have Content-Type exactly `application/json`.
- **Parsing:** it accepts sessions under either `Video` or `Metadata`.
- **Logging:** the token is written to the error logs.

### Monitor loop
1. Wait 15 s, then check that Plex responds and that rclone RC answers `POST rc/noop`. If either check fails, the monitor stops for the rest of this upload.
2. Repeat every `poll_interval` while the upload lock is held:
   1. Count streams that are playing or buffering. Local streams are excluded when `ignore_local_streams` is true. Paused streams are not counted.
   2. If the count is at least `max_streams_before_throttle`, call `POST core/bwlimit {"rate": ...}`.
   3. If the count drops below the threshold, call `POST core/bwlimit {"rate":"off"}`.
   4. If the speed tier has changed, apply the new tier.

### Speed tiers
- `throttle_speeds` maps a stream count to a rate.
- The tier is looked up by exact stream count. If there's no exact entry, the nearest count is used.

### Re-applying the limit
- `throttle_active()` adds up `core/stats` `transferring[].speed`, divides by 1e6, and treats the limit as active when that value minus 10 is at most the limit.
- If the limit doesn't look active, it is applied again. This catches a new rclone process (the next SA, another uploader or the mover) resetting the bandwidth limit.

### RC security
- RC runs with `--rc-no-auth` and no authentication.

## 6. Notifications and download clients
### Notification agents
- Agents: Apprise (`url`, `title`), Pushover (`app_token`, `user_token`, `priority`) and Slack (`webhook_url`, `sender_name`, `sender_icon`, `channel`).
- Every message goes to every configured agent.
- Messages are plain strings with no levels.

### Events that trigger a notification
- An upload starts, succeeds, fails or is aborted. The abort message includes the suspension in hours.
- A suspension expires.
- Download clients are paused or resumed.
- The mover runs.
- The hidden cleaner finishes, with its counts.
- A sync step runs.
- The Plex throttle changes.
- An exception is raised.

### NZBGet
- XML-RPC `pausedownload` and `resumedownload` at `<url>/xmlrpc`. The URL contains the username and password.

### SABnzbd
- `GET /api?mode=pause|resume&apikey=…`.
- Any HTTP response counts as success.
- A `URLError` aborts the upload loop.
- `pause` is called twice.

## 7. Configuration keys
| Section | Keys |
|---|---|
| `core` | `dry_run`, `rclone_binary_path`, `rclone_config_path` |
| `hidden` | `{"<unionfs meta dir>": {"hidden_remotes": [...]}}` |
| `notifications` | `{name: {service, ...}}` |
| `nzbget` | `enabled`, `url` |
| `sabnzbd` | `enabled`, `url`, `apikey` |
| `plex` | `enabled`, `url`, `token`, `poll_interval`, `max_streams_before_throttle`, `ignore_local_streams`, `notifications`, `rclone.url` (becomes `--rc-addr`, default `localhost:7949`), `rclone.throttle_speeds` |
| `remotes.<name>` | `upload_folder`, `upload_remote`, `hidden_remote`, `sync_remote`, `rclone_command`, `rclone_excludes`, `rclone_extras` (required for uploads), `rclone_sleeps`, `remove_empty_dir_depth` |
| `uploader.<remote>` | `check_interval` (minutes), `max_size_gb`, `size_excludes`, `exclude_open_files`, `opened_excludes`, `can_be_throttled`, `schedule{enabled, allowed_from, allowed_until}`, `service_account_path`, `mover{...}` |
| `syncer.<name>` | See section 4 |

The config has no schema validation.

## 8. Dependencies
- **Python packages:**
  - lockfile (deprecated)
  - schedule
  - requests
  - GitPython (used only for the version check)
  - sqlitedict
  - apprise
  - jsonpickle
  - urllib3
- **External tools:** rclone (including the RC server), GNU `du`, `find`, `lsof`, and `scw` v1.
- **Deployment:** Linux with systemd (`Restart=always`).

## 9. Assessment
### Ideas worth keeping
- Configurable triggers on rclone output.
- Exit code 7 combined with `--drive-stop-on-upload-limit`.
- An SA pool with per-SA unban times that persist across restarts.
- Suspending the uploader until the earliest unban time.
- Injecting the SA file through environment variables after walking wrapper remotes.
- Tiered Plex throttling through RC, re-applied after a reset.
- Excluding open files from uploads.
- A schedule window that can wrap past midnight.
- Pausing download clients during uploads.
- The server-side mover.
- Refusing `sync` as an upload command.
- Notifications when suspensions start and expire.

### Behaviours to improve in Autoplow
- **Brittle rclone integration.** It parses rclone's text output instead of `--use-json-log`, rcd or RC jobs.
- **Polling.** It runs `du` and `lsof +D` over the whole tree, and polls Plex.
- **One thread.** The scheduler is single-threaded, so one upload blocks everything else.
- **Code structure.**
  - State lives in globals, and the process exits after any config upgrade.
  - It shells out through `os.popen` and `shell=True`.
  - There are no tests, and broad `except` blocks swallow errors.
- **Inflexible bans.** Bans are measured in whole hours, and several are hard-coded to 25 h.
- **Ignored exit codes.** The mover and the syncer don't check rclone's exit code. `process.execute` also drops the last line of output and busy-spins.
- **Security.**
  - `--rc-no-auth`.
  - Secrets are logged: the Plex token, the full environment, and the NZBGet password in the URL.
  - `verify=False`.
  - rclone.conf is copied to and from the VM without checks.
- **Dead integration.** The Scaleway `scw` v1 CLI no longer exists.

### What a successor should change
- Drive rclone through rcd and RC jobs, or JSON logs.
- Run a worker per remote, concurrently.
- Use a typed, validated config.
- Track folder size from events or a cache instead of running `du`.
- For whiteouts: match the suffix exactly, handle both files and directories, and only delete the local whiteout once the remote delete is confirmed.
- Make ban durations configurable and shorter than an hour.
- Put authentication on RC, or use a unix socket.
- Never log secrets.
