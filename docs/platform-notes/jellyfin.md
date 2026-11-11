# Jellyfin

Verified 2026-10-27 with live tests on Jellyfin 12.3.0 and source reading (jellyfin `master`, `Emby.Server.Implementations/IO/LibraryMonitor.cs` and `FileRefresher.cs`).

## `POST /Library/Media/Updated`
- **Processing is delayed by `LibraryMonitorDelay`** (server configuration, default **60 s**). Updates are handed to a `FileRefresher` that restarts its timer on each new event for the same path, and merges sibling and child paths.
- When the timer fires, it walks **up** from each reported path to the nearest item that already exists in the database, and refreshes that item. The root `AggregateFolder` is skipped.
- Every tested scenario (new episode, season pack, upgrade, delete, file rename, folder rename, burst of 20 files in 10 folders, new movie, deleted movie folder) became visible at about **60.5 s**.
- **Late visibility:** a path reported a few seconds before it existed was still picked up, because the delay outlasted the gap.
- **`UpdateType`:** autoscan sends `Modified`.

## Library creation
- **`POST /Library/VirtualFolders?refreshLibrary=true` starts a server-wide "Scan Media Library" across all libraries.** Use `refreshLibrary=false`, then refresh only the new library (`POST /Items/{libraryId}/Refresh?Recursive=true`).
- **A library created on an empty folder is not registered.** The log shows "Library folder … is inaccessible or empty, skipping". Every later `Media/Updated` for it is **silently dropped**: no item is found when walking up, and nothing is logged at Info level. Refreshing only that library didn't fix it. Recreating the library after the folder had content did.
- **Implication:**
  - Post-delivery verification should detect this case and suggest re-adding the library.
  - Never create a library on an empty folder in tests.

## Item refresh (`POST /Items/{id}/Refresh`) is not a scan
- Refreshing the item of a **deleted** file does not remove it; it stayed listed for more than 180 s. Use `Media/Updated` on the folder.
- **Implication:** an autopulse-style "find the item and refresh it" approach breaks deletes.

## Overlapping library locations
- If one library's location is nested inside another's, the folder belongs to the **outer** library only. The server logs "Found duplicate path", and the inner library got 0 items.
- **Implication:** the UI should warn about overlapping locations on Jellyfin targets.

## Sessions
Baseline of 2026-11-11 from source reading (jellyfin at 10.8.13, 10.9.11, 10.10.7, 10.11.11 and 12.4) and the earlier Autoplow implementation. **Not run against a live server.**

- **List:** `GET /Sessions`; an API key sees every session. A session without `NowPlayingItem` is an idle client, not a stream.
- **State:** `PlayState.IsPaused`. There is no buffering state.
- **Bitrate:** `TranscodingInfo.Bitrate` when `PlayState.PlayMethod` is `Transcode` (bits per second, taken from the encoder's output bitrate). For direct play the item has **no** `Bitrate` field; the numbers are in `NowPlayingItem.MediaStreams[].BitRate`. The earlier implementation read the missing field and got 0.
- **Local or remote:** not reported. Only `RemoteEndPoint`, the client's address.
- **Websocket:** `/socket`. The key is accepted in the `Authorization: MediaBrowser Token="…"` header or as `ApiKey`. The `api_key` query argument works only while legacy authorization is enabled, which is the default up to 10.11 and **off by default in 12**.
- **Subscribing:** send `{"MessageType":"SessionsStart","Data":"0,1500"}`. The second number is the shortest gap in milliseconds between routine updates. The server then sends `Sessions` messages whose data is the same list as `GET /Sessions`: at once on a start, stop or session change, rate-limited for progress. Nothing is sent at the moment of subscribing, so the list is read once after connecting.
- **Keep-alive:** the client sends `{"MessageType":"KeepAlive"}`. The server asks for it after 45 s of silence and closes the connection at 60 s.
- **Versions:** on 10.9, the subscription requires an administrator user and has no API-key case, so an API-key connection receives nothing. From 10.10 an API key is accepted.
- **Own session:** an API-key websocket appears in the session list as a client with no user and nothing playing.
- **To check live:** which of the three ways of sending the key is accepted on a default Jellyfin 12; the keep-alive timings; the direct-play bitrate fields against a known file; how often `Sessions` arrives while a stream is paused.
