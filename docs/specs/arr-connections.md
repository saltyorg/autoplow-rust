# Spec: managed Arr connections (v1)

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
