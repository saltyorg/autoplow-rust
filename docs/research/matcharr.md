# matcharr: codebase report

- **Source:** github.com/saltydk/matcharr
- **Snapshot analysed:** HEAD `0284a10` (2022-05-21)
- **Language:** Python, about 580 lines of source

## Purpose
matcharr makes sure Plex (and, as an untested extra, Emby) has matched each series or movie to the same metadata ID that Sonarr (tvdb) or Radarr (tmdb) holds for it. When the two disagree, it forces Plex to re-match the item.

- **Source of truth:** the Arr apps.
- **How items are paired:** by folder path.
- **How it runs:** a single batch script. All the code sits at module level in `app.py` and ends with `sys.exit(0)`. There is no daemon, CLI, scheduler or webhook.

## Layout
| File | Role |
|---|---|
| `app.py` | Orchestration |
| `classes/arr.py` | Two GET requests per Arr instance |
| `classes/arrmedia.py` | Per-item record: title, path, mappedpath, id, imdb |
| `classes/plex.py` | Parses Plex GUIDs |
| `classes/emby*.py`, `utils/emby.py` | Emby support |
| `utils/arr.py` | `parse_arr_data`, `get_arrpaths`, `check_faulty` (pandas, used only to report duplicate Arr paths) |
| `utils/plex.py` | Loading items, splitting merged items, mapping roots, comparing, matching |
| `utils/base.py` | `map_path`, tqdm wrapper |

## Algorithm
### 1. Read the Arr apps
For each instance it calls:
- `GET {url}/api/v3/{series|movie}?apikey=`
- `GET {url}/api/v3/rootfolder`

Each instance is constructed twice, so this is 4 requests per instance. The requests have no timeout and no status check, and the API key goes in the URL.

What it keeps from each item:
- Sonarr: `id = tvdbId`
- Radarr: `id = tmdbId`
- Both: `imdb = imdbId`

### 2. Map paths
`path_mappings` is a dict of `{hostPath: appPath}`. For each entry, in order: if the path starts with `appPath`, return `path.replace(appPath, hostPath)`.

Two problems with this:
- The first matching entry wins, not the longest prefix.
- `str.replace` replaces *every* occurrence of `appPath`, not only the leading one.

### 3. Link Arr root folders to Plex sections
An Arr root folder is linked to a Plex section only when the mapped root folder exactly equals the section location, ignoring a trailing slash. A root folder nested inside a section location does not link.

### 4. Read Plex
1. Set `Show._include = Movie._include = ""` to trim the include parameters plexapi adds by default.
2. Call `section.all()`.
3. For each item, keep `locations[0]`, `guid`, `guids[]`, `ratingKey` and `title`.

### 5. Parse Plex GUIDs
| `item.guid` | Agent | ID used |
|---|---|---|
| `com.plexapp.agents.themoviedb://…` | themoviedb | First run of digits |
| `com.plexapp.agents.thetvdb://…` | thetvdb | First run of digits |
| `com.plexapp.agents.imdb://…` | imdb | `tt\d{7,}` |
| `plex://…` (new agent) | plex | `imdb[]`, `tmdb[]` and `tvdb[]` lists from the `Guid` children |
| Anything else (`local://`, `none://`, HAMA, `tv.plex.agents.*`) | unknown | 0 |

If a regex does not match, calling `.group()` on the empty result crashes the whole run.

### 6. Pair items and detect mismatches
An Arr item and a Plex item are the same title when the Arr path equals either the Plex location or the Plex location's parent directory. The parent-directory case covers movie files.

How a mismatch is detected depends on the Plex item's agent:
- **New Plex agent:** Radarr's tmdbId must appear in the item's `tmdb[]` list, and Sonarr's tvdbId in its `tvdb[]` list.
- **Legacy imdb agent:** the Arr item's imdbId must equal the Plex ID.
- **Any other agent:** the Arr ID must equal the legacy agent's ID. Because unknown agents get ID 0, **every item on an unknown agent is re-matched to a legacy agent**.

### 7. Fix the match
The fix is a raw HTTP request:

```
PUT {plex}/library/metadata/{ratingKey}/match?guid=...&name={arr title}&X-Plex-Token=...
```

The `guid` it sends:
- New Plex agent: `tmdb://ID?lang=en` or `tvdb://ID?lang=en`
- Legacy agents: `com.plexapp.agents.{themoviedb|thetvdb|imdb}://ID?lang=en`

Details of the call:
- The language is hardcoded to `en`.
- It does not call `/matches` to search for candidates first.
- It does not trigger a refresh; it relies on Plex refreshing the item after the match.
- It never reads the item back to confirm the fix took.

### 8. Split merged items
Before comparing, it splits any item whose locations span more than one parent directory, using `PUT /library/metadata/{id}/split`. This always runs and cannot be turned off. Two shows merged under the same root share a parent directory, so that case is never detected.

### 9. Rate limiting and retries
- It sleeps for `delay` seconds after every write.
- It retries 5 times, and only on timeouts.
- Any response other than 200 is logged and not retried.

### 10. Emby
- Libraries come from `GET /emby/Library/SelectableMediaFolders`.
- Items come from `GET /emby/Items?ParentId=&Fields=ProviderIds,Path`, with no paging.
- It compares `ProviderIds.Tmdb` or `ProviderIds.Tvdb` against the Arr ID.
- The update request's body is invalid JSON: the `"Id": metadataid` placeholder is never filled in.
- After an update it calls `POST /emby/Items/{id}/Refresh?...FullRefresh...`.

## Configuration (`config.json`, read from the working directory)
| Key | Purpose |
|---|---|
| `plex_url`, `plex_token`, `plex_enabled` | Plex connection |
| `emby_url`, `emby_token`, `emby_enabled` | Emby connection |
| `delay` | Seconds to wait after each write (default 10) |
| `path_mappings` | `{hostPath: appPath}` |
| `radarr`, `sonarr` | `{name: {url, apikey}}` |

The config is not validated.

## Dependencies
- requests 2.27.1
- pandas 1.4.2, used only for the duplicate report
- tqdm
- PlexAPI 4.11.1
- pkg_resources

## Limitations observed (HEAD 0284a10)
- No dry-run mode.
- Splitting merged items is unconditional.
- Items on unknown agents are wrongly re-matched.
- Language is hardcoded to `en`.
- Missing `break`s make the scan O(Arr × Plex).
- Every root folder checks every item of its Arr instance.
- Two Arr root folders linked to one Plex section produce duplicate match requests, made against a stale snapshot.
- `map_path` is first-match and replaces every occurrence.
- Only `locations[0]` is considered.
- An `isfile` check runs against the local filesystem.
- Non-200 responses are not retried.
- The "fixed" counter goes up even when the match fails.
- Only the Arr v3 API is supported.
- Only tvdb and tmdb IDs are supported: no anime, no alternate episode orderings, one Plex server.

## What a successor should do
The core is small: pair items by path, check that the Arr ID is in Plex's set of GUIDs, then `PUT …/match?guid=tmdb://X` (or `tvdb://X`). A successor should:
- Use a path-keyed hashmap instead of nested loops.
- Map paths by longest prefix.
- Never touch items on agents it does not understand.
- Make the match language configurable.
- Support dry-run, and read the item back after a match to verify it.
- Make splitting optional and detect merged items correctly.
- Back off on 5xx responses and connection errors.
- Rate-limit its requests.
- Optionally run per item after an Arr import, triggered by a webhook, instead of only as a full sweep.
