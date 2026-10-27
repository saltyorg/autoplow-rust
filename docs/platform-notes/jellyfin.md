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
