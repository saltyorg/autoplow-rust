# ADR-0018: Autoplow runs as a service on the host

## Status
Accepted

## Date
2026-11-10

## Context
No document said how Autoplow is deployed. Several specs quietly assumed a container: a container image as a build target, an image that ships a pinned rclone, and open-file detection described through container flags (`pid: host`, `SYS_PTRACE`). That assumption was never decided and it is wrong for Saltbox, where Autoplow is meant to run on the host, as cloudplow does.

## Decision
- **Host service.** Autoplow runs on the host as a systemd service. v1 ships static binaries and an example unit. There is no container image in v1.
- **User.** The service runs as the Saltbox user, the same user that owns the media files. It does not run as root.
- **Capabilities per feature.** A feature that needs more than that user can do declares the capability it needs, and the unit grants it. At start, each such feature checks whether it can actually work. If it can't, it switches itself off, says so in the UI, and everything else keeps working.
- **rclone.** Autoplow uses the rclone installed on the host. Nothing is bundled.
- **Logs.** Written to standard output, for the journal, and to a file that Autoplow rotates itself.
- **Environment.** Settings needed before the database is open (the secret key, the listen address, the data directory) come from the service's environment.

## Alternatives Considered
### Container image as the primary deployment
- **Pros:** the usual way to ship a Saltbox app; isolated.
- **Cons:** the upload module must see the host's files, mounts and the processes that hold files open. In a container that needs host PID access and extra privileges, and paths differ between container and host.
- **Rejected:** the daemon's job is host-level.

### Host service plus a container image for other users
- **Pros:** reaches self-hosters outside Saltbox.
- **Cons:** a second deployment to build, document and test, with its own rclone packaging.
- **Rejected for v1.** It can be added later without changing the design.

### Run as root
- **Pros:** every feature works without capability handling.
- **Cons:** the broadest privilege, and files Autoplow creates would need their ownership corrected.
- **Rejected:** capabilities are granted per feature instead.

## Consequences
- **Amends earlier text:** the "container image ships a pinned rclone" consequence in ADR-0003, and the container image listed as a build target.
- **Networking:** media servers and Arrs usually run in containers and call back to a service on the host. The callback base URL has to be an address they can reach; the Saltbox role sets it.
- **Health and shutdown:** systemd supervises the process. Docker health checks and stop timeouts do not apply.
- **Self-hosters outside Saltbox** run the same binary and unit.
