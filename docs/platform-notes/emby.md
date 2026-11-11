# Emby

Verified 2026-10-27 with live tests on Emby Server 4.10.2.

## `POST /emby/Library/Media/Updated`
- Every tested scenario (new episode, season pack, upgrade, delete, file rename, folder rename, burst of 20 files in 10 folders, new movie, deleted movie folder) became visible after about **90.4 s**: a fixed processing delay.
- The server configuration doesn't expose it as `LibraryMonitorDelay`.
- **Late visibility:** a path reported a few seconds before it existed was still picked up, because the delay outlasted the gap.
- **`UpdateType`:** autoscan sends `Created`.

## Item refresh is not a scan
- As on Jellyfin, `POST /emby/Items/{id}/Refresh` on the item of a deleted file does **not** remove it.

## Library management API
- `DELETE /emby/Library/VirtualFolders?name=` and `POST /emby/Library/VirtualFolders/Delete?Name=` both fail with HTTP 500. The cause is a null reference in `LibraryManager.RemoveVirtualFolder(Int64 id)`.
- **Delete by numeric id:** `POST /emby/Library/VirtualFolders/Delete?Id=<ItemId>&RefreshLibrary=false` (returns 204).
- **A library created on an empty folder** also showed 0 items afterwards. It wasn't investigated further. Treat it like Jellyfin and never create a library on an empty folder.

## Overlapping library locations
- If one library's location is nested inside another's, the folder appeared in the **inner** library only. That is the opposite of Jellyfin.
- **Implication:** the UI should warn about overlapping locations on Emby targets.

## Sessions
Baseline of 2026-11-11 from Emby's REST documentation, its JavaScript client and the earlier Autoplow implementation. **Not run against a live server.**

- **List:** `GET /Sessions` with `X-Emby-Token` or the `api_key` query argument. *Documented.*
- **State:** `PlayState.IsPaused`, and `PlayState.PlayMethod` (`Transcode`, `DirectStream`, `DirectPlay`). *Documented.*
- **Bitrate:** `NowPlayingItem.Bitrate` and `TranscodingInfo.Bitrate` exist. Their unit is not documented; the earlier implementation treated them as bits per second.
- **Local or remote:** not reported. Only `RemoteEndPoint`.
- **Websocket:** the earlier implementation connected to `/embywebsocket` with `api_key` and `deviceId`, sent `SessionsStart`, and re-read the session list on any session or playback message. Emby's own client uses the same path. **Emby's documentation describes none of these messages,** and no keep-alive.
- **To check live:** that `SessionsStart` is honoured and what arrives; whether a keep-alive is needed; the bitrate unit against a known file; `RemoteEndPoint` behind a reverse proxy.
