# Spec: managed Arr connections (v1)

**Module:** `arr` · **Depends on:** core, notifications · **Decisions:** ADR-0012 · **Status:** approved 2026-10-27

## Objective
Talk to every Arr instance correctly: receive and parse their webhooks, and keep Autoplow's own webhook connection in each Arr present and correct without touching anyone else's.

## Non-goals
- Managing Arr settings beyond our own connection
- Readarr (archived)

## Adding an Arr instance
1. **Entry:** the user enters a URL and API key. The instance is added in the UI, through the API, or seeded from the bootstrap file.
2. **Detection:** we call `system/status` to get `appName` and `version`, which select the API flavour:

   | App | API flavour |
   |---|---|
   | Sonarr v4 | v3 |
   | Sonarr v5 | v3, switching to v5 later |
   | Radarr | v3 |
   | Lidarr | v1 |
   | Whisparr v2 | Sonarr flavour |
   | Whisparr v3 | Radarr flavour |

   We also read `urlBase`.
3. **Path mappings:** taken from `rootfolder`, then set up with the filesystem picker or evidence-based suggestions (see the scan spec).
4. **Trigger:** each Arr instance gets its own trigger with **per-instance credentials** (a header token).

## The managed connection
| Field | Value |
|---|---|
| Name | `Autoplow (Managed)`, Prowlarr-style |
| Implementation | `Webhook`, method POST |
| URL | `<callback base>/triggers/<trigger-id>`. The callback base is global, with an optional per-Arr override. |
| Headers | `X-Api-Key: <per-instance token>` and `X-Autoplow-Instance: <uuid>` (fingerprint) |
| Tags | `[]`. Tags would silently filter out events. |
| Events (fixed) | **Sonarr / Whisparr v2:** onDownload, onUpgrade, onImportComplete, onRename, onSeriesDelete, onEpisodeFileDelete, onEpisodeFileDeleteForUpgrade. **Radarr / Whisparr v3:** onDownload, onUpgrade, onRename, onMovieDelete, onMovieFileDelete, onMovieFileDeleteForUpgrade. **Lidarr:** onReleaseImport, onUpgrade, onRename, onTrackRetag, onArtistDelete, onAlbumDelete. |

Notes on the fixed event set:
- The `*ForUpgrade` deletes are included so that removing an old file triggers a scan.
- Add and grab events are excluded.

## Lifecycle
1. **Create:**
   - Our receiver must be up first, because v3/v1 run a live `Test` on save.
   - `POST /notification`. Store the returned `id`.
   - On Sonarr v5 we may use `skipTesting` and run our own test afterwards.
2. **Reconcile:** runs periodically (default every 15 minutes) and on demand.
   - **Finding our connection:** by stored id, then by fingerprint header, then by our URL.
   - **Fingerprint:**
     - url
     - method
     - headers
     - every `on*` flag
     - `includeHealthWarnings`
     - `tags == []`
     - name
   - **Drift** means any difference. It is fixed with a **full PUT**, sending all fields, and an `arr.connection.drift` notification is sent.
   - **Missing** means the connection was deleted. It is re-created and a notification is sent.
3. **Unmanage:** done in our UI only. The user can remove the connection from the Arr, or leave it in place but stop reconciling.
4. **Removing the Arr from the app:** deletes our connection from the Arr (a confirmation dialog in the UI).

## Migration helper
- **Detection:** list the Arr's existing Webhook connections whose URL path looks like any of:
  - autoscan (`/triggers/sonarr|radarr|lidarr`)
  - autopulse (`/triggers/<name>` on port 2875)
  - our older endpoints
- **Offer:** once our connection has been verified (Test passed, and the first real event received or a test round-trip done), offer to **disable** (set all `on*` flags false) or **delete** each of them.

## Receiver
- **Parsers:** one per app flavour. They handle both Sonarr `Download` shapes, deduplicating by `downloadId` and folder.
- **`Test` events:** answered with 2xx; nothing is queued.
- **Unknown events:** answered with 2xx and logged at debug level. They never return 500.
- **Request bodies:** limited in size.

## Acceptance criteria
1. Sonarr v4/v5, Radarr, Lidarr and Whisparr v2/v3 are detected from `system/status` and handled with the right API flavour.
2. Creating a managed connection succeeds against an Arr that performs its test-on-save; the stored definition reads back identical.
3. Drift (any changed field) is detected and repaired with one full PUT; no PUT is sent when there is no drift (Lidarr re-tests on every PUT).
4. Connections not owned by Autoplow are never modified; old autoscan-style hooks are only listed and offered for removal after ours is verified.
5. Every payload shape in the research doc (incl. Sonarr per-file vs ImportComplete `Download`, Lidarr `albums` Test) parses; unknown events return 2xx and are logged.

## Boundaries
- **Always:** follow `CONSTRAINTS.md`; validate external input at the boundary.
- **Ask first:** Changing the fixed event set.
- **Never:** Put tags on our connection; Modify connections we do not own.
