# Rust vs Go for Autoplow: feasibility pass (2026-10-27)

This compares the two languages against the backend as specified (`docs/architecture.md`, `docs/specs/`, `tasks/plan.md`). It is based on measured spikes plus a survey of the library ecosystem.

## 1. rclone embedding: the hard constraint (measured)
**Spikes:**
- A Go host running rclone in-process through `librclone`.
- A Rust host linking a Go **c-archive** shim of `librclone`. The shim adds an explicit config-path setter.

(The spike code is not part of this repository; the findings are recorded here and in `docs/platform-notes/rclone.md`.)

**Setup:** rclone v1.75.2, the same curated backends, and the same checks in both spikes.

| | Go host | Rust host (Go c-archive via FFI) |
|---|---|---|
| All spike checks (config/create + obscure, movefile, async batch with duplicate basenames, filters, live bwlimit, job/stop, errors, stats cleanup) | ✅ | ✅ |
| Concurrent RPC from many threads | n/a (goroutines) | ✅ 400 `core/stats` calls from 8 tokio threads during a transfer |
| Peak RSS for the same run (4-core cap) | 129 MB | 138 MB (dominated by rclone itself) |
| Binary | 34.4 MB, **fully static** (`CGO_ENABLED=0`) | 39.7 MB, **dynamically linked to glibc**. A static musl binary would need the Go archive built with a musl C toolchain (`CGO_ENABLED=1` + musl-gcc/zig). Not verified. |
| Build | one `go build` | two toolchains: `go build -buildmode=c-archive` (25 s, needs cgo and gcc) → 50 MB `.a`, then `cargo build` linking it |
| Event-driven job completion (`jobs.OnFinish`) | ✅ native Go call | ❌ not exposed by the C ABI. Poll `job/status`, or extend the shim with a C callback. |
| Calling rclone Go APIs directly (beyond the RC JSON calls) | possible | only through new shim exports, one per function |
| Debugging and profiling | one runtime, pprof | two runtimes in one process; Go's pprof and Rust's tooling each see half |

### Signal hazard found (applies to **both** hosts)
- **What happens:** rclone's `lib/atexit` installs `signal.Notify(SIGINT, SIGTERM)` the first time anything calls `atexit.Register`. `fs/operations/copy.go` does this for every copy that uses a partial file (destinations with partial-upload support, such as local and sftp). The hook stays for the life of the process. On SIGTERM it runs rclone's cleanup and then **`os.Exit(143)`**.
- **Evidence:**
  - Rust host after a local→local copy: tokio received SIGTERM, then the process exited with 143 before the host could finish.
  - Go host, the same test: "GO HOST RECEIVED SIGTERM", then exit 143.
- **Impact:** graceful shutdown (draining queues, resuming downloaders, persisting state) can be cut short in either language.
- **Mitigations:**
  - **Go:** register our shutdown through `atexit.Register` so it runs inside rclone's handler, or keep partial-file copies off with `options/set {"main":{"Inplace":true}}` / `_config` where acceptable. Cloud destinations such as Drive don't use partial files anyway.
  - **Rust:** the same, but registering a host callback means adding a C-callback export to the shim.
- **This is a design item regardless of language.**

## 1b. Every Rust route to rclone (checked 2026-10-27)
| Route | Status | Evidence |
|---|---|---|
| **A. Own Go c-archive shim (FFI, in-process)** | ✅ works (section 1) | measured spike |
| **B. `librclone` crate** (trevyn) | Same mechanism as A, compiled in `build.rs` (needs Go). **Pinned to rclone v1.69, last release 2025-02** | 52 stars, 1 reverse dependency (`xvc-storage`). Celeste (1.6k stars) used it, but **is archived** |
| **C. Supervised subprocess `rclone rcd` over the RC HTTP API** | ✅ works | measured spike. Typed client available: `rclone-sdk` 1.75 (generated from OpenAPI, 0 reverse deps). Prior art: **rustic** spawns `rclone serve restic`; our Go autoplow v1 supervised `rcd` |
| **D. Pure Rust, no rclone** (Apache OpenDAL, rclone-crypt crates) | ❌ not viable | OpenDAL has gdrive/s3/sftp/dropbox/onedrive but no crypt, union or chunker, and no `rclone.conf` compatibility. The Rust crypt crates are stale (2021) or decrypt-only CLIs. We decided to use the user's existing `rclone.conf`, which includes crypt remotes |

### Route C, measured (rclone v1.75.1, unix socket)
- **Startup:** `rcd` was ready in about 52 ms. The RC API is on `unix:///…/rc.sock`, so it is never on the network (socket created mode 755; put it in a 0700 directory).
- **Transfers:** config/create (obscured, our config path) and an async batch with duplicate basenames passed, the same as in-process.
- **Child crash (`kill -9` in the middle of a transfer):**
  - The source was intact.
  - RC calls fail with "connection refused".
  - After the supervisor restarts `rcd` (52 ms), **all job state is gone** (`job not found`), so the host must re-queue from its own database. That is already the design. The re-queued move completed.
  - The destination listing showed one entry besides the six batch files, probably the interrupted transfer's partial file. Not verified.
- **Signal isolation:** after a local→local copy (which installs rclone's atexit hook), SIGTERM to the host is handled normally. **The hook lives in the child, so the atexit hazard disappears.**
- **Memory:** host 4 MB plus `rcd` 162 MB. The host binary is 1 MB.
- **Trade-offs:**
  - A second process to supervise.
  - The rclone version comes from the system (Saltbox installs it) or has to be bundled in the image.
  - No `OnFinish`, so job status is polled.
  - The control channel is a socket instead of a function call.
- **Route C is language-neutral.** Go could use it too.

## 2. The rest of the backend (survey; sources in the research report)
| Component | Rust | Go | Verdict |
|---|---|---|---|
| HTTP server, OpenAPI, SSE, embedded SPA | axum 0.8 + utoipa 6 (annotations can drift from handlers), rust-embed | huma v2 (spec derived from handler signatures), chi/stdlib, `embed` | parity, slight Go edge |
| HTTP client, size limits, Retry-After | reqwest 0.13 (rustls + aws-lc-rs by default, which needs cmake/C for cross builds) | stdlib; autoscan's http.go is reusable | Go |
| WebSocket clients | tokio-tungstenite | coder/websocket | parity |
| SQLite (WAL, writer + readers, static) | rusqlite `bundled` (C amalgamation, needs a C cross toolchain); sqlx adds build friction | modernc (pure Go, CGO off) | Go for builds and simplicity |
| YAML strict config, line/column errors, JSON Schema | serde + schemars + **serde-saphyr** (serde_yaml archived, churn) | goccy/go-yaml strict; go-yaml v3 archived, v4 not released | **Rust** |
| Recursive inotify | `notify` recursive mode | fsnotify has **no** recursion (about 150 lines of our own) | Rust, slightly |
| /proc (fdinfo flags, locks, cgroups) | procfs: no fdinfo flags | prometheus/procfs: no /proc/locks | parity (each needs one small parser) |
| Google OAuth and Drive Changes | `oauth2` ok; `google-drive3` heavy and awkward, so hand-roll 3 endpoints | official `x/oauth2` + `google.golang.org/api/drive/v3` | **Go** |
| Fake clock for tests | `tokio::time::pause` (tokio timers only, not `SystemTime`) | `testing/synctest` (fakes all `time`, including `Now`) | parity, slight Go edge for the debounce logic |
| Metrics, logging, redaction | prometheus-client, tracing, `secrecy` (type-level) | client_golang, slog | parity |
| Crypto (argon2/bcrypt, AES-GCM) | RustCrypto (new majors, churn) | x/crypto + stdlib | parity |
| Plex/Jellyfin/Emby/Arr clients | effectively none | golift/starr (Arrs), generated Plex/Jellyfin clients, our autoscan code | **Go** |
| Static musl and arm64 cross builds | cargo-zigbuild; C dependencies (SQLite, aws-lc) and **the Go c-archive** complicate it | `CGO_ENABLED=0 GOARCH=arm64` | **Go** |

## 3. Ecosystem and people
- **saltyorg tooling is overwhelmingly Go:** sb-go, sdc, sdhm, svm-go, the autoscan fork, the earlier autoplow.
- **Rust prior art:** autopulse, the Tofa server, saltyorg/ansible-facts.
- **Compile times:** Rust with axum, utoipa, reqwest/aws-lc, rusqlite and tokio typically takes minutes for a cold release build. Go builds incrementally in seconds. That matters for CI and arm64 cross builds.

## 4. Conclusion
**Rust is feasible.** The FFI spike works, including concurrent calls and signals, at about the same memory. But for this backend it costs:
- two toolchains and cgo in every build
- a non-static binary unless a musl C toolchain is set up for the Go archive
- no `OnFinish` events or direct rclone APIs without growing the shim
- weaker libraries in Autoplow's riskiest areas: Drive, the media-server and Arr clients, static cross builds

Rust's real gains are typed config and schema (serde, schemars, serde-saphyr), recursive `notify`, and a stronger type system for state machines. They don't outweigh the rest.

**Updated recommendation (after testing every route):**
- **Rust is feasible two ways:** in-process FFI (route A) and a supervised `rcd` (route C).
  - **Route C** gives Rust a clean single-toolchain build (a 1 MB host, fully separate from Go) and isolates rclone's signal hook. The cost is giving up true embedding: a second process, polled job status, and a separate rclone version.
  - **Route A** keeps embedding, at the cost of a cgo build and a two-runtime process.
- **Go** keeps embedding with a single static binary and native rclone APIs. It has to handle the atexit hook itself. Go can also choose route C later through the same `Transport` interface.
- **The language choice now comes down to the backend libraries (section 2, where Go is stronger), and to whether "embedded" is a hard requirement.** If it isn't, Rust plus route C is a credible option.
