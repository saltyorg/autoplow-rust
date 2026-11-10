# ADR-0020: What a target can see decides when it is scanned

## Status
Accepted. Amends [ADR-0011](0011-upload-readiness-model.md) ("scanned first").

## Date
2026-11-10

## Context
Autoplow both uploads files and tells media servers to scan. Walking an import through both showed a gap: after a move, the file is gone from local disk and appears on the cloud mount only when that mount refreshes. A scan sent in between makes the server treat the item as deleted. The upload rule "scanned first" also assumed every server can see a file before it is uploaded.

Neither holds in general. A media server may run on another machine and see media only through its own mount of the remote, so it cannot see a file until after the upload. And Autoplow can only check files on its own disks, never on another machine's.

## Decision
- Each target says where it runs: on the **same system** as Autoplow, or **elsewhere**.
- **Same system:** the server sees a file as soon as it is imported. Scans go out after the normal wait and the upload waits for them. If the file was already uploaded, the scan waits until the file is visible again, for at most the mount's propagation delay.
- **Elsewhere:** the upload comes first. The scan waits for the upload to finish and then for that target's propagation delay. Time is the only gate.
- **File checks** ("path must exist", visibility after upload) are made only for same-system targets.
- A destination records the scan-side path of its local folder, so uploads and scans agree on which folder is which.
- A local delete caused by Autoplow's own move is not an event.

## Alternatives Considered
### One fixed delay after every upload, for every target
- **Pros:** simple.
- **Cons:** delays scans for servers that can already see the file, and is still a guess for the ones that cannot.
- **Rejected:** Autoplow knows where the file is and should use that.

### Check file visibility for every target
- **Pros:** no guessed delays.
- **Cons:** impossible for a server on another machine.
- **Rejected.**

### Refresh the mount through its own rclone remote control after each upload
- **Pros:** closes the gap in seconds.
- **Cons:** one more connection to configure, and no help for a server elsewhere.
- **Not in v1.** It can be added later without changing the rule.

## Consequences
- Targets gain one setting and a propagation delay for a server elsewhere. Destinations gain a scan-side path, which Saltbox's bootstrap fills in, and a delay of their own for the mount on this host.
- `scan` is built before `upload` and must not depend on it. Scan defines the two questions it needs answered (where a folder's file is; whether a local delete was Autoplow's own move) and `upload` supplies the answers.
- "Scanned first" applies to same-system targets only.
- The scan queue has new wait reasons: waiting for the upload, and waiting for the mount.
