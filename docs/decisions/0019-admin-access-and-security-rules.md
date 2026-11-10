# ADR-0019: Admin access is a shell, and the rules that follow

## Status
Accepted. Amends [ADR-0007](0007-seed-once-bootstrap-and-rest-api.md) ("Secrets are write-only").

## Date
2026-11-10

## Context
A security review of the whole design, after each spec had been reviewed on its own, found that no document stated what admin access to Autoplow is worth. The admin chooses which rclone binary runs, with which options and environment, and can create a move from any local folder. So admin access is the ability to run programs as the service account, which owns all the media.

Several earlier decisions were made without that in view:
- Sign-in could be switched off for installs behind an authenticating proxy. Autoplow's port must be reachable by containers for callbacks, so those callers never pass through the proxy.
- The first-start setup page skipped its token for requests "from the host itself". Behind a proxy on the same host, every request looks local.
- ADR-0007 said secrets are write-only. Later the admin was given a way to read stored secrets, without an ADR.

## Decision
- **State it.** The core spec says that admin access is equivalent to a shell as the service account, and carries a "Security rules" section that every module follows.
- **Sign-in is always on.** The switch to turn it off is removed.
- **The setup page always asks for its token,** and does not exist while a bootstrap file is present.
- **Stored secrets can be shown to the admin** (masked by default, one at a time, through an admin-only endpoint). This replaces "write-only" in ADR-0007. Showing a secret is logged as a security event. Plex user tokens are the exception and are never shown.
- **The rclone settings are filtered by family,** not by a short list, and the child gets a clean environment without Autoplow's key.
- **Read-only keys** cannot call anything but `GET`, and a named set of `GET`s is admin-only. A third scope reads metrics only.
- The remaining rules (request origin, sessions, files, outbound redirects, response headers, trigger limits) are listed in the core spec.

## Alternatives Considered
### Keep "sign-in off", but only for requests from a trusted proxy
- **Pros:** one login fewer behind an authenticating proxy.
- **Cons:** correctness depends on the trusted-proxy list being exact; a list that covers the container network reopens the hole.
- **Rejected:** sessions last 30 days, so the saving is one login a month.

### Require the password again before a secret is shown
- **Pros:** a stolen session cannot read every secret.
- **Cons:** the admin asked for secrets to be easy to check, and a stolen session already allows running programs.
- **Rejected:** logging the event gives the trace without the friction.

### Keep the local shortcut on the setup page, with strict checks
- **Pros:** convenient on a desktop install.
- **Cons:** easy to get wrong behind any proxy, and the cost of being wrong is the whole host.
- **Rejected.**

## Consequences
- An install behind an authenticating proxy signs in twice.
- The systemd unit ships with hardening options, and releases publish checksums and a build attestation that the Saltbox role verifies (task 12.2).
- A stolen backup together with the secret key still yields every stored secret; without the key it yields the password hash and metadata, which is why the data directory is private.
