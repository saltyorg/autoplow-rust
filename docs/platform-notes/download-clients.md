# Download clients: SABnzbd, NZBGet, qBittorrent

Baseline of 2026-11-11 from documentation and source reading. **Nothing here was run against a live client.** Sources: SABnzbd's API documentation (4.5) and source at 3.7.2, 4.5.5 and 5.1.3; NZBGet's API documentation and `daemon/remote/XmlRpc.cpp` at 21.1, 24.8 and 26.3; qBittorrent's Web API wiki (4.1 and 5.0), its Web API changelog and `src/webui/api` at 4.1.0 through 5.3.0. The earlier Autoplow never drove download clients. cloudplow used pause and resume on SABnzbd and NZBGet with the calls below.

Each claim is marked **agreed** (documentation and source say the same), **source** (source only) or **differs** (they disagree; the source is followed).

## SABnzbd (3.7.2 and newer)
- **Pause and resume:** `GET /api?mode=pause` and `mode=resume`, with `apikey` and `output=json`. *Agreed.* Either call first cancels a timed resume the user set. *Source.*
- **Rights:** pause, resume, config and queue need the full API key; the NZB key is refused. `mode=version` needs no key, so it does not prove a key works. *Agreed.*
- **Reading state:** `mode=queue` gives `paused` (also true while SABnzbd pauses itself for post-processing), `pause_int` (time left on a timed pause) and `status`. *Source.*
- **Setting the limit:** `mode=config&name=speedlimit&value=V`. *Differs:* the documentation says a bare number is a percentage. In the source, a number from 1 to 100 (or with `%`) is a percentage of the configured line speed, and any larger bare number is **bytes per second**. `K` and `M` multiply by 1024 and 1024². `0` is unlimited.
- **Reading the limit:** `speedlimit_abs` in the queue output is bytes per second as text, `"0"` for unlimited. `speedlimit` is a percentage and is not comparable. *Agreed.*
- **Not kept across a restart:** a limit set this way is not written to SABnzbd's config. *Source.*
- **What changes state by itself:** its scheduler (pause, resume, speed limit), a timed pause running out, a full disk, and resuming when disk space returns. Nothing reports who made a change. *Source.*

## NZBGet (21.1 and newer, including the 24–26 releases)
- **Calls:** JSON-RPC by `POST` to `/jsonrpc`, with positional parameters. A changing call sent by `GET` is refused. *Source.*
- **Pause and resume:** `pausedownload` and `resumedownload`. Either cancels a scheduled resume. *Agreed.*
- **Rights:** the control and restricted users may pause, resume, set the rate and read status. The add-only user may not, though it may read the version. *Agreed.*
- **Setting the limit:** `rate(N)` with N in whole **KiB/s**; `0` is unlimited. *Agreed.*
- **Reading:** `status` gives `DownloadLimit` in **bytes per second** (a different scale from `rate`, as the documentation warns), `DownloadPaused`, `ServerStandBy`, `ResumeTime` and `QuotaReached`. `DownloadPaused` does not show a quota stop or a temporary pause. *Agreed.*
- **Ceiling:** the limit is a 32-bit number of bytes, so just under 2 GiB/s. *Source.*
- **What changes state by itself:** scheduler tasks for pause, resume and rate, and the scheduled-resume timer. Nothing reports who made a change. *Source.*

## qBittorrent (4.5.0 and newer)
- **Signing in:** `POST /api/v2/auth/login` sets a session cookie. Its name changed in 5.2.0, so a cookie jar is needed, never a fixed name. *Source.* From 5.2.0 an API key can be sent as a bearer token. *Agreed.*
- **Referer and Origin:** a request with neither header is accepted; one with a header that does not match the host is refused. *Agreed with the source; the wiki says to send one.*
- **Every changing call is a `POST`,** and success can be 200 or, from 5.2.0, 204. *Agreed.*
- **Setting a limit:** `transfer/setDownloadLimit` and `setUploadLimit` with `limit` in **bytes per second**; `0` is unlimited. The value is stored in whole KiB, rounded down. *Agreed for the unit; rounding from source.*
- **Reading a limit:** `transfer/downloadLimit` and `uploadLimit`, in bytes per second. *Agreed.*
- **Alternative-speed mode:** `transfer/speedLimitsMode` returns 1 or 0. **While it is on, the set calls change the alternative limits and the read calls return them.** *Source.* Its scheduler (`scheduler_enabled` in the preferences) switches the mode on a timetable.
- **All four limits at once (5.3.0 and newer):** `transfer/getSpeedLimits` and `setSpeedLimits` name the normal and alternative limits separately, whatever the mode. *Agreed.*
- **Preferences:** the wiki gives `dl_limit` and its siblings in KiB/s; the source and the wiki's own example give bytes per second. *Differs.*
- **Pausing:** the only way before 5.3.0 is stopping every torrent (`torrents/pause` in 4.x, `torrents/stop` in 5.x), which loses which torrents the user had stopped, and stops seeding. 5.3.0 adds `transfer/pauseSession` and `resumeSession`, which leave each torrent's state alone. *Agreed.*

## Units side by side
For a limit of 80 MiB/s (83 886 080 bytes per second):

| Client | Sent | Read back |
|---|---|---|
| SABnzbd | `value=83886080` | `speedlimit_abs` = `"83886080"` |
| NZBGet | `rate(81920)` | `DownloadLimit` = `83886080` |
| qBittorrent | `limit=83886080` | `downloadLimit` = `83886080` |

`0` means unlimited in all three, so a limit of zero can never be used to stop a client.

## To check live before each client is built
- **SABnzbd:** the limit round-trips with and without a configured line speed; `value=100` is read as a percentage; what a wrong key and an NZB key return; `paused` during post-processing; a pause call clears a user's timed pause; the limit after a restart.
- **NZBGet (21.x and 26.x):** `rate(81920)` reads back as 83 886 080; `GET` is refused; the restricted user works and the add-only user does not; whether pause and rate survive a restart.
- **qBittorrent (4.6, 5.1 and 5.3):** the limit round-trips and 102 500 reads back as 102 400; with alternative mode on, a set call changes the alternative limit; sign-in without Referer or Origin; cookie name and status codes per version; on 5.3, `setSpeedLimits` leaves the alternative limits unchanged and `pauseSession` keeps each torrent's state.
