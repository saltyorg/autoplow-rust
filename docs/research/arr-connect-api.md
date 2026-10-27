# Arr Connect (webhook) management API and webhook payloads

This page is based on reading the source, not running anything. Snapshot as of 2026-10-25:

| App | Branch | Version | Notes |
|---|---|---|---|
| Sonarr | `develop` | **v5.0.0** | Serves both `Api.V3` and `Api.V5` |
| Sonarr | `v4-develop` | 4.0.20 | |
| Radarr | `develop` | 7.0.0 | |
| Lidarr | `develop` | 3.2.0 | |
| Readarr | | | Archived; skip |
| Whisparr | `v2-develop` | | Based on Sonarr; not inspected |

## Goal
Our tool can optionally create and maintain its own webhook "Connection" in each Arr. That means creating it, updating it as our payload expectations change, detecting drift, and removing it.

## 1. Connect management API

### Paths and authentication
- Base path:
  - **Sonarr v4 and Radarr:** `/api/v3/notification`
  - **Lidarr:** `/api/v1/notification`
  - **Sonarr v5:** `/api/v5/connection`. `/api/v3/notification` still works there, but `GET /api` reports it as deprecated: `{"current":"v5","deprecated":["v3"]}`.
- **Authentication:** any one of `?apikey=`, the `X-Api-Key` header, or `Authorization: Bearer <key>`.
- **URL base:** read `urlBase` from `GET /config/host` (Sonarr v5: `/api/v5/settings/general`) and put it in front of every path.

### Endpoints
| Operation | Request | Notes |
|---|---|---|
| List | `GET /notification` | |
| Get | `GET /notification/{id}` | |
| Create | `POST /notification` | v3/v1 take `?forceSave=`. v5 takes `?skipTesting=&skipValidation=None\|Warnings\|All`. Returns 201. |
| Update | `PUT /notification/{id}` | Same query params as create. Returns 202. |
| Delete | `DELETE /notification/{id}` | |
| Schema | `GET /notification/schema` | Use the template with `implementation == "Webhook"`. |
| Test | `POST /notification/test` | Takes the full resource; returns 400 with validation errors. |
| Bulk | `PUT /notification/bulk`, `DELETE /notification/bulk` | Not available on v5 `/connection`. |

### Validation and the test-on-save behaviour
- `name` is required and must be unique, ignoring case.
- There is no "enabled" field. A connection counts as enabled when any `on*` flag is true, and validation and testing only run when it is enabled.
- **Creating on v3/v1 always runs a live test.** The Arr synchronously sends `eventType:"Test"` to our URL, and the create fails unless we answer with a 2xx. `forceSave=true` only lets the save go through despite *warnings*; errors still fail it.
- **Updating on v3/v1** re-tests only when the definition has changed. An unchanged PUT does nothing.
- **v5:** `skipTesting=true` skips the live test entirely.

### Webhook resource
```
{ id, name, implementation:"Webhook", configContract:"WebhookSettings", tags:[int],
  fields:[{name,value,...}], on*..., includeHealthWarnings }
```

The webhook `fields` (the same `name` keys in all three apps):

| Field | Type | Notes |
|---|---|---|
| `url` | string | |
| `method` | int | 1 = POST (default), 2 = PUT |
| `username` | string | |
| `password` | string | Masked as `********` on GET |
| `headers` | list | `[{"key":"...","value":"..."}]`. **Not masked.** |

### Event flags
**Sonarr v4 and v5** (identical sets):
- `onGrab`, `onDownload`, `onUpgrade`, `onImportComplete`, `onRename`
- `onSeriesAdd`, `onSeriesDelete`
- `onEpisodeFileDelete`, `onEpisodeFileDeleteForUpgrade`
- `onHealthIssue`, `includeHealthWarnings`, `onHealthRestored`
- `onApplicationUpdate`, `onManualInteractionRequired`

**Radarr** (no `onImportComplete`):
- `onGrab`, `onDownload`, `onUpgrade`, `onRename`
- `onMovieAdded`, `onMovieDelete`
- `onMovieFileDelete`, `onMovieFileDeleteForUpgrade`
- `onHealthIssue`, `includeHealthWarnings`, `onHealthRestored`
- `onApplicationUpdate`, `onManualInteractionRequired`

**Lidarr:**
- `onGrab`, `onReleaseImport` (this is its "download" event), `onUpgrade`, `onRename`
- `onArtistAdd`, `onArtistDelete`, `onAlbumDelete`
- `onHealthIssue`, `onHealthRestored`, `includeHealthWarnings`
- `onDownloadFailure`, `onImportFailure`, `onTrackRetag`, `onApplicationUpdate`
- There is no track-file-delete event.

### Which events actually get sent
- **Upgrades:** an upgrade import is only sent if `onUpgrade` is also set.
- **Deletes caused by an upgrade:** only sent if the `*ForUpgrade` flag is set.
- **New downloads only:** Download/Import events are **not** sent for files that appear through a disk rescan.
- ⚠ **Tags filter events.** A connection that has tags only fires for media that shares one of those tags. **Never put tags on our connection.**

### Identifying our connection
1. Store the `id` the Arr returns, per Arr instance, and look the connection up by that first.
2. Give it a reserved name such as `Autoplow (managed)`. Users can rename it, so this alone is not enough.
3. Add a fingerprint header, e.g. `X-Autoplow-Instance: <uuid>`. Headers are readable on GET, so this survives renames.
4. Optionally put an instance id in the URL path, e.g. `/hooks/sonarr/<id>`.

### Drift detection and authentication
- **Auth:** the password is masked on GET, so we can't compare it. Use a **header token** (`X-Autoplow-Token` or `Authorization: Bearer`) instead of basic auth so drift can be checked. Header values are visible to anyone with admin access to that Arr.
- **What to compare:** `url`, `method`, `headers`, every `on*` flag, `includeHealthWarnings`, and `tags == []`.
- **Updating:** always PUT the **full** `fields` list. Any field left out resets to null.

## 2. Webhook payloads

### Common to all apps
- The Arr sends POST or PUT according to `method`, as JSON. It adds basic auth if a username or password is set, plus any custom headers. A non-2xx response is recorded as a failure.
- JSON property names are camelCase and null values are left out.
- **`eventType` is PascalCase** (`"Download"`). Other enum values are camelCase, e.g. `deleteReason:"upgrade"`.
- Every payload includes `eventType`, `instanceName` and `applicationUrl`.
- **All paths are as the Arr sees them** (container paths), so they need path mapping.

### Sonarr
`eventType` values:
- `Test`, `Grab`, `Download`, `Rename`
- `SeriesAdd`, `SeriesDelete`, `EpisodeFileDelete`
- `Health`, `HealthRestored`, `ApplicationUpdate`, `ManualInteractionRequired`

Common objects:
- **`series`:** `{id, title, path (absolute), tvdbId, tvMazeId, tmdbId, imdbId, type, year, tags, originalLanguage}`. v5 adds `malIds`, `aniListIds` and `originalCountry`.
- **`episodeFile`:** `{id, relativePath, path (absolute), quality, size, sceneName, releaseGroup, mediaInfo, sourcePath?}`.

Events:
- **Download, sent once per imported file:**
  - Payload: `{series, episodes, episodeFile, isUpgrade, downloadClient*, downloadId, release, deletedFiles?[]}`.
  - On an upgrade, `deletedFiles` lists the replaced files, each with an absolute `path` and `recycleBinPath`.
- **ImportComplete, also sent as `eventType:"Download"`:**
  - You can tell it apart because it has a plural **`episodeFiles[]`** and no `episodeFile`.
  - It also includes **`destinationPath`**, the common parent folder of the imported files, and `sourcePath`.
  - It is sent once per completed download and is ideal for one scan per download.
  - Deduplicate against the per-file events using `downloadId`.
- **Rename:** `{series, renamedEpisodeFiles[]}`. Each entry has `path`, `relativePath`, `previousPath` and `previousRelativePath`.
- **EpisodeFileDelete:** `{series, episodes, episodeFile, deleteReason}`. `deleteReason` is one of `missingFromDisk`, `manual`, `upgrade`, `noLinkedEpisodes`, `manualOverride`.
- **SeriesAdd:** `{series}`.
- **SeriesDelete:** `{series, deletedFiles: bool}`.
- **Test:** shaped like a Grab payload, with `series.path:"C:\\testpath"` and one fake episode. **Accept it with a 2xx and don't queue anything.**

### Radarr
`eventType` values:
- `Test`, `Grab`, `Download`, `Rename`
- `MovieAdded`, `MovieDelete`, `MovieFileDelete`
- `Health`, `HealthRestored`, `ApplicationUpdate`, `ManualInteractionRequired`

Common objects:
- **`movie`:** `{id, title, year, folderPath (absolute), tmdbId, imdbId, tags, ...}`. `filePath` is never set, so don't use it.
- **`movieFile`:** `path` (absolute) and `relativePath`.

Events:
- **Download:** `{movie, movieFile, isUpgrade, downloadId, deletedFiles?[]}`.
- **Rename:** `{movie, renamedMovieFiles[] (path, previousPath, ...)}`.
- **MovieFileDelete:** `{movie, movieFile, deleteReason}`.
- **MovieDelete:** `{movie, deletedFiles, movieFolderSize}`.
- **MovieAdded:** `{movie, addMethod}`.

### Lidarr
`eventType` values:
- `Test`, `Grab`, `Download`, `Rename`, `Retag`
- `DownloadFailure`, `ImportFailure`
- `ArtistAdd`, `ArtistDelete`, `AlbumDelete`
- `Health`, `HealthRestored`, `ApplicationUpdate`

Common objects:
- **`artist`:** includes `path` (absolute) and `mbId`.
- **`album`:** has no path.
- **`trackFile`:** `path` is absolute, and there is no `relativePath`.

Events:
- **Download, sent once per album release import:** `{artist, album, tracks[], trackFiles[], deletedFiles?[], isUpgrade, downloadId}`.
- **Rename:** `{artist, renamedTrackFiles[] (path, previousPath)}`.
- **Retag:** `{artist, trackFile}`.
- **ArtistDelete:** `{artist, deletedFiles}`.
- **AlbumDelete:** `{artist, album, deletedFiles}`.

## 3. Version detection
- `GET /api/v3/system/status` (Lidarr: `/api/v1/...`) returns `appName`, `version`, `branch`, `urlBase` and `isDocker`. Use `appName` and the major `version` to decide behaviour.
- `GET /api` returns `{current, deprecated}`, a cheap way to find out whether the v5 API is available.
- **Differences in Sonarr v5:**
  - Connections are at `/api/v5/connection`.
  - `forceSave` is replaced by `skipTesting` and `skipValidation`.
  - There are no bulk endpoints, and DELETE returns 204.
  - Payload changes are additive only.
- **Recommendation:** use v3 everywhere for now, and switch to v5 when `version` starts with `5.`.
- Sonarr ships an OpenAPI spec in its source tree at `src/Sonarr.Api.V5/openapi.json`.

## 4. Other useful endpoints
| Purpose | Endpoint |
|---|---|
| Root folders, for validating path mappings | `GET /rootfolder` |
| Tags | `GET /tag` |
| Library | Sonarr `GET /series`, `GET /episodefile?seriesId=`; Radarr `GET /movie`, `GET /moviefile?movieId=`; Lidarr `GET /artist`, `GET /album`, `GET /trackfile?artistId=` |
| Commands | `POST /command`, e.g. `{"name":"RescanSeries","seriesId":N}` |

## Design implications
1. **Our webhook endpoint must be up and answer `Test` with a 2xx before we create the connection** on v3/v1. On v5 we can skip the test instead.
2. **Prefer a header token over basic auth**, so drift can be checked.
3. **Identify our connection by** the stored id, then the managed name, then the `X-Autoplow-Instance` header. Keep `tags: []`.
4. **Handle Sonarr's two kinds of `Download`:** per-file events (`episodeFile`) and ImportComplete (`episodeFiles` + `destinationPath`). Pick one, or deduplicate by `downloadId`.
5. **Events to enable for scanning and uploading:**
   - Download and Upgrade
   - Rename
   - File delete, plus the `*ForUpgrade` variant if we want cleanup of old files
   - Series, movie, artist and album deletes
   - Lidarr Retag
   - Optionally ImportFailure
6. **Path mapping is required.** Every path field is absolute and as the Arr sees it, including `previousPath`, `deletedFiles[].path` and `destinationPath`.
7. **Tofa matches TV by TMDB.** For matcharr against Tofa, use `series.tmdbId` (Sonarr v4+) rather than `tvdbId`.

## Addendum: what "ImportComplete" really is (checked in Sonarr v5 source)
- **The name is misleading.** It does **not** mean the download client finished. Internally it is `DownloadCompletedEvent`, which Sonarr publishes from `CompletedDownloadService.VerifyImport` **after every episode of a download has been imported into the library** (`NzbDrone.Core/Download/CompletedDownloadService.cs`). Manual and untracked imports publish it too, from `ManualImportService.cs` via `UntrackedDownloadCompletedEvent`.
- **It is not sent when an import is only partly done**, i.e. when some episodes failed or were skipped. The per-file `Download` events (`EpisodeImportedEvent`) still fire for each file that was imported.
- **The history fallback can include files imported earlier.** It builds the file list from history, so the list may contain files that are already in the library.
- **Conclusion:** per-file `Download` events are the reliable signal. With folder coalescing, all the files of a season pack collapse into one queued folder anyway, so ImportComplete adds nothing for scanning.

## Addendum: Whisparr and Bazarr (checked 2026-10-26)

### Whisparr
**`v2-develop`** (last commit 2026-09-19) is **based on Sonarr**:
- `WebhookSeries`, `WebhookEpisodeFile`, `WebhookImportCompletePayload`, `WebhookRenamedEpisodeFile` and so on.
- Same payload shapes as Sonarr, so it reuses the Sonarr parser.
- Its API is `Whisparr.Api.V3`.

**`eros`** (Whisparr v3, last commit 2026-08-28) is **based on Radarr**:
- `WebhookMovie`, `WebhookMovieFile`, `WebhookRenamedMovieFile` and so on.
- Same payload shapes as Radarr, so it reuses the Radarr parser.

**Detection:** check `appName` and `version` from `system/status`, then pick the Sonarr-style or Radarr-style handling.

### Bazarr (HEAD bfe4593, 2026-10-11)
Bazarr has a built-in **"external webhook"** (`bazarr/utilities/autopulse_webhook.py`). It was designed for autopulse.

**After a subtitle download, upload, delete or embedded-subtitle action:**
- Bazarr sends `GET {external_webhook_url}?path=<parent dir of the media file>&action_type=&language=&media_type=&subtitle_path=&media_path=`.
- It uses **HTTP basic auth**, if a username and password are set. The request is retried 3 times on network errors.
- Paths are as Bazarr sees them, so they need a rewrite.

**The "Test" button:**
- If the URL contains `/triggers/`, Bazarr calls `GET {base}/stats` (the part before `/triggers/`) and expects a 200. Otherwise it calls the URL itself.
- **For compatibility, our Bazarr trigger lives at `/triggers/bazarr`, and we serve `GET /stats` (basic-auth protected) with a 200.**

**Config generator:** Bazarr can also fetch `GET {base}/api/config-template?triggers=bazarr&targets=plex&database=sqlite` to generate an autopulse TOML config. That feature is autopulse-specific and we don't need to emulate it.
