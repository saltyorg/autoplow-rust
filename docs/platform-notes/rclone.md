# rclone

Verified 2026-10-27 against rclone v1.75.1 and v1.75.2: live spikes plus source reading (`lib/atexit`, `fs/operations/copy.go`, `fs/config/config.go`, `librclone/librclone/librclone.go`).

## RC API (the same over `rcd` HTTP and in-process `librclone.RPC`)
- `librclone.RPC` dispatches through the same `rc.Calls` table that `rcd` serves, so the methods and parameters are identical (`_async`, `_group`, `_config`, `_filter`).
- **In-process RPC can't run methods that need the HTTP request or response** (`operations/uploadfile`, `core/command`; returns 404). `rcd` can.
- **Verified working:**
  - `config/create` (including crypt with `obscure`)
  - `operations/movefile` and `copyfile`
  - async `job/batch` (results in input order)
  - `sync/move` with per-call `_filter`/`_config`
  - a live `core/bwlimit` change mid-transfer
  - `job/stop` (source intact, nothing left at the destination)
- **Transfer stats** carry the full relative `name` plus `srcFs`, `dstFs` and `group`, so items with the same basename can't be confused.
- **Gotchas:**
  - `core/stats` `speed` is an average over the whole run and lags limit changes. Measure the change in `bytes` over a time window.
  - **Stats groups accumulate** until `core/stats-delete` is called.
  - `core/bwlimit` is process-wide (one token bucket for every transfer).
  - A move within the same local filesystem is a rename: instant, with no progress, limit or cancellation window.

## Supervised `rcd`
- **Startup and isolation:**
  - `rclone rcd --rc-addr unix:///path/rc.sock --config <file>` answers `rc/noop` in about 50 ms.
  - The socket is created mode 755, so put it in a 0700 directory.
  - The socket keeps the API off the network.
- **When the child is killed in the middle of a transfer:**
  - The source stays intact.
  - **All job state is lost.** After a restart, `job/status` for the old id returns "job not found", so the host must re-queue from its own state.
- **Signal isolation:** rclone's signal handling (below) stays inside the child.

## Options given to `rcd` and operations started through its API
Verified 2026-11-11 against rclone v1.75.1, with a short-lived `rcd` on a unix socket and an empty config. The observable used was the local backend's `--links` option, which changes what `operations/list` returns for a symlink, and `options/get` for global options.

- **Global options on the `rcd` command line apply to API operations.** `--tpslimit 8 --transfers 2` show in `options/get` as the daemon's running values.
- **Backend options on the `rcd` command line apply to backends created through the API.** With `--links` (or `--local-links`) on the command line, `operations/list` over the API returned the symlink as a `.rclonelink` entry; without it, the symlink was left out.
- **The same options given as environment variables apply too** (`RCLONE_LOCAL_LINKS=true`, `RCLONE_TPSLIMIT=5`).
- **A backend option given this way applies to every remote of that backend type.** A per-remote value belongs in `rclone.conf`, or in a connection string on the call (`:local,links=false:/path` overrode the daemon's `--links` for that call).
- **Per-call `_config`** overrides a global option for that call only, with the exceptions listed under "What a running `rcd` accepts" below.
- **`--tpslimit` is one limit for the whole daemon, shared by every backend.** Measured against a local WebDAV server: a recursive listing of 7 folders took 0.1 s without a limit and 6.0 s with `--tpslimit 1`; two such listings run at once through two separate backend instances took 14.0 s together, so they drew from one bucket. It cannot express a different rate for a different provider.
- **Per-call `_config` cannot set it.** The same listing with `_config: {"TPSLimit": 1}` on a daemon started without a limit still took 0.1 s.
- **An option can be set for one named remote on one call** by writing it into the remote part of the path: `name,option=value:path`. With `loc` and `loc2` both plain local remotes in the config, `loc,links=true:` listed the symlink while `loc:` and `loc2:` in the same daemon did not, and the config file was unchanged. This is how one remote can get its own backend options, including a backend's own pacing options, without editing `rclone.conf`. The remote can also be given as a JSON object (`{"_name": "loc", "links": true}`), which leaves the quoting to rclone.
- **Not verified here:** an option of a cloud backend such as Drive's chunk size, which needs a real remote to observe. It is registered and read the same way as the local backend's option, so the same result is expected, and the first live upload test should confirm it.

## What a running `rcd` accepts
Verified 2026-11-11 against rclone v1.75.1: a short-lived `rcd` on a unix socket with a scratch config, local `rclone serve webdav` and `rclone serve sftp` servers as remotes, and a crypt and an alias remote on top. Timing of a recursive listing (8 requests) shows pacing; the user agent seen by the server shows connection settings. Source read at v1.75.2 where marked *(source)*. No cloud remote was used, so everything about Drive, Dropbox and other cloud backends is *(source)*.

### Global options
- `options/set` writes the running value. It takes effect only where rclone reads the option again.
- **Read when a transfer or job starts** (so they apply to the next one, not to one already running): `Transfers`, `Checkers`, `BwLimitFile`, and *(source)* `BufferSize`, the multi-thread options, the compare options and `LowLevelRetries` for the copy itself.
- **Fixed when a remote is opened:** `UserAgent`, `Dump`, and *(source)* timeouts, HTTP/2, proxy, headers, certificates and the pacer's retry count. A remote already open keeps the old value.
- **Read once at start; `options/set` changes nothing:**
  - `TPSLimit` and `TPSLimitBurst`. A daemon started with `--tpslimit 2` kept that rate after `options/set` to 1000 and to 0, and one started without a limit stayed unlimited. No other call changes it.
  - `BwLimit`. Only `core/bwlimit` changes the live limit.
  - The remote cache's expiry times, and *(source)* `UseMmap` and `MaxBufferMemory`.
- `LogLevel` and the `rc` block's `JobExpireDuration` apply at once. A finished job's status is dropped after 60 s by default.
- `--retries` is not used by API operations at all *(source)*; the caller retries.

### Per-call `_config` and `_filter`
- `_config` gives the job a private copy of the global options. Two jobs running at once with different `Transfers`, or different `BwLimitFile`, each kept their own.
- It does not affect `TPSLimit` or `BwLimit`, which are single buckets for the process.
- **Connection settings in `_config` stick.** They are used by whichever call first opens the remote, and later calls get that remote from the cache with the first call's value, whatever they pass.
- `_filter` applies to `sync/*`. `operations/copyfile` and `movefile` name one file and use no filter *(source)*.
- Since 1.75.0, a top-level parameter named like a global flag is read as config, so a client must send no stray parameters.

### Options for one remote
- **Precedence, highest first:** the remote address on the call; a backend flag or `RCLONE_<BACKEND>_<OPTION>` variable on the daemon; `RCLONE_CONFIG_<REMOTE>_<OPTION>`; `rclone.conf`; the default. The second and third are the other way round in rclone's documentation. So a backend option given to the daemon overrides the per-remote values in `rclone.conf`.
- **`override.<global option>`** (rclone 1.71 and later) in a remote's address or config section gives that remote its own value for anything fixed when a remote is opened: user agent, timeouts, `max_connections`, low-level retries. It works through `rcd`. It cannot give a remote its own `tpslimit` or bandwidth limit.
- **Unknown option names are ignored silently** in a remote address, in `override.*` and in `_config`. Only a bad value is an error. `config/providers` and `options/info` list the names the running rclone knows.
- **A remote that wraps another does not pass options down.** A pacing option on a crypt remote had no effect; the same option written into the crypt remote's `remote` value (`cr,remote="wd,pacer_min_sleep=500ms:crypt":`) did.
- `backend/command` with Drive's `set` writes into `rclone.conf` *(source)*.

### One opened remote, one pacer
- rclone keeps opened remotes in a cache, keyed by name, overridden backend options and root path. An entry expires 5 minutes after last use; a running job keeps its own alive.
- Options are read once, when the remote is opened.
- **Each cache entry has its own request pacer.** Two listings through one root shared a pacer (7.5 s); the same two addressed as two sub-folders ran at twice the rate (4.0 s). Addressing a remote by its root, with the whole path in the file argument, keeps one pacer per remote.
- **`override.*` values are not part of the key.** If the plain remote is already cached, an address that differs only in `override.*` gets the cached one. A differing backend option does make a new entry; `description` exists on every backend and can serve as that difference.
- `fscache/clear` empties the cache. Transfers already running finished normally on WebDAV and SFTP. It also shuts a backend down where the backend has a shutdown step; for Dropbox that ends its batch committer *(source)*, so clearing while Dropbox uploads run is not safe.
- **Tunable pacing** *(source)*: Drive (`pacer_min_sleep`, `pacer_burst`), Dropbox and WebDAV (`pacer_min_sleep`), Zoho. OneDrive, B2, S3, Box, Google Cloud Storage and Azure Blob have fixed values. WebDAV's was measured: 500 ms on one remote made its listing take 4.0 s while two other remotes stayed at 0.09 s.
- `override.max_connections=2` held four concurrent uploads to two at a time on WebDAV. rclone's documentation warns that the option can deadlock.

### `rclone.conf` changes
- rclone checks the file's size and modification time on every config access and re-reads it when they differ. No call is needed.
- A remote added by another process was listed by `config/listremotes` and usable at once. An edited remote kept its old values while cached and used the new ones once opened afresh. A removed remote failed the next time it was opened.
- rclone saves a renewed token by writing a new file and renaming it over the old one, so a watcher must watch the folder.
- **Encrypted config:** the key is kept after the first read, so later re-reads need no password. After the password was changed by another process, config calls failed until `config/unlock` was called, and the file was not re-read until it changed again.

### Bandwidth and concurrency
- `core/bwlimit` takes one value or `up:down`, not a timetable. With `2M:off`, an upload was held to 2 MiB/s, but a copy between local folders was not limited at all; with `2M` it was.
- There is no limit per group, job or remote *(source)*. `BwLimitFile` in `_config` caps one transfer and is fixed when it starts.
- **`--transfers` does not cap single-file jobs.** On a daemon started with `--transfers 1`, four async `operations/copyfile` jobs transferred at once. It sets the workers inside one `sync/*` job.

### How values are parsed
Verified 2026-11-11 against rclone v1.75.1. Global options were set with `options/set` and read back with `options/get`; a backend size option was observed as the chunk sizes written by a chunker remote over a local folder; `core/bwlimit` reports the rate it applied.

| Sent | As a global option (`options/set`) | In a remote address | To `core/bwlimit` |
|---|---|---|---|
| `"32Mi"`, `"32M"`, `"32MiB"`, `"32mi"` | 32 MiB | 32 MiB | 32 MiB/s |
| `"1.5Mi"` | 1 572 864 bytes | 1 572 864 bytes | 1 572 864 bytes/s |
| `"32MB"` | error | error | error |
| `"1 Mi"` (with a space) | not tested | error | not tested |
| `"33554432"` (digits as text) | **32 GiB**: read as KiB | **read as KiB** | **read as KiB/s** |
| `33554432` (JSON number) | 32 MiB: read as bytes | error: values must be text | not tested |
| `"33554432B"` | 32 MiB | 32 MiB | 32 MiB/s |

- **Sizes:** the unit letters are powers of 1024 with or without the `i`. Bare digits as text are KiB. A JSON number is bytes in `options/set` and is refused inside a remote address given as a JSON object. The `B` suffix is the one form read as bytes everywhere.
- **Durations:** `"150ms"`, `"0.15s"`, `"5m"`, `"1h30m"` and `"2d"` are read as written. Bare digits as text are **seconds** (`"300"` is 5 minutes); a JSON number is **nanoseconds** (`300` is 300 ns).
- **Yes/no:** `options/set` accepts only JSON `true` and `false`; `"true"`, `"yes"`, `1` are errors. Inside a remote address only the text `"true"` or `"false"` is accepted; JSON `true` and `"yes"` are errors.
- **Whole numbers** inside a remote address must be text (`"5"`); a JSON number is an error.
- `options/get` returns sizes as bytes and durations as nanoseconds. `options/info` and `config/providers` give each option's type (`SizeSuffix`, `Duration`, `bool`, `int`) and its default both as a number and as text (`16777216` and `16Mi`).
- `core/bwlimit` answers with `bytesPerSecond`, so the applied rate can be compared with the intended one. `"off"` and `"0"` remove the limit.

### Options that run a program
- sftp `ssh` (observed: the named program ran when the remote was opened) and the global `metadata_mapper` given in `_config` (observed).
- *(source)* WebDAV `bearer_token_command`, `name_transform` in its command form, `password_command`.

### Cost of more processes
- An idle `rcd` used about 65 MB, and about 130 MB during four concurrent uploads. A single `rclone copyto` used about 83 MB mid-transfer. `rcd` answered its first call about 0.1 s after start.

### Still to confirm on a real remote
- Drive and Dropbox chunk and pacing options through a remote address, and the error a Drive upload returns with `stop_on_upload_limit`.
- Dropbox batch commits with one job per file.
- Token renewal with one OAuth remote opened twice in the daemon beside a mount using the same config.

## Crypt name decoding through the API
Verified 2026-11-11 against rclone v1.75.1. Ten crypt remotes over local folders covered `filename_encryption` standard (with `filename_encoding` base32, base64 and base32768), obfuscate and off, each with `directory_name_encryption` on and off. Files with accented, CJK and 120-character names were copied in through each remote, the stored names were listed with `operations/list` on the underlying folder, and `backend/command` with `decode` was compared against the original paths.

- **Call:** `backend/command` with `{"command": "decode", "fs": "<crypt remote>:", "arg": [paths…]}`. The result is a list of decoded paths in the order given.
- **A full file path decodes correctly in all ten modes,** including when folder names are stored in plain text and when file names are stored in plain text with the `.bin` suffix.
- **A folder path fails when folder names are not encrypted.** `decode` treats the last segment as a file name, so a plain folder name is an error ("not a multiple of blocksize", "does not match suffix"). The same call works when folder names are encrypted.
- **A folder path can be decoded in every mode by appending an encoded file name.** `encode` of a one-letter name gives that name as the remote stores it; `decode` of `<folder path>/<that name>` returned `<decoded folder path>/<the letter>` in all ten modes. This needs no knowledge of the remote's settings.
- **Paths are relative to the crypt remote's own root.** A path that still carries the folder the crypt remote stores in is an error. A leading slash is accepted and kept.
- **One bad name fails the whole call** with status 500 and the first failing name in the message; no partial result is returned. Finding which names fail means splitting the list and calling again.
- **A wrong password fails the same way** ("bad PKCS#7 padding"), for every name.
- **Size:** 50 000 paths in one call (a 10.7 MB request) were decoded in 0.3 s.
- **Names must be the stored names as rclone sees them.** Listing the folder with operating-system tools gave different text for base32768 names on a local disk, because the local backend re-encodes some characters. Names taken from the Drive API are not affected by that local-disk translation; this was not tested against Drive.

## Signal handling hazard (any process that runs rclone code in-process)
- `lib/atexit` installs `signal.Notify(SIGINT, SIGTERM)` the first time anything calls `atexit.Register`.
- `fs/operations/copy.go` does this for any copy that uses a partial file (destinations with partial-upload support, for example local and sftp). The hook stays for the life of the process.
- **On SIGTERM it runs rclone's cleanup and then `os.Exit(143)`.** Verified with both a Go host and a Rust host (FFI): the host received SIGTERM, but the process exited before its own shutdown could finish.
- Running rclone as a separate process avoids this.

## Config path (in-process use)
- **`RCLONE_CONFIG` is resolved during package initialisation.** Setting it later from `main` has no effect, and new remotes are written to `~/.config/rclone/rclone.conf`. Call `config.SetConfigPath` before `librclone.Initialize()`.
- **Package initialisation creates `~/.config/rclone/`** unless `RCLONE_CONFIG` or `--config` is present when the process starts.

## Mounts and Drive change visibility
- An `rclone mount` sees Drive changes only when its own `--poll-interval` fires (default 1 m; often configured lower).
- **Implication:** scans triggered by the Drive Changes API should wait at least that long (the minimum-age default).

## Embedding from Rust
- The `librclone` crate builds rclone as a Go c-archive in `build.rs`; it was pinned to rclone v1.69 at its last release (2025-02).
- A Go c-archive linked into Rust works, including concurrent calls from many threads, but needs cgo and produces a glibc-dynamic binary.
- See [../research/rust-vs-go.md](../research/rust-vs-go.md).
