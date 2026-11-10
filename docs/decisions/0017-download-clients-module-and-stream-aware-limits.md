# ADR-0017: Download clients as their own module, limited by stream activity

## Status
Accepted

## Date
2026-11-10

## Context
ADR-0014 put "stream-aware throttling" in v1, meaning rclone's upload bandwidth. A new requirement widens it: some users want their download clients' download and upload speeds limited while people are watching, whether or not they use Autoplow's uploads.

The plan did not allow this:
- Download clients existed only inside `upload`, and only to be paused.
- `throttle` could not reach them, and could not run without rclone.
- Only SABnzbd and NZBGet were supported, and usenet clients have no upload to limit.

## Decision
- **New module `downloaders`.** It holds the clients and is the single owner of what Autoplow asks of them: pause state and speed limits. `upload` and `throttle` hand it requests and never call a client themselves. It is built before `upload`.
- **Clients in v1:** SABnzbd, NZBGet and qBittorrent. qBittorrent is limited but not paused.
- **Separate limits per limiter.** rclone upload, and each client's download and upload speed, have their own mode and limits. There is no shared bandwidth budget.
- **Autoplow owns a managed client's limit.** The limit with no streams is set in Autoplow, and a limit changed in the client is overwritten.
- **The throttle no longer requires uploads.** Any combination of limiters can be switched on.

The details are in [the downloaders spec](../specs/downloaders.md) and [the throttle spec](../specs/throttle.md).

## Alternatives Considered
### Keep the clients inside `upload`
- **Pros:** no new module.
- **Cons:** `throttle` would depend on `upload`, so limiting download clients would require the upload module, which the requirement rules out.
- **Rejected.**

### Put the clients inside `throttle`
- **Pros:** no new module.
- **Cons:** `upload` would depend on `throttle` just to pause a client, and `throttle` would own the free-space guard.
- **Rejected:** two modules changing one client need one owner that is neither of them.

### One upstream budget shared by rclone and seeding
- **Pros:** uses spare upstream automatically.
- **Cons:** needs a priority rule and makes the by-bitrate maths much harder to predict and to test.
- **Rejected for v1:** each limiter has its own limits.

### Restore the client's previous limit when idle
- **Pros:** the client's own settings stay untouched.
- **Cons:** the "previous" value is ambiguous after a crash or a manual change, and it is hard to show the user what will happen.
- **Rejected:** the idle limit is set in Autoplow.

## Consequences
- **Scope:** v1 grows by one module and one torrent client. This amends the scope in ADR-0014.
- **Verification:** each client's pause and limit API is verified and recorded as a platform note before it is implemented.
- **Conflicts:** a client's own scheduler or alternative-speed mode can override Autoplow. Where detectable, it is reported and never changed.
- **Plan:** a `downloaders` phase is inserted before `upload`, and the later phases move up by one.
- **UI:** download clients move to their own Settings section, and the Throttle page shows every limiter.
