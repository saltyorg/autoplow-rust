# Plex-Auto-Languages (PAL): codebase report

- **Source:** github.com/JourneyDocker/Plex-Auto-Languages
- **Snapshot analysed:** HEAD `6b523fa`, version 1.6.1
- **Language:** Python, about 4.5k lines of source plus tests
- **Path notation:** `pal/` means `plex_auto_languages/`

## Purpose
PAL remembers which audio and subtitle tracks each user picks for a TV show. It then applies the same choice to the other episodes of that show (or season), separately for each user. It only handles TV episodes, never movies.

## Architecture and threads
- **Main loop** (main.py)
  - `init()` creates the Plex server object and starts the alert listener.
  - Every 60s it checks that Plex is alive. Every 300s it cleans idle caches.
  - If Plex goes away it saves the cache and reconnects, backing off exponentially from 1s up to 300s.
  - A watchdog calls `os._exit(1)` after 5 consecutive failures or more than 300s unhealthy, so Docker restarts the container.
  - SIGINT and SIGTERM are handled.
- **Health server**
  - Flask on 0.0.0.0:9880, serving `/`, `/health` and `/ready`.
  - The Docker HEALTHCHECK calls it.
- **Scheduler thread**
  - Uses the `schedule` library to run at `HH:MM`, optionally only on chosen days.
  - Runs the deep analysis described under Triggers.
- **PlexAlertListener**
  - Subclass of plexapi `AlertListener`, connected to `ws(s)://…/:/websockets/notifications`.
  - TLS verification is disabled for `wss`.
- **PlexAlertHandler**
  1. Picks the alert class from the message type and which triggers are enabled.
  2. Drops alerts that `is_relevant()` rejects.
  3. Drops duplicates seen within a 5s window. Only timeline alerts have a real dedupe key.
  4. Puts the alert on `Queue(10000)`. When the queue is full the alert is dropped and counted.
  5. **8 consumer threads** drain the queue. A ReadTimeout is retried 3 times; any other error is logged and the alert skipped.
  6. A stats thread logs every 5 minutes.
- **User fan-out pool**
  - A global `ThreadPoolExecutor(5)`.
- **HTTP session**
  - A pooled HTTPAdapter.
  - A selective "no TLS verify" setting for the configured Plex host.
  - A stable `X-Plex-Client-Identifier` (uuid3), so Plex does not send "new device" emails.

## Startup
1. `_get_server` retries `PlexServer(url, token)` up to 300 times, 5s apart. That can block for about 25 minutes before the watchdog applies.
2. The admin user is found by matching `myPlexAccount().username` against `systemAccounts()`.
3. The cache is loaded from SQLite. On a cold start PAL scans the whole library instead.
4. `is_alive` is true when both hold:
   - a `library.sections()` probe succeeds (the result is cached for 2 minutes), and
   - the listener thread is alive.

## Triggers
| Trigger | Config flag | What fires it |
|---|---|---|
| **playing** | `trigger_on_play` (default true) | `PlaySessionStateNotification` |
| **activity** | `trigger_on_activity` (default false) | `library.refresh.items` activity with `event == "ended"` |
| **timeline** | `trigger_on_scan` | Timeline entries with `identifier == com.plexapp.plugins.library`, `state == 5`, `type != -1`, and no `mediaState` |
| **status** | `trigger_on_scan` | "Library scan complete" |
| **scheduler** | `scheduler.enable` | Daily at `HH:MM` |

### playing
1. Finds the user from the client: first `user_clients[clientIdentifier]`, otherwise the admin's `sessions()` matched by `player.machineIdentifier` and then `userID`.
2. Fetches the item with that user's token and skips anything that is not an Episode. Live TV is skipped.
3. Applies the ignore rules.
4. Calls `reload()`.
5. Skips if both the session's cached streams and the item's cached default streams are unchanged. A track change during playback therefore still fires.
6. Calls `change_tracks`.

### activity
- The user comes from `Activity.userID`; the item from `Context.key`.
- Debounced for 3s per (user, item).
- According to the config comment, only Plex Web and Plex for Windows emit this when the user changes tracks without playing.

### timeline
- Deduped by `(itemID, has metadataState)`.
- **Entry has `metadataState`:** this is an updated item. PAL continues only if the item's set of media part keys changed compared with the cache (a file was upgraded). It then runs the new/updated flow with `new = False`.
- **Entry has no `metadataState`:** this is a new item. PAL requires `addedAt` within the last 5 minutes and that this `addedAt` has not been processed before. It then runs the flow with `new = True`.

### status
- If `refresh_library_on_scan` is set and the last refresh was more than 5 minutes ago, PAL runs a full cache diff that finds added and updated episodes.
- Otherwise it queries `searchEpisodes(addedAt>>5m)`.
- This path does **not** apply `ignore_filepatterns`.

### scheduler
1. Reads `history(mindate = now - 1 day)` and runs `change_tracks` for each episode in it, under that history entry's user.
2. Runs a full library diff, then runs the new/updated flow for everything found.

## Change flows
### `change_tracks(user, reference_episode)`
Used by the playing, activity and scheduler-history paths.
1. Selects target episodes from the reference episode:
   - `update_level`: `show` (`show().episodes()`) or `season` (`season().episodes()`).
   - `update_strategy`: `all`, or `next`, which keeps only episodes strictly after the reference SxxEyy.
2. Computes the changes, applies them, and sends a notification.

### `process_new_or_updated_episode(item_id)`
1. For the admin and every instance user (run in the fan-out pool):
   1. Fetch the item with that user's token.
   2. Pick the user's reference episode with `show.watched()[-1]`, which is the highest-*indexed* watched episode, not the most recently watched one. If nothing is watched, use the first episode.
   3. Compute and apply the changes for that one item.
2. Send one global notification.

## Track-matching algorithm (track_changes.py)
### Reference streams
- The **first** selected audio stream and the first selected subtitle stream of the reference episode. Either can be None.
- The reference stream's index within its own filtered candidate list is stored for tie-breaking.

### compute
For each target episode, `reload()`, then for each media part:
1. **Audio**
   - Find the best match. Change the track only if both the current selection and the match exist and they differ.
2. **Subtitle when the current subtitle is set but no match was found**

   | Reference has | Action |
   |---|---|
   | No selected subtitle, but subtitle streams exist | Clear the subtitle |
   | No subtitle streams at all (burned-in or none) | Do nothing |
   | A forced subtitle | Clear the subtitle |
   | A regular subtitle | Keep the current subtitle |

3. **Subtitle otherwise**
   - If the match differs from the current selection, set it.
   - Special case: subtitles are skipped when the target's current audio title contains "commentary" and no audio match was found.

### Audio match
1. If the reference has no audio, return None.
2. **Filter** the candidates in steps. Steps b and c narrow the list only when at least one candidate is left:
   1. Same `languageCode`.
   2. Visually-impaired (VI) status mirrors the reference.
   3. "Descriptive" terms mirror the reference. The terms are commentary, description, descriptive, narration, narrative and described, searched in `extendedDisplayTitle`, `displayTitle` and `title`.
3. If no candidates remain, return None. If one remains, return it.
4. **Score** the remaining candidates:

   | Condition | Points |
   |---|---|
   | Same codec | +5 |
   | Same `audioChannelLayout` | +3 |
   | Same `extendedDisplayTitle` | +5 |
   | Same `displayTitle` | +5 |
   | Same `title` | +5 |

   When all unfiltered streams share the same title, a channel heuristic applies:
   - Reference has fewer than 3 channels: a candidate with more channels gets +8. This avoids picking 2.0 audio-description tracks.
   - Otherwise: a candidate with at least the reference's channel count gets +1.

### Subtitle match
1. **Filter** the candidates:
   - **Reference has no subtitle:** keep only *forced* subtitles in the reference's *audio* language. "Subtitles off" therefore means "forced subtitles in the audio language are fine".
   - **Reference has a subtitle:** keep the reference's language. If the reference is forced, keep only forced streams. If the reference is hearing-impaired (HI), keep only HI streams. A forced or HI reference never falls back to a regular subtitle.
   - A stream counts as forced when its `forced` flag is set or its title contains "forced".
2. **Score** the remaining candidates:

   | Condition | Points |
   |---|---|
   | Same forced status | +3 |
   | Same HI status | +3 |
   | Same codec | +1 |
   | Same `extendedDisplayTitle` | +5 |
   | Same `displayTitle` | +5 |
   | Same `title` | +5 |

### Tie-break
- The highest score wins.
- If several candidates tie, prefer the stream at the reference's index in the filtered list, when that stream is among the tied ones. Otherwise take the first tied stream.
- This keeps a deliberate choice among identically named tracks.

### Apply
- Uses plexapi `setSelectedAudioStream`, `setSelectedSubtitleStream` and `resetSelectedSubtitleStream`.
- These send `PUT /library/parts/{partId}?audioStreamID=… | subtitleStreamID=…(0 = off)&allParts=1`.
- The requests use **the user's token**.
- The result is not verified afterwards.

## Per-user handling
- **Users.** `myPlexAccount().users()` from plex.tv, filtered to users who have access to this server's machineIdentifier. This covers shared friends and Home/managed users. The list is cached for 12 hours.
- **Tokens.**
  - Each user's token comes from `user.get_token(machineId)`, which reads the `accessToken` in plex.tv's shared-servers data.
  - Tokens are held in memory only.
  - If a token fails, PAL fetches a fresh one and retries once.
  - A new `UnprivilegedPlexServer` (`GET /`) is built for every event.

## Caching and persistence
- **Database:** SQLite at `data_dir/cache/{machineIdentifier}.sqlite3`, with WAL and `busy_timeout` set to 30s.
- **Tables:**
  - `episodes(episode_key PK, newly_added_at, newly_updated_at, part_keys_json)`
  - `system_metadata` (holds `last_refresh`)
- **Migration and recovery:** the old JSON cache is migrated once. A corrupt database is rebuilt.
- **`refresh_library_cache`:**
  - Pages through every episode in each show section, 1000 at a time.
  - Compares each episode's set of media part keys with the cache. A new key means the episode was added; a changed set means it was updated.
  - Has a re-entrancy guard.
- **Saving:** coalesced, and rewrites the whole table (delete all rows, insert again).
- **In memory only:** session states, default streams (at most 10k entries, evicted at random), user clients, recent activities, users and tokens.

## Ignore rules
- `ignore_libraries`: section titles, matched exactly.
- `ignore_labels`: show labels. The default is `PAL_IGNORE`.
- `ignore_filepatterns`: case-insensitive regexes tested against file paths.

## Notifications
- Sent with Apprise.
- `apprise_configs` entries are either a URL string (used for all users and events) or `{urls, users?, events?}`.
- Event types: `play_or_activity`, `new_episode`, `updated_episode`, `scheduler`.
- The new/updated flow calls the global `notify`, so users' own URLs never receive those notifications.

## Configuration (root key `plexautolanguages`)
| Key | Default |
|---|---|
| `update_level` | `show` (or `season`) |
| `update_strategy` | `next` (or `all`) |
| `trigger_on_play` | true |
| `trigger_on_scan` | true |
| `trigger_on_activity` | false |
| `refresh_library_on_scan` | true |
| `ignore_labels` | `[PAL_IGNORE]` |
| `ignore_libraries` | (none) |
| `ignore_filepatterns` | (none) |
| `plex.url` | required |
| `plex.token` | required |
| `plex.connection_max_retries` | 300 |
| `plex.connection_retry_delay` | 5 |
| `scheduler.enable` | true |
| `scheduler.schedule_time` | `02:00` |
| `scheduler.schedule_days` | (every day) |
| `notifications.enable` | false |
| `notifications.apprise_configs` | (none) |
| `data_path` | (none) |
| `debug` | false |

Settings are loaded in this order, each layer overriding the previous one:
1. The built-in `default.yaml`.
2. The user's config file, deep-merged.
3. Environment variables, named by the key path in upper case (for example `PLEX_TOKEN`, `SCHEDULER_SCHEDULE_TIME`).
4. Docker secrets.
5. Validation.

## Dependencies and runtime
- **Python packages:**
  - plexapi 4.18.3
  - websocket-client
  - apprise
  - PyYAML
  - schedule
  - Flask
  - python-dateutil
  - requests
- **Docker image:** python alpine with tini.
- **Volumes:** `/config` and `/logs`.
- **Healthcheck:** curls port 9880.
- **Tests:** pytest with fakes.

## Limitations observed (v1.6.1)
1. The scheduler's history pass fetches episodes with the **admin** token (`episode.source()`). It reads the admin's track selection and applies it under the other user's name.
2. There is no per-show or per-user lock across the 8 consumers and the scheduler. Concurrent events race and the last write wins.
3. New episodes use the highest-indexed watched episode as the reference, not the most recently watched one.
4. The status path skips `ignore_filepatterns`.
5. Only the first selected stream is considered, and multi-part episodes are not handled well.
6. Languages must match exactly. There is no fallback for `und` or regional variants.
7. The commentary check looks at the target's audio instead of the reference's.
8. Per-user notification URLs never receive new or updated events.
9. TLS verification is disabled for HTTPS and `wss`.
10. Startup can block for about 25 minutes.
11. Users and tokens are not persisted, and a server object is rebuilt for every event.
12. Alerts are dropped when the queue is full, and only timeline alerts are deduplicated.
13. TV only, no movies.
14. A full library diff costs O(all episodes).

## Ideas worth reusing
- Use websocket notifications instead of polling.
- Detect new and upgraded files by diffing each episode's media part keys against a cache.
- The track matcher: filter by language, then VI, then descriptive terms; score by weight; break ties by position.
- Forced and HI subtitle semantics, including "subtitles off" meaning forced subtitles in the audio language.
- Write each user's selection with the access token from that user's shared-server entry.
- Route Apprise notifications by user and event.
