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
