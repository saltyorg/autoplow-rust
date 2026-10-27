# Plex Media Server

Verified 2026-10-27 with live tests against a current Plex Media Server, using tiny test libraries with Plex's own automatic scanning turned off. Timings were polled once per second.

## Partial scans (`GET /library/sections/{id}/refresh?path=<folder>`)
- A new episode, a 10-episode season pack, an upgrade (new file name, old file removed), a file rename, a show-folder rename (both old and new folders scanned), and a new movie were all **visible at the first poll (about 1 s)**.
- A burst of 20 files in 10 folders, sent as 10 sequential folder requests, became visible in about 5 s.
- **A deleted folder that Plex already knows** (for example a removed movie folder, scanned at its old path) **is removed promptly.**
- **A path Plex doesn't know yet is ignored.** If the partial scan arrives before the file exists (mount or Drive lag), nothing is indexed and nothing retries later.
  - **Implication:** Autoplow's optional "path must exist before delivery" check (hold and retry) matters for Plex targets.
- Spaces in `path` may be encoded as `%20` or `+`; both work.
- `Job was already killed, not killing again.` in the server log is harmless debug output.

## Sections
- **Creating a section** (`POST /library/sections?...&location=`) immediately runs a full scan of that section.
- **Disrupted initial scan (observed once, cause unconfirmed):** a section whose initial scan was disrupted ignored every partial scan ("Refreshing 0 IDs") until one full refresh of that section. After that, partial scans worked normally.
  - **Implication:** post-delivery verification should detect "scan accepted but nothing indexed", and suggest a full refresh of that section.
- **Overlapping locations:** a folder inside two sections (one section's location nested inside another's) is indexed in **both** when each section receives the partial scan.

## Trash
- With Plex's automatic empty-trash setting enabled, deleted items disappeared after the partial scan without an explicit `emptyTrash`.
- Autoplow's empty-trash option only matters when that setting is off.

## API
- List endpoints log `Missing X-Plex-Container-Size header. This will fail with status code 400 in the future.` Always send `X-Plex-Container-Start` and `X-Plex-Container-Size`.
